import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab
    @State private var selectedOrganization: OrganizationKind?
    @AppStorage("appearanceDark") private var appearanceDark = false

    enum Tab {
        case ward
        case organizations
        case openCallings
        case reports
    }

    init() {
        // Launch-argument hook for automated screenshots and UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "orgs": _selectedTab = State(initialValue: .organizations)
            case "open": _selectedTab = State(initialValue: .openCallings)
            case "reports": _selectedTab = State(initialValue: .reports)
            default: _selectedTab = State(initialValue: .ward)
            }
        } else {
            _selectedTab = State(initialValue: .ward)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            WardCallingsView { organization in
                selectedOrganization = organization
                selectedTab = .organizations
            }
            .tabItem { Label("Ward", systemImage: "person.3") }
            .tag(Tab.ward)
            OrganizationsView(selection: $selectedOrganization)
                .tabItem { Label("Organizations", systemImage: "rectangle.3.group") }
                .tag(Tab.organizations)
            OpenCallingsView()
                .tabItem { Label("Open Callings", systemImage: "list.bullet.rectangle") }
                .tag(Tab.openCallings)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "list.clipboard") }
                .tag(Tab.reports)
        }
        .preferredColorScheme(appearanceDark ? .dark : .light)
    }
}
