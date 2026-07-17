import SwiftUI

/// Candidates for one calling. Drop target for member drags; tap opens the
/// filtered candidate picker.
struct CandidatesColumnView: View {
    @Environment(WardStore.self) private var store
    let slotID: UUID
    @Binding var showingPicker: Bool
    @State private var isTargeted = false

    private var openEntry: OpenCalling? { store.openCalling(forSlot: slotID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Candidates")
                    .font(.headline)
                Spacer()
                Button {
                    if openEntry == nil, let slot = store.slotsByID[slotID] {
                        store.openCallingEntry(for: slot)
                    }
                    showingPicker = true
                } label: {
                    Image(systemName: "plus.circle")
                }
            }

            if let entry = openEntry, !entry.candidateIDs.isEmpty {
                List {
                    ForEach(entry.candidateIDs, id: \.self) { memberID in
                        if let member = store.member(memberID) {
                            MemberRowView(member: member, showTenure: true)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.toggleCandidate(memberID, for: entry.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView {
                    Label("No Candidates", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text("Drag members here or tap + to pick from the filtered list.")
                }
            }
        }
        .padding(10)
        .background(
            isTargeted ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .dropDestination(for: Member.self) { members, _ in
            guard let slot = store.slotsByID[slotID] else { return false }
            let entry = store.openCallingEntry(for: slot)
            for member in members {
                store.addCandidate(member.id, for: entry.id)
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}
