import Foundation

/// Normalizes a loaded ward document onto content-derived record identities
/// and collapses the duplicate callings that random per-import ids allowed to
/// pile up.
///
/// Background: `CallingSlot.id` / `CallingDefinition.id` used to be a fresh
/// `UUID()` per import, and the CloudKit record name derives from the id. An
/// import that was never diffed out left its old records in the zone, and any
/// full re-fetch pulled them back in beside the new ones — `integrate` upserts
/// by id, so it saw them as different callings. The board ended up showing two
/// generations of the same export.
///
/// This pass is pure, deterministic, and idempotent: every device computes the
/// same result from the same data, so running it on launch makes the devices
/// converge instead of drifting further apart. See `StableID`.
enum WardDataRepair {

    struct Report: Equatable {
        var definitionsMerged = 0
        var duplicateSlotsRemoved = 0
        var duplicateMembersMerged = 0
        var identitiesRewritten = 0
        var openCallingsRepointed = 0

        var isEmpty: Bool {
            definitionsMerged == 0 && duplicateSlotsRemoved == 0 && duplicateMembersMerged == 0
                && identitiesRewritten == 0 && openCallingsRepointed == 0
        }

        /// One-line summary for the Sharing screen / sync log.
        var summary: String {
            "\(duplicateSlotsRemoved) duplicate callings removed, "
                + "\(definitionsMerged) calling types merged, "
                + "\(duplicateMembersMerged) duplicate names merged, "
                + "\(identitiesRewritten) records re-identified"
        }
    }

    static func normalize(_ data: WardData) -> (WardData, Report) {
        var data = data
        var report = Report()

        mergePlaceholderMembers(in: &data, report: &report)
        mergeDefinitions(in: &data, report: &report)
        let slotRemap = rebuildSlots(in: &data, report: &report)
        repoint(&data, slotRemap: slotRemap, report: &report)
        dropOrphanedDefinitions(in: &data)

        return (data, report)
    }

    // MARK: - Members

    /// A placeholder member (a calling holder who isn't on the roster) is
    /// created on first sight by name, so two generations of an import can
    /// leave two records for one person. Fold them onto the roster member of
    /// that name, or onto the first placeholder — otherwise the duplicate
    /// seats they hold look like different people.
    private static func mergePlaceholderMembers(in data: inout WardData, report: inout Report) {
        var canonical: [String: UUID] = [:]
        for member in data.members where !member.isPlaceholder {
            canonical[ImportReconciler.normalizeName(member.name)] = member.id
        }

        var remap: [UUID: UUID] = [:]
        var survivors: [Member] = []
        for member in data.members {
            guard member.isPlaceholder else { survivors.append(member); continue }
            let key = ImportReconciler.normalizeName(member.name)
            if let existing = canonical[key] {
                remap[member.id] = existing
                report.duplicateMembersMerged += 1
            } else {
                canonical[key] = member.id
                survivors.append(member)
            }
        }
        guard !remap.isEmpty else { return }

        data.members = survivors
        for index in data.callingSlots.indices {
            if let memberID = data.callingSlots[index].memberID, let target = remap[memberID] {
                data.callingSlots[index].memberID = target
            }
        }
        for index in data.openCallings.indices {
            if let memberID = data.openCallings[index].memberToBeCalledID, let target = remap[memberID] {
                data.openCallings[index].memberToBeCalledID = target
            }
            var seen = Set<UUID>()
            data.openCallings[index].candidateIDs = data.openCallings[index].candidateIDs
                .map { remap[$0] ?? $0 }
                .filter { seen.insert($0).inserted }
        }
    }

    // MARK: - Definitions

