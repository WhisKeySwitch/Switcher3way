#if SWITCHER_APPSTORE
import AppKit
import StoreKit

/// The window the purchase happens in.
///
/// Not a nicety. This app is `LSUIElement` — no Dock icon, no windows — and StoreKit's purchase
/// sheet has to attach itself to one. Called with nothing on screen, `Product.purchase()` never
/// returns: the menu closes, no sheet appears, and the app looks like it ignored the click. That
/// is exactly what happened, and it left no trace until the attempt was recorded before the call.
///
/// So the window exists to be something the sheet can hang from — and, having to exist anyway, it
/// is also the one place with room to say what is being bought and why one option might suit
/// someone better than the other, which two priced menu rows could never do.
@MainActor
final class PurchaseWindowController {
    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var rows: NSStackView?

    func show() {
        if window == nil { build() }
        refreshContents()
        // An agent app is not in the responder chain until it asks to be. Without this the window
        // appears behind whatever the user was typing in, which for a purchase prompt reads as the
        // app having done nothing at all.
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L10n.purchaseWindowTitle
        w.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: L10n.purchaseWindowHeading)
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(heading)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byWordWrapping
        status.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(status)
        statusLabel = status

        let productRows = NSStackView()
        productRows.orientation = .vertical
        productRows.alignment = .leading
        productRows.spacing = 10
        stack.addArrangedSubview(productRows)
        rows = productRows

        let restore = NSButton(title: L10n.purchaseRestore, target: self,
                               action: #selector(restoreTapped))
        restore.bezelStyle = .inline
        stack.addArrangedSubview(restore)

        w.contentView?.addSubview(stack)
        if let cv = w.contentView {
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: cv.topAnchor),
                stack.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: cv.bottomAnchor),
            ])
        }
        window = w
    }

    func refreshContents() {
        statusLabel?.stringValue = statusText()
        guard let rows else { return }
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for product in Purchases.shared.products {
            rows.addArrangedSubview(row(for: product))
        }
    }

    private func statusText() -> String {
        switch Purchases.shared.entitlement {
        case .trial(let days): return L10n.purchaseTrialDaysLeft(days)
        case .expired: return L10n.purchaseExpired
        case .purchased: return L10n.purchaseThanks
        case .unknown: return ""
        }
    }

    private func row(for product: Product) -> NSView {
        let line = NSStackView()
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 12

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let name = NSTextField(labelWithString: product.displayName)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = NSTextField(labelWithString: product.description)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        text.addArrangedSubview(name)
        text.addArrangedSubview(detail)
        line.addArrangedSubview(text)

        let buy = NSButton(title: product.displayPrice, target: self, action: #selector(buyTapped(_:)))
        buy.bezelStyle = .rounded
        buy.identifier = NSUserInterfaceItemIdentifier(product.id)
        // Already paid: nothing left to buy, but the row stays so the window still explains what
        // was bought rather than going blank.
        buy.isEnabled = Purchases.shared.entitlement != .purchased
        line.addArrangedSubview(buy)
        return line
    }

    @objc private func buyTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let product = Purchases.shared.product(for: id),
              let window else { return }
        sender.isEnabled = false
        Task {
            _ = await Purchases.shared.purchase(product, confirmIn: window)
            refreshContents()
        }
    }

    @objc private func restoreTapped() {
        Task {
            await Purchases.shared.restore()
            refreshContents()
        }
    }
}
#endif  // SWITCHER_APPSTORE
