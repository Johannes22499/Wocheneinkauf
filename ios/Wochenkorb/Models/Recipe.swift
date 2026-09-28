import Foundation

/// A dinner recipe. `kind`/`hist`/`lakt`/`glut` are derived from ingredient tags,
/// exactly like the `.map(...)` block that builds `RECIPES` in web/wochenkorb.html.
struct Recipe: Identifiable, Sendable {
    let id: String
    let name: String
    let minutes: Int
    let ing: [String: Double]   // ingredientId -> Menge pro Person
    let steps: String
    let kind: String            // fleisch | fisch | veg | vegan
    let hist: Bool
    let lakt: Bool
    let glut: Bool

    init(raw: RecipeRaw, ingredients: [String: Ingredient]) {
        self.id = raw.id
        self.name = raw.name
        self.minutes = raw.min
        self.ing = raw.ing
        self.steps = raw.steps

        var tags = Set<String>()
        for key in raw.ing.keys {
            if let i = ingredients[key] { tags.formUnion(i.tags) }
        }
        if tags.contains("fleisch") { kind = "fleisch" }
        else if tags.contains("fisch") { kind = "fisch" }
        else if tags.contains("milch") || tags.contains("ei") { kind = "veg" }
        else { kind = "vegan" }
        hist = tags.contains("hist")
        lakt = tags.contains("lakt")
        glut = tags.contains("glut")
    }
}

enum KindLabel {
    static let map: [String: String] = ["fleisch": "Fleisch", "fisch": "Fisch", "veg": "Vegetarisch", "vegan": "Vegan"]
}

enum Diets {
    static let all: [(id: String, label: String)] = [
        ("mix", "Gemischt"), ("fleisch", "Fleisch & Fisch"), ("veg", "Vegetarisch"), ("vegan", "Vegan")
    ]
}

enum Subs {
    static let all: [(id: String, label: String)] = [
        ("hist", "Histaminarm"), ("lakt", "Laktosefrei"), ("glut", "Glutenfrei")
    ]
}

enum DayNames {
    static let short = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let long = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
}
