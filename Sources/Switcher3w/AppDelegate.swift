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
    private var pauseTimer: Timer?         // авто-возобновление по истечении таймерной паузы (W4)
    private var lastPermissionsOK: Bool?   // для перестройки меню при смене состояния разрешений
    private var monitoringActive = false
    private var caretIndicator: CaretIndicator?   // issue #10: флаг у каретки (бета, по умолчанию OFF)

    // Ссылки на живые метки статусного заголовка меню (обновляются опросом иконки)
    private weak var headerBadgeLabel: NSTextField?
    private weak var headerNameLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupSettingsCallbacks()
        setupOnboardingCallbacks()
        syncLoginItem()
        applyEnabledState()   // взводит таймер, если персистентная пауза ещё не истекла
        runPermissionWizard()
    }

    private func setupSettingsCallbacks() {
        settingsController.onAutoSwitchChanged = { [weak self] _ in
            self?.applyEnabledState()   // иконка + меню (Pause/Resume) следуют за мастер-тумблером
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
            self?.rebuildMenu()  // синхронизировать галочку в меню
        }
        settingsController.onRemoteDesktopChanged = { [weak self] _ in
            self?.reconfigureTap()  // уровень tap зависит от режима
            self?.rebuildMenu()
        }
        settingsController.onCaretFlagChanged = { [weak self] _ in
            self?.rebuildMenu()          // синхронизировать галочку в меню
            self?.syncCaretIndicator()   // создать/снести индикатор + обновить гейт onUserInput
        }
    }

    private func setupOnboardingCallbacks() {
        onboardingController.onAllGranted = { [weak self] in
            guard let self else { return }
            SettingsManager.shared.permissionsWereGranted = true
            if !self.monitoringActive { self.startMonitoring() }
            self.rebuildMenu()   // убрать «Проверить разрешения…» из меню
        }
        onboardingController.onRequestRestart = { [weak self] in
            self?.restartApp()
        }
    }

    // MARK: - Пауза / мастер-тумблер (W4)

    /// Единая точка применения «работаем/нет»: mастер-тумблер И пауза. Сам event tap
    /// не сносим (как и прежний Enable-чекбокс) — колбэки гейтятся effectivelyEnabled.
    private func applyEnabledState() {
        let settings = SettingsManager.shared

        // Таймер авто-возобновления для таймерной паузы (переживает и перезапуск:
        // pausedUntil персистентный, поэтому взводим и при старте приложения).
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

    // MARK: - Learn-from-undo (предложить добавить слово в never-convert)

    /// Последняя авто-конвертация: слово (как было набрано) + время. Если пользователь
    /// сразу откатывает ручным триггером — предлагаем занести слово в исключения.
    private var lastAutoConverted: (word: String, at: Date)?
    /// Анти-наг: за сессию про одно слово спрашиваем один раз.
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

    /// Синхронизирует состояние автозагрузки с системой при старте.
    /// Если галочка включена, но Login Item потерян (переустановка/обновление) — перерегистрирует.
    /// Если галочка выключена, но Login Item есть — снимает.
    private func syncLoginItem() {
        let settings = SettingsManager.shared
        let wanted = settings.launchAtLogin
        let status = settings.loginItemStatus

        rslog("Login item sync: wanted=\(wanted) status=\(status.rawValue)")

        if wanted && status != .enabled {
            // Галочка стоит, но Login Item не активен — перерегистрируем
            rslog("Re-registering login item...")
            settings.launchAtLogin = true  // setter вызовет doUpdateLoginItem
        } else if !wanted && status == .enabled {
            // Галочка снята, но Login Item активен — убираем
            rslog("Unregistering stale login item...")
            settings.launchAtLogin = false
        }
    }

    // MARK: - Permission Wizard

    /// Онбординг-чеклист (W3) вместо цепочки модальных алертов: одно окно с живым
    /// статусом обоих разрешений; закрытие ничего не теряет.
    private func runPermissionWizard(interactive: Bool = false) {
        let acc = AXIsProcessTrusted()
        let inp = CGPreflightListenEventAccess()
        rslog("Permissions: accessibility=\(acc) inputMonitoring=\(inp)")

        if acc && inp {
            // Запоминаем что разрешения были даны
            SettingsManager.shared.permissionsWereGranted = true
            if !monitoringActive { startMonitoring() }
            // Ручная проверка из меню должна давать видимый отклик: окно в состоянии «всё выдано».
            if interactive { onboardingController.show() }
            return
        }

        // Разрешения были раньше, а теперь сброшены (обновление): чистим TCC-записи
        // и показываем чеклист с пометкой о сбросе.
        if SettingsManager.shared.permissionsWereGranted {
            rslog("Permissions were previously granted — reset detected after update")
            SettingsManager.shared.permissionsWereGranted = false
            resetPermissions()
            onboardingController.show(resetNotice: true)
            return
        }

        // Первый запуск — чеклист онбординга
        onboardingController.show()
    }

    /// Сбрасывает старые записи разрешений для нашего bundle ID
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
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                let keys = self.keyboardMonitor.currentWordKeys
                let prevKeys = self.keyboardMonitor.prevWordKeys
                let bc = self.keyboardMonitor.boundaryCount
                // N-way: если детект однозначно указывает целевую раскладку из 3+, конвертим
                // туда. Иначе (слово валидно/неоднозначно) — прежний 2-way toggle по паре.
                let mkeys = keys.isEmpty ? prevKeys : keys
                let mtrailing = keys.isEmpty ? bc : 0
                let mcaps = mkeys.contains { $0.caps }
                if !mkeys.isEmpty,
                   let d = NWayResolver.resolve(keys: mkeys, capsLock: mcaps),
                   self.textConverter.convertBuffer(original: d.original, converted: d.converted,
                                                    keyCount: mkeys.count, trailingSpaces: mtrailing) {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchTo(layoutID: d.targetLayoutID)
                    self.updateStatusIcon()
                    self.lastAutoConverted = nil
                } else if self.textConverter.convert(wordKeys: keys, prevWordKeys: prevKeys, boundaryCount: bc) {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    self.lastAutoConverted = nil
                }
            },
            onAltReconvert: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.effectivelyEnabled else { return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    rslog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                if self.textConverter.reconvert() {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchToOpposite()
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
        updateStatusIcon()        // сначала выставляем флаг меню-бара, пока индикатора ещё нет
        syncCaretIndicator()      // затем создаём индикатор — без стартового ложного «попа»
        // Страховка к issue #9: системное уведомление о смене раскладки ненадёжно
        // (особенно через удалённый стол — на той машине оно часто не доходит), поэтому
        // флаг «застревает». Постоянный лёгкий опрос держит иконку в синхроне с системой.
        // Тот же опрос следит за состоянием разрешений (W4: пункт меню — только когда сломано).
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

        // Предлагаем автозамену при первом запуске (один раз). Автозагрузка теперь
        // предлагается тумблером в окне онбординга (W3), отдельного алерта больше нет.
        offerAutoConvertIfNeeded()
    }

    /// Перестраивает меню при смене состояния разрешений (потеря/возврат) — чтобы
    /// «Проверить разрешения…» появлялся только когда действительно сломано.
    private func watchPermissions() {
        let ok = AXIsProcessTrusted() && CGPreflightListenEventAccess()
        if ok != lastPermissionsOK {
            lastPermissionsOK = ok
            rebuildMenu()
        }
    }

    /// Авто-конвертация на границе слова: детект неправильной раскладки → конверт + смена.
    /// Точность-first: при любой неуверенности ничего не делаем. Ручной триггер не трогаем.
    private func handleAutoConvert() {
        rslog("auto: fired")
        guard SettingsManager.shared.effectivelyEnabled else { rslog("auto: bail master-off"); return }
        guard SettingsManager.shared.autoConvert else { rslog("auto: bail flag-off"); return }
        guard !AutoSwitchPolicy.secureInputActive else { rslog("auto: bail secure-input"); return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Удалёнка: НЕ выходим сразу — прогоняем детектор по своему (чистому) буферу, и при
        // «не той раскладке» переключаем СВОЮ раскладку (конверсию делает инстанс на той стороне).
        let deferToRemote = SettingsManager.shared.remoteDesktopMode && AutoSwitchPolicy.isRemoteDesktopClient(frontID)
        if AutoSwitchPolicy.isDeniedApp(frontID) { rslog("auto: bail denied-app \(frontID ?? "?")"); return }
        if let captured = keyboardMonitor.prevWordBundleID, captured != frontID {
            rslog("auto: bail focus-changed"); return  // фокус уехал между пробелом и сейчас
        }

        let keys = keyboardMonitor.prevWordKeys
        let bc = keyboardMonitor.boundaryCount
        guard !keys.isEmpty else { rslog("auto: bail empty-keys"); return }  // курсор уехал — небезопасно
        let capsLock = keys.contains { $0.caps }

        // --- Проброшенный через удалёнку текст (все символы — char): N-way неприменим,
        // т.к. все раскладки дали бы один символ. Оставляем прежний 2-way путь по СКРИПТУ
        // (RU↔EN), где направление определяет KeyMapping.convert, а не раскладка офиса. ---
        if keys.allSatisfy({ $0.char != nil }) {
            guard let pair = DynamicKeyMapping.convertKeys(keys) else { rslog("auto: bail convertKeys-nil"); return }
            if AutoSwitchPolicy.isDeniedWord(pair.original, pair.converted) { rslog("auto: bail denied-word"); return }
            let typedIsCyrillic = pair.original.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            let verdict = LayoutDetector.decide(typed: pair.original, converted: pair.converted,
                                                currentLang: typedIsCyrillic ? "ru" : "en",
                                                otherLang: typedIsCyrillic ? "en" : "ru",
                                                capsLock: capsLock)
            guard verdict == .switchToConverted else { return }
            // Удалёнка: конверсию делает инстанс на той стороне, здесь только своя раскладка.
            LayoutSwitcher.switchToOpposite()
            updateStatusIcon()
            rslog("auto: remote — local layout switched")
            return
        }

        // --- Локальный ввод: N-way детект среди всех установленных раскладок (EN/UK/RU/…). ---
        guard let decision = NWayResolver.resolve(keys: keys, capsLock: capsLock) else {
            rslog("auto: keep"); return
        }
        if AutoSwitchPolicy.isDeniedWord(decision.original, decision.converted) {
            rslog("auto: bail denied-word"); return
        }

        if deferToRemote {
            // Удалёнка (контроллер): текст конвертит инстанс на той стороне, здесь — своя раскладка.
            LayoutSwitcher.switchTo(layoutID: decision.targetLayoutID)
            updateStatusIcon()
            rslog("auto: local layout switched, conversion handled by controlled instance")
            return
        }

        rslog("auto: convert \(keys.count) keys (+\(bc) sp) → \(decision.targetLayoutID)")
        if textConverter.convertBuffer(original: decision.original, converted: decision.converted,
                                       keyCount: keys.count, trailingSpaces: bc) {
            keyboardMonitor.markConverted()
            LayoutSwitcher.switchTo(layoutID: decision.targetLayoutID)
            updateStatusIcon()
            lastAutoConverted = (decision.original, Date())
        }
    }

    /// Предлагает включить автозамену при первом запуске (один раз). Фича OFF по умолчанию,
    /// поэтому без явного предложения пользователь о ней не узнает.
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
            rebuildMenu()  // синхронизировать галочку «Автоматическая конверсия» в меню
            rslog("User enabled auto-convert at onboarding")
        } else {
            rslog("User declined auto-convert at onboarding")
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
        // issue #9: иконка должна отражать раскладку и при СИСТЕМНОЙ смене (стандартный/
        // переопределённый хоткей), а не только при нашей конверсии. Слушаем системное
        // распределённое уведомление о смене источника ввода.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemInputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }

    @objc private func systemInputSourceChanged() {
        updateStatusIcon()
        keyboardMonitor.soundArmed = true  // issue #7: следующая буква даст звук раскладки
    }

    /// Собирает меню статус-бара (W4: статус первым, тумблеры сгруппированы).
    /// Вызывается заново при смене языка интерфейса, состояния паузы и разрешений.
    private func rebuildMenu() {
        let menu = NSMenu()

        // Статусный заголовок: текущая раскладка + подсказка триггера + версия.
        // Версия переехала сюда из отдельной отключённой строки.
        let headerItem = NSMenuItem()
        headerItem.view = makeMenuHeaderView()
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // «Быстрые переключатели» — без «(beta)»: бейджи остаются в настройках.
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

        // Режим удалённого стола отложен в 2.5 — тумблер скрыт за флагом (для тестирования).
        if SettingsManager.shared.showRemoteDesktopBeta {
            let remoteDesktopItem = NSMenuItem(title: L10n.menuRemoteDesktop, action: #selector(toggleRemoteDesktop), keyEquivalent: "")
            remoteDesktopItem.target = self
            remoteDesktopItem.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
            menu.addItem(remoteDesktopItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Пауза с длительностями вместо чекбокса «Включить» (W4): выключенный
        // свитчер не должен выглядеть включённым — иконка показывает паузу.
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

        // «Проверить разрешения…» — только когда разрешения сломаны (W4);
        // в здоровом состоянии пункт не нужен в ежедневном меню.
        if !(AXIsProcessTrusted() && CGPreflightListenEventAccess()) {
            let permItem = NSMenuItem(title: L10n.menuCheckPermissions, action: #selector(recheckPermissions), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let settingsItem = NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Справка: встроенное руководство (⌘? — стандартный шорткат помощи macOS)
        let helpItem = NSMenuItem(title: L10n.menuHelp, action: #selector(openHelp), keyEquivalent: "?")
        helpItem.target = self
        menu.addItem(helpItem)

        // «Check for Updates», «Support Development», «Star on GitHub» удалены в форке Switcher3way.
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        rslog("Menu (re)built with \(menu.items.count) items")
    }

    /// Статусный заголовок меню (W4): бейдж с кодом языка, имя раскладки,
    /// строка «триггер конвертирует последнее слово · версия».
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

    /// Двухбуквенный код языка текущей раскладки для бейджа заголовка (W4: чип «EN»).
    private func currentLayoutBadge() -> String {
        guard let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty else {
            return "?"
        }
        return String(lang.prefix(2)).uppercased()
    }

    /// Символ клавиши-триггера для подсказки в заголовке меню.
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
        // W4: на паузе (или при выключенном мастер-тумблере) иконка явно отличается —
        // выключенный свитчер не должен выглядеть включённым.
        let title = SettingsManager.shared.effectivelyEnabled ? flag : "⏸" + flag
        // Каретку дёргаем ТОЛЬКО при реальной смене флага раскладки: updateStatusIcon
        // зовётся ещё и 2-секундным опросом-страховкой, иначе флаг у каретки выскакивал
        // бы каждые 2с (а смена паузы — не смена раскладки).
        let changed = lastFlagShown != flag
        lastFlagShown = flag
        statusItem.button?.title = title
        if changed { caretIndicator?.layoutChanged() }
        // Живой заголовок меню: раскладка могла смениться после последней пересборки меню.
        headerBadgeLabel?.stringValue = currentLayoutBadge()
        headerNameLabel?.stringValue = LayoutSwitcher.currentLayoutName()
    }

    private var lastFlagShown = ""

    /// Флаг текущей раскладки по коду языка (BCP-47), а не по подстроке в ID — иначе
    /// "Belarusian" ложно матчил "ru", а любая не-RU/EN пара показывалась как 🇺🇸.
    func flagForCurrentLayout() -> String {
        guard let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty else {
            // Язык раскладки недоступен — мягкий фолбэк по ID.
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

    /// issue #10: создаёт/освобождает индикатор каретки по флагу настроек. Создаётся лениво,
    /// только когда фича включена И мониторинг запущен (нужны разрешения).
    private func syncCaretIndicator() {
        keyboardMonitor.caretFlagEnabled = SettingsManager.shared.caretFlag   // гейт диспатча onUserInput
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

    /// Resume снимает и паузу, и выключенный мастер-тумблер — «включи обратно» одним пунктом.
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
        syncCaretIndicator()   // создать/снести индикатор и обновить гейт onUserInput
    }

    @objc private func toggleRemoteDesktop(_ sender: NSMenuItem) {
        SettingsManager.shared.remoteDesktopMode.toggle()
        sender.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
        reconfigureTap()  // уровень event tap зависит от режима
    }

    /// Пересоздаёт event tap и, если создание не удалось (например, session-tap отклонён),
    /// ретраит — иначе тумблер «вкл», а tap'а нет, и приложение молча не реагирует на триггер.
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
        // Не теряем буфер обмена в 2-секундном окне отложенного восстановления
        // (актуально и при само-обновлении, которое завершает процесс).
        textConverter.flushPendingClipboardRestore()
    }

    @objc private func quit() {
        textConverter.flushPendingClipboardRestore()
        perAppLayoutManager.stop()
        keyboardMonitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
