import Foundation

/// Persists offers imported from prospectus PDFs, one `StoreOffer` per store, in
/// Application Support (`imported_offers.json`). Independent of `OfferService`'s
/// downloaded/cached offers; `AppStore` merges the two, preferring a still-valid import.
@MainActor
final class ImportedOffersStore {
    private let fileName = "imported_offers.json"

    private var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    /// Loads the stored imports and drops any whose validity has passed `today`
    /// ("yyyy-MM-dd"), persisting the pruned result.
    func loadPruned(today: String) -> [String: StoreOffer] {
        var stores = load()
        let before = stores.count
        stores = stores.filter { $0.value.validTo >= today }
        if stores.count != before {
            save(stores)
        }
        return stores
    }

    func load() -> [String: StoreOffer] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: StoreOffer].self, from: data)) ?? [:]
    }

    func save(_ stores: [String: StoreOffer]) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(stores) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func setOffer(_ offer: StoreOffer, forStore storeID: String) {
        var stores = load()
        stores[storeID] = offer
        save(stores)
    }

    func delete(storeID: String) {
        var stores = load()
        stores.removeValue(forKey: storeID)
        save(stores)
    }
}
