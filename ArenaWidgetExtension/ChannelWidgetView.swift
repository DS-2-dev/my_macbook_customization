import ArenaKit
import SwiftUI
import WidgetKit

struct ChannelWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ChannelEntry

    private var tiles: [Tile] { entry.tiles }

    var body: some View {
        let grid = GridSpec(family)
        GeometryReader { geometry in
            TileGrid(grid: grid, cell: grid.cellSize(in: geometry.size), tiles: tiles, showTitles: entry.showTitles)
        }
        // Outer tile corners follow the widget's own rounded corners.
        .clipShape(ContainerRelativeShape())
        .overlay { message }
        .padding(GridSpec.gap)
        .redacted(reason: entry.status == .placeholder ? .placeholder : [])
        .widgetURL(family == .systemSmall ? tiles.first?.link : ArenaLink.channel(entry.slug))
    }

    @ViewBuilder private var message: some View {
        switch entry.status {
        case .notFound: Caption("Channel not found")
        case .unauthorized: Caption("This channel is private")
        case .loaded where tiles.isEmpty: Caption("No blocks yet")
        default: EmptyView()
        }
    }
}

private struct TileGrid: View {
    let grid: GridSpec
    let cell: CGSize
    let tiles: [Tile]
    let showTitles: Bool

    var body: some View {
        VStack(spacing: GridSpec.gap) {
            ForEach(0..<grid.rows, id: \.self) { row in
                HStack(spacing: GridSpec.gap) {
                    ForEach(0..<grid.columns, id: \.self) { column in
                        let index = row * grid.columns + column
                        TileSlot(tile: index < tiles.count ? tiles[index] : nil, index: index, cell: cell, showTitle: showTitles)
                    }
                }
            }
        }
    }
}

/// One grid position. When the rotation moves on, the old block blurs out and
/// the new one blurs in, staggered across the grid so the change sweeps
/// rather than flashing. WidgetKit caps entry animations at about 2 seconds.
private struct TileSlot: View {
    let tile: Tile?
    let index: Int
    let cell: CGSize
    let showTitle: Bool

    var body: some View {
        // A ZStack per slot keeps the outgoing and incoming tiles stacked in
        // place while they cross, instead of pushing each other in the row.
        ZStack {
            TileView(tile: tile, cell: cell, showTitle: showTitle)
                .id(tile?.id)
                .transition(.blurReplace)
        }
        .frame(width: cell.width, height: cell.height)
        .clipped()
        .animation(.smooth(duration: 1.1).delay(Double(index) * 0.08), value: tile?.id)
    }
}

private struct TileView: View {
    @Environment(\.colorScheme) private var colorScheme
    let tile: Tile?
    let cell: CGSize
    let showTitle: Bool

    var body: some View {
        if let tile {
            Link(destination: tile.link) {
                content(tile)
            }
            .buttonStyle(.plain)
        } else {
            Palette.tile(colorScheme)
        }
    }

    private func content(_ tile: Tile) -> some View {
        let shortSide = min(cell.width, cell.height)
        return ZStack(alignment: .bottomLeading) {
            switch tile.kind {
            case .image:
                if let data = tile.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                        .frame(width: cell.width, height: cell.height)
                } else {
                    Palette.tile(colorScheme)
                }
            case .text:
                Palette.tile(colorScheme)
                    .overlay(alignment: .topLeading) {
                        Text(tile.text ?? "")
                            .font(.system(size: min(13, max(9, shortSide / 11))))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(shortSide > 100 ? 9 : 6)
                    }
            }

            if showTitle, let title = tile.title, title != tile.text {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.background(colorScheme).opacity(0.9))
            }
        }
        .frame(width: cell.width, height: cell.height)
        .clipped()
    }
}

private struct Caption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(8)
    }
}

struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Palette.background(colorScheme)
    }
}

/// Neutral, like Are.na itself: the blocks should be the only color in the widget.
enum Palette {
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.11) : .white
    }

    static func tile(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.18) : Color(white: 0.95)
    }
}
