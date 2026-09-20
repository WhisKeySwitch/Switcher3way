import AppKit
import ApplicationServices
import Carbon

/// The result of one password-field check: the verdict plus each signal's individual answer.
///
/// The per-signal breakdown is not a debugging luxury — it is the difference between "the guard
/// looked and found nothing" and "the guard is broken". The equivalent Windows guard reported
/// `false` for every field on earth for four releases because nobody could tell those two apart
/// from the log (see `windows/src/Switcher3way.App/SecureField.cs`).
/// One signal's answer. Three states rather than two, because "could not run" and "ran and found
/// nothing" have the same consequence and are completely different facts. Reporting the first as
/// the second is exactly how a guard that never fires becomes indistinguishable from a guard that
/// correctly finds nothing — the failure this file's header already records from the Windows port.
///
/// In the sandboxed App Store flavour signals 1 and 2 are permanently `.unavailable`: the sandbox
/// forbids inspecting another application's Accessibility elements, so those checks never run.
enum SignalState: String {
    case yes
    case no
    case unavailable

    init(_ flag: Bool) { self = flag ? .yes : .no }

    /// Only an outright `yes` suppresses conversion. `unavailable` is not a positive — the guard
    /// stays fail-open, so a signal that cannot run can never block the user from typing.
    var isPositive: Bool { self == .yes }
}

struct SecureFieldVerdict {
    /// Signal 1: the focused element's AX subrole is `AXSecureTextField`.
    let subroleSecure: SignalState
    /// Signal 2: a text-entry element whose label/placeholder/help says "password".
    let labelledPassword: SignalState
    /// Signal 3: the process-global secure-input flag (the app's original, only check).
    let secureInput: SignalState
    /// Signal 4: the frontmost application is one that exists to hold credentials. Coarse — it
    /// suppresses the whole application rather than one field — but it needs no element query, so
    /// it is the only password signal that still works when the sandbox forbids inspection.
    let credentialApp: SignalState
    /// What had focus, for the log — role/subrole and the label we matched against.
    let focusDescription: String

    /// Any signal fired → treat as a password field.
    var isPassword: Bool {
        subroleSecure.isPositive || labelledPassword.isPositive
            || secureInput.isPositive || credentialApp.isPositive
    }

    /// One line naming the verdict and every signal, for the debug log and `diagpw`.
    var describe: String {
        "password=\(isPassword)  (subrole=\(subroleSecure.rawValue) " +
        "labelled=\(labelledPassword.rawValue) secureInput=\(secureInput.rawValue) " +
        "credentialApp=\(credentialApp.rawValue))  focus[\(focusDescription)]"
    }

    /// No element to inspect — the signals exist in this build, they simply had nothing to answer
    /// about. Distinct from `.elementInspectionUnavailable`, where they cannot run at all.
    @MainActor
    static func none(_ why: String) -> SecureFieldVerdict {
        SecureFieldVerdict(subroleSecure: .no, labelledPassword: .no,
                           secureInput: SignalState(IsSecureEventInputEnabled()),
                           credentialApp: SecureFieldDetector.frontmostIsCredentialApp(),
                           focusDescription: why)
    }

    /// This build cannot inspect Accessibility elements at all. The verdict rests on what is left.
    @MainActor
    static func elementInspectionUnavailable() -> SecureFieldVerdict {
        SecureFieldVerdict(subroleSecure: .unavailable, labelledPassword: .unavailable,
                           secureInput: SignalState(IsSecureEventInputEnabled()),
                           credentialApp: SecureFieldDetector.frontmostIsCredentialApp(),
                           focusDescription: "element inspection unavailable (sandboxed build)")
    }
}

