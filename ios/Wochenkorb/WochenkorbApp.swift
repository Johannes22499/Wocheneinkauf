import SwiftUI

@main
struct WochenkorbApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { await store.start() }
                .onOpenURL { url in
                    guard url.pathExtension.lowercased() == "pdf" else { return }
                    store.handleIncomingPDF(url)
                }
        }
    }
}
