import SwiftUI

/// Home page: a horizontally scrolling board of group columns (snapping
/// into place), each column scrolling vertically on its own.
struct WardCallingsView: View {
    @Environment(WardStore.self) private var store
    /// Tapping a group header drills into the Organizations tab.
    var onDrill: (OrganizationKind) -> Void = { _ in }

    @State private var editingDefinition: CallingDefinition?
    @State private var pickerSlot: CallingSlot?
    @State private var detailMemberID: UUID?
    @State private var addingCalling = false

    private let columnSpacing: CGFloat = 12

    /// User-specified column arrangement, left to right.
    private static let homeColumns: [[HomeGroup]] = [
        [.org(.eldersQuorum)],
        [.org(.reliefSociety)],
        [.org(.wardMissionaries), .org(.templeAndFamilyHistory)],
        [.org(.aaronicPriesthoodQuorums)],
        [.org(.youngWomen)],
        [.org(.primary)],
        [.org(.sundaySchool)],
        [.activitiesCommittee, .org(.youngSingleAdult)],
        [.org(.otherCallings)],
        [.org(.bishopric)],
    ]

    private var visibleColumns: [[HomeGroup]] {
        Self.homeColumns
            .map { $0.filter { !store.slots(in: $0.organization).isEmpty } }
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
            .appToolbar(help: .ward)
            .toolbar {
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
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
            .sheet(item: $pickerSlot) { slot in
                CandidatePickerSheet(slotID: slot.id)
            }
            .sheet(item: $detailMemberID) { memberID in
                MemberDetailSheet(memberID: memberID)
            }
        }
    }

    private var board: some View {
        GeometryReader { geometry in
            // Three columns across in landscape; narrower screens show fewer.
            let columnWidth = max(340, (geometry.size.width - 4 * columnSpacing) / 3)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(Array(visibleColumns.enumerated()), id: \.offset) { _, groups in
                        boardColumn(groups, width: columnWidth)
                    }
                }
                .scrollTargetLayout()
                .padding(columnSpacing)
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    private func boardColumn(_ groups: [HomeGroup], width: CGFloat) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    OrganizationCardView(
                        group: group,
                        editingDefinition: $editingDefinition,
                        pickerSlot: $pickerSlot,
                        detailMemberID: $detailMemberID,
                        onDrill: onDrill
                    )
                }
            }
        }
        .frame(width: width)
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
                Text("\(store.tenureThresholdMonths) mo")
                    .font(.callout.weight(.medium))
            }
        }
    }
}
