import Foundation

/// Raw shape of Resources/data.json, extracted from the web reference (web/wochenkorb.html).
struct DataBundle: Codable {
    let stores: [String: StoreInfo]
    let cats: [String: String]
    let catOrder: [String]
    let ing: [String: IngredientRaw]
    let recipes: [RecipeRaw]
}

struct StoreInfo: Codable {
    let name: String
    let f: Double
    let bias: [String: Double]
}

struct IngredientRaw: Codable {
    let name: String
    let unit: String
    let pk: Double
    let price: Double
    let cat: String
    let tags: String
    let pkLabel: String?
}

struct RecipeRaw: Codable {
    let id: String
    let name: String
    let min: Int
    let ing: [String: Double]
    let steps: String
}
