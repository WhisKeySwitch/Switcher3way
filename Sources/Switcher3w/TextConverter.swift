import AppKit
import ApplicationServices
import CoreGraphics

/// Text conversion between layouts
@MainActor
final class TextConverter {
    private var lastConvertedCount = 0
    private var lastBoundaryCount = 0
    private var savedClipboardItems: [NSPasteboardItem]?
    private var clipboardRestoreWork: DispatchWorkItem?
    private var isConverting = false
    /// Queue for injecting the buffer engine's keystrokes — so usleep doesn't block
    /// the main thread where the event tap sits (otherwise the tap starves → lag/lost keystrokes).
    nonisolated private let injectQueue = DispatchQueue(label: "com.switcher3w.inject", qos: .userInteractive)

    // State of the retype cycle (keystroke buffer → unicode insert). The manual trigger
    // cycles through the N-way candidates; auto-conversion is a single-step cycle. The cycle wraps
    // back to the original text AND to the layout active before the first conversion.
    private var cycleHome = ""                                        // original text (+ trailing spaces)
    private var cycleSteps: [(text: String, layoutID: String)] = []  // candidates (text already with spaces)
    private var cycleIndex = -1                                       // -1 = home shown; 0..n-1 = candidate i
    private var cycleShownCount = 0                                   // characters currently on screen (for erasing)
    private var cyclePreviousLayoutID = ""                           // the layout active BEFORE the first conversion
    private var lastWasBuffer = false

