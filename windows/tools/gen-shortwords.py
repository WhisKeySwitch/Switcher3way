#!/usr/bin/env python3
"""Regenerate the word lists in windows/src/Switcher3way.Core/ShortWords.cs from the macOS source.

Sources/Switcher3wCore/ShortWords.swift is the single source of the short-word lists: the two ports
must decide identically. This rewrites only the `Common` dictionary initializer of the C# file —
the doc comments and the code around it are the Windows port's own.

    python3 windows/tools/gen-shortwords.py          # rewrite in place
    python3 windows/tools/gen-shortwords.py --check  # exit 1 if the C# file is out of date
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "Sources/Switcher3wCore/ShortWords.swift"
CSHARP = ROOT / "windows/src/Switcher3way.Core/ShortWords.cs"


def swift_lists() -> list[tuple[str, list[str]]]:
    src = SWIFT.read_text(encoding="utf-8")
    body = src[src.index("static let common"):]
    body = body[: body.index("\n    ]\n")]
    out = []
    for m in re.finditer(r'^        "(\w\w)": \[\n(.*?)^        \],', body, re.S | re.M):
        lang, block = m.group(1), m.group(2)
        block = "\n".join(line.split("//", 1)[0] for line in block.splitlines())   # drop comments
        words = sorted(set(re.findall(r'"([^"]+)"', block)))                       # code-point order
        out.append((lang, words))
    if not out:
        sys.exit("no lists found in ShortWords.swift — has its layout changed?")
    return out


def render(lists: list[tuple[str, list[str]]]) -> str:
    parts = ["    private static readonly Dictionary<string, HashSet<string>> Common = new()\n    {\n"]
    for lang, words in lists:
        parts.append(f'        ["{lang}"] = new()\n        {{\n')
        for i in range(0, len(words), 10):
            parts.append("        " + " ".join(f'"{w}",' for w in words[i:i + 10]) + "\n")
        parts.append("        },\n")
    parts.append("    };\n")
    return "".join(parts)


def main() -> None:
    cs = CSHARP.read_text(encoding="utf-8")
    start = cs.index("    private static readonly Dictionary<string, HashSet<string>> Common = new()")
    end = cs.index("    };\n", start) + len("    };\n")
    updated = cs[:start] + render(swift_lists()) + cs[end:]
    if "--check" in sys.argv:
        sys.exit(0 if updated == cs else "ShortWords.cs is out of date — run windows/tools/gen-shortwords.py")
    CSHARP.write_text(updated, encoding="utf-8")
    print(f"wrote {CSHARP.relative_to(ROOT)}: " + ", ".join(f"{l} {len(w)}" for l, w in swift_lists()))


if __name__ == "__main__":
    main()
