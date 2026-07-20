import SwiftUI

/// Long-press editor for a calling: candidate criteria and display sequence.
struct CallingEditorSheet: View {
    @Environment(WardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var definition: CallingDefinition
    @State private var confirmingDelete = false

    private let knownClasses = [
        "Gatherers of Light", "Messengers of Hope", "Builders of Faith",
        "Priests Quorum", "Teachers Quorum", "Deacons Quorum",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Stepper(value: $definition.displayOrder, in: 0...200, step: 5) {
                        LabeledContent("Display sequence", value: String(format: "%g", definition.displayOrder))
                    }
                    Text("Lower numbers sort first (President 0, 1st Counselor 10, 2nd Counselor 20, Secretary 30…).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Candidate Criteria") {
                    Picker("Gender", selection: $definition.criteria.gender) {
                        Text("Any").tag(Gender?.none)
                        Text("Male").tag(Gender?.some(.male))
                        Text("Female").tag(Gender?.some(.female))
                    }
                    Picker("Minimum priesthood", selection: $definition.criteria.minimumPriesthood) {
                        Text("None").tag(PriesthoodTrack?.none)
                        Text("Aaronic").tag(PriesthoodTrack?.some(.aaronic))
                        Text("Melchizedek").tag(PriesthoodTrack?.some(.melchizedek))
                    }
                    agePicker("Minimum age", selection: $definition.criteria.minAge)
                    agePicker("Maximum age", selection: $definition.criteria.maxAge)
                    Toggle("Allow members who already have a calling", isOn: $definition.criteria.allowMultipleCallings)
                }

                Section {
                    if definition.isMarkedForDeletion {
                        Button("Cancel Deletion") {
                            store.cancelDeletion(of: definition)
                            dismiss()
                        }
                    } else {
                        Button("Delete Calling…", role: .destructive) {
                            confirmingDelete = true
                        }
                    }
                } footer: {
                    if !definition.isMarkedForDeletion {
                        Text(definition.isPending
                             ? "This calling was created in the app and hasn't been added to LCR — deleting removes it immediately."
                             : "This calling exists in LCR. Deleting marks it in red with a strikethrough and adds a ward-clerk action; it's removed for good when a future import no longer contains it. The current holder, if any, is added to Open Callings for release.")
                        .font(.caption)
                    }
                }

                Section("Required Class / Quorum") {
                    ForEach(knownClasses, id: \.self) { className in
                        let isOn = definition.criteria.requiredClassAssignments.contains(className)
                        Button {
                            if isOn {
                                definition.criteria.requiredClassAssignments.removeAll { $0 == className }
                            } else {
                                definition.criteria.requiredClassAssignments.append(className)
                            }
                        } label: {
                            HStack {
                                Text(className)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isOn { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if definition.criteria.requiredClassAssignments.isEmpty {
                        Text("No class requirement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(definition.name)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                definition.isPending ? "Delete \(definition.name)?" : "Delete \(definition.name) from the ward organization?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Calling", role: .destructive) {
                    store.requestDeletion(of: definition)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: .callingEditor)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateDefinition(definition)
                        dismiss()
                    }
                }
            }
        }
    }

    private func agePicker(_ label: String, selection: Binding<Int?>) -> some View {
        Picker(label, selection: selection) {
            Text("Any").tag(Int?.none)
            ForEach([11, 12, 14, 16, 18, 19, 25, 31, 40], id: \.self) { age in
                Text("\(age)").tag(Int?.some(age))
            }
        }
    }
}
