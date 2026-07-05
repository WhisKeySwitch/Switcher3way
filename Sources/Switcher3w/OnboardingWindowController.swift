import AppKit
import ApplicationServices

/// Onboarding checklist (W3): a single persistent window instead of a chain of modal alerts.
/// Live permission status (polled once a second), a one-line "why" explanation,
/// an inline launch-at-login switch. Closing loses nothing — the window can be reopened.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var pollTimer: Timer?
    private var showResetNotice = false

    // Live elements of the checklist rows
    private var accBubble: NSView?
    private var accTrailing: NSStackView?
    private var inpBubble: NSView?
    private var inpTrailing: NSStackView?
    private var stepLabel: NSTextField?

    /// All permissions granted (on Continue) — AppDelegate starts monitoring.
    var onAllGranted: (() -> Void)?
    /// Input Monitoring was just granted — a restart is needed (as in the old wizard).
    var onRequestRestart: (() -> Void)?

    private var accGranted: Bool { AXIsProcessTrusted() }
    private var inpGranted: Bool { CGPreflightListenEventAccess() }

    func show(resetNotice: Bool = false) {
        showResetNotice = resetNotice
        // Onboarding replaces the old one-time launch-at-login alert — clear its flag.
        SettingsManager.shared.launchAtLoginAsked = true

        if window == nil { window = buildWindow() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    // MARK: - Window construction

    private func buildWindow() -> NSWindow {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = NSTextField(labelWithString: L10n.onboardingTitle)
        title.font = .boldSystemFont(ofSize: 17)
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: L10n.onboardingSubtitle)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center

        var headerViews: [NSView] = [icon, title, subtitle]

        if showResetNotice {
            let notice = NSTextField(wrappingLabelWithString: L10n.onboardingResetNotice)
            notice.font = .systemFont(ofSize: 11)
            notice.textColor = .systemOrange
            notice.alignment = .center
            headerViews.append(notice)
        }

        // Checklist: two permissions + launch at login (instead of a separate alert)
        let box = FormBox()

        let (accRow, accB, accT) = makeChecklistRow(
            number: 1,
            title: L10n.onboardingAccessibilityTitle,
            subtitle: L10n.onboardingAccessibilityText,
            action: #selector(openAccessibilitySettings))
        accBubble = accB; accTrailing = accT
        box.addRow(accRow)

        let (inpRow, inpB, inpT) = makeChecklistRow(
            number: 2,
            title: L10n.onboardingInputMonitoringTitle,
            subtitle: L10n.onboardingInputMonitoringText,
            action: #selector(openInputMonitoringSettings))
        inpBubble = inpB; inpTrailing = inpT
        box.addRow(inpRow)

        let loginSwitch = FormUI.makeSwitch(isOn: SettingsManager.shared.launchAtLogin,
                                            target: self, action: #selector(launchAtLoginChanged))
        box.addRow(FormUI.row(title: L10n.settingsLaunchAtLogin, control: loginSwitch))

        // Footer: step on the left, Continue on the right
        let step = NSTextField(labelWithString: "")
        step.font = .systemFont(ofSize: 11)
        step.textColor = .tertiaryLabelColor
        stepLabel = step

        let continueBtn = NSButton(title: L10n.onboardingContinue, target: self, action: #selector(continueTapped))
        continueBtn.bezelStyle = .rounded
        continueBtn.keyEquivalent = "\r"

        let footer = NSStackView(views: [step, NSView(), continueBtn])
        footer.orientation = .horizontal
        footer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: headerViews + [box, footer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(14, after: box)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalToConstant: 420),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            box.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        let vc = NSViewController()
        vc.view = content
        let win = NSWindow(contentViewController: vc)
        win.styleMask = [.titled, .closable]
        win.title = L10n.onboardingTitle
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.delegate = self
        return win
    }

    /// Checklist row: number bubble, title + explanation, status/button on the right.
    private func makeChecklistRow(number: Int, title: String, subtitle: String,
                                  action: Selector) -> (NSView, NSView, NSStackView) {
        let bubble = NSView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 10
        bubble.widthAnchor.constraint(equalToConstant: 20).isActive = true
        bubble.heightAnchor.constraint(equalToConstant: 20).isActive = true
        let bubbleLabel = NSTextField(labelWithString: "\(number)")
        bubbleLabel.font = .boldSystemFont(ofSize: 11)
        bubbleLabel.alignment = .center
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(bubbleLabel)
        NSLayoutConstraint.activate([
            bubbleLabel.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            bubbleLabel.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        let subLabel = NSTextField(wrappingLabelWithString: subtitle)
        subLabel.font = .systemFont(ofSize: 11)
        subLabel.textColor = .secondaryLabelColor
        let textStack = NSStackView(views: [titleLabel, subLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        // The right side changes on poll: an "Open Settings" button ↔ a "Granted" label
        let trailing = NSStackView()
        trailing.orientation = .horizontal
        let button = NSButton(title: L10n.wizardOpenSettings, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        trailing.addArrangedSubview(button)

        let row = NSStackView(views: [bubble, textStack, NSView(), trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        return (row, bubble, trailing)
    }

    // MARK: - Live status

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let inpWasGranted = inpTrailingShowsGranted
        refresh()
        // Input Monitoring was just granted: like the old wizard — restart,
        // otherwise the event tap won't work (a macOS requirement).
        if inpGranted && !inpWasGranted && accGranted {
            rslog("Input Monitoring granted! Restarting...")
            SettingsManager.shared.permissionsWereGranted = true
            pollTimer?.invalidate()
            pollTimer = nil
            onRequestRestart?()
        }
    }

    private var inpTrailingShowsGranted = false

    /// Redraws the rows to match the current permission state.
    private func refresh() {
        updateRow(bubble: accBubble, trailing: accTrailing, granted: accGranted,
                  number: 1, action: #selector(openAccessibilitySettings))
        updateRow(bubble: inpBubble, trailing: inpTrailing, granted: inpGranted,
                  number: 2, action: #selector(openInputMonitoringSettings))
        inpTrailingShowsGranted = inpGranted

        let total = 2
        let granted = (accGranted ? 1 : 0) + (inpGranted ? 1 : 0)
        if granted == total {
            stepLabel?.stringValue = L10n.permissionsOkText
            SettingsManager.shared.permissionsWereGranted = true
        } else {
            stepLabel?.stringValue = L10n.onboardingStep(min(granted + 1, total), total)
        }
    }

    private func updateRow(bubble: NSView?, trailing: NSStackView?, granted: Bool,
                           number: Int, action: Selector) {
        guard let bubble, let trailing else { return }
        if let label = bubble.subviews.first as? NSTextField {
            label.stringValue = granted ? "✓" : "\(number)"
            label.textColor = granted ? .white : .secondaryLabelColor
        }
        bubble.layer?.backgroundColor = granted ? NSColor.controlAccentColor.cgColor : nil
        bubble.layer?.borderWidth = granted ? 0 : 1.5
        bubble.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor

        let showsGranted = trailing.arrangedSubviews.first is NSTextField
        guard showsGranted != granted else { return }
        trailing.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if granted {
            let label = NSTextField(labelWithString: L10n.onboardingGranted)
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .controlAccentColor
            trailing.addArrangedSubview(label)
        } else {
            let button = NSButton(title: L10n.wizardOpenSettings, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .small
            trailing.addArrangedSubview(button)
        }
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        // System dialog: prompt=true adds the app to the Accessibility list automatically.
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true as CFBoolean] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openInputMonitoringSettings() {
        // System dialog: adds the app to the Input Monitoring list automatically.
        CGRequestListenEventAccess()
    }

    @objc private func launchAtLoginChanged(_ sender: NSSwitch) {
        SettingsManager.shared.launchAtLogin = sender.state == .on
        rslog("Onboarding: launch at login = \(sender.state == .on)")
    }

    @objc private func continueTapped() {
        if accGranted && inpGranted { onAllGranted?() }
        window?.close()   // "Later": nothing is lost, the window can be reopened
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
