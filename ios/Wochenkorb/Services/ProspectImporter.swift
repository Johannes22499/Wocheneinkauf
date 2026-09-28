import Foundation
import PDFKit
import Vision
import UIKit
import FoundationModels

/// Extracts offers from a prospectus PDF the user hands to the app (share sheet or
/// file picker): per-page text via PDFKit, OCR fallback via Vision for image-only pages,
/// on-device FoundationModels extraction when Apple Intelligence is available, and a
/// regex heuristic as the always-on fallback. Matches results onto planner ingredients
/// via `ProspectMatcher` and keeps the cheapest offer per ingredient. Fully on-device,
/// no network.
nonisolated final class ProspectImporter: Sendable {
    /// One offer found on a page, before it's matched to an ingredient.
    struct RawOfferOnPage {
        let productText: String
        let price: Double
        let packText: String?
        let appOnly: Bool
    }

    private let matcher: ProspectMatcher

    init(matcher: ProspectMatcher = .loadBundled()) {
        self.matcher = matcher
    }

    // MARK: - Page text extraction (PDFKit, OCR fallback)

    /// One page's content: `lines` are the positioned text runs used for the layout-aware
    /// heuristic (empty when only OCR'd flat text is available), `flatText` is always set.
    struct PageContent {
        let lines: [ProspectParser.TextLine]
        let flatText: String
    }

    /// Pages with less embedded text than this are treated as image-only and OCR'd.
    private let minEmbeddedTextLength = 40

    func pageContents(from pdfURL: URL) async -> [PageContent] {
        guard let doc = PDFDocument(url: pdfURL) else { return [] }
        var out: [PageContent] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if embedded.count >= minEmbeddedTextLength {
                out.append(PageContent(lines: textLines(from: page), flatText: embedded))
            } else if let ocrText = await ocr(page: page), !ocrText.isEmpty {
                out.append(PageContent(lines: [], flatText: ocrText))
            } else {
                out.append(PageContent(lines: [], flatText: embedded))
            }
        }
        return out
    }

    /// Real prospectus PDFs jumble `page.string`'s reading order (product name, pack size and
    /// price aren't adjacent), so the layout-aware heuristic works off each line's own bounding
    /// box instead - see `ProspectParser.extractFromLines`.
    private func textLines(from page: PDFPage) -> [ProspectParser.TextLine] {
        let bounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: bounds) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            let b = line.bounds(for: page)
            let s = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            return ProspectParser.TextLine(x: Double(b.origin.x), y: Double(b.origin.y), width: Double(b.width), height: Double(b.height), text: s)
        }
    }

    private func ocr(page: PDFPage) async -> String? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - FoundationModels extraction (best effort, per page)

    @Generable
    struct AIOffer: Equatable {
        @Guide(description: "Produktname aus dem Prospekt, kurz, ohne Werbetext")
        var product: String
        @Guide(description: "Preis in Euro als Dezimalzahl, z.B. 1.99")
        var price: Double
        @Guide(description: "Packungsgröße als Zahl, z.B. 500 für 500 g oder 1 für 1 Stück")
        var packAmount: Double
        @Guide(description: "Einheit der Packungsgröße: g, kg, ml, l oder Stück")
        var packUnit: String
        @Guide(description: "true, wenn der Preis nur mit App oder Kundenkarte gilt, sonst false")
        var appOnly: Bool
    }

    @Generable
    struct AIPage: Equatable {
        @Guide(description: "Alle Lebensmittel-Angebote mit klar erkennbarem Preis auf dieser Prospektseite")
        var offers: [AIOffer]
    }

    /// Returns nil (never an empty-vs-nil ambiguity issue since callers only care about
    /// "did the model answer at all") whenever the session fails for this page — the caller
    /// then falls back to the regex heuristic for that page. Covers guardrail refusals,
    /// context-window overflow, an unavailable model, and decoding failures alike.
    private func aiExtract(session: LanguageModelSession, pageText: String) async -> [RawOfferOnPage]? {
        guard !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let prompt = "Prospektseite:\n\n\(pageText)"
        do {
            let response = try await session.respond(to: prompt, generating: AIPage.self)
            return response.content.offers.map {
                RawOfferOnPage(
                    productText: $0.product,
                    price: $0.price,
                    packText: "\(Self.fmt($0.packAmount)) \($0.packUnit)",
                    appOnly: $0.appOnly
                )
            }
        } catch {
            // Guardrail violation, context window too large, model unavailable, malformed
            // output, ... - all treated the same: skip AI for this page, use the heuristic.
            return nil
        }
    }

    // MARK: - Orchestration

    struct ImportResult {
        var offers: [ExtractedOffer]
        var dateRange: (from: String, to: String)?
    }

    @concurrent
    func run(pdfURL: URL, progress: @escaping @MainActor (String) -> Void = { _ in }) async -> ImportResult {
        await progress("Text wird gelesen …")
        let pages = await pageContents(from: pdfURL)

        let referenceYear = Calendar.current.component(.year, from: Date())
        // The validity note is always near the front; scanning the whole PDF risks matching an
        // unrelated "dd.mm. - dd.mm." on a recipe or coupon page deep inside.
        let dateRange = pages.prefix(3).compactMap { ProspectParser.guessValidityDates(in: $0.flatText, referenceYear: referenceYear) }.first

        let session: LanguageModelSession?
        if SystemLanguageModel.default.availability == .available {
            session = LanguageModelSession(instructions: """
                Du bekommst einzelne Angebotskacheln aus einem deutschen Supermarkt-Prospekt (z. B. Rewe, \
                Edeka, Lidl, Penny, Netto), oder eine ganze Prospektseite als Text. Liste ausschließlich \
                Lebensmittel-Angebote mit einem klar erkennbaren Preis auf. Ignoriere Nicht-Lebensmittel, \
                reine Werbetexte und Text ohne Preis. Gib Produktname, Preis in Euro und die Packungsgröße \
                so an, wie sie im Text zu finden sind.
                """)
        } else {
            session = nil
        }

        var rawOffers: [RawOfferOnPage] = []
        for (i, page) in pages.enumerated() {
            await progress("Seite \(i + 1) von \(pages.count) wird ausgewertet …")
            // Prefer the layout-aware heuristic when we have positioned lines (real prospectus
            // PDFs); fall back to the flat-text heuristic for OCR'd (image-only) pages.
            let heuristic = page.lines.isEmpty
                ? ProspectParser.extract(from: page.flatText)
                : ProspectParser.extractFromLines(page.lines)

            var pageOffers: [RawOfferOnPage]?
            if let session {
                // Feed the AI the same spatially-grouped tiles the heuristic used, not the
                // page's jumbled raw text, chunked so a dense page can't blow the context window.
                let chunks = page.lines.isEmpty ? [page.flatText] : chunk(ProspectParser.tileTexts(page.lines), maxCharsPerChunk: 3000)
                var aiOffers: [RawOfferOnPage] = []
                var aiFailed = false
                for chunkText in chunks {
                    if let offers = await aiExtract(session: session, pageText: chunkText) {
                        aiOffers.append(contentsOf: offers)
                    } else {
                        aiFailed = true
                    }
                }
                pageOffers = aiFailed && aiOffers.isEmpty ? nil : aiOffers
            }
            let heuristicOffers = heuristic.map {
                RawOfferOnPage(productText: $0.productText, price: $0.price, packText: $0.packText, appOnly: $0.appOnly)
            }
            rawOffers.append(contentsOf: pageOffers ?? heuristicOffers)
        }

        await progress("Angebote werden zugeordnet …")
        return ImportResult(offers: matchAndConvert(rawOffers), dateRange: dateRange)
    }

    /// Groups strings into chunks of at most `maxCharsPerChunk`, splitting a page's tiles across
    /// several `respond` calls so a page-heavy prospectus doesn't exceed the model's context.
    private func chunk(_ blocks: [String], maxCharsPerChunk: Int) -> [String] {
        guard !blocks.isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        for block in blocks {
            if !current.isEmpty, current.count + block.count > maxCharsPerChunk {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + block
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Matches raw offers onto ingredients and keeps the cheapest offer per base unit
    /// (g/ml/Stk) for each ingredient. Offers with an unconvertible pack size are dropped.
    func matchAndConvert(_ raw: [RawOfferOnPage]) -> [ExtractedOffer] {
        var best: [String: ExtractedOffer] = [:]
        for r in raw {
            guard r.price > 0, let ingID = matcher.matchIngredient(r.productText), let ing = matcher.table[ingID] else { continue }
            let searchText = r.productText + " " + (r.packText ?? "")
            guard let parsed = matcher.parsePackSize(searchText, ingredientUnit: ing.unit), parsed.quantity > 0 else { continue }

            let candidate = ExtractedOffer(
                ingredientID: ingID,
                ingredientName: ing.name,
                productText: r.productText,
                price: r.price,
                pk: parsed.quantity,
                label: parsed.label,
                appOnly: r.appOnly
            )
            let candidatePerUnit = ProspectMatcher.pricePerBaseUnit(price: r.price, pk: parsed.quantity)
            if let existing = best[ingID] {
                let existingPerUnit = ProspectMatcher.pricePerBaseUnit(price: existing.price, pk: existing.pk)
                if candidatePerUnit < existingPerUnit {
                    best[ingID] = candidate
                }
            } else {
                best[ingID] = candidate
            }
        }
        return best.values.sorted { $0.ingredientName < $1.ingredientName }
    }

    /// Builds the `StoreOffer` to persist from the (deselect-filtered) review list.
    static func buildStoreOffer(from offers: [ExtractedOffer], validFrom: String, validTo: String, fileName: String) -> StoreOffer {
        var items: [String: OfferItem] = [:]
        for o in offers where o.selected {
            items[o.ingredientID] = OfferItem(product: o.productText, price: o.price, pk: o.pk, label: o.label, note: nil, app: o.appOnly ? true : nil)
        }
        return StoreOffer(name: nil, market: nil, validFrom: validFrom, validTo: validTo, status: "pdf", source: "PDF-Import \(fileName)", items: items)
    }

    private static func fmt(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(n)
    }
}
