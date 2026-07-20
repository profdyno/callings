import XCTest
@testable import Callings

@MainActor
final class WardStoreTests: XCTestCase {

    private func makeStore() -> (WardStore, CallingSlot, Member, Member) {
        let store = WardStore(persistence: PersistenceService(filename: "test-\(UUID().uuidString).json"))
        let old = Member(name: "Old, Holder")
        let new = Member(name: "New, Holder")
        let definition = CallingDefinition(name: "Elders Quorum President", organization: .eldersQuorum)
        let slot = CallingSlot(definitionID: definition.id, memberID: old.id, holderNameRaw: "Old, Holder")
        var data = WardData()
        data.members = [old, new]
        data.callingDefinitions = [definition]
        data.callingSlots = [slot]
        store.apply(data)
        return (store, slot, old, new)
    }

    func testAnnouncedPlusSustainedMovesNewMemberIntoSlot() {
        let (store, slot, _, new) = makeStore()
        var entry = store.openCallingEntry(for: slot)
        entry.memberToBeCalledID = new.id
        entry.releaseStatus = .announced
        entry.callStatus = .sustained
        store.updateOpenCalling(entry)

        // Ward Callings view now shows the new member in the slot.
        XCTAssertEqual(store.slotsByID[slot.id]?.memberID, new.id)
        XCTAssertNotNil(store.slotsByID[slot.id]?.sustainedDate)
        XCTAssertFalse(store.slotsByID[slot.id]!.isSetApart)

        // The finished entry is archived with a full snapshot.
        XCTAssertTrue(store.activeOpenCallings.isEmpty)
        let archived = store.archivedOpenCallings.first
        XCTAssertEqual(archived?.snapshotPreviousHolder, "Old, Holder")
        XCTAssertEqual(archived?.snapshotNewHolder, "New, Holder")
        XCTAssertEqual(archived?.snapshotCallingName, "Elders Quorum President")
    }

    func testNotCompleteUntilBothStatusesFinish() {
        let (store, slot, old, new) = makeStore()
        var entry = store.openCallingEntry(for: slot)
        entry.memberToBeCalledID = new.id
        entry.releaseStatus = .released   // not yet announced
        entry.callStatus = .sustained
        store.updateOpenCalling(entry)

        XCTAssertEqual(store.slotsByID[slot.id]?.memberID, old.id)
        XCTAssertEqual(store.activeOpenCallings.count, 1)
    }

    func testVacantSlotCompletesWithoutRelease() {
        let store = WardStore(persistence: PersistenceService(filename: "test-\(UUID().uuidString).json"))
        let new = Member(name: "New, Holder")
        let definition = CallingDefinition(name: "Elders Quorum Secretary", organization: .eldersQuorum)
        let slot = CallingSlot(definitionID: definition.id, memberID: nil)
        var data = WardData()
        data.members = [new]
        data.callingDefinitions = [definition]
        data.callingSlots = [slot]
        store.apply(data)

        var entry = store.openCallingEntry(for: slot)
        XCTAssertEqual(entry.releaseStatus, .none)
        entry.memberToBeCalledID = new.id
        entry.callStatus = .sustained
        store.updateOpenCalling(entry)

        XCTAssertEqual(store.slotsByID[slot.id]?.memberID, new.id)
        XCTAssertTrue(store.activeOpenCallings.isEmpty)
    }

    func testCalledOrReleasedHandsOwnershipToExecSecretary() {
        let (store, slot, _, new) = makeStore()
        var entry = store.openCallingEntry(for: slot)
        entry.releaseAssignedTo = .secondCounselor
        entry.assignedTo = .bishop
        entry.memberToBeCalledID = new.id
        store.updateOpenCalling(entry)

        // Reaching Released hands the release to the Exec Secretary.
        entry = store.data.openCallings[0]
        entry.releaseStatus = .released
        store.updateOpenCalling(entry)
        XCTAssertEqual(store.data.openCallings[0].releaseAssignedTo, .execSecretary)
        XCTAssertEqual(store.data.openCallings[0].assignedTo, .bishop, "call side untouched")

        // Reaching Called (accepted) hands the call to the Exec Secretary.
        entry = store.data.openCallings[0]
        entry.callStatus = .accepted
        store.updateOpenCalling(entry)
        XCTAssertEqual(store.data.openCallings[0].assignedTo, .execSecretary)

        // Only the transition reassigns — a manual change afterwards sticks.
        entry = store.data.openCallings[0]
        entry.assignedTo = .firstCounselor
        store.updateOpenCalling(entry)
        XCTAssertEqual(store.data.openCallings[0].assignedTo, .firstCounselor)
    }

    func testAddTagTrimsAndDeduplicates() {
        let (store, _, _, _) = makeStore()
        store.addTag("  Youth Speaker  ")
        store.addTag("youth speaker")           // duplicate of custom tag
        store.addTag("Moving Soon")             // collides with built-in
        store.addTag("   ")                     // blank
        XCTAssertEqual(store.data.customTags, ["Youth Speaker"])
    }

    func testDeleteTagClearsItFromMembers() {
        let (store, _, old, new) = makeStore()
        store.addTag("Temp")
        store.setCategory(.other("Temp"), forMember: old.id)
        store.setCategory(.movingSoon, forMember: new.id)
        XCTAssertEqual(store.memberCount(withTag: "Temp"), 1)

        store.deleteTag("Temp")

        XCTAssertTrue(store.data.customTags.isEmpty)
        XCTAssertEqual(store.member(old.id)?.category, MemberCategory.none)
        XCTAssertEqual(store.member(new.id)?.category, .movingSoon)  // built-ins untouched
    }
}
