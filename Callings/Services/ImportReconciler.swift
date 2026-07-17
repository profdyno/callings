import Foundation

/// Summary of what an import will change, shown in the preview before applying.
struct ImportSummary {
    var membersAdded = 0
    var membersUpdated = 0
    var membersDeactivated = 0
    var placeholdersCreated: [String] = []
    var definitionsCreated = 0
    var slotsImported = 0
    var vacantSlots = 0
    var openCallingsArchived: [String] = []
    var countMismatches: [String] = []
}

/// Pure reconciliation of parsed PDF data into the ward data set.
/// All functions take the current data and return the new data plus a summary,
/// which makes import behavior directly unit-testable.
enum ImportReconciler {

    // MARK: - Name matching

    /// Normalizes "Last, First Middle" for matching across the two reports.
    static func normalizeName(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// "Last, First Middle" → "last|first" for a looser fallback match.
    static func lastAndFirstToken(_ name: String) -> String {
        let normalized = normalizeName(name)
        let parts = normalized.split(separator: ",", maxSplits: 1)
        let last = parts.first.map(String.init) ?? normalized
        let firstToken = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
            : ""
        return "\(last)|\(firstToken)"
    }

    /// Matches a callings-PDF holder name against the roster. Holder names may
    /// differ from roster names ("Woodruff, Sam" vs "Woodruff, Samuel B"), so
    /// after an exact match this falls back to last name + first given token,
    /// then to a first-token prefix relation — each only when unambiguous.
    private static func findMember(named name: String, in members: [Member]) -> Member? {
        let normalized = normalizeName(name)
        if let exact = members.first(where: { normalizeName($0.name) == normalized }) {
            return exact
        }
        let loose = lastAndFirstToken(name)
        let looseMatches = members.filter { lastAndFirstToken($0.name) == loose }
        if looseMatches.count == 1 { return looseMatches.first }
        guard looseMatches.isEmpty else { return nil }

        let parts = loose.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, parts[1].count >= 3 else { return nil }
        let (last, first) = (String(parts[0]), String(parts[1]))
        let prefixMatches = members.filter { member in
            let memberParts = lastAndFirstToken(member.name).split(separator: "|", maxSplits: 1)
            guard memberParts.count == 2, memberParts[0] == last else { return false }
            let memberFirst = String(memberParts[1])
            return memberFirst.count >= 3 && (memberFirst.hasPrefix(first) || first.hasPrefix(memberFirst))
        }
        return prefixMatches.count == 1 ? prefixMatches.first : nil
    }

    // MARK: - Roster import

    /// Applies a parsed member list: update matches in place (preserving id,
    /// user-set category, and candidacies), add new members, and deactivate
    /// members that disappeared (never hard-delete — slots may reference them).
    static func applyRoster(_ parsed: [ParsedMember], to data: WardData) -> (WardData, ImportSummary) {
        var data = data
        var summary = ImportSummary()
        var seenIDs = Set<UUID>()

        for parsedMember in parsed {
            // Exact normalized match only: roster names are canonical, and a
            // loose match would merge distinct people (e.g. "Bingham, Ryan"
            // with "Bingham, Ryan Kirk Jr.").
            let normalized = normalizeName(parsedMember.name)
            if let index = data.members.firstIndex(where: { normalizeName($0.name) == normalized }) {
                var member = data.members[index]
                member.name = parsedMember.name
                member.age = parsedMember.age
                member.gender = parsedMember.gender ?? member.gender
                member.email = parsedMember.email ?? member.email
                member.phone = parsedMember.phone ?? member.phone
                member.priesthood = parsedMember.priesthood
                member.classAssignments = parsedMember.classAssignments
                member.isActiveOnRoster = true
                member.isPlaceholder = false
                data.members[index] = member
                seenIDs.insert(member.id)
                summary.membersUpdated += 1
            } else {
                var member = Member(name: parsedMember.name)
                member.age = parsedMember.age
                member.gender = parsedMember.gender
                member.email = parsedMember.email
                member.phone = parsedMember.phone
                member.priesthood = parsedMember.priesthood
                member.classAssignments = parsedMember.classAssignments
                data.members.append(member)
                seenIDs.insert(member.id)
                summary.membersAdded += 1
            }
        }

        for index in data.members.indices where !seenIDs.contains(data.members[index].id) {
            if data.members[index].isActiveOnRoster && !data.members[index].isPlaceholder {
                data.members[index].isActiveOnRoster = false
                summary.membersDeactivated += 1
            }
        }

        data.lastRosterImport = .now
        return (data, summary)
    }

    // MARK: - Callings import

    /// Applies a parsed Ward Callings export:
    /// - matches or creates calling definitions, preserving user-edited
    ///   display order and criteria on existing ones
    /// - rebuilds all slots from the PDF rows
    /// - archives open-calling entries whose slot's holder changed (the new
    ///   person now appears in LCR), and repoints surviving entries at the
    ///   rebuilt slots
    static func applyCallings(_ parsed: ParsedWardCallings, to data: WardData) -> (WardData, ImportSummary) {
        var data = data
        var summary = ImportSummary()
        summary.countMismatches = parsed.countMismatches

        // 1. Match or create definitions. An app-created calling that now
        // appears in the LCR export is confirmed: clear its pending flag so
        // the PDF slots take over below.
        let parsedKeys = Set(parsed.rows.map { importKey(for: $0) })
        for index in data.callingDefinitions.indices
        where data.callingDefinitions[index].isPending && parsedKeys.contains(data.callingDefinitions[index].importKey) {
            data.callingDefinitions[index].isPendingLCR = nil
        }

        // A deletion-marked calling the export no longer contains has been
        // removed in LCR: archive its remaining open entries and drop it.
        let deletedDefinitions = data.callingDefinitions.filter {
            $0.isMarkedForDeletion && !parsedKeys.contains($0.importKey)
        }
        if !deletedDefinitions.isEmpty {
            let deletedIDs = Set(deletedDefinitions.map(\.id))
            let deletedSlotIDs = Set(data.callingSlots.filter { deletedIDs.contains($0.definitionID) }.map(\.id))
            let members = Dictionary(uniqueKeysWithValues: data.members.map { ($0.id, $0) })
            for index in data.openCallings.indices
            where !data.openCallings[index].isArchived && deletedSlotIDs.contains(data.openCallings[index].slotID) {
                let slot = data.callingSlots.first { $0.id == data.openCallings[index].slotID }
                let definition = deletedDefinitions.first { $0.id == slot?.definitionID }
                data.openCallings[index].isArchived = true
                data.openCallings[index].archivedAt = .now
                data.openCallings[index].snapshotCallingName = definition?.name
                data.openCallings[index].snapshotOrganization = definition?.organization.rawValue
                data.openCallings[index].snapshotPreviousHolder = slot?.memberID.flatMap { members[$0]?.name } ?? slot?.holderNameRaw
                summary.openCallingsArchived.append("\(definition?.name ?? "?") (deleted)")
            }
            data.callingDefinitions.removeAll { deletedIDs.contains($0.id) }
        }

        var definitionsByKey: [String: CallingDefinition] = [:]
        for definition in data.callingDefinitions {
            definitionsByKey[definition.importKey] = definition
        }
        for row in parsed.rows {
            let key = importKey(for: row)
            if definitionsByKey[key] == nil {
                var definition = CallingDefinition(
                    name: row.callingName,
                    organization: row.organization,
                    subgroup: row.subgroup
                )
                definition.isCustom = row.isCustom
                CallingSeedRules.apply(to: &definition)
                definitionsByKey[key] = definition
                data.callingDefinitions.append(definition)
                summary.definitionsCreated += 1
            }
        }

        // 2. Resolve holders to members (placeholders for unmatched names).
        var newSlots: [CallingSlot] = []
        for (order, row) in parsed.rows.enumerated() {
            guard let definition = definitionsByKey[importKey(for: row)] else { continue }
            var slot = CallingSlot(definitionID: definition.id, importOrder: order)
            slot.sustainedDate = row.sustainedDate
            slot.isSetApart = row.isSetApart
            if let holderName = row.holderName {
                slot.holderNameRaw = holderName
                if let member = findMember(named: holderName, in: data.members) {
                    slot.memberID = member.id
                } else {
                    var placeholder = Member(name: holderName)
                    placeholder.isPlaceholder = true
                    data.members.append(placeholder)
                    slot.memberID = placeholder.id
                    summary.placeholdersCreated.append(holderName)
                }
            } else {
                summary.vacantSlots += 1
            }
            newSlots.append(slot)
        }

        // App-created callings the export doesn't know about yet keep their
        // existing slots (same ids, so open entries stay attached).
        let pendingDefinitionIDs = Set(data.callingDefinitions.filter(\.isPending).map(\.id))
        for slot in data.callingSlots where pendingDefinitionIDs.contains(slot.definitionID) {
            var preserved = slot
            preserved.importOrder = newSlots.count
            newSlots.append(preserved)
        }
        summary.slotsImported = newSlots.count

        // 3. Reconcile open callings against the new slots.
        let oldSlotsByID = Dictionary(uniqueKeysWithValues: data.callingSlots.map { ($0.id, $0) })
        let membersByID = Dictionary(uniqueKeysWithValues: data.members.map { ($0.id, $0) })
        let definitionsByID = Dictionary(uniqueKeysWithValues: data.callingDefinitions.map { ($0.id, $0) })

        for index in data.openCallings.indices where !data.openCallings[index].isArchived {
            var entry = data.openCallings[index]
            guard let oldSlot = oldSlotsByID[entry.slotID],
                  let definition = definitionsByID[oldSlot.definitionID] else { continue }

            // Candidate new slots for the same definition.
            let candidates = newSlots.filter { $0.definitionID == definition.id }

            // Same holder still in place → repoint the entry at the rebuilt slot.
            if let match = candidates.first(where: { sameHolder($0, oldSlot, membersByID: membersByID) }) {
                entry.slotID = match.id
                data.openCallings[index] = entry
                continue
            }

            // Holder changed (or vacant seat now filled) → LCR reflects the
            // completed call. Archive with a snapshot.
            entry.isArchived = true
            entry.archivedAt = .now
            entry.snapshotCallingName = definition.name
            entry.snapshotOrganization = definition.organization.rawValue
            entry.snapshotPreviousHolder = oldSlot.memberID.flatMap { membersByID[$0]?.name } ?? oldSlot.holderNameRaw
            let newHolder = candidates.first { $0.memberID != oldSlot.memberID && $0.memberID != nil }
            entry.snapshotNewHolder = newHolder?.holderNameRaw
                ?? entry.memberToBeCalledID.flatMap { membersByID[$0]?.name }
            data.openCallings[index] = entry
            summary.openCallingsArchived.append(definition.name)
        }

        data.callingSlots = newSlots
        data.wardName = parsed.wardName ?? data.wardName
        data.lastCallingsImport = .now
        return (data, summary)
    }

    private static func importKey(for row: ParsedCallingRow) -> String {
        "\(row.organization.rawValue)|\(row.subgroup ?? "")|\(row.callingName)".lowercased()
    }

    private static func sameHolder(_ a: CallingSlot, _ b: CallingSlot, membersByID: [UUID: Member]) -> Bool {
        if a.memberID != nil || b.memberID != nil {
            return a.memberID == b.memberID
        }
        return a.isVacant == b.isVacant
    }
}
