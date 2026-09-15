import CoreGraphics

/// Where the notch is on a screen, or where a stand-in pill goes on one without.
public struct NotchMetrics: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A hardware cutout; `rect` is exactly its size.
        case notch
        /// No cutout: a floating pill centered under the menu bar.
        case pill
    }

    public var kind: Kind
    /// The collapsed shape, in AppKit screen coordinates (origin bottom-left).
    public var rect: CGRect
    public var screenFrame: CGRect

    public init(kind: Kind, rect: CGRect, screenFrame: CGRect) {
        self.kind = kind
        self.rect = rect
        self.screenFrame = screenFrame
    }
}

public enum NotchGeometry {
    /// Measures the notch from what the screen reports rather than from a
    /// table of models, since it differs between MacBooks.
    public static func metrics(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeft: CGRect?,
        auxiliaryRight: CGRect?,
        pillSize: CGSize,
        pillGap: CGFloat
    ) -> NotchMetrics {
        // A notched display insets its safe area by the notch's height and
        // reports the usable menu bar on either side of the cutout; the gap
        // between those two areas is the notch.
        if safeAreaTop > 0, let left = auxiliaryLeft, let right = auxiliaryRight, right.minX > left.maxX {
            let rect = CGRect(
                x: left.maxX,
                y: screenFrame.maxY - safeAreaTop,
                width: right.minX - left.maxX,
                height: safeAreaTop
            )
            return NotchMetrics(kind: .notch, rect: rect, screenFrame: screenFrame)
        }

        // The visible frame stops at the bottom of the menu bar; with the menu
        // bar set to hide, the two tops meet and the pill sits at the edge.
        let menuBarBottom = min(visibleFrame.maxY, screenFrame.maxY)
        let rect = CGRect(
            x: screenFrame.midX - pillSize.width / 2,
            y: menuBarBottom - pillGap - pillSize.height,
            width: pillSize.width,
            height: pillSize.height
        )
        return NotchMetrics(kind: .pill, rect: rect, screenFrame: screenFrame)
    }

    /// The panel: `canvas`-sized, hanging from the top of the collapsed shape,
    /// centered on it, and kept on the screen.
    public static func panelFrame(for metrics: NotchMetrics, canvas: CGSize) -> CGRect {
        let screen = metrics.screenFrame
        let centered = metrics.rect.midX - canvas.width / 2
        let x = min(max(centered, screen.minX), screen.maxX - canvas.width)
        return CGRect(x: x, y: metrics.rect.maxY - canvas.height, width: canvas.width, height: canvas.height)
    }

    /// `rect`, given in screen coordinates, as seen from inside `panel` with
    /// SwiftUI's top-left origin.
    public static func rect(_ rect: CGRect, inPanel panel: CGRect) -> CGRect {
        CGRect(x: rect.minX - panel.minX, y: panel.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