    /// Collapses definitions that describe the same calling onto one
    /// content-derived id, keeping the richest surviving copy.
    private static func mergeDefinitions(in data: inout WardData, report: inout Report) {
        var merged: [UUID: CallingDefinition] = [:]
        var order: [UUID] = []
        var remap: [UUID: UUID] = [:]

        for definition in data.callingDefinitions {
            let stableID = StableID.definitionID(importKey: definition.importKey)
            remap[definition.id] = stableID
            if definition.id != stableID { report.identitiesRewritten += 1 }

            var candidate = definition
            candidate.id = stableID
            if let existing = merged[stableID] {
                report.definitionsMerged += 1
                merged[stableID] = combine(existing, candidate)
            } else {
                merged[stableID] = candidate
                order.append(stableID)
            }
        }

        data.callingDefinitions = order.compactMap { merged[$0] }
        for index in data.callingSlots.indices {
            if let stableID = remap[data.callingSlots[index].definitionID] {
                data.callingSlots[index].definitionID = stableID
            }
        }
    }

    /// An LCR-confirmed copy beats a pending one; a deletion request from
    /// either copy is preserved so the ward clerk's checklist item survives.
    private static func combine(_ a: CallingDefinition, _ b: CallingDefinition) -> CallingDefinition {
        var result = a.isPending && !b.isPending ? b : a
        result.isPendingDeletion = (a.isMarkedForDeletion || b.isMarkedForDeletion) ? true : nil
        result.isCustom = a.isCustom || b.isCustom
        return result
    }

    // MARK: - Slots

    /// Rebuilds each calling's seats: drops duplicates, then gives every
    /// surviving seat its content-derived id. Returns old slot id → surviving
    /// slot id so open callings can be repointed.
    private static func rebuildSlots(in data: inout WardData, report: inout Report) -> [UUID: UUID] {
        let known = Set(data.callingDefinitions.map(\.id))
        let busySlotIDs = Set(data.openCallings.filter { !$0.isArchived }.map(\.slotID))
        let namesByID = Dictionary(
            data.members.map { ($0.id, ImportReconciler.normalizeName($0.name)) },
            uniquingKeysWith: { first, _ in first }
        )

        var byDefinition: [UUID: [CallingSlot]] = [:]
        var definitionOrder: [UUID] = []
        for slot in data.callingSlots.sorted(by: { $0.importOrder < $1.importOrder })
        where known.contains(slot.definitionID) {
            if byDefinition[slot.definitionID] == nil { definitionOrder.append(slot.definitionID) }
            byDefinition[slot.definitionID, default: []].append(slot)
        }

        let documentFactor = duplicationFactor(of: definitionOrder.map { byDefinition[$0] ?? [] }, namesByID: namesByID)
        var remap: [UUID: UUID] = [:]
        var rebuilt: [CallingSlot] = []

        for definitionID in definitionOrder {
            let (survivors, dropped) = dedupe(
                byDefinition[definitionID] ?? [], busySlotIDs: busySlotIDs,
                namesByID: namesByID, documentFactor: documentFactor
            )
            report.duplicateSlotsRemoved += dropped.count

            var idForGroup: [String: UUID] = [:]
            for (seat, original) in survivors.enumerated() {
                var slot = original
                slot.id = StableID.slotID(definitionID: definitionID, seat: seat)
                if slot.id != original.id { report.identitiesRewritten += 1 }
                remap[original.id] = slot.id
                let key = holderKey(slot, namesByID: namesByID)
                idForGroup[key] = idForGroup[key] ?? slot.id
                rebuilt.append(slot)
            }
            // A dropped duplicate hands its open-calling entry to the seat
            // that replaced it, so no work in progress is lost.
            for (slot, groupKey) in dropped {
                // Every group keeps at least one seat, so the survivor exists.
                remap[slot.id] = idForGroup[groupKey] ?? slot.id
            }
        }

        data.callingSlots = rebuilt
        return remap
    }

