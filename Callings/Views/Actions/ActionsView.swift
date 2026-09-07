import SwiftUI

/// The action checklist as a live table: exactly the data the share button
/// copies as markdown — release/call assignments per bishopric member, a
/// Select Candidate section (rows open the candidate picker), and Ward Clerk
/// LCR bookkeeping.
struct ActionsView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var checklistCopied = false
    @State private var pickerSlotID: UUID?
    @State private var filterStage: StageFilter?
    @State private var filterPerson: BishopricMember?
    @State private var searchText = ""

    private var groups: [ActionChecklistBuilder.Group] {
        ActionChecklistBuilder.groups(from: store)
    }

    private var hasActiveFilters: Bool {
        filterStage != nil || filterPerson != nil
    }

    private func clearFilters() {
        filterStage = nil
        filterPerson = nil
        searchText = ""
    }

    /// The visible checklist: each group's items run through the stage,
    /// person, and search filters; emptied groups drop out. The copy button
    /// exports exactly this.
    private var filteredGroups: [ActionChecklistBuilder.Group] {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        return groups.compactMap { group in
            let items = group.items.filter { matches($0, search: search) }
            return items.isEmpty ? nil : ActionChecklistBuilder.Group(title: group.title, items: items)
        }
    }

    /// Actions rows are one ladder-half each, so the stage buttons match the
    /// row's OWN status (unlike Open Callings, where either ladder counts).
    private func matches(_ item: ActionChecklistBuilder.Item, search: String) -> Bool {
        let entry = item.entryID.flatMap { id in store.data.openCallings.first { $0.id == id } }
        if let filterStage {
            switch item.kind {
            case .release:
                guard entry?.releaseStatus == filterStage.releaseStatus else { return false }
            case .call:
                guard entry?.callStatus == filterStage.callStatus else { return false }
            case .selectCandidate, .clerk:
                return false
            }
        }
        if let filterPerson {
            guard let entry,
                  (entry.releaseAssignedTo ?? .unassigned) == filterPerson || entry.assignedTo == filterPerson
            else { return false }
        }
        guard !search.isEmpty else { return true }
        return (item.member?.localizedCaseInsensitiveContains(search) ?? false)
            || item.calling.localizedCaseInsensitiveContains(search)
            || item.verb.localizedCaseInsensitiveContains(search)
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
                    // Filter bar and table stay mounted even when the filters
                    // match nothing, so there is always a way to clear them.
                    VStack(spacing: 0) {
                        WorkflowFilterBar(stage: $filterStage, person: $filterPerson) {
                            if hasActiveFilters {
                                Button("Clear") { clearFilters() }
                                    .font(.callout)
                            }
                        }
                        Group {
                            if sizeClass == .compact { compactList } else { table }
                        }
                            .overlay {
                                if filteredGroups.isEmpty {
                                    ContentUnavailableView {
                                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                                    } description: {
                                        Text("No actions match these filters.")
                                    } actions: {
                                        Button("Clear Filters") { clearFilters() }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Actions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Member or calling")
            .appToolbar(help: .actions)
            .toolbar {
                Button {
                    UIPasteboard.general.string = ActionChecklistBuilder.markdown(groups: filteredGroups)
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
        filteredGroups.flatMap { [.header($0.title)] + $0.items.map(Line.item) }
    }

    /// iPhone: `Table` shows only its first column in compact width, so the
    /// same four cells stack in a list row instead — and the group titles can
    /// be real section headers here (the iPadOS first-header bug is a Table
    /// problem, not a List one).
    private var compactList: some View {
        List {
            ForEach(filteredGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            CompactRowHeadline(title: item.verb, subtitle: item.calling)
                            LabeledLine("Member", item.member)
                            LabeledLine("Status") { statusCell(item) }
                        }
                        .compactRowLayout()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let slotID = item.slotID { pickerSlotID = slotID }
                        }
                    }
                }
            }
        }
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

    private func entry(for item: ActionChecklistBuilder.Item) -> OpenCalling? {
        item.entryID.flatMap { id in store.data.openCallings.first { $0.id == id } }
    }

    @ViewBuilder
    private func statusCell(_ item: ActionChecklistBuilder.Item) -> some View {
        switch item.kind {
        case .release:
            statusMenu(item, options: ReleaseStatus.allCases, label: \.rawValue,
                       color: entry(for: item)?.releaseStatus.color,
                       canSet: { syncService.canSet(releaseStatus: $0) }) { entry, status in
                entry.releaseStatus = status
            }
        case .call:
            statusMenu(item, options: CallStatus.allCases, label: \.rawValue,
                       color: entry(for: item)?.callStatus.color,
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
        color: Color?,
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
                // Approved and Announced/Sustained are owner (exec secretary) only.
                .disabled(!canSet(status))
            }
        } label: {
            HStack(spacing: 3) {
                Text(item.detail)
                    .foregroundStyle(color ?? .primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
