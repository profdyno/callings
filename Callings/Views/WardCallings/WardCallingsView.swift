import SwiftUI

/// Home page: all organizations with their callings and holders, in a
/// masonry grid that scales from iPad portrait to a 16:9 TV.
struct WardCallingsView: View {
    @Environment(WardStore.self) private var store
    @State private var editingDefinition: CallingDefinition?

    var body: some View {
        NavigationStack {
            Group {
                if store.data.callingSlots.isEmpty {
                    ContentUnavailableView(
                        "No Ward Data",
                        systemImage: "person.3",
                        description: Text("Import the Ward Callings and Member List PDFs from the Import tab.")
                    )
                } else {
                    ScrollView {
                        MasonryLayout(columnWidth: 340, spacing: 12) {
                            ForEach(OrganizationKind.allCases) { org in
                                if !store.slots(in: org).isEmpty {
                                    OrganizationCardView(organization: org, editingDefinition: $editingDefinition)
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(store.data.wardName ?? "Ward Callings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { FilterBar() }
            .navigationDestination(for: OrganizationKind.self) { org in
                OrganizationView(organization: org)
            }
            .navigationDestination(for: CallingSlot.self) { slot in
                CallingDetailView(slotID: slot.id)
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
        }
    }
}

/// Highlight filter controls shown in the toolbar.
struct FilterBar: ToolbarContent {
    @Environment(WardStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            @Bindable var store = store
            Toggle(isOn: $store.highlightOpenCallings) {
                Label("Vacant & Open", systemImage: "exclamationmark.circle")
            }
            .toggleStyle(.button)

            Toggle(isOn: $store.highlightTenure) {
                Label("Over \(store.tenureThresholdMonths) mo", systemImage: "clock")
            }
            .toggleStyle(.button)

            Menu {
                Picker("Months", selection: $store.tenureThresholdMonths) {
                    ForEach([6, 12, 18, 24, 36, 48, 60], id: \.self) { months in
                        Text("\(months) months").tag(months)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
    }
}

#Preview {
    WardCallingsView().environment(WardStore())
}
