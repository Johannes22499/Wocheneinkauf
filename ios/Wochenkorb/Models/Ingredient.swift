import Foundation

/// A shopping ingredient. Mirrors `ING` in web/wochenkorb.html.
struct Ingredient: Identifiable, Sendable {
    let id: String
    let name: String
    let unit: String        // "g" | "ml" | "Stk" | "Zehe" | "Bund"
    let pk: Double          // Packungsgröße
    let price: Double       // Grundpreis je Packung
    let cat: String         // obst | kuehl | fleisch | tk | trocken | konserve | vorrat
    let tags: Set<String>   // fleisch, fisch, milch, ei, hist, lakt, glut, basic
    let pkLabel: String?

    init(id: String, raw: IngredientRaw) {
        self.id = id
        self.name = raw.name
        self.unit = raw.unit
        self.pk = raw.pk
        self.price = raw.price
        self.cat = raw.cat
        self.tags = Set(raw.tags.split(separator: " ").map(String.init))
        self.pkLabel = (raw.pkLabel?.isEmpty ?? true) ? nil : raw.pkLabel
    }
}
