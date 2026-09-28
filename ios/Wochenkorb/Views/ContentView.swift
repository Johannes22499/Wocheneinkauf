import SwiftUI

struct ContentView: View {
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
    }
}

#Preview {
    ContentView().environment(AppStore())
}
