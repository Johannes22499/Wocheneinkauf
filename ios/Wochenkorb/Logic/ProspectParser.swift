import Foundation

/// Heuristic, LLM-free extraction of offer candidates from prospectus page text: finds lines
/// with a price ("1.99", "1,99 €", "-.99", ".99") near product text and an optional pack size
/// ("250 g", "1 kg", "2 x 250 g", "500-g-Packung", "je 1 l", "Stück"). This is the always-on
/// fallback used when FoundationModels is unavailable or fails on a page/chunk. Pure, no UI,
/// fully testable.
nonisolated enum ProspectParser {
    struct RawOffer: Equatable {
        var productText: String
        var price: Double
        /// Raw pack-size substring as found in the text (e.g. "500 g", "2 x 250 g"), or nil.
        var packText: String?
        var appOnly: Bool
    }

    // Full price with leading digits: "1.99", "1,99 €", "12,49€"
    private static let fullPriceRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.,])(\d{1,3})[.,](\d{2})\s?€?(?!\d)"#)
    // Reduced price shown as "-.99" (cents only, common for < 1 €)
    private static let dashPriceRegex = try! NSRegularExpression(
        pattern: #"-[.,](\d{2})\s?€?(?!\d)"#)
    // Bare ".99" not preceded by a digit (isolated on its own, e.g. superscript cents)
    private static let barePriceRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)\.(\d{2})\s?€?(?!\d)"#)

    private static let packRegex = try! NSRegularExpression(
        pattern: #"\d+(?:[.,]\d+)?[\s-]*x[\s-]*\d+(?:[.,]\d+)?[\s-]*(kg|g|ml|l)\b|\d+(?:[.,]\d+)?[\s-]*(kg|g|ml|l)\b|\d+(?:[.,]\d+)?[\s-]*(st(?:ü|u)ck|stk)\b"#,
        options: [.caseInsensitive])

    private static let appMarkerRegex = try! NSRegularExpression(
        pattern: #"\b(app|kundenkarte|payback|bonuskarte|deutschlandcard)\b"#,
        options: [.caseInsensitive])

    /// Runs the heuristic over one page/chunk of prospectus text.
    static func extract(from pageText: String) -> [RawOffer] {
        let rawLines = pageText.components(separatedBy: .newlines)
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [RawOffer] = []

        for (i, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            guard let (price, priceRange) = firstPrice(in: line) else { continue }

            var product = removing(priceRange, from: line)
            product = cleanProduct(product)
            if product.count < 3, i > 0 {
                // Price-only line (common in prospectus dumps): product name is the line above.
                let above = cleanProduct(lines[i - 1])
                if above.count >= 3 { product = above }
            }
            guard product.count >= 3 else { continue }

            let neighborhood = [i > 0 ? lines[i - 1] : "", line, i + 1 < lines.count ? lines[i + 1] : ""].joined(separator: " ")
            let packText = firstPackText(in: neighborhood)
            let appOnly = appMarkerRegex.firstMatch(in: neighborhood, range: NSRange(neighborhood.startIndex..<neighborhood.endIndex, in: neighborhood)) != nil

            out.append(RawOffer(productText: product, price: price, packText: packText, appOnly: appOnly))
        }
        return out
    }

    private static func firstPrice(in line: String) -> (Double, Range<String.Index>)? {
        let full = NSRange(line.startIndex..<line.endIndex, in: line)
        if let m = fullPriceRegex.firstMatch(in: line, range: full),
           let euroR = Range(m.range(at: 1), in: line), let centR = Range(m.range(at: 2), in: line),
           let euro = Double(line[euroR]), let cent = Double(line[centR]),
           let whole = Range(m.range, in: line) {
            return (Self.centsPrice(euro, cent), whole)
        }
        if let m = dashPriceRegex.firstMatch(in: line, range: full),
           let centR = Range(m.range(at: 1), in: line), let cent = Double(line[centR]),
           let whole = Range(m.range, in: line) {
            return (Self.centsPrice(0, cent), whole)
        }
        if let m = barePriceRegex.firstMatch(in: line, range: full),
           let centR = Range(m.range(at: 1), in: line), let cent = Double(line[centR]),
           let whole = Range(m.range, in: line) {
            return (Self.centsPrice(0, cent), whole)
        }
        return nil
    }

    private static func firstPackText(in text: String) -> String? {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = packRegex.firstMatch(in: text, range: full), let r = Range(m.range, in: text) else { return nil }
        return String(text[r])
    }

    /// Combines a euro and a cent part into a price without the float drift that
    /// `euro + cent / 100` can introduce (e.g. 1.0 + 39.0/100.0 rounding differently than the
    /// single division 139.0/100.0), which would otherwise make `price == 1.39` fail.
    private static func centsPrice(_ euro: Double, _ cent: Double) -> Double {
        (euro * 100 + cent).rounded() / 100
    }

    private static func removing(_ range: Range<String.Index>, from line: String) -> String {
        var s = line
        s.removeSubrange(range)
        return s
    }

    private static func cleanProduct(_ s: String) -> String {
        var t = s
        let full = NSRange(t.startIndex..<t.endIndex, in: t)
        t = oldPriceSuffixRegex.stringByReplacingMatches(in: t, range: full, withTemplate: " ")
        t = t.replacingOccurrences(of: "€", with: " ")
        t = t.replacingOccurrences(of: #"[*•·]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " -.,;:"))
    }

    // MARK: - Validity dates ("Gültig vom 29.09. bis 04.10." / "Mo. 29.9. – Sa. 4.10.")

    // Allows an optional short weekday abbreviation ("Sa.") between the separator and the
    // second date, as in "Mo. 29.9. – Sa. 4.10.".
    private static let dateRangeRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})\.(\d{1,2})\.(\d{4})?\s*(?:bis|[-–])\s*(?:[A-Za-zÄÖÜäöüß]{2,3}\.\s*)?(\d{1,2})\.(\d{1,2})\.(\d{4})?"#)
    // "Gültig ab 28.09.2026" (Rewe): only a start date, no explicit end - assume a Mon-Sat week.
    private static let validFromOnlyRegex = try! NSRegularExpression(
        pattern: #"g[üu]ltig\s+ab\s+(\d{1,2})\.(\d{1,2})\.(\d{4})?"#, options: [.caseInsensitive])

    /// Finds a "dd.mm. bis dd.mm." (or "–") validity range in `text` and returns it as
    /// "yyyy-MM-dd" strings, using `referenceYear` for whichever side omits a year and rolling
    /// the end date into the next year if its month precedes the start month. Falls back to
    /// "Gültig ab dd.mm.yyyy" (assuming a 6-day Mon-Sat run) when no explicit range is found.
    static func guessValidityDates(in text: String, referenceYear: Int) -> (from: String, to: String)? {
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        if let m = dateRangeRegex.firstMatch(in: text, range: full) {
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
            if let d1s = group(1), let mo1s = group(2), let d2s = group(4), let mo2s = group(5),
               let day1 = Int(d1s), let month1 = Int(mo1s), let day2 = Int(d2s), let month2 = Int(mo2s),
               (1...12).contains(month1), (1...12).contains(month2), (1...31).contains(day1), (1...31).contains(day2) {
                let year1 = group(3).flatMap(Int.init) ?? referenceYear
                var year2 = group(6).flatMap(Int.init) ?? referenceYear
                if month2 < month1 { year2 += 1 }
                return (String(format: "%04d-%02d-%02d", year1, month1, day1), String(format: "%04d-%02d-%02d", year2, month2, day2))
            }
        }
        if let m = validFromOnlyRegex.firstMatch(in: text, range: full) {
            func group(_ i: Int) -> String? {
                guard let r = Range(m.range(at: i), in: text) else { return nil }
                return String(text[r])
            }
            if let d1s = group(1), let mo1s = group(2), let day1 = Int(d1s), let month1 = Int(mo1s),
               (1...12).contains(month1), (1...31).contains(day1) {
                let year1 = group(3).flatMap(Int.init) ?? referenceYear
                var comps = DateComponents(year: year1, month: month1, day: day1)
                let cal = Calendar(identifier: .gregorian)
                guard let start = cal.date(from: comps), let end = cal.date(byAdding: .day, value: 5, to: start) else { return nil }
                comps = cal.dateComponents([.year, .month, .day], from: end)
                return (String(format: "%04d-%02d-%02d", year1, month1, day1),
                        String(format: "%04d-%02d-%02d", comps.year ?? year1, comps.month ?? month1, comps.day ?? day1))
            }
        }
        return nil
    }

    // MARK: - Layout-aware extraction (real prospectus PDFs: PDFKit line boxes)

    /// One line of text with its position on the page, as reported by
    /// `PDFPage.selection(for:).selectionsByLine()`. Decoupled from PDFKit so this stays
    /// pure/testable; `ProspectImporter` is the only place that constructs these from a PDF.
    struct TextLine: Equatable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let text: String
    }

    /// Lines that are pure page furniture, never part of a product's name/description.
    private static let noiseLines: Set<String> = [
        "aktion", "aktions-preis", "knaller", "bonus", "bonus bauer", "angebaut von",
    ]
    private static let originLineRegex = try! NSRegularExpression(pattern: #"^aus\s+[a-zäöüß.\-]+$"#, options: [.caseInsensitive])
    private static let grundpreisLineRegex = try! NSRegularExpression(pattern: #"grundpreis|^\(.*=.*\)$"#, options: [.caseInsensitive])
    /// A line that is *only* a price, e.g. "1.49", "0.89", or "1.69*" for an old/reference price.
    private static let priceOnlyRegex = try! NSRegularExpression(pattern: #"^(\d{1,3})\.(\d{2})(\*)?$"#)
    private static let intFragmentRegex = try! NSRegularExpression(pattern: #"^(\d{1,2})\.$"#)
    private static let centFragmentRegex = try! NSRegularExpression(pattern: #"^(\d{2})$"#)

    private static let bareDateRangeRegex = try! NSRegularExpression(pattern: #"^\d{1,2}\.\d{1,2}\.\s*[-–]\s*\d{1,2}\.\d{1,2}\.\d{2,4}$"#)

    private static func isNoise(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if noiseLines.contains(t.lowercased()) { return true }
        let full = NSRange(t.startIndex..<t.endIndex, in: t)
        if originLineRegex.firstMatch(in: t, range: full) != nil { return true }
        if grundpreisLineRegex.firstMatch(in: t, range: full) != nil { return true }
        if bareDateRangeRegex.firstMatch(in: t, range: full) != nil { return true }
        return false
    }

    private static let oldPriceSuffixRegex = try! NSRegularExpression(pattern: #"\bstatt\s+\d{1,3}[.,]\d{2}\*?"#, options: [.caseInsensitive])

    /// Real prospectus PDFs sometimes render a price as two separate text runs, a big euro
    /// digit ("1.") and a smaller superscript cents part ("49"), positioned right next to each
    /// other. Detects horizontally-adjacent, vertically-overlapping fragment pairs and merges
    /// them into one "1.49" line so the rest of the pipeline sees a normal price.
    static func mergeSplitPriceFragments(_ lines: [TextLine]) -> [TextLine] {
        var used = Set<Int>()
        var out: [TextLine] = []
        for (i, line) in lines.enumerated() {
            guard !used.contains(i) else { continue }
            let t = line.text.trimmingCharacters(in: .whitespaces)
            let fullT = NSRange(t.startIndex..<t.endIndex, in: t)
            guard let intMatch = intFragmentRegex.firstMatch(in: t, range: fullT), let intRange = Range(intMatch.range(at: 1), in: t) else {
                out.append(line)
                continue
            }
            // Look for a "NN" fragment close to the right and vertically overlapping.
            var partner: Int?
            for (j, other) in lines.enumerated() where j != i && !used.contains(j) {
                let ot = other.text.trimmingCharacters(in: .whitespaces)
                let fullO = NSRange(ot.startIndex..<ot.endIndex, in: ot)
                guard centFragmentRegex.firstMatch(in: ot, range: fullO) != nil else { continue }
                let dx = other.x - (line.x + line.width)
                let verticalOverlap = min(line.y + line.height, other.y + other.height) - max(line.y, other.y)
                if dx > -15, dx < 40, verticalOverlap > 0 {
                    partner = j
                    break
                }
            }
            if let j = partner {
                used.insert(j)
                let merged = TextLine(x: line.x, y: line.y, width: line.width, height: line.height, text: "\(t[intRange]).\(lines[j].text.trimmingCharacters(in: .whitespaces))")
                out.append(merged)
            } else {
                out.append(line)
            }
        }
        return out
    }

    private struct Anchor { let index: Int; let x: Double; let y: Double; let price: Double }

    /// Groups a page's positioned text lines into per-offer tiles by assigning every
    /// descriptive line to the nearest price anchor *below* it in a similar horizontal band
    /// (product info is printed above its price in both Rewe's and Edeka's prospectus layouts).
    /// Old/struck-through prices ("1.69*") are never used as an anchor.
    private static func assembleTiles(_ rawLines: [TextLine]) -> [(price: Double, anchorY: Double, lines: [TextLine])] {
        let lines = mergeSplitPriceFragments(rawLines)

        var anchors: [Anchor] = []
        for (i, line) in lines.enumerated() {
            let t = line.text.trimmingCharacters(in: .whitespaces)
            let full = NSRange(t.startIndex..<t.endIndex, in: t)
            guard let m = priceOnlyRegex.firstMatch(in: t, range: full) else { continue }
            guard Range(m.range(at: 3), in: t) == nil else { continue } // "*" -> old price, not an anchor
            guard let euroR = Range(m.range(at: 1), in: t), let centR = Range(m.range(at: 2), in: t),
                  let euro = Double(t[euroR]), let cent = Double(t[centR]) else { continue }
            anchors.append(Anchor(index: i, x: line.x, y: line.y, price: Self.centsPrice(euro, cent)))
        }
        guard !anchors.isEmpty else { return [] }

        let maxDX = 90.0
        let maxDY = 210.0 // a single card is well under this tall; caps bleed from page headers etc.
        let yTolerance = 8.0
        var tiles: [Int: [TextLine]] = [:] // anchor index -> lines
        for (i, line) in lines.enumerated() {
            if anchors.contains(where: { $0.index == i }) { continue }
            let t = line.text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !isNoise(t) else { continue }
            var best: Anchor?
            var bestDist = Double.greatestFiniteMagnitude
            for a in anchors {
                let dy = line.y - a.y
                guard dy >= -yTolerance, dy <= maxDY, abs(a.x - line.x) <= maxDX else { continue }
                let dist = dy + abs(a.x - line.x) * 0.2
                if dist < bestDist {
                    bestDist = dist
                    best = a
                }
            }
            if let best {
                tiles[best.index, default: []].append(line)
            }
        }

        return anchors.compactMap { a in
            guard let tileLines = tiles[a.index], !tileLines.isEmpty else { return nil }
            return (a.price, a.y, tileLines)
        }
    }

    /// Extracts offers from a page's positioned text lines (see `assembleTiles`), reading off
    /// product text / pack size / app-only markers per assembled tile. Pure, testable without
    /// PDFKit.
    static func extractFromLines(_ rawLines: [TextLine]) -> [RawOffer] {
        assembleTiles(rawLines).compactMap { price, anchorY, tileLines in
            let product = cleanProduct(tileLines.sorted { $0.y > $1.y }.map(\.text).joined(separator: " "))
            guard product.count >= 3 else { return nil }
            // Search for the pack size starting with the lines physically closest to the price,
            // since a tile occasionally accumulates an unrelated neighbor's text too.
            let byProximity = tileLines.sorted { abs($0.y - anchorY) < abs($1.y - anchorY) }
            let packText = byProximity.lazy.compactMap { firstPackText(in: $0.text) }.first
                ?? firstPackText(in: byProximity.map(\.text).joined(separator: " "))
            let joined = tileLines.map(\.text).joined(separator: " ")
            let full = NSRange(joined.startIndex..<joined.endIndex, in: joined)
            let appOnly = appMarkerRegex.firstMatch(in: joined, range: full) != nil
            return RawOffer(productText: product, price: price, packText: packText, appOnly: appOnly)
        }
    }

    /// Renders each assembled tile as one text block (product lines + its price), for feeding
    /// FoundationModels a spatially-grouped prompt instead of the page's jumbled raw text.
    static func tileTexts(_ rawLines: [TextLine]) -> [String] {
        assembleTiles(rawLines).map { price, _, tileLines in
            let text = tileLines.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n")
            return text + "\nPreis: \(String(format: "%.2f", price)) €"
        }
    }
}
