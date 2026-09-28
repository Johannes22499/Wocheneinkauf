import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        TabView {
            Tab("Plan", systemImage: "fork.knife") {
                NavigationStack { PlanView() }
            }
            Tab("Einkaufsliste", systemImage: "cart") {
                NavigationStack { ShoppingListView() }
            }
            Tab("Einstellungen", systemImage: "slider.horizontal.3") {
                NavigationStack { SettingsView() }
            }
        }
        .sheet(isPresented: Binding(
            get: { store.pendingImportURL != nil },
            set: { if !$0 { store.clearPendingImport() } }
        )) {
            if let url = store.pendingImportURL {
                ProspectImportView(fileURL: url)
            }
        }
    }
}

#Preview {
    ContentView().environment(AppStore())
}
