import SwiftUI

/// Shows what an import will change before it is applied.
struct ImportPreviewView: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pending: PendingImport

    var body: some View {
        NavigationStack {
            Form {
                switch pending.kind {
                case .memberList:
                    Section("Roster Changes") {
                        LabeledContent("Members added", value: "\(pending.summary.membersAdded)")
                        LabeledContent("Members updated", value: "\(pending.summary.membersUpdated)")
                        LabeledContent("Members deactivated", value: "\(pending.summary.membersDeactivated)")
                    }
                case .wardCallings:
                    Section("Organization Changes") {
                        LabeledContent("Callings imported", value: "\(pending.summary.slotsImported)")
                        LabeledContent("Vacant callings", value: "\(pending.summary.vacantSlots)")
                        LabeledContent("New calling types", value: "\(pending.summary.definitionsCreated)")
                    }
                    if !pending.summary.openCallingsArchived.isEmpty {
                        Section("Open Callings Completed (will be archived)") {
                            ForEach(pending.summary.openCallingsArchived, id: \.self) { name in
                                Label(name, systemImage: "archivebox")
                            }
                        }
                    }
                    if !pending.summary.placeholdersCreated.isEmpty {
                        Section {
                            ForEach(pending.summary.placeholdersCreated, id: \.self) { name in
                                Label(name, systemImage: "person.crop.circle.badge.questionmark")
                            }
                        } header: {
                            Text("Holders Not on the Roster")
                        } footer: {
                            Text("These calling holders were not found in the member list (often out-of-unit callings). They are kept as placeholder members.")
                        }
                    }
                }

                if !pending.summary.countMismatches.isEmpty {
                    Section("Warnings") {
                        ForEach(pending.summary.countMismatches, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle(pending.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        store.apply(pending.newData)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
