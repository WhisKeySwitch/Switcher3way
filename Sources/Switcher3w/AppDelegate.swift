import AppKit
import ApplicationServices
import Switcher3wCore
import UserNotifications

@MainActor
// `UNUserNotificationCenterDelegate` is not annotated for the main actor even though the system
// delivers on it, so the conformance needs @preconcurrency — same treatment AppKit's own delegates
// get. Both callbacks below only hop into main-actor state, which is where they already run.
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let keyboardMonitor = KeyboardMonitor()
    private let textConverter = TextConverter()
    /// A run of consecutive short words that were all held (see `NWayResolver.Outcome.held`) and all
    /// read as the same other language. No single one of them is evidence of anything. Several in a
    /// row are: words only pile up here while nothing in the phrase validates in the layout being
    /// typed in, which is precisely what typing in the wrong layout looks like. Two is enough, and
    /// without this a short message — "як ти?" — would never be fixed at all, because no word in it
    /// is long enough to settle the phrase by itself.
    private var heldLang: String?
    private var heldRun = 0
    /// The language a run of held words settled on, standing in for a phrase lock.
    private var settledLang: String?
    private static let heldRunSettles = 2

    private let phraseTracker = PhraseTracker { keys, layoutID in
        NWay.resolver.render(keys: keys, layoutID: layoutID)
    }

    private func forgetHeldRun() { heldLang = nil; heldRun = 0; settledLang = nil }

    /// Drop the phrase and everything derived from it. The held run is part of the phrase's state,
    /// so the two must never be reset apart.
    private func resetPhrase() { phraseTracker.reset(); forgetHeldRun() }
    private let settingsController = SettingsWindowController()
    private let onboardingController = OnboardingWindowController()
    private let helpController = HelpWindowController()
    private let perAppLayoutManager = PerAppLayoutManager()
    private var iconRefreshTimer: Timer?
    private var pauseTimer: Timer?         // auto-resume when the timed pause expires (W4)
    private var lastPermissionsOK: Bool?   // to rebuild the menu when permissions state changes
    private var monitoringActive = false
    private var caretIndicator: CaretIndicator?   // issue #10: caret flag (beta, OFF by default)
    private var secureFieldFocusObserver: NSObjectProtocol?   // invalidates the password-guard cache

    // References to the live labels of the menu status header (updated by icon polling)
    private weak var headerBadgeLabel: NSTextField?
    private weak var headerNameLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NWay.installLogSink()   // the core logs through rslog; wire it before anything evaluates
        ConversionNotifier.onNeverConvert = { [weak self] word in self?.addNeverConvertWord(word) }
        ConversionNotifier.configure(delegate: self)
        setupStatusItem()
        setupSettingsCallbacks()
        setupOnboardingCallbacks()
        syncLoginItem()
        applyEnabledState()   // arms the timer if the persistent pause hasn't expired yet
        runPermissionWizard()

        // Software updates: menu state follows the checker; first background check ~15 s
        // after launch, then daily (gated on the setting inside startSchedule).
        UpdateChecker.shared.onStateChange = { [weak self] in self?.rebuildMenu() }
        UpdateChecker.shared.startSchedule()
    }

    private func setupSettingsCallbacks() {
        settingsController.onAutoSwitchChanged = { [weak self] _ in
            self?.applyEnabledState()   // icon + menu (Pause/Resume) follow the master toggle
        }
        settingsController.onPerAppLayoutChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.startPerAppLayout()
            } else {
                self.perAppLayoutManager.stop()
            }
        }
        settingsController.onLanguageChanged = { [weak self] in
            self?.rebuildMenu()
        }
        settingsController.onTriggerChanged = { [weak self] in
            self?.reconfigureTap()
        }
        settingsController.onAutoConvertChanged = { [weak self] _ in
            self?.rebuildMenu()  // sync the menu checkmark
        }
        settingsController.onRemoteDesktopChanged = { [weak self] _ in
            self?.reconfigureTap()  // tap level depends on the mode
            self?.rebuildMenu()
        }
        settingsController.onCaretFlagChanged = { [weak self] _ in
            self?.rebuildMenu()          // sync the menu checkmark
            self?.syncCaretIndicator()   // create/tear down the indicator + update the onUserInput gate
        }
    }

    private func setupOnboardingCallbacks() {
        onboardingController.onAllGranted = { [weak self] in
            guard let self else { return }
            SettingsManager.shared.permissionsWereGranted = true
            if !self.monitoringActive { self.startMonitoring() }
            self.rebuildMenu()   // remove "Check Permissions…" from the menu
        }
        onboardingController.onRequestRestart = { [weak self] in
            self?.restartApp()
        }
    }

    // MARK: - Pause / master toggle (W4)

    /// Single point for applying "active/not": master toggle AND pause. We don't tear down
    /// the event tap itself (like the former Enable checkbox) — callbacks are gated by effectivelyEnabled.
    private func applyEnabledState() {
        let settings = SettingsManager.shared

        // Auto-resume timer for the timed pause (survives restart too:
        // pausedUntil is persistent, so we arm it on app start as well).
        pauseTimer?.invalidate()
        pauseTimer = nil
        if let until = settings.pausedUntil, until > Date() {
            pauseTimer = Timer.scheduledTimer(withTimeInterval: until.timeIntervalSinceNow + 0.5,
                                              repeats: false) { [weak self] _ in
                Task { @MainActor in
                    SettingsManager.shared.clearPause()
                    rslog("pause: expired — auto-resume")
                    self?.applyEnabledState()
                }
            }
        }

        settingsController.updateAutoSwitchState(settings.autoSwitchEnabled)
        updateStatusIcon()
        rebuildMenu()
    }

    // MARK: - Learn-from-undo (offer to add the word to never-convert)

    /// Last auto-conversion: word (as typed) + time. If the user
    /// immediately undoes it with the manual trigger — we offer to add the word to the exceptions.
    private var lastAutoConverted: (word: String, at: Date)?
    /// Anti-nag: we ask about a given word once per session.
    private var offeredExceptionWords: Set<String> = []

    private func offerExceptionAfterUndo() {
        guard let last = lastAutoConverted, Date().timeIntervalSince(last.at) < 8 else { return }
        lastAutoConverted = nil
        let word = last.word
        let key = word.lowercased()
        guard !offeredExceptionWords.contains(key) else { return }
        offeredExceptionWords.insert(key)
        guard !SettingsManager.shared.deniedWordsSet.contains(key) else { return }

        // A notification, not a modal alert: this fires in the middle of typing, right after the
        // app already interrupted the user by rewriting their word. A dialog that steals focus
        // there is the worst place in the app for one.
        ConversionNotifier.offerNeverConvert(word: word)
    }

    /// Appends a word to the never-convert list — the notification action's landing point.
    private func addNeverConvertWord(_ word: String) {
        var list = SettingsManager.shared.deniedWords
        guard !list.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        list.append(word)
        SettingsManager.shared.deniedWords = list
        rslog("learn: added word (len=\(word.count)) to never-convert")
        settingsController.reloadExceptions()
    }

    private func startPerAppLayout() {
        perAppLayoutManager.onLayoutRestored = { [weak self] in
            self?.keyboardMonitor.markConverted()
            self?.textConverter.clearState()
            self?.updateStatusIcon()
        }
        perAppLayoutManager.start()
    }

    // MARK: - Login Item Sync

    /// Syncs the launch-at-login state with the system on start.
    /// If the checkbox is on but the Login Item is lost (reinstall/update) — re-registers it.
    /// If the checkbox is off but the Login Item exists — removes it.
    private func syncLoginItem() {
        let settings = SettingsManager.shared
        let wanted = settings.launchAtLogin
        let status = settings.loginItemStatus

        rslog("Login item sync: wanted=\(wanted) status=\(status.rawValue)")

        if wanted && status != .enabled {
            // Checkbox is on but the Login Item is not active — re-register
            rslog("Re-registering login item...")
            settings.launchAtLogin = true  // setter will call doUpdateLoginItem
        } else if !wanted && status == .enabled {
            // Checkbox is off but the Login Item is active — remove it
            rslog("Unregistering stale login item...")
            settings.launchAtLogin = false
        }
    }

    // MARK: - Permission Wizard

    /// Onboarding checklist (W3) instead of a chain of modal alerts: one window with a live
    /// status of both permissions; closing loses nothing.
    private func runPermissionWizard(interactive: Bool = false) {
        let acc = AXIsProcessTrusted()
        let inp = CGPreflightListenEventAccess()
        rslog("Permissions: accessibility=\(acc) inputMonitoring=\(inp)")

        if acc && inp {
            // Remember that permissions were granted
            SettingsManager.shared.permissionsWereGranted = true
            if !monitoringActive { startMonitoring() }
            // A manual check from the menu should give a visible response: window in the "all granted" state.
            if interactive { onboardingController.show() }
            return
        }

        // Permissions were granted before but are now reset (update): clean the TCC entries
        // and show the checklist with a reset note.
        if SettingsManager.shared.permissionsWereGranted {
            rslog("Permissions were previously granted — reset detected after update")
            SettingsManager.shared.permissionsWereGranted = false
            resetPermissions()
            onboardingController.show(resetNotice: true)
            return
        }

        // First launch — onboarding checklist
        onboardingController.show()
    }

    /// Resets old permission entries for our bundle ID
    private func resetPermissions() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.switcher3way.app"
        rslog("Resetting TCC entries for \(bundleID)")

        for service in ["Accessibility", "ListenEvent"] {
            let reset = Process()
            reset.launchPath = "/usr/bin/tccutil"
            reset.arguments = ["reset", service, bundleID]
            try? reset.run()
            reset.waitUntilExit()
        }

        rslog("TCC entries reset done")
    }

    private func restartApp() {
        rslog("Restarting from: \(Bundle.main.bundlePath)")
        AppRelauncher.relaunch()
    }

    // MARK: - Start Monitoring

    private func startMonitoring() {
        if !keyboardMonitor.start(
            onAltTap: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.effectivelyEnabled else { return }
                // Manual control invalidates the phrase memory (its conversions/undos
                // aren't tracked, so later corrections would erase the wrong segment).
                self.resetPhrase()
                // The trigger is an explicit user action, which is why it converts words auto
                // declines — but that does not make it safe to read a password field through the
                // clipboard fallback, or to retype its contents. Checked before anything reads text.
                guard !SecureFieldDetector.isFocusedPassword else {
                    rslog("trigger: suppressed — password field")
                    return
                }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Remote desktop: the office instance converts the text using the real forwarded characters
                    // (Fix #6). Here we change OUR layout — so further input goes in
                    // the correct layout and we don't have to convert each word.
                    LayoutSwitcher.switchToNextInstalled()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                let keys = self.keyboardMonitor.currentWordKeys
                let prevKeys = self.keyboardMonitor.prevWordKeys
                let bc = self.keyboardMonitor.boundaryCount
                let mkeys = keys.isEmpty ? prevKeys : keys
                let mtrailing = keys.isEmpty ? bc : 0
                let mcaps = mkeys.contains { $0.caps }
                // N-way manual cycle: iterate over every layout that renders the typed text differently.
                // Explicit user action ⇒ convert even when ambiguous; a repeated
                // trigger (RECONVERT) pages through candidates and cycles back to the original.
                if !mkeys.isEmpty, let plan = NWay.resolver.manualPlan(keys: mkeys, capsLock: mcaps,
                                                          ambiguousLang: SettingsManager.shared.ambiguousLang),
                   let firstTarget = plan.candidates.first?.targetLayoutID {
                    let spaces = String(repeating: " ", count: mtrailing)
                    let steps = plan.candidates.map { (text: $0.converted + spaces, layoutID: $0.targetLayoutID) }
                    // Bookkeeping only if the injection wasn't aborted by concurrent typing.
                    _ = self.textConverter.beginCycle(home: plan.original + spaces, steps: steps,
                                                      eraseCount: mkeys.count + mtrailing,
                                                      previousLayoutID: plan.originalLayoutID) { [weak self] success in
                        guard let self, success else { return }
                        self.keyboardMonitor.markConverted()
                        LayoutSwitcher.switchTo(layoutID: firstTarget)
                        self.updateStatusIcon()
                        self.lastAutoConverted = nil
                        if let first = plan.candidates.first {
                            self.caretIndicator?.conversionApplied(original: plan.original,
                                                                   converted: first.converted)
                        }
                    }
                } else if let target = self.textConverter.convertViaClipboard(wordLength: keys.count,
                                                                              prevWordLength: prevKeys.count,
                                                                              boundaryCount: bc) {
                    // No keystroke buffer (text selected with the mouse): rendering by keycode is
                    // impossible, so the clipboard path maps the selection into each layout and
                    // switches to the chosen candidate (N-way, dictionary winner first).
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchTo(layoutID: target)
                    self.updateStatusIcon()
                    self.lastAutoConverted = nil
                } else if !mkeys.isEmpty {
                    // There WAS something to convert and neither path could apply it — a window
                    // that rejects synthetic input, a non-editable focus. Until now this was a
                    // silent no-op that reads exactly like the app being broken.
                    rslog("trigger: nothing could be applied")
                    ConversionNotifier.reportRewriteFailure()
                }
            },
            onAltReconvert: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.effectivelyEnabled else { return }
                self.resetPhrase()   // manual control — see onAltTap
                guard !SecureFieldDetector.isFocusedPassword else {
                    rslog("trigger: suppressed — password field")
                    return
                }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    LayoutSwitcher.switchToNextInstalled()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // Buffer cycle: next candidate, or a return to the original text AND the exact
                // layout active before conversion (3-way undo fix). Selection — via the clipboard.
                // The layout switch runs in the completion — only if the retype wasn't aborted
                // by concurrent typing.
                let cycled = self.textConverter.cycleStep { [weak self] layoutID, restored in
                    guard let self else { return }
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchTo(layoutID: layoutID)
                    self.updateStatusIcon()
                    if restored {
                        self.offerExceptionAfterUndo()   // no chip: this step UNDOES a conversion
                    } else if let step = self.textConverter.currentCycleText {
                        self.caretIndicator?.conversionApplied(original: step.home,
                                                               converted: step.shown)
                    }
                }
                if cycled {
                    // Scheduled (or aborted inside) — never fall through to the clipboard path.
                } else if let step = self.textConverter.reconvert() {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchTo(layoutID: step.layoutID)
                    self.updateStatusIcon()
                    if step.restored { self.offerExceptionAfterUndo() }
                }
            }
        ) {
            rslog("Event tap failed - will retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startMonitoring()
            }
            return
        }

        monitoringActive = true
        keyboardMonitor.onWordBoundary = { [weak self] in
            self?.handleAutoConvert()
        }
        // Synchronous abort signal for the retype engine: any real keydown/click while an
        // injection is in flight stops it before it can erase the user's fresh characters.
        keyboardMonitor.onRealUserEvent = { [textConverter] in textConverter.noteRealUserEvent() }
        // Phrase memory (phrase-aware-ambiguity): resets with the word buffer, tracks multi-space
        // runs. Async main hop like onWordBoundary — order among these dispatches follows event
        // order; races against retype completions are caught by the tracker's generation guard.
        keyboardMonitor.onPhraseReset = { [weak self] in
            DispatchQueue.main.async {
                self?.resetPhrase()
                // Same events that reset the word buffer (Enter/Tab/arrows/click/Esc) are the ones
                // that move focus between fields — a tab from a username box to the password beside
                // it must never be answered from the cache.
                SecureFieldDetector.invalidate()
            }
        }
        // App switches likewise change what has focus.
        secureFieldFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SecureFieldDetector.invalidate() }
        }
        keyboardMonitor.onExtraSpace = { [weak self] in
            DispatchQueue.main.async { self?.phraseTracker.noteExtraSpace() }
        }
        keyboardMonitor.onUserInput = { [weak self] in self?.caretIndicator?.userTyped() }  // issue #10
        updateStatusIcon()        // first set the menu bar flag while the indicator isn't there yet
        syncCaretIndicator()      // then create the indicator — without a false startup "pop"
        // Safety net for issue #9: the system notification about a layout change is unreliable
        // (especially over remote desktop — on that machine it often doesn't arrive), so
        // the flag "gets stuck". A constant light poll keeps the icon in sync with the system.
        // The same poll watches the permissions state (W4: menu item — only when broken).
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusIcon()
                self?.watchPermissions()
            }
        }
        rslog("Monitoring started successfully")

        if SettingsManager.shared.perAppLayout {
            startPerAppLayout()
        }

        // Offer auto-fix on first launch (once). Launch-at-login is now
        // offered by a switch in the onboarding window (W3), there's no separate alert anymore.
        offerAutoConvertIfNeeded()
    }

    /// Rebuilds the menu when permissions state changes (loss/return) — so that
    /// "Check Permissions…" appears only when it's really broken.
    private func watchPermissions() {
        let ok = AXIsProcessTrusted() && CGPreflightListenEventAccess()
        if ok != lastPermissionsOK {
            lastPermissionsOK = ok
            rebuildMenu()
        }
    }

    /// Auto-conversion at the word boundary: detect the wrong layout → convert + switch.
    /// Precision-first: on any uncertainty we do nothing. We don't touch the manual trigger.
    private func handleAutoConvert() {
        rslog("auto: fired")
        guard SettingsManager.shared.effectivelyEnabled else { rslog("auto: bail master-off"); return }
        guard SettingsManager.shared.autoConvert else { rslog("auto: bail flag-off"); return }
        // Contexts where words go unevaluated make the phrase memory incomplete —
        // reset it so a later correction can't be computed over a gap.
        //
        // The guard verdict is logged on EVERY word, not only when it fires: "no suppression" and
        // "guard broken" are otherwise the same log, which is how the equivalent Windows guard went
        // four releases without firing once.
        let secure = SecureFieldDetector.verdict()
        rslog("  secure: \(secure.describe)")
        guard !secure.isPassword else {
            resetPhrase()
            rslog("auto: bail — password field")
            return
        }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Remote desktop: do NOT bail immediately — run the detector over our own (clean) buffer, and on
        // "wrong layout" switch OUR layout (the instance on the other side does the conversion).
        let deferToRemote = SettingsManager.shared.remoteDesktopMode && AutoSwitchPolicy.isRemoteDesktopClient(frontID)
        if AutoSwitchPolicy.isDeniedApp(frontID) { resetPhrase(); rslog("auto: bail denied-app \(frontID ?? "?")"); return }
        if let captured = keyboardMonitor.prevWordBundleID, captured != frontID {
            resetPhrase()
            rslog("auto: bail focus-changed"); return  // focus moved away between the space and now
        }

        let keys = keyboardMonitor.prevWordKeys
        let bc = keyboardMonitor.boundaryCount
        guard !keys.isEmpty else { resetPhrase(); rslog("auto: bail empty-keys"); return }  // cursor moved away — unsafe
        let capsLock = keys.contains { $0.caps }

        // --- Text forwarded over remote desktop (all symbols are char): N-way is inapplicable,
        // since every layout would yield the same character. We keep the former 2-way path by SCRIPT
        // (RU↔EN), where the direction is decided by KeyMapping.convert, not the office layout. ---
        if keys.allSatisfy({ $0.char != nil }) {
            resetPhrase()   // phrase tracking is local-input only
            guard let pair = DynamicKeyMapping.convertKeys(keys) else { rslog("auto: bail convertKeys-nil"); return }
            if AutoSwitchPolicy.isDeniedWord(pair.original, pair.converted) { rslog("auto: bail denied-word"); return }
            let typedIsCyrillic = pair.original.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            let verdict = LayoutDetector.decide(typed: pair.original, converted: pair.converted,
                                                currentLang: typedIsCyrillic ? "ru" : "en",
                                                otherLang: typedIsCyrillic ? "en" : "ru",
                                                capsLock: capsLock)
            guard verdict == .switchToConverted else { return }
            // Remote desktop: the instance on the other side does the conversion, here only our own layout.
            LayoutSwitcher.switchToNextInstalled()
            updateStatusIcon()
            rslog("auto: remote — local layout switched")
            return
        }

        // --- Local input: N-way detection across all installed layouts (EN/UK/RU/…). ---
        // Ambiguity (valid in several other languages, the uk/ru shared vocabulary) is resolved
        // by the phrase lock, then the preference setting; "off" keeps the old precision-first keep.
        let gen = phraseTracker.generation
        var decision: NWayResolver.Decision?
        var wordKind = PhraseTracker.WordKind.neutral
        // How an unconverted word is remembered. A word already valid in the layout it was typed in
        // settles what language this phrase is — nothing else the app sees is stronger — and filing
        // it as neutral, as this used to, threw that away and left short words undecidable.
        var keepKind = PhraseTracker.WordKind.neutral
        // The phrase's language goes in, because words too short to decide alone are decided by it.
        switch NWay.resolver.evaluate(keys: keys, capsLock: capsLock,
                                      phraseLang: phraseTracker.lockedLang ?? settledLang) {
        case .keep(let reason):
            forgetHeldRun()
            // Say why. Leaving a word alone is this app's most common decision and its least visible
            // one: nothing moves on screen either way, so without the reason a guard that is working
            // and a guard that never ran leave identical evidence.
            rslog("auto: keep — \(Self.explain(reason))")
            if reason == .validInCurrent, let lang = currentLanguageCode() {
                keepKind = .locked(lang: lang)
            }
        case .held(let original, let winners):
            // Reads as another language, but it is two or three letters long, so that reading is
            // worth very little. Leave the screen alone and remember the keystrokes as defaulted to
            // the current language: if a later word settles the phrase the other way, the correction
            // machinery converts this word along with it, and if none does, nothing was disturbed.
            handleHeldWord(keys: keys, original: original, winners: winners, spacesAfter: bc, gen: gen)
            return
        case .convert(let d):
            forgetHeldRun()
            decision = d
            wordKind = .locked(lang: d.lang)
        case .ambiguous(let original, let winners):
            forgetHeldRun()
            let pref = phraseTracker.lockedLang ?? SettingsManager.shared.ambiguousLang
            if pref != "off", let w = winners.first(where: { $0.lang == pref }) {
                decision = NWayResolver.Decision(targetLayoutID: w.layoutID, lang: w.lang,
                                                 original: original, converted: w.converted)
                wordKind = .defaulted(lang: w.lang)
                rslog("auto: ambiguous → \(w.lang) (\(phraseTracker.lockedLang != nil ? "phrase lock" : "preference"))")
            } else {
                // Valid in several languages with nothing to choose between them. Left alone, and
                // said out loud: this is a decision like any other, and an unlogged decision is
                // indistinguishable from the detection never having run.
                rslog("auto: keep — valid in \(winners.map(\.lang).sorted().joined(separator: "/")),"
                      + " nothing to choose between them")
            }
        }

        // Remembers an unconverted word so phrase corrections can reproduce the segment verbatim.
        func recordAsNeutral() {
            if let shown = NWay.resolver.renderCurrent(keys: keys) {
                phraseTracker.record(keys: keys, shownText: shown, spacesAfter: bc, kind: keepKind)
            } else {
                resetPhrase()   // can't account for the on-screen text exactly
            }
        }

        guard let decision else {
            recordAsNeutral()
            return
        }
        if AutoSwitchPolicy.isDeniedWord(decision.original, decision.converted) {
            recordAsNeutral()
            rslog("auto: bail denied-word")
            return
        }

        if deferToRemote {
            // Remote desktop (controller): the instance on the other side converts the text, here — our own layout.
            resetPhrase()   // phrase tracking is local-input only
            LayoutSwitcher.switchTo(layoutID: decision.targetLayoutID)
            updateStatusIcon()
            rslog("auto: local layout switched, conversion handled by controlled instance")
            return
        }

        // Phrase correction: a word valid in exactly one language re-converts the phrase's
        // earlier ambiguity-defaulted words of OTHER languages together with itself — one
        // replacement, one layout switch, one ⌥-undo for the whole segment.
        var correction: PhraseTracker.Correction?
        if case .locked(let lang) = wordKind {
            correction = phraseTracker.correction(toLang: lang, layoutID: decision.targetLayoutID)
        }

        // Single-step cycle: record the layout BEFORE switching, so ⌥-undo restores
        // exactly it (and not "the opposite of the pair" — the former 3-way undo bug).
        let prevLayout = LayoutSwitcher.currentLayoutID()
        let spaces = String(repeating: " ", count: bc)
        let home: String
        let insert: String
        if let correction {
            home = correction.oldSegment + decision.original + spaces
            insert = correction.newSegment + decision.converted + spaces
            rslog("auto: convert \(keys.count) keys (+\(bc) sp) → \(decision.targetLayoutID)"
                  + " + phrase correction (\(correction.correctedWords.count) word(s), erase \(home.count))")
        } else {
            home = decision.original + spaces
            insert = decision.converted + spaces
            rslog("auto: convert \(keys.count) keys (+\(bc) sp) → \(decision.targetLayoutID)")
        }

        // The cycle continues through the REMAINING layouts, not just back to the original.
        // Seeding one step meant that after an auto-fix the trigger could only toggle between the
        // converted text and what you typed: for "dblyj" → "видно" (uk), Russian was unreachable,
        // even though uk and ru are both real candidates. A phrase correction keeps the single
        // step — its `home` is a whole segment, and the other layouts' renderings of that segment
        // are not what these candidates describe.
        var steps = [(text: insert, layoutID: decision.targetLayoutID)]
        if correction == nil,
           let plan = NWay.resolver.manualPlan(keys: keys, capsLock: capsLock,
                                               ambiguousLang: SettingsManager.shared.ambiguousLang) {
            steps += plan.candidates
                .filter { $0.targetLayoutID != decision.targetLayoutID }
                .map { (text: $0.converted + spaces, layoutID: $0.targetLayoutID) }
            rslog("auto: cycle seeded with \(steps.count) step(s): " +
                  steps.map { $0.layoutID.components(separatedBy: ".").last ?? "?" }.joined(separator: "→"))
        }
        let kind = wordKind
        // Layout switch + bookkeeping only after the replacement really happened: if the user
        // kept typing, the injection aborts and both the text and the layout must stay theirs.
        _ = textConverter.beginCycle(home: home, steps: steps,
                                     eraseCount: home.count, previousLayoutID: prevLayout) { [weak self] success in
            guard let self else { return }
            guard success else {
                // Aborted mid-injection: the erased tail was put back, but a keystroke may have
                // interleaved — the exact on-screen segment is no longer certain. Precision-first.
                self.resetPhrase()
                return
            }
            self.keyboardMonitor.markConverted()
            LayoutSwitcher.switchTo(layoutID: decision.targetLayoutID)
            self.updateStatusIcon()
            self.lastAutoConverted = (decision.original, Date())
            // Show what changed. Without this a successful fix is invisible: the text simply
            // becomes different under the user, with no hint that the app did it or how to undo.
            self.caretIndicator?.conversionApplied(original: decision.original,
                                                   converted: decision.converted)
            if let correction { self.phraseTracker.confirm(correction, ifGeneration: gen) }
            self.phraseTracker.record(keys: keys, shownText: decision.converted,
                                      spacesAfter: bc, kind: kind, ifGeneration: gen)
        }
    }

    /// Plain-language reason for a word being left alone, for the debug log.
    private static func explain(_ reason: NWayResolver.KeepReason) -> String {
        switch reason {
        case .validInCurrent:    return "already a word in this layout's language"
        case .notAWordAnywhere:  return "not a word in any installed language"
        case .noCurrentLanguage: return "current layout has no usable language"
        case .looksLikeATypo:    return "reads as another language, but this one has a word one key "
                                      + "away — treating it as a typo"
        case .phraseDisagrees:   return "too short to decide, and the phrase reads as another language"
        }
    }

    /// The 2-letter language of the layout being typed in, or nil if it cannot be determined.
    private func currentLanguageCode() -> String? {
        let id = LayoutSwitcher.currentLayoutID()
        return SystemLayoutCatalog().installedLayouts().first { $0.id == id }
            .map { String($0.lang.prefix(2)) }
    }

    /// A word too short to decide on its own. Record it unconverted but retro-correctable, then count
    /// the run: enough short words agreeing on the same language is evidence in a way that no single
    /// one of them is, and it is the only thing that can rescue a message where every word is short.
    private func handleHeldWord(keys: [TypedKey], original: String,
                                winners: [NWayResolver.Winner], spacesAfter: Int, gen: Int) {
        guard let currentLang = currentLanguageCode() else { resetPhrase(); return }
        rslog("auto: held — \(original) reads as "
              + winners.map { "\($0.converted) [\($0.lang)]" }.joined(separator: "/")
              + " — too short to act on, waiting for the phrase")
        phraseTracker.record(keys: keys, shownText: original, spacesAfter: spacesAfter,
                             kind: .defaulted(lang: currentLang), ifGeneration: gen)

        // Only an unambiguous reading counts: a word that could be two languages says nothing about
        // which one this phrase is in.
        let only = winners.count == 1 ? winners[0] : nil
        if let only, only.lang == heldLang {
            heldRun += 1
        } else {
            heldLang = only?.lang
            heldRun = only == nil ? 0 : 1
        }
        guard heldRun >= Self.heldRunSettles, let only else { return }
        settleHeldRun(toLang: only.lang, layoutID: only.layoutID, gen: gen)
    }

    /// Enough held words have agreed on the same language to act on them together: convert the whole
    /// held run in one replacement and treat the phrase as settled, so the words after it convert
    /// directly instead of piling up too.
    private func settleHeldRun(toLang lang: String, layoutID: String, gen: Int) {
        guard let correction = phraseTracker.correction(toLang: lang, layoutID: layoutID) else { return }
        let prevLayout = LayoutSwitcher.currentLayoutID()
        rslog("auto: \(heldRun) short words agree → \(lang), converting the run "
              + "(\(correction.correctedWords.count) word(s), erase \(correction.oldSegment.count))")
        heldLang = nil
        heldRun = 0
        _ = textConverter.beginCycle(home: correction.oldSegment,
                                     steps: [(text: correction.newSegment, layoutID: layoutID)],
                                     eraseCount: correction.oldSegment.count,
                                     previousLayoutID: prevLayout) { [weak self] success in
            guard let self else { return }
            guard success else { self.resetPhrase(); return }
            self.keyboardMonitor.markConverted()
            LayoutSwitcher.switchTo(layoutID: layoutID)
            self.updateStatusIcon()
            self.caretIndicator?.conversionApplied(original: correction.oldSegment.trimmingCharacters(in: .whitespaces),
                                                   converted: correction.newSegment.trimmingCharacters(in: .whitespaces))
            self.phraseTracker.confirm(correction, ifGeneration: gen)
            self.settledLang = lang
        }
    }

    /// Offers to enable auto-fix on first launch (once). The feature is OFF by default,
    /// so without an explicit offer the user won't learn about it.
    private func offerAutoConvertIfNeeded() {
        let settings = SettingsManager.shared
        guard !settings.autoConvertOffered else { return }
        settings.autoConvertOffered = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.onboardAutoConvertTitle
        alert.informativeText = L10n.onboardAutoConvertText
        alert.addButton(withTitle: L10n.wizardYes)
        alert.addButton(withTitle: L10n.wizardNo)

        if alert.runModal() == .alertFirstButtonReturn {
            settings.autoConvert = true
            rebuildMenu()  // sync the "Automatic conversion" checkmark in the menu
            rslog("User enabled auto-convert at onboarding")
        } else {
            rslog("User declined auto-convert at onboarding")
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
        // issue #9: the icon must reflect the layout even on a SYSTEM change (standard/
        // overridden hotkey), not only on our own conversion. We listen for the system
        // distributed notification about an input source change.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemInputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func systemInputSourceChanged() {
        updateStatusIcon()
        keyboardMonitor.soundArmed = true  // issue #7: the next letter will play the layout sound
    }

    /// Builds the status bar menu (W4: status first, toggles grouped).
    /// Called again when the interface language, pause state, and permissions change.
    private func rebuildMenu() {
        let menu = NSMenu()

        // Status header: current layout + trigger hint + version.
        // The version moved here from a separate disabled line.
        let headerItem = NSMenuItem()
        headerItem.view = makeMenuHeaderView()
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // "Quick toggles" — without "(beta)": badges stay in the settings.
        if #available(macOS 14.0, *) {
            menu.addItem(NSMenuItem.sectionHeader(title: L10n.menuQuickToggles))
        } else {
            let header = NSMenuItem(title: L10n.menuQuickToggles, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }

        let autoConvertItem = NSMenuItem(title: L10n.menuAutofix, action: #selector(toggleAutoConvert), keyEquivalent: "")
        autoConvertItem.target = self
        autoConvertItem.state = SettingsManager.shared.autoConvert ? .on : .off
        menu.addItem(autoConvertItem)

        let keySoundItem = NSMenuItem(title: L10n.menuSound, action: #selector(toggleKeySound), keyEquivalent: "")
        keySoundItem.target = self
        keySoundItem.state = SettingsManager.shared.keySound ? .on : .off
        menu.addItem(keySoundItem)

        let caretFlagItem = NSMenuItem(title: L10n.menuFlag, action: #selector(toggleCaretFlag), keyEquivalent: "")
        caretFlagItem.target = self
        caretFlagItem.state = SettingsManager.shared.caretFlag ? .on : .off
        menu.addItem(caretFlagItem)

        // Remote desktop mode is deferred to 2.5 — the toggle is hidden behind a flag (for testing).
        if SettingsManager.shared.showRemoteDesktopBeta {
            let remoteDesktopItem = NSMenuItem(title: L10n.menuRemoteDesktop, action: #selector(toggleRemoteDesktop), keyEquivalent: "")
            remoteDesktopItem.target = self
            remoteDesktopItem.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
            menu.addItem(remoteDesktopItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Pause with durations instead of the "Enable" checkbox (W4): a disabled
        // switcher shouldn't look enabled — the icon shows the pause.
        if SettingsManager.shared.effectivelyEnabled {
            let pauseItem = NSMenuItem(title: L10n.menuPause, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let p30 = NSMenuItem(title: L10n.menuPause30m, action: #selector(pause30m), keyEquivalent: "")
            p30.target = self
            sub.addItem(p30)
            let p1h = NSMenuItem(title: L10n.menuPause1h, action: #selector(pause1h), keyEquivalent: "")
            p1h.target = self
            sub.addItem(p1h)
            let pRestart = NSMenuItem(title: L10n.menuPauseUntilRestart, action: #selector(pauseUntilRestartTapped), keyEquivalent: "")
            pRestart.target = self
            sub.addItem(pRestart)
            pauseItem.submenu = sub
            menu.addItem(pauseItem)
        } else {
            let resumeItem = NSMenuItem(title: L10n.menuResume, action: #selector(resumeTapped), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        }

        // "Check Permissions…" — only when permissions are broken (W4);
        // in a healthy state the item isn't needed in the everyday menu.
        if !(AXIsProcessTrusted() && CGPreflightListenEventAccess()) {
            let permItem = NSMenuItem(title: L10n.menuCheckPermissions, action: #selector(recheckPermissions), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let settingsItem = NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Help: built-in guide (⌘? — the standard macOS help shortcut)
        let helpItem = NSMenuItem(title: L10n.menuHelp, action: #selector(openHelp), keyEquivalent: "?")
        helpItem.target = self
        menu.addItem(helpItem)

        // Updates: the fork's own updater (source = WhisKeySwitch/switcher3way-releases).
        // Disabled with a busy title while a check or install is in progress.
        let checker = UpdateChecker.shared
        let updatesTitle = checker.isInstalling ? L10n.menuInstallingUpdate
                         : checker.isBusy ? L10n.menuCheckingUpdates
                         : L10n.menuCheckUpdates
        let updatesItem = NSMenuItem(title: updatesTitle,
                                     action: checker.isBusy ? nil : #selector(checkForUpdatesTapped),
                                     keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        // "Support Development", "Star on GitHub" removed in the Switcher3way fork.
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        rslog("Menu (re)built with \(menu.items.count) items")
    }

    /// Menu status header (W4): badge with the language code, layout name,
    /// line "trigger converts the last word · version".
    private func makeMenuHeaderView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 48))

        let badge = NSView(frame: NSRect(x: 14, y: 10, width: 28, height: 28))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.borderWidth = 1.5
        badge.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        let badgeLabel = NSTextField(labelWithString: currentLayoutBadge())
        badgeLabel.font = .boldSystemFont(ofSize: 11)
        badgeLabel.alignment = .center
        badgeLabel.frame = NSRect(x: 0, y: 7, width: 28, height: 14)
        badge.addSubview(badgeLabel)
        container.addSubview(badge)
        headerBadgeLabel = badgeLabel

        let nameLabel = NSTextField(labelWithString: LayoutSwitcher.currentLayoutName())
        nameLabel.font = .boldSystemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 52, y: 25, width: 196, height: 17)
        container.addSubview(nameLabel)
        headerNameLabel = nameLabel

        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let devTag = Bundle.main.infoDictionary?["RSDevTag"] as? String ?? ""
        let hintLabel = NSTextField(labelWithString: "\(L10n.menuHeaderHint(triggerSymbol())) · v\(ver)\(devTag)")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.frame = NSRect(x: 52, y: 8, width: 196, height: 14)
        container.addSubview(hintLabel)

        return container
    }

    /// Two-letter language code of the current layout for the header badge (W4: "EN" chip).
    private func currentLayoutBadge() -> String {
        guard let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty else {
            return "?"
        }
        return String(lang.prefix(2)).uppercased()
    }

    /// Trigger key symbol for the hint in the menu header.
    private func triggerSymbol() -> String {
        switch SettingsManager.shared.triggerKey {
        case "command": return "⌘"
        case "control": return "⌃"
        case "shift": return "⇧"
        case "command+shift": return "⌘⇧"
        case "control+shift": return "⌃⇧"
        case "command+option": return "⌘⌥"
        case "control+option": return "⌃⌥"
        default: return "⌥"
        }
    }

    func updateStatusIcon() {
        let flag = flagForCurrentLayout()
        // W4: while paused (or with the master toggle off) the icon is clearly different —
        // a disabled switcher shouldn't look enabled.
        let title = SettingsManager.shared.effectivelyEnabled ? flag : "⏸" + flag
        // We poke the caret ONLY on a real layout flag change: updateStatusIcon
        // is also called by the 2-second safety poll, otherwise the caret flag would pop
        // up every 2s (and a pause change is not a layout change).
        let changed = lastFlagShown != flag
        lastFlagShown = flag
        statusItem.button?.title = title
        if changed { caretIndicator?.layoutChanged() }
        // Live menu header: the layout may have changed since the last menu rebuild.
        headerBadgeLabel?.stringValue = currentLayoutBadge()
        headerNameLabel?.stringValue = LayoutSwitcher.currentLayoutName()
    }

    private var lastFlagShown = ""

    /// Flag of the current layout by language code (BCP-47), not by a substring in the ID — otherwise
    /// "Belarusian" falsely matched "ru", and any non-RU/EN pair was shown as 🇺🇸.
    func flagForCurrentLayout() -> String {
        guard let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty else {
            // Layout language unavailable — soft fallback by ID.
            let id = LayoutSwitcher.currentLayoutID().lowercased()
            return (id.contains("russian") || id.hasSuffix(".ru")) ? "🇷🇺" : "🇺🇸"
        }
        let code = String(lang.prefix(2))
        let flags: [String: String] = [
            "ru": "🇷🇺", "en": "🇺🇸", "uk": "🇺🇦", "be": "🇧🇾",
            "de": "🇩🇪", "fr": "🇫🇷", "es": "🇪🇸", "it": "🇮🇹",
            "pt": "🇵🇹", "pl": "🇵🇱", "ja": "🇯🇵", "zh": "🇨🇳", "ko": "🇰🇷",
        ]
        return flags[code] ?? code.uppercased()
    }

    /// issue #10: creates/releases the caret indicator per the settings flag. Created lazily,
    /// only when the feature is on AND monitoring is running (permissions required).
    private func syncCaretIndicator() {
        // The panel is shared by two surfaces with separate settings: the beta flag badge (off by
        // default) and the conversion chip (on). It must exist when EITHER is enabled.
        let wanted = SettingsManager.shared.caretFlag || SettingsManager.shared.conversionChip
        keyboardMonitor.caretFlagEnabled = wanted   // onUserInput dispatch gate
        if wanted, monitoringActive {
            if caretIndicator == nil {
                let ci = CaretIndicator()
                ci.flagProvider = { [weak self] in self?.flagForCurrentLayout() ?? "" }
                caretIndicator = ci
            }
        } else {
            caretIndicator?.teardown()
            caretIndicator = nil
        }
    }

    // MARK: - Actions

    @objc private func pause30m() {
        SettingsManager.shared.pause(for: 30 * 60)
        rslog("pause: 30m")
        applyEnabledState()
    }

    @objc private func pause1h() {
        SettingsManager.shared.pause(for: 3600)
        rslog("pause: 1h")
        applyEnabledState()
    }

    @objc private func pauseUntilRestartTapped() {
        SettingsManager.shared.pause(for: nil)
        rslog("pause: until restart")
        applyEnabledState()
    }

    /// Resume clears both the pause and the disabled master toggle — "turn it back on" in one item.
    @objc private func resumeTapped() {
        SettingsManager.shared.clearPause()
        SettingsManager.shared.autoSwitchEnabled = true
        rslog("pause: resumed manually")
        applyEnabledState()
    }

    @objc private func toggleAutoConvert(_ sender: NSMenuItem) {
        SettingsManager.shared.autoConvert.toggle()
        sender.state = SettingsManager.shared.autoConvert ? .on : .off
    }

    @objc private func toggleKeySound(_ sender: NSMenuItem) {
        SettingsManager.shared.keySound.toggle()
        sender.state = SettingsManager.shared.keySound ? .on : .off
    }

    @objc private func toggleCaretFlag(_ sender: NSMenuItem) {
        SettingsManager.shared.caretFlag.toggle()
        sender.state = SettingsManager.shared.caretFlag ? .on : .off
        settingsController.updateCaretFlagState(SettingsManager.shared.caretFlag)
        syncCaretIndicator()   // create/tear down the indicator and update the onUserInput gate
    }

    @objc private func toggleRemoteDesktop(_ sender: NSMenuItem) {
        SettingsManager.shared.remoteDesktopMode.toggle()
        sender.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
        reconfigureTap()  // event tap level depends on the mode
    }

    /// Recreates the event tap and, if creation failed (e.g. the session tap was denied),
    /// retries — otherwise the toggle is "on" but there's no tap, and the app silently ignores the trigger.
    private func reconfigureTap() {
        guard !keyboardMonitor.reconfigure() else { return }
        rslog("reconfigure failed (tap denied) — retry in 3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.keyboardMonitor.reconfigure() == false { rslog("reconfigure retry failed") }
        }
    }

    @objc private func recheckPermissions() {
        runPermissionWizard(interactive: true)
    }

    @objc private func openSettings() {
        settingsController.showWindow()
    }

    @objc private func openHelp() {
        helpController.show()
    }

    @objc private func checkForUpdatesTapped() {
        UpdateChecker.shared.checkManually()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't lose the clipboard in the 2-second window of deferred restore
        // (relevant on self-update too, which terminates the process).
        textConverter.flushPendingClipboardRestore()
    }

    @objc private func quit() {
        textConverter.flushPendingClipboardRestore()
        perAppLayoutManager.stop()
        keyboardMonitor.stop()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Notification actions

extension AppDelegate {
    /// The "Never convert this" button on the learn-from-undo notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ConversionNotifier.handle(response: response)
        completionHandler()
    }

    /// The app is a menu-bar agent and is always "frontmost" in the notification sense, so without
    /// this its own notifications would never be shown.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
