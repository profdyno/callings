import SwiftUI

/// Members directory: every active member in a single searchable table with
/// their class assignments, callings, and tag. Row tap opens the member
/// detail sheet; the tag icon manages the shared tag list.
struct MembersView: View {
    @Environment(WardStore.self) private var store
    @State private var searchText = ""
    @State private var detailMemberID: UUID?
    @State private var managingTags = false

    private struct Row: Identifiable {
        let member: Member
        let classes: String
        let callings: String
        var id: UUID { member.id }
    }

    private var rows: [Row] {
        let search = searchText.trimmingCharacters(in: .whitespaces)
        return store.data.members
            .filter(\.isActiveOnRoster)
            .sorted { $0.name < $1.name }
            .map { member in
                Row(
                    member: member,
                    classes: member.classAssignments.joined(separator: ", "),
                    callings: store.slots(heldBy: member.id)
                        .compactMap { store.definition(for: $0)?.name }
                        .joined(separator: ", ")
                )
            }
            .filter { row in
                guard !search.isEmpty else { return true }
                return row.member.name.localizedCaseInsensitiveContains(search)
                    || row.classes.localizedCaseInsensitiveContains(search)
                    || row.member.category.label.localizedCaseInsensitiveContains(search)
            }
    }

    var body: some View {
        NavigationStack {
            Table(rows) {
                TableColumn("Name") { row in
                    Button {
                        detailMemberID = row.member.id
                    } label: {
                        Text(row.member.name)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .width(min: 150, ideal: 190)

                TableColumn("Gender") { row in
                    Text(row.member.gender.map(\.rawValue) ?? "—")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Age") { row in
                    Text(row.member.age.map(String.init) ?? "—")
                }
                .width(min: 40, ideal: 50)

                TableColumn("Class") { row in
                    Text(row.classes)
                        .font(.callout)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Callings") { row in
                    Text(row.callings)
                        .font(.callout)
                        .foregroundStyle(row.callings.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .width(min: 170, ideal: 260)

                TableColumn("Tag") { row in
                    CategoryMenu(member: row.member)
                }
                .width(min: 90, ideal: 120)
            }
            .searchable(text: $searchText, prompt: "Name, class, or tag")
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar(help: .members)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        managingTags = true
                    } label: {
                        Label("Manage Tags", systemImage: "tag")
                    }
                }
            }
            .sheet(item: $detailMemberID) { memberID in
                MemberDetailSheet(memberID: memberID)
            }
            .sheet(isPresented: $managingTags) {
                TagManagerSheet()
            }
        }
    }
}

/// Manage the shared member-tag list: built-in tags are fixed; custom tags
/// can be added and deleted (deleting clears the tag from every member).
struct TagManagerSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""
    @State private var deletingTag: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Built-in Tags") {
                    ForEach(MemberCategory.standardCases.filter { $0 != .none }, id: \.label) { category in
                        Text(category.label)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(store.data.customTags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            let count = store.memberCount(withTag: tag)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                deletingTag = tag
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }
                    HStack {
                        TextField("New tag", text: $newTag)
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Custom Tags")
                } footer: {
                    Text("Tags are shared with everyone on the ward. Deleting a tag removes it from all members.")
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: .tagManager)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                deletingTag.map { tag in
                    let count = store.memberCount(withTag: tag)
                    return count > 0
                        ? "Delete “\(tag)”? It will be removed from \(count) member\(count == 1 ? "" : "s")."
                        : "Delete “\(tag)”?"
                } ?? "",
                isPresented: Binding(
                    get: { deletingTag != nil },
                    set: { if !$0 { deletingTag = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Tag", role: .destructive) {
                    if let tag = deletingTag { store.deleteTag(tag) }
                }
            }
        }
    }

    private func addTag() {
        store.addTag(newTag)
        newTag = ""
    }
}
