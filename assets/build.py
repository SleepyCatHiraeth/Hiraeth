#!/usr/bin/env python3
"""Build the README artwork: banner, section headers, palette, type, gallery tiles.

Text is drawn as Michroma outlines (fontTools), so it renders on GitHub without a web font.
Everything sits in the same flat navy sky as the live wallpaper: glowing dots, fading tails,
particle discs, tiny ships. Nothing photoreal, no static orbit rings.
Run: python3 assets/build.py   (needs fontTools; the brand venv has it)
"""
import math, os, random, re
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

ROOT = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.expanduser("~/Project/Hiraeth/brand")
FONT = TTFont(os.path.join(BRAND, "Michroma.ttf"))
GS, CMAP, UPM = FONT.getGlyphSet(), FONT.getBestCmap(), FONT["head"].unitsPerEm

C = dict(bg="#05070f", sky="#070a17", navy="#0b1330", ink="#cfdaf7", core="#f6f7ff",
         engine="#a8eefc", blue="#b6c4ff", muted="#8189a8", line="#1b2140")

# Gallery, in page order: (number, folder, title, subtitle, [(tile, caption), ...]).
SECTIONS = [
    ("01", "shell", "Shell", "My desktop shell on Hyprland, built on Quickshell.", [
        ("bar", "the sidebar bar"),
        ("launcher", "type to find an app"),
        ("notch", "user, splash line, notifications"),
        ("dashboard", "media, calendar, quick toggles"),
        ("notifications", "toasts drop out of the notch"),
        ("overview", "every workspace at a glance"),
        ("assistant", "ai sidebar"),
        ("capture", "screenshot and recording tools"),
        ("settings", "sorted groups, one window"),
        ("power", "lock, sleep, log out, reboot"),
        ("wallpapers", "picker with images, gifs, videos"),
        ("weather", "clock popup: calendar, live weather sky, focus timer"),
        ("presets", "whole-shell presets, one click"),
        ("mixer", "volume, mic and brightness meters"),
        ("power-profile", "saver, balanced, performance"),
    ]),
    ("02", "greeter", "Greeter", "My login screen. greetd, Hyprland, Quickshell.", [
        ("login", "avatar card, clock, splash line"),
        ("typing", "the cipher pill"),
        ("unlock", "into the session"),
        ("wallpapers", "follows whatever wallpaper I use"),
        ("live-wallpaper", "gifs and videos too"),
    ]),
    ("03", "polkit", "Polkit", "My own authentication agent. Replaced hyprpolkitagent.", [
        ("prompt", "slides up out of the frame"),
    ]),
    ("04", "lockscreen", "Lockscreen", "The sky keeps running behind the clock.", [
        ("lock", "lock and unlock"),
        ("card", "type and the card appears"),
    ]),
    ("05", "sky", "Sky", "My live wallpaper. A whole galaxy that runs like a clock.", [
        ("galaxy", "far light, spiral arms, dust"),
        ("systems", "the home system turning"),
        ("ships", "a ship crossing, then jumping"),
        ("events", "warp out"),
        ("far-light", "hr 1, the far light"),
    ]),
    ("06", "desktop", "Desktop", "Things that live on the wallpaper.", [
        ("splash", "hyprctl splash under the notch"),
        ("osd", "volume and brightness"),
    ]),
    ("07", "brand", "Brand", "Wordmark Sky. Michroma and seven stars.", [
        ("lockup", "the mark"),
        ("meters", "system metrics as segment meters"),
    ]),
    ("08", "system", "System", "Everything around the shell.", [
        ("fastfetch", "logo rendered by the shell"),
        ("terminal", "kitty and yazi in the sky palette"),
    ]),
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


DEFS = (f'<defs><linearGradient id="n" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{C["navy"]}"/>'
        f'<stop offset="1" stop-color="{C["bg"]}"/></linearGradient>'
        f'<radialGradient id="glow"><stop offset="0" stop-color="{C["blue"]}" stop-opacity=".5"/>'
        f'<stop offset=".35" stop-color="{C["blue"]}" stop-opacity=".12"/><stop offset="1" stop-color="{C["blue"]}" stop-opacity="0"/></radialGradient>'
        f'<radialGradient id="eng"><stop offset="0" stop-color="{C["engine"]}" stop-opacity=".9"/>'
        f'<stop offset="1" stop-color="{C["engine"]}" stop-opacity="0"/></radialGradient>'
        f'<linearGradient id="tail" x1="0" x2="1"><stop offset="0" stop-color="{C["ink"]}" stop-opacity="0"/>'
        f'<stop offset="1" stop-color="{C["ink"]}" stop-opacity=".7"/></linearGradient></defs>')


def star(x, y, r, spikes=False):
    o = f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r*7:.1f}" fill="url(#glow)"/>'
    if spikes:
        s = r * 9
        o += (f'<line x1="{x-s:.1f}" y1="{y:.1f}" x2="{x+s:.1f}" y2="{y:.1f}" stroke="{C["core"]}" stroke-width=".5" opacity=".45"/>'
              f'<line x1="{x:.1f}" y1="{y-s:.1f}" x2="{x:.1f}" y2="{y+s:.1f}" stroke="{C["core"]}" stroke-width=".5" opacity=".45"/>')
    return o + f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.2f}" fill="{C["core"]}"/>'


