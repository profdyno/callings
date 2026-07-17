import Foundation
import PDFKit

/// One member row from the "Member List for Callings" LCR report.
struct ParsedMember: Equatable {
    var name: String
    var age: Int?
    var gender: Gender?
    /// Callings with sustained date and set-apart flag from the
    /// "Callings with Date Sustained and Set Apart" column.
    var callings: [ParsedMemberCalling] = []
    var classAssignments: [String] = []
    var email: String?
    var phone: String?
    var priesthood: PriesthoodTrack = .none
}

struct ParsedMemberCalling: Equatable {
    var name: String
    var sustainedDate: Date?
    var isSetApart: Bool
}

struct ParsedMemberList {
    var members: [ParsedMember] = []
    /// The report's own "Count: N" total, for validation.
    var expectedCount: Int?
}

/// Parses the "Member List for Callings" report PDF.
///
/// Layout (verified against a real export): a 9-column table whose header block
/// ("Preferred Name | Age | Callings | Callings with Date… | Class Assignment |
/// Gender | Individual E-mail | Individual Phone | Priesthood") appears on the
/// first page only and defines column x-bands for the whole document. Cells wrap
/// up to 4 lines and the name can wrap around the age line, so rows are segmented
/// by vertical gap: intra-row line spacing is ~8–10pt, between-row padding ~18pt.
/// Rows can continue across page breaks; a leading block with no name+age anchor
/// belongs to the previous member. The report ends with a "Count: N" total.
enum MemberListParser {

    private struct Bands {
        var name: Range<CGFloat>
        var age: Range<CGFloat>
        var callings: Range<CGFloat>
        var callingsWithDate: Range<CGFloat>
        var classAssignment: Range<CGFloat>
        var gender: Range<CGFloat>
        var email: Range<CGFloat>
        var phone: Range<CGFloat>
        var priesthood: Range<CGFloat>
    }

