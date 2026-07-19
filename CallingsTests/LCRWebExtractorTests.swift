import XCTest
@testable import Callings

final class LCRWebExtractorTests: XCTestCase {

    private func table(_ rows: [[String]]) -> LCRWebExtractor.ScrapedTable {
        LCRWebExtractor.ScrapedTable(rows: rows)
    }

    func testParsesMembersFromScrapedTable() throws {
        let scraped = table([
            ["Member List for Callings"],  // page cruft above the header
            ["Preferred Name", "Age", "Callings with Date Sustained and Set Apart", "Class Assignment",
             "Gender", "Individual E-mail", "Individual Phone", "Priesthood", "Priesthood office",
             "Move In Date", "Temple Recommend Status"],
            ["Alley, Mike", "45", "Primary Teacher (11 Feb 2024/No)", "Elders Quorum, Adult Sunday School",
             "M", "mike@example.com", "(480) 555-0001", "Aaronic", "Priest", "15 Sep 2016", "Active"],
            ["Alley, Raelyn Kay", "45", "", "Relief Society",
             "F", "", "(480) 555-0002", "", "", "15 Sep 2016", "Expiring next month"],
            ["", "", "", "", "", "", "", "", "", "", ""],  // trailing junk row
        ])

        let members = try LCRWebExtractor.parseMembers(from: scraped)
        XCTAssertEqual(members.count, 2)

        let mike = members[0]
        XCTAssertEqual(mike.name, "Alley, Mike")
        XCTAssertEqual(mike.age, 45)
        XCTAssertEqual(mike.gender, .male)
        XCTAssertEqual(mike.callings.first?.name, "Primary Teacher")
        XCTAssertEqual(mike.classAssignments, ["Elders Quorum", "Adult Sunday School"])
        XCTAssertEqual(mike.email, "mike@example.com")
        XCTAssertEqual(mike.priesthood, .aaronic)
        XCTAssertEqual(mike.priesthoodOffice, "Priest")
        XCTAssertNotNil(mike.moveInDate)
        XCTAssertEqual(mike.templeRecommendStatus, "Active")

        XCTAssertEqual(members[1].gender, .female)
        XCTAssertEqual(members[1].priesthood, .none)
        XCTAssertNil(members[1].priesthoodOffice)
    }

    func testColumnReorderingTolerated() throws {
        let scraped = table([
            ["Gender", "Preferred Name", "Age"],
            ["F", "Smith, Jane", "30"],
        ])
        let members = try LCRWebExtractor.parseMembers(from: scraped)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members[0].name, "Smith, Jane")
        XCTAssertEqual(members[0].gender, .female)
        XCTAssertEqual(members[0].age, 30)
    }

    func testNoTableThrows() {
        var scraped = table([])
        scraped.error = "no table"
        scraped.title = "Sign In"
        XCTAssertThrowsError(try LCRWebExtractor.parseMembers(from: scraped))
    }

    func testParsesCallingsFromPDFShapedTable() throws {
        let scraped = table([
            ["Elders Quorum"],
            ["Elders Quorum Presidency"],
            ["Calling", "Name", "Sustained", "Set Apart"],
            ["Elders Quorum President", "Valiulis, John Peter", "17 Dec 2023", "✓"],
            ["Elders Quorum Secretary", "Calling Vacant"],
            ["* Organist", "Boss, Linda", "4 Jan 2026"],
        ])
        let parsed = try LCRWebExtractor.parseCallings(from: scraped)
        XCTAssertEqual(parsed.rows.count, 3)
        XCTAssertEqual(parsed.rows[0].organization, .eldersQuorum)
        XCTAssertEqual(parsed.rows[0].subgroup, "Elders Quorum Presidency")
        XCTAssertEqual(parsed.rows[0].holderName, "Valiulis, John Peter")
        XCTAssertTrue(parsed.rows[0].isSetApart)
        XCTAssertNil(parsed.rows[1].holderName, "vacant")
        XCTAssertTrue(parsed.rows[2].isCustom)
    }

    func testCallingsWithNoRecognizableRowsThrows() {
        let scraped = table([["Something unrelated", "entirely"]])
        XCTAssertThrowsError(try LCRWebExtractor.parseCallings(from: scraped))
    }

    func testScrapeDecoding() throws {
        let json = #"{"rows": [["Preferred Name", "Gender"], ["Smith, Jane", "F"]]}"#
        let scraped = try LCRWebExtractor.decodeScrape(json)
        XCTAssertEqual(scraped.rows.count, 2)
    }
}
