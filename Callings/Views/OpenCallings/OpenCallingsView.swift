import SwiftUI

/// The Open Callings workflow table: one row per calling being worked,
/// sorted by group then calling display order.
struct OpenCallingsView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    @State private var showArchived = false
    @State private var pickerEntry: OpenCalling?
    @State private var editingDefinition: CallingDefinition?
    // Filters (nil = all)
    @State private var filterOrganization: OrganizationKind?
    @State private var filterStage: StageFilter?
    @State private var filterPerson: BishopricMember?

    /// Workflow-stage quick filters: a row matches when EITHER ladder sits
    /// at that stage.
    private enum StageFilter: String, CaseIterable, Identifiable {
        case approve = "Need to Approve"
        case releaseCall = "Need to Release/Call"
        case announceSustain = "Need to Announce/Sustain"

        var id: String { rawValue }

        func matches(_ entry: OpenCalling) -> Bool {
            switch self {
            case .approve:
                entry.releaseStatus == .proposed || entry.callStatus == .proposed
            case .releaseCall:
                entry.releaseStatus == .approved || entry.callStatus == .approved
            case .announceSustain:
                entry.releaseStatus == .released || entry.callStatus == .called
            }
        }
    }

    private var hasActiveFilters: Bool {
        filterOrganization != nil || filterStage != nil || filterPerson != nil
    }

    private func clearFilters() {
        filterOrganization = nil
        filterStage = nil
        filterPerson = nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if showArchived {
                    archivedList
                } else if store.activeOpenCallings.isEmpty {
                    // Truly nothing to work — filters play no part here.
                    ContentUnavailableView(
                        "No Open Callings",
                        systemImage: "rectangle.stack",
                        description: Text("Tap a calling on the Ward page to start a release/call.")
                    )
                } else {
                    // Filter bar and table stay mounted even when the filters
                    // match nothing, so there is always a way to clear them.
                    VStack(spacing: 0) {
                        filterBar
                        table
                            .overlay {
                                if rows.isEmpty {
                                    ContentUnavailableView {
                                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                                    } description: {
                                        Text("No open callings match these filters.")
                                    } actions: {
                                        Button("Clear Filters") { clearFilters() }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle(showArchived ? "Archived Callings" : "Open Callings")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(help: .openCallings)
            .toolbar {
                Toggle(isOn: $showArchived) {
                    Label("Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
            }
            .sheet(item: $pickerEntry) { entry in
                CandidatePickerSheet(slotID: entry.slotID)
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
        }
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let entry: OpenCalling
        let organization: OrganizationKind
        let displayOrder: Double
        let callingName: String
        let currentMember: String
        let newMember: String
        let candidates: String

        var id: UUID { entry.id }
    }

    private var rows: [Row] {
        store.activeOpenCallings.compactMap { entry in
            guard let slot = store.slotsByID[entry.slotID],
                  let definition = store.definition(for: slot) else { return nil }
            return Row(
                entry: entry,
                organization: definition.organization,
                displayOrder: definition.displayOrder,
                callingName: definition.name,
                currentMember: store.member(slot.memberID)?.name ?? slot.holderNameRaw ?? "Vacant",
                newMember: store.member(entry.memberToBeCalledID)?.name ?? "—",
                candidates: entry.candidateIDs.compactMap { store.member($0)?.displayName }.joined(separator: ", ")
            )
        }
        .filter { row in
            if let filterOrganization, row.organization != filterOrganization { return false }
            if let filterStage, !filterStage.matches(row.entry) { return false }
            if let filterPerson,
               (row.entry.releaseAssignedTo ?? .unassigned) != filterPerson,
               row.entry.assignedTo != filterPerson { return false }
            return true
        }
        .sorted {
            if $0.organization.displayOrder != $1.organization.displayOrder {
                return $0.organization.displayOrder < $1.organization.displayOrder
            }
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            return $0.callingName < $1.callingName
        }
    }

    /// Stage and person toggle buttons plus the Group menu, above the table.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StageFilter.allCases) { stage in
                    toggleChip(stage.rawValue, isOn: filterStage == stage) {
                        filterStage = filterStage == stage ? nil : stage
                    }
                }
                Divider()
                    .frame(height: 20)
                ForEach([BishopricMember.bishop, .firstCounselor, .secondCounselor]) { member in
                    toggleChip(member.rawValue, isOn: filterPerson == member) {
                        filterPerson = filterPerson == member ? nil : member
                    }
                }
                Divider()
                    .frame(height: 20)
                filterMenu("Group", selection: $filterOrganization, options: OrganizationKind.allCases) { $0.rawValue }
                if hasActiveFilters {
                    Button("Clear") { clearFilters() }
                        .font(.callout)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func toggleChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterMenu<T: Hashable>(
        _ title: String,
        selection: Binding<T?>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        Menu {
            Button("All") { selection.wrappedValue = nil }
            ForEach(options, id: \.self) { option in
                Button(label(option)) { selection.wrappedValue = option }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.wrappedValue.map(label) ?? title)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.callout)
            .foregroundStyle(selection.wrappedValue == nil ? Color.secondary : Color.accentColor)
        }
    }

    private func definition(for entry: OpenCalling) -> CallingDefinition? {
        guard let slot = store.slotsByID[entry.slotID] else { return nil }
        return store.definition(for: slot)
    }

    private var table: some View {
        Table(rows) {
            TableColumn("") { row in
                if syncService.canDeleteOpenCallings {
                    Button(role: .destructive) {
                        store.removeOpenCalling(row.entry.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this calling change")
                }
            }
            .width(28)

            TableColumn("Group") { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.organization.rawValue)
                    if let subgroup = definition(for: row.entry)?.subgroup {
                        Text(CallingDefinition.subgroupDisplayName(subgroup, organization: row.organization))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("Calling") { row in
                HStack(spacing: 6) {
                    Button {
                        editingDefinition = definition(for: row.entry)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit criteria and display order")
                    let rowDefinition = definition(for: row.entry)
                    Text(row.callingName)
                        .strikethrough(rowDefinition?.isMarkedForDeletion == true)
                        .foregroundStyle(rowDefinition?.isPending == true ? .orange : .red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .width(min: 180, ideal: 280)

            TableColumn("Current (Release)") { row in
                ReleaseStatusCell(
                    currentName: row.currentMember,
                    memberID: store.slotsByID[row.entry.slotID]?.memberID,
                    entry: row.entry
                ) { row.entry }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Assigned (Release)") { row in
                AssignedCell(assigned: row.entry.releaseAssignedTo) { member in
                    update(row.entry) { $0.releaseAssignedTo = member }
                }
            }
            .width(min: 85, ideal: 105)

            TableColumn("Candidates") { row in
                CandidatesCell(entry: row.entry) {
                    pickerEntry = row.entry
                }
            }
            .width(min: 160)

            TableColumn("To Be Called (Status)") { row in
                ToBeCalledCell(entry: row.entry) { row.entry }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Assigned (Call)") { row in
                AssignedCell(assigned: row.entry.assignedTo) { member in
                    update(row.entry) { $0.assignedTo = member }
                }
            }
            .width(min: 85, ideal: 105)
        }
        .contextMenu(forSelectionType: Row.ID.self) { ids in
            if let id = ids.first {
                Button {
                    store.archiveOpenCalling(id)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                Button(role: .destructive) {
                    store.removeOpenCalling(id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!syncService.canDeleteOpenCallings)
            }
        }
    }

    private func update(_ entry: OpenCalling, _ mutate: (inout OpenCalling) -> Void) {
        var updated = entry
        mutate(&updated)
        store.updateOpenCalling(updated)
    }

    // MARK: - Archive

    private var archivedList: some View {
        List(store.archivedOpenCallings) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.snapshotCallingName ?? "—")
                        .font(.headline)
                    Spacer()
                    if let date = entry.archivedAt {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.snapshotOrganization ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(entry.snapshotPreviousHolder ?? "Vacant")
                    Image(systemName: "arrow.right")
                    Text(entry.snapshotNewHolder ?? "—")
                }
                .font(.subheadline)
            }
            .swipeActions {
                if syncService.canDeleteOpenCallings {
                    Button(role: .destructive) {
                        store.removeOpenCalling(entry.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }
}
