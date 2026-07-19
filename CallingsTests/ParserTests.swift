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
        let url = importFolder.appendingPathComponent("Ward Callings-20260719.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sample PDF not available")
        let document = try XCTUnwrap(PDFDocument(url: url))
        // The 2026-07-19 export has corrupt font dictionaries and no text
        // layer; skip until the user provides a readable re-export, then
        // restore count assertions.
        try XCTSkipIf(
            (document.page(at: 0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "Ward Callings export has no extractable text — needs re-export from LCR"
        )

        let parsed = WardCallingsParser.parse(document: document)
        XCTAssertEqual(parsed.countMismatches, [], "every section should match its Count: N line")
        XCTAssertFalse(parsed.rows.isEmpty)

        // Repeated ward/stake page headers must not leak in as subgroups.
        let subgroups = Set(parsed.rows.compactMap(\.subgroup))
        XCTAssertFalse(subgroups.contains { $0.contains("Stake (") || $0.contains("Ward (") })
    }

    func testRealMemberListPDF() throws {
        let url = importFolder.appendingPathComponent("Member List for Callings-20260719.pdf")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "sample PDF not available")
        let document = try XCTUnwrap(PDFDocument(url: url))

        let list = MemberListParser.parse(document: document)
        XCTAssertEqual(list.members.count, list.expectedCount, "parsed member count matches the report's Count line")
        XCTAssertEqual(list.members.filter { $0.gender == nil }.count, 0)

        // Row wrapped around the age line
        let raelyn = list.members.first { $0.name == "Alley, Raelyn Kay" }
        XCTAssertNotNil(raelyn)

        // Ligature repair across the landscape font: ﬀ→'g', ﬂ→'j', Th→'P'.
        let names = Set(list.members.map(\.name))
        XCTAssertTrue(names.contains("Dickman, Jeff"), "ﬀ ligature repaired")
        XCTAssertTrue(names.contains("Shiflett, Becky"), "ﬂ ligature repaired")
        XCTAssertTrue(names.contains("Apsey, Thomas"), "Th ligature repaired")
        XCTAssertFalse(names.contains {
            $0.contains("Jeg") || $0.contains("jett,") || $0.contains("Pomas") || $0.contains("Woodrug")
        })

        // New columns populated.
        XCTAssertGreaterThan(list.members.filter { $0.priesthoodOffice != nil }.count, 100)
        XCTAssertGreaterThan(list.members.filter { $0.moveInDate != nil }.count, 100)
        XCTAssertGreaterThan(list.members.filter { $0.templeRecommendStatus != nil }.count, 100)
        let mike = list.members.first { $0.name == "Alley, Mike" }
        XCTAssertEqual(mike?.priesthoodOffice, "Priest")
        XCTAssertNotNil(mike?.moveInDate)
    }
}
