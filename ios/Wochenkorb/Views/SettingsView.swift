import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(Settings.allStores, id: \.self) { id in
                        let selected = store.settings.stores.contains(id)
                        Button(store.catalog.stores[id]?.name ?? id) {
                            store.toggleStore(id)
                        }
                        .font(.subheadline.weight(selected ? .bold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(selected ? Color.green : Color.clear)
                        .foregroundStyle(selected ? .white : .primary)
                        .overlay(Capsule().stroke(selected ? .clear : .secondary.opacity(0.4)))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Supermärkte (\(store.settings.stores.count) von max. 2)")
            } footer: {
                Text("Bei zwei Märkten landet jeder Artikel dort, wo er günstiger ist.")
            }

            Section("Budget für die Woche") {
                HStack {
                    Slider(value: Binding(
                        get: { min(200, store.settings.budget) },
                        set: { store.setBudget($0) }
                    ), in: 10...200, step: 5)
                    Text(DE.eur(store.settings.budget))
                        .monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
                Stepper("Personen: \(store.settings.persons)") { store.setPersons(1) } onDecrement: { store.setPersons(-1) }
                Stepper("Abendessen: \(store.settings.days)") { store.setDays(1) } onDecrement: { store.setDays(-1) }
            }

            Section("Ernährung") {
                Picker("Ernährung", selection: Binding(
                    get: { store.settings.diet },
                    set: { store.setDiet($0) }
                )) {
                    ForEach(Diets.all, id: \.id) { d in
                        Text(d.label).tag(d.id)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(Subs.all, id: \.id) { s in
                    Toggle(s.label, isOn: Binding(
                        get: { subValue(s.id) },
                        set: { store.setSub(s.id, $0) }
                    ))
                }
            }

            Section {
                Toggle("Öl, Brühe, Mehl & Gewürze habe ich zu Hause", isOn: Binding(
                    get: { store.settings.vorrat },
                    set: { store.setVorrat($0) }
                ))
                Toggle("App- und Kartenpreise einrechnen", isOn: Binding(
                    get: { store.settings.app },
                    set: { store.setApp($0) }
                ))
            } header: {
                Text("Vorrat & Angebote")
            } footer: {
                Text("Normalpreise sind geschätzte Richtwerte. Angebote stammen aus den Prospekten.")
            }

            Section {
                offersHeader
                ForEach(Settings.allStores, id: \.self) { id in
                    if let o = store.offers?.stores[id] {
                        OfferRow(storeID: id, offer: o)
                    }
                }
            } header: {
                Text("Angebote diese Woche")
            }
        }
        .navigationTitle("Einstellungen")
    }

    private func subValue(_ id: String) -> Bool {
        switch id {
        case "hist": return store.settings.hist
        case "lakt": return store.settings.lakt
        case "glut": return store.settings.glut
        default: return false
        }
    }

    @ViewBuilder
    private var offersHeader: some View {
        if let offers = store.offers {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stand \(offers.stand) · \(offers.ort ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceLabel: String {
        switch store.offerSource {
        case .remote: return "Online geladen"
        case .cache: return "Aus dem Zwischenspeicher (offline)"
        case .bundle: return "Mitgelieferte Angebote (KW 40)"
        }
    }
}

private struct OfferRow: View {
    @Environment(AppStore.self) private var store
    let storeID: String
    let offer: StoreOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(offer.market ?? offer.name ?? store.catalog.stores[storeID]?.name ?? storeID)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let link = offer.source, let url = URL(string: link) {
                    Link("Quelle", destination: url).font(.caption)
                }
            }
            Text("\(offer.validFrom) bis \(offer.validTo) · \(offer.items.count) passende Angebote\(offer.status.map { " · " + $0 } ?? "")")
                .font(.caption)
                .foregroundStyle(store.planner.offersLive(storeID) ? .primary : .secondary)
        }
        .padding(.vertical, 2)
    }
}
