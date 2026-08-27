import Foundation

/// One keystroke in the conversion buffer. For normal local input the keyCode is known
/// (char == nil). For input forwarded via remote desktop, Apple Screen Sharing
/// sends keyCode 0 + the character itself — then char != nil, and conversion goes by the
/// character, not by the useless keyCode 0 (keyCode 0 is what produced the runaway repeat).
public struct TypedKey: Sendable, Equatable {
    public let keyCode: UInt16
    public let shift: Bool
    public let caps: Bool
    public var char: Character?

    public init(keyCode: UInt16, shift: Bool, caps: Bool, char: Character? = nil) {
        self.keyCode = keyCode
        self.shift = shift
        self.caps = caps
        self.char = char
    }
}

/// An installed keyboard layout, reduced to what the detection logic needs. The platform type
/// (`TISInputSource` on macOS) stays behind `LayoutCatalog` so the core has no Carbon dependency.
public struct Layout: Sendable, Equatable {
    public let id: String
    /// 2-letter language code (ru/uk/en…).
    public let lang: String

    public init(id: String, lang: String) {
        self.id = id
        self.lang = lang
    }
}

/// Word validation in a language. Production is `NSSpellChecker`; tests supply a fixed word set,
/// so results never depend on which dictionaries the developer's machine happens to have.
/// (Mirrors `IDictionaryValidator` in the Windows port.)
@MainActor
public protocol DictionaryValidating {
    func isAvailable(_ lang: String) -> Bool
    func isValidWord(_ word: String, lang: String) -> Bool

    /// The language's letters, for generating the neighbours of a word in `TypoGuard.nearMiss`.
    /// Empty means "unknown", and the near-miss check simply does not run — which is why there is a
    /// default: a validator that cannot answer should not have to, and degrading to the previous
    /// behaviour is safer than vetoing everything.
    ///
    /// The Windows port takes this from the Hunspell dictionary's own `TRY` line. `NSSpellChecker`
    /// exposes nothing equivalent, so the macOS adapter derives it from the keyboard layout of that
    /// language — which is arguably the more honest source anyway: a language's letters are the
    /// letters its layout types.
    func alphabet(_ lang: String) -> String

    /// The language's vowels, for `WordShape.isPlausible` (the gibberish-rescue path). Same
    /// fail-open convention as `alphabet(_:)`: empty means "unknown", and the rescue simply does
    /// not run — a validator that cannot answer must not cause conversions.
    func vowels(_ lang: String) -> String
}

public extension DictionaryValidating {
    func alphabet(_ lang: String) -> String { "" }
    func vowels(_ lang: String) -> String { "" }
}

/// Installed layouts and how keystrokes render in them. Production wraps the TIS input-source
/// APIs; tests supply a fixed catalog. (Mirrors `ILayoutCatalog` in the Windows port.)
@MainActor
public protocol LayoutCatalog {
    func installedLayouts() -> [Layout]
    func currentLayoutID() -> String
    /// How the typed keycodes look in a specific layout, or nil when they cannot be rendered
    /// (no layout data, or characters forwarded through a remote desktop).
    func render(_ keys: [TypedKey], layoutID: String) -> String?
}

/// The user's word exception lists. (Mirrors `IAlwaysConvertList` and the never-convert check.)
@MainActor
public protocol WordExceptionList {
    /// An EXPLICIT override matched against the CONVERTED (target) form — the intended result, not
    /// the mistyped form, so a correctly typed word doesn't cause ping-pong.
    func isAlwaysConvert(_ converted: String) -> Bool
    /// Never convert — matched on either side of the pair.
    func isNeverConvert(_ typed: String, _ converted: String) -> Bool
}

/// Log sink for the core. The executable wires this to `rslog` at startup; in tests it stays a
/// no-op, so the core carries no file-I/O or UserDefaults dependency.
public enum CoreLog {
    nonisolated(unsafe) private static var sink: (@Sendable (String) -> Void)?

    public static func install(_ sink: @escaping @Sendable (String) -> Void) {
        Self.sink = sink
    }

    public static func write(_ message: String) {
        sink?(message)
    }
}
