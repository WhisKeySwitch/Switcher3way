import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyboardMonitor = KeyboardMonitor()
    private let textConverter = TextConverter()
    private let settingsController = SettingsWindowController()
    private let onboardingController = OnboardingWindowController()
    private let helpController = HelpWindowController()
    private let perAppLayoutManager = PerAppLayoutManager()
    private var iconRefreshTimer: Timer?
    private var pauseTimer: Timer?         // auto-resume when the timed pause expires (W4)
    private var lastPermissionsOK: Bool?   // to rebuild the menu when permissions state changes
    private var monitoringActive = false
    private var caretIndicator: CaretIndicator?   // issue #10: caret flag (beta, OFF by default)

    // References to the live labels of the menu status header (updated by icon polling)
    private weak var headerBadgeLabel: NSTextField?
    private weak var headerNameLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupSettingsCallbacks()
        setupOnboardingCallbacks()
        syncLoginItem()
        applyEnabledState()   // arms the timer if the persistent pause hasn't expired yet
        runPermissionWizard()
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

        let alert = NSAlert()
        alert.messageText = L10n.learnQuestion(word)
        alert.addButton(withTitle: L10n.learnAdd)
        alert.addButton(withTitle: L10n.learnNotNow)
        if alert.runModal() == .alertFirstButtonReturn {
            var list = SettingsManager.shared.deniedWords
            list.append(word)
            SettingsManager.shared.deniedWords = list
            rslog("learn: added word (len=\(word.count)) to never-convert")
        }
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
                if !mkeys.isEmpty, let plan = NWayResolver.manualPlan(keys: mkeys, capsLock: mcaps) {
                    let spaces = String(repeating: " ", count: mtrailing)
                    let steps = plan.candidates.map { (text: $0.converted + spaces, layoutID: $0.targetLayoutID) }
                    if let target = self.textConverter.beginCycle(home: plan.original + spaces, steps: steps,
                                                                  eraseCount: mkeys.count + mtrailing,
                                                                  previousLayoutID: plan.originalLayoutID) {
                        self.keyboardMonitor.markConverted()
                        LayoutSwitcher.switchTo(layoutID: target)
                        self.updateStatusIcon()
                        self.lastAutoConverted = nil
                    }
                } else if self.textConverter.convertViaClipboard(wordLength: keys.count,
                                                                 prevWordLength: prevKeys.count,
                                                                 boundaryCount: bc) {
                    // No keystroke buffer (text selected with the mouse) or remote desktop: rendering by layout
                    // is impossible — convert by script via the clipboard and just page through the layout.
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchToNextInstalled()
                    self.updateStatusIcon()
                    self.lastAutoConverted = nil
                }
            },
            onAltReconvert: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.effectivelyEnabled else { return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    LayoutSwitcher.switchToNextInstalled()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // Buffer cycle: next candidate, or a return to the original text AND the exact
                // layout active before conversion (3-way undo fix). Selection — via the clipboard.
                if let step = self.textConverter.cycleStep() {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchTo(layoutID: step.layoutID)
                    self.updateStatusIcon()
                    if step.restored { self.offerExceptionAfterUndo() }
                } else if self.textConverter.reconvert() {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchToNextInstalled()
                    self.updateStatusIcon()
                    self.offerExceptionAfterUndo()
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
        guard !AutoSwitchPolicy.secureInputActive else { rslog("auto: bail secure-input"); return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Remote desktop: do NOT bail immediately — run the detector over our own (clean) buffer, and on
        // "wrong layout" switch OUR layout (the instance on the other side does the conversion).
        let deferToRemote = SettingsManager.shared.remoteDesktopMode && AutoSwitchPolicy.isRemoteDesktopClient(frontID)
        if AutoSwitchPolicy.isDeniedApp(frontID) { rslog("auto: bail denied-app \(frontID ?? "?")"); return }
        if let captured = keyboardMonitor.prevWordBundleID, captured != frontID {
            rslog("auto: bail focus-changed"); return  // focus moved away between the space and now
        }

        let keys = keyboardMonitor.prevWordKeys
        let bc = keyboardMonitor.boundaryCount
        guard !keys.isEmpty else { rslog("auto: bail empty-keys"); return }  // cursor moved away — unsafe
        let capsLock = keys.contains { $0.caps }

        // --- Text forwarded over remote desktop (all symbols are char): N-way is inapplicable,
        // since every layout would yield the same character. We keep the former 2-way path by SCRIPT
        // (RU↔EN), where the direction is decided by KeyMapping.convert, not the office layout. ---
        if keys.allSatisfy({ $0.char != nil }) {
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
        guard let decision = NWayResolver.resolve(keys: keys, capsLock: capsLock) else {
            rslog("auto: keep"); return
        }
        if AutoSwitchPolicy.isDeniedWord(decision.original, decision.converted) {
            rslog("auto: bail denied-word"); return
        }

        if deferToRemote {
            // Remote desktop (controller): the instance on the other side converts the text, here — our own layout.
            LayoutSwitcher.switchTo(layoutID: decision.targetLayoutID)
            updateStatusIcon()
            rslog("auto: local layout switched, conversion handled by controlled instance")
            return
        }

        rslog("auto: convert \(keys.count) keys (+\(bc) sp) → \(decision.targetLayoutID)")
        // Single-step cycle: record the layout BEFORE switching, so ⌥-undo restores
        // exactly it (and not "the opposite of the pair" — the former 3-way undo bug).
        let prevLayout = LayoutSwitcher.currentLayoutID()
        let spaces = String(repeating: " ", count: bc)
        let steps = [(text: decision.converted + spaces, layoutID: decision.targetLayoutID)]
        if let target = textConverter.beginCycle(home: decision.original + spaces, steps: steps,
                                                 eraseCount: keys.count + bc, previousLayoutID: prevLayout) {
            keyboardMonitor.markConverted()
            LayoutSwitcher.switchTo(layoutID: target)
            updateStatusIcon()
            lastAutoConverted = (decision.original, Date())
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

        // "Check for Updates", "Support Development", "Star on GitHub" removed in the Switcher3way fork.
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
        keyboardMonitor.caretFlagEnabled = SettingsManager.shared.caretFlag   // onUserInput dispatch gate
        if SettingsManager.shared.caretFlag, monitoringActive {
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
