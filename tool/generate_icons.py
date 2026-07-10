"""Generuje komplet ikon Fitter Welder Pro z jednego mistrza wektorowego.

Znak: przekrój rury (pierścień ze stali), którego fragment ścianki jest
rozżarzony. Strefa wpływu ciepła wygasa w metal — brak konturu, brak
"czapek", więc ikona nie czyta się jak pierścień postępu.

Uruchomienie (z katalogu projektu):
    python tool/generate_icons.py

Wymaga: cairosvg, pillow.   pip install cairosvg pillow
Nadpisuje:
    assets/icons/app_icon.png                    (stara wersja -> app_icon_legacy.png)
    ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-*.png
    android/app/src/main/res/mipmap-*/ic_launcher.png
    android/app/src/main/res/drawable-*/ic_launcher_foreground.png   (przezroczyste!)
"""
import math
import os
import shutil
import glob

import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CX = CY = 512
R_OUT, R_IN = 344, 214
A_LO, A_HI = -88, 20  # rozżarzony odcinek ścianki, godz. ~1-2


def pt(r, deg):
    a = math.radians(deg)
    return CX + r * math.cos(a), CY + r * math.sin(a)


def sector(a1, a2, r_in=R_IN, r_out=R_OUT):
    """Wycinek pierścienia — promieniowe krawędzie, bez zaokrągleń."""
    x1o, y1o = pt(r_out, a1)
    x2o, y2o = pt(r_out, a2)
    x2i, y2i = pt(r_in, a2)
    x1i, y1i = pt(r_in, a1)
    la = 1 if abs(a2 - a1) > 180 else 0
    return (f"M{x1o:.2f},{y1o:.2f} A{r_out},{r_out} 0 {la},1 {x2o:.2f},{y2o:.2f} "
            f"L{x2i:.2f},{y2i:.2f} A{r_in},{r_in} 0 {la},0 {x1i:.2f},{y1i:.2f} Z")


def ramp(a1, a2, fill, n, power, opac):
    """Pasmo wycinków z opacity wg krzywej dzwonowej — gorąco wygasa w stal."""
    out = []
    span = a2 - a1
    for i in range(n):
        tm = (i + 0.5) / n
        o = (math.sin(math.pi * tm) ** power) * opac
        if o < 0.02:
            continue
        d = sector(a1 + span * (i / n) - 0.9, a1 + span * ((i + 1) / n) + 0.9)
        out.append(f'<path d="{d}" fill="{fill}" opacity="{o:.3f}"/>')
    return "".join(out)


DEFS = """
  <defs>
    <linearGradient id="bg" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#222833"/>
      <stop offset="0.5" stop-color="#141821"/>
      <stop offset="1" stop-color="#080B10"/>
    </linearGradient>
    <linearGradient id="steel" x1="0.15" y1="0.05" x2="0.85" y2="0.95">
      <stop offset="0" stop-color="#DCE2EE"/>
      <stop offset="0.38" stop-color="#9CA5BA"/>
      <stop offset="0.78" stop-color="#6A7488"/>
      <stop offset="1" stop-color="#4E5768"/>
    </linearGradient>
    <linearGradient id="amber" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#FFD062"/>
      <stop offset="0.45" stop-color="#FF8E1E"/>
      <stop offset="1" stop-color="#E0570F"/>
    </linearGradient>
    <radialGradient id="heat" cx="0.66" cy="0.28" r="0.5">
      <stop offset="0" stop-color="#FF8A1F" stop-opacity="0.50"/>
      <stop offset="1" stop-color="#FF8A1F" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="bore" x1="0.3" y1="0" x2="0.7" y2="1">
      <stop offset="0" stop-color="#0D1118"/>
      <stop offset="1" stop-color="#05070A"/>
    </linearGradient>
  </defs>
"""

HEAT = ramp(A_LO, A_HI, "url(#amber)", 72, 0.50, 1.0)
CORE = ramp(A_LO + 26, A_HI - 26, "#FFE9C2", 56, 1.7, 0.92)

