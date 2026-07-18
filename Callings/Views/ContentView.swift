import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab

    enum Tab {
        case wardCallings
        case openCallings
        case reports
    }

    init() {
        // Launch-argument hook for automated screenshots and UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "open": _selectedTab = State(initialValue: .openCallings)
            case "reports": _selectedTab = State(initialValue: .reports)
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
            ReportsView()
                .tabItem { Label("Reports", systemImage: "list.clipboard") }
                .tag(Tab.reports)
        }
    }
}
