import AppKit
import Foundation

/// Single point for relaunching the app.
/// This sequence used to be duplicated in AppDelegate and UpdateChecker.
@MainActor
enum AppRelauncher {
    /// Relaunches the app: reopens the bundle and terminates the current process.
    static func relaunch(bundlePath: String = Bundle.main.bundlePath) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; open '\(bundlePath)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
