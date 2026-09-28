import Foundation

/// Saves/restores `Settings` (which already carries plan, seed and checked items) as JSON
/// in Application Support.
enum PersistenceService {
    private static let fileName = "wochenkorb_settings.json"

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> Settings? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Settings.self, from: data)
    }

    static func save(_ settings: Settings) {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
