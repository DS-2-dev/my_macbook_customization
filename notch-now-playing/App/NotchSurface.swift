import SwiftUI

/// The black surface in every state, as one shape whose outline animates:
/// the resting wing, the expanded panel, and the pill on a screen without a
/// notch. Every number in it interpolates, so the spring morphs one outline
/// into the next instead of cross-fading two.
struct NotchSurface: Shape {
    var geometry: SurfaceGeometry

    var animatableData: SurfaceGeometry {
        get { geometry }
        set { geometry = newValue }
    }

    func path(in _: CGRect) -> Path {
        let g = geometry
        let minX = g.x, minY = g.y, maxX = g.x + g.width, maxY = g.y + g.height
        let limit = max(0, min(g.width, g.height) / 2)
        let top = min(max(g.topRadius, 0), limit)
        let bottomLeading = min(max(g.bottomLeadingRadius, 0), limit)
        let bottomTrailing = min(max(g.bottomTrailingRadius, 0), limit)
        let leadingShoulder = max(g.leadingShoulder, 0)
        let trailingShoulder = max(g.trailingShoulder, 0)
        // How far a cubic's control points sit along a quarter circle.
        let k: CGFloat = 0.5523

        var path = Path()
        // Top edge, left to right. A shoulder flares outward into the top of
        // the screen; a top radius rounds a corner that floats free of it.
        if leadingShoulder > 0 {
            path.move(to: CGPoint(x: minX - leadingShoulder, y: minY))
        } else {
            path.move(to: CGPoint(x: minX + top, y: minY))
        }
        if trailingShoulder > 0 {
            path.addLine(to: CGPoint(x: maxX + trailingShoulder, y: minY))
            path.addCurve(
                to: CGPoint(x: maxX, y: minY + trailingShoulder),
                control1: CGPoint(x: maxX + trailingShoulder * (1 - k), y: minY),
                control2: CGPoint(x: maxX, y: minY + trailingShoulder * (1 - k))
            )
        } else {
            path.addLine(to: CGPoint(x: maxX - top, y: minY))
            path.addCurve(
                to: CGPoint(x: maxX, y: minY + top),
                control1: CGPoint(x: maxX - top * (1 - k), y: minY),
                control2: CGPoint(x: maxX, y: minY + top * (1 - k))
            )
        }
        // Down the trailing side and round the bottom.
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomTrailing))
        path.addCurve(
            to: CGPoint(x: maxX - bottomTrailing, y: maxY),
            control1: CGPoint(x: maxX, y: maxY - bottomTrailing * (1 - k)),
            control2: CGPoint(x: maxX - bottomTrailing * (1 - k), y: maxY)
        )
        path.addLine(to: CGPoint(x: minX + bottomLeading, y: maxY))
        path.addCurve(
            to: CGPoint(x: minX, y: maxY - bottomLeading),
            control1: CGPoint(x: minX + bottomLeading * (1 - k), y: maxY),
            control2: CGPoint(x: minX, y: maxY - bottomLeading * (1 - k))
        )
        // Up the leading side, back to the start.
        if leadingShoulder > 0 {
            path.addLine(to: CGPoint(x: minX, y: minY + leadingShoulder))
            path.addCurve(
                to: CGPoint(x: minX - leadingShoulder, y: minY),
                control1: CGPoint(x: minX, y: minY + leadingShoulder * (1 - k)),
                control2: CGPoint(x: minX - leadingShoulder * (1 - k), y: minY)
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY + top))
            path.addCurve(
                to: CGPoint(x: minX + top, y: minY),
                control1: CGPoint(x: minX, y: minY + top * (1 - k)),
                control2: CGPoint(x: minX + top * (1 - k), y: minY)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The surface's outline as numbers SwiftUI can interpolate.
struct SurfaceGeometry: VectorArithmetic, Sendable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var topRadius: CGFloat = 0
    var bottomLeadingRadius: CGFloat = 0
    var bottomTrailingRadius: CGFloat = 0
    var leadingShoulder: CGFloat = 0
    var trailingShoulder: CGFloat = 0

    init(
        rect: CGRect,
        topRadius: CGFloat = 0,
        bottomLeadingRadius: CGFloat = 0,
        bottomTrailingRadius: CGFloat = 0,
        leadingShoulder: CGFloat = 0,
        trailingShoulder: CGFloat = 0
    ) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
        self.topRadius = topRadius
        self.bottomLeadingRadius = bottomLeadingRadius
        self.bottomTrailingRadius = bottomTrailingRadius
        self.leadingShoulder = leadingShoulder
        self.trailingShoulder = trailingShoulder
    }

    private init(_ values: [CGFloat]) {
        (x, y, width, height) = (values[0], values[1], values[2], values[3])
        (topRadius, bottomLeadingRadius, bottomTrailingRadius) = (values[4], values[5], values[6])
        (leadingShoulder, trailingShoulder) = (values[7], values[8])
    }

    private var values: [CGFloat] {
        [x, y, width, height, topRadius, bottomLeadingRadius, bottomTrailingRadius, leadingShoulder, trailingShoulder]
    }

    static var zero: SurfaceGeometry { SurfaceGeometry(Array(repeating: 0, count: 9)) }

    static func + (lhs: SurfaceGeometry, rhs: SurfaceGeometry) -> SurfaceGeometry {
        SurfaceGeometry(zip(lhs.values, rhs.values).map { $0 + $1 })
    }

    static func - (lhs: SurfaceGeometry, rhs: SurfaceGeometry) -> SurfaceGeometry {
        SurfaceGeometry(zip(lhs.values, rhs.values).map { $0 - $1 })
    }

    mutating func scale(by rhs: Double) {
        self = SurfaceGeometry(values.map { $0 * CGFloat(rhs) })
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + Double($1 * $1) }
    }
}
