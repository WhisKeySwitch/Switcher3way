import AppKit
import ApplicationServices
import Carbon
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

    // State of the clipboard/selection cycle (mouse-selected text → paste). Parallel to the
    // buffer cycle above but N-way over ALL installed layouts: the selection is re-rendered into
    // each layout by a character-position map, the dictionary-unambiguous language is offered
    // first, and repeated triggers page through the rest and back to the original.
    private var selHome = ""                                          // original selected text
    private var selSteps: [(text: String, layoutID: String)] = []    // ordered candidates (dictionary winner first)
    private var selIndex = -1                                         // -1 = original shown; 0..n-1 = candidate i
    private var selPrevLayout = ""                                    // layout active BEFORE the first selection conversion

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

    /// Next step of the selection cycle (second+ trigger, no input between). The buffer
    /// (word-by-word) path goes through `cycleStep`; only mouse-selected text reaches here.
    /// Returns the target layout and the `restored` flag (true — wrapped back to the original
    /// text → switch to the pre-conversion layout). nil — no active selection conversion.
    func reconvert() -> (layoutID: String, restored: Bool)? {
        guard !isConverting, !lastWasBuffer, !selSteps.isEmpty else { return nil }
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

    /// Conversion via the clipboard (fallback: mouse-selected text etc.). First checks the
    /// selection, then tries the word by counter. Builds the N-way candidate cycle (see
    /// `buildSelectionSteps`) and applies the first candidate. Returns the target layout ID to
    /// switch to, or nil if there was nothing to convert.
    func convertViaClipboard(wordLength: Int, prevWordLength: Int, boundaryCount: Int) -> String? {
        guard !isConverting else {
            rslog("convert: skipped — already converting")
            return nil
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
            guard let target = beginSelectionCycle(original: text, boundary: 0, pasteboard: pasteboard) else {
                rslog("convert: no candidate layouts for selection")
                return nil
            }
            conversionSucceeded = true
            return target
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
            return nil
        }

        rslog("convert: selecting \(charCount) chars (boundary=\(usedBoundary))")
        selectBack(charCount)
        usleep(50_000)

        guard let text = tryCopy(pasteboard) else {
            rslog("convert: copy failed")
            simKey(keyCode: KC.right, flags: []) // clear the selection
            moveRight(usedBoundary)
            return nil
        }

        rslog("convert: word len=\(text.count)")
        guard let target = beginSelectionCycle(original: text, boundary: usedBoundary, pasteboard: pasteboard) else {
            simKey(keyCode: KC.right, flags: [])
            moveRight(usedBoundary)
            return nil
        }
        moveRight(usedBoundary)
        conversionSucceeded = true
        return target
    }

    /// Builds the N-way candidate cycle for `original`, applies the first candidate, and records
    /// the cycle state. Returns the first candidate's layout ID, or nil if there are none.
    private func beginSelectionCycle(original: String, boundary: Int, pasteboard: NSPasteboard) -> String? {
        let steps = buildSelectionSteps(original: original)
        guard let first = steps.first else { return nil }

        pasteText(first.text, pasteboard: pasteboard)

        selHome = original
        selSteps = steps
        selIndex = 0
        selPrevLayout = LayoutSwitcher.currentLayoutID()
        lastConvertedCount = first.text.count
        lastBoundaryCount = boundary
        scheduleClipboardRestore()
        rslog("selection cycle: \(steps.count) candidate(s), → \(first.layoutID.components(separatedBy: ".").last ?? "?")")
        return first.layoutID
    }

    /// Advances the selection cycle by one candidate via the clipboard, wrapping back to the
    /// original text (and the pre-conversion layout) after the last one.
    private func reconvertViaClipboard() -> (layoutID: String, restored: Bool)? {
        guard !isConverting else {
            rslog("reconvert: skipped — already converting")
            return nil
        }
        isConverting = true
        defer { isConverting = false }

        guard lastConvertedCount > 0, !selSteps.isEmpty else { return nil }

        let pasteboard = NSPasteboard.general
        cancelClipboardRestore()

        // Re-select the currently shown text (its length is known; no typing happened in between,
        // so we don't need to re-copy — we page through our stored candidates).
        moveLeft(lastBoundaryCount)
        selectBack(lastConvertedCount)
        usleep(80_000)

        let next = selIndex + 1
        let insert: String
        let resultLayout: String
        let restored: Bool
        if next < selSteps.count {
            insert = selSteps[next].text
            resultLayout = selSteps[next].layoutID
            restored = false
            selIndex = next
        } else {
            insert = selHome
            resultLayout = selPrevLayout
            restored = true
            selIndex = -1
        }

        pasteText(insert, pasteboard: pasteboard)
        moveRight(lastBoundaryCount)
        lastConvertedCount = insert.count
        scheduleClipboardRestore()
        rslog("reconvert: step \(selIndex) → \(resultLayout.components(separatedBy: ".").last ?? "?") restored=\(restored)")
        return (resultLayout, restored)
    }

    /// Ordered N-way candidates for a selection: the text mapped character-by-character into every
    /// other installed layout (via `DynamicKeyMapping.buildMap`), deduplicated, with the single
    /// dictionary-unambiguous language (if any) placed first. This mirrors `NWayResolver.manualPlan`
    /// but operates on already-rendered characters, since a selection gives us text, not keystrokes.
    private func buildSelectionSteps(original: String) -> [(text: String, layoutID: String)] {
        let layouts = LayoutSwitcher.installedLayouts()
        let currentID = LayoutSwitcher.currentLayoutID()
        guard let currentSource = layouts.first(where: { LayoutSwitcher.sourceID($0) == currentID }) else { return [] }

        // The selection is characters, not keystrokes, so we infer the layout that PRODUCED it
        // (the one whose repertoire covers the text) rather than assuming the active layout — auto
        // may have left a different layout active while the leftover words are still in the old one.
        let source = sourceLayout(for: original, among: layouts, current: currentSource)
        let sourceID = LayoutSwitcher.sourceID(source)

        // Start the cycle just after the source layout and wrap, so "next" is predictable.
        let ordered: [TISInputSource]
        if let i = layouts.firstIndex(where: { LayoutSwitcher.sourceID($0) == sourceID }) {
            ordered = Array(layouts[(i + 1)...]) + Array(layouts[...i])
        } else {
            ordered = layouts
        }

        var steps: [(text: String, layoutID: String, lang: String)] = []
        var seen: Set<String> = [original]   // don't offer what's already on screen, nor duplicates
        for layout in ordered {
            let id = LayoutSwitcher.sourceID(layout)
            guard id != sourceID else { continue }
            let map = DynamicKeyMapping.buildMap(from: source, to: layout)
            guard !map.isEmpty else { continue }
            let text = String(original.map { map[$0] ?? $0 }).precomposedStringWithCanonicalMapping
            guard !seen.contains(text) else { continue }
            seen.insert(text)
            let lang = String((LayoutSwitcher.languageCode(layout) ?? "").prefix(2))
            steps.append((text, id, lang))
        }

        // Dictionary-first: for a single-word selection, if exactly one candidate is a real word in
        // its language, move it to the front so one tap gives the "correct" layout (as in auto).
        let core = letterCore(original)
        if !core.isEmpty, !core.contains(where: { $0.isWhitespace }) {
            let validIdxs = steps.indices.filter { i in
                let c = letterCore(steps[i].text)
                return !c.isEmpty && Dict.isAvailable(steps[i].lang)
                    && Dict.isValidWord(c.lowercased(), lang: steps[i].lang)
            }
            if validIdxs.count == 1 {
                let w = steps.remove(at: validIdxs[0])
                steps.insert(w, at: 0)
            }
        }

        return steps.map { (text: $0.text, layoutID: $0.layoutID) }
    }

    /// Picks the layout that most likely produced `text`: the one whose character repertoire covers
    /// the most of the selection's letters. Falls back to the current layout (e.g. for text that is
    /// identical across layouts). This lets the selection cycle work even when auto-switching has
    /// left a different layout active than the one the selected words were typed in.
    private func sourceLayout(for text: String, among layouts: [TISInputSource],
                              current: TISInputSource) -> TISInputSource {
        let letters = Set(text.lowercased().filter { $0.isLetter })
        guard !letters.isEmpty else { return current }

        var best = current
        var bestScore = -1
        for layout in layouts {
            var repertoire: Set<Character> = []
            for kc in UInt16(0)...UInt16(50) {
                guard let c = DynamicKeyMapping.characterForKeycode(kc, layout: layout) else { continue }
                for ch in String(c).lowercased() { repertoire.insert(ch) }
            }
            let score = letters.reduce(0) { $0 + (repertoire.contains($1) ? 1 : 0) }
            if score > bestScore {
                bestScore = score
                best = layout
            }
        }
        return best
    }

    /// The word's letter core: the string with leading/trailing non-letters trimmed.
    private func letterCore(_ s: String) -> String {
        let chars = Array(s)
        var lo = 0, hi = chars.count
        while lo < hi && !chars[lo].isLetter { lo += 1 }
        while hi > lo && !chars[hi - 1].isLetter { hi -= 1 }
        return String(chars[lo..<hi])
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
        selHome = ""
        selSteps = []
        selIndex = -1
        selPrevLayout = ""
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
