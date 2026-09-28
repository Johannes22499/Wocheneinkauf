import Foundation

/// One offer found in an imported prospectus PDF, matched (or not) to a planner ingredient,
/// shown in the review list before the user taps "Übernehmen".
nonisolated struct ExtractedOffer: Identifiable, Equatable, Sendable {
    let id = UUID()
    var ingredientID: String
    var ingredientName: String
    var productText: String
    var price: Double
    var pk: Double
    var label: String
    var appOnly: Bool
    var selected: Bool = true
}

/// Stores importable via "Prospekt-PDF importieren" — Aldi/Kaufland are already scraped
/// automatically, so only the remaining chains make sense to hand-import.
nonisolated enum ImportableStore {
    static let all = ["rewe", "edeka", "lidl", "penny", "netto"]
}
