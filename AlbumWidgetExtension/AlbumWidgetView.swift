import SwiftUI
import WidgetKit

struct AlbumWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AlbumEntry

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            HStack(spacing: 0) {
                if family.isWide {
                    Cover(data: entry.cover, size: CGSize(width: size.height, height: size.height))
                    Titles(album: entry.album, scale: size.height / 160)
                } else {
                    // Small and large are near enough square that the cover fills them.
                    Cover(data: entry.cover, size: size)
                }
            }
            // The old album blurs out as the new one blurs in. WidgetKit caps
            // entry animations at about 2 seconds.
            .id(entry.album?.key)
            .transition(.blurReplace)
            .animation(.smooth(duration: 1.1), value: entry.album?.key)
        }
        // A thin frame of the widget's own dark body, like the system widgets
        // have. A cover run to the very edge puts the glass rim straight onto
        // the artwork, which reads as a hard white outline.
        .padding(Palette.frame)
        .widgetURL(NowPlaying.widgetURL)
    }
}

extension WidgetFamily {
    /// Wide sizes put the titles beside the cover; the rest are cover only.
    var isWide: Bool {
        self == .systemMedium || self == .systemExtraLarge
    }
}

private struct Cover: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: Data?
    let size: CGSize

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Palette.tile(colorScheme)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: min(size.width, size.height) / 4))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        // Corners concentric with the widget's own.
        .clipShape(ContainerRelativeShape())
    }
}

private struct Titles: View {
    let album: Album?
    /// 1 at the medium size; the type grows with the widget's height.
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(album?.title ?? "Nothing played yet")
                .font(.system(size: 15 * scale, weight: .semibold))
                .lineLimit(3)
            if let artist = album?.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(14 * scale)
    }
}

struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Palette.background(colorScheme)
    }
}

/// Neutral, so the cover is the only color in the widget.
enum Palette {
    static let frame: CGFloat = 4

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.11) : .white
    }

    static func tile(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.18) : Color(white: 0.95)
    }
}
