import SwiftUI

/// Creates a new calling: pick a group, then its subgroup/class, then tap +
/// after the calling the new one should follow. The name is pre-filled with
/// that calling's name and can be edited. New callings show in orange until
/// an LCR import confirms them.
struct AddCallingSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Preselected when opened from an organization drill-down.
    var organization: OrganizationKind?

    @State private var selectedOrg: OrganizationKind?
    @State private var selectedSubgroup: SubgroupChoice?
    @State private var anchor: CallingDefinition?
    @State private var newName = ""

    /// A subgroup within the chosen org (nil = callings with no subgroup).
    struct SubgroupChoice: Hashable, Identifiable {
        let subgroup: String?
        var id: String { subgroup ?? "—" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let org = selectedOrg ?? organization {
                    if let choice = selectedSubgroup {
                        callingList(for: org, subgroup: choice.subgroup)
                    } else {
                        subgroupList(for: org)
                    }
                } else {
                    groupList
                }
            }
            .navigationTitle("New Calling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: .addCalling)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("New Calling", isPresented: Binding(
                get: { anchor != nil },
                set: { if !$0 { anchor = nil } }
            )) {
                TextField("Calling name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Add") {
                    if let anchor, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.createCalling(named: newName.trimmingCharacters(in: .whitespaces), after: anchor)
                    }
                    newName = ""
                    dismiss()
                }
            } message: {
                if let anchor {
                    Text("Added after \(anchor.name) in \(subgroupTitle(selectedSubgroup?.subgroup, org: anchor.organization)). It shows in orange until the ward clerk adds it in LCR.")
                }
            }
        }
    }

    private var groupList: some View {
        List(OrganizationKind.allCases) { org in
            Button {
                selectedOrg = org
                let subgroups = subgroupChoices(for: org)
                // Orgs without subgroups skip straight to the callings.
                if subgroups.count == 1, subgroups[0].subgroup == nil {
                    selectedSubgroup = subgroups[0]
                }
            } label: {
                HStack {
                    Text(org.rawValue)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func subgroupChoices(for org: OrganizationKind) -> [SubgroupChoice] {
        var seen = Set<String?>()
        var choices: [SubgroupChoice] = []
        for slot in store.slots(in: org) {
            let subgroup = store.definition(for: slot)?.subgroup
            if seen.insert(subgroup).inserted {
                choices.append(SubgroupChoice(subgroup: subgroup))
            }
        }
        return choices
    }

    private func subgroupTitle(_ subgroup: String?, org: OrganizationKind) -> String {
        subgroup.map { CallingDefinition.subgroupDisplayName($0, organization: org) } ?? org.rawValue
    }

    private func subgroupList(for org: OrganizationKind) -> some View {
        List(subgroupChoices(for: org)) { choice in
            Button {
                selectedSubgroup = choice
            } label: {
                HStack {
                    Text(subgroupTitle(choice.subgroup, org: org))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(org.rawValue)
    }

    private func callingList(for org: OrganizationKind, subgroup: String?) -> some View {
        let definitions = store.data.callingDefinitions
            .filter { $0.organization == org && $0.subgroup == subgroup }
            .sorted { $0.displayOrder != $1.displayOrder ? $0.displayOrder < $1.displayOrder : $0.name < $1.name }
        return List(definitions) { definition in
            HStack {
                Text(definition.name)
                    .foregroundStyle(definition.isPending ? Color.orange : Color.primary)
                Spacer()
                Button {
                    newName = definition.name
                    anchor = definition
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Insert a new calling after this one")
            }
        }
        .navigationTitle(subgroupTitle(subgroup, org: org))
    }
}
