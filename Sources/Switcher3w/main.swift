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

// `Switcher3Way diagstore` — App Store build only. Prints the entitlement and whatever products
// StoreKit will actually hand over, then exits. The equivalent of diagpw for purchases: an empty
// product list and a product list that failed to load look identical from the outside, and the
// app's own log lives inside the sandbox container where it cannot easily be read.
#if SWITCHER_APPSTORE
if CommandLine.arguments.dropFirst().contains("diagstore") {
    print("Switcher3Way — purchase diagnostic\n")
    let done = DispatchSemaphore(value: 0)
    Task { @MainActor in
        await Purchases.shared.refresh()
        await Purchases.shared.loadProducts()
        print("entitlement: \(Purchases.shared.entitlement)")
        print("last buy:    \(Purchases.lastOutcomeDescription ?? "no purchase attempted")")
        let products = Purchases.shared.products
        if products.isEmpty {
            print("products:    NONE LOADED")
            print("""

                  Nothing loaded. Usually one of:
                    - the app is not signed with a Mac App Store provisioning profile
                    - the products are not yet in a reviewable state in App Store Connect
                    - no sandbox account is signed in (System Settings > App Store)
                    - no network
                  """)
        } else {
            print("products:")
            for p in products {
                print("  \(p.id)  \(p.displayName)  \(p.displayPrice)  [\(p.type)]")
            }
        }
        done.signal()
    }
    // The StoreKit calls above are async and the main actor must keep running for them to
    // proceed, so pump the run loop rather than blocking it.
    while done.wait(timeout: .now() + 0.05) == .timedOut {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
