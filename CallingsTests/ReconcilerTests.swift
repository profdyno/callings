import XCTest
@testable import Callings

final class ReconcilerTests: XCTestCase {

    private func makeRow(
        _ calling: String,
        org: OrganizationKind = .eldersQuorum,
        subgroup: String? = nil,
        holder: String? = nil
    ) -> ParsedCallingRow {
        ParsedCallingRow(
            organization: org,
            subgroup: subgroup,
            callingName: calling,
            isCustom: false,
            holderName: holder,
            sustainedDate: nil,
            isSetApart: false
        )
    }

    func testRosterImportAddsAndUpdates() {
        let parsed = [
            ParsedMember(name: "Smith, John", age: 40, gender: .male, priesthood: .melchizedek),
            ParsedMember(name: "Smith, Jane", age: 38, gender: .female),
        ]
        let (data, summary) = ImportReconciler.applyRoster(parsed, to: WardData())
        XCTAssertEqual(summary.membersAdded, 2)
        XCTAssertEqual(data.members.count, 2)

        // Re-import updates in place, preserving IDs and user category.
        var updatedData = data
        updatedData.members[0].category = .notActive
        let originalID = updatedData.members[0].id
        let (data2, summary2) = ImportReconciler.applyRoster(parsed, to: updatedData)
        XCTAssertEqual(summary2.membersAdded, 0)
        XCTAssertEqual(summary2.membersUpdated, 2)
        XCTAssertEqual(data2.members[0].id, originalID)
        XCTAssertEqual(data2.members[0].category, .notActive)
    }

    func testRosterImportDoesNotMergeSimilarNames() {
        let parsed = [
            ParsedMember(name: "Bingham, Ryan", age: 50, gender: .male),
            ParsedMember(name: "Bingham, Ryan Kirk Jr.", age: 20, gender: .male),
        ]
        let (data, summary) = ImportReconciler.applyRoster(parsed, to: WardData())
        XCTAssertEqual(summary.membersAdded, 2)
        XCTAssertEqual(data.members.count, 2)
    }

    func testRosterImportDeactivatesMissingMembers() {
        let (data, _) = ImportReconciler.applyRoster(
            [ParsedMember(name: "Smith, John", age: 40, gender: .male),
             ParsedMember(name: "Jones, Amy", age: 30, gender: .female)],
            to: WardData()
        )
        let (data2, summary) = ImportReconciler.applyRoster(
            [ParsedMember(name: "Smith, John", age: 41, gender: .male)],
            to: data
        )
        XCTAssertEqual(summary.membersDeactivated, 1)
        XCTAssertEqual(data2.members.count, 2)
        XCTAssertFalse(data2.members.first { $0.name == "Jones, Amy" }!.isActiveOnRoster)
    }

    func testCallingsImportMatchesHolderByPrefix() {
        let (roster, _) = ImportReconciler.applyRoster(
            [ParsedMember(name: "Woodruff, Samuel B", age: 40, gender: .male)],
            to: WardData()
        )
        let parsed = ParsedWardCallings(rows: [makeRow("Ward Clerk", org: .bishopric, holder: "Woodruff, Sam")])
        let (data, summary) = ImportReconciler.applyCallings(parsed, to: roster)
        XCTAssertTrue(summary.placeholdersCreated.isEmpty)
        XCTAssertEqual(data.callingSlots.first?.memberID, roster.members[0].id)
    }

    func testCallingsImportCreatesPlaceholderForUnknownHolder() {
        let parsed = ParsedWardCallings(rows: [makeRow("Ward Clerk", org: .bishopric, holder: "Unknown, Person")])
        let (data, summary) = ImportReconciler.applyCallings(parsed, to: WardData())
        XCTAssertEqual(summary.placeholdersCreated, ["Unknown, Person"])
        XCTAssertTrue(data.members.first!.isPlaceholder)
    }

