import AppKit
import ApplicationServices
import CoreGraphics

/// issue #10: shows the current layout flag next to the text caret — briefly after
/// a switch, hides on typing/click. The caret position is obtained via Accessibility
/// (kAXBoundsForRangeParameterizedAttribute). If the app doesn't provide it (Electron/web,
/// some terminals) — we simply don't show it; the menu-bar flag remains. Click-through,
/// doesn't steal focus (LSUIElement + .nonactivatingPanel + orderFrontRegardless).
@MainActor
final class CaretIndicator {
    private let panel: NSPanel
    private let label: NSTextField
    private var lastFlag = ""
    private var hideTimer: Timer?
    private var visible = false

    /// Provider of the current layout flag — usually AppDelegate.flagForCurrentLayout.
    var flagProvider: () -> String = { "" }

    /// How long we keep the flag after a switch before hiding it ourselves (if nothing is typed).
    private let showDuration: TimeInterval = 1.6

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 30, height: 24),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true                 // click-through — mandatory
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true

        // Semi-transparent rounded backdrop — flag readability on any background.
        let backdrop = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        backdrop.layer?.cornerRadius = 5
        panel.contentView = backdrop

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
        ])
    }

    // MARK: - Entry points (called from AppDelegate)

    /// A real layout change → show the flag at the caret (for showDuration).
    func layoutChanged() {
        guard SettingsManager.shared.caretFlag else { return }
        showAtCaret()
    }

    /// Any user input/click → hide (issue #10: "hide on typing").
    func userTyped() { if visible { hide() } }

    /// Feature disabled / exit — remove the window and timer.
    func teardown() {
        hideTimer?.invalidate(); hideTimer = nil
        panel.orderOut(nil)
        visible = false
        lastFlag = ""
    }

    // MARK: - Internals

    private func showAtCaret() {
        guard let rect = axCaretRectAppKit() else { hide(); return }   // no caret → don't show
        let flag = flagProvider()
        guard !flag.isEmpty else { hide(); return }
        if flag != lastFlag { label.stringValue = flag; lastFlag = flag }
        position(forCaret: rect)
        if !panel.isVisible { panel.orderFrontRegardless() }            // show WITHOUT stealing focus
        fade(to: 1, duration: 0.12)
        visible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: showDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func hide() {
        hideTimer?.invalidate(); hideTimer = nil
        guard visible else { return }
        visible = false
        // Stays ordered-in at alpha 0 — invisible and click-through; full orderOut in teardown().
        fade(to: 0, duration: 0.18)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            panel.animator().alphaValue = alpha
        }
    }

    /// Place the flag to the right of the caret (vertically centered), clamped to the screen's visible area.
    private func position(forCaret caret: NSRect) {
        let gap: CGFloat = 6
        let size = panel.frame.size
        var x = caret.maxX + gap
        var y = caret.midY - size.height / 2
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY)) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            if x + size.width > vf.maxX { x = caret.minX - gap - size.width }  // doesn't fit on the right → left
            x = min(max(x, vf.minX), vf.maxX - size.width)
            y = min(max(y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// The caret in AppKit coordinates (bottom-left), or nil if unavailable / a guard rejected it.
    private func axCaretRectAppKit() -> NSRect? {
        guard SettingsManager.shared.caretFlag else { return nil }
        guard AXIsProcessTrusted() else { return nil }
        guard !AutoSwitchPolicy.secureInputActive else { return nil }          // not over a password field
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // We do NOT apply the auto-conversion denylist: it's about "don't change text", and the flag changes nothing —
        // in IDEs/terminals the layout indicator is actually useful. Passwords are guarded by secure-input above.
        guard !AutoSwitchPolicy.shouldDeferToRemoteClient else { return nil }  // remote desktop: the caret is on the other side
        guard frontID != Bundle.main.bundleIdentifier else { return nil }      // not over our own window

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Limit the AX round-trip: with a hung/busy target (or Chromium, whose tree
        // is only being built after AXManualAccessibility) the default ~6s timeout would hang the main
        // thread. 0.25s — didn't make it, so nil → hide(), without a UI stall on a layout change.
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        enableChromiumA11y(axApp)   // raise the lazy Electron/Chromium tree (idempotent)
        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focused = focusedRaw else { return nil }
        let element = focused as! AXUIElement
        // Native Cocoa → range path; web/Electron → text-marker (private AX attributes).
        guard let topLeft = axCaretRectTopLeft(of: element) ?? axCaretRectViaTextMarker(of: element) else { return nil }

        // AX returns global coordinates with the origin at the top-left of the PRIMARY screen; AppKit — bottom-left.
        // We flip over the primary screen's full height (screens.first), not visibleFrame, not the target's.
        guard let primary = NSScreen.screens.first else { return nil }
        var r = topLeft
        r.origin.y = primary.frame.height - topLeft.origin.y - topLeft.height
        return r
    }

    private func axCaretRectTopLeft(of element: AXUIElement) -> CGRect? {
        var rangeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rv = rangeValue, CFGetTypeID(rv) == AXValueGetTypeID() else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rv as! AXValue, .cfRange, &range) else { return nil }

        // Some Cocoa controls return an empty rectangle for zero length → we request 1 character,
        // with a fallback to the original zero-length range (an empty field where there's no next glyph).
        var q = range; q.length = 1
        guard let arg = AXValueCreate(.cfRange, &q) else { return nil }
        var boundsValue: AnyObject?
        var err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, arg, &boundsValue)
        if err != .success {
            guard let zeroArg = AXValueCreate(.cfRange, &range) else { return nil }
            err = AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, zeroArg, &boundsValue)
        }
        guard err == .success, let bv = boundsValue, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect) else { return nil }
        // Caret: width = 0 (a thin line), but height = line height. VS Code canvas returns
        // (0,N,0x0) — height 0 = no real geometry, don't show (otherwise a badge in the screen corner).
        guard rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect
    }

    /// Electron/Chromium build the a11y tree lazily — we raise it with the private
    /// AXManualAccessibility attribute (as TextSniper/PopClip do). Idempotent (on an already-enabled
    /// Chromium and on native apps — a no-op). No caching by pid: pids are reused when
    /// apps restart, and a "forever" cache would break the flag for a restarted Electron.
    private func enableChromiumA11y(_ axApp: AXUIElement) {
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Web/Electron: the caret comes via AXTextMarker, not CFRange. Private,
    /// undocumented attributes (stable in practice for years).
    private func axCaretRectViaTextMarker(of element: AXUIElement) -> CGRect? {
        var markerRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
              let mr = markerRange else { return nil }
        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, "AXBoundsForTextMarkerRange" as CFString, mr as CFTypeRef, &boundsValue) == .success,
              let bv = boundsValue, CFGetTypeID(bv) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect) else { return nil }
        // The same guard as in the range path: reject degenerate geometry (web/Electron
        // sometimes returns (x,y,0x0) with a nonzero origin — height>=1 catches this, including .zero).
        guard rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect   // screen coordinates, top-left
    }
}
