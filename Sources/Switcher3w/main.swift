import AppKit

// Migration of settings from the old com.ruswitcher.* keys — strictly before the first
// settings read (L10n lazily reads the interface language on first access).
SettingsManager.migrateLegacyDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
