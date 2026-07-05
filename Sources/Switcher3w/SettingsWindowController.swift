import AppKit
import Carbon

/// Settings window: toolbar tabs in the System Settings style (W1/W2),
/// grouped forms with switches instead of bare checkboxes.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var statusSwitch: NSSwitch?
    private var statusTitleLabel: NSTextField?
    private var caretFlagSwitch: NSSwitch?
    private var exceptionsPane: ExceptionsPane?

    /// Callback for updating the menu
    var onAutoSwitchChanged: ((Bool) -> Void)?
    var onPerAppLayoutChanged: ((Bool) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onTriggerChanged: (() -> Void)?
    var onAutoConvertChanged: ((Bool) -> Void)?
    var onRemoteDesktopChanged: ((Bool) -> Void)?
    var onCaretFlagChanged: ((Bool) -> Void)?

    private let tabWidth: CGFloat = 500

    func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        // Tab order per W1: General / Auto-fix / Advanced / About.
        tabVC.addTabViewItem(makeTab(title: L10n.settingsTabGeneral, symbol: "gearshape",
                                     view: buildGeneralTab()))
        tabVC.addTabViewItem(makeTab(title: L10n.settingsTabAutofix, symbol: "wand.and.stars",
                                     view: buildAutofixTab()))
        tabVC.addTabViewItem(makeTab(title: L10n.settingsTabAdvanced, symbol: "slider.horizontal.3",
                                     view: buildAdvancedTab()))
        tabVC.addTabViewItem(makeTab(title: L10n.settingsTabAbout, symbol: "info.circle",
                                     view: buildAboutTab()))

        let win = NSWindow(contentViewController: tabVC)
        win.styleMask = [.titled, .closable]
        win.toolbarStyle = .preference
        win.title = L10n.settingsTitle
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        window = win
    }

    /// Tab wrapper: a view controller with an SF Symbol icon and a computed
    /// preferredContentSize (the toolbar style resizes the window to it).
    private func makeTab(title: String, symbol: String, view: NSView) -> NSTabViewItem {
        let vc = NSViewController()
        vc.view = view
        // NSTabViewController in the toolbar style takes the window title from the title
        // of the selected controller — without it the window is called "Untitled".
        vc.title = L10n.settingsTitle
        view.layoutSubtreeIfNeeded()
        vc.preferredContentSize = NSSize(width: tabWidth, height: view.fittingSize.height)
        let item = NSTabViewItem(viewController: vc)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// Tab skeleton: a vertical stack of sections with padding, fixed width.
    private func makeTabRoot(_ sections: [NSView],
                             alignment: NSLayoutConstraint.Attribute = .leading) -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: tabWidth),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            // Pin content to the top: "<=" instead of "=". fittingSize still gives the
            // natural tab height (the minimum where root.bottom >= stack.bottom+18),
            // but when the window is stretched to the tallest tab, the extra height goes DOWN
            // as empty space rather than stretching the boxes and centering lone rows.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
        ])
        for s in sections {
            s.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return root
    }

    /// Update the master switch state from outside (menu / pause)
    func updateAutoSwitchState(_ enabled: Bool) {
        statusSwitch?.state = enabled ? .on : .off
        statusTitleLabel?.stringValue = enabled ? L10n.settingsStatusOn : L10n.settingsStatusOff
    }

    /// Update the "caret flag" switch from outside (when toggled from the menu)
    func updateCaretFlagState(_ enabled: Bool) {
        caretFlagSwitch?.state = enabled ? .on : .off
    }

    // MARK: - General tab (W1)

    private func buildGeneralTab() -> NSView {
        let settings = SettingsManager.shared

        // Status card: master toggle, promoted from a bare checkbox.
        let statusBox = FormBox()
        let sw = FormUI.makeSwitch(isOn: settings.autoSwitchEnabled,
                                   target: self, action: #selector(autoSwitchChanged))
        statusSwitch = sw
        let statusRow = FormUI.row(title: settings.autoSwitchEnabled ? L10n.settingsStatusOn : L10n.settingsStatusOff,
                                   subtitle: L10n.settingsHotkey, titleBold: true, control: sw)
        statusTitleLabel = findTitleLabel(in: statusRow)
        statusBox.addRow(statusRow)

        // "Trigger" section
        let triggerBox = FormBox()
        let triggerPopup = NSPopUpButton()
        populateTriggerPopup(triggerPopup)
        triggerPopup.target = self
        triggerPopup.action = #selector(triggerChanged)
        triggerBox.addRow(FormUI.row(title: L10n.settingsConvertWith, control: triggerPopup))
        triggerBox.addRow(FormUI.row(title: L10n.settingsTriggerRightOnly,
                                     control: FormUI.makeSwitch(isOn: settings.triggerRightOnly,
                                                                target: self, action: #selector(triggerRightOnlyChanged))))
        triggerBox.addRow(FormUI.row(title: L10n.settingsTriggerDoubleTap,
                                     control: FormUI.makeSwitch(isOn: settings.triggerDoubleTap,
                                                                target: self, action: #selector(triggerDoubleTapChanged))))

        // The manual trigger is now fully N-way (cycles candidates over all installed
        // layouts); the fixed Layout 1/2 pair is gone — the corresponding row was removed.

        // "System" section
        let systemBox = FormBox()
        systemBox.addRow(FormUI.row(title: L10n.settingsLaunchAtLogin,
                                    control: FormUI.makeSwitch(isOn: settings.launchAtLogin,
                                                               target: self, action: #selector(launchAtLoginChanged))))
        systemBox.addRow(FormUI.row(title: L10n.settingsPerAppLayout,
                                    control: FormUI.makeSwitch(isOn: settings.perAppLayout,
                                                               target: self, action: #selector(perAppLayoutChanged))))
        let langPopup = NSPopUpButton()
        populateLanguagePopup(langPopup)
        langPopup.target = self
        langPopup.action = #selector(languageChanged)
        systemBox.addRow(FormUI.row(title: L10n.settingsLanguage, control: langPopup))

        return makeTabRoot([
            statusBox,
            FormUI.sectionHeader(L10n.settingsGroupTrigger),
            triggerBox,
            FormUI.footnote(L10n.settingsTriggerHint),
            FormUI.sectionHeader(L10n.settingsGroupSystem),
            systemBox,
        ])
    }

    /// Extracts the bold title from a FormUI.row row (for the status card).
    private func findTitleLabel(in row: NSView) -> NSTextField? {
        func walk(_ v: NSView) -> NSTextField? {
            if let tf = v as? NSTextField, tf.font == NSFont.boldSystemFont(ofSize: 13) { return tf }
            for sub in v.subviews { if let hit = walk(sub) { return hit } }
            return nil
        }
        return walk(row)
    }

    // MARK: - Auto-fix tab (W2)

    private func buildAutofixTab() -> NSView {
        let settings = SettingsManager.shared

        // Auto-fix master card (no beta badge — the feature has shipped).
        let masterBox = FormBox()
        masterBox.addRow(FormUI.row(title: L10n.settingsAutofixTitle,
                                    subtitle: L10n.settingsAutofixSubtitle,
                                    titleBold: true,
                                    control: FormUI.makeSwitch(isOn: settings.autoConvert,
                                                               target: self, action: #selector(autoConvertChanged))))

        // Experimental toggles (caret flag, remote desktop) moved to Advanced.
        var sections: [NSView] = [masterBox]

        // Unified exceptions list with a segmented filter
        let pane = ExceptionsPane()
        exceptionsPane = pane
        sections.append(FormUI.sectionHeader(L10n.settingsGroupExceptions))
        sections.append(pane.makeView())

        return makeTabRoot(sections)
    }

    // MARK: - About tab

    private func buildAboutTab() -> NSView {
        let titleLabel = NSTextField(labelWithString: "Switcher3way")
        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.alignment = .center

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let devTag = Bundle.main.infoDictionary?["RSDevTag"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "v\(version)\(devTag)")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        // Tagline under the version.
        let taglineLabel = NSTextField(labelWithString: L10n.settingsVersion)
        taglineLabel.font = .systemFont(ofSize: 12)
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.alignment = .center

        // All buttons (Star on GitHub / Donate / Contact / Check for Updates) removed in the Switcher3way fork.
        return makeTabRoot([titleLabel, versionLabel, taglineLabel], alignment: .centerX)
    }

    // MARK: - Advanced tab

    private func buildAdvancedTab() -> NSView {
        let settings = SettingsManager.shared
        var sections: [NSView] = []

        // Experimental toggles at the top of Advanced (moved from Auto-fix).
        // Caret flag (issue #10)
        let caretBox = FormBox()
        let cfSwitch = FormUI.makeSwitch(isOn: settings.caretFlag,
                                         target: self, action: #selector(caretFlagChanged))
        caretFlagSwitch = cfSwitch
        caretBox.addRow(FormUI.row(title: L10n.settingsAutofixCaretFlag,
                                   badge: L10n.commonBeta, control: cfSwitch))
        sections.append(caretBox)

        // Remote desktop mode deferred to 2.5 — the block is hidden behind a flag (for testing).
        if settings.showRemoteDesktopBeta {
            let remoteBox = FormBox()
            remoteBox.addRow(FormUI.row(title: L10n.menuRemoteDesktop,
                                        subtitle: L10n.settingsRemoteDesktopHint,
                                        control: FormUI.makeSwitch(isOn: settings.remoteDesktopMode,
                                                                   target: self, action: #selector(remoteDesktopChanged))))
            sections.append(remoteBox)
        }

        let debugBox = FormBox()
        debugBox.addRow(FormUI.row(title: L10n.settingsDebugLog,
                                   control: FormUI.makeSwitch(isOn: settings.debugLogEnabled,
                                                              target: self, action: #selector(debugLogChanged))))
        sections.append(debugBox)

        let showLogBtn = NSButton(title: L10n.settingsShowLog, target: self, action: #selector(showLogFile))
        showLogBtn.bezelStyle = .rounded
        sections.append(showLogBtn)

        let pathLabel = FormUI.footnote(logFilePath())
        pathLabel.isSelectable = true
        sections.append(pathLabel)

        return makeTabRoot(sections)
    }

    // MARK: - Language Popup

    private func populateLanguagePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItem(withTitle: "🌐 \(L10n.settingsLanguageAuto)")
        popup.menu?.items.last?.representedObject = "" as NSString

        for lang in L10n.languageNames {
            popup.addItem(withTitle: lang.name)
            popup.menu?.items.last?.representedObject = lang.code as NSString
        }

        selectItem(in: popup, matching: SettingsManager.shared.interfaceLanguage)
    }

    /// Selects the popup item whose representedObject == id (or the first one when id is empty)
    private func selectItem(in popup: NSPopUpButton, matching id: String) {
        if id.isEmpty {
            popup.selectItem(at: 0)
            return
        }
        for (i, item) in popup.itemArray.enumerated() {
            if (item.representedObject as? String) == id {
                popup.selectItem(at: i)
                return
            }
        }
        popup.selectItem(at: 0)
    }

    // MARK: - Trigger Popup

    private func populateTriggerPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        // Key names are not localized — these are standard Apple notations.
        let items: [(key: String, title: String)] = [
            ("option", "Option ⌥ (Alt)"),
            ("command", "Command ⌘"),
            ("control", "Control ⌃"),
            ("shift", "Shift ⇧"),
            // Caps Lock removed: native interception is unstable (HID debounce/toggle) — see tech debt.
        ]
        // issue #12: a combo of two modifiers (the familiar Windows-style Alt+Shift).
        let comboItems: [(key: String, title: String)] = [
            ("command+shift", "⌘ + ⇧  (Command + Shift)"),
            ("control+shift", "⌃ + ⇧  (Control + Shift)"),
            ("command+option", "⌘ + ⌥  (Command + Option)"),
            ("control+option", "⌃ + ⌥  (Control + Option)"),
        ]
        for it in items {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        popup.menu?.addItem(.separator())
        for it in comboItems {
            popup.addItem(withTitle: it.title)
            popup.menu?.items.last?.representedObject = it.key as NSString
        }
        selectItem(in: popup, matching: SettingsManager.shared.triggerKey)
    }

    // MARK: - Actions

    @objc private func autoSwitchChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.autoSwitchEnabled = enabled
        statusTitleLabel?.stringValue = enabled ? L10n.settingsStatusOn : L10n.settingsStatusOff
        onAutoSwitchChanged?(enabled)
    }

    @objc private func launchAtLoginChanged(_ sender: NSSwitch) {
        SettingsManager.shared.launchAtLogin = sender.state == .on
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let langCode = (sender.selectedItem?.representedObject as? String) ?? ""
        SettingsManager.shared.interfaceLanguage = langCode  // calls L10n.reloadLanguage()
        onLanguageChanged?()  // rebuild the status-bar menu for the new language
        // Recreate the window to apply the new language
        window?.close()
        window = nil
        showWindow()
    }

    @objc private func perAppLayoutChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.perAppLayout = enabled
        onPerAppLayoutChanged?(enabled)
    }

    @objc private func triggerChanged(_ sender: NSPopUpButton) {
        SettingsManager.shared.triggerKey = (sender.selectedItem?.representedObject as? String) ?? "option"
        onTriggerChanged?()
    }

    @objc private func triggerRightOnlyChanged(_ sender: NSSwitch) {
        SettingsManager.shared.triggerRightOnly = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func triggerDoubleTapChanged(_ sender: NSSwitch) {
        SettingsManager.shared.triggerDoubleTap = sender.state == .on
        onTriggerChanged?()
    }

    @objc private func autoConvertChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.autoConvert = enabled
        onAutoConvertChanged?(enabled)
    }

    @objc private func remoteDesktopChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.remoteDesktopMode = enabled
        onRemoteDesktopChanged?(enabled)
    }

    @objc private func caretFlagChanged(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        SettingsManager.shared.caretFlag = enabled
        onCaretFlagChanged?(enabled)
    }

    @objc private func debugLogChanged(_ sender: NSSwitch) {
        SettingsManager.shared.debugLogEnabled = sender.state == .on
    }

    @objc private func showLogFile() {
        let path = logFilePath()
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            let alert = NSAlert()
            alert.messageText = "Log file not found"
            alert.informativeText = "Enable debug logging first."
            alert.runModal()
        }
    }

    private func logFilePath() -> String {
        let logDir = NSHomeDirectory() + "/Library/Logs/Switcher3w"
        return logDir + "/switcher3w.log"
    }
}
