import AppKit

// Миграция настроек со старых com.ruswitcher.* ключей — строго до первого чтения
// настроек (L10n лениво читает язык интерфейса при первом обращении).
SettingsManager.migrateLegacyDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
