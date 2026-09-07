import SwiftUI

/// One "Label  value" line inside a compact (iPhone) list row.
///
/// SwiftUI `Table` renders only its first column in compact width, so on the
/// phone each table view swaps to a `List` whose rows stack the same cells
/// vertically. This keeps those rows reading alike across the four views:
/// a fixed-width caption label on the left, the real cell on the right.
struct LabeledLine<Content: View>: View {
    private let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension LabeledLine where Content == Text {
    /// Plain text value, with a placeholder when there is nothing to show.
    init(_ label: String, _ value: String?, placeholder: String = "—") {
        self.init(label) { Text(value ?? placeholder) }
    }
}

/// The bold first line of a compact row: what the row is about.
struct CompactRowHeadline: View {
    let title: String
    var subtitle: String?
    var titleColor: Color = .primary
    var isStruckThrough = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .strikethrough(isStruckThrough)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Standard padding for a compact list row built from `CompactRowHeadline`
    /// and `LabeledLine`s.
    func compactRowLayout() -> some View {
        self
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
