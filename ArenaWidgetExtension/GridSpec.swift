import SwiftUI
import WidgetKit

/// Tile layout per widget size. Shared by the view (to draw) and the provider
/// (to download images at the size they'll actually be drawn).
struct GridSpec: Equatable {
    var columns: Int
    var rows: Int

    var count: Int { columns * rows }

    static let gap: CGFloat = 4
    static let headerHeight: CGFloat = 14
    static let headerSpacing: CGFloat = 8
    /// Approximate default content margin of a macOS widget; only used to size downloads.
    static let contentMargin: CGFloat = 14

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self.init(columns: 1, rows: 1)
        case .systemLarge: self.init(columns: 3, rows: 3)
        case .systemExtraLarge: self.init(columns: 6, rows: 3)
        default: self.init(columns: 4, rows: 1)
        }
    }

    /// Side length of each square tile when the header and grid must fit in `size`.
    func side(fitting size: CGSize) -> CGFloat {
        let gridHeight = size.height - Self.headerHeight - Self.headerSpacing
        let byWidth = (size.width - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)
        let byHeight = (gridHeight - Self.gap * CGFloat(rows - 1)) / CGFloat(rows)
        return max(0, min(byWidth, byHeight).rounded(.down))
    }

    func width(side: CGFloat) -> CGFloat {
        side * CGFloat(columns) + Self.gap * CGFloat(columns - 1)
    }

    /// Pixel edge to downsample thumbnails to for a widget of `displaySize` points.
    func pixelSize(for displaySize: CGSize, scale: CGFloat = 2) -> Int {
        guard displaySize.width > 0, displaySize.height > 0 else { return 240 }
        let content = CGSize(
            width: displaySize.width - 2 * Self.contentMargin,
            height: displaySize.height - 2 * Self.contentMargin
        )
        return min(400, max(64, Int((side(fitting: content) * scale).rounded(.up))))
    }
}
