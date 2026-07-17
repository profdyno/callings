import SwiftUI

/// The Open Callings workflow table: one row per calling being worked,
/// sorted by group then calling display order.
struct OpenCallingsView: View {
    @Environment(WardStore.self) private var store
    @State private var showArchived = false
    @State private var pickerEntry: OpenCalling?
    @State private var editingDefinition: CallingDefinition?
    @State private var checklistCopied = false

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
                    table
                }
            }
            .navigationTitle(showArchived ? "Archived Callings" : "Open Callings")
            .navigationBarTitleDisplayMode(.inline)
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
                if let definition = definition(for: entry) {
                    CandidatePickerSheet(openCallingID: entry.id, definitionID: definition.id)
                }
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

    private func definition(for entry: OpenCalling) -> CallingDefinition? {
        guard let slot = store.slotsByID[entry.slotID] else { return nil }
        return store.definition(for: slot)
    }

    private var table: some View {
        Table(rows) {
            TableColumn("") { row in
                Button(role: .destructive) {
                    store.removeOpenCalling(row.entry.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete this calling change")
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
                    Text(row.callingName)
                        .foregroundStyle(definition(for: row.entry)?.isPending == true ? .orange : .red)
                }
            }
            .width(min: 180, ideal: 280)

            TableColumn("Current (Release)") { row in
                ReleaseStatusCell(currentName: row.currentMember, entry: row.entry) { row.entry }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Assigned (Release)") { row in
                AssignedCell(assigned: row.entry.releaseAssignedTo) { member in
                    update(row.entry) { $0.releaseAssignedTo = member }
                }
            }
            .width(min: 85, ideal: 105)

            TableColumn("Candidates") { row in
                CandidatesCell(entry: row.entry, ensureEntry: { row.entry }, openPicker: { entry in
                    pickerEntry = entry
                })
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
                Button(role: .destructive) {
                    store.removeOpenCalling(entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
