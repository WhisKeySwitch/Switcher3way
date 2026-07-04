import AppKit

/// Примитивы сгруппированной формы в стиле Системных настроек (W1–W3):
/// белая «коробка» со скруглением и волосяными разделителями между строками.
/// Используется вкладками настроек и чек-листом онбординга.
@MainActor
final class FormBox: NSView {
    private let stack = NSStackView()

    // NSBox не годится: его contentView позиционируется авторесайзингом, и высота
    // коробки не выводится из констрейнтов содержимого (строки схлопываются в кашу).
    // Поэтому рисуем фон/рамку слоем на обычном NSView, а стек пиннится к краям —
    // высота коробки честно равна сумме строк.
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

    // Цвета через updateLayer — корректно перекрашивается при смене светлой/тёмной темы.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Добавляет строку; перед каждой строкой кроме первой — волосяной разделитель.
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

/// Фабрики типовых элементов формы (строки, заголовки секций, сноски, бейджи).
@MainActor
enum FormUI {
    /// Строка «текст слева — контрол справа». subtitle — вторая серым мельче (опционально).
    static func row(title: String, subtitle: String? = nil, titleBold: Bool = false,
                    badge: String? = nil, control: NSView?) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = titleBold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Заголовок (+ опциональный бейдж BETA) в горизонтальном стеке
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
                // Контрол выше текста (попапы) не должен вылезать за строку
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

    /// Заголовок секции: капс мелким жирным серым, как в Системных настройках.
    static func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Сноска под секцией — мелкая серая, с переносом.
    static func footnote(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .tertiaryLabelColor
        return label
    }

    /// Рамка-«пилюля» с перекраской при смене темы (для бейджей).
    private final class PillView: NSView {
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
            layer?.cornerRadius = 7
        }
    }

    /// Бейдж-«пилюля» (BETA / always off): рамка, капс, мелкий шрифт.
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

    /// NSSwitch, привязанный к action; начальное состояние — из isOn.
    static func makeSwitch(isOn: Bool, target: AnyObject?, action: Selector) -> NSSwitch {
        let sw = NSSwitch()
        sw.state = isOn ? .on : .off
        sw.target = target
        sw.action = action
        sw.controlSize = .small
        return sw
    }
}
