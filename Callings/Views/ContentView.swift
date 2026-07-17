import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            WardCallingsView()
                .tabItem { Label("Ward Callings", systemImage: "person.3") }
            OpenCallingsView()
                .tabItem { Label("Open Callings", systemImage: "list.bullet.rectangle") }
            ImportView()
                .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
        }
    }
}