    static func parse(document: PDFDocument) -> ParsedMemberList {
        var result = ParsedMemberList()
        var bands: Bands?
        // Trailing block from the previous page that didn't parse on its own —
        // a row whose remaining cells (often the name) continue on the next page.
        var pendingTail: [PDFTableExtractor.TextLine]?

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let lines = PDFTableExtractor.lines(from: page)

            var headerBottomY = CGFloat.greatestFiniteMagnitude
            if let (found, bottom) = findBands(in: lines) {
                bands = found
                headerBottomY = bottom
            }
            guard let bands else { continue }

            var dataLines: [PDFTableExtractor.TextLine] = []
            for line in lines {
                guard line.y < headerBottomY else { continue }
                let text = line.text()
                if isChrome(text) { continue }
                if let match = text.firstMatch(of: #/^Count:\s*(\d+)$/#) {
                    result.expectedCount = Int(match.1)
                    continue
                }
                dataLines.append(line)
            }

            // Cluster into row blocks by vertical gap.
            var blocks: [[PDFTableExtractor.TextLine]] = []
            for line in dataLines {
                if var block = blocks.last, let previous = block.last, previous.y - line.y < 14 {
                    block.append(line)
                    blocks[blocks.count - 1] = block
                } else {
                    blocks.append([line])
                }
            }

            for (blockIndex, block) in blocks.enumerated() {
                if blockIndex == 0, let tail = pendingTail {
                    pendingTail = nil
                    // A row split by the page break: stitch the previous page's
                    // unparseable tail onto this page's leading block.
                    if let member = parseBlock(tail + block, bands: bands) {
                        result.members.append(member)
                        continue
                    }
                }
                if let member = parseBlock(block, bands: bands) {
                    result.members.append(member)
                } else if blockIndex == blocks.count - 1 {
                    pendingTail = block
                } else if blockIndex == 0, !result.members.isEmpty {
                    // A page-leading block with no name+age anchor continues the
                    // previous member's wrapped cells across the page break.
                    merge(block, into: &result.members[result.members.count - 1], bands: bands)
                }
            }
        }
        return result
    }

    /// Locates the column-header block (first page) and returns bands plus the
    /// y below which data rows start.
    private static func findBands(in lines: [PDFTableExtractor.TextLine]) -> (Bands, CGFloat)? {
        // The main header line contains "Age" and "Gender" runs.
        guard let headerLine = lines.first(where: { line in
            let texts = line.runs.map(\.text)
            return texts.contains("Age") && texts.contains(where: { $0.hasPrefix("Gender") })
        }) else { return nil }

        func x(startingWith prefix: String) -> CGFloat? {
            headerLine.runs.first { $0.text.hasPrefix(prefix) }?.minX
        }
        guard let ageX = x(startingWith: "Age"),
              let callingsX = x(startingWith: "Callings"),
              let genderX = x(startingWith: "Gender"),
              let priesthoodX = x(startingWith: "Priesthood") else { return nil }

        // The taller header words wrap onto separate lines around the main one;
        // only lines made of known header words count as part of the block.
        let headerWords: Set<String> = [
            "Preferred", "Name", "Age", "Callings", "with Date", "Sustained",
            "and Set", "Apart", "Class", "Assignment", "Gender",
            "Individual", "Individual E-mail", "Individual Phone", "Phone", "Priesthood",
        ]
        let headerBlock = lines.filter { line in
            abs(line.y - headerLine.y) < 50 &&
            line.runs.allSatisfy { headerWords.contains($0.text.trimmingCharacters(in: .whitespaces)) }
        }
        let withDateX = headerBlock.compactMap { line in
            line.runs.first { $0.text.hasPrefix("with Date") || $0.text.hasPrefix("Sustained") }?.minX
        }.first ?? (callingsX + 60)
        let classX = headerBlock.compactMap { line in
            line.runs.first { $0.text == "Class" || $0.text.hasPrefix("Assignment") }?.minX
        }.first ?? (genderX - 67)
        let emailX = headerLine.runs.first { $0.text.contains("E-mail") }?.minX ?? (genderX + 49)
        let phoneX = headerBlock.compactMap { line in
            line.runs.first { $0.text.hasPrefix("Individual Phone") || $0.text == "Phone" }?.minX
        }.first ?? (priesthoodX - 60)

        let pad: CGFloat = 4
        let bands = Bands(
            name: 0..<(ageX - pad),
            age: (ageX - pad)..<(callingsX - pad),
            callings: (callingsX - pad)..<(withDateX - pad),
            callingsWithDate: (withDateX - pad)..<(classX - pad),
            classAssignment: (classX - pad)..<(genderX - pad),
            gender: (genderX - pad)..<(emailX - pad),
            email: (emailX - pad)..<(phoneX - pad),
            phone: (phoneX - pad)..<(priesthoodX - pad),
            priesthood: (priesthoodX - pad)..<CGFloat.greatestFiniteMagnitude
        )
        let headerBottom = headerBlock.map(\.y).min() ?? headerLine.y
        return (bands, headerBottom - 4)
    }

    private static func isChrome(_ text: String) -> Bool {
        if text.isEmpty { return true }
        if text.firstMatch(of: #/^Page\s*\d+\s*of\s*\d+/#) != nil { return true }
        if text.contains("churchofjesuschrist.org") { return true }
        if text.hasPrefix("Create a Report") { return true }
        if text.hasPrefix("Member List for Callings") { return true }
        if text.hasPrefix("Used to import into") { return true }
        if text == "Search" || text == "Edit Report" || text.hasSuffix("Edit Report") { return true }
        return false
    }

    private static func parseBlock(_ block: [PDFTableExtractor.TextLine], bands: Bands) -> ParsedMember? {
        let name = joined(block, bands.name)
        let ageText = joined(block, bands.age)
        let genderText = joined(block, bands.gender)
        // A valid row has a name plus an integer age or a gender letter.
        guard !name.isEmpty, Int(ageText) != nil || Gender(rawValue: genderText) != nil else { return nil }

        var member = ParsedMember(name: name)
        member.age = Int(ageText)
        member.gender = Gender(rawValue: genderText)
        member.callings = parseCallings(joined(block, bands.callingsWithDate))
        member.classAssignments = parseClasses(joined(block, bands.classAssignment))
        let email = joined(block, bands.email)
        member.email = email.isEmpty ? nil : email
        let phone = joined(block, bands.phone)
        member.phone = phone.isEmpty ? nil : phone
        member.priesthood = PriesthoodTrack(rawValue: joined(block, bands.priesthood)) ?? .none
        return member
    }

    /// Appends a continuation block's cell contents to a member whose row
    /// broke across a page boundary.
    private static func merge(_ block: [PDFTableExtractor.TextLine], into member: inout ParsedMember, bands: Bands) {
        member.callings.append(contentsOf: parseCallings(joined(block, bands.callingsWithDate)))
        member.classAssignments.append(contentsOf: parseClasses(joined(block, bands.classAssignment)))
        if member.email == nil {
            let email = joined(block, bands.email)
            if !email.isEmpty { member.email = email }
        }
        if member.phone == nil {
            let phone = joined(block, bands.phone)
            if !phone.isEmpty { member.phone = phone }
        }
        if member.priesthood == .none {
            member.priesthood = PriesthoodTrack(rawValue: joined(block, bands.priesthood)) ?? .none
        }
    }

    private static func joined(_ block: [PDFTableExtractor.TextLine], _ band: Range<CGFloat>) -> String {
        block.map { $0.text(in: band) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func parseClasses(_ text: String) -> [String] {
        // The report sometimes repeats a class within one cell — dedupe, keeping order.
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Parses "Primary Teacher (11 Feb 2024/No), Ward Missionary (1 Mar 2026/Yes)".
    static func parseCallings(_ text: String) -> [ParsedMemberCalling] {
        guard !text.isEmpty else { return [] }
        var callings: [ParsedMemberCalling] = []
        let pattern = #/([^(,][^(]*?)\(\s*(\d{1,2}\s*[A-Za-z]{3}\s*\d{4})\s*/\s*(Yes|No)\s*\)/#
        for match in text.matches(of: pattern) {
            let name = String(match.1)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            callings.append(ParsedMemberCalling(
                name: name,
                sustainedDate: PDFTableExtractor.parseLCRDate(String(match.2)),
                isSetApart: match.3 == "Yes"
            ))
        }
        return callings
    }
}
