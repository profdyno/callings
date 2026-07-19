import SwiftUI

/// Filtered candidate picker: members matching the calling's criteria, with
/// name, current calling (blank if none), and an editable category column.
/// Tapping a row toggles the member as a candidate.
///
/// The open-calling entry is created lazily on the FIRST candidate selection:
/// opening and closing the picker without picking anyone does not initiate a
/// calling change (and doesn't turn the calling red).
struct CandidatePickerSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slotID: UUID
    @State private var searchText = ""
    @State private var ignoreCriteria = false
    @State private var editingDefinition: CallingDefinition?
    @State private var createdEntryID: UUID?
    @State private var detailMemberID: UUID?

    private var slot: CallingSlot? { store.slotsByID[slotID] }
    private var definition: CallingDefinition? { slot.flatMap { store.definition(for: $0) } }
    private var openEntry: OpenCalling? { store.openCalling(forSlot: slotID) }

    private var currentCandidates: [Member] {
        (openEntry?.candidateIDs ?? []).compactMap { store.member($0) }
    }

    private var candidates: [Member] {
        var members = ignoreCriteria
            ? store.data.members.filter { $0.isActiveOnRoster && !$0.isPlaceholder }.sorted { $0.name < $1.name }
            : store.candidates(matching: definition?.criteria ?? CandidateCriteria())
        let selected = Set(openEntry?.candidateIDs ?? [])
        members = members.filter { !selected.contains($0.id) }
        if !searchText.isEmpty {
            members = members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return members
    }

    var body: some View {
        NavigationStack {
            List {
                if !currentCandidates.isEmpty {
                    Section("Current Candidates") {
                        ForEach(currentCandidates) { member in
                            candidateRow(member)
                        }
                    }
                }
                Section(currentCandidates.isEmpty ? "" : "Add Candidates") {
                    ForEach(candidates) { member in
                        candidateRow(member)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search members")
            .navigationTitle(definition.map { "Candidates — \($0.name)" } ?? "Select Candidates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Toggle("All Members", isOn: $ignoreCriteria)
                    Button {
                        editingDefinition = definition
                    } label: {
                        Label("Edit Criteria", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Start the calling change with no candidate chosen.
                    if openEntry == nil {
                        Button("Start as TBD") {
                            if let slot {
                                store.openCallingEntry(for: slot)
                                createdEntryID = nil  // survives the empty-entry cleanup
                            }
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
            }
            .sheet(item: $detailMemberID) { memberID in
                MemberDetailSheet(memberID: memberID)
            }
        }
        .onDisappear {
            // If this picker session created the entry but ended with no
            // candidates, no calling change was initiated — remove it.
            if let id = createdEntryID,
               let entry = store.data.openCallings.first(where: { $0.id == id }),
               !entry.isArchived, entry.candidateIDs.isEmpty {
                store.removeOpenCalling(id)
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ member: Member) -> some View {
        let isSelected = openEntry?.candidateIDs.contains(member.id) ?? false
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(member.name)
                let callings = store.slots(heldBy: member.id)
                    .compactMap { store.definition(for: $0)?.name }
                if !callings.isEmpty {
                    Text(callings.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            Button {
                detailMemberID = member.id
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            CategoryMenu(member: member)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggle(member)
        }
    }

    private func toggle(_ member: Member) {
        if let entry = openEntry {
            store.toggleCandidate(member.id, for: entry.id)
        } else if let slot {
            let entry = store.openCallingEntry(for: slot)
            store.addCandidate(member.id, for: entry.id)
            createdEntryID = entry.id
        }
    }
}

/// Editable member-category chip (blank, Not Active, Moving Soon, …).
struct CategoryMenu: View {
    @Environment(WardStore.self) private var store
    let member: Member

    var body: some View {
        Menu {
            ForEach(MemberCategory.standardCases, id: \.label) { category in
                Button(category == .none ? "Clear" : category.label) {
                    store.setCategory(category, forMember: member.id)
                }
            }
        } label: {
            Text(member.category == .none ? "—" : member.category.label)
                .font(.caption)
                .foregroundStyle(member.category == .none ? .secondary : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }
}
