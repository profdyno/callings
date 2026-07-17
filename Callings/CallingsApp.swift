import SwiftUI

@main
struct CallingsApp: App {
    @State private var store = WardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
