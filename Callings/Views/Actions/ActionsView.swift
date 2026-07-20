import SwiftUI

/// The action checklist as a live table: exactly the data the share button
/// copies as markdown — release/call assignments per bishopric member, a
/// Select Candidate section (rows open the candidate picker), and Ward Clerk
/// LCR bookkeeping.
struct ActionsView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
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
            .appToolbar(help: .actions)
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

    /// Group titles rendered as in-table header rows: iPadOS Table drops the
    /// header of its first Section, so native section headers can't be trusted.
    private enum Line: Identifiable {
        case header(String)
        case item(ActionChecklistBuilder.Item)

        var id: String {
            switch self {
            case .header(let title): return "header-\(title)"
            case .item(let item): return item.id.uuidString
            }
        }

        var item: ActionChecklistBuilder.Item? {
            if case .item(let item) = self { return item }
            return nil
        }
    }

    private var lines: [Line] {
        groups.flatMap { [.header($0.title)] + $0.items.map(Line.item) }
    }

    private var table: some View {
        let lines = lines
        return Table(lines) {
            TableColumn("Action") { line in
                switch line {
                case .header(let title):
                    Text(title)
                        .font(.headline)
                        .padding(.top, 6)
                case .item(let item):
                    Text(item.verb)
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("Member") { line in
                if let item = line.item {
                    Text(item.member ?? "—")
                        .foregroundStyle(item.member == nil ? Color.secondary : Color.primary)
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Calling") { line in
                if let item = line.item {
                    Text(item.calling)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .width(min: 180, ideal: 280)

            TableColumn("Status") { line in
                if let item = line.item {
                    statusCell(item)
                }
            }
            .width(min: 130, ideal: 170)
        }
        .contextMenu(forSelectionType: Line.ID.self) { _ in
        } primaryAction: { ids in
            if let id = ids.first,
               let slotID = lines.first(where: { $0.id == id })?.item?.slotID {
                pickerSlotID = slotID
            }
        }
    }

    // MARK: - Status editing

    @ViewBuilder
    private func statusCell(_ item: ActionChecklistBuilder.Item) -> some View {
        switch item.kind {
        case .release:
            statusMenu(item, options: ReleaseStatus.allCases, label: \.rawValue,
                       canSet: { syncService.canSet(releaseStatus: $0) }) { entry, status in
                entry.releaseStatus = status
            }
        case .call:
            statusMenu(item, options: CallStatus.allCases, label: \.displayName,
                       canSet: { syncService.canSet(callStatus: $0) }) { entry, status in
                entry.callStatus = status
            }
        case .selectCandidate:
            HStack {
                Text(item.detail)
                    .foregroundStyle(.secondary)
                Button("Pick…") { pickerSlotID = item.slotID }
                    .font(.callout)
                    .buttonStyle(.borderless)
            }
        case .clerk:
            Text(item.detail)
                .foregroundStyle(.secondary)
        }
    }

    private func statusMenu<Status: Identifiable>(
        _ item: ActionChecklistBuilder.Item,
        options: [Status],
        label: KeyPath<Status, String>,
        canSet: @escaping (Status) -> Bool,
        apply: @escaping (inout OpenCalling, Status) -> Void
    ) -> some View {
        Menu {
            ForEach(options) { status in
                Button(status[keyPath: label]) {
                    guard var entry = store.data.openCallings.first(where: { $0.id == item.entryID })
                    else { return }
                    apply(&entry, status)
                    store.updateOpenCalling(entry)
                }
                // Announced/Sustained happen in sacrament meeting — owner only.
                .disabled(!canSet(status))
            }
        } label: {
            HStack(spacing: 3) {
                Text(item.detail)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
