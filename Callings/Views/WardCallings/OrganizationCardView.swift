import SwiftUI

/// A home-board group: a real organization, or the virtual Activities
/// Committee group carved out of Other Callings for display.
enum HomeGroup: Hashable, Identifiable {
    case org(OrganizationKind)
    case activitiesCommittee

    var id: String {
        switch self {
        case .org(let organization): return organization.rawValue
        case .activitiesCommittee: return "ActivitiesCommittee"
        }
    }

    var title: String {
        switch self {
        case .org(let organization): return organization.rawValue
        case .activitiesCommittee: return "Activities Committee"
        }
    }

    /// The data organization backing this group (drill target, subgroup names).
    var organization: OrganizationKind {
        switch self {
        case .org(let organization): return organization
        case .activitiesCommittee: return .otherCallings
        }
    }

    /// The seats belonging to this group. Activities Committee is carved out
    /// of Other Callings, so the two split the same organization.
    @MainActor
    func slots(in store: WardStore) -> [CallingSlot] {
        let all = store.slots(in: organization)
        switch self {
        case .activitiesCommittee:
            return all.filter { store.definition(for: $0)?.isActivitiesCommittee == true }
        case .org(.otherCallings):
            return all.filter { store.definition(for: $0)?.isActivitiesCommittee != true }
        case .org:
            return all
        }
    }

    /// Whether subgroup headings are meaningful for this group.
    var showsSubgroups: Bool {
        if case .activitiesCommittee = self { return false }
        return true
    }

    /// Sections in subgroup display order (EQ/RS: presidency, Ministering,
    /// Teachers, then the imported order — stable for equal ranks).
    @MainActor
    func sections(in store: WardStore) -> [(subgroup: String?, slots: [CallingSlot])] {
        var sections: [(subgroup: String?, slots: [CallingSlot])] = []
        for slot in slots(in: store) {
            let subgroup = store.definition(for: slot)?.subgroup
            if let index = sections.lastIndex(where: { $0.subgroup == subgroup }) {
                sections[index].slots.append(slot)
            } else {
                sections.append((subgroup, [slot]))
            }
        }
        return sections
            .enumerated()
            .sorted { a, b in
                let rankA = CallingDefinition.subgroupRank(a.element.subgroup, organization: organization)
                let rankB = CallingDefinition.subgroupRank(b.element.subgroup, organization: organization)
                return rankA != rankB ? rankA < rankB : a.offset < b.offset
            }
            .map(\.element)
    }
}

/// One group's card on the home board: header plus a two-column grid of
/// calling / member name, sectioned by subgroup.
struct OrganizationCardView: View {
    @Environment(WardStore.self) private var store
    let group: HomeGroup
    @Binding var editingDefinition: CallingDefinition?
    @Binding var pickerSlot: CallingSlot?
    @Binding var detailMemberID: UUID?
    var onDrill: (OrganizationKind) -> Void = { _ in }


    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onDrill(group.organization)
            } label: {
                HStack {
                    Text(group.title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(group.sections(in: store), id: \.subgroup) { section in
                    if group.showsSubgroups, let subgroup = section.subgroup {
                        GridRow {
                            Text(CallingDefinition.subgroupDisplayName(subgroup, organization: group.organization))
                                .font(.caption.smallCaps())
                                .foregroundStyle(.secondary)
                                .gridCellColumns(2)
                                .padding(.top, 4)
                        }
                    }
                    ForEach(section.slots) { slot in
                        CallingRowView(
                            slot: slot,
                            editingDefinition: $editingDefinition,
                            pickerSlot: $pickerSlot,
                            detailMemberID: $detailMemberID
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
