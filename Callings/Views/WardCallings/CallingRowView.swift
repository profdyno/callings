import SwiftUI

/// Presentation for one calling seat, computed once and shared by the iPad
/// grid row and the iPhone list row.
///
/// Red calling text = has an open entry; red strikethrough = deleted, awaiting
/// LCR removal; orange = created in app, pending LCR.
struct CallingRowModel {
    let definition: CallingDefinition?
    let holderName: String?
    let isVacant: Bool
    let hasOpenEntry: Bool
    let isOverTenure: Bool
    let highlightVacant: Bool

    var callingName: String { definition?.nameWithinOrganization ?? "—" }
    var isStruckThrough: Bool { definition?.isMarkedForDeletion == true }

    var callingColor: Color {
        if definition?.isMarkedForDeletion == true { return .red }
        if definition?.isPending == true { return .orange }
        if hasOpenEntry { return .red }
        return .primary
    }

    var holderLabel: String { holderName ?? "Vacant" }

    var holderStyle: Color {
        if isVacant { return .secondary }
        if isOverTenure { return .orange }
        return .primary
    }

    var highlightBackground: Color {
        if highlightVacant && isVacant { return .red.opacity(0.18) }
        if isOverTenure { return .orange.opacity(0.15) }
        return .clear
    }
}

/// The calling-name cell. Tapping starts (or resumes) a calling change.
struct CallingNameCell: View {
    let model: CallingRowModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(model.callingName)
                .font(.subheadline)
                .strikethrough(model.isStruckThrough)
                .foregroundStyle(model.callingColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// The holder cell, with the vacancy and long-tenure highlights.
struct CallingHolderCell: View {
    let model: CallingRowModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(model.holderLabel)
                .font(.subheadline)
                .foregroundStyle(model.holderStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3)
                .background(model.highlightBackground, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(model.isVacant)
    }
}

/// One calling/name grid row on the iPad board.
struct CallingRowView: View {
    @Environment(WardStore.self) private var store
    let slot: CallingSlot
    @Binding var editingDefinition: CallingDefinition?
    @Binding var pickerSlot: CallingSlot?
    @Binding var detailMemberID: UUID?

    var body: some View {
        let model = store.rowModel(for: slot)
        GridRow {
            CallingNameCell(model: model) { pickerSlot = slot }
            CallingHolderCell(model: model) {
                if let memberID = slot.memberID { detailMemberID = memberID }
            }
        }
        .callingContextMenu(
            slot: slot,
            editingDefinition: $editingDefinition,
            detailMemberID: $detailMemberID
        )
    }
}

/// The same seat as a single row in the iPhone list.
struct CompactCallingRow: View {
    @Environment(WardStore.self) private var store
    let slot: CallingSlot
    @Binding var editingDefinition: CallingDefinition?
    @Binding var pickerSlot: CallingSlot?
    @Binding var detailMemberID: UUID?

    var body: some View {
        let model = store.rowModel(for: slot)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            CallingNameCell(model: model) { pickerSlot = slot }
            CallingHolderCell(model: model) {
                if let memberID = slot.memberID { detailMemberID = memberID }
            }
        }
        .callingContextMenu(
            slot: slot,
            editingDefinition: $editingDefinition,
            detailMemberID: $detailMemberID
        )
    }
}

/// Details / member details / open-calling entry / edit criteria — identical
/// on both layouts.
private struct CallingContextMenu: ViewModifier {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    let slot: CallingSlot
    @Binding var editingDefinition: CallingDefinition?
    @Binding var detailMemberID: UUID?

    func body(content: Content) -> some View {
        content.contextMenu {
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
            if let entry = store.openCalling(forSlot: slot.id) {
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
                editingDefinition = store.definition(for: slot)
            } label: {
                Label("Edit Criteria & Order…", systemImage: "slider.horizontal.3")
            }
        }
    }
}

private extension View {
    func callingContextMenu(
        slot: CallingSlot,
        editingDefinition: Binding<CallingDefinition?>,
        detailMemberID: Binding<UUID?>
    ) -> some View {
        modifier(CallingContextMenu(
            slot: slot,
            editingDefinition: editingDefinition,
            detailMemberID: detailMemberID
        ))
    }
}

extension WardStore {
    /// Everything a calling row needs to draw itself.
    func rowModel(for slot: CallingSlot) -> CallingRowModel {
        let months = highlightTenure ? slot.monthsInCalling() : nil
        return CallingRowModel(
            definition: definition(for: slot),
            holderName: member(slot.memberID)?.name ?? slot.holderNameRaw,
            isVacant: slot.memberID == nil,
            hasOpenEntry: openCalling(forSlot: slot.id) != nil,
            isOverTenure: (months ?? -1) >= tenureThresholdMonths,
            highlightVacant: highlightOpenCallings
        )
    }
}