/// Whether the focused control is a password field. Auto-conversion, the manual trigger and the
/// on-screen feedback must never touch text in one.
///
/// Three signals, in the order of what actually catches what:
///   1. **AX subrole `AXSecureTextField`** — the canonical macOS answer: `NSSecureTextField` and
///      WebKit's masked `<input type="password">` both publish it.
///   2. **A text-entry element labelled as a password** — the same field while *un-masked*, which
///      no subrole reports. Any login form with a show/hide toggle turns its input into plain text
///      while revealed, and some forms mask in their own code and never use a secure field at all.
///   3. **`IsSecureEventInputEnabled()`** — the app's original check, kept as a third signal. It is
///      process-global and advisory: Electron hosts and JavaScript-masked web forms leave it clear,
///      which is exactly the gap signals 1 and 2 close.
///
/// Best-effort by design: any query failure logs and returns "not a password" — detection must never
/// throw into or stall the conversion path. But it must also never silently answer "not a password"
/// because a query failed, so every failure is logged.
///
/// Deliberately over-blocks. A false positive costs one unconverted word in a box labelled
/// *password*, which is what the user wants there anyway; a false negative rewrites a credential.
@MainActor
enum SecureFieldDetector {

    /// Messaging timeout for the focused-element queries. Tighter than `CaretIndicator`'s 0.25 s:
    /// that one runs *after* a switch, this one sits in front of the user's next keystroke.
    private static let axTimeout: Float = 0.05

    /// How long a verdict stays good for the same focused element. A backstop only — the element
    /// identity below is the real cache key.
    private static let cacheTTL: TimeInterval = 2.0

    private static var cachedElement: AXUIElement?
    private static var cachedVerdict: SecureFieldVerdict?
    private static var cachedAt: Date = .distantPast

    /// The verdict for the currently focused control, reusing the cached answer while focus has not
    /// moved. This is the entry point for the conversion paths — call it once per word and pass the
    /// result down, rather than re-querying per consumer.
    static func verdict() -> SecureFieldVerdict {
#if SWITCHER_APPSTORE
        // The sandbox refuses the element query (kAXErrorCannotComplete), so do not pretend to
        // ask: an answer of "no" here would be a lie about a check that never happened.
        return .elementInspectionUnavailable()
#else
        guard let (element, axApp) = focusedElement() else {
            invalidate()
            return .none("no focused element")
        }
        if let cached = cachedVerdict, let key = cachedElement,
           CFEqual(key, element), Date().timeIntervalSince(cachedAt) < cacheTTL {
            // Signal 3 is free and can change without focus moving (a terminal toggling secure
            // entry), so it is re-read rather than cached.
            // Signals 3 and 4 are free and can change without focus moving, so they are re-read
            // rather than cached.
            return SecureFieldVerdict(subroleSecure: cached.subroleSecure,
                                      labelledPassword: cached.labelledPassword,
                                      secureInput: SignalState(IsSecureEventInputEnabled()),
                                      credentialApp: frontmostIsCredentialApp(),
                                      focusDescription: cached.focusDescription)
        }
        let fresh = evaluate(element: element, axApp: axApp)
        cachedElement = element
        cachedVerdict = fresh
        cachedAt = Date()
        return fresh
#endif
    }

    /// Convenience for the call sites that only need the answer.
    static var isFocusedPassword: Bool { verdict().isPassword }

    /// A fresh, uncached verdict — for `diagpw` and for anything that must not see a stale answer.
    static func describe() -> SecureFieldVerdict {
#if SWITCHER_APPSTORE
        return .elementInspectionUnavailable()
#else
        guard let (element, axApp) = focusedElement() else { return .none("no focused element") }
        return evaluate(element: element, axApp: axApp)
#endif
    }

    /// Drop the cached verdict. Called when focus context changes (app switch, buffer reset), so a
    /// move from a username field to the password beside it can never be answered from the cache.
    static func invalidate() {
        cachedElement = nil
        cachedVerdict = nil
        cachedAt = .distantPast
    }

