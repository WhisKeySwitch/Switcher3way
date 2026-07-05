import AppKit
import WebKit

/// Окно встроенной справки: показывает руководство пользователя, собранное на этапе
/// сборки из docs/user-guide*.md в Resources/help/ (см. scripts/md2html.py).
/// Язык выбирается по языку интерфейса приложения при каждом открытии;
/// офлайн по построению — приложение вообще не ходит в сеть.
@MainActor
final class HelpWindowController: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?

    func show() {
        if window == nil { buildWindow() }
        window?.title = L10n.menuHelp
        loadCurrentGuide()   // язык мог смениться с прошлого открытия
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
        // Доступ на чтение ко всей папке help/ — чтобы работали перекрёстные ссылки между языками
        webView?.loadFileURL(file, allowingReadAccessTo: helpDir)
    }

    /// Руководство есть на en/uk/ru; остальные 13 языков интерфейса читают английское.
    static func guideFileName(for lang: String) -> String {
        switch lang {
        case "uk": return "user-guide.uk.html"
        case "ru": return "user-guide.ru.html"
        default:   return "user-guide.en.html"
        }
    }

    // MARK: - WKNavigationDelegate

    /// Внешние ссылки — в браузер по умолчанию; внутри окна остаются только
    /// file-URL из бандла (само руководство, его якоря и переводы).
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
