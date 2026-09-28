import Foundation
import Testing
import UIKit
import PDFKit
@testable import Wochenkorb

@MainActor
private enum MatcherFixture {
    static let matcher = ProspectMatcher.loadBundled(bundle: Bundle(for: BundleToken.self))
}

@Suite("ProspectParser heuristics")
struct ProspectParserTests {

    // MARK: - Price / pack parsing on flat text snippets

    @Test("Finds price and pack size next to a product name")
    func priceAndPack() {
        let text = "Rispentomaten\n1,99 €\n500 g Schale"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.count == 1)
        #expect(offers[0].productText == "Rispentomaten")
        #expect(offers[0].price == 1.99)
        #expect(offers[0].packText == "500 g")
    }

    @Test("Handles a dot-decimal price and a multipack size")
    func dotPriceAndMultipack() {
        let text = "Joghurt\n0.89\n2 x 250 g"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.count == 1)
        #expect(offers[0].price == 0.89)
        #expect(offers[0].packText == "2 x 250 g")
    }

    @Test("Handles the '-.99' reduced-price notation")
    func dashPrice() {
        let text = "Bio Bananen\n-.99\nje kg"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.count == 1)
        #expect(offers[0].price == 0.99)
    }

    @Test("Handles the bare '.99' notation")
    func barePrice() {
        let text = "Gouda Scheiben\n.99\n150 g Packung"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.count == 1)
        #expect(offers[0].price == 0.99)
    }

    @Test("Detects an app/Kundenkarte-only marker nearby")
    func appOnlyMarker() {
        let text = "Kaffee\nnur mit REWE App\n2,99 €\n500 g"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.count == 1)
        #expect(offers[0].appOnly)
    }

    @Test("Skips a line with no usable product text")
    func skipsBareNumberOnly() {
        let text = "12\n1,99 €"
        let offers = ProspectParser.extract(from: text)
        #expect(offers.isEmpty)
    }

    // MARK: - Validity date guessing

    @Test("Parses 'Gültig vom dd.mm. bis dd.mm.'")
    func validityRangeVom() {
        let r = ProspectParser.guessValidityDates(in: "Gültig vom 29.09. bis 04.10.", referenceYear: 2026)
        #expect(r?.from == "2026-09-29")
        #expect(r?.to == "2026-10-04")
    }

    @Test("Parses 'Mo. 29.9. – Sa. 4.10.'")
    func validityRangeDash() {
        let r = ProspectParser.guessValidityDates(in: "Mo. 29.9. – Sa. 4.10.", referenceYear: 2026)
        #expect(r?.from == "2026-09-29")
        #expect(r?.to == "2026-10-04")
    }

    @Test("Parses the exact Edeka wording with an explicit end year")
    func validityRangeEdeka() {
        let r = ProspectParser.guessValidityDates(in: "28.09. – 02.10.26", referenceYear: 2026)
        #expect(r?.from == "2026-09-28")
        #expect(r?.to == "2026-10-02")
    }

    @Test("Falls back to a 6-day run for 'Gültig ab dd.mm.yyyy'")
    func validityFromOnly() {
        let r = ProspectParser.guessValidityDates(in: "40. Woche 2026. Gültig ab 28.09.2026", referenceYear: 2026)
        #expect(r?.from == "2026-09-28")
        #expect(r?.to == "2026-10-03")
    }

    // MARK: - Layout-aware extraction (positioned lines, as from a real prospectus PDF)

    @Test("Assigns descriptive lines to the nearest price below them in the same column")
    func layoutAwareTileAssembly() {
        // Mirrors the real Edeka layout: two stacked tiles in one column, where the second
        // tile's own "origin" line sits closer (in raw y) to the FIRST tile's price than to its
        // own - the extractor must still assign it to its own (second) tile.
        let lines: [ProspectParser.TextLine] = [
            .init(x: 94, y: 755, width: 45, height: 11, text: "Deutschland"),
            .init(x: 94, y: 746, width: 50, height: 11, text: "Mini Pak Choi"),
            .init(x: 111, y: 649, width: 60, height: 19, text: "300 g Schale"),
            .init(x: 107, y: 603, width: 44, height: 46, text: "1.49"),
            .init(x: 106, y: 599, width: 47, height: 10, text: "Aktions-Preis"),
            .init(x: 94, y: 582, width: 45, height: 11, text: "Deutschland"),
            .init(x: 94, y: 572, width: 34, height: 11, text: "Spitzkohl"),
            .init(x: 113, y: 477, width: 29, height: 20, text: "Stück"),
            .init(x: 107, y: 429, width: 44, height: 46, text: "1.11"),
            .init(x: 106, y: 425, width: 47, height: 10, text: "Aktions-Preis"),
        ]
        let offers = ProspectParser.extractFromLines(lines).sorted { $0.price < $1.price }
        #expect(offers.count == 2)
        #expect(offers[0].price == 1.11)
        #expect(offers[0].productText.contains("Spitzkohl"))
        #expect(!offers[0].productText.contains("Mini Pak Choi"))
        #expect(offers[1].price == 1.49)
        #expect(offers[1].productText.contains("Mini Pak Choi"))
    }

    @Test("Merges a price split into two fragments ('1.' + '49') into one price")
    func mergesSplitPriceFragments() {
        let lines: [ProspectParser.TextLine] = [
            .init(x: 456, y: 649, width: 70, height: 19, text: "400 g Packung"),
            .init(x: 445, y: 429, width: 28, height: 46, text: "1."),
            .init(x: 466, y: 444, width: 22, height: 27, text: "49"),
        ]
        let merged = ProspectParser.mergeSplitPriceFragments(lines)
        #expect(merged.contains { $0.text == "1.49" })
    }

    @Test("Never uses a starred (old/struck-through) price as an anchor")
    func ignoresOldPrice() {
        let lines: [ProspectParser.TextLine] = [
            .init(x: 20, y: 200, width: 60, height: 10, text: "Rapsöl 750 ml"),
            .init(x: 20, y: 150, width: 40, height: 20, text: "1.69*"),
            .init(x: 20, y: 100, width: 40, height: 20, text: "1.39"),
        ]
        let offers = ProspectParser.extractFromLines(lines)
        #expect(offers.count == 1)
        #expect(offers[0].price == 1.39)
    }
}

