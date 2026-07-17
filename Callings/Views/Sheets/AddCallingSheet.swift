import SwiftUI

/// Creates a new calling: pick a group, tap + after the calling it should
/// follow, and name it. The new calling shows in orange until an LCR import
/// confirms it.
struct AddCallingSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Preselected when opened from an organization drill-down.
    var organization: OrganizationKind?

    @State private var selectedOrg: OrganizationKind?
    @State private var anchor: CallingDefinition?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if let org = selectedOrg ?? organization {
                    callingList(for: org)
                } else {
                    groupList
                }
            }
            .navigationTitle("New Calling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    Text("Will be added after \(anchor.name). It shows in orange until the ward clerk adds it in LCR.")
                }
            }
        }
    }

    private var groupList: some View {
        List(OrganizationKind.allCases) { org in
            Button {
                selectedOrg = org
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

    private func callingList(for org: OrganizationKind) -> some View {
        let definitions = store.data.callingDefinitions
            .filter { $0.organization == org }
            .sorted { $0.displayOrder != $1.displayOrder ? $0.displayOrder < $1.displayOrder : $0.name < $1.name }
        return List(definitions) { definition in
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(definition.name)
                        .foregroundStyle(definition.isPending ? Color.orange : Color.primary)
                    if let subgroup = definition.subgroup {
                        Text(subgroup)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    anchor = definition
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Insert a new calling after this one")
            }
        }
        .navigationTitle(org.rawValue)
    }
}
