import SwiftUI

/// The black body of the resting state. Its inner edge sits inside the notch,
/// hidden by the hardware, so it's square; its outer edge is what shows, with a
/// rounded bottom corner and a concave shoulder flaring into the top of the
/// screen. The shoulder draws past the shape's frame on purpose.
struct NotchBodyShape: Shape {
    var outerSide: HorizontalEdge
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        // Drawn with the outer side on the right, then mirrored if needed.
        let bottom = min(bottomRadius, rect.height / 2, rect.width / 2)
        let shoulder = min(shoulderRadius, rect.height / 2)
        // How far a cubic's control points sit along a quarter circle.
        let k: CGFloat = 0.5523

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + shoulder, y: rect.minY))
        if shoulder > 0 {
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + shoulder),
                control1: CGPoint(x: rect.maxX + shoulder * (1 - k), y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + shoulder * (1 - k))
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottom, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - bottom * (1 - k)),
            control2: CGPoint(x: rect.maxX - bottom * (1 - k), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        guard outerSide == .leading else { return path }
        return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.minX + rect.maxX, ty: 0))
    }
}
