import SwiftUI

/// The Open Callings workflow table: one row per calling being worked,
/// sorted by group then calling display order.
struct OpenCallingsView: View {
    @Environment(WardStore.self) private var store
    @State private var showArchived = false
    @State private var pickerEntry: OpenCalling?

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
                Toggle(isOn: $showArchived) {
                    Label("Archived", systemImage: "archivebox")
                }
                .toggleStyle(.button)
            }
            .sheet(item: $pickerEntry) { entry in
                if let criteria = criteria(for: entry) {
                    CandidatePickerSheet(openCallingID: entry.id, criteria: criteria)
                }
            }
        }
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let entry: OpenCalling
        let organization: OrganizationKind
        let displayOrder: Int
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

    private func criteria(for entry: OpenCalling) -> CandidateCriteria? {
        guard let slot = store.slotsByID[entry.slotID] else { return nil }
        return store.definition(for: slot)?.criteria
    }

    private var table: some View {
        Table(rows) {
            TableColumn("Assigned") { row in
                Menu {
                    ForEach(BishopricMember.allCases) { member in
                        Button(member.rawValue) { update(row.entry) { $0.assignedTo = member } }
                    }
                } label: {
                    Text(row.entry.assignedTo == .unassigned ? "—" : row.entry.assignedTo.rawValue)
                        .foregroundStyle(row.entry.assignedTo == .unassigned ? .secondary : .primary)
                }
            }
            .width(min: 90, ideal: 110)

            TableColumn("Group") { row in
                Text(row.organization.rawValue)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Calling") { row in
                Text(row.callingName)
                    .foregroundStyle(.red)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Current (Release)") { row in
                Menu {
                    ForEach(ReleaseStatus.allCases) { status in
                        Button(status.rawValue) { update(row.entry) { $0.releaseStatus = status } }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.currentMember)
                            .foregroundStyle(row.entry.releaseStatus.color ?? .primary)
                        if row.entry.releaseStatus != .none {
                            Text(row.entry.releaseStatus.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 150, ideal: 220)

            TableColumn("To Be Called (Status)") { row in
                Menu {
                    Section("Member to call") {
                        Button("None") { update(row.entry) { $0.memberToBeCalledID = nil; $0.callStatus = .none } }
                        ForEach(row.entry.candidateIDs, id: \.self) { id in
                            if let member = store.member(id) {
                                Button(member.name) {
                                    update(row.entry) {
                                        $0.memberToBeCalledID = id
                                        if $0.callStatus == .none { $0.callStatus = .selected }
                                    }
                                }
                            }
                        }
                    }
                    Section("Status") {
                        ForEach(CallStatus.allCases) { status in
                            Button(status.rawValue) { update(row.entry) { $0.callStatus = status } }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.newMember)
                            .foregroundStyle(row.entry.callStatus.color ?? .primary)
                        if row.entry.callStatus != .none {
                            Text(row.entry.callStatus.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Candidates") { row in
                Button {
                    pickerEntry = row.entry
                } label: {
                    Text(row.candidates.isEmpty ? "Add…" : row.candidates)
                        .foregroundStyle(row.candidates.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            }
            .width(min: 160)
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
