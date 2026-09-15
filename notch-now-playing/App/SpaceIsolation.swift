import AppKit
import OSLog

/// Keeps the panel out of the animation when you swipe between Spaces.
///
/// A window that joins every Space is still part of each one, so a swipe
/// slides it along with everything else, and the half of the black shape that
/// normally sits under the notch slides out into view. The menu bar doesn't
/// slide because it lives in a Space of its own, shown above all the others.
/// This puts the panel in one like it, so it stays exactly where the notch is.
///
/// There's no public API for that; it takes the window server's private one
/// (SkyLight), looked up by name when the app starts. If a future macOS drops
/// or renames any of it, this does nothing and the panel just slides along
/// with the Space, the way it did before.
@MainActor
final class SpaceIsolation {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, CFDictionary?) -> UInt64
    private typealias SpaceSetLevel = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias WindowsToSpaces = @convention(c) (Int32, CFArray, CFArray) -> Void

    private let connection: Int32
    private let space: UInt64
    private let addWindows: WindowsToSpaces
    private static let log = Logger(subsystem: "com.dantesmith.NowPlayingNotch", category: "space")

    /// The panel's own Space, drawn above everything at `level`. Nil when the
    /// private API isn't there.
    init?(level: Int32 = .max) {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainConnection = Self.symbol(skyLight, "MainConnectionID", as: MainConnection.self),
              let spaceCreate = Self.symbol(skyLight, "SpaceCreate", as: SpaceCreate.self),
              let spaceSetLevel = Self.symbol(skyLight, "SpaceSetAbsoluteLevel", as: SpaceSetLevel.self),
              let showSpaces = Self.symbol(skyLight, "ShowSpaces", as: ShowSpaces.self),
              let addWindows = Self.symbol(skyLight, "AddWindowsToSpaces", as: WindowsToSpaces.self)
        else {
            Self.log.error("space isolation unavailable; the panel will move with Space switches")
            return nil
        }
        connection = mainConnection()
        // The 1 matters: other values have Finder start drawing desktop icons
        // into the new Space.
        space = spaceCreate(connection, 1, nil)
        guard space != 0 else {
            Self.log.error("couldn't create the panel's Space")
            return nil
        }
        spaceSetLevel(connection, space, level)
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
        self.addWindows = addWindows
        Self.log.notice("panel has its own Space")
    }

    /// Moves `window` into the panel's Space. Needs a window number, so call
    /// it once the window has been ordered in.
    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        addWindows(connection, [NSNumber(value: window.windowNumber)] as CFArray, [NSNumber(value: space)] as CFArray)
    }

    /// The SkyLight name first, then the older CoreGraphics alias.
    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as _: T.Type) -> T? {
        for prefix in ["SLS", "CGS"] {
            if let pointer = dlsym(handle, prefix + name) {
                return unsafeBitCast(pointer, to: T.self)
            }
        }
        return nil
    }
}
