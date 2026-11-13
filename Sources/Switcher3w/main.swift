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

// `Switcher3way diagpost` — can this process deliver synthetic keystrokes to another app? Posts,
// through the retype engine's exact path (hidSystemState source, `.cghidEventTap`), a Unicode
// insert "AB", one Backspace, then "Z": a target that received everything reads "AZ". The report —
// permission state and which app was frontmost when the keys went out — goes to the general
// pasteboard as well as the log, because a sandboxed app launched through LaunchServices has no
// terminal, and its container is unreadable from outside. Launch it with `open -g`, not from a
// shell: from a shell, macOS attributes the posting to the parent process and its permissions.
if CommandLine.arguments.dropFirst().contains("diagpost") {
    let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    var report = "diagpost: bundle=\(Bundle.main.bundleIdentifier ?? "none") sandboxed=\(sandboxed)"
        + " accessibility=\(AXIsProcessTrusted()) postEvent=\(CGPreflightPostEventAccess())"
        + " listenEvent=\(CGPreflightListenEventAccess())"
    Thread.sleep(forTimeInterval: 2)
    report += " frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")"
    let source = CGEventSource(stateID: .hidSystemState)
    func post(_ code: UInt16, _ text: String?) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else {
            NSLog("diagpost: could not create event"); return
        }
        if let text {
            let utf16 = Array(text.utf16)
            utf16.withUnsafeBufferPointer { buf in
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        usleep(50_000)
    }
    post(0, "AB")
    post(51, nil)   // Backspace
    post(0, "Z")
    report += " posted"
    NSLog("%@", report)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(report, forType: .string)
    exit(0)
}

// `Switcher3way diagtap` — can this process see typing with Accessibility alone? Creates the
// monitor's tap (HID location, tail-appended) as an ACTIVE tap, which macOS gates under
// Accessibility, not under Input Monitoring as it does the listen-only tap. Never asks for Input
// Monitoring, so the answer isolates exactly that. Counts keyDowns for 10 s: real keys separately
// from three it posts itself (tagged), because the system could plausibly pass posted events and
// filter hardware ones. Not trusted yet: shows the Accessibility prompt and exits. The report goes
// to the pasteboard, as with diagpost; launch it with `open -g`, never from a shell.
var diagTapReal = 0
var diagTapPosted = 0
let diagTapMarker: Int64 = 0x7461_7074   // "tapt"
if CommandLine.arguments.dropFirst().contains("diagtap") {
    let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    var report = "diagtap: bundle=\(Bundle.main.bundleIdentifier ?? "none") sandboxed=\(sandboxed)"
        + " accessibility=\(AXIsProcessTrusted()) listenEvent=\(CGPreflightListenEventAccess())"
    func finish(_ tail: String) -> Never {
        report += tail
        NSLog("%@", report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        exit(0)
    }
    if !AXIsProcessTrusted() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true as CFBoolean] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        finish(" — not trusted: Accessibility prompt shown, grant it and run again")
    }
    let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .keyDown {
            if event.getIntegerValueField(.eventSourceUserData) == diagTapMarker { diagTapPosted += 1 }
            else { diagTapReal += 1 }
        }
        return Unmanaged.passUnretained(event)
    }
    guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                                      callback: callback, userInfo: nil) else {
        finish(" activeTap=FAILED to create")
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    report += " activeTap=created"
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let posting = CGEventSource(stateID: .hidSystemState)
    posting?.userData = diagTapMarker
    for code: UInt16 in [113, 113, 113] {   // F15: a real keyDown that does nothing almost anywhere
        CGEvent(keyboardEventSource: posting, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: posting, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(9))
    finish(" enabledAtEnd=\(CGEvent.tapIsEnabled(tap: tap)) realKeyDowns=\(diagTapReal) postedKeyDownsSeen=\(diagTapPosted)/3")
}

// `Switcher3way diagmonitor` — start the app's real keyboard monitor through the real code path,
// and report what it did: which permissions this flavour checked, which tap mode it chose, and
// whether the tap came up enabled. The Store build must get an enabled active tap without ever
// raising the Input Monitoring prompt. Report via the pasteboard, as with diagpost.
if CommandLine.arguments.dropFirst().contains("diagmonitor") {
    MainActor.assumeIsolated {
        let monitor = KeyboardMonitor()
        let started = monitor.start(onAltTap: {}, onAltReconvert: {})
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let active = Permissions.needsActiveTap(capsLockTrigger: TriggerConfig.current().isCapsLock)
        let report = "diagmonitor: bundle=\(Bundle.main.bundleIdentifier ?? "none")"
            + " asksForInputMonitoring=\(Permissions.asksForInputMonitoring) allGranted=\(Permissions.allGranted)"
            + " tapMode=\(active ? "active" : "listen-only") started=\(started) enabled=\(monitor.isTapEnabled)"
            + " | \(Permissions.logLine)"
        NSLog("%@", report)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
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
