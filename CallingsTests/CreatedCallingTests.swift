import XCTest
@testable import Callings

@MainActor
final class CreatedCallingTests: XCTestCase {

    private func makeStore() -> WardStore {
        let store = WardStore(persistence: PersistenceService(filename: "test-\(UUID().uuidString).json"))
        var president = CallingDefinition(name: "Elders Quorum President", organization: .eldersQuorum)
        president.displayOrder = 0
        var counselor = CallingDefinition(name: "Elders Quorum First Counselor", organization: .eldersQuorum)
        counselor.displayOrder = 10
        var data = WardData()
        data.callingDefinitions = [president, counselor]
        data.callingSlots = [
            CallingSlot(definitionID: president.id, importOrder: 0),
            CallingSlot(definitionID: counselor.id, importOrder: 1),
        ]
        store.apply(data)
        return store
    }

    func testCreateCallingInsertsHalfway() {
        let store = makeStore()
        let anchor = store.data.callingDefinitions[0]  // order 0, next is 10
        let slot = store.createCalling(named: "Elders Quorum Historian", after: anchor)

        let created = store.definition(for: slot)
        XCTAssertEqual(created?.displayOrder, 5)
        XCTAssertTrue(created?.isPending == true)
        XCTAssertNil(store.slotsByID[slot.id]?.memberID, "starts vacant")
    }

    func testCreateCallingAtEndAppendsAfterAnchor() {
        let store = makeStore()
        let anchor = store.data.callingDefinitions[1]  // order 10, no next
        let slot = store.createCalling(named: "Elders Quorum Historian", after: anchor)
        XCTAssertEqual(store.definition(for: slot)?.displayOrder, 20)
    }

    func testPendingCallingSurvivesImport() {
        let store = makeStore()
        let anchor = store.data.callingDefinitions[0]
        let slot = store.createCalling(named: "Elders Quorum Historian", after: anchor)
        store.openCallingEntry(for: store.slotsByID[slot.id]!)

        // Import knows nothing about the created calling.
        let parsed = ParsedWardCallings(rows: [
            ParsedCallingRow(organization: .eldersQuorum, subgroup: nil, callingName: "Elders Quorum President",
                             isCustom: false, holderName: "Smith, John", sustainedDate: nil, isSetApart: false)
        ])
        let (data, _) = ImportReconciler.applyCallings(parsed, to: store.data)

        let preserved = data.callingSlots.first { $0.id == slot.id }
        XCTAssertNotNil(preserved, "pending slot keeps its identity through the import")
        XCTAssertTrue(data.callingDefinitions.first { $0.name == "Elders Quorum Historian" }!.isPending)
        XCTAssertFalse(data.openCallings[0].isArchived, "open entry stays attached")
        XCTAssertEqual(data.openCallings[0].slotID, slot.id)
    }

    func testImportConfirmsPendingCalling() {
        let store = makeStore()
        let anchor = store.data.callingDefinitions[0]
        let slot = store.createCalling(named: "Elders Quorum Historian", after: anchor)
        store.openCallingEntry(for: store.slotsByID[slot.id]!)

        // LCR now includes the calling, still vacant.
        let parsed = ParsedWardCallings(rows: [
            ParsedCallingRow(organization: .eldersQuorum, subgroup: nil, callingName: "Elders Quorum Historian",
                             isCustom: false, holderName: nil, sustainedDate: nil, isSetApart: false)
        ])
        let (data, _) = ImportReconciler.applyCallings(parsed, to: store.data)

        let definition = data.callingDefinitions.first { $0.name == "Elders Quorum Historian" }!
        XCTAssertFalse(definition.isPending, "matched import clears the pending flag")
        XCTAssertNil(data.callingSlots.first { $0.id == slot.id }, "PDF slot replaces the local one")
        // Vacant→vacant: the open entry repoints at the PDF slot.
        let entry = data.openCallings[0]
        XCTAssertFalse(entry.isArchived)
        XCTAssertEqual(data.callingSlots.first { $0.definitionID == definition.id }?.id, entry.slotID)
    }

    func testChecklistMarkdown() {
        let store = makeStore()
        var data = store.data
        let holder = Member(name: "Jones, Amy")
        let candidate = Member(name: "Smith, John")
        data.members = [holder, candidate]
        data.callingSlots[0].memberID = holder.id
        store.apply(data)

        // Release assigned to 2nd counselor; call assigned to bishop.
        let slot = store.data.callingSlots[0]
        var entry = store.openCallingEntry(for: slot)
        entry.releaseStatus = .released
        entry.releaseAssignedTo = .secondCounselor
        entry.assignedTo = .bishop
        entry.candidateIDs = [candidate.id]
        entry.memberToBeCalledID = candidate.id
        entry.callStatus = .accepted
        store.updateOpenCalling(entry)

        // A pending calling for the Ward Clerk block.
        store.createCalling(named: "Elders Quorum Historian", after: store.data.callingDefinitions[0])

        let markdown = ActionChecklistBuilder.markdown(from: store, date: Date(timeIntervalSince1970: 1_784_000_000))

        XCTAssertTrue(markdown.hasPrefix("# Calling Actions —"))
        XCTAssertTrue(markdown.contains("**Bishop**"))
        XCTAssertTrue(markdown.contains("- [ ] Call Smith, John — Elders Quorum President (Accepted)"))
        XCTAssertTrue(markdown.contains("**2nd Counselor**"))
        XCTAssertTrue(markdown.contains("- [ ] Release Jones, Amy — Elders Quorum President (Released)"))
        XCTAssertTrue(markdown.contains("**Ward Clerk**"))
        XCTAssertTrue(markdown.contains("- [ ] Add to LCR — Elders Quorum Historian (Elders Quorum)"))
        XCTAssertFalse(markdown.contains("**1st Counselor**"), "empty sections omitted")
    }

    func testChecklistSelectCandidateItem() {
        let store = makeStore()
        let slot = store.data.callingSlots[1]
        var entry = store.openCallingEntry(for: slot)
        entry.releaseStatus = .none
        store.updateOpenCalling(entry)

        let markdown = ActionChecklistBuilder.markdown(from: store)
        XCTAssertTrue(markdown.contains("**Select Candidate**"))
        XCTAssertTrue(markdown.contains("- [ ] Select candidate — Elders Quorum First Counselor (0 candidates)"))

        // The structured groups feeding the Actions table put the item in the
        // Select Candidate section with the slot wired for the picker.
        let groups = ActionChecklistBuilder.groups(from: store)
        let section = groups.first { $0.title == ActionChecklistBuilder.selectCandidateTitle }
        XCTAssertEqual(section?.items.first?.slotID, slot.id)
    }
}