@Suite("ProspectMatcher")
struct ProspectMatcherTests {
    @MainActor
    private var matcher: ProspectMatcher { MatcherFixture.matcher }

    @Test("Matches a plain ingredient name")
    @MainActor func matchesSpaghetti() {
        #expect(matcher.matchIngredient("REWE Beste Wahl Spaghetti No. 3") == "spaghetti")
    }

    @Test("'Butterkekse' does not match 'Butter'")
    @MainActor func excludesButterkekse() {
        #expect(matcher.matchIngredient("Leibniz Butterkekse") != "butter")
    }

    @Test("'Eier-Nudeln' does not match 'Eier'")
    @MainActor func excludesEiernudeln() {
        #expect(matcher.matchIngredient("Birkel Eier-Nudeln") != "eier")
    }

    @Test("'Milchreis' does not match 'Reis'")
    @MainActor func excludesMilchreis() {
        #expect(matcher.matchIngredient("Oetker Milchreis") != "reis")
    }

    @Test("Converts a single pack size in grams")
    @MainActor func parsesSingleGrams() {
        let parsed = matcher.parsePackSize("500 g Packung", ingredientUnit: "g")
        #expect(parsed?.quantity == 500)
    }

    @Test("Converts kg to the ingredient's gram unit")
    @MainActor func parsesKilograms() {
        let parsed = matcher.parsePackSize("1,5 kg Sack", ingredientUnit: "g")
        #expect(parsed?.quantity == 1500)
    }

    @Test("Converts a multipack to total grams")
    @MainActor func parsesMultipack() {
        let parsed = matcher.parsePackSize("4 x 125 g Becher", ingredientUnit: "g")
        #expect(parsed?.quantity == 500)
    }

    @Test("Converts millilitres/litres for a ml ingredient")
    @MainActor func parsesLiters() {
        let parsed = matcher.parsePackSize("1 l Flasche", ingredientUnit: "ml")
        #expect(parsed?.quantity == 1000)
    }

    @Test("Bare 'Stück' implies a quantity of 1 for a Stk ingredient")
    @MainActor func parsesBareStueck() {
        let parsed = matcher.parsePackSize("Salatgurke, Stück", ingredientUnit: "Stk")
        #expect(parsed?.quantity == 1)
    }

    @Test("A gram pack size does not convert for an ml ingredient")
    @MainActor func rejectsUnitMismatch() {
        #expect(matcher.parsePackSize("500 g Packung", ingredientUnit: "ml") == nil)
    }
}