    /// Signal 4. Reuses the non-removable password-manager list that already hard-gates automatic
    /// conversion, so the two cannot drift apart.
    static func frontmostIsCredentialApp() -> SignalState {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return .no }
        return SignalState(AutoSwitchPolicy.protectedApps.contains(id))
    }

    // MARK: - The signals

    private static func evaluate(element: AXUIElement, axApp: AXUIElement) -> SecureFieldVerdict {
        let secure = IsSecureEventInputEnabled()
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""

        // Signal 1 — the canonical answer.
        let subroleSecure = (subrole == "AXSecureTextField")

        // Signal 2 — a text-entry element that *says* it is a password, masked or not.
        var labelled = false
        var matchedLabel = ""
        if textEntryRoles.contains(role) {
            for label in labels(of: element) where looksLikePassword(label) {
                labelled = true
                matchedLabel = label
                break
            }
        }

        let focus = "role=\(role.isEmpty ? "?" : role) subrole=\(subrole.isEmpty ? "-" : subrole)" +
                    (matchedLabel.isEmpty ? "" : " matched='\(matchedLabel)'")
        return SecureFieldVerdict(subroleSecure: SignalState(subroleSecure),
                                  labelledPassword: SignalState(labelled),
                                  secureInput: SignalState(secure),
                                  credentialApp: frontmostIsCredentialApp(),
                                  focusDescription: focus)
    }

    /// Roles that accept typed text. A non-text element cannot be a password box, and skipping the
    /// label reads for everything else keeps the common case to two AX round trips.
    private static let textEntryRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]

    /// Every string on the element that could carry a "password" label. `AXTitleUIElement` is the
    /// separate label control web and AppKit forms often use instead of a title on the field itself.
    private static func labels(of element: AXUIElement) -> [String] {
        var out: [String] = []
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute] {
            if let s = string(element, attr), !s.isEmpty { out.append(s) }
        }
        var labelRaw: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleUIElementAttribute as CFString, &labelRaw) == .success,
           let label = labelRaw, CFGetTypeID(label) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            let labelElement = label as! AXUIElement
            for attr in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let s = string(labelElement, attr), !s.isEmpty { out.append(s) }
            }
        }
        return out
    }

    /// Password wording in the languages this app's users are most likely to meet. The interface
    /// language is irrelevant here — the label comes from whatever page or app they are typing into.
    private static let passwordWords: [String] = [
        "password", "passwd", "passcode",
        "пароль",        // ru/uk/be
        "passwort",      // de
        "mot de passe",  // fr
        "contraseña",    // es
        "senha",         // pt
        "hasło",         // pl
        "密码", "パスワード", "비밀번호",
    ]

    static func looksLikePassword(_ label: String?) -> Bool {
        guard let label, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return passwordWords.contains { label.range(of: $0, options: .caseInsensitive) != nil }
    }

    // MARK: - Accessibility plumbing

    /// The focused element of the frontmost app, with the messaging timeout applied. Returns the
    /// app element too, so callers reuse the same bounded connection.
    private static func focusedElement() -> (AXUIElement, AXUIElement)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // Bounded: an unresponsive app must never stall the path in front of the next keystroke.
        AXUIElementSetMessagingTimeout(axApp, axTimeout)
        // Electron/Chromium build their accessibility tree lazily; without this they report no
        // focused element at all. That is not an edge case for this guard — browsers and Electron
        // apps are precisely where the unmasked/JS-masked login fields live, so skipping it would
        // leave signals 1 and 2 dead exactly where they matter. Same private attribute the caret
        // indicator already uses; idempotent, and a no-op on native apps.
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focusedRaw: AnyObject?
        let err = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRaw)
        guard err == .success, let focused = focusedRaw, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            // Not silent: a guard that cannot see the focused element cannot protect anything, and
            // the consequence (conversion proceeds) is exactly what we would want to know about.
            if err != .success {
                rslog("secure: focused element unavailable (AXError \(err.rawValue)) — treating as not-a-password")
            }
            return nil
        }
        // swiftlint:disable:next force_cast
        return (focused as! AXUIElement, axApp)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? String
    }
}
