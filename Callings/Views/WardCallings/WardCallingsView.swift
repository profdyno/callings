import SwiftUI

/// Home page: a horizontally scrolling board of organization columns
/// (snapping into place), each column scrolling vertically on its own.
struct WardCallingsView: View {
    @Environment(WardStore.self) private var store
    /// Tapping an org header drills into the Organizations tab.
    var onDrill: (OrganizationKind) -> Void = { _ in }

    @State private var editingDefinition: CallingDefinition?
    @State private var pickerSlot: CallingSlot?
    @State private var addingCalling = false
    @State private var showingSharing = false
    @State private var showingImport = false
    @AppStorage("appearanceDark") private var appearanceDark = false

    /// User-specified column arrangement, left to right.
    private static let homeColumns: [[OrganizationKind]] = [
        [.eldersQuorum],
        [.reliefSociety],
        [.wardMissionaries, .templeAndFamilyHistory],
        [.aaronicPriesthoodQuorums],
        [.youngWomen],
        [.primary],
        [.sundaySchool],
        [.youngSingleAdult, .otherCallings],
        [.bishopric],
    ]

    private var visibleColumns: [[OrganizationKind]] {
        Self.homeColumns
            .map { $0.filter { !store.slots(in: $0).isEmpty } }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.data.callingSlots.isEmpty {
                    ContentUnavailableView(
                        "No Ward Data",
                        systemImage: "person.3",
                        description: Text("Import the Ward Callings and Member List PDFs from the ••• menu.")
                    )
                } else {
                    board
                }
            }
            .navigationTitle(store.data.wardName ?? "Ward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingSharing = true
                    } label: {
                        Label("Sharing", systemImage: "person.2")
                    }
                    Menu {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import…", systemImage: "square.and.arrow.down")
                        }
                        Toggle(isOn: $appearanceDark) {
                            Label("Dark Background", systemImage: appearanceDark ? "moon.fill" : "moon")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
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
            .navigationDestination(for: CallingSlot.self) { slot in
                CallingDetailView(slotID: slot.id)
            }
            .sheet(isPresented: $addingCalling) {
                AddCallingSheet()
            }
            .sheet(isPresented: $showingSharing) {
                SharingView()
            }
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
            .sheet(item: $pickerSlot) { slot in
                CandidatePickerSheet(slotID: slot.id)
            }
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(visibleColumns.enumerated()), id: \.offset) { _, organizations in
                    boardColumn(organizations)
                }
            }
            .scrollTargetLayout()
            .padding(12)
        }
        .scrollTargetBehavior(.viewAligned)
    }

    private func boardColumn(_ organizations: [OrganizationKind]) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(organizations) { org in
                    OrganizationCardView(
                        organization: org,
                        editingDefinition: $editingDefinition,
                        pickerSlot: $pickerSlot,
                        onDrill: onDrill
                    )
                }
            }
        }
        .frame(width: 460)
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
