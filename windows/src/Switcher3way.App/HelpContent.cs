using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Switcher3way.App;

/// <summary>
/// Renders the bundled user guide (docs/user-guide*.md, embedded) to a styled HTML page for the
/// in-app <see cref="HelpWindow"/>. A faithful C# port of scripts/md2html.py — the Markdown guides
/// stay the single source of truth and are converted at runtime, so the built-in help needs no
/// browser link and no external dependency. Supports exactly the subset the guides use: h1–h3,
/// **bold**, *italic*, `code`, links, bullet lists, tables, blockquotes, fenced code.
/// </summary>
internal static class HelpContent
{
    // Cross-guide links (the "also available in" line) become a "help:" scheme the Help window
    // intercepts to switch language in place instead of navigating to a missing file.
    private static readonly Dictionary<string, string> GuideLinks = new()
    {
        ["user-guide.md"] = "help:en",
        ["user-guide.uk.md"] = "help:uk",
        ["user-guide.ru.md"] = "help:ru",
    };

    private static readonly Dictionary<string, string> Resources = new()
    {
        ["en"] = "user-guide.md",
        ["uk"] = "user-guide.uk.md",
        ["ru"] = "user-guide.ru.md",
    };

    /// <summary>Full HTML page for the guide in the given language (falls back to English).</summary>
    public static string Render(string lang)
    {
        if (!Resources.TryGetValue(lang, out var res)) { lang = "en"; res = Resources["en"]; }
        var md = ReadResource(res) ?? ReadResource(Resources["en"]) ?? "# Switcher3way\n\nUser guide unavailable.";
        var (title, body) = Convert(md);
        return Template(lang, Esc(title), body);
    }

    private static string? ReadResource(string logicalName)
    {
        try
        {
            using var s = typeof(HelpContent).Assembly.GetManifestResourceStream(logicalName);
            if (s is null) return null;
            using var r = new StreamReader(s, Encoding.UTF8);
            return r.ReadToEnd();
        }
        catch { return null; }
    }

    // ---- Markdown subset → HTML (ported from md2html.py) ------------------------------------
    private static string Esc(string s) => s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    private static string Slugify(string text)
    {
        text = Regex.Replace(text.ToLowerInvariant(), @"[^\w\s-]", ""); // \w is Unicode in .NET → Cyrillic anchors survive
        return Regex.Replace(text.Trim(), @"\s", "-");
    }

    private static string Inline(string text)
    {
        var parts = Regex.Split(text, "(`[^`]+`)"); // order: code → links → bold → italic
        var sb = new StringBuilder();
        foreach (var part in parts)
        {
            if (part.Length > 2 && part.StartsWith('`') && part.EndsWith('`'))
            {
                sb.Append("<code>").Append(Esc(part[1..^1])).Append("</code>");
                continue;
            }
            var p = Esc(part);
            p = Regex.Replace(p, @"\[([^\]]+)\]\(([^)\s]+)\)", m =>
            {
                var href = m.Groups[2].Value;
                if (GuideLinks.TryGetValue(href, out var mapped)) href = mapped;
                return $"<a href=\"{href}\">{m.Groups[1].Value}</a>";
            });
            p = Regex.Replace(p, @"\*\*([^*]+)\*\*", "<strong>$1</strong>");
            p = Regex.Replace(p, @"(?<!\w)\*([^*]+)\*(?!\w)", "<em>$1</em>");
            sb.Append(p);
        }
        return sb.ToString();
    }

