import SwiftUI
import WidgetKit

/// Tile layout per widget size. Shared by the view (to draw) and the provider
/// (to download images at the size they'll actually be drawn).
struct GridSpec: Equatable {
    var columns: Int
    var rows: Int

    var count: Int { columns * rows }

    /// Space between tiles, and between the tiles and the widget's edge.
    static let gap: CGFloat = 4

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self.init(columns: 1, rows: 1)
        case .systemLarge: self.init(columns: 2, rows: 2)
        case .systemExtraLarge: self.init(columns: 3, rows: 2)
        default: self.init(columns: 2, rows: 1)
        }
    }

    /// Size of each tile when the grid fills `size`.
    func cellSize(in size: CGSize) -> CGSize {
        CGSize(
            width: max(0, (size.width - Self.gap * CGFloat(columns - 1)) / CGFloat(columns)),
            height: max(0, (size.height - Self.gap * CGFloat(rows - 1)) / CGFloat(rows))
        )
    }

    /// Pixel size to downsample thumbnails to for a widget of `displaySize` points.
    func pixelSize(for displaySize: CGSize, scale: CGFloat = 2, limit: CGFloat = 800) -> CGSize {
        guard displaySize.width > 0, displaySize.height > 0 else { return CGSize(width: 320, height: 320) }
        let cell = cellSize(in: CGSize(
            width: displaySize.width - 2 * Self.gap,
            height: displaySize.height - 2 * Self.gap
        ))
        let pixels = CGSize(width: cell.width * scale, height: cell.height * scale)
        let shrink = min(1, limit / max(pixels.width, pixels.height, 1))
        return CGSize(width: (pixels.width * shrink).rounded(.up), height: (pixels.height * shrink).rounded(.up))
    }
}
