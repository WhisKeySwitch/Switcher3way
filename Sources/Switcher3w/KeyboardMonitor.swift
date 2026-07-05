import AppKit
import CoreGraphics
import Foundation

/// Marker for synthesized events — KeyboardMonitor ignores them
let kSwitcher3wEventMarker: Int64 = 0x52555300

/// One keystroke in the conversion buffer. For normal local input the keyCode is known
/// (char == nil). For input forwarded via remote desktop, Apple Screen Sharing
/// sends keyCode 0 + the character itself — then char != nil, and conversion goes by the
/// character, not by the useless keyCode 0 (keyCode 0 is what produced the runaway repeat).
struct TypedKey {
    let keyCode: UInt16
    let shift: Bool
    let caps: Bool
    var char: Character? = nil
}

/// Dedicated queue for log file I/O — so disk writes don't block
/// the event-handling thread (the event tap sits on the main run loop, and the log is
/// written for each keystroke when debug is on).
private let rsLogQueue = DispatchQueue(label: "com.switcher3w.log")

func rslog(_ msg: String) {
    // Thread-safe: read UserDefaults directly (no MainActor)
    guard UserDefaults.standard.bool(forKey: "com.switcher3w.debugLog") else { return }

    let line = "\(Date()): \(msg)\n"
    rsLogQueue.async {
        let logDir = NSHomeDirectory() + "/Library/Logs/Switcher3w"
        let path = logDir + "/switcher3w.log"

        // Create the directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: logDir) {
            try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            // Rotation: if > 5MB — truncate
            if handle.offsetInFile > 5_000_000 {
                handle.truncateFile(atOffset: 0)
                handle.write("--- Log rotated ---\n".data(using: .utf8)!)
            }
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }
}

/// Trigger-key configuration (read from settings, cached in KeyboardMonitor).
struct TriggerConfig {
    enum Kind {
        case modifier(mask: CGEventFlags, left: UInt16, right: UInt16)
        /// Combo of two modifiers (e.g. ⌘+⇧). Detected by flags: both held without
        /// extras → all released with no keys in between. Side (left/right) doesn't matter.
        case combo(CGEventFlags, CGEventFlags)
        case capsLock
    }
    let kind: Kind
    let rightOnly: Bool
    let doubleTap: Bool

    var isCapsLock: Bool { if case .capsLock = kind { return true } else { return false } }

    static func current() -> TriggerConfig {
        let s = SettingsManager.shared
        let kind: Kind
        switch s.triggerKey {
        case "command": kind = .modifier(mask: .maskCommand, left: KC.leftCommand, right: KC.rightCommand)
        case "control": kind = .modifier(mask: .maskControl, left: KC.leftControl, right: KC.rightControl)
        case "shift":   kind = .modifier(mask: .maskShift,   left: KC.leftShift,   right: KC.rightShift)
        // Combo of two modifiers (issue #12: the familiar Windows-style Alt+Shift etc.).
        case "command+shift":  kind = .combo(.maskCommand, .maskShift)
        case "control+shift":  kind = .combo(.maskControl, .maskShift)
        case "command+option": kind = .combo(.maskCommand, .maskAlternate)
        case "control+option": kind = .combo(.maskControl, .maskAlternate)
        // TECH DEBT: native Caps Lock removed from the UI (unstable — HID debounce/toggle,
        // needs a Karabiner-level HID driver). The consume-path code is kept for the future.
        case "capsLock": kind = .capsLock
        default:        kind = .modifier(mask: .maskAlternate, left: KC.leftOption, right: KC.rightOption)
        }
        return TriggerConfig(kind: kind, rightOnly: s.triggerRightOnly, doubleTap: s.triggerDoubleTap)
    }
}

