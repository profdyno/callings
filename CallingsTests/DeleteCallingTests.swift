import XCTest
@testable import Callings

@MainActor
final class DeleteCallingTests: XCTestCase {

    private func makeStore(withHolder: Bool = true) -> (WardStore, CallingDefinition, Member) {
        let store = WardStore(persistence: PersistenceService(filename: "test-\(UUID().uuidString).json"))
        let holder = Member(name: "Jones, Amy")
        var definition = CallingDefinition(name: "Relief Society Teacher", organization: .reliefSociety)
        definition.displayOrder = 70
        var data = WardData()
        data.members = [holder]
        data.callingDefinitions = [definition]
        data.callingSlots = [CallingSlot(definitionID: definition.id, memberID: withHolder ? holder.id : nil)]
        store.apply(data)
        return (store, definition, holder)
    }

    func testDeletingAppCreatedCallingRemovesImmediately() {
        let (store, anchor, _) = makeStore()
        let slot = store.createCalling(named: "RS Historian", after: anchor)
        store.openCallingEntry(for: store.slotsByID[slot.id]!)
        let created = store.definition(for: slot)!

        store.requestDeletion(of: created)

        XCTAssertNil(store.data.callingDefinitions.first { $0.id == created.id })
        XCTAssertNil(store.slotsByID[slot.id])
        XCTAssertTrue(store.activeOpenCallings.isEmpty)
    }

    func testDeletingLCRCallingMarksAndOpensRelease() {
        let (store, definition, holder) = makeStore()
        store.requestDeletion(of: definition)

        let marked = store.data.callingDefinitions[0]
        XCTAssertTrue(marked.isMarkedForDeletion)
        // The holder's release is now tracked in Open Callings.
        let entry = store.activeOpenCallings.first
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.releaseStatus, .proposed)
        XCTAssertEqual(store.slotsByID[entry!.slotID]?.memberID, holder.id)

        store.cancelDeletion(of: marked)
        XCTAssertFalse(store.data.callingDefinitions[0].isMarkedForDeletion)
    }

    func testImportWithoutDeletedCallingRemovesIt() {
        let (store, definition, _) = makeStore()
        store.requestDeletion(of: definition)

        // Re-import no longer contains the calling → gone, entry archived.
        let parsed = ParsedWardCallings(rows: [])
        let (data, summary) = ImportReconciler.applyCallings(parsed, to: store.data)

        XCTAssertTrue(data.callingDefinitions.isEmpty)
        XCTAssertTrue(data.callingSlots.isEmpty)
        XCTAssertTrue(data.openCallings.allSatisfy(\.isArchived))
        XCTAssertEqual(data.openCallings.first?.snapshotPreviousHolder, "Jones, Amy")
        XCTAssertTrue(summary.openCallingsArchived.contains("Relief Society Teacher (deleted)"))
    }

    func testImportStillContainingDeletedCallingKeepsMark() {
        let (store, definition, _) = makeStore()
        store.requestDeletion(of: definition)

        let parsed = ParsedWardCallings(rows: [
            ParsedCallingRow(organization: .reliefSociety, subgroup: nil, callingName: "Relief Society Teacher",
                             isCustom: false, holderName: "Jones, Amy", sustainedDate: nil, isSetApart: false)
        ])
        let (data, _) = ImportReconciler.applyCallings(parsed, to: store.data)

        XCTAssertTrue(data.callingDefinitions[0].isMarkedForDeletion, "clerk hasn't removed it in LCR yet")
    }

    func testChecklistIncludesDeleteAction() {
        let (store, definition, _) = makeStore()
        store.requestDeletion(of: definition)

        let markdown = ActionChecklistBuilder.markdown(from: store)
        XCTAssertTrue(markdown.contains("**Ward Clerk**"))
        XCTAssertTrue(markdown.contains("- [ ] Delete from LCR — Relief Society Teacher (Relief Society)"))
    }
}