    /// Within one calling: the same person can't hold the same seat twice, so
    /// a repeated holder is a duplicate. Vacant seats are indistinguishable
    /// from one another, so they are only thinned by the duplication factor
    /// the filled seats prove — never below one, and never when work is in
    /// progress on them. A re-import restores the exact seat count.
    private static func dedupe(
        _ seats: [CallingSlot],
        busySlotIDs: Set<UUID>,
        namesByID: [UUID: String],
        documentFactor: Int
    ) -> (survivors: [CallingSlot], dropped: [(slot: CallingSlot, groupKey: String)]) {
        var groups: [String: [CallingSlot]] = [:]
        var groupOrder: [String] = []
        for slot in seats {
            let key = holderKey(slot, namesByID: namesByID)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(slot)
        }

        // This calling's own filled seats prove the factor; a calling with
        // nothing but empty seats falls back to the document's.
        let filledFactor = groupOrder.filter { $0 != vacantKey }.compactMap { groups[$0]?.count }.max() ?? 0
        let factor = max(1, filledFactor > 1 ? filledFactor : (filledFactor == 0 ? documentFactor : 1))

        var survivors: [CallingSlot] = []
        var dropped: [(slot: CallingSlot, groupKey: String)] = []

        for key in groupOrder {
            let group = groups[key] ?? []
            let keepCount = key == vacantKey ? max(1, group.count / factor) : 1
            for (rank, slot) in group.sorted(by: { best($0, over: $1, busySlotIDs: busySlotIDs) }).enumerated() {
                if rank < keepCount || busySlotIDs.contains(slot.id) {
                    survivors.append(slot)
                } else {
                    dropped.append((slot, key))
                }
            }
        }

        return (survivors.sorted { $0.importOrder < $1.importOrder }, dropped)
    }

    /// How many times over the document appears to be duplicated, judged only
    /// by filled seats (the unambiguous evidence). Returns 1 unless duplicated
    /// callings actually outnumber clean ones, so a healthy ward is never
    /// thinned — and empty seats in an all-vacant calling can then be judged
    /// by the same factor as everything else.
    private static func duplicationFactor(of callings: [[CallingSlot]], namesByID: [UUID: String]) -> Int {
        var votes: [Int: Int] = [:]
        for seats in callings {
            var counts: [String: Int] = [:]
            for slot in seats {
                let key = holderKey(slot, namesByID: namesByID)
                if key != vacantKey { counts[key, default: 0] += 1 }
            }
            guard let maximum = counts.values.max() else { continue }
            votes[maximum, default: 0] += 1
        }
        let clean = votes[1] ?? 0
        guard let (factor, count) = votes.filter({ $0.key > 1 }).max(by: { $0.value < $1.value }),
              count > clean else { return 1 }
        return factor
    }

    private static let vacantKey = "\u{0}vacant"

    /// Who is in the seat, keyed by person rather than by record id so two
    /// records for the same person still collapse.
    private static func holderKey(_ slot: CallingSlot, namesByID: [UUID: String]) -> String {
        if let memberID = slot.memberID, let name = namesByID[memberID] { return name }
        // The member record may itself be a stale duplicate; the printed
        // holder name still identifies the person.
        if let raw = slot.holderNameRaw { return ImportReconciler.normalizeName(raw) }
        if let memberID = slot.memberID { return memberID.uuidString }
        return vacantKey
    }

    /// Keep the seat with work in progress, then the most recently sustained,
    /// then the earliest imported — the copy most likely to be current.
    private static func best(_ a: CallingSlot, over b: CallingSlot, busySlotIDs: Set<UUID>) -> Bool {
        let aBusy = busySlotIDs.contains(a.id), bBusy = busySlotIDs.contains(b.id)
        if aBusy != bBusy { return aBusy }
        if a.sustainedDate != b.sustainedDate {
            return (a.sustainedDate ?? .distantPast) > (b.sustainedDate ?? .distantPast)
        }
        return a.importOrder < b.importOrder
    }

    // MARK: - Open callings and leftovers

    private static func repoint(_ data: inout WardData, slotRemap: [UUID: UUID], report: inout Report) {
        for index in data.openCallings.indices {
            guard let newID = slotRemap[data.openCallings[index].slotID],
                  newID != data.openCallings[index].slotID else { continue }
            data.openCallings[index].slotID = newID
            if !data.openCallings[index].isArchived { report.openCallingsRepointed += 1 }
        }
    }

    /// A merged-away definition leaves no seats behind. App-created callings
    /// awaiting LCR keep theirs even when empty.
    private static func dropOrphanedDefinitions(in data: inout WardData) {
        let used = Set(data.callingSlots.map(\.definitionID))
        data.callingDefinitions.removeAll {
            !used.contains($0.id) && !$0.isPending && !$0.isMarkedForDeletion
        }
    }
}
