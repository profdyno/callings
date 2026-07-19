import CloudKit
import Foundation

/// Pure mapping between the app's value-type models and CKRecords.
///
/// Records use individual fields (not a JSON blob) so conflicts can be merged
/// field-by-field. recordName encodes the model identity as "<Type>_<uuid>";
/// decoding is lenient — missing fields fall back to model defaults so the
/// schema can grow additively.
enum CKRecordMapper {

    enum RecordType {
        static let member = "Member"
        static let callingDefinition = "CallingDefinition"
        static let callingSlot = "CallingSlot"
        static let openCalling = "OpenCalling"
        static let wardMeta = "WardMeta"
        static let share = "cloudkit.share"
    }

    // MARK: - Record names

    static func recordName(forMember id: UUID) -> String { "Member_\(id.uuidString)" }
    static func recordName(forDefinition id: UUID) -> String { "CallingDefinition_\(id.uuidString)" }
    static func recordName(forSlot id: UUID) -> String { "CallingSlot_\(id.uuidString)" }
    static func recordName(forOpenCalling id: UUID) -> String { "OpenCalling_\(id.uuidString)" }
    static let wardMetaRecordName = "WardMeta"

    /// Parses "<Type>_<uuid>" back into its parts. WardMeta has no UUID.
    static func parse(recordName: String) -> (type: String, id: UUID?)? {
        if recordName == wardMetaRecordName { return (RecordType.wardMeta, nil) }
        guard let underscore = recordName.firstIndex(of: "_"),
              let id = UUID(uuidString: String(recordName[recordName.index(after: underscore)...]))
        else { return nil }
        return (String(recordName[..<underscore]), id)
    }

    // MARK: - Member

    static func populate(_ record: CKRecord, from member: Member) {
        record["name"] = member.name
        record["age"] = member.age
        record["gender"] = member.gender?.rawValue
        record["email"] = member.email
        record["phone"] = member.phone
        record["priesthood"] = member.priesthood.rawValue
        record["priesthoodOffice"] = member.priesthoodOffice
        record["moveInDate"] = member.moveInDate
        record["templeRecommendStatus"] = member.templeRecommendStatus
        record["classAssignments"] = member.classAssignments
        record["categoryKind"] = categoryKind(member.category)
        record["categoryText"] = categoryText(member.category)
        record["isActiveOnRoster"] = member.isActiveOnRoster ? 1 : 0
        record["isPlaceholder"] = member.isPlaceholder ? 1 : 0
    }

    static func member(from record: CKRecord) -> Member? {
        guard let parsed = parse(recordName: record.recordID.recordName),
              parsed.type == RecordType.member, let id = parsed.id,
              let name = record["name"] as? String else { return nil }
        var member = Member(name: name)
        member.id = id
        member.age = record["age"] as? Int
        member.gender = (record["gender"] as? String).flatMap(Gender.init(rawValue:))
        member.email = record["email"] as? String
        member.phone = record["phone"] as? String
        member.priesthood = (record["priesthood"] as? String).flatMap(PriesthoodTrack.init(rawValue:)) ?? .none
        member.priesthoodOffice = record["priesthoodOffice"] as? String
        member.moveInDate = record["moveInDate"] as? Date
        member.templeRecommendStatus = record["templeRecommendStatus"] as? String
        member.classAssignments = record["classAssignments"] as? [String] ?? []
        member.category = category(kind: record["categoryKind"] as? String, text: record["categoryText"] as? String)
        member.isActiveOnRoster = (record["isActiveOnRoster"] as? Int ?? 1) == 1
        member.isPlaceholder = (record["isPlaceholder"] as? Int ?? 0) == 1
        return member
    }

    private static func categoryKind(_ category: MemberCategory) -> String {
        switch category {
        case .none: return "none"
        case .notActive: return "notActive"
        case .doNotCall: return "doNotCall"
        case .movingSoon: return "movingSoon"
        case .other: return "other"
        }
    }

