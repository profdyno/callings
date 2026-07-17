import SwiftUI

/// Filtered candidate picker: members matching the calling's criteria, with
/// name, current calling (blank if none), and an editable category column.
/// Tapping a row toggles the member as a candidate.
struct CandidatePickerSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let openCallingID: UUID
    let definitionID: UUID
    @State private var searchText = ""
    @State private var ignoreCriteria = false
    @State private var editingDefinition: CallingDefinition?

    private var definition: CallingDefinition? { store.definitionsByID[definitionID] }

    private var openEntry: OpenCalling? {
        store.data.openCallings.first { $0.id == openCallingID }
    }

    private var candidates: [Member] {
        var members = ignoreCriteria
            ? store.data.members.filter { $0.isActiveOnRoster && !$0.isPlaceholder }.sorted { $0.name < $1.name }
            : store.candidates(matching: definition?.criteria ?? CandidateCriteria())
        if !searchText.isEmpty {
            members = members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return members
    }

    var body: some View {
        NavigationStack {
            List(candidates) { member in
                candidateRow(member)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingDefinition) { definition in
                CallingEditorSheet(definition: definition)
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

            CategoryMenu(member: member)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.toggleCandidate(member.id, for: openCallingID)
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
