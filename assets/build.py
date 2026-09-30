#!/usr/bin/env python3
"""Build the README artwork: section headers, palette and type specimen, each in a dark and a light version.

Text is drawn as Michroma outlines (fontTools), so it renders on GitHub without a web font.
Backgrounds are transparent; the README picks the version that matches the viewer's theme.
The banner and brand lockup come from render.py, which draws them with the shell's own components.
Run: python3 assets/build.py   (needs fontTools; the brand venv has it)
"""
import os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

ROOT = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.expanduser("~/Project/Hiraeth/brand")
FONT = TTFont(os.path.join(BRAND, "Michroma.ttf"))
GS, CMAP, UPM = FONT.getGlyphSet(), FONT.getBestCmap(), FONT["head"].unitsPerEm

PAL = [("BG", "#05070f"), ("SKY", "#070a17"), ("NAVY", "#0b1330"), ("LINE", "#1b2140"), ("MUTED", "#8189a8"),
       ("BLUE", "#b6c4ff"), ("ENGINE", "#a8eefc"), ("INK", "#cfdaf7"), ("CORE", "#f6f7ff")]

# Ink colours per GitHub theme.
THEMES = {
    "dark": dict(ink="#cfdaf7", muted="#8189a8", line="#2a3358", accent="#a8eefc", edge="#2a3358"),
    "light": dict(ink="#0b1330", muted="#5b6488", line="#d3d9ec", accent="#3b6fd8", edge="#c3cbe3"),
}

SECTIONS = [
    ("01", "shell", "Shell", "Bar, notch, panels"),
    ("02", "login", "Login", "Greeter, lock, polkit"),
    ("03", "sky", "Sky", "Live wallpaper"),
    ("04", "terminal", "Terminal", "Fetch, yazi"),
    ("05", "design", "Design", "Mark, colour, type"),
]


def text_path(s, size, x=0, y=0, track=0.12):
    """Return (svg path d, advance width) for s set in Michroma, baseline at y."""
    k, pen, cx = size / UPM, SVGPathPen(GS), 0.0
    for ch in s:
        g = CMAP.get(ord(ch))
        if g is None:
            continue
        GS[g].draw(TransformPen(pen, (k, 0, 0, -k, x + cx, y)))
        cx += GS[g].width * k + size * track
    return pen.getCommands(), cx - size * track


def text(s, size, x, y, fill, anchor="start", op=1, track=0.12):
    w = text_path(s, size, 0, 0, track)[1]
    x -= w / 2 if anchor == "middle" else (w if anchor == "end" else 0)
    return f'<path d="{text_path(s, size, x, y, track)[0]}" fill="{fill}" opacity="{op}"/>'


def far_light(x, y, c):
    """The brand's bright star, small: core, halo ring, hairline spikes."""
    return (f'<circle cx="{x}" cy="{y}" r="9" fill="none" stroke="{c}" stroke-width=".8" opacity=".35"/>'
            f'<line x1="{x-14}" y1="{y}" x2="{x+14}" y2="{y}" stroke="{c}" stroke-width=".7" opacity=".6"/>'
            f'<line x1="{x}" y1="{y-14}" x2="{x}" y2="{y+14}" stroke="{c}" stroke-width=".7" opacity=".6"/>'
            f'<circle cx="{x}" cy="{y}" r="2.6" fill="{c}"/>')


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>'


def put(rel, data):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(data)


def header(num, key, title, sub, t, th):
    w, h = 1280, 100
    body = far_light(20, 44, th["ink"])
    body += text(title.upper(), 28, 58, 58, th["ink"], track=.16)
    body += text(sub.upper(), 10, w, 56, th["muted"], "end", track=.3)
    # Hairline that stops short of the star, as on the mark.
    body += f'<line x1="58" y1="86" x2="{w}" y2="86" stroke="{th["line"]}" stroke-width="1"/>'
    put(f"headers/{num}-{key}-{t}.svg", svg(w, h, body))


def palette(t, th):
    cw = 140
    w, h = cw * len(PAL) - 16, 170
    body = ""
    for i, (label, hexv) in enumerate(PAL):
        x = i * cw
        body += f'<rect x="{x+.5}" y=".5" width="{cw-17}" height="104" rx="8" fill="{hexv}" stroke="{th["edge"]}"/>'
        body += text(label, 10, x, 134, th["ink"], track=.25)
        body += text(hexv.upper(), 9, x, 158, th["muted"], track=.2)
    put(f"palette-{t}.svg", svg(w, h, body))


def type_specimen(t, th):
    w, h = 1280, 190
    body = text("MICHROMA", 46, 0, 60, th["ink"], track=.16)
    body += text("ABCDEFGHIJKLMNOPQRSTUVWXYZ  0123456789", 16, 0, 116, th["ink"], op=.8, track=.18)
    body += text("DISPLAY FACE  /  UPPERCASE  /  WIDE TRACKING", 9, 0, 166, th["muted"], track=.3)
    put(f"type-{t}.svg", svg(w, h, body))


if __name__ == "__main__":
    for t, th in THEMES.items():
        palette(t, th)
        type_specimen(t, th)
        for num, key, title, sub in SECTIONS:
            header(num, key, title, sub, t, th)
    print("built", len(SECTIONS), "headers, palette and type, in", len(THEMES), "themes")