    private static func categoryText(_ category: MemberCategory) -> String? {
        if case .other(let text) = category { return text }
        return nil
    }

    private static func category(kind: String?, text: String?) -> MemberCategory {
        switch kind {
        case "notActive": return .notActive
        case "doNotCall": return .doNotCall
        case "movingSoon": return .movingSoon
        case "other": return .other(text ?? "")
        default: return .none
        }
    }

    // MARK: - CallingDefinition

    static func populate(_ record: CKRecord, from definition: CallingDefinition) {
        record["name"] = definition.name
        record["organization"] = definition.organization.rawValue
        record["subgroup"] = definition.subgroup
        record["displayOrder"] = definition.displayOrder
        record["isCustom"] = definition.isCustom ? 1 : 0
        record["isPendingLCR"] = definition.isPending ? 1 : 0
        record["isPendingDeletion"] = definition.isMarkedForDeletion ? 1 : 0
        record["criteriaGender"] = definition.criteria.gender?.rawValue
        record["criteriaMinAge"] = definition.criteria.minAge
        record["criteriaMaxAge"] = definition.criteria.maxAge
        record["criteriaMinPriesthood"] = definition.criteria.minimumPriesthood?.rawValue
        record["criteriaRequiredClasses"] = definition.criteria.requiredClassAssignments
        record["criteriaAllowMultiple"] = definition.criteria.allowMultipleCallings ? 1 : 0
    }

    static func callingDefinition(from record: CKRecord) -> CallingDefinition? {
        guard let parsed = parse(recordName: record.recordID.recordName),
              parsed.type == RecordType.callingDefinition, let id = parsed.id,
              let name = record["name"] as? String,
              let organization = (record["organization"] as? String).flatMap(OrganizationKind.init(rawValue:))
        else { return nil }
        var definition = CallingDefinition(name: name, organization: organization)
        definition.id = id
        definition.subgroup = record["subgroup"] as? String
        definition.displayOrder = record["displayOrder"] as? Double ?? 100
        definition.isCustom = (record["isCustom"] as? Int ?? 0) == 1
        definition.isPendingLCR = (record["isPendingLCR"] as? Int ?? 0) == 1 ? true : nil
        definition.isPendingDeletion = (record["isPendingDeletion"] as? Int ?? 0) == 1 ? true : nil
        definition.criteria.gender = (record["criteriaGender"] as? String).flatMap(Gender.init(rawValue:))
        definition.criteria.minAge = record["criteriaMinAge"] as? Int
        definition.criteria.maxAge = record["criteriaMaxAge"] as? Int
        definition.criteria.minimumPriesthood = (record["criteriaMinPriesthood"] as? String).flatMap(PriesthoodTrack.init(rawValue:))
        definition.criteria.requiredClassAssignments = record["criteriaRequiredClasses"] as? [String] ?? []
        definition.criteria.allowMultipleCallings = (record["criteriaAllowMultiple"] as? Int ?? 1) == 1
        return definition
    }

    // MARK: - CallingSlot

    static func populate(_ record: CKRecord, from slot: CallingSlot) {
        record["definitionID"] = slot.definitionID.uuidString
        record["memberID"] = slot.memberID?.uuidString
        record["holderNameRaw"] = slot.holderNameRaw
        record["sustainedDate"] = slot.sustainedDate
        record["isSetApart"] = slot.isSetApart ? 1 : 0
        record["importOrder"] = slot.importOrder
    }