    func testReimportPreservesUserEditsAndKeepsOpenCallings() {
        let parsed = ParsedWardCallings(rows: [
            makeRow("Elders Quorum President", holder: "Smith, John"),
            makeRow("Elders Quorum Secretary", holder: nil),
        ])
        var (data, _) = ImportReconciler.applyCallings(parsed, to: WardData())

        // User edits display order and opens the secretary calling.
        data.callingDefinitions[1].displayOrder = 5
        let secretarySlot = data.callingSlots[1]
        data.openCallings.append(OpenCalling(slotID: secretarySlot.id, releaseStatus: .none))

        let (data2, summary) = ImportReconciler.applyCallings(parsed, to: data)
        XCTAssertEqual(summary.definitionsCreated, 0)
        XCTAssertEqual(data2.callingDefinitions[1].displayOrder, 5)
        // Secretary still vacant → entry survives, repointed at the rebuilt slot.
        let entry = data2.openCallings[0]
        XCTAssertFalse(entry.isArchived)
        XCTAssertEqual(entry.slotID, data2.callingSlots[1].id)
    }

    func testReimportArchivesWhenHolderChanges() {
        let before = ParsedWardCallings(rows: [makeRow("Elders Quorum President", holder: "Smith, John")])
        var (data, _) = ImportReconciler.applyCallings(before, to: WardData())
        data.openCallings.append(OpenCalling(slotID: data.callingSlots[0].id))

        let after = ParsedWardCallings(rows: [makeRow("Elders Quorum President", holder: "Jones, Robert")])
        let (data2, summary) = ImportReconciler.applyCallings(after, to: data)

        XCTAssertEqual(summary.openCallingsArchived, ["Elders Quorum President"])
        let entry = data2.openCallings[0]
        XCTAssertTrue(entry.isArchived)
        XCTAssertEqual(entry.snapshotPreviousHolder, "Smith, John")
        XCTAssertEqual(entry.snapshotNewHolder, "Jones, Robert")
        XCTAssertEqual(entry.snapshotCallingName, "Elders Quorum President")
    }

    func testReimportArchivesWhenVacantSeatFilled() {
        let before = ParsedWardCallings(rows: [makeRow("Elders Quorum Secretary", holder: nil)])
        var (data, _) = ImportReconciler.applyCallings(before, to: WardData())
        data.openCallings.append(OpenCalling(slotID: data.callingSlots[0].id, releaseStatus: .none))

        let after = ParsedWardCallings(rows: [makeRow("Elders Quorum Secretary", holder: "New, Person")])
        let (data2, summary) = ImportReconciler.applyCallings(after, to: data)

        XCTAssertEqual(summary.openCallingsArchived.count, 1)
        XCTAssertTrue(data2.openCallings[0].isArchived)
        XCTAssertEqual(data2.openCallings[0].snapshotNewHolder, "New, Person")
    }

    func testSeedRulesOrderPresidencyFirst() {
        XCTAssertLessThan(
            CallingSeedRules.displayOrder(for: "Elders Quorum President"),
            CallingSeedRules.displayOrder(for: "Elders Quorum First Counselor")
        )
        XCTAssertLessThan(
            CallingSeedRules.displayOrder(for: "Elders Quorum First Counselor"),
            CallingSeedRules.displayOrder(for: "Elders Quorum Second Counselor")
        )
        XCTAssertLessThan(
            CallingSeedRules.displayOrder(for: "Elders Quorum Second Counselor"),
            CallingSeedRules.displayOrder(for: "Elders Quorum Secretary")
        )
        XCTAssertLessThan(
            CallingSeedRules.displayOrder(for: "Elders Quorum Secretary"),
            CallingSeedRules.displayOrder(for: "Elders Quorum Assistant Secretary")
        )
    }

    func testSeedCriteriaByOrganization() {
        let rs = CallingSeedRules.criteria(for: "Relief Society Teacher", organization: .reliefSociety, subgroup: "Teachers")
        XCTAssertEqual(rs.gender, .female)
        XCTAssertEqual(rs.minAge, 18)

        let eq = CallingSeedRules.criteria(for: "Elders Quorum President", organization: .eldersQuorum, subgroup: nil)
        XCTAssertEqual(eq.gender, .male)
        XCTAssertEqual(eq.minimumPriesthood, .melchizedek)

        let ywClass = CallingSeedRules.criteria(
            for: "Class President",
            organization: .youngWomen,
            subgroup: "Gatherers of Light Class Presidency"
        )
        XCTAssertEqual(ywClass.gender, .female)
        XCTAssertEqual(ywClass.requiredClassAssignments, ["Gatherers of Light"])
        XCTAssertEqual(ywClass.maxAge, 18)
    }
}
