import Foundation

/// Loaded, ready-to-use game data: stores, ingredients, recipes and the deterministic
/// market-price grid (PRICE in web/wochenkorb.html).
struct Catalog: Sendable {
    let stores: [String: StoreInfo]
    let cats: [String: String]
    let catOrder: [String]
    let ing: [String: Ingredient]
    let recipes: [Recipe]
    let recipesByID: [String: Recipe]
    /// price[ingredientID][storeID] = estimated normal price for one full pack.
    let price: [String: [String: Double]]

    init(bundle: DataBundle) {
        self.stores = bundle.stores
        self.cats = bundle.cats
        self.catOrder = bundle.catOrder

        var ingredients: [String: Ingredient] = [:]
        for (key, raw) in bundle.ing {
            ingredients[key] = Ingredient(id: key, raw: raw)
        }
        self.ing = ingredients

        let builtRecipes = bundle.recipes.map { Recipe(raw: $0, ingredients: ingredients) }
        self.recipes = builtRecipes
        self.recipesByID = Dictionary(uniqueKeysWithValues: builtRecipes.map { ($0.id, $0) })

        var priceGrid: [String: [String: Double]] = [:]
        for (ingID, i) in ingredients {
            var row: [String: Double] = [:]
            for (storeID, st) in bundle.stores {
                let jitter = 1 + (Double(PlannerMath.hash(ingID + storeID) % 100) / 100 - 0.5) * 0.12
                let bias = st.bias[i.cat] ?? 1
                let raw = i.price * st.f * bias * jitter
                row[storeID] = max(0.19, (raw * 10).rounded() / 10 - 0.01)
            }
            priceGrid[ingID] = row
        }
        self.price = priceGrid
    }

    static func loadBundled(bundle: Bundle = .main) -> Catalog {
        guard let url = bundle.url(forResource: "data", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(DataBundle.self, from: data) else {
            fatalError("Wochenkorb: data.json fehlt oder ist beschädigt")
        }
        return Catalog(bundle: bundle)
    }
}