@Suite("Imported-offer merge preference")
struct OfferMergeTests {
    private static func offer(validFrom: String, validTo: String, product: String = "Testware") -> StoreOffer {
        StoreOffer(name: nil, market: nil, validFrom: validFrom, validTo: validTo, status: "pdf", source: "PDF-Import test.pdf",
                   items: ["milch": OfferItem(product: product, price: 0.79, pk: 1000, label: "1 l", note: nil, app: nil)])
    }

    private static let downloaded = OffersFile(
        kw: "40", stand: "2026-09-28", ort: nil, hinweis: nil,
        stores: ["rewe": StoreOffer(name: "Rewe", market: nil, validFrom: "2026-09-28", validTo: "2026-10-03", status: "ok", source: nil,
                                     items: ["milch": OfferItem(product: "Downloadmilch", price: 1.09, pk: 1000, label: "1 l", note: nil, app: nil)])]
    )

    @MainActor
    @Test("A still-valid import wins over the downloaded offer for that store")
    func validImportWins() {
        let imported = ["rewe": Self.offer(validFrom: "2026-09-28", validTo: "2026-10-03")]
        let merged = AppStore.merge(downloaded: Self.downloaded, imported: imported, today: "2026-09-30")
        #expect(merged?.stores["rewe"]?.items["milch"]?.product == "Testware")
    }

    @MainActor
    @Test("An expired import is ignored, the download is used instead")
    func expiredImportIgnored() {
        let imported = ["rewe": Self.offer(validFrom: "2026-09-14", validTo: "2026-09-19")]
        let merged = AppStore.merge(downloaded: Self.downloaded, imported: imported, today: "2026-09-30")
        #expect(merged?.stores["rewe"]?.items["milch"]?.product == "Downloadmilch")
    }

    @MainActor
    @Test("An import for a store with no download still shows up")
    func importOnlyStore() {
        let imported = ["edeka": Self.offer(validFrom: "2026-09-28", validTo: "2026-10-03")]
        let merged = AppStore.merge(downloaded: Self.downloaded, imported: imported, today: "2026-09-30")
        #expect(merged?.stores["edeka"]?.items["milch"]?.product == "Testware")
        #expect(merged?.stores["rewe"]?.items["milch"]?.product == "Downloadmilch")
    }
}

@Suite("End-to-end: sample PDF through the heuristic-only pipeline")
struct ProspectImporterEndToEndTests {
    /// Draws a small, single-column, text-based PDF (no FoundationModels involved) with a
    /// handful of offers and runs it through the whole import pipeline.
    @MainActor
    private func makeSamplePDF() -> URL {
        let pageBounds = CGRect(x: 0, y: 0, width: 400, height: 700)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample-prospekt-\(UUID().uuidString).pdf")
        let font = UIFont.systemFont(ofSize: 14)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            var y: CGFloat = 20
            func line(_ s: String) {
                s.draw(at: CGPoint(x: 20, y: y), withAttributes: attrs)
                y += 22
            }
            line("Gültig vom 29.09. bis 04.10.")
            y += 10
            line("Gehackte Tomaten")
            line("1.99")
            line("400 g Dose")
            y += 10
            line("Spaghetti No. 3")
            line("0.89")
            line("500 g Packung")
            y += 10
            line("Leibniz Butterkekse")
            line("1.49")
            line("200 g Packung")
        }
        return url
    }

    @MainActor
    @Test("Extracts and matches offers from a generated sample PDF without FoundationModels")
    func endToEndHeuristicPath() async {
        let url = makeSamplePDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = ProspectImporter(matcher: MatcherFixture.matcher)
        let result = await importer.run(pdfURL: url)

        let byIngredient = Dictionary(uniqueKeysWithValues: result.offers.map { ($0.ingredientID, $0) })
        #expect(byIngredient["tomdose"]?.price == 1.99)
        #expect(byIngredient["tomdose"]?.pk == 400)
        #expect(byIngredient["spaghetti"]?.price == 0.89)
        #expect(byIngredient["spaghetti"]?.pk == 500)
        // "Butterkekse" must never be matched onto the "Butter" ingredient.
        #expect(byIngredient["butter"] == nil)

        #expect(result.dateRange?.from == "2026-09-29")
        #expect(result.dateRange?.to == "2026-10-04")
    }
}

private final class BundleToken {}