def galaxy(x, y, rad, r, tilt=.45, rot=0):
    """Particle disc with two trailing arms, flat dots only."""
    o, a0 = "", rot
    for arm in (0, math.pi):
        for i in range(70):
            t = i / 70
            a = a0 + arm + t * 3.4
            d = rad * (.08 + t)
            px = x + math.cos(a) * d + r.gauss(0, rad * .05)
            py = y + math.sin(a) * d * tilt + r.gauss(0, rad * .03)
            o += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{.4+ (1-t)*.6:.2f}" fill="{C["blue"]}" opacity="{.15+(1-t)*.45:.2f}"/>'
    return o + f'<circle cx="{x}" cy="{y}" r="{rad*.5:.1f}" fill="url(#glow)"/>' + f'<circle cx="{x}" cy="{y}" r="1.4" fill="{C["core"]}"/>'


def comet(x, y, length, ang):
    """Head at x,y; the tail fades out behind it along ang."""
    return (f'<g transform="rotate({math.degrees(ang):.1f} {x:.1f} {y:.1f})">'
            f'<rect x="{x-length:.1f}" y="{y-.5:.1f}" width="{length:.1f}" height="1" fill="url(#tail)"/></g>'
            + star(x, y, 1.1))


def ship(x, y, ang, k=1.0):
    pts = [(9, 0), (-5, -4), (-3, 0), (-5, 4)]
    p = " ".join(f"{px*k:.1f},{py*k:.1f}" for px, py in pts)
    return (f'<g transform="translate({x:.1f} {y:.1f}) rotate({ang:.1f})">'
            f'<circle cx="{-5*k:.1f}" cy="0" r="{5*k:.1f}" fill="url(#eng)"/>'
            f'<polygon points="{p}" fill="{C["ink"]}"/></g>')


def space(w, h, seed, dens=1.0):
    """Flat navy sky: dust, a few bright stars, sometimes a galaxy, a comet or a small fleet."""
    r = random.Random(seed)
    o = DEFS + f'<rect width="{w}" height="{h}" fill="url(#n)"/>'
    for _ in range(int(w * h / 1500 * dens)):
        o += (f'<circle cx="{r.random()*w:.1f}" cy="{r.random()*h:.1f}" r="{r.random()*.7+.3:.2f}" '
              f'fill="{C["ink"]}" opacity="{r.random()*.35+.08:.2f}"/>')
    for _ in range(max(2, int(w * h / 60000))):
        o += star(r.random() * w, r.random() * h, r.uniform(.8, 1.6), r.random() < .3)
    return o, r


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>'


def put(rel, data):
    p = os.path.normpath(os.path.join(ROOT, rel))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(data)


