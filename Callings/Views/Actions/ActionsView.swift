import SwiftUI

/// The action checklist as a live table: exactly the data the share button
/// copies as markdown — release/call assignments per bishopric member, a
/// Select Candidate section (rows open the candidate picker), and Ward Clerk
/// LCR bookkeeping.
struct ActionsView: View {
    @Environment(WardStore.self) private var store
    @State private var checklistCopied = false
    @State private var pickerSlotID: UUID?

    private var groups: [ActionChecklistBuilder.Group] {
        ActionChecklistBuilder.groups(from: store)
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No Actions",
                        systemImage: "checklist",
                        description: Text("Releases, calls, and LCR updates that need attention will appear here.")
                    )
                } else {
                    table
                }
            }
            .navigationTitle("Actions")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar()
            .toolbar {
                Button {
                    UIPasteboard.general.string = ActionChecklistBuilder.markdown(from: store)
                    checklistCopied = true
                } label: {
                    Label("Copy Action Checklist", systemImage: "square.and.arrow.up")
                }
            }
            .alert("Checklist Copied", isPresented: $checklistCopied) {
                Button("OK") {}
            } message: {
                Text("The action checklist is on the clipboard as markdown — paste it into Notes, a message, or an email.")
            }
            .sheet(item: $pickerSlotID) { slotID in
                CandidatePickerSheet(slotID: slotID)
            }
        }
    }

    private var itemsByID: [UUID: ActionChecklistBuilder.Item] {
        Dictionary(uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.id, $0) })
    }

    private var table: some View {
        Table(of: ActionChecklistBuilder.Item.self) {
            TableColumn("Action") { item in
                Text(item.verb)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Member") { item in
                Text(item.member ?? "—")
                    .foregroundStyle(item.member == nil ? Color.secondary : Color.primary)
            }
            .width(min: 150, ideal: 190)

            TableColumn("Calling") { item in
                Text(item.calling)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Status") { item in
                HStack {
                    Text(item.detail)
                        .foregroundStyle(.secondary)
                    if item.slotID != nil {
                        Button("Pick…") { pickerSlotID = item.slotID }
                            .font(.callout)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .width(min: 130, ideal: 170)
        } rows: {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        TableRow(item)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: ActionChecklistBuilder.Item.ID.self) { _ in
        } primaryAction: { ids in
            if let id = ids.first, let slotID = itemsByID[id]?.slotID {
                pickerSlotID = slotID
            }
        }
    }
}
