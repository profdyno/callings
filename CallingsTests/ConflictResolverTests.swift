import XCTest
import CloudKit
@testable import Callings

final class ConflictResolverTests: XCTestCase {

    private let zoneID = CKRecordZone.ID(zoneName: "WardZone", ownerName: CKCurrentUserDefaultName)

    private func openCallingRecords() -> (client: CKRecord, server: CKRecord, ancestor: CKRecord) {
        var entry = OpenCalling(slotID: UUID())
        entry.notes = "original"
        entry.callStatus = .none
        let recordID = CKRecord.ID(recordName: CKRecordMapper.recordName(forOpenCalling: entry.id), zoneID: zoneID)

        let ancestor = CKRecord(recordType: "OpenCalling", recordID: recordID)
        CKRecordMapper.populate(ancestor, from: entry)
        let client = CKRecord(recordType: "OpenCalling", recordID: recordID)
        CKRecordMapper.populate(client, from: entry)
        let server = CKRecord(recordType: "OpenCalling", recordID: recordID)
        CKRecordMapper.populate(server, from: entry)
        return (client, server, ancestor)
    }

    func testDisjointFieldEditsBothSurvive() {
        let (client, server, ancestor) = openCallingRecords()
        client["notes"] = "client edit"
        server["callStatus"] = CallStatus.accepted.rawValue

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(merged["notes"] as? String, "client edit")
        XCTAssertEqual(merged["callStatus"] as? String, CallStatus.accepted.rawValue)
    }

    func testSameFieldClientWinsWhenChanged() {
        let (client, server, ancestor) = openCallingRecords()
        client["notes"] = "client edit"
        server["notes"] = "server edit"

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(merged["notes"] as? String, "client edit")
    }

    func testUntouchedFieldKeepsServerValue() {
        let (client, server, ancestor) = openCallingRecords()
        server["notes"] = "server edit"

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(merged["notes"] as? String, "server edit")
    }

    func testCandidateSetMerge() {
        let (client, server, ancestor) = openCallingRecords()
        let a = UUID().uuidString, b = UUID().uuidString, c = UUID().uuidString
        ancestor["candidateIDs"] = [a]
        client["candidateIDs"] = [a, b]        // client added b
        server["candidateIDs"] = [a, c]        // other device added c

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(Set(merged["candidateIDs"] as? [String] ?? []), Set([a, b, c]))
    }

    func testCandidateRemovalWins() {
        let (client, server, ancestor) = openCallingRecords()
        let a = UUID().uuidString, b = UUID().uuidString
        ancestor["candidateIDs"] = [a, b]
        client["candidateIDs"] = [b]           // client removed a
        server["candidateIDs"] = [a, b]

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(merged["candidateIDs"] as? [String], [b])
    }

    func testArchiveLatchWins() {
        let (client, server, ancestor) = openCallingRecords()
        // Server archived the entry (e.g. import saw the calling filled).
        server["isArchived"] = 1
        server["snapshotNewHolder"] = "New, Holder"
        server["callStatus"] = CallStatus.sustained.rawValue
        // Client, offline, tried to advance the call status and edit notes.
        client["callStatus"] = CallStatus.accepted.rawValue
        client["notes"] = "offline note"

        let merged = ConflictResolver.merge(client: client, server: server, ancestor: ancestor)
        XCTAssertEqual(merged["isArchived"] as? Int, 1)
        XCTAssertEqual(merged["callStatus"] as? String, CallStatus.sustained.rawValue, "archive latch keeps server status")
        XCTAssertEqual(merged["snapshotNewHolder"] as? String, "New, Holder")
        XCTAssertEqual(merged["notes"] as? String, "offline note", "harmless fields still merge")
    }
}