def lockup(x, y, w):
    """Nest the brand master (generated by brand.py, not redrawn) at x,y with width w."""
    src = open(os.path.join(BRAND, "svg", "hiraeth-lockup-notag.svg")).read()
    vb = re.search(r'viewBox="([^"]+)"', src).group(1)
    vw, vh = map(float, vb.split()[2:])
    inner = re.sub(r"^<svg[^>]*>|</svg>$", "", src)
    return f'<svg x="{x}" y="{y}" width="{w}" height="{w*vh/vw:.1f}" viewBox="{vb}">{inner}</svg>'


def banner():
    w, h = 1280, 480
    body, r = space(w, h, 7, 1.3)
    body += galaxy(170, 120, 90, r, .42, .6)
    body += galaxy(1120, 360, 55, r, .5, 2.2)
    body += comet(1040, 90, 120, math.radians(160))
    body += ship(250, 390, -12, 1.1) + ship(282, 402, -12, .9) + ship(268, 372, -12, .8)
    body += lockup((w - 520) / 2, 44, 520)
    body += text("SHELL · SYSTEM", 11, w / 2, 400, C["blue"], "middle", op=.75, track=.45)
    body += f'<line x1="{w/2-170}" y1="{h-46}" x2="{w/2+170}" y2="{h-46}" stroke="{C["line"]}"/>'
    body += text("MY SHELL · MY SKY · MY SYSTEM", 9, w / 2, h - 22, C["muted"], "middle", track=.4)
    put("banner.svg", svg(w, h, body))


def header(num, key, title, sub):
    w, h = 1280, 140
    body, r = space(w, h, int(num) * 13, 1.1)
    motif = int(num) % 3
    if motif == 0:
        body += galaxy(w - 150, h / 2, 60, r, .45, int(num))
    elif motif == 1:
        body += comet(w - 90, 40, 150, math.radians(165))
    else:
        body += ship(w - 220, 80, -8, 1.1) + ship(w - 190, 92, -8, .9) + ship(w - 205, 64, -8, .8)
    body += f'<rect x=".5" y=".5" width="{w-1}" height="{h-1}" rx="8" fill="none" stroke="{C["line"]}"/>'
    body += star(58, 60, 1.4, True)
    body += text(num, 11, 50, 100, C["engine"], track=.3)
    body += text(title.upper(), 30, 110, 70, C["ink"], track=.14)
    body += text(sub.upper(), 9, 110, 102, C["muted"], track=.22)
    put(f"headers/{num}-{key}.svg", svg(w, h, body))


REAL = (".png", ".jpg", ".jpeg", ".webp", ".gif")


def tile(num, key, i, name, cap):
    """Draw the pending tile unless a real screenshot with the same stem exists."""
    stem = os.path.join(ROOT, "..", "gallery", f"{num}-{key}", f"{i+1:02d}-{name}")
    if any(os.path.exists(stem + e) for e in REAL):
        if os.path.exists(stem + ".svg"):
            os.remove(stem + ".svg")
        return
    w, h = 800, 500
    body, r = space(w, h, int(num) * 100 + i, 1.2)
    pick = (int(num) + i) % 3
    if pick == 0:
        body += galaxy(r.uniform(120, 680), r.choice([90, 410]), r.uniform(45, 70), r, .45, r.random() * 6)
    elif pick == 1:
        body += comet(r.uniform(500, 740), r.uniform(50, 110), r.uniform(90, 150), math.radians(r.uniform(150, 170)))
    else:
        x, y, a = r.uniform(80, 250), r.uniform(380, 440), r.uniform(-20, -5)
        body += ship(x, y, a) + ship(x + 26, y + 12, a, .85) + ship(x + 14, y - 18, a, .75)
    body += f'<rect x=".5" y=".5" width="{w-1}" height="{h-1}" rx="8" fill="none" stroke="{C["line"]}"/>'
    body += text(f"{num}.{i+1:02d}", 11, 36, 50, C["engine"], track=.3)
    body += text(name.upper(), 30, w / 2, h / 2, C["ink"], "middle", track=.16)
    body += text(cap.upper(), 10, w / 2, h / 2 + 36, C["blue"], "middle", op=.8, track=.25)
    body += text("SCREENSHOT SOON", 8, w - 36, h - 30, C["muted"], "end", track=.35)
    put(f"../gallery/{num}-{key}/{i+1:02d}-{name}.svg", svg(w, h, body))


