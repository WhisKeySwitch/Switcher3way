#!/usr/bin/env python3
"""Генератор встроенной справки: docs/user-guide*.md → Resources/help/*.html.

Руководства — единственный источник правды для справки в приложении; конвертация
выполняется build_app.sh на каждой сборке. Только stdlib. Поддерживается ровно то
подмножество Markdown, которым написаны руководства: h1–h3, **жирный**, *курсив*,
`код`, ссылки, маркированные списки, таблицы, цитаты, код-блоки. Отсутствующий
исходник — ошибка сборки (справка не должна молча устареть или потеряться).

Использование: md2html.py <docs-dir> <out-dir>
"""
import html
import re
import sys
from pathlib import Path

# user-guide.md публикуется как user-guide.en.html — выбор языка в приложении единообразен
SOURCES = {
    "user-guide.md": "user-guide.en.html",
    "user-guide.uk.md": "user-guide.uk.html",
    "user-guide.ru.md": "user-guide.ru.html",
}

CSS = """
:root { color-scheme: light dark; }
body { font: 15px/1.6 -apple-system, system-ui, sans-serif; max-width: 46em;
       margin: 0 auto; padding: 24px 32px 48px; }
h1 { font-size: 1.7em; border-bottom: 1px solid rgba(128,128,128,.35); padding-bottom: .3em; }
h2 { font-size: 1.3em; margin-top: 1.8em; border-bottom: 1px solid rgba(128,128,128,.2);
     padding-bottom: .25em; }
h3 { font-size: 1.05em; margin-top: 1.5em; }
code { font: .9em ui-monospace, monospace; background: rgba(128,128,128,.15);
       border-radius: 4px; padding: .1em .35em; }
pre { background: rgba(128,128,128,.12); border-radius: 8px; padding: 12px 14px;
      overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: 1em 0; }
th, td { border: 1px solid rgba(128,128,128,.35); padding: 6px 12px; text-align: left; }
th { background: rgba(128,128,128,.12); }
blockquote { margin: 1em 0; padding: .1em 1em; border-left: 3px solid rgba(128,128,128,.4);
             color: rgba(128,128,128,1); }
a { color: -apple-system-blue; }
li { margin: .25em 0; }
""".strip()

TEMPLATE = """<!DOCTYPE html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
{css}
</style>
</head>
<body>
{body}
</body>
</html>
"""


def slugify(text):
    """Анкер заголовка в стиле GitHub: строчные, пробелы → дефисы, пунктуация — вон.
    Кириллица сохраняется — оглавления uk/ru ссылаются на кириллические анкеры."""
    text = re.sub(r"[^\w\s-]", "", text.lower(), flags=re.UNICODE)
    return re.sub(r"\s", "-", text.strip())


def inline(text):
    """Инлайн-разметка. Порядок: экранирование → код → ссылки → жирный → курсив."""
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 2:
            out.append("<code>%s</code>" % html.escape(part[1:-1]))
            continue
        p = html.escape(part, quote=False)
        # Ссылки между руководствами ведут на собранные .html-имена
        def link(m):
            href = m.group(2)
            href = SOURCES.get(href, href)
            return '<a href="%s">%s</a>' % (href, m.group(1))
        p = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", link, p)
        p = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", p)
        p = re.sub(r"(?<!\w)\*([^*]+)\*(?!\w)", r"<em>\1</em>", p)
        out.append(p)
    return "".join(out)


def convert(md):
    lines = md.split("\n")
    out = []
    i = 0
    in_list = in_quote = False
    title = ""

    def close_blocks():
        nonlocal in_list, in_quote
        if in_list:
            out.append("</ul>")
            in_list = False
        if in_quote:
            out.append("</blockquote>")
            in_quote = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("```"):
            close_blocks()
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(code)))
            i += 1
            continue

        m = re.match(r"^(#{1,3}) (.*)$", stripped)
        if m:
            close_blocks()
            level = len(m.group(1))
            text = m.group(2)
            if level == 1 and not title:
                title = text
            out.append('<h%d id="%s">%s</h%d>' % (level, slugify(text), inline(text), level))
            i += 1
            continue

        if stripped.startswith("|"):
            close_blocks()
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append("<table>")
            for r, row in enumerate(rows):
                if r == 1 and all(re.fullmatch(r":?-+:?", c) for c in row):
                    continue
                tag = "th" if r == 0 else "td"
                cells = "".join("<%s>%s</%s>" % (tag, inline(c), tag) for c in row)
                out.append("<tr>%s</tr>" % cells)
            out.append("</table>")
            continue

        if stripped.startswith("- "):
            if in_quote:
                out.append("</blockquote>")
                in_quote = False
            if not in_list:
                out.append("<ul>")
                in_list = True
            # многострочные пункты: продолжения с отступом приклеиваем к пункту
            item = stripped[2:]
            while i + 1 < len(lines) and lines[i + 1].startswith("  ") and lines[i + 1].strip() \
                    and not lines[i + 1].strip().startswith("- "):
                i += 1
                item += " " + lines[i].strip()
            out.append("<li>%s</li>" % inline(item))
            i += 1
            continue

        if stripped.startswith(">"):
            if in_list:
                out.append("</ul>")
                in_list = False
            if not in_quote:
                out.append("<blockquote>")
                in_quote = True
            out.append("<p>%s</p>" % inline(stripped.lstrip("> ")))
            i += 1
            continue

        if not stripped:
            close_blocks()
            i += 1
            continue

        # обычный абзац; соседние строки склеиваются
        close_blocks()
        para = [stripped]
        while i + 1 < len(lines) and lines[i + 1].strip() \
                and not re.match(r"^(#|\||- |>|```)", lines[i + 1].strip()):
            i += 1
            para.append(lines[i].strip())
        out.append("<p>%s</p>" % inline(" ".join(para)))
        i += 1

    close_blocks()
    return title, "\n".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: md2html.py <docs-dir> <out-dir>")
    docs, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    langs = {"user-guide.md": "en", "user-guide.uk.md": "uk", "user-guide.ru.md": "ru"}
    for src_name, html_name in SOURCES.items():
        src = docs / src_name
        if not src.exists():
            sys.exit(f"md2html: source guide missing: {src} — help must not go stale, build aborted")
        title, body = convert(src.read_text(encoding="utf-8"))
        if not title or "<h2" not in body:
            sys.exit(f"md2html: {src_name} produced implausible output (no title/h2), build aborted")
        page = TEMPLATE.format(lang=langs[src_name], title=html.escape(title), css=CSS, body=body)
        (out_dir / html_name).write_text(page, encoding="utf-8")
        print(f"  help: {src_name} → {html_name} ({len(page)} bytes)")


if __name__ == "__main__":
    main()
