import AppKit
import ApplicationServices
import CoreGraphics

/// issue #10: показывает флаг текущей раскладки рядом с текстовой кареткой — кратко после
/// переключения, прячется при печати/клике. Позицию каретки берём через Accessibility
/// (kAXBoundsForRangeParameterizedAttribute). Если приложение её не отдаёт (Electron/веб,
/// часть терминалов) — просто не показываем; флаг в меню-баре остаётся. Click-through,
/// не крадёт фокус (LSUIElement + .nonactivatingPanel + orderFrontRegardless).
@MainActor
final class CaretIndicator {
    private let panel: NSPanel
    private let label: NSTextField
    private var lastFlag = ""
    private var hideTimer: Timer?
    private var visible = false

    /// Поставщик флага текущей раскладки — обычно AppDelegate.flagForCurrentLayout.
    var flagProvider: () -> String = { "" }

    /// Сколько держим флаг после переключения, прежде чем спрятать сам (если не печатают).
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
        panel.ignoresMouseEvents = true                 // click-through — обязательно
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true

        // Полупрозрачная скруглённая подложка — читаемость флага на любом фоне.
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

    // MARK: - Entry points (вызываются из AppDelegate)

    /// Реальная смена раскладки → показать флаг у каретки (на showDuration).
    func layoutChanged() {
        guard SettingsManager.shared.caretFlag else { return }
        showAtCaret()
    }

    /// Любой ввод/клик пользователя → прячем (issue #10: «скрывать при печати»).
    func userTyped() { if visible { hide() } }

    /// Фича выключена / выход — снять окно и таймер.
    func teardown() {
        hideTimer?.invalidate(); hideTimer = nil
        panel.orderOut(nil)
        visible = false
        lastFlag = ""
    }

    // MARK: - Internals

    private func showAtCaret() {
        guard let rect = axCaretRectAppKit() else { hide(); return }   // нет каретки → не показываем
        let flag = flagProvider()
        guard !flag.isEmpty else { hide(); return }
        if flag != lastFlag { label.stringValue = flag; lastFlag = flag }
        position(forCaret: rect)
        if !panel.isVisible { panel.orderFrontRegardless() }            // показ БЕЗ кражи фокуса
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
        // Остаётся ordered-in на alpha 0 — невидимо и click-through; полный orderOut в teardown().
        fade(to: 0, duration: 0.18)
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            panel.animator().alphaValue = alpha
        }
    }

    /// Кладём флаг справа от каретки (по центру по вертикали), прижимая к видимой области экрана.
    private func position(forCaret caret: NSRect) {
        let gap: CGFloat = 6
        let size = panel.frame.size
        var x = caret.maxX + gap
        var y = caret.midY - size.height / 2
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: caret.midX, y: caret.midY)) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            if x + size.width > vf.maxX { x = caret.minX - gap - size.width }  // не влез справа → слева
            x = min(max(x, vf.minX), vf.maxX - size.width)
            y = min(max(y, vf.minY), vf.maxY - size.height)
        }
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// Каретка в координатах AppKit (низ-лево), или nil если недоступна / гвард не пустил.
    private func axCaretRectAppKit() -> NSRect? {
        guard SettingsManager.shared.caretFlag else { return nil }
        guard AXIsProcessTrusted() else { return nil }
        guard !AutoSwitchPolicy.secureInputActive else { return nil }          // не над полем пароля
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // denylist авто-конверсии НЕ применяем: он про «не менять текст», а флаг ничего не меняет —
        // в IDE/терминалах индикатор раскладки как раз полезен. Пароли закрыты secure-input выше.
        guard !AutoSwitchPolicy.shouldDeferToRemoteClient else { return nil }  // удалёнка: каретка на той стороне
        guard frontID != Bundle.main.bundleIdentifier else { return nil }      // не над своим окном

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Ограничиваем AX round-trip: с зависшим/занятым таргетом (или Chromium, чьё дерево
        // только строится после AXManualAccessibility) дефолтный таймаут ~6с завесил бы главный
        // поток. 0.25с — не успел, значит nil → hide(), без залипания UI на смене раскладки.
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        enableChromiumA11y(axApp)   // поднять ленивое дерево Electron/Chromium (идемпотентно)
        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focused = focusedRaw else { return nil }
        let element = focused as! AXUIElement
        // Нативные Cocoa → range-путь; веб/Electron → text-marker (приватные AX-атрибуты).
        guard let topLeft = axCaretRectTopLeft(of: element) ?? axCaretRectViaTextMarker(of: element) else { return nil }

        // AX отдаёт глобальные координаты с началом сверху-слева ОСНОВНОГО экрана; AppKit — снизу-слева.
        // Отражаем по полной высоте основного экрана (screens.first), не по visibleFrame, не по целевому.
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

        // Часть Cocoa-контролов отдаёт пустой прямоугольник на нулевой длине → просим 1 символ,
        // с откатом на исходный нулевой диапазон (пустое поле, где следующего глифа нет).
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
        // Каретка: width = 0 (тонкая черта), но height = высота строки. VS Code-canvas отдаёт
        // (0,N,0x0) — height 0 = реальной геометрии нет, не показываем (иначе плашка в углу экрана).
        guard rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect
    }

    /// Electron/Chromium строят дерево a11y лениво — поднимаем его приватным атрибутом
    /// AXManualAccessibility (так делают TextSniper/PopClip). Идемпотентно (на уже включённом
    /// Chromium и на нативных приложениях — no-op). Без кэша по pid: pid переиспользуются при
    /// перезапуске приложений, а кэш «навсегда» ломал бы флаг для перезапущенного Electron.
    private func enableChromiumA11y(_ axApp: AXUIElement) {
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Веб/Electron: каретка приходит через AXTextMarker, а не CFRange. Приватные,
    /// недокументированные атрибуты (стабильны на практике годами).
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
        // Тот же гвард, что в range-пути: отвергаем вырожденную геометрию (веб/Electron
        // порой отдаёт (x,y,0x0) с ненулевым origin — height>=1 это ловит, включая .zero).
        guard rect.height >= 1, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect   // экранные координаты, верх-лево
    }
}
