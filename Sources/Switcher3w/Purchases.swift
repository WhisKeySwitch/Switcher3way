#if SWITCHER_APPSTORE
import Foundation
import Security
import StoreKit

/// What the user is currently allowed to do.
///
/// `unknown` is deliberately permissive. A paying customer locked out by a flaky network is a
/// worse outcome than someone getting a free session, and this app's failure mode is silence:
/// when it stops converting there is nothing on screen to explain why, so a wrong "expired" reads
/// as the app being broken.
enum Entitlement: Equatable {
    /// Inside the free trial, with this many whole days left (0 on the last day).
    case trial(daysRemaining: Int)
    /// Paid — subscription or lifetime unlock. Which one does not matter to the rest of the app.
    case purchased
    /// Trial is over and nothing is active.
    case expired
    /// Could not be determined this launch. Treated as allowed; re-checked.
    case unknown

    var allowsConversion: Bool {
        switch self {
        case .trial, .purchased, .unknown: return true
        case .expired: return false
        }
    }
}

/// Purchases and entitlement for the App Store build. Compiled out of the direct build entirely —
/// that channel is free and stays free.
@MainActor
final class Purchases {
    static let shared = Purchases()

    static let yearlyID = "site.ironmade.switcher3way.yearly"
    static let lifetimeID = "site.ironmade.switcher3way.lifetime"

    /// The trial runs in the app rather than as a StoreKit introductory offer. An offer would
    /// require the user to subscribe — payment details, confirmation sheet — before they had seen
    /// the app work once, which is a lot to ask for a utility at this price.
    static let trialDays = 14

    private(set) var entitlement: Entitlement = .unknown
    private(set) var products: [Product] = []

    /// Fires whenever the entitlement or the loaded products change, so the menu can redraw.
    var onChange: (() -> Void)?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        // Transactions can arrive at any time — a purchase made on another Mac, a subscription
        // renewing, a refund. Listening for the lifetime of the process is what StoreKit expects.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { await refresh() }
        Task { await loadProducts() }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Entitlement

    func refresh() async {
        let resolved = await resolveEntitlement()
        guard resolved != entitlement else { return }
        entitlement = resolved
        rslog("purchases: entitlement = \(resolved)")
        onChange?()
    }

    private func resolveEntitlement() async -> Entitlement {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiry = transaction.expirationDate, expiry < Date() { continue }
            if transaction.productID == Self.lifetimeID || transaction.productID == Self.yearlyID {
                return .purchased
            }
        }
        // Nothing owned. Fall back to the trial clock.
        guard let started = TrialClock.startDate() else {
            // First run we have ever seen: start the clock now.
            TrialClock.begin()
            return .trial(daysRemaining: Self.trialDays)
        }
        let elapsed = Calendar.current.dateComponents([.day], from: started, to: Date()).day ?? 0
        let left = Self.trialDays - elapsed
        return left > 0 ? .trial(daysRemaining: left) : .expired
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: [Self.yearlyID, Self.lifetimeID])
            // Cheapest first, so the purchase UI reads in a predictable order regardless of what
            // the store hands back.
            products = loaded.sorted { $0.price < $1.price }
            onChange?()
        } catch {
            // Offline, or the products are not yet approved. Not fatal: the app keeps working on
            // whatever entitlement it already resolved.
            rslog("purchases: product load failed — \(error.localizedDescription)")
        }
    }

    func product(for id: String) -> Product? { products.first { $0.id == id } }

    // MARK: - Buying

    enum PurchaseOutcome { case bought, cancelled, pending, failed(String) }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                    return .bought
                }
                // Signed by something that is not Apple. Do not grant anything.
                rslog("purchases: unverified transaction refused")
                return .failed("could not be verified")
            case .userCancelled:
                return .cancelled
            case .pending:
                // Ask to Buy, or payment needing approval. The entitlement arrives later through
                // Transaction.updates; nothing to do but wait.
                return .pending
            @unknown default:
                return .failed("unrecognised result")
            }
        } catch {
            rslog("purchases: purchase failed — \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    /// For the customer who already paid and is on a new Mac, or reinstalled.
    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
        } catch {
            rslog("purchases: restore failed — \(error.localizedDescription)")
        }
    }
}

/// When the trial started.
///
/// Kept in the keychain so that deleting and reinstalling the app does not silently hand out a
/// fresh trial — the sandbox container goes with the app, the keychain item does not. Falls back
/// to defaults if the keychain refuses, which it can before a provisioning profile is embedded:
/// a trial that resets is a much smaller problem than a trial that never starts.
private enum TrialClock {
    private static let service = "site.ironmade.switcher3way.trial"
    private static let account = "firstLaunch"
    private static let defaultsKey = "com.switcher3w.trialStarted"

    static func startDate() -> Date? {
        if let stamp = keychainRead(), let t = TimeInterval(stamp) {
            return Date(timeIntervalSince1970: t)
        }
        let stored = UserDefaults.standard.double(forKey: defaultsKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    static func begin() {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: defaultsKey)
        keychainWrite(String(now))
        rslog("purchases: trial clock started")
    }

    private static func keychainRead() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ value: String) {
        let data = Data(value.utf8)
        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            rslog("purchases: keychain write refused (\(status)) — using defaults")
        }
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
#endif  // SWITCHER_APPSTORE
