import SwiftUI

/// Controls for one open calling: bishopric assignment, release status,
/// member to be called, and call status.
struct StatusMenu: View {
    @Environment(WardStore.self) private var store
    let openCallingID: UUID

    private var entry: OpenCalling? {
        store.data.openCallings.first { $0.id == openCallingID }
    }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Assigned (release)", selection: binding(\.releaseAssignedTo)) {
                    Text(BishopricMember.unassigned.rawValue).tag(BishopricMember?.none)
                    ForEach(BishopricMember.allCases) { member in
                        Text(member.rawValue).tag(BishopricMember?.some(member))
                    }
                }

                Picker("Assigned (call)", selection: binding(\.assignedTo)) {
                    ForEach(BishopricMember.allCases) { member in
                        Text(member.rawValue).tag(member)
                    }
                }

                Picker("Release status", selection: binding(\.releaseStatus)) {
                    ForEach(ReleaseStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }

                Picker("Member to call", selection: binding(\.memberToBeCalledID)) {
                    Text("None").tag(UUID?.none)
                    ForEach(entry.candidateIDs, id: \.self) { id in
                        if let member = store.member(id) {
                            Text(member.name).tag(UUID?.some(id))
                        }
                    }
                }

                Picker("Call status", selection: binding(\.callStatus)) {
                    ForEach(CallStatus.allCases) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<OpenCalling, T>) -> Binding<T> where T: Hashable {
        Binding(
            get: { entry![keyPath: keyPath] },
            set: { newValue in
                guard var updated = entry else { return }
                updated[keyPath: keyPath] = newValue
                // Selecting a member to call implies Selected status.
                if keyPath == \OpenCalling.memberToBeCalledID {
                    if updated.memberToBeCalledID != nil, updated.callStatus == .none {
                        updated.callStatus = .selected
                    }
                }
                store.updateOpenCalling(updated)
            }
        )
    }
}
