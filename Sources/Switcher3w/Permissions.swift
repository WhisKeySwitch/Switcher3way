import AppKit
import ApplicationServices

/// What the app needs from macOS before it can work, per build flavour.
///
/// **Direct build:** two grants, Accessibility and Input Monitoring. Its keyboard monitor is a
/// listen-only event tap, which macOS gates under Input Monitoring.
///
/// **App Store build:** one grant, Accessibility — shown on macOS 27 as Privacy & Security →
/// Device Control and Data Access. Its keyboard monitor is an *active* tap, which macOS gates under
/// that same grant, so the build never asks for Input Monitoring at all. Measured 2026-09-30 with a
/// sandboxed build granted only there: its active tap saw every real and posted keystroke, and
/// `CGPreflightListenEventAccess()` reported true although the app appeared nowhere in the Input
/// Monitoring list. App Review rejected the two-permission Store build under guideline 2.4.5(v)
/// for the Input Monitoring request (2026-09-28). The Store build requires macOS 27, where this was
/// measured; earlier versions were not tested.
@MainActor
enum Permissions {

    /// Whether this build asks the user for Input Monitoring.
    nonisolated static var asksForInputMonitoring: Bool {
        #if SWITCHER_APPSTORE
        return false
        #else
        return true
        #endif
    }

    /// Whether the keyboard monitor must be an active tap. The Store build always uses one, because
    /// that is what lets it work without Input Monitoring; the direct build uses one only when Caps
    /// Lock is the trigger, since that tap has to swallow the key.
    nonisolated static func needsActiveTap(capsLockTrigger: Bool) -> Bool {
        !asksForInputMonitoring || capsLockTrigger
    }

    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Input Monitoring as far as this build is concerned. The Store build does not ask for it, so
    /// it is satisfied by definition there: its keyboard access comes with the Accessibility grant,
    /// and a missing grant is reported as Accessibility, never as a permission the user was never
    /// shown. The real preflight still goes into the log line.
    static var inputMonitoring: Bool {
        asksForInputMonitoring ? CGPreflightListenEventAccess() : true
    }

    /// Everything this build needs.
    static var allGranted: Bool { accessibility && inputMonitoring }

    /// One line for the log, naming what was checked in this flavour.
    static var logLine: String {
        asksForInputMonitoring
            ? "Permissions: accessibility=\(accessibility) inputMonitoring=\(CGPreflightListenEventAccess())"
            : "Permissions: accessibility=\(accessibility) (App Store build: no Input Monitoring request;"
              + " preflight reports \(CGPreflightListenEventAccess()))"
    }

    /// The Privacy & Security pane that holds the Accessibility grant. macOS 27 renamed it to
    /// Device Control and Data Access; the checklist names the pane the user will actually see.
    static var accessibilityPaneIsRenamed: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0,
                                                                                patchVersion: 0))
    }
}
