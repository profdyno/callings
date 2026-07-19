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
    // Columns added by the 2026-07 report revision (nil in the old format).
    var priesthoodOffice: String?
    var moveInDate: Date?
    var templeRecommendStatus: String?
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
        // 2026-07 landscape revision only:
        var priesthoodOffice: Range<CGFloat>?
        var moveInDate: Range<CGFloat>?
        var recommendStatus: Range<CGFloat>?
    }

    static func parse(document: PDFDocument) -> ParsedMemberList {
        var result = ParsedMemberList()
        var bands: Bands?
        // Trailing block from the previous page that didn't parse on its own —
        // a row whose remaining cells (often the name) continue on the next page.
        var pendingTail: [PDFTableExtractor.TextLine]?

        // Extract all pages first so ligature medians are document-wide —
        // a single page can have more ligature occurrences of a letter than
        // real ones (poisoning a per-page median).
        let pageLines: [[PDFTableExtractor.TextLine]] = (0..<document.pageCount).compactMap { index in
            document.page(at: index).map(PDFTableExtractor.lines(from:))
        }
        let medians = ligatureMedianWidths(for: pageLines.flatMap { $0.flatMap(\.glyphs) })

        for rawLines in pageLines {
            // Detect bands on the RAW text: ligature repair could alter header
            // words (a bold header 'g' in "Age" can trip the width outlier).
            var headerBottomY = CGFloat.greatestFiniteMagnitude
            if let (found, bottom) = findBands(in: rawLines) {
                bands = found
                headerBottomY = bottom
            }
            guard let bands else { continue }

            let lines = correctingLigatures(rawLines, medians: medians)
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

    /// The report's embedded fonts map ligature glyphs to wrong characters —
    /// observed so far: "ﬀ"→'g' ("Jeff"→"Jeg"), "ﬂ"→'j' ("Shiflett"→
    /// "Shijett"), "ﬃ"→'>' ("office"→"o>ce"), "Th"→'P' ("Thomas"→"Pomas";
    /// the older portrait font used 'O'). Ligature glyphs are much wider than
    /// the letters they masquerade as, so repair by geometry: compare each
    /// suspect glyph's width to the median width of that character in the
    /// page's body font (fonts and sizes changed between report revisions, so
    /// no hardcoded thresholds).
    private static let ligatureRepairs: [String: String] = [
        "g": "ff", "j": "fl", ">": "ffi", "P": "Th", "O": "Th",
    ]

    struct LigatureMedians {
        var bodyHeight: CGFloat = 10
        var widths: [String: CGFloat] = [:]
    }

    /// Median width per suspect character across the whole document's body
    /// font (dominant glyph height ± a wide band — selection heights vary
    /// per row, glyph widths don't).
    static func ligatureMedianWidths(for glyphs: [PDFTableExtractor.Glyph]) -> LigatureMedians {
        guard !glyphs.isEmpty else { return LigatureMedians() }
        let heights = glyphs.map(\.frame.height).sorted()
        var medians = LigatureMedians(bodyHeight: heights[heights.count / 2])
        for character in ligatureRepairs.keys {
            let widths = glyphs
                .filter { $0.text == character && isBodyFont($0, bodyHeight: medians.bodyHeight) }
                .map(\.frame.width)
                .sorted()
            if !widths.isEmpty {
                medians.widths[character] = widths[widths.count / 2]
            }
        }
        return medians
    }

    private static func isBodyFont(_ glyph: PDFTableExtractor.Glyph, bodyHeight: CGFloat) -> Bool {
        glyph.frame.height > bodyHeight * 0.6 && glyph.frame.height < bodyHeight * 1.9
    }

    private static func correctingLigatures(
        _ lines: [PDFTableExtractor.TextLine],
        medians: LigatureMedians
    ) -> [PDFTableExtractor.TextLine] {
        lines.map { line in
            var line = line
            line.glyphs = line.glyphs.map { glyph in
                guard isBodyFont(glyph, bodyHeight: medians.bodyHeight),
                      let replacement = ligatureRepairs[glyph.text],
                      let median = medians.widths[glyph.text] else { return glyph }
                // A ligature is distinctly wider than the real letter (the
                // smallest observed gap is ~24%, so the threshold sits below
                // it but above normal same-font width variation). When nearly
                // every occurrence IS the ligature (e.g. '>' never appears
                // legitimately), the median equals the ligature width — also
                // accept at-median glyphs when the median is implausibly wide.
                let isOutlier = glyph.frame.width > median * 1.15
                let medianItselfSuspicious = glyph.text == ">" && median > medians.bodyHeight * 0.55
                if isOutlier || (medianItselfSuspicious && glyph.frame.width > median * 0.9) {
                    return PDFTableExtractor.Glyph(text: replacement, frame: glyph.frame)
                }
                return glyph
            }
            return line
        }
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
              let genderX = x(startingWith: "Gender"),
              let priesthoodX = x(startingWith: "Priesthood") else { return nil }

        // The taller header words wrap onto separate lines around the main one;
        // only lines made of known header words count as part of the block.
        // ("o>ce" = "office" through the font's ffi-ligature corruption.)
        let headerWords: Set<String> = [
            "Preferred", "Name", "Age", "Callings", "with Date", "Sustained",
            "and Set", "Apart", "Class", "Assignment", "Gender",
            "Individual", "Individual E-mail", "Individual Phone", "Phone", "Priesthood",
            "office", "o>ce", "Move", "In", "Date", "Temple", "Recommend", "Status",
        ]
        let headerBlock = lines.filter { line in
            abs(line.y - headerLine.y) < 60 &&
            line.runs.allSatisfy { headerWords.contains($0.text.trimmingCharacters(in: .whitespaces)) }
        }
        func blockX(_ predicate: @escaping (String) -> Bool) -> CGFloat? {
            headerBlock.compactMap { line in
                line.runs.first { predicate($0.text.trimmingCharacters(in: .whitespaces)) }?.minX
            }.first
        }
        let classX = blockX { $0 == "Class" || $0.hasPrefix("Assignment") } ?? (genderX - 67)
        let emailX = headerLine.runs.first { $0.text.contains("E-mail") }?.minX ?? (genderX + 49)
        let phoneX = blockX { $0.hasPrefix("Individual Phone") || $0 == "Phone" } ?? (priesthoodX - 60)
        let pad: CGFloat = 4
        let headerBottom = (headerBlock.map(\.y).min() ?? headerLine.y) - 4

        // The 2026-07 landscape revision is identified by its "Move In Date"
        // column. (The "Priesthood office" header itself is unreliable: its
        // two wrapped lines extract as one interleaved run like
        // "Po>riecsethood", so the office column x is taken from the run
        // following "Priesthood" on the main line.)
        if let moveInX = blockX({ $0 == "Move" }) {
            let withDateX = x(startingWith: "Sustained")
                ?? blockX { $0 == "Callings" || $0.hasPrefix("with Date") }
                ?? (ageX + 38)
            let officeX = headerLine.runs
                .sorted { $0.minX < $1.minX }
                .first { $0.minX > priesthoodX + 1 && $0.minX < moveInX }?
                .minX ?? (priesthoodX + 69)
            let recommendX = blockX { $0 == "Temple" || $0 == "Recommend" } ?? (moveInX + 45)

            let bands = Bands(
                name: 0..<(ageX - pad),
                age: (ageX - pad)..<(withDateX - pad),
                callings: (withDateX - pad)..<(withDateX - pad),  // merged into callingsWithDate
                callingsWithDate: (withDateX - pad)..<(classX - pad),
                classAssignment: (classX - pad)..<(genderX - pad),
                gender: (genderX - pad)..<(emailX - pad),
                email: (emailX - pad)..<(phoneX - pad),
                phone: (phoneX - pad)..<(priesthoodX - pad),
                priesthood: (priesthoodX - pad)..<(officeX - pad),
                priesthoodOffice: (officeX - pad)..<(moveInX - pad),
                moveInDate: (moveInX - pad)..<(recommendX - pad),
                recommendStatus: (recommendX - pad)..<CGFloat.greatestFiniteMagnitude
            )
            return (bands, headerBottom)
        }

        // Old portrait revision: separate short-callings column, one Priesthood.
        guard let callingsX = x(startingWith: "Callings") else { return nil }
        let withDateX = blockX { $0.hasPrefix("with Date") || $0.hasPrefix("Sustained") } ?? (callingsX + 60)
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
        return (bands, headerBottom)
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
        if let officeBand = bands.priesthoodOffice {
            let office = joined(block, officeBand)
            member.priesthoodOffice = office.isEmpty ? nil : office
        }
        if let moveInBand = bands.moveInDate {
            member.moveInDate = PDFTableExtractor.parseLCRDate(joined(block, moveInBand))
        }
        if let recommendBand = bands.recommendStatus {
            let status = joined(block, recommendBand)
            member.templeRecommendStatus = status.isEmpty ? nil : status
        }
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
