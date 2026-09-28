import Foundation

/// Pure port of scraper/matcher.py: maps prospectus product text onto a planner ingredient id
/// using the hand-curated match/exclude keyword lists in Resources/ingredients_match.json, and
/// parses pack sizes ("500 g", "2 x 250 g", "1 kg", "6 Stück", ...) into the ingredient's own
/// unit (g/ml/Stk). No UI, fully testable.
nonisolated struct ProspectMatcher {
    let table: IngredientMatchTable

    init(table: IngredientMatchTable) {
        self.table = table
    }

    static func loadBundled(bundle: Bundle = .main) -> ProspectMatcher {
        guard let url = bundle.url(forResource: "ingredients_match", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(IngredientMatchTable.self, from: data) else {
            fatalError("Wochenkorb: ingredients_match.json fehlt oder ist beschädigt")
        }
        return ProspectMatcher(table: table)
    }

    // MARK: - Ingredient matching

    private static func fold(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True if `keyword` occurs in `text` as a whole word/phrase (case-insensitive), mirroring
    /// matcher.py's `_word_boundary_hit` (German-aware: umlauts/ß don't count as boundaries).
    private static func wordBoundaryHit(_ keyword: String, in text: String) -> Bool {
        guard !keyword.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = "(?<![a-zäöüß0-9])" + escaped + "(?![a-zäöüß0-9])"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Returns the ingredient id whose keywords best match `title`, or nil.
    /// Excludes win; the longest matching keyword wins among remaining candidates
    /// (e.g. "süßkartoffel" before "kartoffeln").
    func matchIngredient(_ title: String) -> String? {
        let text = Self.fold(title)
        var bestID: String?
        var bestLen = -1
        for (iid, ing) in table {
            let excluded = ing.exclude.contains { Self.wordBoundaryHit(Self.fold($0), in: text) }
            if excluded { continue }
            for kw in ing.match {
                let kwf = Self.fold(kw)
                if Self.wordBoundaryHit(kwf, in: text), kwf.count > bestLen {
                    bestLen = kwf.count
                    bestID = iid
                }
            }
        }
        return bestID
    }

    // MARK: - Pack size parsing

    struct ParsedPack {
        /// Quantity converted into the ingredient's own unit (g/ml/Stk).
        let quantity: Double
        /// Human-readable label as found in the text, e.g. "500 g", "2 x 250 g", "6 Stück".
        let label: String
    }

    private static let numPattern = #"(\d+(?:[.,]\d+)?)"#
    private static let sep = #"[\s-]*"#

    private static let multipackRegex = try! NSRegularExpression(
        pattern: numPattern + sep + "x" + sep + numPattern + sep + "(kg|g|ml|l)\\b",
        options: [.caseInsensitive])
    private static let singleRegex = try! NSRegularExpression(
        pattern: numPattern + sep + "(kg|g|ml|l)\\b",
        options: [.caseInsensitive])
    private static let stkRegex = try! NSRegularExpression(
        pattern: numPattern + sep + #"(st(?:ü|u)ck|stk)\b"#,
        options: [.caseInsensitive])
    private static let bareStkRegex = try! NSRegularExpression(
        pattern: #"\bst(?:ü|u)ck\b"#,
        options: [.caseInsensitive])

    private static let unitFactor: [String: Double] = ["kg": 1000, "g": 1, "l": 1000, "ml": 1]

    private static func number(from text: String, group: Int, in match: NSTextCheckingResult, source: String) -> Double? {
        guard let range = Range(match.range(at: group), in: source) else { return nil }
        return Double(source[range].replacingOccurrences(of: ",", with: "."))
    }

    private static func string(from source: String, group: Int, in match: NSTextCheckingResult) -> String? {
        guard let range = Range(match.range(at: group), in: source) else { return nil }
        return String(source[range])
    }

    /// Tries to find a pack size in `text` and convert it to `ingredientUnit` (g|ml|Stk|Zehe|Bund).
    /// Returns nil if not parseable / not convertible into that unit.
    func parsePackSize(_ text: String, ingredientUnit: String) -> ParsedPack? {
        let t = text
        let full = NSRange(t.startIndex..<t.endIndex, in: t)

        if let m = Self.multipackRegex.firstMatch(in: t, options: [], range: full) {
            guard let n = Self.number(from: t, group: 1, in: m, source: t),
                  let size = Self.number(from: t, group: 2, in: m, source: t),
                  let unit = Self.string(from: t, group: 3, in: m)?.lowercased() else { return nil }
            let total = n * size
            if ["kg", "g"].contains(unit), ingredientUnit == "g" {
                return ParsedPack(quantity: total * (Self.unitFactor[unit] ?? 1), label: "\(Self.fmt(n)) x \(Self.fmt(size)) \(unit)")
            }
            if ["l", "ml"].contains(unit), ingredientUnit == "ml" {
                return ParsedPack(quantity: total * (Self.unitFactor[unit] ?? 1), label: "\(Self.fmt(n)) x \(Self.fmt(size)) \(unit)")
            }
            return nil
        }

        if let m = Self.singleRegex.firstMatch(in: t, options: [], range: full) {
            guard let n = Self.number(from: t, group: 1, in: m, source: t),
                  let unit = Self.string(from: t, group: 2, in: m)?.lowercased() else { return nil }
            if ["kg", "g"].contains(unit), ingredientUnit == "g" {
                return ParsedPack(quantity: n * (Self.unitFactor[unit] ?? 1), label: "\(Self.fmt(n)) \(unit)")
            }
            if ["l", "ml"].contains(unit), ingredientUnit == "ml" {
                return ParsedPack(quantity: n * (Self.unitFactor[unit] ?? 1), label: "\(Self.fmt(n)) \(unit)")
            }
            return nil
        }

        if let m = Self.stkRegex.firstMatch(in: t, options: [], range: full), ingredientUnit == "Stk" {
            guard let n = Self.number(from: t, group: 1, in: m, source: t) else { return nil }
            return ParsedPack(quantity: n, label: "\(Self.fmt(n)) Stück")
        }

        if ingredientUnit == "Stk", Self.bareStkRegex.firstMatch(in: t, options: [], range: full) != nil {
            return ParsedPack(quantity: 1, label: "1 Stück")
        }

        return nil
    }

    private static func fmt(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(n)
    }

    /// Price per gram/ml/Stück - used to pick the cheapest offer per ingredient.
    static func pricePerBaseUnit(price: Double, pk: Double) -> Double {
        pk <= 0 ? .infinity : price / pk
    }
}
