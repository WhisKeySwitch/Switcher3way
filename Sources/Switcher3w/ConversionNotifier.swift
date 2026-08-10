import AppKit
import UserNotifications

/// The two things the app cannot say any other way: a rewrite it could not perform, and an offer to
/// remember a word after the user undoes a conversion. Everything else it does is visible where it
/// happens (the caret badge, the status icon), so this is deliberately limited — a layout fixer that
/// notified on success would be unusable.
///
/// Nothing here is load-bearing. Authorization is requested lazily on first use; a denial, a
/// registration failure or a delivery failure is logged and ignored. Conversion must never depend on
/// a notification being deliverable.
@MainActor
enum ConversionNotifier {

    /// Set by `AppDelegate` — appends the word to the never-convert list when the user taps the
    /// action button.
    static var onNeverConvert: ((String) -> Void)?

    private static let neverConvertAction = "switcher3w.neverConvert"
    private static let undoCategory = "switcher3w.undoOffer"
    private static let wordKey = "word"

    /// `UNUserNotificationCenter.current()` traps in a process with no bundle identifier — which is
    /// exactly how the package runs under `swift run` and how `diagpw` runs. Every entry point goes
    /// through this, so the non-bundled developer loop keeps working.
    private static var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    private static var authorized = false
    private static var authorizationAsked = false

    /// Registers the action category and the delegate. Safe to call when unbundled (does nothing).
    static func configure(delegate: UNUserNotificationCenterDelegate) {
        guard let center else {
            rslog("notify: unbundled process — notifications disabled")
            return
        }
        let action = UNNotificationAction(identifier: neverConvertAction,
                                          title: L10n.learnAdd,
                                          options: [])
        let category = UNNotificationCategory(identifier: undoCategory,
                                              actions: [action],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
        center.delegate = delegate
    }

    /// Asks for permission the first time we actually have something to say, rather than at launch:
    /// a menu-bar utility asking for notification access before it has ever needed one is noise.
    private static func withAuthorization(_ body: @escaping @MainActor () -> Void) {
        guard let center else { return }
        if authorized { return body() }
        guard !authorizationAsked else { return }   // asked and refused (or still pending)
        authorizationAsked = true
        center.requestAuthorization(options: [.alert]) { granted, error in
            Task { @MainActor in
                if let error {
                    // Ungated: if notifications are dead the user only ever sees silence, so the
                    // reason has to be recoverable from the log even with debug logging off.
                    logAlways("notify: authorization failed — \(error.localizedDescription)")
                    return
                }
                guard granted else {
                    logAlways("notify: authorization denied — errors and undo offers will be log-only")
                    return
                }
                authorized = true
                body()
            }
        }
    }

    // MARK: - Errors

    /// Throttle: a window that rejects every rewrite must not produce a stream of notifications.
    private static var lastErrorAt: Date = .distantPast
    private static let errorThrottle: TimeInterval = 30

    /// A failure the user would otherwise experience as the app silently doing nothing.
    static func reportRewriteFailure() {
        let now = Date()
        guard now.timeIntervalSince(lastErrorAt) >= errorThrottle else {
            rslog("notify: rewrite failure suppressed (throttled)")
            return
        }
        lastErrorAt = now
        rslog("notify: rewrite failure")
        withAuthorization {
            post(title: L10n.notifyErrorTitle, body: L10n.notifyCannotActHere, category: nil, userInfo: [:])
        }
    }

    // MARK: - Learn from undo

    /// After an undo: offer to leave this word alone in future. The word carried in the action is
    /// the form the never-convert rule matches on, so accepting suppresses exactly this conversion.
    static func offerNeverConvert(word: String) {
        guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        rslog("notify: offering never-convert (len=\(word.count))")
        withAuthorization {
            post(title: L10n.learnQuestion(word),
                 body: L10n.notifyUndoBody,
                 category: undoCategory,
                 userInfo: [wordKey: word])
        }
    }

    /// Handles the action button. Called from the app delegate's notification-center delegate.
    static func handle(response: UNNotificationResponse) {
        guard response.actionIdentifier == neverConvertAction,
              let word = response.notification.request.content.userInfo[wordKey] as? String,
              !word.isEmpty else { return }
        rslog("notify: never-convert accepted (len=\(word.count))")
        onNeverConvert?(word)
    }

    // MARK: - Delivery

    private static func post(title: String, body: String, category: String?, userInfo: [String: Any]) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { logAlways("notify: delivery failed — \(error.localizedDescription)") }
        }
    }
}
