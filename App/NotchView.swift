import AppKit
import NotchKit
import SwiftUI

/// Everything drawn in the panel. The controller animates the state changes
/// (width, then height, then text; a track arriving or going); this only
/// draws whatever state it's in.
struct NotchView: View {
    let layout: NotchLayout

    var body: some View {
        let track = layout.track
        // Art that failed to load is treated as none: text only, with the note.
        let hasArt = track?.art != nil && !layout.artworkFailed
        let frames = NotchFrames(
            kind: layout.kind,
            shape: layout.shape,
            wide: layout.widthOpen,
            tall: layout.heightOpen,
            visible: track != nil,
            hasArt: hasArt
        )
        ZStack(alignment: .topLeading) {
            if NotchStyle.showsPanelBounds {
                Rectangle()
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
            }

            NotchSurface(geometry: frames.surface)
                .fill(NotchStyle.bezel)

            // Clipped to the surface, so nothing ever draws outside the
            // black, whatever the timing of the steps.
            ZStack(alignment: .topLeading) {
                if let track {
                    artwork(frames, hasArt: hasArt)
                    if layout.showsDetails {
                        details(track)
                            .frame(width: frames.text.width, height: frames.text.height, alignment: .leading)
                            .offset(x: frames.text.minX, y: frames.text.minY)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -3)), removal: .opacity))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask(NotchSurface(geometry: frames.surface))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The panel only takes clicks while open, and only on the surface.
        .contentShape(NotchSurface(geometry: frames.surface))
        .onTapGesture {
            guard layout.expanded, let url = layout.track?.url else { return }
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private func artwork(_ frames: NotchFrames, hasArt: Bool) -> some View {
        if hasArt {
            // The slot is there straight away; the image fades into it once
            // it has loaded, and nothing waits on it.
            ZStack {
                Rectangle()
                    .fill(NotchStyle.artPlaceholder)
                if let image = layout.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .frame(width: frames.art.width, height: frames.art.height)
            .clipShape(RoundedRectangle(cornerRadius: frames.artCornerRadius, style: .continuous))
            .offset(x: frames.art.minX, y: frames.art.minY)
        } else if !layout.heightOpen {
            // No art: a small note in the wing, gone once the panel opens to text only.
            Image(systemName: NotchStyle.noArtSymbol)
                .font(.system(size: NotchStyle.noArtSymbolSize, weight: .semibold))
                .foregroundStyle(NotchStyle.secondaryText)
                .frame(width: frames.art.width, height: frames.art.height)
                .offset(x: frames.art.minX, y: frames.art.minY)
                .transition(.opacity)
        }
    }

    private func details(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: NotchStyle.lineSpacing) {
            // Redrawn every half minute, so "20 minutes ago" keeps counting
            // between polls.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(track.status(at: context.date))
                    .font(NotchStyle.statusFont)
                    .foregroundStyle(NotchStyle.tertiaryText)
            }
            Text(track.track ?? "")
                .font(NotchStyle.titleFont)
                .foregroundStyle(NotchStyle.primaryText)
            if let artist = track.artist {
                Text(artist)
                    .font(NotchStyle.artistFont)
                    .foregroundStyle(NotchStyle.secondaryText)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

/// Where everything goes, in the panel's top-left coordinates. Width and
/// height open separately: `wide` alone is a bar the notch's height reaching
/// the full width; `tall` drops it into the full panel. Not `visible`, the
/// surface shrinks to nothing in the middle of the notch, behind the hardware.
struct NotchFrames {
    var surface: SurfaceGeometry
    var art: CGRect
    var artCornerRadius: CGFloat
    var text: CGRect

    init(kind: NotchMetrics.Kind, shape: CGRect, wide: Bool, tall: Bool, visible: Bool, hasArt: Bool) {
        let trailing = NotchStyle.wingSide == .trailing
        let small = NotchStyle.restingArtSize
        let big = NotchStyle.expandedArtSize

        // The resting shape, and the fully open one.
        let resting = kind == .notch
            ? NotchGeometry.restingBody(notch: shape, wing: NotchStyle.wingWidth, side: NotchStyle.wingSide)
            : shape
        let open = NotchGeometry.expandedSurface(around: shape, size: NotchStyle.expandedSize)

        // The content area below the notch, where the big art and the text go.
        let contentTop = kind == .notch ? open.minY + shape.height : open.minY
        let bigArt = CGRect(
            x: trailing ? open.maxX - NotchStyle.contentPadding - big : open.minX + NotchStyle.contentPadding,
            y: contentTop + (open.maxY - contentTop - big) / 2,
            width: big,
            height: big
        )
        if hasArt {
            text = CGRect(
                x: trailing ? open.minX + NotchStyle.contentPadding : bigArt.maxX + NotchStyle.textGap,
                y: bigArt.minY,
                width: open.width - big - NotchStyle.textGap - NotchStyle.contentPadding * 2,
                height: big
            )
        } else {
            // Text only: the whole width.
            text = CGRect(
                x: open.minX + NotchStyle.contentPadding,
                y: bigArt.minY,
                width: open.width - NotchStyle.contentPadding * 2,
                height: big
            )
        }

        guard visible else {
            // Nothing to show: a sliver of nothing in the middle of the shape,
            // so appearing is sliding out of the notch.
            let middle = CGRect(x: shape.midX, y: shape.minY, width: 0, height: shape.height)
            let radius = kind == .pill ? shape.height / 2 : 0
            surface = SurfaceGeometry(rect: middle, topRadius: radius, bottomLeadingRadius: radius, bottomTrailingRadius: radius)
            art = CGRect(x: shape.midX, y: shape.midY, width: 0, height: 0)
            artCornerRadius = 0
            return
        }

        // Width and height each come from whichever step they're at.
        let horizontal = wide ? open : resting
        let rect = CGRect(x: horizontal.minX, y: resting.minY, width: horizontal.width, height: tall ? open.height : resting.height)

        switch kind {
        case .notch:
            let bottom: (leading: CGFloat, trailing: CGFloat)
            let shoulders: (leading: CGFloat, trailing: CGFloat)
            if tall {
                let corner = NotchStyle.expandedCornerRadius
                bottom = (corner, corner)
            } else if wide {
                // A bar out of both sides now, so both ends are rounded.
                bottom = (NotchStyle.wingCornerRadius, NotchStyle.wingCornerRadius)
            } else {
                // Square on the side hidden inside the notch.
                bottom = trailing ? (0, NotchStyle.wingCornerRadius) : (NotchStyle.wingCornerRadius, 0)
            }
            if wide {
                shoulders = (NotchStyle.expandedShoulderRadius, NotchStyle.expandedShoulderRadius)
            } else {
                shoulders = trailing ? (0, NotchStyle.shoulderRadius) : (NotchStyle.shoulderRadius, 0)
            }
            surface = SurfaceGeometry(
                rect: rect,
                bottomLeadingRadius: bottom.leading,
                bottomTrailingRadius: bottom.trailing,
                leadingShoulder: shoulders.leading,
                trailingShoulder: shoulders.trailing
            )
        case .pill:
            let corner = tall ? NotchStyle.expandedCornerRadius : shape.height / 2
            surface = SurfaceGeometry(rect: rect, topRadius: corner, bottomLeadingRadius: corner, bottomTrailingRadius: corner)
        }

        if tall {
            art = bigArt
            artCornerRadius = NotchStyle.expandedArtCornerRadius
        } else {
            // Small, riding the outer end: the wing's middle at rest, the same
            // distance in from the end once the bar has widened.
            let inset = kind == .notch ? (NotchStyle.wingWidth - small) / 2 : (shape.height - small) / 2
            art = CGRect(
                x: trailing ? rect.maxX - inset - small : rect.minX + inset,
                y: shape.minY + (shape.height - small) / 2,
                width: small,
                height: small
            )
            artCornerRadius = NotchStyle.restingArtCornerRadius
        }
    }
}
