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

    /// Best-effort parse of a callings table scraped from an LCR page laid
    /// out like the PDF report (org header rows spanning one cell; data rows
    /// of calling | member | sustained). Throws when the structure doesn't
    /// match — the page snapshot then tells us what to adapt to.
    static func parseCallings(from table: ScrapedTable) throws -> ParsedWardCallings {
        if let error = table.error {
            throw ExtractionError.noTable(pageTitle: table.title ?? error)
        }
        var result = ParsedWardCallings()
        var currentOrg: OrganizationKind?
        var currentSubgroup: String?

        for row in table.rows {
            let cells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }

            if cells.count == 1 {
                // Exact name = organization header; anything else under an
                // org is a subgroup ("Elders Quorum Presidency" must not
                // fuzzy-match the Elders Quorum org).
                if let org = OrganizationKind(rawValue: cells[0]) {
                    currentOrg = org
                    currentSubgroup = nil
                } else if currentOrg != nil, !cells[0].lowercased().contains("calling") {
                    currentSubgroup = cells[0]
                }
                continue
            }
            guard let org = currentOrg, cells.count >= 2 else { continue }
            if cells[0].localizedCaseInsensitiveContains("calling") && cells[1].localizedCaseInsensitiveContains("name") {
                continue  // column header row
            }
            var callingName = cells[0]
            var isCustom = false
            if callingName.hasPrefix("*") {
                isCustom = true
                callingName = callingName.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            let holder = cells[1].replacingOccurrences(of: " ", with: "") == "CallingVacant" ? nil : cells[1]
            result.rows.append(ParsedCallingRow(
                organization: org,
                subgroup: currentSubgroup,
                callingName: callingName,
                isCustom: isCustom,
                holderName: holder,
                sustainedDate: cells.count > 2 ? PDFTableExtractor.parseLCRDate(cells[2]) : nil,
                isSetApart: cells.contains { $0 == "✓" || $0.lowercased() == "yes" }
            ))
        }
        guard !result.rows.isEmpty else {
            throw ExtractionError.noTable(pageTitle: table.title)
        }
        return result
    }

    /// JavaScript for the diagnostic snapshot: page title, URL, table shapes,
    /// and the page's repeated element structures (class names + one sample
    /// text, truncated) so the extractor can be adapted from a single
    /// copy-paste without a PII-heavy full dump.
    static let snapshotScript = """
    (() => {
        const tables = Array.from(document.querySelectorAll('table')).map(t => ({
            rows: t.querySelectorAll('tr').length,
            firstRow: Array.from((t.querySelector('tr') || {querySelectorAll: () => []}).querySelectorAll('th,td')).map(c => (c.innerText || '').trim())
        }));
        // Find repeated structures: class names that occur many times.
        const counts = {};
        document.querySelectorAll('[class]').forEach(el => {
            const key = el.tagName.toLowerCase() + '.' + el.className.toString().split(/\\s+/).slice(0, 2).join('.');
            counts[key] = (counts[key] || 0) + 1;
        });
        const repeated = Object.entries(counts)
            .filter(([, n]) => n >= 8)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 20)
            .map(([key, n]) => {
                const el = document.querySelector(key.replace(/^([a-z0-9]+)\\./, '$1.').split('.').slice(0, 2).join('.'));
                let sample = '';
                try { sample = (document.getElementsByClassName(key.split('.')[1])[0]?.innerText || '').slice(0, 90); } catch (e) {}
                return {selector: key, count: n, sample: sample};
            });
        return JSON.stringify({
            title: document.title,
            url: location.href,
            tableCount: tables.length,
            tables: tables.slice(0, 5),
            repeatedStructures: repeated
        }, null, 2);
    })()
    """
}
