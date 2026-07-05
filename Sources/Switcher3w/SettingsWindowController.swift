import AppKit
import Carbon

/// Окно настроек: тулбарные вкладки в стиле Системных настроек (W1/W2),
/// сгруппированные формы с переключателями вместо голых чекбоксов.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var statusSwitch: NSSwitch?
    private var statusTitleLabel: NSTextField?
    private var caretFlagSwitch: NSSwitch?
    private var exceptionsPane: ExceptionsPane?

    /// Callback для обновления меню
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
        // Порядок вкладок по W1: General / Auto-fix / Advanced / About.
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

    /// Обёртка вкладки: view-контроллер с иконкой SF Symbol и вычисленным
    /// preferredContentSize (тулбарный стиль ресайзит окно по нему).
    private func makeTab(title: String, symbol: String, view: NSView) -> NSTabViewItem {
        let vc = NSViewController()
        vc.view = view
        // NSTabViewController в тулбарном стиле берёт заголовок окна из title
        // выбранного контроллера — без него окно называется «Без названия».
        vc.title = L10n.settingsTitle
        view.layoutSubtreeIfNeeded()
        vc.preferredContentSize = NSSize(width: tabWidth, height: view.fittingSize.height)
        let item = NSTabViewItem(viewController: vc)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    /// Каркас вкладки: вертикальный стек секций с отступами, ширина фиксирована.
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
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
        ])
        for s in sections {
            s.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return root
    }

    /// Обновить состояние мастер-переключателя извне (меню / пауза)
    func updateAutoSwitchState(_ enabled: Bool) {
        statusSwitch?.state = enabled ? .on : .off
        statusTitleLabel?.stringValue = enabled ? L10n.settingsStatusOn : L10n.settingsStatusOff
    }

    /// Обновить переключатель «флаг у курсора» извне (когда переключили из меню)
    func updateCaretFlagState(_ enabled: Bool) {
        caretFlagSwitch?.state = enabled ? .on : .off
    }

    // MARK: - Вкладка General (W1)

    private func buildGeneralTab() -> NSView {
        let settings = SettingsManager.shared

        // Статус-карточка: мастер-тумблер, повышенный из голого чекбокса.
        let statusBox = FormBox()
        let sw = FormUI.makeSwitch(isOn: settings.autoSwitchEnabled,
                                   target: self, action: #selector(autoSwitchChanged))
        statusSwitch = sw
        let statusRow = FormUI.row(title: settings.autoSwitchEnabled ? L10n.settingsStatusOn : L10n.settingsStatusOff,
                                   subtitle: L10n.settingsHotkey, titleBold: true, control: sw)
        statusTitleLabel = findTitleLabel(in: statusRow)
        statusBox.addRow(statusRow)

        // Секция «Триггер»
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

        // Ручной триггер теперь полностью N-way (перебирает кандидатов по всем установленным
        // раскладкам), фиксированной пары Layout 1/2 больше нет — соответствующий ряд удалён.

        // Секция «Система»
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

    /// Достаёт жирный заголовок из строки FormUI.row (для статус-карточки).
    private func findTitleLabel(in row: NSView) -> NSTextField? {
        func walk(_ v: NSView) -> NSTextField? {
            if let tf = v as? NSTextField, tf.font == NSFont.boldSystemFont(ofSize: 13) { return tf }
            for sub in v.subviews { if let hit = walk(sub) { return hit } }
            return nil
        }
        return walk(row)
    }

    // MARK: - Вкладка Auto-fix (W2)

    private func buildAutofixTab() -> NSView {
        let settings = SettingsManager.shared

        // Мастер-карточка автозамены (без beta-бейджа — фича шипнута).
        let masterBox = FormBox()
        masterBox.addRow(FormUI.row(title: L10n.settingsAutofixTitle,
                                    subtitle: L10n.settingsAutofixSubtitle,
                                    titleBold: true,
                                    control: FormUI.makeSwitch(isOn: settings.autoConvert,
                                                               target: self, action: #selector(autoConvertChanged))))

        // Экспериментальные тумблеры (флаг у курсора, удалёнка) переехали в Advanced.
        var sections: [NSView] = [masterBox]

        // Единый список исключений с сегментным фильтром
        let pane = ExceptionsPane()
        exceptionsPane = pane
        sections.append(FormUI.sectionHeader(L10n.settingsGroupExceptions))
        sections.append(pane.makeView())

        return makeTabRoot(sections)
    }

    // MARK: - Вкладка About

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

        // Слоган под версией.
        let taglineLabel = NSTextField(labelWithString: L10n.settingsVersion)
        taglineLabel.font = .systemFont(ofSize: 12)
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.alignment = .center

        // Все кнопки (Star on GitHub / Donate / Contact / Check for Updates) удалены в форке Switcher3way.
        return makeTabRoot([titleLabel, versionLabel, taglineLabel], alignment: .centerX)
    }

    // MARK: - Вкладка Advanced

    private func buildAdvancedTab() -> NSView {
        let settings = SettingsManager.shared
        var sections: [NSView] = []

        // Экспериментальные тумблеры вверху Advanced (переехали из Auto-fix).
        // Флаг у курсора (issue #10)
        let caretBox = FormBox()
        let cfSwitch = FormUI.makeSwitch(isOn: settings.caretFlag,
                                         target: self, action: #selector(caretFlagChanged))
        caretFlagSwitch = cfSwitch
        caretBox.addRow(FormUI.row(title: L10n.settingsAutofixCaretFlag,
                                   badge: L10n.commonBeta, control: cfSwitch))
        sections.append(caretBox)

        // Режим удалённого стола отложен в 2.5 — блок скрыт за флагом (для тестирования).
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

    /// Выбирает в popup пункт, у которого representedObject == id (или первый при пустом id)
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
        // Имена клавиш не локализуем — это стандартные обозначения Apple.
        let items: [(key: String, title: String)] = [
            ("option", "Option ⌥ (Alt)"),
            ("command", "Command ⌘"),
            ("control", "Control ⌃"),
            ("shift", "Shift ⇧"),
            // Caps Lock убран: нативный перехват нестабилен (HID-дебаунс/тоггл) — см. техдолг.
        ]
        // issue #12: комбо двух модификаторов (привычный по Windows стиль Alt+Shift).
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
        SettingsManager.shared.interfaceLanguage = langCode  // вызывает L10n.reloadLanguage()
        onLanguageChanged?()  // пересобрать меню статус-бара под новый язык
        // Пересоздаём окно для применения нового языка
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
