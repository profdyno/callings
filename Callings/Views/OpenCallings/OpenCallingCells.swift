import SwiftUI

/// Interactive table cells shared by the Open Callings table and the
/// organization drill-in table. Cells that mutate the workflow accept an
/// `ensureEntry` closure so a row without an open entry starts one on first
/// interaction.

/// Current holder with the release-status ladder (Open → Released → Announced).
struct ReleaseStatusCell: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    let currentName: String
    var memberID: UUID?
    let entry: OpenCalling?
    let ensureEntry: () -> OpenCalling
    @State private var detailMemberID: UUID?

    var body: some View {
        Menu {
            ForEach(ReleaseStatus.allCases) { status in
                Button(status.rawValue) {
                    var updated = ensureEntry()
                    updated.releaseStatus = status
                    store.updateOpenCalling(updated)
                }
                // Announced happens in sacrament meeting — owner only.
                .disabled(!syncService.canSet(releaseStatus: status))
            }
            if let memberID {
                Divider()
                Button {
                    detailMemberID = memberID
                } label: {
                    Label("Member Details…", systemImage: "person.crop.circle")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(currentName)
                    .foregroundStyle(entry?.releaseStatus.color ?? .primary)
                if let status = entry?.releaseStatus, status != .none {
                    Text(status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $detailMemberID) { memberID in
            MemberDetailSheet(memberID: memberID)
        }
    }
}

/// Member to be called: pick from the entry's candidates, then walk the
/// call-status ladder (Selected → Accepted → Sustained).
struct ToBeCalledCell: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    let entry: OpenCalling?
    let ensureEntry: () -> OpenCalling
    @State private var detailMemberID: UUID?

    var body: some View {
        Menu {
            if let selectedID = entry?.memberToBeCalledID {
                Button {
                    detailMemberID = selectedID
                } label: {
                    Label("Member Details…", systemImage: "person.crop.circle")
                }
                Divider()
            }
            if let entry, !entry.candidateIDs.isEmpty {
                Section("Member to call") {
                    Button("None") {
                        var updated = ensureEntry()
                        updated.memberToBeCalledID = nil
                        updated.callStatus = .none
                        store.updateOpenCalling(updated)
                    }
                    ForEach(entry.candidateIDs, id: \.self) { id in
                        if let member = store.member(id) {
                            Button(member.name) {
                                var updated = ensureEntry()
                                updated.memberToBeCalledID = id
                                if updated.callStatus == .none { updated.callStatus = .selected }
                                store.updateOpenCalling(updated)
                            }
                        }
                    }
                }
                Section("Status") {
                    ForEach(CallStatus.allCases) { status in
                        Button(status.rawValue) {
                            var updated = ensureEntry()
                            updated.callStatus = status
                            store.updateOpenCalling(updated)
                        }
                        // Sustained happens in sacrament meeting — owner only.
                        .disabled(!syncService.canSet(callStatus: status))
                    }
                }
            } else {
                Text("Add candidates first")
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.member(entry?.memberToBeCalledID)?.name ?? "—")
                    .foregroundStyle(entry?.callStatus.color ?? .primary)
                if let status = entry?.callStatus, status != .none {
                    Text(status.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(item: $detailMemberID) { memberID in
            MemberDetailSheet(memberID: memberID)
        }
    }
}

/// Bishopric-member assignment dropdown (used for both the release and the
/// call assignment columns).
struct AssignedCell: View {
    let assigned: BishopricMember?
    let onSelect: (BishopricMember) -> Void

    var body: some View {
        Menu {
            ForEach(BishopricMember.allCases) { member in
                Button(member.rawValue) { onSelect(member) }
            }
        } label: {
            let value = assigned ?? .unassigned
            Text(value == .unassigned ? "—" : value.rawValue)
                .foregroundStyle(value == .unassigned ? .secondary : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// Candidate names; tapping opens the candidate picker. The picker itself
/// creates the open-calling entry only when a candidate is actually selected.
struct CandidatesCell: View {
    @Environment(WardStore.self) private var store
    let entry: OpenCalling?
    let openPicker: () -> Void

    var body: some View {
        Button {
            openPicker()
        } label: {
            let names = (entry?.candidateIDs ?? []).compactMap { store.member($0)?.displayName }
            Text(names.isEmpty ? "Add…" : names.joined(separator: ", "))
                .foregroundStyle(names.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
    }
}
