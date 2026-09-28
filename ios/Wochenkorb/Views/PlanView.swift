import SwiftUI

struct PlanView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            if let notice {
                Section {
                    Text(notice.text)
                        .font(.footnote)
                        .foregroundStyle(notice.warn ? .red : .secondary)
                }
            }

            Section {
                if store.plan.isEmpty {
                    Text("Noch keine Gerichte geplant.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.settings.plan.enumerated()), id: \.offset) { index, id in
                        if let recipe = store.catalog.recipesByID[id] {
                            MealRow(recipe: recipe, dayIndex: index)
                        }
                    }
                }
            } header: {
                Text("Deine Woche")
            }

            Section {
                ForEach(store.otherRecipes) { recipe in
                    RecipeCatalogRow(recipe: recipe)
                }
            } header: {
                Text("Weitere passende Rezepte (\(store.otherRecipes.count))")
            }
        }
        .navigationTitle("Wochenkorb")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neu mischen") { store.shuffle() }
            }
        }
    }

    private var notice: (text: String, warn: Bool)? {
        let cands = store.candidates
        if cands.isEmpty {
            return ("Für diese Kombination gibt es kein Rezept. Nimm einen Filter heraus.", true)
        }
        let total = store.total
        if total > store.settings.budget {
            return ("Mit \(DE.eur(store.settings.budget)) geht es nicht ganz auf: Der günstigste Plan liegt bei \(DE.eur(total)). Weniger Abendessen, ein zweiter Discounter oder ein höheres Budget helfen.", true)
        }
        if cands.count < store.settings.days {
            return ("Nur \(cands.count) Rezepte passen zu deinen Filtern, deshalb wiederholen sich Gerichte. Tipp: doppelte Menge kochen und am nächsten Tag Reste essen.", false)
        }
        return nil
    }
}

private struct MealRow: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe
    let dayIndex: Int
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(dayIndex < DayNames.short.count ? DayNames.short[dayIndex] : "+")
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                    Text(dayIndex < DayNames.long.count ? DayNames.long[dayIndex] : "Extra")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name).font(.headline)
                    PillsView(recipe: recipe)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(DE.eur(store.planner.portionPrice(recipe)))
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        Text("je Portion").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Button { store.swap(dayIndex: dayIndex) } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) { store.remove(dayIndex: dayIndex) } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    let cols = [GridItem(.adaptive(minimum: 150), alignment: .leading)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
                        ForEach(recipe.ing.sorted(by: { $0.key < $1.key }), id: \.key) { key, qty in
                            if let ing = store.catalog.ing[key] {
                                HStack(spacing: 6) {
                                    Text(store.planner.fmtQty(qty * Double(store.settings.persons), ing.unit))
                                        .font(.subheadline.weight(.bold))
                                    Text(ing.name).font(.subheadline)
                                }
                            }
                        }
                    }
                    Text(recipe.steps).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } label: {
                Text("Zutaten für \(store.settings.persons) \(store.settings.persons == 1 ? "Person" : "Personen") & Zubereitung")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PillsView: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe

    var body: some View {
        let offerCount = recipe.ing.keys.filter { key in
            !(store.settings.vorrat && (store.catalog.ing[key]?.tags.contains("basic") ?? false)) && store.planner.onOffer(key)
        }.count

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Pill(text: KindLabel.map[recipe.kind] ?? recipe.kind, tint: .green)
                if offerCount > 0 {
                    Pill(text: "\(offerCount) im Angebot", tint: .yellow, filled: true)
                }
                if !recipe.hist { Pill(text: "histaminarm", tint: .green, soft: true) }
                if !recipe.lakt { Pill(text: "laktosefrei", tint: .secondary) }
                if !recipe.glut { Pill(text: "glutenfrei", tint: .secondary) }
                Pill(text: "\(recipe.minutes) Min.", tint: .secondary)
            }
        }
    }
}

private struct Pill: View {
    let text: String
    var tint: Color = .secondary
    var filled: Bool = false
    var soft: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(filled ? .bold : .regular))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(filled ? tint.opacity(0.9) : (soft ? tint.opacity(0.15) : Color.clear))
            .foregroundStyle(filled ? Color.black : tint)
            .overlay(Capsule().stroke(filled ? .clear : tint.opacity(0.5), lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct RecipeCatalogRow: View {
    @Environment(AppStore.self) private var store
    let recipe: Recipe

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name).font(.subheadline.weight(.semibold))
                PillsView(recipe: recipe)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(DE.eur(store.planner.portionPrice(recipe)))
                    .font(.caption.monospaced())
                Button("+ In die Woche") { store.add(recipeID: recipe.id) }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