    /// Creates a CGEventSource with a marker so KeyboardMonitor ignores our events
    nonisolated private func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = kSwitcher3wEventMarker
        return source
    }

    /// Checks that the currently focused element is an editable text field
    private func isFocusedElementEditable() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRaw: AnyObject?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw)
        guard err == .success, let focused = focusedRaw else {
            rslog("editable: no focused element")
            return false
        }

        let element = focused as! AXUIElement

        // Check the role
        var roleRaw: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRaw)
        let role = (roleRaw as? String) ?? ""

        // Text roles
        let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXWebArea"]
        if textRoles.contains(role) {
            // Additionally: not read-only?
            var editableRaw: AnyObject?
            let editErr = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRaw)
            // If the attribute is missing — assume editable (AXWebArea may not have it)
            if editErr == .success, let editable = editableRaw as? Bool {
                rslog("editable: role=\(role) editable=\(editable)")
                return editable
            }
            rslog("editable: role=\(role) (no AXEditable attr, assuming yes)")
            return true
        }

        rslog("editable: role=\(role) — not a text field")
        return false
    }

    // MARK: - Public API

    /// Starts the retype cycle: erases `eraseCount` typed characters and types
    /// the first candidate. `home` — original text (with trailing spaces) the cycle
    /// wraps back to; `previousLayoutID` — the layout BEFORE switching (for exact undo).
    /// Returns the target layout ID of the first candidate, or nil. Shared engine for auto-
    /// conversion (single-step cycle) and the manual trigger (cycling through all N-way candidates).
    func beginCycle(home: String, steps: [(text: String, layoutID: String)],
                    eraseCount: Int, previousLayoutID: String) -> String? {
        guard !isConverting, !steps.isEmpty, eraseCount > 0 else { return nil }
        isConverting = true
        cycleHome = home
        cycleSteps = steps
        cycleIndex = 0
        cycleShownCount = steps[0].text.count
        cyclePreviousLayoutID = previousLayoutID
        lastWasBuffer = true
        rslog("cycle begin: \(steps.count) step(s), erase \(eraseCount) → \(steps[0].layoutID)")
        retype(erase: eraseCount, insert: steps[0].text)
        return steps[0].layoutID
    }

    /// Next step of the cycle (second+ trigger with no input between them). Cycles through candidates,
    /// wrapping back to the original text. Returns the target layout and the
    /// `restored` flag (true — returned to the original text → switch to previousLayoutID).
    /// nil — if there's no active buffer conversion (then the caller tries the clipboard).
    func cycleStep() -> (layoutID: String, restored: Bool)? {
        guard !isConverting, lastWasBuffer, !cycleSteps.isEmpty else { return nil }
        isConverting = true
        let next = cycleIndex + 1
        if next < cycleSteps.count {
            let step = cycleSteps[next]
            rslog("cycle step \(next) → \(step.layoutID)")
            retype(erase: cycleShownCount, insert: step.text)
            cycleIndex = next
            cycleShownCount = step.text.count
            return (step.layoutID, false)
        } else {
            rslog("cycle restore → \(cyclePreviousLayoutID)")
            retype(erase: cycleShownCount, insert: cycleHome)
            cycleIndex = -1
            cycleShownCount = cycleHome.count
            return (cyclePreviousLayoutID, true)
        }
    }

    /// Re-conversion of the selection via the clipboard. The buffer (word-by-word) path goes
    /// through `cycleStep`; only mouse-selected text reaches here (clipboard engine).
    func reconvert() -> Bool {
        guard !isConverting, !lastWasBuffer else { return false }
        return reconvertViaClipboard()
    }

    /// Erase `erase` characters and type `insert` — off the main thread, so usleep doesn't
    /// starve the event tap (which sits on the main run loop).
    private func retype(erase: Int, insert: String) {
        injectQueue.async { [weak self] in
            guard let self else { return }
            self.backspace(erase)
            usleep(20_000)
            self.insertText(insert)
            Task { @MainActor in self.isConverting = false }
        }
    }

    /// Conversion via the clipboard (fallback: mouse-selected text etc.).
    /// First checks the selection, then tries the word by counter.
    func convertViaClipboard(wordLength: Int, prevWordLength: Int, boundaryCount: Int) -> Bool {
        guard !isConverting else {
            rslog("convert: skipped — already converting")
            return false
        }
        isConverting = true
        lastWasBuffer = false
        defer { isConverting = false }

        if !isFocusedElementEditable() {
            rslog("convert: element may not be editable, trying anyway")
        }
        let pasteboard = NSPasteboard.general
        cancelClipboardRestore()
        savedClipboardItems = snapshotPasteboard(pasteboard)

        var conversionSucceeded = false
        defer {
            // Any early exit without success must return the clipboard to the user —
            // otherwise the clipboard stays empty or holds the converted text.
            if !conversionSucceeded { restoreClipboardNow() }
        }

        // --- Attempt 1: is there already selected text? ---
        if let text = tryCopy(pasteboard) {
            rslog("convert: selection len=\(text.count)")
            let converted = DynamicKeyMapping.convert(text).precomposedStringWithCanonicalMapping
            pasteText(converted, pasteboard: pasteboard)
            // The cursor stays at the end of the inserted text — don't re-select,
            // so the next input doesn't overwrite the result. For reconvert the
            // unified path via selectBack(lastConvertedCount) is used.
            lastConvertedCount = converted.count
            lastBoundaryCount = 0
            conversionSucceeded = true
            scheduleClipboardRestore()
            return true
        }

        // --- Attempt 2: select the word by counter ---
        let charCount: Int
        let usedBoundary: Int

        if wordLength > 0 {
            charCount = wordLength
            usedBoundary = 0
        } else if prevWordLength > 0 && boundaryCount > 0 {
            moveLeft(boundaryCount)
            charCount = prevWordLength
            usedBoundary = boundaryCount
        } else {
            rslog("convert: nothing to convert (wordLen=\(wordLength) prevLen=\(prevWordLength))")
            return false
        }

        rslog("convert: selecting \(charCount) chars (boundary=\(usedBoundary))")
        selectBack(charCount)
        usleep(50_000)

        guard let text = tryCopy(pasteboard) else {
            rslog("convert: copy failed")
            simKey(keyCode: KC.right, flags: []) // clear the selection
            moveRight(usedBoundary)
            return false
        }

        rslog("convert: word len=\(text.count)")
        let converted = DynamicKeyMapping.convert(text).precomposedStringWithCanonicalMapping
        pasteText(converted, pasteboard: pasteboard)

        moveRight(usedBoundary)

        lastConvertedCount = converted.count
        lastBoundaryCount = usedBoundary
        conversionSucceeded = true
        scheduleClipboardRestore()
        return true
    }

    /// Re-conversion via the clipboard (fallback).
    private func reconvertViaClipboard() -> Bool {
        guard !isConverting else {
            rslog("reconvert: skipped — already converting")
            return false
        }
        isConverting = true
        defer { isConverting = false }

        rslog("reconvert: lastCount=\(lastConvertedCount) boundary=\(lastBoundaryCount)")
        guard lastConvertedCount > 0 else { return false }

        let pasteboard = NSPasteboard.general
        // Cancel the deferred clipboard restore — we're still working
        cancelClipboardRestore()

        moveLeft(lastBoundaryCount)

        selectBack(lastConvertedCount)
        usleep(80_000)  // give the app time to process the selection

        guard let text = tryCopy(pasteboard) else {
            rslog("reconvert: copy failed, count=\(lastConvertedCount)")
            simKey(keyCode: KC.right, flags: [])
            moveRight(lastBoundaryCount)
            scheduleClipboardRestore()
            return false
        }

        rslog("reconvert: len=\(text.count) → converting")
        let converted = DynamicKeyMapping.convert(text).precomposedStringWithCanonicalMapping
        pasteText(converted, pasteboard: pasteboard)

        moveRight(lastBoundaryCount)

        lastConvertedCount = converted.count
        scheduleClipboardRestore()
        return true
    }

    func clearState() {
        lastConvertedCount = 0
        lastBoundaryCount = 0
        cycleHome = ""
        cycleSteps = []
        cycleIndex = -1
        cycleShownCount = 0
        cyclePreviousLayoutID = ""
        lastWasBuffer = false
    }

    // MARK: - Private

    /// Erases n characters (Backspace × n) — for the retype engine.
    nonisolated private func backspace(_ n: Int) {
        for _ in 0..<n {
            simKey(keyCode: KC.backspace, flags: [])
            usleep(3_000)
        }
    }

    /// Types the string directly (unicode insert), without the clipboard.
    nonisolated private func insertText(_ text: String) {
        guard !text.isEmpty, let source = makeSource() else { return }
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Pastes text via Cmd+V and waits for completion
    private func pasteText(_ text: String, pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        simKey(keyCode: KC.letterV, flags: .maskCommand) // Cmd+V
        usleep(150_000) // 150ms — give the app time to paste the text and update the cursor
    }

    /// Cancels the deferred clipboard restore
    private func cancelClipboardRestore() {
        clipboardRestoreWork?.cancel()
        clipboardRestoreWork = nil
    }

    /// Immediately returns the clipboard to the user (for failure paths).
    private func restoreClipboardNow() {
        cancelClipboardRestore()
        guard let saved = savedClipboardItems else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
        savedClipboardItems = nil
    }

    /// Flushes the deferred restore immediately — called before
    /// app termination, so the clipboard isn't lost in the 2-second window.
    func flushPendingClipboardRestore() {
        guard clipboardRestoreWork != nil else { return }
        restoreClipboardNow()
    }

    /// Schedules clipboard restore in 2 seconds
    /// (if a reconvert arrives in that time — it's canceled and rescheduled)
    private func scheduleClipboardRestore() {
        cancelClipboardRestore()
        let saved = self.savedClipboardItems
        let work = DispatchWorkItem { [weak self] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let saved, !saved.isEmpty {
                pasteboard.writeObjects(saved)
            }
            self?.savedClipboardItems = nil
            rslog("clipboard restored (\(saved?.count ?? 0) items)")
        }
        clipboardRestoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Makes a deep copy of all pasteboard items (with all data types).
    /// This is needed because NSPasteboardItem becomes invalid after
    /// pasteboard.clearContents() — so we copy the data for each type
    /// into new NSPasteboardItem objects.
    private func snapshotPasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pb.pasteboardItems else { return [] }
        return items.map { oldItem in
            let newItem = NSPasteboardItem()
            for type in oldItem.types {
                if let data = oldItem.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
    }

    /// Copies the selected text. Makes up to 3 attempts (Cmd+C doesn't always work the first time)
    private func tryCopy(_ pasteboard: NSPasteboard) -> String? {
        for attempt in 0..<3 {
            // Clear the buffer before copying — guarantees changeCount will change
            pasteboard.clearContents()
            let oldCount = pasteboard.changeCount

            simKey(keyCode: KC.letterC, flags: .maskCommand) // Cmd+C
            usleep(attempt == 0 ? 80_000 : 120_000)

            if pasteboard.changeCount != oldCount,
               let text = pasteboard.string(forType: .string),
               !text.isEmpty {
                return text
            }
            usleep(50_000) // pause before retry
        }
        return nil
    }

    /// Selects N characters to the left (Shift+Left × N)
    nonisolated private func selectBack(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.left, flags: .maskShift)
            usleep(3_000)
        }
    }

    /// Moves the cursor left by N characters
    nonisolated private func moveLeft(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.left, flags: [])
            usleep(3_000)
        }
    }

    /// Moves the cursor right by N characters (restoring space boundaries)
    nonisolated private func moveRight(_ count: Int) {
        for _ in 0..<count {
            simKey(keyCode: KC.right, flags: [])
            usleep(3_000)
        }
    }

    /// Simulates a keystroke with a marker (so our monitor ignores it)
    nonisolated private func simKey(keyCode: UInt16, flags: CGEventFlags) {
        guard let source = makeSource() else { return }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
