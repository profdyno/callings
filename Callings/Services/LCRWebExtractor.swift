import Foundation

/// Maps a table scraped from the LCR "Member List for Callings" report page
/// (headers + row cells, already clean text — no PDF geometry or ligature
/// problems) into ParsedMembers. Pure and unit-testable.
enum LCRWebExtractor {

    struct ScrapedTable: Codable {
        var rows: [[String]] = []
        var error: String?
        var title: String?
    }

    enum ExtractionError: LocalizedError {
        case noTable(pageTitle: String?)
        case missingColumns([String])

        var errorDescription: String? {
            switch self {
            case .noTable(let title):
                return "No report table found on the page\(title.map { " (\"\($0)\")" } ?? ""). Make sure the Member List for Callings report is fully loaded, then try again."
            case .missingColumns(let names):
                return "The report table is missing expected columns: \(names.joined(separator: ", ")). Use the Copy Page Snapshot button and share it so the importer can be updated."
            }
        }
    }

    /// Decodes the JSON produced by the injected JavaScript.
    static func decodeScrape(_ json: String) throws -> ScrapedTable {
        try JSONDecoder().decode(ScrapedTable.self, from: Data(json.utf8))
    }

    /// Parses the scraped table into members. The header row is located by
    /// its known column names; header matching is case-insensitive and
    /// tolerant of extra columns and column reordering.
    static func parseMembers(from table: ScrapedTable) throws -> [ParsedMember] {
        if let error = table.error {
            throw ExtractionError.noTable(pageTitle: table.title ?? error)
        }
        guard let headerIndex = table.rows.firstIndex(where: { row in
            row.contains { $0.localizedCaseInsensitiveContains("Preferred") }
                && row.contains { $0.localizedCaseInsensitiveContains("Gender") }
        }) else {
            throw ExtractionError.noTable(pageTitle: table.title)
        }

        let headers = table.rows[headerIndex].map { $0.lowercased() }
        func column(_ keywords: String...) -> Int? {
            headers.firstIndex { header in
                keywords.allSatisfy { header.contains($0.lowercased()) }
            }
        }
        guard let nameColumn = column("preferred"),
              let genderColumn = column("gender") else {
            throw ExtractionError.missingColumns(["Preferred Name", "Gender"])
        }
        let ageColumn = column("age")
        let callingsColumn = column("callings")
        let classColumn = column("class")
        let emailColumn = column("e-mail") ?? column("email")
        let phoneColumn = column("phone")
        let priesthoodColumn = headers.firstIndex { $0 == "priesthood" } ?? column("priesthood")
        let officeColumn = column("priesthood", "office")
        let moveInColumn = column("move")
        let recommendColumn = column("recommend")

        var members: [ParsedMember] = []
        for row in table.rows.dropFirst(headerIndex + 1) {
            func cell(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            guard let name = cell(nameColumn), name.contains(",") || name.contains(" ") else { continue }
            guard cell(ageColumn).flatMap({ Int($0) }) != nil || cell(genderColumn) != nil else { continue }

            var member = ParsedMember(name: name)
            member.age = cell(ageColumn).flatMap(Int.init)
            member.gender = cell(genderColumn).flatMap(Gender.init(rawValue:))
            member.callings = MemberListParser.parseCallings(cell(callingsColumn) ?? "")
            member.classAssignments = (cell(classColumn) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            member.email = cell(emailColumn)
            member.phone = cell(phoneColumn)
            member.priesthood = cell(priesthoodColumn).flatMap(PriesthoodTrack.init(rawValue:)) ?? .none
            member.priesthoodOffice = officeColumn != priesthoodColumn ? cell(officeColumn) : nil
            member.moveInDate = cell(moveInColumn).flatMap(PDFTableExtractor.parseLCRDate)
            member.templeRecommendStatus = cell(recommendColumn)
            members.append(member)
        }
        return members
    }

    /// JavaScript that scrapes the largest table on the page into
    /// {rows: [[String]]} JSON (or {error, title} when there is none).
    static let scrapeScript = """
    (() => {
        const tables = Array.from(document.querySelectorAll('table'));
        if (tables.length === 0) {
            return JSON.stringify({rows: [], error: 'no table', title: document.title});
        }
        const best = tables
            .map(t => ({t, count: t.querySelectorAll('tr').length}))
            .sort((a, b) => b.count - a.count)[0].t;
        const rows = Array.from(best.querySelectorAll('tr')).map(tr =>
            Array.from(tr.querySelectorAll('th,td')).map(c => (c.innerText || '').trim())
        );
        return JSON.stringify({rows: rows});
    })()
    """

    /// JavaScript for the diagnostic snapshot: page title, URL, and a
    /// structural outline so the extractor can be adapted without PII-heavy
    /// full-page dumps.
    static let snapshotScript = """
    (() => {
        const tables = Array.from(document.querySelectorAll('table')).map(t => ({
            rows: t.querySelectorAll('tr').length,
            firstRow: Array.from((t.querySelector('tr') || {querySelectorAll: () => []}).querySelectorAll('th,td')).map(c => (c.innerText || '').trim())
        }));
        return JSON.stringify({
            title: document.title,
            url: location.href,
            tableCount: tables.length,
            tables: tables.slice(0, 5)
        }, null, 2);
    })()
    """
}
