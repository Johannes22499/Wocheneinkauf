import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    let catalog: Catalog
    var settings: Settings
    var offers: OffersFile?
    var offerSource: OfferService.Source = .bundle
    var toast: String?
    /// Offers imported from a prospectus PDF, one per store, pruned of expired entries.
    var importedOffers: [String: StoreOffer] = [:]
    /// Set by the file importer / "Öffnen in" share-sheet handoff; `ContentView` presents the
    /// import sheet for it and clears it again.
    var pendingImportURL: URL?

    private let offerService = OfferService()
    private let importedOffersStore = ImportedOffersStore()
    private var toastTask: Task<Void, Never>?

    init() {
        catalog = Catalog.loadBundled()
        settings = PersistenceService.load() ?? Settings()
        var planner = Planner(catalog: catalog, offers: nil, settings: settings)
        planner.fitPlan()
        settings = planner.settings
    }

    func start() async {
        let result = await offerService.load()
        offers = result.offers
        offerSource = result.source
        importedOffers = importedOffersStore.loadPruned(today: Planner.todayString())
        refit()
    }

    var planner: Planner {
        Planner(catalog: catalog, offers: effectiveOffers, settings: settings)
    }

    /// Merges the downloaded/cached offers with still-valid PDF imports: an import wins over
    /// the automatic download for its store as long as it hasn't expired.
    var effectiveOffers: OffersFile? {
        Self.merge(downloaded: offers, imported: importedOffers, today: Planner.todayString())
    }

    /// Pure merge logic (no instance state), so it's directly testable: an import for a store
    /// is used only while `imported[store].validTo >= today`; otherwise the download wins.
    static func merge(downloaded: OffersFile?, imported: [String: StoreOffer], today: String) -> OffersFile? {
        let validImports = imported.filter { $0.value.validTo >= today }
        guard let downloaded else {
            guard !validImports.isEmpty else { return nil }
            return OffersFile(kw: "import", stand: today, ort: nil, hinweis: nil, stores: validImports)
        }
        guard !validImports.isEmpty else { return downloaded }
        var stores = downloaded.stores
        for (id, imported) in validImports { stores[id] = imported }
        return OffersFile(kw: downloaded.kw, stand: downloaded.stand, ort: downloaded.ort, hinweis: downloaded.hinweis, stores: stores)
    }

    /// True while `storeID` is currently served from a PDF import rather than the download.
    func isImported(_ storeID: String) -> Bool {
        guard let offer = importedOffers[storeID] else { return false }
        return offer.validTo >= Planner.todayString()
    }

    // MARK: - Prospectus import

    func beginImport(fileURL: URL) {
        pendingImportURL = fileURL
    }

    /// Takes a PDF handed to the app (`.fileImporter` selection or an "Öffnen in Wochenkorb"
    /// share-sheet URL), reads it through its security scope if needed, and copies it into our
    /// own Application Support folder so it stays readable for the rest of the import flow.
    func handleIncomingPDF(_ url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let importsDir = supportDir.appendingPathComponent("ProspectImports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: importsDir, withIntermediateDirectories: true)
            let dest = importsDir.appendingPathComponent(url.lastPathComponent.isEmpty ? "\(UUID().uuidString).pdf" : url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            beginImport(fileURL: dest)
        } catch {
            showToast("Die PDF-Datei konnte nicht gelesen werden.")
        }
    }

    func clearPendingImport() {
        pendingImportURL = nil
    }

    func applyImport(storeID: String, offer: StoreOffer) {
        importedOffersStore.setOffer(offer, forStore: storeID)
        importedOffers[storeID] = offer
        refit()
        showToast("Angebote aus PDF übernommen.")
    }

    func deleteImport(storeID: String) {
        importedOffersStore.delete(storeID: storeID)
        importedOffers.removeValue(forKey: storeID)
        refit()
    }

    // MARK: - Derived data for views

    var plan: [Recipe] { settings.plan.compactMap { catalog.recipesByID[$0] } }

    var candidates: [Recipe] { planner.candidates() }

    var otherRecipes: [Recipe] {
        let p = planner
        return p.candidates().filter { !settings.plan.contains($0.id) }
            .map { ($0, p.portionPrice($0)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    var total: Double { planner.costOf(settings.plan) }

    var shoppingList: (items: [Planner.ShoppingItem], pantry: [String]) { planner.buildList() }

    // MARK: - Mutations (mirrors the web version's event handlers)

    /// Settings changed: keep matching recipes, refill, replan only if over budget (fitPlan).
    func refit() {
        var p = planner
        p.fitPlan()
        settings = p.settings
        persist()
    }

    func toggleStore(_ id: String) {
        if settings.stores.contains(id) {
            if settings.stores.count > 1 { settings.stores.removeAll { $0 == id } }
        } else {
            settings.stores = Array((settings.stores + [id]).suffix(2))
        }
        refit()
    }

    func setDiet(_ id: String) {
        settings.diet = id
        refit()
    }

    func setSub(_ id: String, _ value: Bool) {
        switch id {
        case "hist": settings.hist = value
        case "lakt": settings.lakt = value
        case "glut": settings.glut = value
        default: break
        }
        refit()
    }

    func setVorrat(_ value: Bool) { settings.vorrat = value; refit() }
    func setApp(_ value: Bool) { settings.app = value; refit() }

    func setBudget(_ value: Double) { settings.budget = value.rounded(); refit() }

    func setPersons(_ delta: Int) {
        settings.persons = min(8, max(1, settings.persons + delta))
        refit()
    }

    func setDays(_ delta: Int) {
        settings.days = min(7, max(1, settings.days + delta))
        refit()
    }

    /// "Neu mischen"
    func shuffle() {
        settings.seed += 1
        settings.plan = planner.generate(keep: [])
        persist()
    }

    func swap(dayIndex: Int) {
        guard settings.plan.indices.contains(dayIndex) else { return }
        let cur = settings.plan[dayIndex]
        let cands = planner.candidates().map(\.id)
        let alts = cands.filter { $0 != cur && !settings.plan.contains($0) }
        let pool = alts.isEmpty ? cands.filter { $0 != cur } : alts
        guard !pool.isEmpty else { return }
        let millis = Int(Date().timeIntervalSince1970 * 1000) % 1000
        let rand = PlannerMath.makeRNG(seed: PlannerMath.hash(cur + String(dayIndex) + String(settings.seed)) &+ UInt32(millis))
        var generator = SeededGenerator(rand: rand)
        let shuffled = pool.shuffled(using: &generator)
        let p = planner
        if let fit = shuffled.first(where: { id in
            var plan = settings.plan
            plan[dayIndex] = id
            return p.costOf(plan) <= settings.budget
        }) {
            settings.plan[dayIndex] = fit
        } else {
            settings.plan[dayIndex] = shuffled.sorted { p.portionPrice(p.catalog.recipesByID[$0]!) < p.portionPrice(p.catalog.recipesByID[$1]!) }.first ?? cur
        }
        persist()
    }

    func remove(dayIndex: Int) {
        guard settings.plan.indices.contains(dayIndex) else { return }
        settings.plan.remove(at: dayIndex)
        settings.days = max(1, settings.plan.count)
        persist()
    }

    func add(recipeID: String) {
        guard settings.plan.count < 7 else {
            showToast("Die Woche ist voll. Tausch ein Gericht oder entferne einen Tag.")
            return
        }
        settings.plan.append(recipeID)
        settings.days = settings.plan.count
        persist()
    }

    func uncheckAll() {
        settings.checked = [:]
        persist()
    }

    func toggleChecked(_ key: String) {
        if settings.checked[key] == true { settings.checked.removeValue(forKey: key) }
        else { settings.checked[key] = true }
        persist()
    }

    func copyListToClipboard() -> String {
        planner.listText()
    }

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private func persist() {
        PersistenceService.save(settings)
    }
}

/// Tiny RandomNumberGenerator adapter so we can drive Swift's `.shuffled(using:)`
/// with the ported mulberry32 rand() closure (matches `pool.sort(()=>rand()-.5)` closely enough
/// for a "pick a different recipe" swap — determinism isn't user-observable here).
struct SeededGenerator: RandomNumberGenerator {
    let rand: () -> Double
    mutating func next() -> UInt64 {
        UInt64(rand() * Double(UInt64.max))
    }
}
