import Foundation
import Observation

/// Single source of truth for all ward data and filters.
@Observable
@MainActor
final class WardStore {
    var data: WardData
    // Home-page highlight filters
    var highlightOpenCallings = false
    var highlightTenure = false
    var tenureThresholdMonths = 24

    private let persistence: PersistenceService

    /// Called after every local mutation with the new data — the sync layer
    /// diffs against its baseline and enqueues record changes.
    @ObservationIgnored var syncObserver: ((WardData) -> Void)?
    /// True while remote changes are being applied, so they don't re-enter
    /// the sync layer as local changes.
    @ObservationIgnored private var isApplyingRemote = false

    init(persistence: PersistenceService = PersistenceService()) {
        self.persistence = persistence
        self.data = persistence.load() ?? WardData()
    }

    private func save() {
        persistence.scheduleSave(data)
        if !isApplyingRemote {
            syncObserver?(data)
        }
    }

    /// Entry point for the sync layer: mutate the store with remote changes
    /// without echoing them back out.
    func applyRemote(_ mutate: (inout WardData) -> Void) {
        isApplyingRemote = true
        mutate(&data)
        persistence.scheduleSave(data)
        isApplyingRemote = false
    }

    // MARK: - Lookups

    var membersByID: [UUID: Member] {
        Dictionary(uniqueKeysWithValues: data.members.map { ($0.id, $0) })
    }

    var definitionsByID: [UUID: CallingDefinition] {
        Dictionary(uniqueKeysWithValues: data.callingDefinitions.map { ($0.id, $0) })
    }

    var slotsByID: [UUID: CallingSlot] {
        Dictionary(uniqueKeysWithValues: data.callingSlots.map { ($0.id, $0) })
    }

    func member(_ id: UUID?) -> Member? {
        guard let id else { return nil }
        return membersByID[id]
    }

    func definition(for slot: CallingSlot) -> CallingDefinition? {
        definitionsByID[slot.definitionID]
    }

    /// Slots for one organization, ordered by definition displayOrder then PDF order.
    func slots(in organization: OrganizationKind) -> [CallingSlot] {
        let definitions = definitionsByID
        return data.callingSlots
            .filter { definitions[$0.definitionID]?.organization == organization }
            .sorted { a, b in
                let da = definitions[a.definitionID], db = definitions[b.definitionID]
                if da?.displayOrder != db?.displayOrder {
                    return (da?.displayOrder ?? 100) < (db?.displayOrder ?? 100)
                }
                return a.importOrder < b.importOrder
            }
    }

    /// All slots held by a member (a member may have more than one calling).
    func slots(heldBy memberID: UUID) -> [CallingSlot] {
        data.callingSlots.filter { $0.memberID == memberID }
    }

    var activeOpenCallings: [OpenCalling] {
        data.openCallings.filter { !$0.isArchived }
    }

