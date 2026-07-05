import AppKit

/// Grouped-form primitives in the System Settings style (W1–W3):
/// a white rounded "box" with hairline separators between rows.
/// Used by the Settings tabs and the onboarding checklist.
@MainActor
final class FormBox: NSView {
    private let stack = NSStackView()

    // NSBox won't do: its contentView is positioned via autoresizing, and the box's
    // height isn't derived from the content constraints (rows collapse into a mess).
    // So we draw the background/border with a layer on a plain NSView, and the stack is
    // pinned to the edges — the box's height honestly equals the sum of the rows.
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Colors via updateLayer — repaints correctly when switching light/dark theme.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Adds a row; before every row except the first — a hairline separator.
    func addRow(_ row: NSView) {
        if !stack.arrangedSubviews.isEmpty {
            let sep = NSBox()
            sep.boxType = .separator
            sep.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(sep)
            sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// Factories for common form elements (rows, section headers, footnotes, badges).
@MainActor
enum FormUI {
    /// Row "text on the left — control on the right". subtitle — a smaller gray second line (optional).
    static func row(title: String, subtitle: String? = nil, titleBold: Bool = false,
                    badge: String? = nil, control: NSView?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = titleBold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Title (+ optional BETA badge) in a horizontal stack
        let titleStack = NSStackView()
        titleStack.orientation = .horizontal
        titleStack.spacing = 6
        titleStack.alignment = .centerY
        titleStack.addArrangedSubview(titleLabel)
        if let badge { titleStack.addArrangedSubview(betaBadge(badge)) }

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleStack)
        if let subtitle {
            let sub = NSTextField(wrappingLabelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            sub.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textStack.addArrangedSubview(sub)
        }
        row.addSubview(textStack)

        var constraints = [
            textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
            textStack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -9),
        ]
        if let control {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            control.setContentHuggingPriority(.required, for: .horizontal)
            row.addSubview(control)
            constraints += [
                control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                // A control taller than the text (popups) must not overflow the row
                control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 6),
                control.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -6),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -12),
            ]
        } else {
            constraints.append(textStack.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -12))
        }
        NSLayoutConstraint.activate(constraints)
        return row
    }

    /// Section header: uppercase in small bold gray, as in System Settings.
    static func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Footnote below a section — small gray, wrapping.
    static func footnote(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    /// A "pill" frame that repaints on theme change (for badges).
    private final class PillView: NSView {
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            layer?.cornerRadius = 7
        }
    }

    /// A "pill" badge (BETA / always off): frame, uppercase, small font.
    static func betaBadge(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let pill = PillView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.wantsLayer = true
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -1),
        ])
        return pill
    }

    /// NSSwitch bound to an action; initial state — from isOn.
    static func makeSwitch(isOn: Bool, target: AnyObject?, action: Selector) -> NSSwitch {
        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = target
        sw.action = action
        sw.controlSize = .small
        return sw
    }
}
