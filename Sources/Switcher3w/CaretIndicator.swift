import AppKit
import ApplicationServices
import CoreGraphics
import Switcher3wCore

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

    /// A conversion happened → show WHAT changed: the typed form struck through, an arrow, the
    /// converted form, and the configured trigger as an undo hint. Before this, a successful fix
    /// produced no feedback at all — the text simply changed under the user.
    func conversionApplied(original: String, converted: String) {
        guard SettingsManager.shared.conversionChip else { return }
        guard !original.isEmpty, !converted.isEmpty else { return }
        guard feedbackAllowed() else { return }
        // Unlike the flag badge, the chip falls back to the window when no caret can be resolved:
        // knowing what was rewritten matters more than the exact position.
        guard let rect = axCaretRectAppKit() ?? focusedWindowAnchor() else { return }
        label.attributedStringValue = chipText(original: original, converted: converted)
        lastFlag = ""   // the label no longer holds a flag; force a refresh on the next layout change
        sizeToFit()
        present(at: rect)
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
        if flag != lastFlag {
            label.attributedStringValue = NSAttributedString(
                string: flag, attributes: [.font: NSFont.systemFont(ofSize: 14),
                                           .foregroundColor: NSColor.white])
            lastFlag = flag
            sizeToFit()
        }
        present(at: rect)
    }

    /// Order in without stealing focus, fade up, and arm the auto-hide. Shared by both surfaces.
    private func present(at rect: NSRect) {
        position(forCaret: rect)
        if !panel.isVisible { panel.orderFrontRegardless() }            // show WITHOUT stealing focus
        fade(to: 1, duration: 0.12)
        visible = true
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: showDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    /// `ghbdsn → привіт   ⌥` — the typed form struck through, the result, and the undo keycap.
    private func chipText(original: String, converted: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13)
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: original, attributes: [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.white.withAlphaComponent(0.55),
        ]))
        out.append(NSAttributedString(string: "  →  ", attributes: [
            .font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.55),
        ]))
        out.append(NSAttributedString(string: converted, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white,
        ]))
        // Names the key the user actually configured, not a hard-coded ⌥.
        let hint = L10n.chipUndoHint(L10n.triggerSymbol(SettingsManager.shared.triggerKey))
        out.append(NSAttributedString(string: "   \(hint)", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ]))
        return out
    }

    /// Resize the panel around whatever the label currently holds (the flag badge is ~30pt, a chip
    /// is as wide as the words it names).
    private func sizeToFit() {
        let padX: CGFloat = 10, padY: CGFloat = 6
        let size = label.attributedStringValue.size()
        let w = max(30, (size.width + padX * 2).rounded(.up))
        let h = max(24, (size.height + padY * 2).rounded(.up))
        panel.setContentSize(NSSize(width: w, height: h))
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: w, height: h)
    }

    /// The focused window's rectangle, used when no caret can be resolved (Electron hosts, WebKit
    /// views that expose no bounds). Not the caret, but it puts the chip against the right window
    /// rather than dropping the feedback entirely.
    private func focusedWindowAnchor() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        var windowRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRaw) == .success,
              let win = windowRaw, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        let window = win as! AXUIElement

        var posRaw: AnyObject?, sizeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRaw) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let pv = posRaw, let sv = sizeRaw,
              CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sv as! AXValue, .cgSize, &size),
              let primary = NSScreen.screens.first else { return nil }

        // AX is top-left origin on the primary screen; AppKit is bottom-left. Anchor near the
        // window's bottom-left so the chip sits under the text rather than over the title bar.
        let y = primary.frame.height - origin.y - size.height
        return NSRect(x: origin.x + 24, y: y + 24, width: 1, height: 18)
    }

    /// The suppression rules the feedback surfaces share. Stricter than the flag badge's used to
    /// be: the chip carries the text that was typed, so it must never appear anywhere conversion
    /// itself would be refused.
    private func feedbackAllowed() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard !SecureFieldDetector.isFocusedPassword else { return false }
        guard !AutoSwitchPolicy.shouldDeferToRemoteClient else { return false }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard !AutoSwitchPolicy.isDeniedApp(frontID) else { return false }
        guard frontID != Bundle.main.bundleIdentifier else { return false }
        return true
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
        guard AXIsProcessTrusted() else { return nil }
        // The focused-element guard, not just the process-global secure-input flag: an unmasked
        // "show password" field sets neither, and the badge would otherwise appear over one.
        guard !SecureFieldDetector.isFocusedPassword else { return nil }
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
