import SwiftUI

/// One calling/name grid row. Red calling text = has an open entry.
/// Tapping the calling starts (or resumes) a calling change and opens the
/// candidate picker. Optional highlights: vacant callings and long tenure.
struct CallingRowView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    let slot: CallingSlot
    @Binding var editingDefinition: CallingDefinition?
    @Binding var pickerSlot: CallingSlot?
    @Binding var detailMemberID: UUID?

    private var definition: CallingDefinition? { store.definition(for: slot) }
    private var holder: Member? { store.member(slot.memberID) }
    private var openEntry: OpenCalling? { store.openCalling(forSlot: slot.id) }

    private var isVacant: Bool { slot.memberID == nil }

    private var isOverTenure: Bool {
        guard store.highlightTenure, let months = slot.monthsInCalling() else { return false }
        return months >= store.tenureThresholdMonths
    }

    var body: some View {
        GridRow {
            Button {
                // The picker creates the open entry only if a candidate is
                // actually selected.
                pickerSlot = slot
            } label: {
                Text(definition?.nameWithinOrganization ?? "—")
                    .font(.subheadline)
                    .strikethrough(definition?.isMarkedForDeletion == true)
                    .foregroundStyle(callingColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                if let memberID = slot.memberID { detailMemberID = memberID }
            } label: {
                Text(holderLabel)
                    .font(.subheadline)
                    .foregroundStyle(holderStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 3)
                    .background(highlightBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(slot.memberID == nil)
        }
        .contextMenu {
            NavigationLink(value: slot) {
                Label("Details…", systemImage: "info.circle")
            }
            if let memberID = slot.memberID {
                Button {
                    detailMemberID = memberID
                } label: {
                    Label("Member Details…", systemImage: "person.crop.circle")
                }
            }
            if let entry = openEntry {
                if syncService.canDeleteOpenCallings {
                    Button(role: .destructive) {
                        store.removeOpenCalling(entry.id)
                    } label: {
                        Label("Remove from Open Callings", systemImage: "rectangle.stack.badge.minus")
                    }
                }
            } else {
                Button {
                    store.openCallingEntry(for: slot)
                } label: {
                    Label("Add to Open Callings", systemImage: "rectangle.stack.badge.plus")
                }
            }
            Button {
                editingDefinition = definition
            } label: {
                Label("Edit Criteria & Order…", systemImage: "slider.horizontal.3")
            }
        }
    }

    /// Red strikethrough = deleted, awaiting LCR removal; orange = created
    /// in app, pending LCR; red = has an open entry.
    private var callingColor: Color {
        if definition?.isMarkedForDeletion == true { return .red }
        if definition?.isPending == true { return .orange }
        if openEntry != nil { return .red }
        return .primary
    }

    private var holderLabel: String {
        if let holder { return holder.name }
        return slot.holderNameRaw ?? "Vacant"
    }

    private var holderStyle: Color {
        if isVacant { return .secondary }
        if isOverTenure { return .orange }
        return .primary
    }

    private var highlightBackground: Color {
        if store.highlightOpenCallings && isVacant { return .red.opacity(0.18) }
        if isOverTenure { return .orange.opacity(0.15) }
        return .clear
    }
}
