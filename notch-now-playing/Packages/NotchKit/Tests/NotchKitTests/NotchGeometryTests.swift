import CoreGraphics
import Testing
@testable import NotchKit

@Suite struct NotchGeometryTests {
    private let pill = CGSize(width: 180, height: 32)

    /// The 16-inch MacBook Pro, as its screen reports itself.
    private func macBookPro16() -> NotchMetrics {
        NotchGeometry.metrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            visibleFrame: CGRect(x: 0, y: 81, width: 1728, height: 1003),
            safeAreaTop: 32,
            auxiliaryLeft: CGRect(x: 0, y: 1085, width: 771.5, height: 32),
            auxiliaryRight: CGRect(x: 956.5, y: 1085, width: 771.5, height: 32),
            pillSize: pill,
            pillGap: 6
        )
    }

    @Test func notchIsTheGapBetweenTheMenuBarAreas() {
        let metrics = macBookPro16()
        #expect(metrics.kind == .notch)
        #expect(metrics.rect == CGRect(x: 771.5, y: 1085, width: 185, height: 32))
    }

    @Test func externalDisplayGetsAPillUnderTheMenuBar() {
        // A 1440p monitor to the right of the laptop, with a 24pt menu bar.
        let screen = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
        let metrics = NotchGeometry.metrics(
            screenFrame: screen,
            visibleFrame: CGRect(x: 1728, y: 0, width: 2560, height: 1416),
            safeAreaTop: 0,
            auxiliaryLeft: nil,
            auxiliaryRight: nil,
            pillSize: pill,
            pillGap: 6
        )
        #expect(metrics.kind == .pill)
        #expect(metrics.rect == CGRect(x: 1728 + 1280 - 90, y: 1416 - 6 - 32, width: 180, height: 32))
    }

    @Test func hiddenMenuBarPutsThePillAtTheTop() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let metrics = NotchGeometry.metrics(
            screenFrame: screen, visibleFrame: screen, safeAreaTop: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, pillSize: pill, pillGap: 6
        )
        #expect(metrics.rect.maxY == CGFloat(1080 - 6))
    }

    @Test func insetWithoutMenuBarAreasIsNotANotch() {
        let metrics = NotchGeometry.metrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32, auxiliaryLeft: nil, auxiliaryRight: nil, pillSize: pill, pillGap: 6
        )
        #expect(metrics.kind == .pill)
    }

    @Test func panelHangsFromTheNotchCentered() {
        let metrics = macBookPro16()
        let panel = NotchGeometry.panelFrame(for: metrics, canvas: CGSize(width: 480, height: 220))
        #expect(panel == CGRect(x: 864 - 240, y: 1117 - 220, width: 480, height: 220))
        // Seen from inside the panel, the notch is centered along the top edge.
        #expect(NotchGeometry.rect(metrics.rect, inPanel: panel) == CGRect(x: 147.5, y: 0, width: 185, height: 32))
    }

    @Test func restingBodyReachesPastOneSideFromTheMiddle() {
        let notch = CGRect(x: 147.5, y: 0, width: 185, height: 32)
        let trailing = NotchGeometry.restingBody(notch: notch, wing: 26, side: .trailing)
        #expect(trailing == CGRect(x: 240, y: 0, width: 118.5, height: 32))
        #expect(trailing.maxX == notch.maxX + 26)

        let leading = NotchGeometry.restingBody(notch: notch, wing: 26, side: .leading)
        #expect(leading.minX == notch.minX - 26)
        #expect(leading.maxX == notch.midX)
    }

    @Test func expandedSurfaceHangsCenteredFromTheNotch() {
        let notch = CGRect(x: 147.5, y: 0, width: 185, height: 32)
        let surface = NotchGeometry.expandedSurface(around: notch, size: CGSize(width: 380, height: 132))
        #expect(surface == CGRect(x: 50, y: 0, width: 380, height: 132))
        #expect(surface.midX == notch.midX)
    }

    @Test func panelCoordinatesRoundTrip() {
        let panel = CGRect(x: 624, y: 897, width: 480, height: 220)
        let notch = CGRect(x: 771.5, y: 1085, width: 185, height: 32)
        let inside = NotchGeometry.rect(notch, inPanel: panel)
        #expect(NotchGeometry.rect(inside, fromPanel: panel) == notch)
    }

    @Test func panelStaysOnScreen() {
        let metrics = NotchMetrics(
            kind: .pill,
            rect: CGRect(x: 10, y: 1000, width: 180, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 1080)
        )
        let panel = NotchGeometry.panelFrame(for: metrics, canvas: CGSize(width: 480, height: 220))
        #expect(panel.minX == 0)
    }
}
