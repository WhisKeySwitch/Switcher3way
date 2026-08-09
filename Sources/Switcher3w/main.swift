import AppKit

// Migration of settings from the old com.ruswitcher.* keys — strictly before the first
// settings read (L10n lazily reads the interface language on first access).
SettingsManager.migrateLegacyDefaults()

// `Switcher3way diagpw` — print what the password guard sees for whatever currently has focus,
// then exit. The verdict alone is not enough to trust: knowing WHICH signal answered is what
// separates a working guard from one that is right by accident. Runs on a 3 s countdown so the
// user can click into the field they want inspected after launching it from a terminal.
if CommandLine.arguments.dropFirst().contains("diagpw") {
    print("Switcher3way — password-field guard diagnostic")
    print("Click into the field you want inspected. Sampling in 3 seconds…\n")
    Thread.sleep(forTimeInterval: 3)
    let verdict = MainActor.assumeIsolated { SecureFieldDetector.describe() }
    print(verdict.describe)
    print("\nConversion would be: \(verdict.isPassword ? "SUPPRESSED (password field)" : "allowed")")
    if !AXIsProcessTrusted() {
        print("\nNote: this process is not trusted for Accessibility, so the element query cannot " +
              "see anything. Run the diagnostic from the installed, permitted app bundle.")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
