#!/usr/bin/env python3
"""Replace hard-coded UI strings with localisation lookups.

Dart wraps long strings by writing adjacent literals that the compiler
concatenates, so a single user-facing sentence can be three literals across
three lines with arbitrary indentation. Matching those by hand is where a
mechanical edit goes wrong — one missed continuation leaves a half-replaced
string that still compiles.

This finds runs of adjacent literals, concatenates them, and matches on the
resulting text. Interpolations are preserved verbatim in the match key, so
`'$name in $minutes minutes'` is addressed by exactly that text.
"""
import pathlib
import re
import sys

# A single-quoted or double-quoted Dart literal, allowing escaped quotes.
LITERAL = r"""(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")"""
# One or more literals separated only by whitespace and newlines.
RUN = re.compile(rf"{LITERAL}(?:\s*{LITERAL})*")


def content(literal: str) -> str:
    """The text inside one literal, with escapes left as written."""
    return literal[1:-1]


def concat(run: str) -> str:
    return "".join(content(m.group(0)) for m in re.finditer(LITERAL, run))


def replace(source: str, wanted: str, replacement: str) -> tuple[str, int]:
    """Replace every literal run whose concatenation equals `wanted`."""
    count = 0
    out = []
    last = 0
    for match in RUN.finditer(source):
        if concat(match.group(0)) != wanted:
            continue
        out.append(source[last:match.start()])
        out.append(replacement)
        last = match.end()
        count += 1
    out.append(source[last:])
    return "".join(out), count


def ensure_import(source: str, depth: int) -> str:
    if "l10n/app_localizations.dart" in source:
        return source

    rel = "../" * depth + "l10n/app_localizations.dart"
    lines = source.split("\n")
    relative = [
        i for i, line in enumerate(lines)
        if line.startswith("import '") and not line.startswith("import 'package:")
    ]
    if relative:
        lines.insert(relative[0], f"import '{rel}';")
    else:
        package = [i for i, line in enumerate(lines)
                   if line.startswith("import 'package:")]
        lines.insert(package[-1] + 1, f"\nimport '{rel}';")
    return "\n".join(lines)


def apply(path: str, pairs: list[tuple[str, str]], depth: int) -> None:
    file = pathlib.Path(path)
    source = file.read_text()

    missed = []
    for wanted, replacement in pairs:
        source, count = replace(source, wanted, replacement)
        if count == 0:
            missed.append(wanted)

    source = ensure_import(source, depth)
    file.write_text(source)

    name = path.split("/")[-1]
    if missed:
        print(f"  !! {name}: {len(missed)} unmatched")
        for m in missed:
            print(f"     {m[:78]}")
    else:
        print(f"  ok {name}: {len(pairs)} replaced")


if __name__ == "__main__":
    print(concat(sys.argv[1]) if len(sys.argv) > 1 else __doc__)


def strip_const(root: str = "lib") -> None:
    """Remove `const` from any expression containing a localisation lookup.

    A lookup is a method call, so the enclosing expression can no longer be a
    compile-time constant — and the enclosing one may be several levels up from
    the string that changed. Scanning for the outermost `const` whose argument
    list contains a lookup handles that without needing to know the widget tree.
    """
    for path in pathlib.Path(root).rglob("*.dart"):
        source = path.read_text()
        out, changed, i = [], False, 0
        while True:
            match = re.search(r"\bconst\s+(?=[A-Z_])", source[i:])
            if not match:
                out.append(source[i:])
                break
            start, after = i + match.start(), i + match.end()
            open_paren = source.find("(", after)
            if open_paren == -1:
                out.append(source[i:after])
                i = after
                continue
            depth, k = 0, open_paren
            while k < len(source):
                if source[k] == "(":
                    depth += 1
                elif source[k] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                k += 1
            out.append(source[i:start])
            if "AppLocalizations.of(" in source[open_paren:k]:
                out.append(source[after:k + 1])
                changed = True
            else:
                out.append(source[start:k + 1])
            i = k + 1
        if changed:
            path.write_text("".join(out))