    var archivedOpenCallings: [OpenCalling] {
        data.openCallings.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    func openCalling(forSlot slotID: UUID) -> OpenCalling? {
        activeOpenCallings.first { $0.slotID == slotID }
    }

    /// Members with no calling slot, for the "Members Need Callings" column.
    var membersNeedingCallings: [Member] {
        let heldMemberIDs = Set(data.callingSlots.compactMap(\.memberID))
        return data.members
            .filter { $0.isActiveOnRoster && !heldMemberIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    var membersWithCallings: [Member] {
        let heldMemberIDs = Set(data.callingSlots.compactMap(\.memberID))
        return data.members
            .filter { $0.isActiveOnRoster && heldMemberIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Open calling workflow

    /// Creates an open-callings entry for a slot (no-op if one is already active).
    @discardableResult
    func openCallingEntry(for slot: CallingSlot) -> OpenCalling {
        if let existing = openCalling(forSlot: slot.id) { return existing }
        var entry = OpenCalling(slotID: slot.id)
        // A vacant slot has nobody to release.
        entry.releaseStatus = slot.memberID == nil ? .none : .open
        data.openCallings.append(entry)
        save()
        return entry
    }

    func removeOpenCalling(_ id: UUID) {
        data.openCallings.removeAll { $0.id == id }
        save()
    }

    func updateOpenCalling(_ entry: OpenCalling) {
        guard let index = data.openCallings.firstIndex(where: { $0.id == entry.id }) else { return }
        data.openCallings[index] = entry
        completeIfFinished(entry.id)
        save()
    }

    /// Once the outgoing member's release is Announced and the new member is
    /// Sustained, the calling has changed hands: show the new member on the
    /// Ward Callings view and archive the workflow entry. (A vacant seat has
    /// nobody to release, so its release status stays at none.)
    private func completeIfFinished(_ entryID: UUID) {
        guard let index = data.openCallings.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = data.openCallings[index]
        guard !entry.isArchived,
              entry.callStatus == .sustained,
              entry.releaseStatus == .announced || entry.releaseStatus == .none,
              let newMemberID = entry.memberToBeCalledID,
              let slotIndex = data.callingSlots.firstIndex(where: { $0.id == entry.slotID })
        else { return }

        // Archive first so the snapshot captures the outgoing holder.
        archiveOpenCalling(entry.id)

        var slot = data.callingSlots[slotIndex]
        slot.memberID = newMemberID
        slot.holderNameRaw = member(newMemberID)?.name
        slot.sustainedDate = .now
        slot.isSetApart = false
        data.callingSlots[slotIndex] = slot
    }

    func archiveOpenCalling(_ id: UUID, newHolderName: String? = nil) {
        guard let index = data.openCallings.firstIndex(where: { $0.id == id }) else { return }
        var entry = data.openCallings[index]
        let slot = slotsByID[entry.slotID]
        let definition = slot.flatMap { definitionsByID[$0.definitionID] }
        entry.isArchived = true
        entry.archivedAt = .now
        entry.snapshotCallingName = definition?.name
        entry.snapshotOrganization = definition?.organization.rawValue
        entry.snapshotPreviousHolder = slot.flatMap { s in member(s.memberID)?.name ?? s.holderNameRaw }
        entry.snapshotNewHolder = newHolderName ?? member(entry.memberToBeCalledID)?.name
        data.openCallings[index] = entry
        save()
    }

    // MARK: - Candidates

    func toggleCandidate(_ memberID: UUID, for openCallingID: UUID) {
        guard let index = data.openCallings.firstIndex(where: { $0.id == openCallingID }) else { return }
        if let existing = data.openCallings[index].candidateIDs.firstIndex(of: memberID) {
            data.openCallings[index].candidateIDs.remove(at: existing)
        } else {
            data.openCallings[index].candidateIDs.append(memberID)
        }
        save()
    }

    func addCandidate(_ memberID: UUID, for openCallingID: UUID) {
        guard let index = data.openCallings.firstIndex(where: { $0.id == openCallingID }),
              !data.openCallings[index].candidateIDs.contains(memberID) else { return }
        data.openCallings[index].candidateIDs.append(memberID)
        save()
    }

    /// Eligible candidates for a calling per its criteria.
    func candidates(matching criteria: CandidateCriteria) -> [Member] {
        let heldMemberIDs = Set(data.callingSlots.compactMap(\.memberID))
        return data.members
            .filter { $0.isActiveOnRoster && !$0.isPlaceholder && criteria.matches($0) }
            .filter { criteria.allowMultipleCallings || !heldMemberIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Member and definition edits

    func setCategory(_ category: MemberCategory, forMember memberID: UUID) {
        guard let index = data.members.firstIndex(where: { $0.id == memberID }) else { return }
        data.members[index].category = category
        save()
    }

    func updateDefinition(_ definition: CallingDefinition) {
        guard let index = data.callingDefinitions.firstIndex(where: { $0.id == definition.id }) else { return }
        data.callingDefinitions[index] = definition
        save()
    }

    /// Deletes a calling. App-created callings that LCR never confirmed are
    /// removed outright. LCR-backed callings are marked for deletion (struck
    /// through in red, with a ward-clerk checklist action) until a re-import
    /// no longer contains them; any current holder gets an open-callings
    /// entry so their release can be assigned and tracked.
    func requestDeletion(of definition: CallingDefinition) {
        guard let index = data.callingDefinitions.firstIndex(where: { $0.id == definition.id }) else { return }
        let slots = data.callingSlots.filter { $0.definitionID == definition.id }

        if definition.isPending {
            let slotIDs = Set(slots.map(\.id))
            data.openCallings.removeAll { slotIDs.contains($0.slotID) && !$0.isArchived }
            data.callingSlots.removeAll { slotIDs.contains($0.id) }
            data.callingDefinitions.remove(at: index)
        } else {
            data.callingDefinitions[index].isPendingDeletion = true
            for slot in slots where slot.memberID != nil {
                openCallingEntry(for: slot)
            }
        }
        save()
    }

    func cancelDeletion(of definition: CallingDefinition) {
        guard let index = data.callingDefinitions.firstIndex(where: { $0.id == definition.id }) else { return }
        data.callingDefinitions[index].isPendingDeletion = nil
        save()
    }

    /// Creates a new calling right after `anchor` in display order, marked
    /// pending until an LCR import confirms it, with a vacant slot so it
    /// shows on the ward view immediately.
    @discardableResult
    func createCalling(named name: String, after anchor: CallingDefinition) -> CallingSlot {
        var definition = CallingDefinition(name: name, organization: anchor.organization, subgroup: anchor.subgroup)
        definition.criteria = anchor.criteria
        definition.isPendingLCR = true

        // Halfway between the anchor and the next calling in the org's order.
        let ordered = data.callingDefinitions
            .filter { $0.organization == anchor.organization }
            .sorted { $0.displayOrder < $1.displayOrder }
        if let index = ordered.firstIndex(where: { $0.id == anchor.id }), index + 1 < ordered.count,
           ordered[index + 1].displayOrder > anchor.displayOrder {
            definition.displayOrder = (anchor.displayOrder + ordered[index + 1].displayOrder) / 2
        } else {
            definition.displayOrder = anchor.displayOrder + 10
        }

        data.callingDefinitions.append(definition)
        let slot = CallingSlot(
            definitionID: definition.id,
            importOrder: (data.callingSlots.map(\.importOrder).max() ?? 0) + 1
        )
        data.callingSlots.append(slot)
        save()
        return slot
    }

    // MARK: - Import

    func apply(_ newData: WardData) {
        data = newData
        persistence.saveNow(data)
    }
}
