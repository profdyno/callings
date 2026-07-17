import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab

    enum Tab {
        case wardCallings
        case openCallings
        case importData
    }

    init() {
        // Launch-argument hook for automated screenshots and UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "open": _selectedTab = State(initialValue: .openCallings)
            case "import": _selectedTab = State(initialValue: .importData)
            default: _selectedTab = State(initialValue: .wardCallings)
            }
        } else {
            _selectedTab = State(initialValue: .wardCallings)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WardCallingsView()
                .tabItem { Label("Ward Callings", systemImage: "person.3") }
                .tag(Tab.wardCallings)
            OpenCallingsView()
                .tabItem { Label("Open Callings", systemImage: "list.bullet.rectangle") }
                .tag(Tab.openCallings)
            ImportView()
                .tabItem { Label("Import", systemImage: "square.and.arrow.down") }
                .tag(Tab.importData)
        }
    }
}
