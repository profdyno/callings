import XCTest
import CloudKit
@testable import Callings

@MainActor
final class SyncServiceTests: XCTestCase {

    private func makeService(role: SyncRole) -> (SyncService, WardStore) {
        let store = WardStore(persistence: PersistenceService(filename: "test-\(UUID().uuidString).json"))
        let stateStore = SyncStateStore(filename: "test-sync-\(UUID().uuidString).json")
        stateStore.settings.role = role
        let service = SyncService(store: store, stateStore: stateStore)
        return (service, store)
    }

    func testPermissionGatesForParticipant() {
        let (service, _) = makeService(role: .participant)
        XCTAssertTrue(service.canSet(releaseStatus: .proposed))
        XCTAssertFalse(service.canSet(releaseStatus: .approved), "approval is owner-only")
        XCTAssertTrue(service.canSet(releaseStatus: .released))
        XCTAssertFalse(service.canSet(releaseStatus: .announced), "sacrament-meeting step is owner-only")
        XCTAssertTrue(service.canSet(callStatus: .proposed))
        XCTAssertFalse(service.canSet(callStatus: .approved), "approval is owner-only")
        XCTAssertTrue(service.canSet(callStatus: .called))
        XCTAssertFalse(service.canSet(callStatus: .sustained), "sacrament-meeting step is owner-only")
        XCTAssertFalse(service.canImport)
    }

    func testPermissionGatesForOwnerAndSolo() {
        for role in [SyncRole.owner, .solo] {
            let (service, _) = makeService(role: role)
            XCTAssertTrue(service.canSet(releaseStatus: .approved))
            XCTAssertTrue(service.canSet(releaseStatus: .announced))
            XCTAssertTrue(service.canSet(callStatus: .approved))
            XCTAssertTrue(service.canSet(callStatus: .sustained))
            XCTAssertTrue(service.canImport)
        }
    }

    /// Regression: an unsent local edit must survive an incoming remote
    /// fetch. The baseline may only advance by the remote changes themselves;
    /// fast-forwarding it to the full store state swallowed local edits made
    /// while sync traffic was arriving (assignments/status changes appeared
    /// to "not sync" during active two-device sessions).
    func testRemoteApplyDoesNotSwallowUnsentLocalEdit() {
        let (service, store) = makeService(role: .owner)
        let definition = CallingDefinition(name: "Ward Clerk", organization: .bishopric)
        let slot = CallingSlot(definitionID: definition.id)
        var entry = OpenCalling(slotID: slot.id)
        var data = WardData()
        data.callingDefinitions = [definition]
        data.callingSlots = [slot]
        data.openCallings = [entry]
        store.apply(data)

        // Everything is synced: baseline == store.
        service.stateStore.baseline = store.data

        // Local edit that hasn't been enqueued yet (debounce pending).
        entry.assignedTo = .bishop
        store.updateOpenCalling(entry)

        // A remote fetch arrives for an unrelated record.
        let zoneID = CKRecordZone.ID(zoneName: "WardZone", ownerName: CKCurrentUserDefaultName)
        let remoteMember = Member(name: "Remote, Person")
        let record = CKRecord(
            recordType: "Member",
            recordID: CKRecord.ID(recordName: CKRecordMapper.recordName(forMember: remoteMember.id), zoneID: zoneID)
        )
        CKRecordMapper.populate(record, from: remoteMember)
        service.apply(modifications: [record], deletions: [])

        // The remote member landed in both store and baseline...
        XCTAssertTrue(store.data.members.contains { $0.id == remoteMember.id })
        // ...but the unsent local edit still differs from the baseline, so
        // the next diff will enqueue it.
        let changes = SnapshotDiffer.diff(baseline: service.stateStore.baseline!, current: store.data)
        XCTAssertEqual(changes.savedRecordNames, [CKRecordMapper.recordName(forOpenCalling: entry.id)])
    }

