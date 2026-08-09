import AppKit
import Carbon
import Switcher3wCore

/// Word checking against the system dictionary (NSSpellChecker) — locally, without dependencies,
/// without network and without a data bundle. ~0.1ms per check, 40+ languages.
enum Dict {
    @MainActor private static let checker = NSSpellChecker.shared

    @MainActor static func isAvailable(_ lang: String) -> Bool {
        let two = String(lang.prefix(2))
        return checker.availableLanguages.contains { String($0.prefix(2)) == two }
    }

    /// true — the word is in the language's dictionary (spelling is correct).
    @MainActor static func isValidWord(_ word: String, lang: String) -> Bool {
        let range = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                          wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
}

enum LayoutVerdict { case switchToConverted, keep, undecided }

/// Decides whether a word was typed in the wrong layout. Precision matters more than recall:
/// on any uncertainty → .undecided (we do nothing). The manual trigger remains.
enum LayoutDetector {
    @MainActor
    static func decide(typed: String, converted: String, currentLang: String, otherLang: String, capsLock: Bool) -> LayoutVerdict {
        // always-convert — an EXPLICIT override: we match against the CONVERTED (target) form.
        // The target word is put in the list (the intended result, not the mistyped form); this way a correctly typed word
        // doesn't cause ping-pong. Hard gates (secure/denied-app/never) are checked BEFORE decide.
        if AutoSwitchPolicy.isAlwaysConvert(converted) { return .switchToConverted }

        // --- soft vetoes (cheap, before the dictionary) ---
        guard SoftGates.passes(typed, capsLock: capsLock) else { return .undecided }

        let cur = String(currentLang.prefix(2))
        let oth = String(otherLang.prefix(2))

        // Dictionary — case-insensitive (Caps Lock must not interfere with word detection).
        guard Dict.isAvailable(oth) else { return .undecided }
        guard Dict.isValidWord(converted.lowercased(), lang: oth) else { return .keep }
        if Dict.isAvailable(cur), Dict.isValidWord(typed.lowercased(), lang: cur) {
            return .keep
        }
        return .switchToConverted
    }

    /// Soft vetoes now live in `SoftGates` (Switcher3wCore) so they are unit-testable and shared
    /// verbatim with the N-way resolver. Kept as a forwarding name for the 2-way call site above.
    static func passesSoftGates(_ typed: String, capsLock: Bool) -> Bool {
        SoftGates.passes(typed, capsLock: capsLock)
    }
}

/// Security policy for auto-conversion.
enum AutoSwitchPolicy {
    /// Whether secure input is active (a password field, Secure Keyboard Entry in a terminal) —
    /// then we do NOT do auto-conversion (privacy; we don't touch the password).
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    /// Default list of apps where auto is disabled: terminals, IDEs, password
    /// managers. Returned until the user has edited the list
    /// (see SettingsManager.deniedApps). An entry with a "*" suffix is a prefix (the whole vendor).
    static let defaultDeniedApps: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
        "io.alacritty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.sublimetext.4", "com.todesktop.230313mzl4w4u92", "com.google.android.studio",
        "com.jetbrains.*",
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc",
    ]

    /// Password managers — non-removable from the list in the UI (security).
    static let protectedApps: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc",
    ]

    static func isDeniedApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        // Password managers — a hard gate independent of the user's list:
        // they can't be unlocked either through the UI or through a defaults desync.
        if protectedApps.contains(id) { return true }
        for entry in SettingsManager.shared.deniedApps {
            if entry.hasSuffix("*") {
                if id.hasPrefix(String(entry.dropLast())) { return true }
            } else if entry == id {
                return true
            }
        }
        return false
    }

    /// A word in the never-convert list (both sides of the pair, case-insensitive).
    static func isDeniedWord(_ typed: String, _ converted: String) -> Bool {
        let set = SettingsManager.shared.deniedWordsSet
        guard !set.isEmpty else { return false }
        return set.contains(typed.lowercased()) || set.contains(converted.lowercased())
    }

    /// A word in the always-convert list — we match against the CONVERTED (target) form.
    /// The "target" word is put in the list (what should result), not layout garbage —
    /// otherwise a correctly typed word would be converted back (ping-pong).
    static func isAlwaysConvert(_ converted: String) -> Bool {
        let set = SettingsManager.shared.alwaysConvertWordsSet
        guard !set.isEmpty else { return false }
        return set.contains(converted.lowercased())
    }

    /// Remote desktop clients: when such a window is focused, the text lives
    /// on ANOTHER machine — our instance must stay silent and defer to the remote Switcher3way.
    static let remoteClients: Set<String> = [
        "com.apple.ScreenSharing",   // Apple "Screen Sharing" / Screen Sharing.app
        "com.apple.RemoteDesktop",   // Apple Remote Desktop
    ]

    static func isRemoteDesktopClient(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return remoteClients.contains(id)
    }

    /// The "defer to the remote desktop" rule: remote desktop mode is enabled AND a remote desktop
    /// client is focused → this instance does nothing (neither trigger nor auto), so as not to
    /// duplicate the work of the instance on the controlled machine.
    static var shouldDeferToRemoteClient: Bool {
        guard SettingsManager.shared.remoteDesktopMode else { return false }
        return isRemoteDesktopClient(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
