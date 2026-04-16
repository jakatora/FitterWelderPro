from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Tuple

from PIL import Image, ImageDraw, ImageFont


@dataclass(frozen=True)
class Color:
    r: int
    g: int
    b: int
    a: int = 255

    def as_rgba(self) -> Tuple[int, int, int, int]:
        return (self.r, self.g, self.b, self.a)


def hex_color(value: str, *, alpha: int = 255) -> Color:
    value = value.strip().lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Expected 6 hex chars, got: {value!r}")
    r = int(value[0:2], 16)
    g = int(value[2:4], 16)
    b = int(value[4:6], 16)
    return Color(r, g, b, alpha)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(c1: Color, c2: Color, t: float) -> Color:
    return Color(
        int(round(lerp(c1.r, c2.r, t))),
        int(round(lerp(c1.g, c2.g, t))),
        int(round(lerp(c1.b, c2.b, t))),
        int(round(lerp(c1.a, c2.a, t))),
    )


def cubic_bezier(p0, p1, p2, p3, t: float):
    # Standard cubic Bezier
    x = (
        (1 - t) ** 3 * p0[0]
        + 3 * (1 - t) ** 2 * t * p1[0]
        + 3 * (1 - t) * t**2 * p2[0]
        + t**3 * p3[0]
    )
    y = (
        (1 - t) ** 3 * p0[1]
        + 3 * (1 - t) ** 2 * t * p1[1]
        + 3 * (1 - t) * t**2 * p2[1]
        + t**3 * p3[1]
    )
    return (x, y)


def polyline_from_beziers(segments, steps_per_segment: int = 80):
    points = []
    for (p0, p1, p2, p3) in segments:
        for i in range(steps_per_segment + 1):
            t = i / steps_per_segment
            points.append(cubic_bezier(p0, p1, p2, p3, t))
    return points


def load_font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    # Prefer Segoe UI on Windows, fallback to default.
    windows_fonts = Path("C:/Windows/Fonts")
    candidates: list[Path] = []
    if bold:
        candidates += [
            windows_fonts / "segoeuib.ttf",
            windows_fonts / "SegoeUI-Bold.ttf",
        ]
    candidates += [
        windows_fonts / "segoeui.ttf",
        windows_fonts / "SegoeUI.ttf",
    ]

    for path in candidates:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except Exception:
                pass

    try:
        return ImageFont.truetype("DejaVuSans.ttf", size=size)
    except Exception:
        return ImageFont.load_default()


def rounded_rect(draw: ImageDraw.ImageDraw, xy, radius: int, fill, outline=None, width: int = 1):
    # Pillow supports rounded_rectangle.
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def draw_diagonal_stripes(img: Image.Image, *, spacing: int = 24, stripe_width: int = 10, alpha: int = 10):
    # Subtle diagonal overlay to mimic the SVG pattern.
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    w, h = img.size
    # Draw lines in a rotated coordinate space by drawing long rectangles.
    # We approximate rotation by drawing parallelograms as polygons.
    import math

    angle = math.radians(20)
    dx = math.cos(angle)
    dy = math.sin(angle)

    # Vector perpendicular to stripe direction
    px = -dy
    py = dx

    length = w + h
    # Start positions across a wide range so the full canvas is covered.
    for k in range(-length, length, spacing):
        # Center line point
        cx = k
        cy = 0

        # Build a rectangle around the stripe center, extended far.
        half = stripe_width / 2
        # Two offset edges
        ax = cx + px * half
        ay = cy + py * half
        bx = cx - px * half
        by = cy - py * half

        # Extend along direction
        ex = dx * (length * 2)
        ey = dy * (length * 2)

        poly = [
            (ax, ay),
            (ax + ex, ay + ey),
            (bx + ex, by + ey),
            (bx, by),
        ]
        d.polygon(poly, fill=(255, 255, 255, alpha))

    img.alpha_composite(overlay)


