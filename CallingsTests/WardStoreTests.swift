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

    /// Checklist rows route by status: the Exec Secretary owns approvals and
    /// the sacrament-meeting steps; the assigned member owns the step in
    /// between. The assignment fields themselves never change hands.
    func testChecklistRoutesByStatus() {
        let (store, slot, _, new) = makeStore()
        var entry = store.openCallingEntry(for: slot)
        entry.releaseAssignedTo = .secondCounselor
        entry.assignedTo = .bishop
        entry.memberToBeCalledID = new.id
        entry.callStatus = .proposed
        store.updateOpenCalling(entry)

        func items(_ group: String) -> [String] {
            ActionChecklistBuilder.groups(from: store)
                .first { $0.title == group }?.items.map(\.verb) ?? []
        }

        // Proposed: both halves wait on the Exec Secretary's approval.
        XCTAssertEqual(items("Exec Secretary"), ["Approve Release", "Approve Call"])

        // Approved: each half moves to its assigned member.
        entry = store.data.openCallings[0]
        entry.releaseStatus = .approved
        entry.callStatus = .approved
        store.updateOpenCalling(entry)
        XCTAssertEqual(items("2nd Counselor"), ["Release"])
        XCTAssertEqual(items("Bishop"), ["Call"])
        XCTAssertEqual(items("Exec Secretary"), [])

        // Released/Called: back to the Exec Secretary for sacrament meeting,
        // with the assignments untouched.
        entry = store.data.openCallings[0]
        entry.releaseStatus = .released
        entry.callStatus = .called
        store.updateOpenCalling(entry)
        XCTAssertEqual(items("Exec Secretary"), ["Announce Release", "Sustain"])
        XCTAssertEqual(store.data.openCallings[0].releaseAssignedTo, .secondCounselor)
        XCTAssertEqual(store.data.openCallings[0].assignedTo, .bishop)
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