    func testRemoteApplyOfSameRecordWinsOverUnsentEdit() {
        let (service, store) = makeService(role: .owner)
        var entry = OpenCalling(slotID: UUID())
        var data = WardData()
        data.openCallings = [entry]
        store.apply(data)
        service.stateStore.baseline = store.data

        // Unsent local edit, then a remote update to the SAME entry arrives.
        entry.notes = "local edit"
        store.updateOpenCalling(entry)

        var remoteEntry = entry
        remoteEntry.notes = "remote edit"
        let zoneID = CKRecordZone.ID(zoneName: "WardZone", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(
            recordType: "OpenCalling",
            recordID: CKRecord.ID(recordName: CKRecordMapper.recordName(forOpenCalling: entry.id), zoneID: zoneID)
        )
        CKRecordMapper.populate(record, from: remoteEntry)
        service.apply(modifications: [record], deletions: [])

        // Remote apply is authoritative for that record, and no stale
        // re-send is queued (baseline matches the store).
        XCTAssertEqual(store.data.openCallings[0].notes, "remote edit")
        XCTAssertTrue(SnapshotDiffer.diff(baseline: service.stateStore.baseline!, current: store.data).isEmpty)
    }

    /// Loopback: device A updates an EXISTING entry's assignment/status via
    /// the same store call the table menus use; the diffed record is applied
    /// to device B. Covers the full local pipeline (store → diff → mapper →
    /// apply) for updates, not just creations.
    func testAssignmentUpdateRoundTripsBetweenDevices() {
        let (serviceA, storeA) = makeService(role: .owner)
        let (serviceB, storeB) = makeService(role: .participant)

        // Both devices already have the synced entry.
        let definition = CallingDefinition(name: "Ward Clerk", organization: .bishopric)
        let slot = CallingSlot(definitionID: definition.id)
        var entry = OpenCalling(slotID: slot.id)
        var data = WardData()
        data.callingDefinitions = [definition]
        data.callingSlots = [slot]
        data.openCallings = [entry]
        storeA.apply(data)
        storeB.apply(data)
        serviceA.stateStore.baseline = storeA.data
        serviceB.stateStore.baseline = storeB.data

        // A assigns a bishopric member, selects the member to call, sets status —
        // exactly what the table menu cells do. Assignments stick; the Actions
        // tab routes the sustain step to the Exec Secretary by status alone.
        entry.assignedTo = .firstCounselor
        entry.releaseAssignedTo = .bishop
        entry.callStatus = .called
        storeA.updateOpenCalling(entry)
        XCTAssertEqual(storeA.data.openCallings[0].assignedTo, .firstCounselor)

        // The diff must catch it...
        let changes = SnapshotDiffer.diff(baseline: serviceA.stateStore.baseline!, current: storeA.data)
        XCTAssertEqual(changes.savedRecordNames, [CKRecordMapper.recordName(forOpenCalling: entry.id)])

        // ...the mapper builds the wire record from A's store...
        let zoneID = CKRecordZone.ID(zoneName: "WardZone", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(
            recordType: "OpenCalling",
            recordID: CKRecord.ID(recordName: changes.savedRecordNames[0], zoneID: zoneID)
        )
        CKRecordMapper.populate(record, from: storeA.data.openCallings[0])

        // ...and B applies it.
        serviceB.apply(modifications: [record], deletions: [])
        XCTAssertEqual(storeB.data.openCallings[0].assignedTo, .firstCounselor)
        XCTAssertEqual(storeB.data.openCallings[0].releaseAssignedTo, .bishop)
        XCTAssertEqual(storeB.data.openCallings[0].callStatus, .called)
    }

    func testPrepareForResyncWipesDataButKeepsRole() {
        let (service, store) = makeService(role: .participant)
        service.stateStore.settings.zoneOwnerName = "_owner"
        var data = WardData()
        data.members = [Member(name: "Stale, Person")]
        store.apply(data)
        service.stateStore.baseline = store.data

        service.prepareForResync()

        XCTAssertTrue(store.data.members.isEmpty, "local data wiped for re-download")
        XCTAssertEqual(service.stateStore.baseline, WardData())
        XCTAssertNil(service.stateStore.engineStateData, "engine refetches from scratch")
        XCTAssertEqual(service.stateStore.settings.role, .participant, "role survives")
        XCTAssertEqual(service.stateStore.settings.zoneOwnerName, "_owner")
    }

    func testReconcileArchivesDanglingEntriesAfterRemoteImport() {
        let (service, store) = makeService(role: .participant)
        let definition = CallingDefinition(name: "Ward Clerk", organization: .bishopric)
        let survivingSlot = CallingSlot(definitionID: definition.id)
        var data = WardData()
        data.callingDefinitions = [definition]
        data.callingSlots = [survivingSlot]
        // One entry points at a surviving slot, one at a slot the remote
        // import deleted.
        data.openCallings = [
            OpenCalling(slotID: survivingSlot.id),
            OpenCalling(slotID: UUID()),
        ]
        store.apply(data)

        service.reconcileAfterRemoteImport()

        XCTAssertFalse(store.data.openCallings[0].isArchived)
        XCTAssertTrue(store.data.openCallings[1].isArchived)
    }
}
