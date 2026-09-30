#!/usr/bin/env python3
"""Render the README banner with the shell's own QML components.

HiraethMark and Starfield are copied out of the AMBXST source and drawn offscreen with qml6,
with the Hiraeth palette standing in for the shell's theme singletons. Each scene is drawn at
SS times its final size and downscaled with Lanczos for clean hairlines.
Run: python3 assets/render.py   (needs qml6 and Pillow)
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
SRC = Path.home() / ".local/src/ambxst/modules/components"
SS = 4

SKY = """
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#0b1330" }
            GradientStop { position: 1; color: "#05070f" }
        }
    }
    Starfield { anchors.fill: parent; count: %(stars)d; galaxy: 0; seed: %(seed)d; shooting: false; strength: 0.85; phase: 0.3; driftPhase: 0.2 }
"""

MARK = """
    HiraethMark {
        width: %(mw)d; height: %(mh)d
        anchors.centerIn: parent
        anchors.verticalCenterOffset: %(dy)d
        mode: "lockup"
        tagline: %(tag)s
        playOnShow: false
        ambient: true
        phase: 0.08
        reveal: 1
        hairPx: %(hair)s
        starScale: %(star)s
    }
"""

SCENES = {
    # name: (width, height, output scale, body)
    "banner": (1280, 520, 2, SKY % dict(stars=150, seed=7)
               + MARK % dict(mw=620, mh=400, dy=0, tag="true", hair=1.2, star=0.7)),
}

WRAP = """import QtQuick
import qs.modules.components
Item {
    id: canvas
    width: %(W)d * %(K)d; height: %(H)d * %(K)d
    Item {
        width: %(W)d; height: %(H)d
        scale: %(K)d
        transformOrigin: Item.TopLeft
%(body)s
    }
    Timer { interval: 400; running: true; onTriggered: canvas.grabToImage(r => { r.saveToFile("%(out)s"); Qt.quit(); }) }
}
"""


def stage(t):
    comp, theme, conf = t / "qs/modules/components", t / "qs/modules/theme", t / "qs/config"
    for d in (comp, theme, conf):
        d.mkdir(parents=True)
    for p in ("HiraethMark.qml", "Starfield.qml"):
        shutil.copy(SRC / p, comp)
    (comp / "qmldir").write_text("module qs.modules.components\nHiraethMark 1.0 HiraethMark.qml\nStarfield 1.0 Starfield.qml\n")
    (theme / "qmldir").write_text("module qs.modules.theme\nsingleton Colors 1.0 Colors.qml\nsingleton Motion 1.0 Motion.qml\n")
    (theme / "Colors.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject {\n property color primary: "#cfdaf7"\n'
        ' property color overBackground: "#e6eaf8"\n property color overSurface: "#cfdaf7"\n'
        ' property color error: "#ffb4ab"\n}\n')
    # Motion off: nothing animates, the still frame is set explicitly.
    (theme / "Motion.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool enabled: false }\n")
    (conf / "qmldir").write_text("module qs.config\nsingleton Config 1.0 Config.qml\n")
    (conf / "Config.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property QtObject theme: QtObject { property string monoFont: "Iosevka Nerd Font" } }\n')


def render(name, w, h, scale, body):
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        stage(t)
        k = SS * scale
        (t / "Scene.qml").write_text(WRAP % dict(W=w, H=h, K=k, body=body, out=t / "big.png"))
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        subprocess.run(["qml6", "-I", str(t), str(t / "Scene.qml")], env=env, check=True, capture_output=True, timeout=180)
        big = Image.open(t / "big.png").convert("RGB")
    out = ROOT / f"{name}.png"
    big.resize((w * scale, h * scale), Image.LANCZOS).save(out, optimize=True)
    return out


if __name__ == "__main__":
    for name, (w, h, scale, body) in SCENES.items():
        out = render(name, w, h, scale, body)
        assert Image.open(out).size == (w * scale, h * scale)
        print(out.relative_to(ROOT.parent))
