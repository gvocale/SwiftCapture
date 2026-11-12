import Foundation
import CoreGraphics

/// How the target app is treated when recording starts.
enum ActivationPolicy: String, CaseIterable {
    /// Never raise, focus or otherwise change the frontmost app (default for --window-id).
    case preserve
    /// Bring the target application to the front first (legacy --app behaviour).
    case raise
}

/// One exact window to record, identified by its Core Graphics window ID.
struct WindowTarget: Equatable {
    let windowID: CGWindowID
    /// If set, the window's owning application must have exactly this bundle identifier.
    let expectedBundleID: String?
}

/// Pure helpers for exact-window capture (unit tested; no system access).
enum WindowTargetRules {
    /// Rec.709 limited-range H.264 needs even pixel dimensions. Floor to even, minimum 2.
    static func evenPixelSize(_ size: CGSize) -> CGSize {
        func even(_ v: CGFloat) -> CGFloat { max(2, CGFloat(Int(v.rounded()) & ~1)) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    /// Window pixel size from its point size and the display scale.
    static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        evenPixelSize(CGSize(width: points.width * scale, height: points.height * scale))
    }

    /// Returns nil when the owner matches (or no expectation was given), otherwise a refusal message.
    static func bundleMismatch(expected: String?, actual: String?, windowID: CGWindowID) -> String? {
        guard let expected = expected else { return nil }
        guard let actual = actual else {
            return "Window \(windowID) has no owning application; expected bundle id \(expected)."
        }
        if actual == expected { return nil }
        return "Window \(windowID) is owned by \(actual), not the expected \(expected). Refusing to record."
    }

    /// Option-combination rules for --window-id / --expect-bundle-id / --activation.
    /// Returns an error message, or nil if the combination is valid.
    static func validateOptions(windowID: Int?, expectBundleID: String?, activation: String?,
                                app: String?, areaGiven: Bool, screen: Int) -> String? {
        if let id = windowID, id <= 0 { return "--window-id must be a positive Core Graphics window ID." }
        if windowID == nil && expectBundleID != nil { return "--expect-bundle-id requires --window-id." }
        if let a = activation, ActivationPolicy(rawValue: a.lowercased()) == nil {
            return "--activation must be 'preserve' or 'raise' (got '\(a)')."
        }
        if windowID != nil {
            if app != nil || areaGiven || screen != 1 {
                return "--window-id conflicts with --app, --area and --screen."
            }
            if let a = activation, a.lowercased() == "raise" {
                return "--activation raise is not available with --window-id; exact-window capture never raises the app."
            }
        }
        return nil
    }
}
