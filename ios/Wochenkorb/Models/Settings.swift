import Foundation

/// Mirrors the `S` settings object in web/wochenkorb.html, persisted as JSON.
struct Settings: Codable, Equatable, Sendable {
    var stores: [String] = ["aldi", "lidl"]
    var budget: Double = 45
    var persons: Int = 2
    var days: Int = 5
    var diet: String = "mix"     // mix | fleisch | veg | vegan
    var hist: Bool = false
    var lakt: Bool = false
    var glut: Bool = false
    var vorrat: Bool = true
    var app: Bool = true
    var plan: [String] = []
    var seed: Int = 7
    var checked: [String: Bool] = [:]

    static let allStores = ["aldi", "lidl", "penny", "netto", "kaufland", "rewe", "edeka"]
}
