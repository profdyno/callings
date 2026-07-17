import Foundation
import PDFKit

/// One calling row from the Ward Callings LCR export.
struct ParsedCallingRow: Equatable {
    var organization: OrganizationKind
    var subgroup: String?
    var callingName: String
    var isCustom: Bool
    /// nil = "Calling Vacant"
    var holderName: String?
    var sustainedDate: Date?
    var isSetApart: Bool
}

struct ParsedWardCallings {
    var wardName: String?
    var rows: [ParsedCallingRow] = []
    /// Section (org|subgroup) row counts that disagreed with the PDF's "Count: N" line.
    var countMismatches: [String] = []
}

/// Parses the "Ward Callings" PDF exported from LCR (Organizations and Callings).
///
/// Layout (verified against a real export):
/// - Organization headers are single left-margin runs with a larger font (height > 12.5)
///   whose text matches one of the fixed organization names.
/// - Subgroup headers are single-run lines immediately followed by a "Calling Name
///   Sustained Set Apart" column-header line; they may carry a trailing " Room: …"
///   annotation.
/// - Column headers repeat per table and their run x-origins define the column bands
///   (positions shift between sections, e.g. "Additional … Callings" tables).
/// - Data rows: calling name in the first band ("* " prefix marks custom callings),
///   holder or "Calling Vacant" in the Name band, "d MMM yyyy" in Sustained, ✓ in Set Apart.
/// - "Count: N" lines close a section; "* custom calling" is a legend line to skip.
enum WardCallingsParser {

    static func parse(document: PDFDocument) -> ParsedWardCallings {
        var result = ParsedWardCallings()

        // Flatten pages so section headers can look ahead across page breaks.
        var lines: [PDFTableExtractor.TextLine] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for line in PDFTableExtractor.lines(from: page) {
                let text = line.text()
                if text.isEmpty || line.y < 25 { continue }
                if text.contains("For Church Use Only") { continue }
                if text == "* custom calling" { continue }
                if text.hasPrefix("Organizations and Callings") {
                    if result.wardName == nil, let run = line.runs.last, run.minX > 300 {
                        result.wardName = run.text.trimmingCharacters(in: .whitespaces)
                    }
                    continue
                }
                if pageIndex == 0, text.contains("Stake (") { continue }
                lines.append(line)
            }
        }

        var currentOrg: OrganizationKind?
        var currentSubgroup: String?
        // Column band boundaries from the most recent header line.
        var nameX: CGFloat = 245
        var sustainedX: CGFloat = 370
        var setApartX: CGFloat = 475
        var sectionRowCount = 0

        for (index, line) in lines.enumerated() {
            let fullText = line.text()

            // Column header — locks in band positions for the rows below.
            if isColumnHeader(line) {
                if let name = line.runs.first(where: { $0.text.hasPrefix("Name") }) {
                    nameX = name.minX
                }
                if let sustained = line.runs.first(where: { $0.text.hasPrefix("Sustained") }) {
                    sustainedX = sustained.minX
                }
                if let setApart = line.runs.first(where: { $0.text.hasPrefix("Set Apart") }) {
                    setApartX = setApart.minX
                }
                continue
            }

            // Section count closes the current section.
            if let match = fullText.firstMatch(of: #/^Count:\s*(\d+)$/#) {
                let expected = Int(match.1) ?? 0
                if sectionRowCount != expected {
                    let section = "\(currentOrg?.rawValue ?? "?")|\(currentSubgroup ?? "")"
                    result.countMismatches.append("\(section): PDF says \(expected), parsed \(sectionRowCount)")
                }
                sectionRowCount = 0
                continue
            }

            // Organization header (large font, known name).
            if line.runs.count == 1, line.maxRunHeight > 12.5,
               let org = OrganizationKind.match(headerText: fullText) {
                currentOrg = org
                currentSubgroup = nil
                continue
            }

            // Subgroup header: the next line is a column header.
            if index + 1 < lines.count, isColumnHeader(lines[index + 1]) {
                currentSubgroup = stripRoomSuffix(fullText)
                continue
            }

            // Data row
            guard let org = currentOrg else { continue }
            var callingName = line.text(in: 0..<(nameX - 4))
            guard !callingName.isEmpty else { continue }
            var isCustom = false
            if callingName.hasPrefix("*") {
                isCustom = true
                callingName = callingName.dropFirst().trimmingCharacters(in: .whitespaces)
            }

            let nameText = line.text(in: (nameX - 4)..<(sustainedX - 4))
            let sustainedText = line.text(in: (sustainedX - 4)..<(setApartX - 4))
            let setApartText = line.text(in: (setApartX - 4)..<CGFloat.greatestFiniteMagnitude)

            let isVacant = nameText.replacingOccurrences(of: " ", with: "") == "CallingVacant"
            result.rows.append(ParsedCallingRow(
                organization: org,
                subgroup: currentSubgroup,
                callingName: callingName,
                isCustom: isCustom,
                holderName: isVacant || nameText.isEmpty ? nil : nameText,
                sustainedDate: PDFTableExtractor.parseLCRDate(sustainedText),
                isSetApart: setApartText.contains("✓")
            ))
            sectionRowCount += 1
        }
        return result
    }

    private static func isColumnHeader(_ line: PDFTableExtractor.TextLine) -> Bool {
        let compact = line.text().replacingOccurrences(of: " ", with: "")
        return compact == "CallingNameSustainedSetApart"
    }

    private static func stripRoomSuffix(_ text: String) -> String {
        guard let range = text.range(of: "Room:") else { return text }
        return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}