    private static (string title, string body) Convert(string md)
    {
        var lines = md.Replace("\r\n", "\n").Split('\n');
        var outp = new List<string>();
        int i = 0;
        bool inList = false, inQuote = false;
        string title = "";

        void CloseBlocks()
        {
            if (inList) { outp.Add("</ul>"); inList = false; }
            if (inQuote) { outp.Add("</blockquote>"); inQuote = false; }
        }

        while (i < lines.Length)
        {
            var stripped = lines[i].Trim();

            if (stripped.StartsWith("```"))
            {
                CloseBlocks();
                i++;
                var code = new List<string>();
                while (i < lines.Length && !lines[i].Trim().StartsWith("```")) { code.Add(lines[i]); i++; }
                outp.Add("<pre><code>" + Esc(string.Join("\n", code)) + "</code></pre>");
                i++;
                continue;
            }

            var m = Regex.Match(stripped, @"^(#{1,3}) (.*)$");
            if (m.Success)
            {
                CloseBlocks();
                int level = m.Groups[1].Value.Length;
                var text = m.Groups[2].Value;
                if (level == 1 && title.Length == 0) title = text;
                outp.Add($"<h{level} id=\"{Slugify(text)}\">{Inline(text)}</h{level}>");
                i++;
                continue;
            }

            if (stripped.StartsWith("|"))
            {
                CloseBlocks();
                var rows = new List<string[]>();
                while (i < lines.Length && lines[i].Trim().StartsWith("|"))
                {
                    var cells = lines[i].Trim().Trim('|').Split('|');
                    for (int c = 0; c < cells.Length; c++) cells[c] = cells[c].Trim();
                    rows.Add(cells);
                    i++;
                }
                outp.Add("<table>");
                for (int r = 0; r < rows.Count; r++)
                {
                    if (r == 1 && rows[r].All(c => Regex.IsMatch(c, @"^:?-+:?$"))) continue; // separator row
                    var tag = r == 0 ? "th" : "td";
                    var sb = new StringBuilder();
                    foreach (var c in rows[r]) sb.Append($"<{tag}>{Inline(c)}</{tag}>");
                    outp.Add($"<tr>{sb}</tr>");
                }
                outp.Add("</table>");
                continue;
            }

            if (stripped.StartsWith("- "))
            {
                if (inQuote) { outp.Add("</blockquote>"); inQuote = false; }
                if (!inList) { outp.Add("<ul>"); inList = true; }
                var item = stripped[2..];
                while (i + 1 < lines.Length && lines[i + 1].StartsWith("  ") && lines[i + 1].Trim().Length > 0
                       && !lines[i + 1].Trim().StartsWith("- "))
                {
                    i++;
                    item += " " + lines[i].Trim();
                }
                outp.Add("<li>" + Inline(item) + "</li>");
                i++;
                continue;
            }

            if (stripped.StartsWith(">"))
            {
                if (inList) { outp.Add("</ul>"); inList = false; }
                if (!inQuote) { outp.Add("<blockquote>"); inQuote = true; }
                outp.Add("<p>" + Inline(stripped.TrimStart('>', ' ')) + "</p>");
                i++;
                continue;
            }

            if (stripped.Length == 0) { CloseBlocks(); i++; continue; }

            CloseBlocks();
            var para = new List<string> { stripped };
            while (i + 1 < lines.Length && lines[i + 1].Trim().Length > 0
                   && !Regex.IsMatch(lines[i + 1].Trim(), @"^(#|\||- |>|```)"))
            {
                i++;
                para.Add(lines[i].Trim());
            }
            outp.Add("<p>" + Inline(string.Join(" ", para)) + "</p>");
            i++;
        }

        CloseBlocks();
        return (title, string.Join("\n", outp));
    }

    private static string Template(string lang, string title, string body) => $@"<!DOCTYPE html>
<html lang=""{lang}"">
<head>
<meta charset=""utf-8"">
<meta http-equiv=""X-UA-Compatible"" content=""IE=edge"">
<title>{title}</title>
<style>
{Css}
</style>
</head>
<body>
{body}
</body>
</html>";

    private static readonly string Css = (@"
:root { color-scheme: light dark; }
body { font: 15px/1.6 'Segoe UI', system-ui, sans-serif; max-width: 46em;
       margin: 0 auto; padding: 20px 28px 44px; color: #1b1b1b; background: #ffffff; }
h1 { font-size: 1.7em; border-bottom: 1px solid rgba(128,128,128,.35); padding-bottom: .3em; }
h2 { font-size: 1.3em; margin-top: 1.6em; border-bottom: 1px solid rgba(128,128,128,.2);
     padding-bottom: .25em; }
h3 { font-size: 1.05em; margin-top: 1.4em; }
code { font: .9em Consolas, 'Cascadia Mono', monospace; background: rgba(128,128,128,.15);
       border-radius: 4px; padding: .1em .35em; }
pre { background: rgba(128,128,128,.12); border-radius: 8px; padding: 12px 14px; overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 1em 0; }
th, td { border: 1px solid rgba(128,128,128,.35); padding: 6px 12px; text-align: left; }
th { background: rgba(128,128,128,.12); }
blockquote { margin: 1em 0; padding: .1em 1em; border-left: 3px solid rgba(128,128,128,.4);
             color: #666; }
a { color: #0b64d6; }
li { margin: .25em 0; }
@media (prefers-color-scheme: dark) {
  body { background: #1e1e1e; color: #e6e6e6; }
  a { color: #5aa1ff; }
  blockquote { color: #a8a8a8; }
}
").Trim();
}
