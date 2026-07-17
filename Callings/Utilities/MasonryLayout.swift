import SwiftUI

/// Packs variable-height cards into columns, placing each card in the
/// currently shortest column. Organization cards vary from 3 to 30+ rows,
/// so a uniform grid would waste most of a 16:9 display.
struct MasonryLayout: Layout {
    var columnWidth: CGFloat = 340
    var spacing: CGFloat = 12

    private func columnCount(for width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (columnWidth + spacing)))
    }

    private func placements(
        subviews: Subviews,
        width: CGFloat
    ) -> (offsets: [CGPoint], size: CGSize, itemWidth: CGFloat) {
        let columns = columnCount(for: width)
        let itemWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = [CGFloat](repeating: 0, count: columns)
        var offsets: [CGPoint] = []

        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height
            let column = columnHeights.firstIndex(of: columnHeights.min() ?? 0) ?? 0
            let x = CGFloat(column) * (itemWidth + spacing)
            offsets.append(CGPoint(x: x, y: columnHeights[column]))
            columnHeights[column] += height + spacing
        }
        let totalHeight = max((columnHeights.max() ?? spacing) - spacing, 0)
        return (offsets, CGSize(width: width, height: totalHeight), itemWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? columnWidth
        return placements(subviews: subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (offsets, _, itemWidth) = placements(subviews: subviews, width: bounds.width)
        for (subview, offset) in zip(subviews, offsets) {
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: ProposedViewSize(width: itemWidth, height: nil)
            )
        }
    }
}