final class KeyboardMonitor: @unchecked Sendable {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Length of the word currently being typed
    private(set) var currentWordLength = 0
    /// Length of the word up to the last space
    private(set) var wordBeforeBoundaryLength = 0
    /// How many spaces after the word (spaces only, not enter/arrows)
    private(set) var boundaryCount = 0
    /// Were there real keystrokes since the last conversion?
    private(set) var keysTypedSinceConversion = true

    /// Keystrokes of the word being typed — for the retype engine (no clipboard)
    private(set) var currentWordKeys: [TypedKey] = []
    /// Keystrokes of the word before the last space boundary
    private(set) var prevWordKeys: [TypedKey] = []
    /// Frontmost app at the moment of the word boundary — so the auto-path doesn't retype
    /// into another field if focus moved away (Cmd-Tab/Spotlight) without a click/Tab.
    private(set) var prevWordBundleID: String?
    /// issue #7: armed on a layout switch → on the first letter we play the layout sound.
    var soundArmed = false

    private var onAltTap: (() -> Void)?
    private var onAltReconvert: (() -> Void)?
    /// Auto-conversion: called (async) at the word boundary when autoConvert is on.
    var onWordBoundary: (() -> Void)?
    /// issue #10: any user input/click — to hide the caret flag while typing.
    var onUserInput: (() -> Void)?
    /// issue #10: whether the caret-flag feature is on. Gates the onUserInput dispatch on the hot path,
    /// so when the feature is off (the default) we don't wake the main queue on every keystroke.
    var caretFlagEnabled = false

    // Trigger config (cache; updated in start/reconfigure)
    private var triggerConfig = TriggerConfig.current()

    // Solo-tap detection for the modifier
    private var triggerArmed = false
    private var triggerPressTime: Date?
    // For double tap
    private var lastTapTime: Date?
    private let tapWindow: TimeInterval = 0.4

    func start(
        onAltTap: @escaping () -> Void,
        onAltReconvert: @escaping () -> Void
    ) -> Bool {
        self.onAltTap = onAltTap
        self.onAltReconvert = onAltReconvert

        let precheck = CGPreflightListenEventAccess()
        rslog("Preflight check = \(precheck)")
        if !precheck {
            rslog("Requesting access...")
            CGRequestListenEventAccess()
        }

        triggerConfig = TriggerConfig.current()
        rslog("Attempting to create event tap... (trigger=\(SettingsManager.shared.triggerKey) capsLock=\(triggerConfig.isCapsLock))")
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Caps Lock requires an active tap (consume) to suppress case
        // switching. For modifiers we keep listenOnly — don't interfere with input.
        let options: CGEventTapOptions = triggerConfig.isCapsLock ? .defaultTap : .listenOnly

        // Remote desktop mode: the session level sees the keystrokes forwarded by Screen
        // Sharing (they're injected via CGEventPost, which the HID tap doesn't see).
        let tapLocation: CGEventTapLocation =
            SettingsManager.shared.remoteDesktopMode ? .cgSessionEventTap : .cghidEventTap
        rslog("Tap location: \(SettingsManager.shared.remoteDesktopMode ? "session (remote desktop)" : "hid")")

        guard let tap = CGEvent.tapCreate(
            tap: tapLocation,
            place: .tailAppendEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: keyboardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            rslog("FAILED to create event tap - no permission")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        rslog("Event tap created and enabled successfully")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Restarts the tap with the current trigger config. Needed on a setting change —
    /// especially when switching to/from Caps Lock, since the tap mode changes (consume).
    @discardableResult
    func reconfigure() -> Bool {
        guard let t = onAltTap, let r = onAltReconvert else { return false }
        rslog("Reconfiguring trigger…")
        stop()
        return start(onAltTap: t, onAltReconvert: r)
    }

    func markConverted() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        keysTypedSinceConversion = false
    }

    private func fullReset() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
    }

    /// A word ended on a space — if autoConvert is on, trigger the auto-path
    /// (async, so we don't block delivery of the current event).
    private func fireWordBoundary() {
        guard SettingsManager.shared.autoConvert else { return }
        let cb = onWordBoundary
        DispatchQueue.main.async { cb?() }
    }