def main() -> None:
    out_dir = Path(__file__).resolve().parent
    out_png = out_dir / "feature_graphic.png"

    width, height = 1024, 500
    bg1 = hex_color("#0B1220")
    bg2 = hex_color("#111827")

    img = Image.new("RGBA", (width, height), (0, 0, 0, 255))

    # Background gradient
    px = img.load()
    for y in range(height):
        t = y / max(1, height - 1)
        c = lerp_color(bg1, bg2, t)
        for x in range(width):
            px[x, y] = c.as_rgba()

    draw_diagonal_stripes(img, spacing=24, stripe_width=10, alpha=10)

    draw = ImageDraw.Draw(img)

    # Decorative "pipe" curve
    steel = hex_color("#C9CDD4")
    steel_dark = Color(17, 24, 39, int(round(0.55 * 255)))

    # Bezier segments approximating: M70 350 C 220 280, 310 390, 450 330 S 720 290, 940 340
    seg1 = ((70, 350), (220, 280), (310, 390), (450, 330))
    # Smooth continuation: reflect control point from seg1 p2 around p3 => (590, 270)
    seg2 = ((450, 330), (590, 270), (720, 290), (940, 340))
    points = polyline_from_beziers([seg1, seg2], steps_per_segment=120)

    # Shadow under the pipe (simple)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.line(points, fill=(0, 0, 0, 115), width=28, joint="curve")
    # Slight blur by down/up sample
    shadow = shadow.resize((width // 2, height // 2), resample=Image.BILINEAR).resize((width, height), resample=Image.BILINEAR)
    img.alpha_composite(shadow)

    # Main stroke and inner dark stroke
    draw.line(points, fill=steel.as_rgba(), width=18, joint="curve")
    draw.line(points, fill=steel_dark.as_rgba(), width=6, joint="curve")

    # Left badge
    badge_x, badge_y = 64, 64
    badge_w, badge_h = 140, 140
    badge_bg = hex_color("#0F172A")
    badge_stroke = Color(229, 231, 235, int(round(0.18 * 255)))

    rounded_rect(
        draw,
        (badge_x, badge_y, badge_x + badge_w, badge_y + badge_h),
        radius=28,
        fill=badge_bg.as_rgba(),
        outline=badge_stroke.as_rgba(),
        width=2,
    )

    # Spark polygon
    center = (badge_x + badge_w // 2, badge_y + 72)
    cx, cy = center
    spark = [
        (cx + 0, cy - 34),
        (cx + 6, cy - 10),
        (cx + 30, cy - 16),
        (cx + 10, cy + 2),
        (cx + 30, cy + 18),
        (cx + 6, cy + 12),
        (cx + 0, cy + 36),
        (cx - 6, cy + 12),
        (cx - 30, cy + 18),
        (cx - 10, cy + 2),
        (cx - 30, cy - 16),
        (cx - 6, cy - 10),
    ]
    draw.polygon(spark, fill=Color(229, 231, 235, int(round(0.92 * 255))).as_rgba())
    draw.ellipse((cx - 7, cy - 7, cx + 7, cy + 7), fill=Color(156, 163, 175, int(round(0.9 * 255))).as_rgba())

    # PRO text
    font_pro = load_font(14, bold=True)
    pro_text = "PRO"
    bbox = draw.textbbox((0, 0), pro_text, font=font_pro)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((badge_x + badge_w / 2 - tw / 2, badge_y + 132 - th), pro_text, font=font_pro, fill=Color(229, 231, 235, int(round(0.88 * 255))).as_rgba())

    # Text block
    title_font = load_font(44, bold=True)
    subtitle_font = load_font(20, bold=False)
    bullet_font = load_font(18, bold=False)

    tx, ty = 232, 88
    draw.text((tx, ty), "Fitter Welder Pro", font=title_font, fill=hex_color("#F9FAFB").as_rgba())
    draw.text(
        (tx, ty + 42),
        "Listy cięcia i parametry spawania",
        font=subtitle_font,
        fill=Color(229, 231, 235, int(round(0.92 * 255))).as_rgba(),
    )

    bullets = [
        "Projekty • Segmenty • Obliczenia cięcia",
        "WPS / parametry spawania pod ręką",
    ]
    bullet_y0 = ty + 80
    for i, text in enumerate(bullets):
        y = bullet_y0 + i * 36
        draw.ellipse((tx + 2, y + 2, tx + 14, y + 14), fill=Color(156, 163, 175, int(round(0.9 * 255))).as_rgba())
        draw.text((tx + 26, y), text, font=bullet_font, fill=Color(229, 231, 235, int(round(0.92 * 255))).as_rgba())

    # Save
    img.convert("RGB").save(out_png, format="PNG", optimize=True)
    print(f"Wrote: {out_png}")


if __name__ == "__main__":
    main()