MARK = f"""
  <path d="M{CX},{CY-R_OUT} a{R_OUT},{R_OUT} 0 1,0 0.1,0 Z
           M{CX},{CY-R_IN} a{R_IN},{R_IN} 0 1,1 -0.1,0 Z"
        fill="url(#steel)" fill-rule="evenodd"/>
  {HEAT}
  {CORE}
  <path d="{sector(150, 205, R_IN+22, R_OUT-22)}" fill="#FFFFFF" opacity="0.13"/>
  <circle cx="{CX}" cy="{CY}" r="{R_IN}" fill="url(#bore)"/>
  <circle cx="{CX}" cy="{CY}" r="{R_IN}" fill="none" stroke="#000" stroke-opacity="0.45" stroke-width="12"/>
  <g fill="#FFD98A">
    <circle cx="790" cy="214" r="11" opacity="0.9"/>
    <circle cx="846" cy="286" r="7" opacity="0.75"/>
    <circle cx="742" cy="150" r="6" opacity="0.6"/>
  </g>
"""

# Pełna ikona (iOS / legacy launcher): tło wypełnia kadr.
SVG_FULL = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
{DEFS}
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <circle cx="{CX}" cy="{CY}" r="500" fill="url(#heat)" opacity="0.45"/>
  {MARK}
</svg>"""

# Warstwa foreground Androida: PRZEZROCZYSTA, sam znak.
# Skala 0.90 trzyma iskry wewnątrz strefy bezpiecznej maski adaptive
# (znak zajmuje wtedy ~61% kadru 108dp, przy wymaganych max 66%).
SVG_MARK = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
{DEFS}
  <g transform="translate({CX},{CY}) scale(0.90) translate({-CX},{-CY})">
    <circle cx="{CX}" cy="{CY}" r="470" fill="url(#heat)" opacity="0.35"/>
    {MARK}
  </g>
</svg>"""


def render(svg: str, path: str, size: int, opaque: bool):
    cairosvg.svg2png(bytestring=svg.encode("utf-8"), write_to=path,
                     output_width=size, output_height=size)
    im = Image.open(path)
    if opaque:
        # iOS odrzuca kanał alfa w ikonie aplikacji.
        bg = Image.new("RGB", im.size, (20, 24, 33))
        bg.paste(im.convert("RGBA"), (0, 0), im.convert("RGBA"))
        bg.save(path)
    else:
        im.convert("RGBA").save(path)


def main():
    n = 0

    # 0. kopia zapasowa dotychczasowej ikony
    legacy_src = os.path.join(ROOT, "assets", "icons", "app_icon.png")
    legacy_dst = os.path.join(ROOT, "assets", "icons", "app_icon_legacy.png")
    if os.path.exists(legacy_src) and not os.path.exists(legacy_dst):
        shutil.copy2(legacy_src, legacy_dst)
        print(f"kopia zapasowa -> {legacy_dst}")

    # 1. mistrz wektorowy w repo
    master_svg = os.path.join(ROOT, "assets", "icons", "app_icon.svg")
    with open(master_svg, "w", encoding="utf-8") as fh:
        fh.write(SVG_FULL)
    print(f"master  {master_svg}")

    # 2. ikona w assets (używana w aplikacji)
    render(SVG_FULL, legacy_src, 1024, opaque=True)
    n += 1

    # 3. iOS — każdy istniejący plik odtwarzamy w jego rozmiarze, bez alfy
    ios = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for f in sorted(glob.glob(os.path.join(ios, "Icon-App-*.png"))):
        size = Image.open(f).size[0]
        render(SVG_FULL, f, size, opaque=True)
        n += 1
    print(f"iOS     {len(glob.glob(os.path.join(ios, 'Icon-App-*.png')))} plików (RGB, bez alfy)")

    # 4. Android legacy launcher
    for f in sorted(glob.glob(os.path.join(ROOT, "android", "app", "src", "main", "res",
                                           "mipmap-*", "ic_launcher.png"))):
        size = Image.open(f).size[0]
        render(SVG_FULL, f, size, opaque=False)
        n += 1

    # 5. Android adaptive foreground — musi być PRZEZROCZYSTY,
    #    inaczej przykrywa @color/ic_launcher_background.
    for f in sorted(glob.glob(os.path.join(ROOT, "android", "app", "src", "main", "res",
                                           "drawable-*", "ic_launcher_foreground.png"))):
        size = Image.open(f).size[0]
        render(SVG_MARK, f, size, opaque=False)
        n += 1
    print("Android mipmap + adaptive foreground (RGBA)")

    print(f"\ngotowe: {n} plików PNG wygenerowanych z {os.path.basename(master_svg)}")


if __name__ == "__main__":
    main()
