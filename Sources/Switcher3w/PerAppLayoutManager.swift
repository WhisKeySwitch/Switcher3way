import AppKit

/// Remembers the keyboard layout for each app and restores it on switching.
@MainActor
final class PerAppLayoutManager {
    private var layoutByApp: [String: String] = [:]
    private var previousBundleID: String?
    private var observer: NSObjectProtocol?

    var onLayoutRestored: (() -> Void)?

    func start() {
        previousBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.handleAppActivated(app)
            }
        }
        rslog("PerAppLayout: started")
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
        layoutByApp.removeAll()
        previousBundleID = nil
        rslog("PerAppLayout: stopped")
    }

    private func handleAppActivated(_ app: NSRunningApplication?) {
        guard let newBundleID = app?.bundleIdentifier else { return }

        let currentLayout = LayoutSwitcher.currentLayoutID()

        // Save the layout for the previous app
        if let prevID = previousBundleID {
            layoutByApp[prevID] = currentLayout
        }

        // Remote desktop: in a remote desktop client window the layout is driven by conversion
        // and the user, not by per-app memory. Otherwise, on entering the window we'd revert the
        // layout to the remembered one (e.g. always Russian) and break continued typing.
        if SettingsManager.shared.remoteDesktopMode,
           AutoSwitchPolicy.isRemoteDesktopClient(newBundleID) {
            previousBundleID = newBundleID
            return
        }

        // Restore the layout for the new app
        if let savedLayout = layoutByApp[newBundleID], savedLayout != currentLayout {
            rslog("PerAppLayout: \(newBundleID) → restore \(savedLayout)")
            LayoutSwitcher.switchTo(layoutID: savedLayout)
            onLayoutRestored?()
        }

        previousBundleID = newBundleID
    }
}
