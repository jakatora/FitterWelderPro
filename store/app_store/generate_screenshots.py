from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WIDTH = 1242
HEIGHT = 2688
BG_TOP = (15, 17, 23)
BG_BOTTOM = (26, 29, 38)
CARD = (29, 33, 46, 230)
SURFACE = (36, 40, 58, 255)
WHITE = (244, 247, 252)
MUTED = (159, 169, 196)
ORANGE = (245, 166, 35)
GOLD = (232, 193, 75)
BLUE = (74, 158, 255)
GREEN = (46, 204, 113)
RED = (231, 76, 60)
PURPLE = (171, 71, 188)

ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "screenshots"


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend(
            [
                r"C:\Windows\Fonts\segoeuib.ttf",
                r"C:\Windows\Fonts\arialbd.ttf",
                r"C:\Windows\Fonts\calibrib.ttf",
            ]
        )
    else:
        candidates.extend(
            [
                r"C:\Windows\Fonts\segoeui.ttf",
                r"C:\Windows\Fonts\arial.ttf",
                r"C:\Windows\Fonts\calibri.ttf",
            ]
        )

    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size=size)
    return ImageFont.load_default()


TITLE_FONT = load_font(108, bold=True)
SUBTITLE_FONT = load_font(46)
BODY_FONT = load_font(38)
LABEL_FONT = load_font(32, bold=True)
SMALL_FONT = load_font(28)
BIG_STAT_FONT = load_font(56, bold=True)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> str:
    lines = []
    for paragraph in text.split("\n"):
        words = paragraph.split()
        if not words:
            lines.append("")
            continue
        current = words[0]
        for word in words[1:]:
            test = f"{current} {word}"
            if draw.textbbox((0, 0), test, font=font)[2] <= max_width:
                current = test
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return "\n".join(lines)


SCREENS = [
    {
        "name": "iphone67_01_dashboard.png",
        "headline": "Manage pipe projects\nwith shop-floor context",
        "subhead": "Projects, segments, and recent activity in one fast workspace.",
        "accent": ORANGE,
        "chips": ["Projects", "Segments", "Recent work"],
        "stats": [("18", "projects"), ("64", "segments"), ("5", "active today")],
        "panel": "dashboard",
    },
    {
        "name": "iphone67_02_spool.png",
        "headline": "Plan spool routes\nand elbows in 3D",
        "subhead": "Quick direction changes, takeoffs, and field dimensions without losing the route.",
        "accent": BLUE,
        "chips": ["Spool planner", "3D preview", "Takeoffs"],
        "stats": [("3D", "route preview"), ("12", "components"), ("4", "legs")],
        "panel": "spool",
    },
    {
        "name": "iphone67_03_cutlist.png",
        "headline": "Calculate cut lengths\nwith weld gaps included",
        "subhead": "Keep segment questions, field dimensions, and final cut values together.",
        "accent": GREEN,
        "chips": ["Cut list", "Weld gaps", "Field dimensions"],
        "stats": [("1420", "mm main cut"), ("6", "welds"), ("OK", "validation")],
        "panel": "cutlist",
    },
    {
        "name": "iphone67_04_materials.png",
        "headline": "Build material summaries\nand BOM breakdowns",
        "subhead": "Track elbows, reducers, valves, flanges, and straight pipe from one project set.",
        "accent": PURPLE,
        "chips": ["Material list", "BOM", "Components"],
        "stats": [("28", "fittings"), ("7", "valves"), ("2.4 m", "pipe stock")],
        "panel": "materials",
    },
    {
        "name": "iphone67_05_welder.png",
        "headline": "Keep welding data\nand references close",
        "subhead": "Useful screens for welders and fitters without extra setup or cloud accounts.",
        "accent": GOLD,
        "chips": ["Welder tools", "Local data", "Quick access"],
        "stats": [("WPS", "ready"), ("Local", "storage"), ("EN/PL", "language")],
        "panel": "welder",
    },
]


def gradient_background() -> Image.Image:
    image = Image.new("RGBA", (WIDTH, HEIGHT))
    px = image.load()
    for y in range(HEIGHT):
        ratio = y / (HEIGHT - 1)
        r = int(BG_TOP[0] * (1 - ratio) + BG_BOTTOM[0] * ratio)
        g = int(BG_TOP[1] * (1 - ratio) + BG_BOTTOM[1] * ratio)
        b = int(BG_TOP[2] * (1 - ratio) + BG_BOTTOM[2] * ratio)
        for x in range(WIDTH):
            px[x, y] = (r, g, b, 255)
    return image


