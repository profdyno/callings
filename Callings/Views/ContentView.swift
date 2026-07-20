import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab
    @State private var selectedOrganization: OrganizationKind?
    @AppStorage("appearanceDark") private var appearanceDark = false

    enum Tab {
        case members
        case ward
        case organizations
        case openCallings
        case actions
    }

    init() {
        // Launch-argument hook for automated screenshots and UI tests.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "orgs": _selectedTab = State(initialValue: .organizations)
            case "open": _selectedTab = State(initialValue: .openCallings)
            case "members": _selectedTab = State(initialValue: .members)
            case "actions": _selectedTab = State(initialValue: .actions)
            default: _selectedTab = State(initialValue: .ward)
            }
        } else {
            _selectedTab = State(initialValue: .ward)
        }
        if let index = arguments.firstIndex(of: "-org"), index + 1 < arguments.count {
            _selectedOrganization = State(initialValue: OrganizationKind(rawValue: arguments[index + 1]))
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MembersView()
                .tabItem { Label("Members", systemImage: "person.text.rectangle") }
                .tag(Tab.members)
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
            ActionsView()
                .tabItem { Label("Actions", systemImage: "checklist") }
                .tag(Tab.actions)
        }
        .preferredColorScheme(appearanceDark ? .dark : .light)
    }
}
