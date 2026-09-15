import SwiftUI

/// Milestone 1: a solid red shape exactly where the notch is.
struct NotchView: View {
    let layout: NotchLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            if NotchStyle.showsPanelBounds {
                Rectangle()
                    .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
            }
            shape
                .frame(width: layout.shape.width, height: layout.shape.height)
                .offset(x: layout.shape.minX, y: layout.shape.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var shape: some View {
        switch layout.kind {
        case .notch: Rectangle().fill(Color.red)
        case .pill: Capsule().fill(Color.red)
        }
    }
}
