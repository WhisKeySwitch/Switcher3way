import Foundation

/// The text the update alert shows under "a new version is available".
///
/// A GitHub release has one description, written for the release page: markdown, English, and as
/// long as it needs to be. The alert is none of those — `NSAlert` renders plain text, the reader
/// may be Ukrainian, and the box holds a few paragraphs. Shown raw it read `## It now tells you…`
/// and stopped mid-word ("It now says so at th"). So the release's `version.json` may carry
/// `notes` — plain text per interface language — and the release description is only the fallback,
/// cleaned up. Copies that predate this read only `sha256` from that file, so the extra key costs
/// them nothing; they show the first 700 characters of the description, which is why a release
/// description should open with a plain summary shorter than that.
enum ReleaseNotes {

    /// About what the alert's text box holds before it starts to scroll awkwardly.
    static let limit = 700

    /// The notes for `language`: its own entry, else English, else the cleaned description.
    static func text(localized: [String: String], body: String, language: String) -> String {
        let own = localized[language]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let english = localized["en"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = !own.isEmpty ? own : !english.isEmpty ? english : plainText(fromMarkdown: body)
        return truncated(chosen)
    }

    /// `notes` from a `version.json` manifest; empty when absent or malformed.
    static func localized(fromManifest data: Data) -> [String: String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let notes = obj["notes"] as? [String: String] else { return [:] }
        return notes
    }

    /// Markdown as the alert can show it: no heading marks, emphasis, code ticks, rules, comments
    /// or link targets; list items as bullets.
    static func plainText(fromMarkdown md: String) -> String {
        var s = md.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        let lines = s.components(separatedBy: "\n").compactMap { raw -> String? in
            var line = raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil { return nil }
            line = line.replacingOccurrences(of: "^\\s{0,3}#{1,6}\\s+", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^(\\s*)[-*+]\\s+", with: "$1• ", options: .regularExpression)
            for mark in ["**", "__", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
            return line
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// At most `limit` characters, ending on a paragraph — else a sentence, else a word — never
    /// mid-word.
    static func truncated(_ text: String, limit: Int = limit) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let floor = head.index(head.startIndex, offsetBy: limit / 3)
        for separator in ["\n\n", ". ", " "] {
            if let r = head.range(of: separator, options: .backwards), r.lowerBound > floor {
                let end = separator == ". " ? head.index(after: r.lowerBound) : r.lowerBound
                return String(head[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + " …"
            }
        }
        return head + "…"
    }
}
