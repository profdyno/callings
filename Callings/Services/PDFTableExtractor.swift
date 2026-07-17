import Foundation
import PDFKit

/// Geometry-based text extraction for LCR table PDFs.
///
/// `PDFPage.string` interleaves wrapped table cells, so instead we take the
/// bounds of every character (via one-character `PDFSelection`s, which are
/// reliable where `characterBounds(at:)` is not for these PDFs) and rebuild
/// lines and cells from coordinates.
enum PDFTableExtractor {

    struct Glyph {
        let text: String
        let frame: CGRect
    }

    struct TextRun {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var y: CGFloat
        var height: CGFloat
    }

    struct TextLine {
        var y: CGFloat
        var glyphs: [Glyph]   // sorted by minX
        var runs: [TextRun]   // gap-split, sorted by minX

        /// Joined text of glyphs whose midX falls in `band`, with spaces
        /// inserted at intra-cell word gaps. `nil` band = whole line.
        func text(in band: Range<CGFloat>? = nil) -> String {
            var result = ""
            var lastMaxX: CGFloat?
            for glyph in glyphs {
                if let band, !band.contains(glyph.frame.midX) { continue }
                if let last = lastMaxX, glyph.frame.minX - last > 1.5 {
                    result += " "
                }
                result += glyph.text
                lastMaxX = glyph.frame.maxX
            }
            return result.trimmingCharacters(in: .whitespaces)
        }

        var maxRunHeight: CGFloat { runs.map(\.height).max() ?? 0 }
        var minX: CGFloat { glyphs.first?.frame.minX ?? 0 }
    }

    /// Extracts positioned lines from a page, top to bottom.
    static func lines(from page: PDFPage) -> [TextLine] {
        let ns = (page.string ?? "") as NSString
        var glyphs: [Glyph] = []
        for i in 0..<ns.length {
            let s = ns.substring(with: NSRange(location: i, length: 1))
            if s == "\n" || s == "\r" || s == " " { continue }
            guard let sel = page.selection(for: NSRange(location: i, length: 1)) else { continue }
            let b = sel.bounds(for: page)
            guard b.width > 0, b.height > 0 else { continue }
            glyphs.append(Glyph(text: s, frame: b))
        }

        // Group glyphs into lines by y midpoint.
        var lines: [TextLine] = []
        for glyph in glyphs {
            if let index = lines.firstIndex(where: { abs($0.y - glyph.frame.midY) < 4 }) {
                lines[index].glyphs.append(glyph)
            } else {
                lines.append(TextLine(y: glyph.frame.midY, glyphs: [glyph], runs: []))
            }
        }
        lines.sort { $0.y > $1.y }

        for index in lines.indices {
            lines[index].glyphs.sort { $0.frame.minX < $1.frame.minX }
            lines[index].runs = makeRuns(from: lines[index].glyphs)
        }
        return lines
    }

    /// Splits a line's glyphs into runs at horizontal gaps larger than a word space.
    private static func makeRuns(from glyphs: [Glyph]) -> [TextRun] {
        var runs: [TextRun] = []
        var current: TextRun?
        for glyph in glyphs {
            let b = glyph.frame
            if var run = current, b.minX - run.maxX < 8 {
                if b.minX - run.maxX > 1.5 { run.text += " " }
                run.text += glyph.text
                run.maxX = max(run.maxX, b.maxX)
                run.height = max(run.height, b.height)
                current = run
            } else {
                if let run = current { runs.append(run) }
                current = TextRun(text: glyph.text, minX: b.minX, maxX: b.maxX, y: b.midY, height: b.height)
            }
        }
        if let run = current { runs.append(run) }
        return runs
    }

    static let lcrDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Parses "30 Apr 2023" (tolerating missing spaces from glyph joining).
    static func parseLCRDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let date = lcrDateFormatter.date(from: trimmed) { return date }
        // Fallback: re-space "30Apr2023" style artifacts
        if let match = trimmed.firstMatch(of: #/(\d{1,2})\s*([A-Za-z]{3})\s*(\d{4})/#) {
            return lcrDateFormatter.date(from: "\(match.1) \(match.2) \(match.3)")
        }
        return nil
    }
}
