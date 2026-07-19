import SwiftUI

/// One organization's card on the home page: header plus a two-column
/// grid of calling / member name, grouped by subgroup.
struct OrganizationCardView: View {
    @Environment(WardStore.self) private var store
    let organization: OrganizationKind
    @Binding var editingDefinition: CallingDefinition?
    @Binding var pickerSlot: CallingSlot?
    var onDrill: (OrganizationKind) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onDrill(organization)
            } label: {
                HStack {
                    Text(organization.rawValue)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            let slots = store.slots(in: organization)
            let grouped = groupedBySubgroup(slots)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                ForEach(grouped, id: \.subgroup) { group in
                    if let subgroup = group.subgroup {
                        GridRow {
                            Text(CallingDefinition.subgroupDisplayName(subgroup, organization: organization))
                                .font(.caption.smallCaps())
                                .foregroundStyle(.secondary)
                                .gridCellColumns(2)
                                .padding(.top, 4)
                        }
                    }
                    ForEach(group.slots) { slot in
                        CallingRowView(slot: slot, editingDefinition: $editingDefinition, pickerSlot: $pickerSlot)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func groupedBySubgroup(_ slots: [CallingSlot]) -> [(subgroup: String?, slots: [CallingSlot])] {
        var result: [(subgroup: String?, slots: [CallingSlot])] = []
        for slot in slots {
            let subgroup = store.definition(for: slot)?.subgroup
            if let index = result.lastIndex(where: { $0.subgroup == subgroup }) {
                result[index].slots.append(slot)
            } else {
                result.append((subgroup, [slot]))
            }
        }
        return result
    }
}
