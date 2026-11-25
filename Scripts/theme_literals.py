import re
import sys
from pathlib import Path

ALLOWED = {0.0, 1.0}
FONT_HELPERS = "regular|round|mono|heavy|medium|semibold|bold|light|black|thin|ultraLight"
FONT = re.compile(rf"(\.(?:{FONT_HELPERS})\(|\.system\(size: ?)(\d+(?:\.\d+)?)(?=[,)])")
RADIUS = re.compile(r"(cornerRadius: ?)(\d+(?:\.\d+)?)(?=[,)])")
PADDING = re.compile(r"(\.padding\((?:(?:\.[a-zA-Z]+|\[[^\]]*\]), ?)?)(\d+(?:\.\d+)?)(?=\))")
SPACING = re.compile(r"(\b(?:spacing|[a-z]+Spacing): ?)(\d+(?:\.\d+)?)(?=[,)])")

TEXT = [(9, "micro"), (10, "caption"), (11, "subheadline"), (12, "callout"), (13, "body"), (15, "title3"), (17, "title2"), (22, "title1"), (26, "largeTitle"), (48, "display"), (64, "wordmark")]
ICON = [(20, "medium"), (30, "large"), (40, "xlarge"), (64, "hero")]
RADII = [(2, "hairline"), (4, "small"), (6, "medium"), (8, "large"), (10, "xlarge"), (16, "panel"), (22, "card")]
SPACE = [(2, "xxs"), (4, "xs"), (6, "s"), (8, "m"), (12, "l"), (16, "xl"), (20, "window"), (24, "xxl"), (32, "xxxl"), (48, "huge")]


def nearest(value, scale):
    return min(scale, key=lambda step: (abs(step[0] - value), step[0]))[1]


def is_icon(lines, i):
    window = "\n".join(lines[max(0, i - 3): i + 1])
    last_image = window.rfind("Image(systemName")
    return last_image != -1 and window.rfind("Text(") < last_image


def offenders(path):
    for n, line in enumerate(path.read_text().split("\n"), 1):
        if line.lstrip().startswith("//"):
            continue
        for pattern in (FONT, RADIUS, PADDING, SPACING):
            for m in pattern.finditer(line):
                if float(m.group(2)) not in ALLOWED:
                    yield n, line.strip()


def migrate(path):
    lines = path.read_text().split("\n")
    for i, line in enumerate(lines):
        if line.lstrip().startswith("//"):
            continue

        def font(m):
            v = float(m.group(2))
            if v in ALLOWED:
                return m.group(0)
            if v >= 20 and is_icon(lines, i):
                return m.group(1) + "IconSize." + nearest(v, ICON)
            return m.group(1) + "TextSize." + nearest(v, TEXT)

        def scaled(prefix, scale):
            def sub(m):
                v = float(m.group(2))
                if v in ALLOWED or v > scale[-1][0] + 8:
                    return m.group(0)
                return m.group(1) + prefix + nearest(v, scale)
            return sub

        line = FONT.sub(font, line)
        line = RADIUS.sub(scaled("Radius.", RADII), line)
        line = PADDING.sub(scaled("Space.", SPACE), line)
        line = SPACING.sub(scaled("Space.", SPACE), line)
        lines[i] = line
    path.write_text("\n".join(lines))


def sources():
    return [p for p in Path("Polc").glob("*.swift") if p.name != "Theme.swift"]


if __name__ == "__main__":
    if sys.argv[1:] == ["--migrate"]:
        for p in sources():
            migrate(p)
    found = [(p, n, l) for p in sources() for n, l in offenders(p)]
    for p, n, l in found:
        print(f"{p}:{n}: literal layout value, use a Theme.swift token: {l}")
    sys.exit(1 if found else 0)
