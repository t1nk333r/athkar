"""Draws the app icons and the previews «أيقونة التطبيق» shows in الإعدادات.

    python3 tools/app-icons.py

Two drawings, each in light, dark and tinted versions (iOS 18 picks one from the home screen's
appearance; iOS 17 shows the light one):

- AppIcon, the default: the letter ب from KFGQPC Uthman Taha Naskh, the face the adhkar are set
  in. Its body is ink and its dot is the accent. The font draws ب as two components, the dotless
  beh (U+066E) and the dot, so each takes its own colour.
- AppIconHorizon, the alternate: a half sun in the accent on an ink horizon, for بكرة وأصيلا,
  morning and evening.
- AppIconLetter, an alternate copy of AppIcon. «الباء» in الإعدادات switches to it instead of back
  to the primary icon: on iOS 26.1 `setAlternateIconName(nil)` can leave the alternate icon on the
  home screen (https://developer.apple.com/forums/thread/809474).

The colours are the palette's (ios/Athkar/Design/Palette.swift). The light icon is ink on paper.
The dark and tinted icons have no background, so iOS draws its own behind them: the dark one in
the dark palette's ink and accent, the tinted one in greys that iOS tints. Each preview is 60 pt
at 3x, light and dark.

Needs fontTools and resvg (RESVG, or resvg on PATH). It rewrites the PNGs and Contents.json files
under ios/Athkar/Assets.xcassets.
"""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

REPO = Path(__file__).resolve().parent.parent
FONT = REPO / "fonts" / "kfgqpc-uthman-taha-naskh.ttf"
CATALOG = REPO / "ios" / "Athkar" / "Assets.xcassets"
SIDE = 1024
PREVIEW = 180

# Each appearance: background (None for none), the main shape, the accent.
LIGHT = ("#f5f1e8", "#1e1c17", "#8f3424")
DARK = (None, "#ece6d9", "#db8f71")
TINTED = (None, "#ffffff", "#9a9a9a")
# Behind the dark preview, the dark palette's raised surface, since the app draws it in a list.
DARK_PREVIEW_BACKGROUND = "#26241f"


def beh_paths() -> tuple[str, str]:
    """The isolated beh's body and dot as SVG path data in icon pixels, the glyph's bounding box
    centred and 600 px wide."""
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    glyf = font["glyf"]
    beh = glyf[font.getBestCmap()[0x628]]
    body, dot = beh.components
    assert body.glyphName == font.getBestCmap()[0x66E], "ب is no longer the dotless beh and a dot"
    beh.recalcBounds(glyf)
    scale = 600 / (beh.xMax - beh.xMin)
    dx = SIDE / 2 - scale * (beh.xMin + beh.xMax) / 2
    # The dot hangs below a heavy body; sitting 12 px above centre balances them.
    dy = SIDE / 2 - 12 + scale * (beh.yMin + beh.yMax) / 2

    def path(component) -> str:
        pen = SVGPathPen(glyphs)
        x, y = component.x, component.y
        glyphs[component.glyphName].draw(TransformPen(pen, (scale, 0, 0, -scale, dx + scale * x, dy - scale * y)))
        return pen.getCommands()

    return path(body), path(dot)


def letter(colours: tuple, body: str, dot: str) -> str:
    background, ink, accent = colours
    return svg(background, f'<path d="{body}" fill="{ink}"/><path d="{dot}" fill="{accent}"/>')


def horizon(colours: tuple) -> str:
    background, ink, accent = colours
    return svg(background,
               '<clipPath id="above"><rect width="1024" height="600"/></clipPath>'
               f'<circle cx="512" cy="600" r="196" fill="{accent}" clip-path="url(#above)"/>'
               f'<rect x="166" y="593" width="692" height="14" rx="7" fill="{ink}"/>')


def svg(background, shapes: str) -> str:
    fill = f'<rect width="1024" height="1024" fill="{background}"/>' if background else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIDE} {SIDE}">{fill}{shapes}</svg>'


def render(source: str, png: Path, width: int, work: Path) -> None:
    resvg = os.environ.get("RESVG") or shutil.which("resvg")
    if not resvg:
        raise SystemExit("resvg is missing; install it or set RESVG")
    svg_path = work / (png.stem + ".svg")
    svg_path.write_text(source, encoding="utf-8")
    subprocess.run([resvg, "-w", str(width), str(svg_path), str(png)], check=True)


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def icon_set(name: str, drawings: dict, work: Path) -> None:
    folder = CATALOG / f"{name}.appiconset"
    folder.mkdir(exist_ok=True)
    images = []
    for appearance, source in drawings.items():
        filename = f"{name}-1024{'' if appearance == 'any' else '-' + appearance}.png"
        render(source, folder / filename, SIDE, work)
        image = {"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename}
        if appearance != "any":
            image["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        images.append(image)
    write_json(folder / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})


def preview_set(name: str, light: str, dark: str, work: Path) -> None:
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(exist_ok=True)
    render(light, folder / f"{name}.png", PREVIEW, work)
    render(dark, folder / f"{name}-dark.png", PREVIEW, work)
    write_json(folder / "Contents.json", {
        "images": [
            {"idiom": "universal", "scale": "3x", "filename": f"{name}.png"},
            {"idiom": "universal", "scale": "3x", "filename": f"{name}-dark.png",
             "appearances": [{"appearance": "luminosity", "value": "dark"}]},
        ],
        "info": {"author": "xcode", "version": 1},
    })


def main() -> None:
    body, dot = beh_paths()
    dark_preview = (DARK_PREVIEW_BACKGROUND, *DARK[1:])
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        letters = {"any": letter(LIGHT, body, dot), "dark": letter(DARK, body, dot),
                   "tinted": letter(TINTED, body, dot)}
        icon_set("AppIcon", letters, work)
        icon_set("AppIconLetter", letters, work)
        icon_set("AppIconHorizon", {"any": horizon(LIGHT), "dark": horizon(DARK), "tinted": horizon(TINTED)}, work)
        preview_set("IconChoiceLetter", letter(LIGHT, body, dot), letter(dark_preview, body, dot), work)
        preview_set("IconChoiceHorizon", horizon(LIGHT), horizon(dark_preview), work)


if __name__ == "__main__":
    main()
