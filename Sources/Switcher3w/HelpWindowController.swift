import AppKit
import WebKit

/// Built-in help window: shows the user guide, compiled at build time
/// from docs/user-guide*.md into Resources/help/ (see scripts/md2html.py).
/// The language is chosen by the app's interface language on every open;
/// offline by construction — the app never touches the network.
@MainActor
final class HelpWindowController: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?

    func show() {
        if window == nil { buildWindow() }
        window?.title = L10n.menuHelp
        loadCurrentGuide()   // the language may have changed since the last open
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = self
        webView = web

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 820),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.contentView = web
        win.minSize = NSSize(width: 420, height: 400)
        win.center()
        win.isReleasedWhenClosed = false
        window = win
    }

    private func loadCurrentGuide() {
        guard let helpDir = Bundle.main.resourceURL?.appendingPathComponent("help", isDirectory: true) else {
            rslog("help: no resource URL")
            return
        }
        let file = helpDir.appendingPathComponent(Self.guideFileName(for: L10n.effectiveLanguage))
        guard FileManager.default.fileExists(atPath: file.path) else {
            rslog("help: bundled guide missing at \(file.path)")
            return
        }
        // Read access to the whole help/ folder — so cross-language links work
        webView?.loadFileURL(file, allowingReadAccessTo: helpDir)
    }

    /// The guide exists in en/uk/ru; the other 13 interface languages read the English one.
    static func guideFileName(for lang: String) -> String {
        switch lang {
        case "uk": return "user-guide.uk.html"
        case "ru": return "user-guide.ru.html"
        default:   return "user-guide.en.html"
        }
    }

    // MARK: - WKNavigationDelegate

    /// External links — to the default browser; only file URLs from the bundle
    /// (the guide itself, its anchors, and translations) stay inside the window.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
