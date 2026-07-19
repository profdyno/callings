import SwiftUI

/// Organizations tab: sidebar of the ward's organizations; selecting one
/// shows its workflow table.
struct OrganizationsView: View {
    @Environment(WardStore.self) private var store
    @Binding var selection: OrganizationKind?

    private var organizations: [OrganizationKind] {
        OrganizationKind.allCases.filter { !store.slots(in: $0).isEmpty }
    }

    var body: some View {
        NavigationSplitView {
            List(organizations, selection: $selection) { org in
                let slots = store.slots(in: org)
                let vacant = slots.filter { $0.memberID == nil }.count
                VStack(alignment: .leading, spacing: 1) {
                    Text(org.rawValue)
                    Text(vacant > 0 ? "\(slots.count) callings · \(vacant) vacant" : "\(slots.count) callings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(org)
            }
            .navigationTitle("Organizations")
        } detail: {
            if let selection {
                NavigationStack {
                    OrganizationView(organization: selection)
                }
            } else {
                ContentUnavailableView(
                    "Select an Organization",
                    systemImage: "person.3",
                    description: Text("Choose a group from the sidebar to work its callings.")
                )
            }
        }
        .onAppear {
            if selection == nil {
                selection = organizations.first
            }
        }
    }
}
