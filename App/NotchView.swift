import NotchKit
import SwiftUI

/// Everything drawn in the panel. Step 2: the resting state only.
struct NotchView: View {
    let layout: NotchLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            if NotchStyle.showsPanelBounds {
                Rectangle()
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
            }
            if layout.hasSomethingToShow {
                resting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var resting: some View {
        switch layout.kind {
        case .notch:
            let body = NotchGeometry.restingBody(notch: layout.shape, wing: NotchStyle.wingWidth, side: NotchStyle.wingSide)
            RestingNotch()
                .frame(width: body.width, height: body.height)
                .offset(x: body.minX, y: body.minY)
        case .pill:
            RestingPill()
                .frame(width: layout.shape.width, height: layout.shape.height)
                .offset(x: layout.shape.minX, y: layout.shape.minY)
        }
    }
}

/// The notch at rest: black out of one side, with the indicator in the part
/// that shows.
private struct RestingNotch: View {
    private var outerSide: HorizontalEdge { NotchStyle.wingSide == .trailing ? .trailing : .leading }

    var body: some View {
        NotchBodyShape(
            outerSide: outerSide,
            bottomRadius: NotchStyle.wingCornerRadius,
            shoulderRadius: NotchStyle.shoulderRadius
        )
        .fill(NotchStyle.bezel)
        .overlay(alignment: outerSide == .trailing ? .trailing : .leading) {
            Indicator()
                .frame(width: NotchStyle.wingWidth)
        }
    }
}

/// No notch: a black pill under the menu bar, indicator at the end.
private struct RestingPill: View {
    var body: some View {
        Capsule()
            .fill(NotchStyle.bezel)
            .overlay(alignment: .trailing) {
                Indicator()
                    .padding(.trailing, (NotchStyle.pillSize.height - NotchStyle.indicatorSize.height) / 2)
            }
    }
}

private struct Indicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: NotchStyle.indicatorCornerRadius, style: .continuous)
            .fill(NotchStyle.placeholderArt)
            .frame(width: NotchStyle.indicatorSize.width, height: NotchStyle.indicatorSize.height)
    }
}