    /// Reset the buffer on a mouse click — otherwise the retype backspace erases the wrong
    /// thing (the cursor may have moved elsewhere).
    fileprivate func resetBuffersOnClick() {
        triggerArmed = false
        lastTapTime = nil
        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: a click hides the caret flag
        fullReset()
    }

    // MARK: - Event Handling

    fileprivate func handleKeyDown(keyCode: UInt16, flags: CGEventFlags, char: Character? = nil) {
        triggerArmed = false
        lastTapTime = nil
        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: hide the flag while typing

        // Remote desktop: Screen Sharing sends forwarded characters as keyCode 0 + unicode. We
        // intercept ONLY in remote desktop mode. CRITICAL: locally keyCode 0 is the ordinary
        // 'a' key (and its Cyrillic letter in the JCUKEN layout) — it must not be swallowed, or
        // local conversion of words with these letters breaks. In local mode we don't reach here —
        // the letter takes the normal path below.
        if SettingsManager.shared.remoteDesktopMode, keyCode == 0 {
            if let ch = char { handleForwardedChar(ch) }
            return
        }

        // Structural keys are handled ALWAYS, even if a "dirty" modifier remains
        // in flags (stale .maskAlternate etc.) — otherwise the word counter
        // isn't reset and the conversion grabs extra characters.

        // Space — the only boundary we can come back through
        if keyCode == KC.space {
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                fireWordBoundary()
            } else {
                boundaryCount += 1
            }
            currentWordLength = 0
            currentWordKeys = []
            return
        }

        // Enter, Tab — full reset
        if keyCode == KC.enter || keyCode == KC.tab {
            fullReset()
            return
        }

        // Arrows (Left…Up) — full reset
        if keyCode >= KC.left && keyCode <= KC.up {
            fullReset()
            return
        }

