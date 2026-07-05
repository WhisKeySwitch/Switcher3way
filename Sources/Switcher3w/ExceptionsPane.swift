import AppKit
import UniformTypeIdentifiers

/// Unified exceptions list (W2): one NSTableView, a segmented filter with live
/// counts (Apps / Never / Always), search, and explicit add/remove buttons.
/// Replaces the three separate ExceptionListEditors from the former tab.
@MainActor
final class ExceptionsPane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    /// Adapter for a single list: data binding via closures, like the old editor.
    private struct Adapter {
        enum Kind { case apps, words }
        let kind: Kind
        let segmentTitle: () -> String
        let get: () -> [String]
        let set: ([String]) -> Void
        let isProtected: (String) -> Bool
    }

    private var adapters: [Adapter] = []
    private var activeIndex = 0
    private var items: [String] = []          // filtered visible list
    private var query = ""

    private let segments = NSSegmentedControl()
    private let searchField = NSSearchField()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private let table = NSTableView()
    /// Name/icon cache keyed by bundle id, to avoid hitting NSWorkspace on every cell vend.
    private var infoCache: [String: (text: String, icon: NSImage?)] = [:]

    override init() {
        super.init()
        adapters = [
            Adapter(kind: .apps,
                    segmentTitle: { L10n.settingsSegApps },
                    get: { SettingsManager.shared.deniedApps },
                    set: { SettingsManager.shared.deniedApps = $0 },
                    isProtected: { AutoSwitchPolicy.protectedApps.contains($0) }),
            Adapter(kind: .words,
                    segmentTitle: { L10n.settingsSegNever },
                    get: { SettingsManager.shared.deniedWords },
                    set: { SettingsManager.shared.deniedWords = $0 },
                    isProtected: { _ in false }),
            Adapter(kind: .words,
                    segmentTitle: { L10n.settingsSegAlways },
                    get: { SettingsManager.shared.alwaysConvertWords },
                    set: { SettingsManager.shared.alwaysConvertWords = $0 },
                    isProtected: { _ in false }),
        ]
    }

    /// Builds the section view: segments → search/add row → table → footnote.
    func makeView() -> NSView {
        segments.segmentCount = adapters.count
        segments.segmentStyle = .texturedRounded
        segments.target = self
        segments.action = #selector(segmentChanged)
        segments.selectedSegment = 0
        segments.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = L10n.settingsSearch
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        addButton.bezelStyle = .rounded
        addButton.controlSize = .regular
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        removeButton.title = "−"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.isEnabled = false
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        let toolbarRow = NSStackView(views: [searchField, addButton, removeButton])
        toolbarRow.orientation = .horizontal
        toolbarRow.spacing = 6
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col"))
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table

        let footer = FormUI.footnote(L10n.settingsExceptionsFooter)
        footer.translatesAutoresizingMaskIntoConstraints = false

        let root = NSStackView(views: [segments, toolbarRow, scroll, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            segments.widthAnchor.constraint(equalTo: root.widthAnchor),
            toolbarRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 190),
        ])

        reload()
        return root
    }

    // MARK: - Data

    private var adapter: Adapter { adapters[activeIndex] }

    /// Re-reads the active list, applies the filter, and updates the segment counts.
    private func reload() {
        let all = adapter.get()
        if query.isEmpty {
            items = all
        } else {
            let q = query.lowercased()
            items = all.filter {
                $0.lowercased().contains(q) || displayText($0).lowercased().contains(q)
            }
        }
        for (i, a) in adapters.enumerated() {
            segments.setLabel("\(a.segmentTitle()) (\(a.get().count))", forSegment: i)
        }
        addButton.title = adapter.kind == .apps ? "+ \(L10n.settingsAddApp)" : "+ \(L10n.settingsAddWord)"
        table.reloadData()
        updateRemoveButton()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = items[row]
        let info = cellInfo(id)
        let cell = NSTableCellView()

        let text = NSTextField(labelWithString: info.text)
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(text)

        var leading: CGFloat = 4
        if adapter.kind == .apps, let icon = info.icon {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
            ])
            leading = 24
        }

        // On the right: for protected entries — an explicit "always off" badge instead of
        // unclear gray text; for regular apps — the bundle id in small gray.
        var trailingView: NSView?
        if adapter.isProtected(id) {
            trailingView = FormUI.betaBadge("🔒 \(L10n.settingsAlwaysOff)")
        } else if adapter.kind == .apps {
            let sub = NSTextField(labelWithString: id)
            sub.font = .systemFont(ofSize: 10)
            sub.textColor = .tertiaryLabelColor
            sub.lineBreakMode = .byTruncatingMiddle
            trailingView = sub
        }

        var textTrailing = cell.trailingAnchor
        if let tv = trailingView {
            tv.translatesAutoresizingMaskIntoConstraints = false
            tv.setContentCompressionResistancePriority(.required, for: .horizontal)
            cell.addSubview(tv)
            NSLayoutConstraint.activate([
                tv.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                tv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            textTrailing = tv.leadingAnchor
        }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading),
            text.trailingAnchor.constraint(lessThanOrEqualTo: textTrailing, constant: -8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }

    private func updateRemoveButton() {
        let row = table.selectedRow
        removeButton.isEnabled = row >= 0 && row < items.count && !adapter.isProtected(items[row])
    }

    // MARK: - Actions

    @objc private func segmentChanged() {
        activeIndex = segments.selectedSegment
        query = ""
        searchField.stringValue = ""
        infoCache.removeAll()   // display depends on the list type (apps/words)
        reload()
    }

    @objc private func searchChanged() {
        query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        reload()
    }

    @objc private func addTapped() {
        switch adapter.kind {
        case .apps: addApp()
        case .words: addWord()
        }
    }

    @objc private func removeTapped() {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return }
        let value = items[row]
        guard !adapter.isProtected(value) else { return }
        var all = adapter.get()                 // re-sync with the live store (learn-from-undo etc.)
        all.removeAll { $0 == value }           // remove by value, not by a stale index
        adapter.set(all)
        reload()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        var all = adapter.get()
        guard !all.contains(id) else { return }
        all.append(id)
        adapter.set(all)
        reload()
    }

    private func addWord() {
        let alert = NSAlert()
        alert.messageText = L10n.settingsAddWordPrompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.commonAdd)
        alert.addButton(withTitle: L10n.commonCancel)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let word = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        var all = adapter.get()
        guard !word.isEmpty,
              !all.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        all.append(word)
        adapter.set(all)
        reload()
    }

    // MARK: - Display

    private func cellInfo(_ id: String) -> (text: String, icon: NSImage?) {
        if let cached = infoCache[id] { return cached }
        let info = (text: displayText(id), icon: adapter.kind == .apps ? appIcon(id) : nil)
        infoCache[id] = info
        return info
    }

    private func displayText(_ id: String) -> String {
        guard adapter.kind == .apps else { return id }
        if id.hasSuffix("*") { return String(id.dropLast()) + "* (все)" }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            // FileManager.displayName is localized by the SYSTEM; when the app's interface
            // language differs, we take the neutral bundle name from disk ("Terminal").
            if L10n.namesFollowSystem {
                let name = FileManager.default.displayName(atPath: url.path)
                return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
            }
            return url.deletingPathExtension().lastPathComponent
        }
        return id
    }

    private func appIcon(_ id: String) -> NSImage? {
        guard !id.hasSuffix("*"),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
