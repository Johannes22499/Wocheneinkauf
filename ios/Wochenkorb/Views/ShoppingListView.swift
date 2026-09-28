import SwiftUI
import UIKit

struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @State private var showCopySheet = false
    @State private var copyText = ""

    var body: some View {
        let (items, pantry) = store.shoppingList
        let total = items.reduce(0) { $0 + $1.sum }
        let over = total > store.settings.budget

        List {
            Section {
                HStack {
                    Text("Summe").font(.headline)
                    Spacer()
                    Text(DE.eur(total)).font(.headline.monospacedDigit())
                }
                HStack {
                    Text("Budget")
                    Spacer()
                    Text(DE.eur(store.settings.budget)).monospacedDigit()
                }
                HStack {
                    Text(over ? "Über Budget" : "Bleibt übrig")
                        .foregroundStyle(over ? .red : .primary)
                    Spacer()
                    Text(DE.eur(abs(store.settings.budget - total)))
                        .monospacedDigit()
                        .foregroundStyle(over ? .red : .primary)
                }
                ProgressView(value: min(1, total / max(0.01, store.settings.budget)))
                    .tint(over ? .red : .green)
            }

            ForEach(store.settings.stores, id: \.self) { storeID in
                let list = items.filter { $0.store == storeID }
                if !list.isEmpty {
                    Section(store.catalog.stores[storeID]?.name ?? storeID) {
                        ForEach(store.catalog.catOrder, id: \.self) { cat in
                            let group = list.filter { $0.cat == cat }.sorted { $0.name < $1.name }
                            ForEach(group) { item in
                                ShoppingRow(item: item, storeID: storeID)
                            }
                        }
                    }
                }
            }

            if !pantry.isEmpty {
                Section("Aus dem Vorrat") {
                    Text(pantry.joined(separator: ", ") + ", Salz, Pfeffer, Gewürze")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Einkaufsliste")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    copyText = store.copyListToClipboard()
                    UIPasteboard.general.string = copyText
                    store.showToast("Liste kopiert.")
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                Button {
                    store.uncheckAll()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.footnote)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.default, value: store.toast)
    }
}

private struct ShoppingRow: View {
    @Environment(AppStore.self) private var store
    let item: Planner.ShoppingItem
    let storeID: String

    private var key: String { storeID + ":" + item.key }
    private var done: Bool { store.settings.checked[key] == true }

    var body: some View {
        Button {
            store.toggleChecked(key)
        } label: {
            HStack(alignment: .top) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.packs)× \(item.name)")
                        .strikethrough(done)
                        .foregroundStyle(done ? .secondary : .primary)
                    let bp = store.planner.basePriceDisplay(item.key, item.unitPrice, item.pk)
                    Text(subtitle(bp: bp))
                        .font(.caption)
                        .foregroundStyle(item.isOffer ? .orange : .secondary)
                }
                Spacer()
                Text(DE.eur(item.sum))
                    .monospacedDigit()
                    .strikethrough(done)
                    .foregroundStyle(done ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    private func subtitle(bp: String?) -> String {
        var s = "\(item.label) à \(DE.eur(item.unitPrice))"
        if let bp { s += " (\(bp))" }
        let restThreshold = (item.unit == "g" || item.unit == "ml") ? 20.0 : 0.5
        if item.rest >= restThreshold {
            s += " · Rest \(store.planner.fmtQty(item.rest, item.unit))"
        }
        if item.isOffer {
            s += " · ANGEBOT"
            if let note = item.offerNote { s += " · \(note)" }
            if item.saved > 0.005 { s += " · spart \(DE.eur(item.saved))" }
        }
        return s
    }
}