        // Backspace
        if keyCode == KC.backspace {
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
            } else {
                fullReset()
            }
            return
        }

        // Count letters only without Cmd/Ctrl/Alt
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if !modifiers.isEmpty { return }

        if KeyMapping.keycodeToEN[keyCode] != nil {
            currentWordKeys.append(TypedKey(keyCode: keyCode, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift)))
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            playLayoutSoundIfArmed()
        } else {
            // Esc, F-keys, etc. — full reset
            fullReset()
        }
    }

    /// Handles a character forwarded via remote desktop (keyCode 0 + unicode).
    /// We work by the character itself: space — word boundary, backspace — rollback,
    /// letter — put the real character into the buffer (conversion goes by it, see convertKeys).
    private func handleForwardedChar(_ ch: Character) {
        // Space — word boundary (like the local keyCode space)
        if ch == " " {
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                fireWordBoundary()
            } else {
                boundaryCount += 1
            }
            currentWordLength = 0
            currentWordKeys = []
            return
        }
        // Newline / tab — full reset
        if ch == "\n" || ch == "\r" || ch == "\t" {
            fullReset()
            return
        }
        // Backspace / Delete — roll back one letter
        if ch == "\u{8}" || ch == "\u{7f}" {
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
            } else {
                fullReset()
            }
            return
        }
        // Letter — put the real character (keyCode 0 = "forwarded"). shift carried from case.
        if ch.isLetter {
            currentWordKeys.append(TypedKey(keyCode: 0, shift: ch.isUppercase, caps: false, char: ch))
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            playLayoutSoundIfArmed()
            return
        }
        // Digits/punctuation/other — don't move the word boundary, don't accumulate into the buffer.
    }

    /// issue #7: on the first letter after a layout switch we play a short sound depending on
    /// the layout — you hear which layout you started typing in. Optional, off by default.
    private func playLayoutSoundIfArmed() {
        guard soundArmed, SettingsManager.shared.keySound else { return }
        soundArmed = false
        let sources = LayoutSwitcher.installedLayouts()
        let id1 = SettingsManager.shared.layout1ID.isEmpty
            ? LayoutSwitcher.autoDetectID1(from: sources) : SettingsManager.shared.layout1ID
        let name = LayoutSwitcher.currentLayoutID() == id1 ? "Tink" : "Pop"
        NSSound(named: name)?.play()
    }

    /// Returns true if the event should be "eaten" (only Caps Lock in consume mode).
    fileprivate func handleFlagsChanged(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        switch triggerConfig.kind {
        case .capsLock:
            guard keyCode == KC.capsLock else { return false }
            // Caps Lock sends one event per press. We use it as a tap and eat it,
            // so the case doesn't switch.
            registerTap()
            return true

        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = triggerConfig.rightOnly ? [right] : [left, right]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let otherMods = allMods.subtracting(mask)

            if flags.contains(mask) {
                // press: arm only if it's the right key and there are no other modifiers
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    triggerArmed = true
                    triggerPressTime = Date()
                } else {
                    triggerArmed = false  // wrong side / combo
                }
            } else {
                // release: solo tap of the right key, fast and with no keys in between
                if triggerArmed, accepted.contains(keyCode), let t = triggerPressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            return false

        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                triggerArmed = false                 // an extra modifier is held — not our trigger
            } else if flags.contains(both) {
                triggerArmed = true                  // exactly both needed, no extras → arm
                triggerPressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                // all released: combo tap, if armed, fast and with no keys in between
                if triggerArmed, let t = triggerPressTime, Date().timeIntervalSince(t) < tapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            // partial state (one of two held) — wait, don't touch anything
            return false
        }
    }

    /// Accounts for single/double tap and starts the conversion.
    private func registerTap() {
        if triggerConfig.doubleTap {
            if let last = lastTapTime, Date().timeIntervalSince(last) < tapWindow {
                lastTapTime = nil
                fireConversion()
            } else {
                lastTapTime = Date()  // wait for the second tap
            }
        } else {
            fireConversion()
        }
    }

    private func fireConversion() {
        if !keysTypedSinceConversion {
            rslog("trigger: RECONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltReconvert?() }
        } else {
            rslog("trigger: CONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltTap?() }
        }
    }
}

// MARK: - C Callback

private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    // Ignore our own synthesized events by the marker
    if event.getIntegerValueField(.eventSourceUserData) == kSwitcher3wEventMarker {
        return Unmanaged.passRetained(event)
    }

    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .keyDown {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let remote = SettingsManager.shared.remoteDesktopMode
        // Remote desktop: ignore key auto-repeat — Screen Sharing latency produces
        // false repeats (that same runaway repeat) that clutter the conversion buffer.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, remote {
            return Unmanaged.passRetained(event)
        }
        // Remote desktop: Screen Sharing forwards characters as keyCode 0 + unicode payload.
        // We read the character itself — without it the buffer fills with keyCode 0 (= one character → runaway repeat).
        var forwardedChar: Character? = nil
        if remote, keyCode == 0 {
            var buf = [UniChar](repeating: 0, count: 4)
            var len = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
            if len >= 1, let scalar = UnicodeScalar(buf[0]) {
                forwardedChar = Character(scalar)
                if SettingsManager.shared.debugLogEnabled {
                    rslog("remote: forwarded char U+\(String(buf[0], radix: 16))")
                }
            }
        }
        monitor.handleKeyDown(keyCode: keyCode, flags: event.flags, char: forwardedChar)
    } else if type == .flagsChanged {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if monitor.handleFlagsChanged(flags: event.flags, keyCode: keyCode) {
            return nil  // eat Caps Lock so the case doesn't switch
        }
    } else if type == .leftMouseDown || type == .rightMouseDown {
        monitor.resetBuffersOnClick()
    }

    return Unmanaged.passRetained(event)
}