def draw_glow(base: Image.Image, center: tuple[int, int], radius: int, color: tuple[int, int, int]) -> None:
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    x, y = center
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*color, 70))
    layer = layer.filter(ImageFilter.GaussianBlur(radius=80))
    base.alpha_composite(layer)


def rounded(draw: ImageDraw.ImageDraw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def draw_header(draw: ImageDraw.ImageDraw, headline: str, subhead: str, accent) -> int:
    wrapped_headline = wrap_text(draw, headline, TITLE_FONT, WIDTH - 184)
    wrapped_subhead = wrap_text(draw, subhead, SUBTITLE_FONT, WIDTH - 184)
    draw.text((92, 110), "CUT LIST APP", font=LABEL_FONT, fill=accent)
    draw.multiline_text((92, 180), wrapped_headline, font=TITLE_FONT, fill=WHITE, spacing=8)
    headline_box = draw.multiline_textbbox((92, 180), wrapped_headline, font=TITLE_FONT, spacing=8)
    subhead_y = headline_box[3] + 28
    draw.multiline_text((92, subhead_y), wrapped_subhead, font=SUBTITLE_FONT, fill=MUTED, spacing=8)
    subhead_box = draw.multiline_textbbox((92, subhead_y), wrapped_subhead, font=SUBTITLE_FONT, spacing=8)
    return subhead_box[3] + 34


def draw_chips(draw: ImageDraw.ImageDraw, chips: list[str], accent, top: int) -> int:
    x = 92
    y = top
    for chip in chips:
        bbox = draw.textbbox((0, 0), chip, font=SMALL_FONT)
        width = (bbox[2] - bbox[0]) + 56
        rounded(draw, (x, y, x + width, y + 64), 30, CARD, outline=(*accent, 180), width=2)
        draw.text((x + 28, y + 15), chip, font=SMALL_FONT, fill=accent)
        x += width + 18
    return y + 94


def draw_stats(draw: ImageDraw.ImageDraw, stats, accent, top: int) -> int:
    left = 92
    box_w = 330
    box_h = 170
    for value, label in stats:
        rounded(draw, (left, top, left + box_w, top + box_h), 34, CARD, outline=(90, 100, 128, 180), width=2)
        draw.text((left + 30, top + 30), value, font=BIG_STAT_FONT, fill=WHITE)
        draw.text((left + 32, top + 104), label, font=SMALL_FONT, fill=accent)
        left += box_w + 18
    return top + box_h + 42


def draw_phone_shell(draw: ImageDraw.ImageDraw) -> tuple[int, int, int, int]:
    box = (86, 960, WIDTH - 86, HEIGHT - 120)
    rounded(draw, box, 82, (8, 10, 16, 255), outline=(95, 106, 136, 255), width=4)
    rounded(draw, (box[0] + 24, box[1] + 24, box[2] - 24, box[3] - 24), 64, (18, 22, 32, 255))
    draw.rounded_rectangle((WIDTH // 2 - 120, box[1] + 32, WIDTH // 2 + 120, box[1] + 70), radius=18, fill=(10, 12, 16, 255))
    return (box[0] + 42, box[1] + 110, box[2] - 42, box[3] - 42)


def draw_top_bar(draw: ImageDraw.ImageDraw, frame, title: str, accent) -> int:
    x0, y0, x1, _ = frame
    rounded(draw, (x0, y0, x1, y0 + 108), 28, SURFACE)
    draw.text((x0 + 26, y0 + 28), title, font=LABEL_FONT, fill=WHITE)
    rounded(draw, (x1 - 138, y0 + 24, x1 - 26, y0 + 82), 20, (*accent, 40), outline=(*accent, 220), width=2)
    draw.text((x1 - 102, y0 + 37), "EN", font=SMALL_FONT, fill=accent)
    return y0 + 132


def draw_list_item(draw: ImageDraw.ImageDraw, x0, y0, x1, title, subtitle, accent, pill=None):
    rounded(draw, (x0, y0, x1, y0 + 126), 26, CARD, outline=(83, 94, 120, 180), width=2)
    draw.ellipse((x0 + 24, y0 + 34, x0 + 58, y0 + 68), fill=accent)
    draw.text((x0 + 82, y0 + 24), title, font=BODY_FONT, fill=WHITE)
    draw.text((x0 + 82, y0 + 70), subtitle, font=SMALL_FONT, fill=MUTED)
    if pill:
        pill_w = 160
        rounded(draw, (x1 - pill_w - 22, y0 + 34, x1 - 22, y0 + 82), 18, (*accent, 35), outline=(*accent, 220), width=2)
        draw.text((x1 - pill_w - 22 + 26, y0 + 46), pill, font=SMALL_FONT, fill=accent)


def draw_dashboard(draw: ImageDraw.ImageDraw, frame, accent):
    x0, y = frame[0], draw_top_bar(draw, frame, "Home", accent)
    x1 = frame[2]
    rounded(draw, (x0, y, x1, y + 220), 34, (30, 34, 52, 255))
    draw.text((x0 + 28, y + 24), "FITTER  WELDER  PRO", font=LABEL_FONT, fill=WHITE)
    draw.text((x0 + 28, y + 78), "Overview of projects, segments, and tools", font=SMALL_FONT, fill=MUTED)
    rounded(draw, (x0 + 28, y + 126, x0 + 240, y + 188), 24, (*ORANGE, 35), outline=(*ORANGE, 200), width=2)
    draw.text((x0 + 56, y + 144), "FITTER", font=SMALL_FONT, fill=ORANGE)
    rounded(draw, (x0 + 262, y + 126, x0 + 474, y + 188), 24, (*BLUE, 35), outline=(*BLUE, 200), width=2)
    draw.text((x0 + 308, y + 144), "WELDER", font=SMALL_FONT, fill=BLUE)
    y += 252
    for row in [
        ("Refinery line A-204", "DN150 / Carbon steel", "Open"),
        ("Steam branch B-17", "DN80 / Stainless", "Recent"),
        ("Workshop skid C-12", "DN50 / Mixed fittings", "Ready"),
    ]:
        draw_list_item(draw, x0, y, x1, row[0], row[1], accent, row[2])
        y += 146


def draw_spool(draw: ImageDraw.ImageDraw, frame, accent):
    x0, y = frame[0], draw_top_bar(draw, frame, "Spool planner", accent)
    x1 = frame[2]
    rounded(draw, (x0, y, x1, y + 440), 34, CARD)
    draw.text((x0 + 26, y + 24), "Route preview", font=LABEL_FONT, fill=WHITE)
    draw.text((x0 + 26, y + 74), "Elbows and legs update instantly", font=SMALL_FONT, fill=MUTED)
    points = [(x0 + 80, y + 310), (x0 + 250, y + 310), (x0 + 250, y + 210), (x0 + 480, y + 210), (x0 + 480, y + 120), (x0 + 700, y + 120)]
    for a, b in zip(points, points[1:]):
        draw.line((a, b), fill=accent, width=18)
        draw.ellipse((a[0] - 18, a[1] - 18, a[0] + 18, a[1] + 18), fill=WHITE)
    draw.ellipse((points[-1][0] - 18, points[-1][1] - 18, points[-1][0] + 18, points[-1][1] + 18), fill=WHITE)
    y += 470
    for row in [
        ("Leg X", "Field dim 1820 mm", "CUT 1420"),
        ("Leg Y", "Takeoff 215 mm", "CUT 610"),
        ("Leg Z", "Open end / elbow 90°", "CHECK"),
    ]:
        draw_list_item(draw, x0, y, x1, row[0], row[1], accent, row[2])
        y += 146


def draw_cutlist(draw: ImageDraw.ImageDraw, frame, accent):
    x0, y = frame[0], draw_top_bar(draw, frame, "Cut list summary", accent)
    x1 = frame[2]
    for row in [
        ("Segment S-01", "Pipe DN150 / 2 elbows / valve", "CUT 1420 mm"),
        ("Segment S-02", "Pipe DN80 / reducer / flange", "CUT 880 mm"),
        ("Segment S-03", "Pipe DN50 / field weld gap 3 mm", "CUT 515 mm"),
    ]:
        draw_list_item(draw, x0, y, x1, row[0], row[1], accent, row[2])
        y += 146
    rounded(draw, (x0, y + 16, x1, y + 246), 34, (24, 44, 34, 255), outline=(*accent, 170), width=2)
    draw.text((x0 + 28, y + 44), "Validation", font=LABEL_FONT, fill=WHITE)
    draw.text((x0 + 28, y + 102), "ISO references and weld gaps are included before final cut export.", font=SMALL_FONT, fill=MUTED)
    rounded(draw, (x1 - 210, y + 44, x1 - 30, y + 110), 24, (*accent, 40), outline=(*accent, 220), width=2)
    draw.text((x1 - 164, y + 61), "PASS", font=SMALL_FONT, fill=accent)


def draw_materials(draw: ImageDraw.ImageDraw, frame, accent):
    x0, y = frame[0], draw_top_bar(draw, frame, "Material list", accent)
    x1 = frame[2]
    columns = [
        ("Elbow 90°", "12 pcs", accent),
        ("Flange", "7 pcs", BLUE),
        ("Valve", "4 pcs", ORANGE),
        ("Reducer", "5 pcs", GREEN),
    ]
    col_y = y
    for idx, (title, value, color) in enumerate(columns):
        left = x0 + (idx % 2) * ((x1 - x0 - 20) // 2 + 20)
        top = col_y + (idx // 2) * 180
        right = left + (x1 - x0 - 20) // 2
        rounded(draw, (left, top, right, top + 160), 30, CARD, outline=(*color, 160), width=2)
        draw.text((left + 24, top + 28), title, font=BODY_FONT, fill=WHITE)
        draw.text((left + 24, top + 92), value, font=LABEL_FONT, fill=color)
    y += 390
    draw_list_item(draw, x0, y, x1, "Pipe stock total", "2.4 m ready for cutting", accent, "BOM")
    y += 146
    draw_list_item(draw, x0, y, x1, "Export summary", "Grouped by project and segment", accent, "CSV")


def draw_welder(draw: ImageDraw.ImageDraw, frame, accent):
    x0, y = frame[0], draw_top_bar(draw, frame, "Welder menu", accent)
    x1 = frame[2]
    entries = [
        ("Weld journal", "Keep key welding notes close", BLUE),
        ("Heat photos", "Reference photos for work progress", ORANGE),
        ("Pipe tools", "Quick helpers for shop-floor tasks", GREEN),
        ("EN / PL", "Language switch in the app", accent),
    ]
    for title, subtitle, color in entries:
        draw_list_item(draw, x0, y, x1, title, subtitle, color, "Open")
        y += 146
    rounded(draw, (x0, y + 10, x1, y + 220), 34, CARD, outline=(*accent, 150), width=2)
    draw.text((x0 + 28, y + 42), "Local first", font=LABEL_FONT, fill=WHITE)
    draw.text((x0 + 28, y + 100), "The standard workflow works on-device without account setup.", font=SMALL_FONT, fill=MUTED)


PANEL_DRAWERS = {
    "dashboard": draw_dashboard,
    "spool": draw_spool,
    "cutlist": draw_cutlist,
    "materials": draw_materials,
    "welder": draw_welder,
}


def draw_footer(draw: ImageDraw.ImageDraw) -> None:
    draw.text((92, HEIGHT - 100), "Prepared for App Store Connect • 1242 × 2688", font=SMALL_FONT, fill=(120, 130, 156))


def render_screen(config: dict) -> None:
    image = gradient_background()
    draw_glow(image, (WIDTH - 220, 320), 280, config["accent"])
    draw_glow(image, (200, HEIGHT - 320), 240, BLUE)
    draw = ImageDraw.Draw(image, "RGBA")
    next_y = draw_header(draw, config["headline"], config["subhead"], config["accent"])
    next_y = draw_chips(draw, config["chips"], config["accent"], next_y)
    draw_stats(draw, config["stats"], config["accent"], next_y)
    frame = draw_phone_shell(draw)
    PANEL_DRAWERS[config["panel"]](draw, frame, config["accent"])
    draw_footer(draw)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(OUT_DIR / config["name"], quality=95)


def main() -> None:
    for screen in SCREENS:
        render_screen(screen)
    print(f"Generated {len(SCREENS)} screenshots in {OUT_DIR}")


if __name__ == "__main__":
    main()