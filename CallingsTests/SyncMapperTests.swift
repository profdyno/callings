import XCTest
import CloudKit
@testable import Callings

final class SyncMapperTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "WardZone", ownerName: CKCurrentUserDefaultName)

    private func record(type: String, name: String) -> CKRecord {
        CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
    }

    func testMemberRoundTrip() {
        var member = Member(name: "Alley, Raelyn Kay")
        member.age = 45
        member.gender = .female
        member.email = "r@example.com"
        member.phone = "(480) 555-1234"
        member.priesthood = .none
        member.priesthoodOffice = "High Priest"
        member.moveInDate = Date(timeIntervalSince1970: 1_600_000_000)
        member.templeRecommendStatus = "Expiring next month"
        member.classAssignments = ["Relief Society", "Adult Sunday School"]
        member.category = .other("Serving mission soon")
        member.isActiveOnRoster = false
        member.isPlaceholder = true

        let rec = record(type: "Member", name: CKRecordMapper.recordName(forMember: member.id))
        CKRecordMapper.populate(rec, from: member)
        XCTAssertEqual(CKRecordMapper.member(from: rec), member)
    }

    func testMemberCategoryStandardCasesRoundTrip() {
        for category in [MemberCategory.none, .notActive, .doNotCall, .movingSoon] {
            var member = Member(name: "Test, Person")
            member.category = category
            let rec = record(type: "Member", name: CKRecordMapper.recordName(forMember: member.id))
            CKRecordMapper.populate(rec, from: member)
            XCTAssertEqual(CKRecordMapper.member(from: rec)?.category, category)
        }
    }

    func testCallingDefinitionRoundTrip() {
        var definition = CallingDefinition(name: "Elders Quorum Historian", organization: .eldersQuorum)
        definition.subgroup = "Elders Quorum Presidency"
        definition.displayOrder = 32.5
        definition.isCustom = true
        definition.isPendingLCR = true
        definition.isPendingDeletion = true
        definition.criteria.gender = .male
        definition.criteria.minAge = 18
        definition.criteria.minimumPriesthood = .melchizedek
        definition.criteria.requiredClassAssignments = ["Elders Quorum"]
        definition.criteria.allowMultipleCallings = false

        let rec = record(type: "CallingDefinition", name: CKRecordMapper.recordName(forDefinition: definition.id))
        CKRecordMapper.populate(rec, from: definition)
        XCTAssertEqual(CKRecordMapper.callingDefinition(from: rec), definition)
    }

    func testCallingSlotRoundTripIncludingNilDates() {
        var slot = CallingSlot(definitionID: UUID())
        slot.memberID = UUID()
        slot.holderNameRaw = "Smith, John"
        slot.sustainedDate = nil
        slot.isSetApart = true
        slot.importOrder = 42

        let rec = record(type: "CallingSlot", name: CKRecordMapper.recordName(forSlot: slot.id))
        CKRecordMapper.populate(rec, from: slot)
        XCTAssertEqual(CKRecordMapper.callingSlot(from: rec), slot)
    }

    func testOpenCallingRoundTrip() {
        var entry = OpenCalling(slotID: UUID())
        entry.assignedTo = .firstCounselor
        entry.releaseAssignedTo = .stake
        entry.releaseStatus = .released
        entry.memberToBeCalledID = UUID()
        entry.callStatus = .called
        entry.candidateIDs = [UUID(), UUID()]
        entry.notes = "Speak after sacrament"
        entry.isArchived = true
        entry.archivedAt = Date(timeIntervalSince1970: 1_780_000_000)
        entry.snapshotCallingName = "Ward Clerk"
        entry.snapshotOrganization = "Bishopric"
        entry.snapshotPreviousHolder = "Old, Holder"
        entry.snapshotNewHolder = "New, Holder"

        let rec = record(type: "OpenCalling", name: CKRecordMapper.recordName(forOpenCalling: entry.id))
        CKRecordMapper.populate(rec, from: entry)
        let decoded = CKRecordMapper.openCalling(from: rec)
        // createdAt goes through CloudKit's Date storage; compare seconds.
        XCTAssertEqual(decoded?.createdAt.timeIntervalSince1970 ?? 0, entry.createdAt.timeIntervalSince1970, accuracy: 0.001)
        var normalized = decoded
        normalized?.createdAt = entry.createdAt
        XCTAssertEqual(normalized, entry)
    }

    /// Records and JSON written before the approval step exist with the old
    /// status rawValues — they must decode to the new ladder, never throw or
    /// silently reset (a throw in WardData decoding would wipe local data).
    func testLegacyStatusValuesDecode() throws {
        // CloudKit path.
        var entry = OpenCalling(slotID: UUID())
        let rec = record(type: "OpenCalling", name: CKRecordMapper.recordName(forOpenCalling: entry.id))
        CKRecordMapper.populate(rec, from: entry)
        rec["releaseStatus"] = "Open"
        rec["callStatus"] = "Accepted"
        var decoded = CKRecordMapper.openCalling(from: rec)
        XCTAssertEqual(decoded?.releaseStatus, .proposed)
        XCTAssertEqual(decoded?.callStatus, .called)
        rec["callStatus"] = "Selected"
        XCTAssertEqual(CKRecordMapper.openCalling(from: rec)?.callStatus, .proposed)
        rec["releaseStatus"] = "Bogus"
        XCTAssertEqual(CKRecordMapper.openCalling(from: rec)?.releaseStatus, ReleaseStatus.none)

        // JSON path.
        entry.releaseStatus = .proposed
        var json = String(data: try JSONEncoder().encode(entry), encoding: .utf8)!
        json = json.replacingOccurrences(of: "\"Proposed\"", with: "\"Open\"")
        decoded = try JSONDecoder().decode(OpenCalling.self, from: Data(json.utf8))
        XCTAssertEqual(decoded?.releaseStatus, .proposed)
    }

    func testRecordNameParsing() {
        let id = UUID()
        let parsed = CKRecordMapper.parse(recordName: "Member_\(id.uuidString)")
        XCTAssertEqual(parsed?.type, "Member")
        XCTAssertEqual(parsed?.id, id)
        XCTAssertEqual(CKRecordMapper.parse(recordName: "WardMeta")?.type, "WardMeta")
        XCTAssertNil(CKRecordMapper.parse(recordName: "garbage"))
    }

    func testWardMetaRoundTrip() {
        let meta = CKRecordMapper.WardMeta(
            wardName: "Valley View Ward (91375)",
            lastCallingsImport: Date(timeIntervalSince1970: 1_780_000_000),
            lastRosterImport: nil,
            schemaVersion: 1,
            importGeneration: 7,
            customTags: ["Youth Speaker", "New Move-In"]
        )
        let rec = record(type: "WardMeta", name: CKRecordMapper.wardMetaRecordName)
        CKRecordMapper.populate(rec, from: meta)
        XCTAssertEqual(CKRecordMapper.wardMeta(from: rec), meta)
    }
}