def palette():
    sw = [("BG", "bg"), ("SKY", "sky"), ("NAVY", "navy"), ("LINE", "line"), ("MUTED", "muted"),
          ("BLUE", "blue"), ("ENGINE", "engine"), ("INK", "ink"), ("CORE", "core")]
    cw = 136
    w, h = cw * len(sw) + 40, 210
    body, _ = space(w, h, 3, .6)
    for i, (label, k) in enumerate(sw):
        x = 20 + i * cw
        body += f'<rect x="{x}" y="22" width="{cw-12}" height="110" rx="6" fill="{C[k]}" stroke="{C["line"]}"/>'
        body += text(label, 10, x, 160, C["ink"], track=.25)
        body += text(C[k].upper(), 9, x, 184, C["muted"], track=.2)
    put("palette.svg", svg(w, h, body))


def type_specimen():
    w, h = 1280, 230
    body, r = space(w, h, 99, 1.0)
    body += galaxy(1130, 115, 70, r, .4, 1.3)
    body += text("MICHROMA", 46, 40, 88, C["ink"], track=.16)
    body += text("ABCDEFGHIJKLMNOPQRSTUVWXYZ  0123456789", 16, 40, 142, C["blue"], track=.18)
    body += text("ONE FACE FOR THE SHELL, THE GREETER, POLKIT AND EVERY DESIGN", 9, 40, 188, C["muted"], track=.3)
    put("type.svg", svg(w, h, body))


def cell(d, f, title, caps):
    """One gallery cell. Real screenshots get their caption underneath; placeholder tiles carry it inside."""
    name = os.path.splitext(f)[0][3:]
    img = f'<img src="{d}/{f}" width="100%" alt="{title}: {name.replace("-", " ")}">'
    if f.endswith(".svg"):
        return f'<td width="50%">{img}</td>'
    return f'<td width="50%">{img}<br><sub>{name.replace("-", " ")} · {caps.get(name, "")}</sub></td>'.replace(" · </sub>", "</sub>")


def gallery_md():
    """Header strip per section, then its folder's images in filename order, two per row."""
    out = []
    for num, key, title, sub, shots in SECTIONS:
        d = f"gallery/{num}-{key}"
        caps = dict(shots)
        files = sorted(f for f in os.listdir(os.path.join(ROOT, "..", d)) if f.endswith(REAL + (".svg",)))
        out.append(f'<a id="{key}"></a>\n\n<img src="assets/headers/{num}-{key}.svg" width="100%" alt="{num} {title}">\n')
        rows = []
        for j in range(0, len(files), 2):
            rows.append("<tr>" + "".join(cell(d, f, title, caps) for f in files[j:j + 2]) + "</tr>")
        out.append("<table>\n" + "\n".join(rows) + "\n</table>\n")
    return "\n".join(out)


def write_readme():
    p = os.path.join(ROOT, "..", "README.md")
    s = open(p).read()
    a, b = "<!-- gallery:start -->", "<!-- gallery:end -->"
    open(p, "w").write(s[:s.index(a) + len(a)] + "\n" + gallery_md() + "\n" + s[s.index(b):])


if __name__ == "__main__":
    banner(); palette(); type_specimen()
    for num, key, title, sub, shots in SECTIONS:
        header(num, key, title, sub)
        for i, (name, cap) in enumerate(shots):
            tile(num, key, i, name, cap)
    write_readme()
    print("built", sum(len(s[4]) for s in SECTIONS), "tiles,", len(SECTIONS), "headers")
