# -*- coding: utf-8 -*-
"""Write the Partner Center bulk-listing CSV from the copy in this repository.

Partner Center lets you download every listing as one CSV, edit it, and upload it back. That is the
only practical way to keep four listings in step: the web form is one language at a time, and the
last time the four were edited by hand they drifted in three different directions at once —

  * the Store was missing the product-feature bullet about words no dictionary knows, added to
    `store-listing.md` for 0.5.0 and never pasted in;
  * one feature bullet had lost its last character to a bad paste ("exclude any ap");
  * the Russian What's-new field still described 0.5.0 while English and Ukrainian described 0.6.0;
  * and the search terms in `store-listing.md` had never been the ones actually uploaded, so for a
    year the file and the Store disagreed with no way to tell which was right.

None of that is careless typing. It is what happens when the same words live in five places. So the
repository holds the words and this script produces the upload, which makes `store-listing.md` and
`whats-new.md` the only copies anyone edits.

    python windows/tools/build-listing-csv.py [path-to-downloaded.csv]

The CSV must be one downloaded from Partner Center: it carries the field IDs, and the screenshot
rows point at assets uploaded per listing that nothing here can reconstruct. Those rows, and the
captions bound to them, are copied through untouched. Everything else is overwritten from the repo.

Every Store limit is checked before writing, because Partner Center rejects the whole upload for one
overlong field and does not say which.
"""
import csv
import io
import os
import re
import sys

# Every language here is non-Latin somewhere; a Windows console defaults to cp1252 and would
# crash on the first report line rather than print it.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
WIN = os.path.dirname(HERE)

LANGS = ["en", "uk", "ru", "bg"]
COLUMN = {"en": "en-us", "uk": "uk", "ru": "ru", "bg": "bg"}

# Partner Center's limits, from the field table at the top of store-listing.md.
MAX_DESCRIPTION = 10000
MAX_RELEASE_NOTES = 1500
MAX_FEATURE = 200
MAX_FEATURES = 20
MAX_SEARCH_TERM = 30
MAX_SEARCH_TERMS = 7
MAX_SEARCH_WORDS = 21
MAX_COPYRIGHT = 200

NEXT_HEADING = chr(10) + "## "


def read(name):
    with io.open(os.path.join(WIN, name), encoding="utf-8") as f:
        return f.read()


def unwrap(text):
    """Markdown here is wrapped at about 100 columns to stay readable in a diff. The Store field is
    plain text and keeps every newline, so uploading the wrapped form puts a hard line break in the
    middle of a sentence — which is exactly what the live English description does today. Paragraphs
    become single lines; blank lines stay."""
    paragraphs = re.split(r"\n\s*\n", text.strip())
    return "\n\n".join(" ".join(p.split()) for p in paragraphs)


def language_sections(md):
    """`## English (en)` … up to the next `## `, keyed by the code in the parentheses."""
    out = {}
    for match in re.finditer(r"^## .*\(([a-z]{2})\)\s*$", md, re.M):
        start = match.end()
        nxt = re.search(r"^## ", md[start:], re.M)
        out[match.group(1)] = md[start:start + nxt.start()] if nxt else md[start:]
    return out


def subsections(section):
    """The `###` blocks in order. Their headings are localised, so position is what identifies
    them: description, product features, what's-new pointer, search terms."""
    parts = re.split(r"^### .*$", section, flags=re.M)[1:]
    return [p.strip() for p in parts]


def bullets(block):
    return [re.sub(r"^-\s+", "", ln).strip() for ln in block.splitlines() if ln.startswith("- ")]


def lines(block):
    """A section's last block runs to the next `##`, so it swallows the `---` rule between them."""
    out = [ln.strip() for ln in block.splitlines() if ln.strip()]
    return [ln for ln in out if set(ln) != {"-"}]


def copy_from(md):
    """The copyright line per language, written in ASCII in the file so it survives copying, with
    the © restored — the Store field accepts it and it is what the other listings already hold."""
    # Stop at the next `##`. The Screenshots section below uses the same `- **en** —` shape for its
    # captions, and reading on picked up the last caption as every language's copyright line.
    section = md.split("## Copyright and trademark info", 1)[1].split(NEXT_HEADING, 1)[0]
    out = {}
    for lang, text in re.findall(r"^- \*\*([a-z]{2})\*\* — (.+)$", section, re.M):
        out[lang] = text.strip().replace("(c)", "©")
    return out


def release_notes(md):
    out = {}
    for match in re.finditer(r"^## .*\(([a-z]{2})\)\s*$", md, re.M):
        rest = md[match.end():]
        body = re.search(r"```\n(.*?)\n```", rest, re.S)
        if body:
            out[match.group(1)] = body.group(1).strip()
    return out


def collect():
    listing = read("store-listing.md")
    sections = language_sections(listing)
    notes = release_notes(read("whats-new.md"))
    copyrights = copy_from(listing)

    data = {}
    for lang in LANGS:
        if lang not in sections:
            sys.exit("store-listing.md has no %s section" % lang)
        blocks = subsections(sections[lang])
        if len(blocks) < 4:
            sys.exit("%s section: expected description, features, what's-new, search terms" % lang)
        data[lang] = {
            "Description": unwrap(blocks[0]),
            "ReleaseNotes": notes[lang],
            "CopyrightTrademarkInformation": copyrights[lang],
            "Features": bullets(blocks[1]),
            "SearchTerms": lines(blocks[3]),
        }
    return data


