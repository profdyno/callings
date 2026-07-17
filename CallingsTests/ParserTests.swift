import XCTest
import PDFKit
@testable import Callings

final class ParserTests: XCTestCase {

    func testParseMemberCallingsCell() {
        let callings = MemberListParser.parseCallings(
            "Primary Teacher (11 Feb 2024/No), Ward Missionary (1 Mar 2026/Yes)"
        )
        XCTAssertEqual(callings.count, 2)
        XCTAssertEqual(callings[0].name, "Primary Teacher")
        XCTAssertFalse(callings[0].isSetApart)
        XCTAssertEqual(callings[1].name, "Ward Missionary")
        XCTAssertTrue(callings[1].isSetApart)
    }

    func testParseCallingsCellToleratesJoinedGlyphs() {
        // Glyph joining across wrapped lines can drop spaces around the parenthesis.
        let callings = MemberListParser.parseCallings("Teachers Quorum First Counselor(3 May2026/Yes)")
        XCTAssertEqual(callings.count, 1)
        XCTAssertEqual(callings[0].name, "Teachers Quorum First Counselor")
        XCTAssertNotNil(callings[0].sustainedDate)
    }

    func testLCRDateParsing() {
        XCTAssertNotNil(PDFTableExtractor.parseLCRDate("30 Apr 2023"))
        XCTAssertNotNil(PDFTableExtractor.parseLCRDate("7 Dec 2025"))
        XCTAssertNotNil(PDFTableExtractor.parseLCRDate("30Apr2023"))
        XCTAssertNil(PDFTableExtractor.parseLCRDate(""))
        XCTAssertNil(PDFTableExtractor.parseLCRDate("Calling Vacant"))
    }

    func testOrganizationHeaderMatching() {
        XCTAssertEqual(OrganizationKind.match(headerText: "Bishopric"), .bishopric)
        XCTAssertEqual(OrganizationKind.match(headerText: "Elders Quorum"), .eldersQuorum)
        XCTAssertEqual(OrganizationKind.match(headerText: "Aaronic Priesthood Quorums"), .aaronicPriesthoodQuorums)
        XCTAssertNil(OrganizationKind.match(headerText: "Teachers"))
    }

    // MARK: - Integration tests against the real LCR exports.
    // The PDFs contain member data and are not committed; these skip when absent.

    private let importFolder = URL(fileURLWithPath: "/Users/mathewbunker/projects/callings/import")

    func testRealWardCallingsPDF() throws {
        let url = importFolder.appendingPathComponent("Ward Callings-20260712.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sample PDF not available")
        let document = try XCTUnwrap(PDFDocument(url: url))

        let parsed = WardCallingsParser.parse(document: document)
        XCTAssertEqual(parsed.countMismatches, [], "every section should match its Count: N line")
        XCTAssertEqual(parsed.rows.count, 218)
        XCTAssertEqual(parsed.rows.filter { $0.holderName == nil }.count, 61)
        XCTAssertEqual(parsed.wardName, "Valley View Ward (91375)")

        let organizations = Set(parsed.rows.map(\.organization))
        XCTAssertEqual(organizations.count, OrganizationKind.allCases.count, "all 11 groups present")

        // Repeated ward/stake page headers must not leak in as subgroups.
        let subgroups = Set(parsed.rows.compactMap(\.subgroup))
        XCTAssertFalse(subgroups.contains { $0.contains("Stake (") || $0.contains("Ward (") })
    }

    func testRealMemberListPDF() throws {
        let url = importFolder.appendingPathComponent("Member List for Callings.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sample PDF not available")
        let document = try XCTUnwrap(PDFDocument(url: url))

        let list = MemberListParser.parse(document: document)
        XCTAssertEqual(list.members.count, list.expectedCount, "parsed member count matches the report's Count line")
        XCTAssertEqual(list.members.filter { $0.gender == nil }.count, 0)

        // Row wrapped around the age line
        let raelyn = list.members.first { $0.name == "Alley, Raelyn Kay" }
        XCTAssertNotNil(raelyn)
        // Row split across a page break (name on the following page)
        let weston = list.members.first { $0.name == "Porter, Weston Glenwood" }
        XCTAssertEqual(weston?.age, 13)
    }
}
