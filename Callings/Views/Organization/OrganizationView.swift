import SwiftUI

/// Organization drill-in: every calling in the org (each row a drop target
/// for candidates), plus the two member columns for drag sources.
struct OrganizationView: View {
    @Environment(WardStore.self) private var store
    let organization: OrganizationKind

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.slots(in: organization)) { slot in
                        OrganizationCallingRow(slot: slot)
                        Divider()
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            MemberColumnView(mode: .needCallings)
                .frame(width: 280)
            MemberColumnView(mode: .withCallings)
                .frame(width: 300)
        }
        .padding(12)
        .navigationTitle(organization.rawValue)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A calling row inside the organization view. Dropping a member on it adds
/// them as a candidate (creating the open-calling entry when needed).
private struct OrganizationCallingRow: View {
    @Environment(WardStore.self) private var store
    let slot: CallingSlot
    @State private var isTargeted = false

    private var openEntry: OpenCalling? { store.openCalling(forSlot: slot.id) }

    var body: some View {
        NavigationLink(value: slot) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(store.definition(for: slot)?.nameWithinOrganization ?? "—")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(openEntry != nil ? Color.red : Color.primary)
                    Spacer()
                    Text(store.member(slot.memberID)?.name ?? slot.holderNameRaw ?? "Vacant")
                        .font(.subheadline)
                        .foregroundStyle(slot.memberID == nil && slot.holderNameRaw == nil ? .secondary : .primary)
                }
                if let entry = openEntry, !entry.candidateIDs.isEmpty {
                    Text("Candidates: " + entry.candidateIDs.compactMap { store.member($0)?.displayName }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isTargeted ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .dropDestination(for: Member.self) { members, _ in
            let entry = store.openCallingEntry(for: slot)
            for member in members {
                store.addCandidate(member.id, for: entry.id)
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}