def check(data, warnings):
    problems = []
    for lang, d in data.items():
        def over(what, value, limit):
            if len(value) > limit:
                problems.append("%s %s: %d characters, limit %d" % (lang, what, len(value), limit))

        over("description", d["Description"], MAX_DESCRIPTION)
        over("what's new", d["ReleaseNotes"], MAX_RELEASE_NOTES)
        over("copyright", d["CopyrightTrademarkInformation"], MAX_COPYRIGHT)

        if len(d["Features"]) > MAX_FEATURES:
            problems.append("%s: %d product features, limit %d" % (lang, len(d["Features"]), MAX_FEATURES))
        for f in d["Features"]:
            if len(f) > MAX_FEATURE:
                problems.append("%s feature over %d characters: %s…" % (lang, MAX_FEATURE, f[:60]))

        terms = d["SearchTerms"]
        if len(terms) > MAX_SEARCH_TERMS:
            problems.append("%s: %d search terms, limit %d" % (lang, len(terms), MAX_SEARCH_TERMS))
        words = sum(len(t.split()) for t in terms)
        if words > MAX_SEARCH_WORDS:
            problems.append("%s: %d words across the search terms, limit %d" % (lang, words, MAX_SEARCH_WORDS))

        # Not fatal, and the reason is worth knowing: the Ukrainian and Russian terms Partner Center
        # already holds are 32 to 36 characters long. Either the documented 30 is not what the form
        # enforces, or they were accepted some other way — but they came out of Partner Center, so
        # refusing to put them back would be this script overruling the Store about its own rules.
        # Warn, upload, and find out at submission rather than silently shortening someone's terms.
        for term in terms:
            if len(term) > MAX_SEARCH_TERM:
                warnings.append("%s search term is %d characters, %d documented: %s"
                                % (lang, len(term), MAX_SEARCH_TERM, term))
    return problems


def main():
    default = os.path.join(WIN, "listing-data.csv")
    path = sys.argv[1] if len(sys.argv) > 1 else default
    if not os.path.exists(path):
        sys.exit("no CSV at %s — download one from Partner Center → Store listings → Export" % path)

    data = collect()
    warnings = []
    problems = check(data, warnings)
    if problems:
        print("Not written — Partner Center would reject the upload:")
        for p in problems:
            print("  " + p)
        sys.exit(1)

    with io.open(path, encoding="utf-8-sig", newline="") as f:
        rows = list(csv.reader(f))
    header, body = rows[0], rows[1:]
    col = {lang: header.index(COLUMN[lang]) for lang in LANGS}

    def put(field, value_for):
        for row in body:
            if row[0] == field:
                for lang in LANGS:
                    row[col[lang]] = value_for(lang)
                return True
        return False

    for field in ("Description", "ReleaseNotes", "CopyrightTrademarkInformation"):
        if not put(field, lambda lang, f=field: data[lang][f]):
            sys.exit("the CSV has no %s row — is it a Partner Center export?" % field)

    # Title and developer name are the same in every language; Bulgarian just has not been given them.
    english = {r[0]: r[col["en"]] for r in body}
    put("Title", lambda lang: english["Title"])
    put("DevStudio", lambda lang: english["DevStudio"])

    for i in range(1, MAX_FEATURES + 1):
        put("Feature%d" % i, lambda lang, i=i: data[lang]["Features"][i - 1]
            if i <= len(data[lang]["Features"]) else "")
    for i in range(1, MAX_SEARCH_TERMS + 1):
        put("SearchTerm%d" % i, lambda lang, i=i: data[lang]["SearchTerms"][i - 1]
            if i <= len(data[lang]["SearchTerms"]) else "")

    # A caption the export stored with a leading space is a paste artefact, not content.
    for row in body:
        row[:] = [c.strip() if c.strip() != c else c for c in row]

    buf = io.StringIO(newline="")
    csv.writer(buf, lineterminator="\r\n").writerows([header] + body)
    with io.open(path, "w", encoding="utf-8-sig", newline="") as f:
        f.write(buf.getvalue())

    print("Wrote %s\n" % path)
    for w in warnings:
        print("  note: " + w)
    if warnings:
        print()
    for lang in LANGS:
        d = data[lang]
        print("  %-3s description %5d  what's new %4d  features %2d  search terms %d (%d words)"
              % (lang, len(d["Description"]), len(d["ReleaseNotes"]), len(d["Features"]),
                 len(d["SearchTerms"]), sum(len(t.split()) for t in d["SearchTerms"])))
    missing = [lang for lang in LANGS
               if not any(r[0] == "DesktopScreenshot1" and r[col[lang]] for r in body)]
    if missing:
        print("\n  No screenshots for: %s. The Store requires at least one per listing, and images"
              % ", ".join(missing))
        print("  are uploaded per listing in Partner Center — this script cannot supply them.")


if __name__ == "__main__":
    main()
