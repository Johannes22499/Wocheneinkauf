import Foundation

/// Raw shape of Resources/ingredients_match.json (a straight copy of scraper/ingredients.json,
/// the scraper's hand-curated German match/exclude keyword lists used to map prospectus text
/// onto planner ingredients).
nonisolated struct IngredientMatchRaw: Codable, Sendable {
    let name: String
    let unit: String        // g | ml | Stk | Zehe | Bund
    let pack: Double
    let basePrice: Double
    let category: String
    let tags: [String]
    let packName: String?
    let match: [String]
    let exclude: [String]
}

typealias IngredientMatchTable = [String: IngredientMatchRaw]
