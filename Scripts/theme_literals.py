import re
import sys
from pathlib import Path

ALLOWED = {0.0, 1.0}
FONT_HELPERS = "regular|round|mono|heavy|medium|semibold|bold|light|black|thin|ultraLight"
FONT = re.compile(rf"(\.(?:{FONT_HELPERS})\(|\.system\(size: ?)(\d+(?:\.\d+)?)(?=[,)])")
RADIUS = re.compile(r"(cornerRadius: ?)(\d+(?:\.\d+)?)(?=[,)])")
PADDING = re.compile(r"(\.padding\((?:(?:\.[a-zA-Z]+|\[[^\]]*\]), ?)?)(\d+(?:\.\d+)?)(?=\))")
SPACING = re.compile(r"(\b(?:spacing|[a-z]+Spacing): ?)(\d+(?:\.\d+)?)(?=[,)])")
SHADOW = re.compile(r"\.shadow\(")


def offenders(path):
    for n, line in enumerate(path.read_text().split("\n"), 1):
        if line.lstrip().startswith("//"):
            continue
        for pattern in (FONT, RADIUS, PADDING, SPACING):
            for m in pattern.finditer(line):
                if float(m.group(2)) not in ALLOWED:
                    yield n, "literal layout value, use a Theme.swift token", line.strip()
        if SHADOW.search(line):
            yield n, "raw shadow, use .themeShadow with a Theme.swift Shadow", line.strip()


def sources():
    return [p for p in Path("Polc").glob("*.swift") if p.name != "Theme.swift"]


if __name__ == "__main__":
    found = [(p, n, why, l) for p in sources() for n, why, l in offenders(p)]
    for p, n, why, l in found:
        print(f"{p}:{n}: {why}: {l}")
    sys.exit(1 if found else 0)
