import XCTest
@testable import Callings

final class ModelTests: XCTestCase {
    func testWardDataRoundTrip() throws {
        var data = WardData()
        var definition = CallingDefinition(name: "Elders Quorum President", organization: .eldersQuorum)
        definition.displayOrder = 0
        let member = Member(name: "Valiulis, John Peter", age: 40, gender: .male, priesthood: .melchizedek)
        data.callingDefinitions = [definition]
        data.members = [member]
        data.callingSlots = [CallingSlot(definitionID: definition.id, memberID: member.id)]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WardData.self, from: encoder.encode(data))

        XCTAssertEqual(decoded.members, data.members)
        XCTAssertEqual(decoded.callingDefinitions, data.callingDefinitions)
        XCTAssertEqual(decoded.callingSlots, data.callingSlots)
    }

    func testCriteriaMatching() {
        var criteria = CandidateCriteria()
        criteria.gender = .male
        criteria.minimumPriesthood = .melchizedek

        let elder = Member(name: "Smith, John", age: 40, gender: .male, priesthood: .melchizedek)
        let priest = Member(name: "Jones, Sam", age: 17, gender: .male, priesthood: .aaronic)
        let sister = Member(name: "Smith, Jane", age: 40, gender: .female)

        XCTAssertTrue(criteria.matches(elder))
        XCTAssertFalse(criteria.matches(priest))
        XCTAssertFalse(criteria.matches(sister))
    }

    func testOpenCallingDecodesDataSavedBeforeReleaseAssignee() throws {
        // releaseAssignedTo was added later; older saved entries lack the key.
        let json = """
        {"id":"\(UUID().uuidString)","slotID":"\(UUID().uuidString)","assignedTo":"Bishop",
         "releaseStatus":"Open","callStatus":"—","candidateIDs":[],"notes":"",
         "createdAt":"2026-01-01T00:00:00Z","isArchived":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(OpenCalling.self, from: Data(json.utf8))
        XCTAssertNil(entry.releaseAssignedTo)
        XCTAssertEqual(entry.assignedTo, .bishop)
        XCTAssertEqual(entry.releaseStatus, .proposed, "legacy \"Open\" maps to Proposed")
    }

    func testStageFilterMatchesEitherLadder() {
        var entry = OpenCalling(slotID: UUID())
        entry.releaseStatus = .proposed
        entry.callStatus = .none
        XCTAssertTrue(StageFilter.approve.matches(entry))
        XCTAssertFalse(StageFilter.releaseCall.matches(entry))

        entry.releaseStatus = .announced
        entry.callStatus = .approved
        XCTAssertTrue(StageFilter.releaseCall.matches(entry), "call ladder alone matches")
        XCTAssertFalse(StageFilter.approve.matches(entry))

        entry.releaseStatus = .released
        entry.callStatus = .none
        XCTAssertTrue(StageFilter.announceSustain.matches(entry), "release ladder alone matches")

        entry.callStatus = .called
        XCTAssertTrue(StageFilter.announceSustain.matches(entry))
    }

    func testNameWithinOrganizationStripsGroupPrefix() {
        let president = CallingDefinition(name: "Elders Quorum President", organization: .eldersQuorum)
        XCTAssertEqual(president.nameWithinOrganization, "President")

        // Not a prefix match — unchanged ("Ward Missionaries" vs "Ward Missionary")
        let missionary = CallingDefinition(name: "Ward Missionary", organization: .wardMissionaries)
        XCTAssertEqual(missionary.nameWithinOrganization, "Ward Missionary")

        // Calling that IS exactly the org name stays intact
        let bishop = CallingDefinition(name: "Bishopric", organization: .bishopric)
        XCTAssertEqual(bishop.nameWithinOrganization, "Bishopric")
    }

    func testNameWithinOrganizationShortening() {
        func make(_ name: String, _ org: OrganizationKind, _ subgroup: String? = nil) -> CallingDefinition {
            var d = CallingDefinition(name: name, organization: org)
            d.subgroup = subgroup
            return d
        }

        // "Ward <org>" prefix
        XCTAssertEqual(
            make("Ward Temple and Family History Consultant", .templeAndFamilyHistory).nameWithinOrganization,
            "Consultant"
        )
        XCTAssertEqual(
            make("Ward Temple and Family History Leader", .templeAndFamilyHistory).nameWithinOrganization,
            "Leader"
        )

        // Subgroup-stem prefixes
        XCTAssertEqual(
            make("Priests Quorum President", .aaronicPriesthoodQuorums, "Priests Quorum Presidency").nameWithinOrganization,
            "President"
        )
        XCTAssertEqual(
            make("Deacons Quorum Adviser", .aaronicPriesthoodQuorums, "Deacons Quorum Adult Leaders").nameWithinOrganization,
            "Adviser"
        )
        XCTAssertEqual(
            make("Gatherers of Light Class President", .youngWomen, "Gatherers of Light Class Presidency").nameWithinOrganization,
            "President"
        )

        // Activity/Service word redundant with the subgroup
        XCTAssertEqual(
            make("Elders Quorum Activity Coordinator", .eldersQuorum, "Activities").nameWithinOrganization,
            "Coordinator"
        )
        XCTAssertEqual(
            make("Relief Society Assistant Service Coordinator", .reliefSociety, "Service").nameWithinOrganization,
            "Asst Coordinator"
        )
        XCTAssertEqual(
            make("Relief Society Activity Committee Member", .reliefSociety, "Activities").nameWithinOrganization,
            "Committee Member"
        )
        XCTAssertEqual(
            make("Elders Quorum Service Committee Member", .eldersQuorum, "Service").nameWithinOrganization,
            "Committee Member"
        )

        // Assistant → Asst
        XCTAssertEqual(
            make("Elders Quorum Assistant Secretary", .eldersQuorum, "Elders Quorum Presidency").nameWithinOrganization,
            "Asst Secretary"
        )
        XCTAssertEqual(
            make("Ward Assistant Clerk--Membership", .bishopric).nameWithinOrganization,
            "Ward Asst Clerk--Membership"
        )

        // Empty-result guard: "Relief Society Teacher" under "Teachers"
        XCTAssertEqual(
            make("Relief Society Teacher", .reliefSociety, "Teachers").nameWithinOrganization,
            "Teacher"
        )

        // YW class-prefixed callings shorten regardless of subgroup
        XCTAssertEqual(
            make("Gatherers of Light Class Specialist", .youngWomen, "Additional Young Women Callings").nameWithinOrganization,
            "Specialist"
        )
        XCTAssertEqual(
            make("Young Women Class Adviser", .youngWomen, "Additional Young Women Callings").nameWithinOrganization,
            "Adviser"
        )

        // Activities Committee group names
        XCTAssertEqual(
            make("Activities Committee Member", .otherCallings, "Additional Callings").nameWithinOrganization,
            "Member"
        )
        XCTAssertEqual(
            make("Ward Activities Chair", .otherCallings, "Additional Callings").nameWithinOrganization,
            "Chair"
        )
    }

    func testActivitiesCommitteePredicateAndSubgroupRank() {
        XCTAssertTrue(CallingDefinition(name: "Ward Activities Chair", organization: .otherCallings).isActivitiesCommittee)
        XCTAssertTrue(CallingDefinition(name: "Activities Committee Member", organization: .otherCallings).isActivitiesCommittee)
        XCTAssertFalse(CallingDefinition(name: "Ward Greeter", organization: .otherCallings).isActivitiesCommittee)
        XCTAssertFalse(CallingDefinition(name: "Activities Committee Member", organization: .eldersQuorum).isActivitiesCommittee)

        // EQ/RS: presidency < Ministering < Teachers < rest
        XCTAssertLessThan(
            CallingDefinition.subgroupRank("Relief Society Presidency", organization: .reliefSociety),
            CallingDefinition.subgroupRank("Ministering", organization: .reliefSociety)
        )
        XCTAssertLessThan(
            CallingDefinition.subgroupRank("Ministering", organization: .eldersQuorum),
            CallingDefinition.subgroupRank("Teachers", organization: .eldersQuorum)
        )
        XCTAssertLessThan(
            CallingDefinition.subgroupRank("Teachers", organization: .eldersQuorum),
            CallingDefinition.subgroupRank("Activities", organization: .eldersQuorum)
        )
        // Other orgs untouched (flat rank)
        XCTAssertEqual(
            CallingDefinition.subgroupRank("Teachers", organization: .sundaySchool),
            CallingDefinition.subgroupRank("Music", organization: .sundaySchool)
        )
    }

    func testSubgroupDisplayNameCommitteeRenames() {
        XCTAssertEqual(CallingDefinition.subgroupDisplayName("Activities", organization: .eldersQuorum), "Activities Committee")
        XCTAssertEqual(CallingDefinition.subgroupDisplayName("Service", organization: .reliefSociety), "Service Committee")
        XCTAssertEqual(CallingDefinition.subgroupDisplayName("Activities", organization: .primary), "Activities")
        XCTAssertEqual(CallingDefinition.subgroupDisplayName("Teachers", organization: .reliefSociety), "Teachers")
    }

    func testMemberNameParsing() {
        let member = Member(name: "Alley, Raelyn Kay")
        XCTAssertEqual(member.lastName, "Alley")
        XCTAssertEqual(member.firstNames, "Raelyn Kay")
        XCTAssertEqual(member.displayName, "Raelyn Kay Alley")
    }
}
