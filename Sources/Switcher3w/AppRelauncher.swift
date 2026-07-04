import AppKit
import Foundation

/// Единая точка перезапуска приложения.
/// Раньше эта последовательность была скопирована в AppDelegate и UpdateChecker.
@MainActor
enum AppRelauncher {
    /// Перезапускает приложение: открывает бандл заново и завершает текущий процесс.
    static func relaunch(bundlePath: String = Bundle.main.bundlePath) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open '\(bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
