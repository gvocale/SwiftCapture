import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Looks up the one window named by --window-id and checks its owner.
@available(macOS 12.3, *)
enum WindowResolver {
    /// Find the window and verify the expected bundle id. Never activates anything.
    static func resolve(_ target: WindowTarget, in content: SCShareableContent) throws -> SCWindow {
        guard let window = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw CaptureController.CaptureError.configurationError(
                "Window \(target.windowID) was not found. It must exist and be visible (not minimized); list windows with CGWindowListCopyWindowInfo.")
        }
        if let message = WindowTargetRules.bundleMismatch(
            expected: target.expectedBundleID,
            actual: window.owningApplication?.bundleIdentifier,
            windowID: target.windowID) {
            throw CaptureController.CaptureError.configurationError(message)
        }
        return window
    }

    /// Fetch current shareable content and resolve the window.
    static func resolve(_ target: WindowTarget) async throws -> SCWindow {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw CaptureController.CaptureError.contentRetrievalFailed(error)
        }
        return try resolve(target, in: content)
    }

    /// Backing scale (pixels per point) of the display that holds most of the window.
    static func displayScale(for frame: CGRect) -> CGFloat {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(frame, UInt32(ids.count), &ids, &count)
        let display = count > 0 ? ids[0] : CGMainDisplayID()
        if let mode = CGDisplayCopyDisplayMode(display), mode.width > 0 {
            return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
        }
        return 1.0
    }

    /// Native pixel size of the window (even dimensions).
    static func pixelSize(of window: SCWindow) -> CGSize {
        WindowTargetRules.pixelSize(points: window.frame.size, scale: displayScale(for: window.frame))
    }
}
