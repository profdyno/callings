import SwiftUI

/// The Open Callings workflow table: one row per calling being worked,
/// sorted by group then calling display order.
struct OpenCallingsView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    @State private var showArchived = false
    @State private var pickerEntry: OpenCalling?
    @State private var editingDefinition: CallingDefinition?
    @State private var checklistCopied = false
    // Column filters (nil = all)
    @State private var filterOrganization: OrganizationKind?
    @State private var filterReleaseStatus: ReleaseStatus?
    @State private var filterCallStatus: CallStatus?
    @State private var filterReleaseAssignee: BishopricMember?
    @State private var filterCallAssignee: BishopricMember?

    private var hasActiveFilters: Bool {
        filterOrganization != nil || filterReleaseStatus != nil || filterCallStatus != nil
            || filterReleaseAssignee != nil || filterCallAssignee != nil
    }

    private func clearFilters() {
        filterOrganization = nil
        filterReleaseStatus = nil
        filterCallStatus = nil
        filterReleaseAssignee = nil
        filterCallAssignee = nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if showArchived {
                    archivedList
                } else if rows.isEmpty {
                    ContentUnavailableView(
                        "No Open Callings",
                        systemImage: "rectangle.stack",
                        description: Text("Tap a calling on the Ward Callings page (or long-press it) to start a release/call.")
                    )
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        table
                    }
                }
            }
            .navigationTitle(showArchived ? "Archived Callings" : "Open Callings")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar()
            .toolbar {
                Button {
                    UIPasteboard.general.string = ActionChecklistBuilder.markdown(from: store)
                    checklistCopied = true
                } label: {
                    Label("Copy Action Checklist", systemImage: "square.and.arrow.up")
                }
                Toggle(isOn: $showArchived) {
                    Label("Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
            }
            .alert("Checklist Copied", isPresented: $checklistCopied) {
                Button("OK") {}
            } message: {
                Text("The action checklist is on the clipboard as markdown — paste it into Notes, a message, or an email.")
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
            if let filterReleaseStatus, row.entry.releaseStatus != filterReleaseStatus { return false }
            if let filterCallStatus, row.entry.callStatus != filterCallStatus { return false }
            if let filterReleaseAssignee, (row.entry.releaseAssignedTo ?? .unassigned) != filterReleaseAssignee { return false }
            if let filterCallAssignee, row.entry.assignedTo != filterCallAssignee { return false }
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

    /// Compact per-column filters above the table.
    private var filterBar: some View {
        HStack(spacing: 10) {
            filterMenu("Group", selection: $filterOrganization, options: OrganizationKind.allCases) { $0.rawValue }
            filterMenu("Release", selection: $filterReleaseStatus, options: ReleaseStatus.allCases) { $0.rawValue }
            filterMenu("Call Status", selection: $filterCallStatus, options: CallStatus.allCases) { $0.rawValue }
            filterMenu("Assigned (R)", selection: $filterReleaseAssignee, options: BishopricMember.allCases) { $0.rawValue }
            filterMenu("Assigned (C)", selection: $filterCallAssignee, options: BishopricMember.allCases) { $0.rawValue }
            if hasActiveFilters {
                Button("Clear") { clearFilters() }
                    .font(.callout)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
                Text(row.organization.rawValue)
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
