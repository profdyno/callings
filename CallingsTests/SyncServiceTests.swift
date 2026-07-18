import XCTest
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
        XCTAssertTrue(service.canSet(releaseStatus: .open))
        XCTAssertTrue(service.canSet(releaseStatus: .released))
        XCTAssertFalse(service.canSet(releaseStatus: .announced), "sacrament-meeting step is owner-only")
        XCTAssertTrue(service.canSet(callStatus: .selected))
        XCTAssertTrue(service.canSet(callStatus: .accepted))
        XCTAssertFalse(service.canSet(callStatus: .sustained), "sacrament-meeting step is owner-only")
        XCTAssertFalse(service.canImport)
    }

    func testPermissionGatesForOwnerAndSolo() {
        for role in [SyncRole.owner, .solo] {
            let (service, _) = makeService(role: role)
            XCTAssertTrue(service.canSet(releaseStatus: .announced))
            XCTAssertTrue(service.canSet(callStatus: .sustained))
            XCTAssertTrue(service.canImport)
        }
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
