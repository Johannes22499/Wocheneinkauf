import Foundation

/// Loads weekly offer data: tries the remote URL first, falls back to the last successful
/// download cached in Application Support, then to the bundled copy of angebote/2026-KW40.json.
@MainActor
final class OfferService {
    /// Written by the GitHub Action (Sundays and Thursdays); see .github/workflows/angebote.yml.
    static let remoteURL: URL? = URL(string: "https://raw.githubusercontent.com/Johannes22499/Wocheneinkauf/main/angebote/AKTUELL.json")

    private let cacheFileName = "offers_cache.json"

    private var cacheURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent(cacheFileName)
    }

    enum Source: String {
        case remote, cache, bundle
    }

    struct LoadResult {
        let offers: OffersFile
        let source: Source
    }

    func load() async -> LoadResult {
        if let url = Self.remoteURL {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let offers = try JSONDecoder().decode(OffersFile.self, from: data)
                saveToCache(data)
                return LoadResult(offers: offers, source: .remote)
            } catch {
                // fall through to cache/bundle
            }
        }
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let offers = try? JSONDecoder().decode(OffersFile.self, from: data) {
            return LoadResult(offers: offers, source: .cache)
        }
        return LoadResult(offers: Self.loadBundled(), source: .bundle)
    }

    private func saveToCache(_ data: Data) {
        guard let url = cacheURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func loadBundled(bundle: Bundle = .main) -> OffersFile {
        guard let url = bundle.url(forResource: "offers_fallback", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let offers = try? JSONDecoder().decode(OffersFile.self, from: data) else {
            fatalError("Wochenkorb: offers_fallback.json fehlt oder ist beschädigt")
        }
        return offers
    }
}