    static func callingSlot(from record: CKRecord) -> CallingSlot? {
        guard let parsed = parse(recordName: record.recordID.recordName),
              parsed.type == RecordType.callingSlot, let id = parsed.id,
              let definitionID = (record["definitionID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        var slot = CallingSlot(definitionID: definitionID)
        slot.id = id
        slot.memberID = (record["memberID"] as? String).flatMap(UUID.init(uuidString:))
        slot.holderNameRaw = record["holderNameRaw"] as? String
        slot.sustainedDate = record["sustainedDate"] as? Date
        slot.isSetApart = (record["isSetApart"] as? Int ?? 0) == 1
        slot.importOrder = record["importOrder"] as? Int ?? 0
        return slot
    }

    // MARK: - OpenCalling

    static func populate(_ record: CKRecord, from entry: OpenCalling) {
        record["slotID"] = entry.slotID.uuidString
        record["assignedTo"] = entry.assignedTo.rawValue
        record["releaseAssignedTo"] = entry.releaseAssignedTo?.rawValue
        record["releaseStatus"] = entry.releaseStatus.rawValue
        record["memberToBeCalledID"] = entry.memberToBeCalledID?.uuidString
        record["callStatus"] = entry.callStatus.rawValue
        record["candidateIDs"] = entry.candidateIDs.map(\.uuidString)
        record["notes"] = entry.notes
        record["createdAt"] = entry.createdAt
        record["isArchived"] = entry.isArchived ? 1 : 0
        record["archivedAt"] = entry.archivedAt
        record["snapshotCallingName"] = entry.snapshotCallingName
        record["snapshotOrganization"] = entry.snapshotOrganization
        record["snapshotPreviousHolder"] = entry.snapshotPreviousHolder
        record["snapshotNewHolder"] = entry.snapshotNewHolder
    }

    static func openCalling(from record: CKRecord) -> OpenCalling? {
        guard let parsed = parse(recordName: record.recordID.recordName),
              parsed.type == RecordType.openCalling, let id = parsed.id,
              let slotID = (record["slotID"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        var entry = OpenCalling(slotID: slotID)
        entry.id = id
        entry.assignedTo = (record["assignedTo"] as? String).flatMap(BishopricMember.init(rawValue:)) ?? .unassigned
        entry.releaseAssignedTo = (record["releaseAssignedTo"] as? String).flatMap(BishopricMember.init(rawValue:))
        entry.releaseStatus = (record["releaseStatus"] as? String).flatMap(ReleaseStatus.init(rawValue:)) ?? .none
        entry.memberToBeCalledID = (record["memberToBeCalledID"] as? String).flatMap(UUID.init(uuidString:))
        entry.callStatus = (record["callStatus"] as? String).flatMap(CallStatus.init(rawValue:)) ?? .none
        entry.candidateIDs = (record["candidateIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        entry.notes = record["notes"] as? String ?? ""
        entry.createdAt = record["createdAt"] as? Date ?? entry.createdAt
        entry.isArchived = (record["isArchived"] as? Int ?? 0) == 1
        entry.archivedAt = record["archivedAt"] as? Date
        entry.snapshotCallingName = record["snapshotCallingName"] as? String
        entry.snapshotOrganization = record["snapshotOrganization"] as? String
        entry.snapshotPreviousHolder = record["snapshotPreviousHolder"] as? String
        entry.snapshotNewHolder = record["snapshotNewHolder"] as? String
        return entry
    }

    // MARK: - WardMeta

    struct WardMeta: Equatable {
        var wardName: String?
        var lastCallingsImport: Date?
        var lastRosterImport: Date?
        var schemaVersion: Int = 1
        var importGeneration: Int = 0
    }

    static func populate(_ record: CKRecord, from meta: WardMeta) {
        record["wardName"] = meta.wardName
        record["lastCallingsImport"] = meta.lastCallingsImport
        record["lastRosterImport"] = meta.lastRosterImport
        record["schemaVersion"] = meta.schemaVersion
        record["importGeneration"] = meta.importGeneration
    }

    static func wardMeta(from record: CKRecord) -> WardMeta {
        WardMeta(
            wardName: record["wardName"] as? String,
            lastCallingsImport: record["lastCallingsImport"] as? Date,
            lastRosterImport: record["lastRosterImport"] as? Date,
            schemaVersion: record["schemaVersion"] as? Int ?? 1,
            importGeneration: record["importGeneration"] as? Int ?? 0
        )
    }
}
