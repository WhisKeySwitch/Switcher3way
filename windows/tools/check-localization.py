# -*- coding: utf-8 -*-
"""Report how complete each interface language in Loc.cs is.

The app labels a language "partly translated" in its own picker, the Settings tab says which
languages are complete, and the Store listing repeats the claim in four languages. All three are
counting the same thing, and until now nobody was counting it — the number in the listing came from
"`Loc.cs` has 16 language blocks", which was true and meant nothing, because most of those blocks
held a third of the strings and the rest silently fell back to English.

    python windows/tools/check-localization.py            # report
    python windows/tools/check-localization.py --require en,uk,ru,bg

`--require` exits non-zero unless every language named is complete, so a claim written into the copy
can be checked rather than believed.
"""
import io
import os
import re
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "src", "Switcher3way.App", "Loc.cs")

BLOCK = re.compile(r'\["([a-z]{2})"\] = new\(\)\s*\{\n(.*?)\n        \},', re.S)
PAIR = re.compile(r'\["([^"]+)"\] = ("(?:[^"\\]|\\.)*"),')
PLACEHOLDER = re.compile(r"%@|%d")


def main():
    text = io.open(SRC, encoding="utf-8").read()
    blocks = {m.group(1): dict(PAIR.findall(m.group(2))) for m in BLOCK.finditer(text)}
    if "en" not in blocks:
        sys.exit("no English block in %s" % SRC)
    english = blocks["en"]

    problems = []
    print("%-4s %-9s %s" % ("", "strings", "missing"))
    for lang in sorted(blocks, key=lambda l: (-len(blocks[l]), l)):
        d = blocks[lang]
        missing = [k for k in english if k not in d]
        extra = [k for k in d if k not in english]
        print("%-4s %3d/%-5d %s" % (lang, len(d), len(english),
                                    "complete" if not missing else "%d missing" % len(missing)))
        if extra:
            problems.append("%s has keys English does not: %s" % (lang, ", ".join(sorted(extra))))
        # A translated string that dropped its %@ renders as a sentence with a hole in it, and the
        # only way anyone finds out is a user seeing "Version  — Windows preview".
        for key, value in d.items():
            if key in english:
                want = len(PLACEHOLDER.findall(english[key]))
                got = len(PLACEHOLDER.findall(value))
                if want != got:
                    problems.append("%s %s: %d placeholders, English has %d" % (lang, key, got, want))

    if problems:
        print()
        for p in problems:
            print("  " + p)

    required = []
    for i, arg in enumerate(sys.argv):
        if arg == "--require" and i + 1 < len(sys.argv):
            required = [l.strip() for l in sys.argv[i + 1].split(",") if l.strip()]
    if required:
        incomplete = [l for l in required
                      if l not in blocks or any(k not in blocks[l] for k in english)]
        print()
        if incomplete:
            print("Required complete, but is not: %s" % ", ".join(incomplete))
            sys.exit(1)
        print("Complete as required: %s" % ", ".join(required))

    if problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
