import SwiftUI
import PDFKit

/// "Prospekt-PDF importieren" flow: pick the store and validity dates (prefilled from the PDF
/// text when we can find it), run the extraction pipeline with a progress indicator, then let
/// the user deselect wrong matches before "Übernehmen".
struct ProspectImportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let fileURL: URL

    private enum Stage: Equatable { case chooseStore, importing, review }

    @State private var stage: Stage = .chooseStore
    @State private var selectedStore = "rewe"
    @State private var validFrom = Self.defaultMonday()
    @State private var validTo = Self.defaultSaturday()
    @State private var progressMessage = "Wird vorbereitet …"
    @State private var offers: [ExtractedOffer] = []

    private let importer = ProspectImporter()

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .chooseStore: chooseStoreForm
                case .importing: importingView
                case .review: reviewList
                }
            }
            .navigationTitle("Prospekt importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await prefillDates() }
    }

    // MARK: - Stage 1: store + dates

    private var chooseStoreForm: some View {
        Form {
            Section("Supermarkt") {
                Picker("Supermarkt", selection: $selectedStore) {
                    ForEach(ImportableStore.all, id: \.self) { id in
                        Text(store.catalog.stores[id]?.name ?? id).tag(id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Gültigkeit") {
                DatePicker("Von", selection: $validFrom, displayedComponents: .date)
                DatePicker("Bis", selection: $validTo, displayedComponents: .date)
            }
            Section {
                Button("Angebote suchen") {
                    Task { await startImport() }
                }
            }
        }
    }

    // MARK: - Stage 2: progress

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(progressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage 3: review

    private var reviewList: some View {
        VStack(spacing: 0) {
            if offers.isEmpty {
                ContentUnavailableView(
                    "Keine Angebote gefunden",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Aus dieser PDF konnten keine zu deinen Zutaten passenden Angebote erkannt werden.")
                )
            } else {
                List {
                    Section {
                        ForEach($offers) { $offer in
                            Toggle(isOn: $offer.selected) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(offer.ingredientName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(offer.productText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text(detailLine(for: offer))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } footer: {
                        Text("\(offers.filter(\.selected).count) von \(offers.count) Angeboten ausgewählt.")
                    }
                }
            }
            Button("Übernehmen") { applyImport() }
                .buttonStyle(.borderedProminent)
                .disabled(offers.allSatisfy { !$0.selected })
                .padding()
        }
    }

    private func detailLine(for offer: ExtractedOffer) -> String {
        var s = "\(DE.eur(offer.price)) · \(offer.label)"
        if offer.appOnly { s += " · nur mit App" }
        return s
    }

    // MARK: - Actions

    private func prefillDates() async {
        guard let doc = PDFDocument(url: fileURL) else { return }
        let year = Calendar.current.component(.year, from: Date())
        for i in 0..<min(doc.pageCount, 3) {
            guard let text = doc.page(at: i)?.string,
                  let range = ProspectParser.guessValidityDates(in: text, referenceYear: year) else { continue }
            if let from = Self.date(fromISO: range.from) { validFrom = from }
            if let to = Self.date(fromISO: range.to) { validTo = to }
            return
        }
    }

    private func startImport() async {
        stage = .importing
        let result = await importer.run(pdfURL: fileURL) { message in
            progressMessage = message
        }
        offers = result.offers
        stage = .review
    }

    private func applyImport() {
        let storeOffer = ProspectImporter.buildStoreOffer(
            from: offers,
            validFrom: Planner.todayString(validFrom),
            validTo: Planner.todayString(validTo),
            fileName: fileURL.lastPathComponent
        )
        store.applyImport(storeID: selectedStore, offer: storeOffer)
        dismiss()
    }

    // MARK: - Date helpers

    private static func date(fromISO iso: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: iso)
    }

    private static func defaultMonday() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    private static func defaultSaturday() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        return cal.date(byAdding: .day, value: 5, to: defaultMonday()) ?? Date()
    }
}
