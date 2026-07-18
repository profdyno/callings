import SwiftUI

/// Home page: all organizations with their callings and holders, in a
/// masonry grid that scales from iPad portrait to a 16:9 TV.
struct WardCallingsView: View {
    @Environment(WardStore.self) private var store
    @State private var editingDefinition: CallingDefinition?
    @State private var pickerEntry: OpenCalling?
    @State private var addingCalling = false
    @State private var showingSharing = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
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
                                    OrganizationCardView(
                                        organization: org,
                                        editingDefinition: $editingDefinition,
                                        pickerEntry: $pickerEntry
                                    )
                                }
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle(store.data.wardName ?? "Ward Callings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSharing = true
                    } label: {
                        Label("Sharing", systemImage: "person.2")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addingCalling = true
                    } label: {
                        Label("New Calling", systemImage: "plus")
                    }
                }
                FilterBar()
            }
            .sheet(isPresented: $addingCalling) {
                AddCallingSheet()
            }
            .sheet(isPresented: $showingSharing) {
                SharingView()
            }
            .navigationDestination(for: OrganizationKind.self) { org in
                OrganizationView(organization: org)
            }
            .navigationDestination(for: CallingSlot.self) { slot in
                CallingDetailView(slotID: slot.id)
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
            .sheet(item: $pickerEntry) { entry in
                if let slot = store.slotsByID[entry.slotID],
                   let definition = store.definition(for: slot) {
                    CandidatePickerSheet(openCallingID: entry.id, definitionID: definition.id)
                }
            }
            .onAppear {
                // Launch-argument hook for automated screenshots and UI tests.
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "-drill"), index + 1 < arguments.count,
                   let org = OrganizationKind.match(headerText: arguments[index + 1]) {
                    path.append(org)
                }
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
