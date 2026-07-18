import XCTest
@testable import Callings

final class SnapshotDifferTests: XCTestCase {

    private func baseData() -> WardData {
        var data = WardData()
        let member = Member(name: "Smith, John")
        let definition = CallingDefinition(name: "Ward Clerk", organization: .bishopric)
        data.members = [member]
        data.callingDefinitions = [definition]
        data.callingSlots = [CallingSlot(definitionID: definition.id, memberID: member.id)]
        return data
    }

    func testNoChanges() {
        let data = baseData()
        XCTAssertTrue(SnapshotDiffer.diff(baseline: data, current: data).isEmpty)
    }

    func testEditProducesSave() {
        let baseline = baseData()
        var current = baseline
        current.members[0].category = .movingSoon

        let changes = SnapshotDiffer.diff(baseline: baseline, current: current)
        XCTAssertEqual(changes.savedRecordNames, [CKRecordMapper.recordName(forMember: baseline.members[0].id)])
        XCTAssertTrue(changes.deletedRecordNames.isEmpty)
    }

    func testAddAndDelete() {
        let baseline = baseData()
        var current = baseline
        let newEntry = OpenCalling(slotID: baseline.callingSlots[0].id)
        current.openCallings.append(newEntry)
        let removedSlot = current.callingSlots.removeFirst()

        let changes = SnapshotDiffer.diff(baseline: baseline, current: current)
        XCTAssertEqual(changes.savedRecordNames, [CKRecordMapper.recordName(forOpenCalling: newEntry.id)])
        XCTAssertEqual(changes.deletedRecordNames, [CKRecordMapper.recordName(forSlot: removedSlot.id)])
    }

    func testImportWholesaleReplacement() {
        let baseline = baseData()
        var current = baseline
        // Simulate import: all slots replaced, meta bumped.
        let newSlot = CallingSlot(definitionID: baseline.callingDefinitions[0].id)
        current.callingSlots = [newSlot]
        current.importGeneration += 1
        current.lastCallingsImport = .now

        let changes = SnapshotDiffer.diff(baseline: baseline, current: current)
        XCTAssertTrue(changes.savedRecordNames.contains(CKRecordMapper.recordName(forSlot: newSlot.id)))
        XCTAssertTrue(changes.savedRecordNames.contains(CKRecordMapper.wardMetaRecordName))
        XCTAssertEqual(changes.deletedRecordNames, [CKRecordMapper.recordName(forSlot: baseline.callingSlots[0].id)])
    }

    func testMetaOnlyChange() {
        let baseline = baseData()
        var current = baseline
        current.wardName = "Valley View Ward"

        let changes = SnapshotDiffer.diff(baseline: baseline, current: current)
        XCTAssertEqual(changes.savedRecordNames, [CKRecordMapper.wardMetaRecordName])
    }
}
