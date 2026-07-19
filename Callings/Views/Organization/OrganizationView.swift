import SwiftUI

/// Organization drill-in: every calling in the org as a workflow table —
/// current holder with release status, member to be called with call status,
/// and candidates. Interacting with a row starts its open-calling entry.
struct OrganizationView: View {
    @Environment(WardStore.self) private var store
    let organization: OrganizationKind
    @State private var pickerSlot: CallingSlot?
    @State private var editingDefinition: CallingDefinition?
    @State private var addingCalling = false

    private struct Row: Identifiable {
        let slot: CallingSlot
        let definition: CallingDefinition
        let entry: OpenCalling?
        let currentName: String

        var id: UUID { slot.id }
    }

    private var rows: [Row] {
        store.slots(in: organization).compactMap { slot -> Row? in
            guard let definition = store.definition(for: slot) else { return nil }
            return Row(
                slot: slot,
                definition: definition,
                entry: store.openCalling(forSlot: slot.id),
                currentName: store.member(slot.memberID)?.name ?? slot.holderNameRaw ?? "Vacant"
            )
        }
        // Subgroup display order (EQ/RS: presidency, Ministering, Teachers, rest)
        // with the existing order preserved inside equal ranks.
        .enumerated()
        .sorted { a, b in
            let rankA = CallingDefinition.subgroupRank(a.element.definition.subgroup, organization: organization)
            let rankB = CallingDefinition.subgroupRank(b.element.definition.subgroup, organization: organization)
            return rankA != rankB ? rankA < rankB : a.offset < b.offset
        }
        .map(\.element)
    }

    var body: some View {
        Table(rows) {
            TableColumn("Calling") { row in
                HStack(spacing: 6) {
                    Button {
                        editingDefinition = row.definition
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit criteria and display order")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.definition.nameWithinOrganization)
                            .strikethrough(row.definition.isMarkedForDeletion)
                            .foregroundStyle(
                                row.definition.isMarkedForDeletion ? Color.red
                                : row.definition.isPending ? Color.orange
                                : (row.entry != nil ? Color.red : Color.primary)
                            )
                        if let subgroup = row.definition.subgroup {
                            Text(CallingDefinition.subgroupDisplayName(subgroup, organization: row.definition.organization))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 200, ideal: 300)

            TableColumn("Current (Release)") { row in
                ReleaseStatusCell(currentName: row.currentName, memberID: row.slot.memberID, entry: row.entry) {
                    store.openCallingEntry(for: row.slot)
                }
            }
            .width(min: 150, ideal: 200)

            TableColumn("Assigned (Release)") { row in
                AssignedCell(assigned: row.entry?.releaseAssignedTo) { member in
                    var updated = store.openCallingEntry(for: row.slot)
                    updated.releaseAssignedTo = member
                    store.updateOpenCalling(updated)
                }
            }
            .width(min: 85, ideal: 105)

            TableColumn("Candidates") { row in
                CandidatesCell(entry: row.entry) {
                    pickerSlot = row.slot
                }
            }
            .width(min: 160)

            TableColumn("To Be Called (Status)") { row in
                ToBeCalledCell(entry: row.entry) {
                    store.openCallingEntry(for: row.slot)
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Assigned (Call)") { row in
                AssignedCell(assigned: row.entry?.assignedTo) { member in
                    var updated = store.openCallingEntry(for: row.slot)
                    updated.assignedTo = member
                    store.updateOpenCalling(updated)
                }
            }
            .width(min: 85, ideal: 105)
        }
        .navigationTitle(organization.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                addingCalling = true
            } label: {
                Label("New Calling", systemImage: "plus")
            }
        }
        .sheet(isPresented: $addingCalling) {
            AddCallingSheet(organization: organization)
        }
        .sheet(item: $pickerSlot) { slot in
            CandidatePickerSheet(slotID: slot.id)
        }
        .sheet(item: $editingDefinition) { definition in
            CallingEditorSheet(definition: definition)
        }
    }
}
