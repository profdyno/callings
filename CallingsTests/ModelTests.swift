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

    func testMemberNameParsing() {
        let member = Member(name: "Alley, Raelyn Kay")
        XCTAssertEqual(member.lastName, "Alley")
        XCTAssertEqual(member.firstNames, "Raelyn Kay")
        XCTAssertEqual(member.displayName, "Raelyn Kay Alley")
    }
}
