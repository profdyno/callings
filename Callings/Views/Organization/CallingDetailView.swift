import SwiftUI

/// Single-calling drill-in: calling info and actions, candidates (drop
/// target), members needing callings, and members with callings.
struct CallingDetailView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    let slotID: UUID
    @State private var showingPicker = false
    @State private var editingDefinition: CallingDefinition?

    private var slot: CallingSlot? { store.slotsByID[slotID] }
    private var definition: CallingDefinition? { slot.flatMap { store.definition(for: $0) } }
    private var openEntry: OpenCalling? { store.openCalling(forSlot: slotID) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            infoColumn
                .frame(width: 300)
            CandidatesColumnView(slotID: slotID, showingPicker: $showingPicker)
                .frame(maxWidth: .infinity)
            MemberColumnView(mode: .needCallings)
                .frame(maxWidth: .infinity)
            MemberColumnView(mode: .withCallings)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .navigationTitle(definition?.name ?? "Calling")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpButton(topic: .callingDetail)
        }
        .sheet(isPresented: $showingPicker) {
            CandidatePickerSheet(slotID: slotID)
        }
        .sheet(item: $editingDefinition) { definition in
            CallingEditorSheet(definition: definition)
        }
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let slot, let definition {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Organization", value: definition.organization.rawValue)
                        if let subgroup = definition.subgroup {
                            LabeledContent("Group", value: subgroup)
                        }
                        LabeledContent("Current", value: store.member(slot.memberID)?.name ?? slot.holderNameRaw ?? "Vacant")
                        if let date = slot.sustainedDate {
                            LabeledContent("Sustained", value: date.formatted(date: .abbreviated, time: .omitted))
                            if let months = slot.monthsInCalling() {
                                LabeledContent("Tenure", value: "\(months) months")
                            }
                        }
                        LabeledContent("Set Apart", value: slot.isSetApart ? "Yes" : "No")
                    }
                }

                if let openEntry {
                    GroupBox("Open Calling") {
                        VStack(alignment: .leading, spacing: 8) {
                            StatusMenu(openCallingID: openEntry.id)
                            if syncService.canDeleteOpenCallings {
                                Button(role: .destructive) {
                                    store.removeOpenCalling(openEntry.id)
                                } label: {
                                    Label("Remove from Open Callings", systemImage: "trash")
                                }
                            }
                        }
                    }
                } else {
                    Button {
                        store.openCallingEntry(for: slot)
                    } label: {
                        Label("Add to Open Callings", systemImage: "rectangle.stack.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    editingDefinition = definition
                } label: {
                    Label("Edit Criteria & Order…", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
    }
}
