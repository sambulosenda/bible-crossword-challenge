#!/usr/bin/env python3
"""
Compose App Store marketing screenshots from raw simulator captures.

Creative direction: "Quiet Morning" — warm parchment + ink + gold.
Not the live Store electric-blue / blue-scribble style.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

# 6.9" App Store portrait
W, H = 1320, 2868

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "simulator-screenshots" / "appstore-6.9"
OUT = SRC / "composited"

# Type
FONT_DISPLAY = "/Library/Fonts/SF-Pro-Display-Bold.otf"
FONT_DISPLAY_BLACK = "/Library/Fonts/SF-Pro-Display-Black.otf"
FONT_SERIF = "/System/Library/Fonts/NewYork.ttf"
FONT_SERIF_ITALIC = "/System/Library/Fonts/NewYorkItalic.ttf"
FONT_UI = "/Library/Fonts/SF-Pro-Display-Semibold.otf"

# Palette — quiet morning (cream / ink / gold)
CREAM = (247, 241, 232)
CREAM_MID = (236, 228, 216)
MIST = (214, 224, 232)
DUSK = (168, 186, 204)
INK = (26, 35, 50)
INK_SOFT = (55, 66, 82)
GOLD = (184, 142, 72)
GOLD_SOFT = (212, 180, 120)
WHITE = (255, 255, 255)
BEZEL = (22, 24, 28)

SHOTS = [
    {
        "src": "01-today-home.png",
        "out": "01-today-home.jpg",
        "kicker": "EVERY MORNING",
        "lines": ["A new Bible", "crossword", "every day"],
        "accent_line": 2,  # 0-based index of line to underline in gold
    },
    {
        "src": "02-completion.png",
        "out": "02-completion.jpg",
        "kicker": "GROW IN THE WORD",
        "lines": ["Learn Scripture", "as you solve"],
        "accent_line": 0,
    },
    {
        "src": "03-today-streak.png",
        "out": "03-today-streak.jpg",
        "kicker": "STAY CONSISTENT",
        "lines": ["Build a daily", "faith habit"],
        "accent_line": 1,
    },
    {
        "src": "04-packs.png",
        "out": "04-packs.jpg",
        "kicker": "THEMED COLLECTIONS",
        "lines": ["Stories you know.", "Puzzles you'll love."],
        "accent_line": 0,
    },
    {
        "src": "05-crossword-midsolve.png",
        "out": "05-crossword-midsolve.jpg",
        "kicker": "REAL CROSSWORDS",
        "lines": ["Scripture clues.", "Real play."],
        "accent_line": 0,
    },
    {
        "src": "06-daily-mini.png",
        "out": "06-daily-mini.jpg",
        "kicker": "BUSY DAY?",
        "lines": ["Got 5 minutes?", "Play the Mini"],
        "accent_line": 1,
    },
    {
        "src": "07a-challenge-result.png",
        "out": "07a-challenge-result.jpg",
        "kicker": "PLAY TOGETHER",
        "lines": ["Challenge a friend.", "Beat their time."],
        "accent_line": 0,
    },
]


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype(FONT_DISPLAY, size)


def vertical_gradient(size: tuple[int, int]) -> Image.Image:
    """Cream → mist → soft dusk. Quiet, not neon."""
    img = Image.new("RGB", size)
    px = img.load()
    w, h = size
    for y in range(h):
        t = y / (h - 1)
        if t < 0.45:
            u = t / 0.45
            r = int(CREAM[0] + (CREAM_MID[0] - CREAM[0]) * u)
            g = int(CREAM[1] + (CREAM_MID[1] - CREAM[1]) * u)
            b = int(CREAM[2] + (CREAM_MID[2] - CREAM[2]) * u)
        elif t < 0.75:
            u = (t - 0.45) / 0.30
            r = int(CREAM_MID[0] + (MIST[0] - CREAM_MID[0]) * u)
            g = int(CREAM_MID[1] + (MIST[1] - CREAM_MID[1]) * u)
            b = int(CREAM_MID[2] + (MIST[2] - CREAM_MID[2]) * u)
        else:
            u = (t - 0.75) / 0.25
            r = int(MIST[0] + (DUSK[0] - MIST[0]) * u)
            g = int(MIST[1] + (DUSK[1] - MIST[1]) * u)
            b = int(MIST[2] + (DUSK[2] - MIST[2]) * u)
        for x in range(w):
            # Soft radial wash — slightly brighter center
            cx, cy = w * 0.5, h * 0.35
            d = math.hypot(x - cx, y - cy) / (w * 0.85)
            lift = max(0.0, 1.0 - d) * 10
            px[x, y] = (
                min(255, int(r + lift)),
                min(255, int(g + lift)),
                min(255, int(b + lift)),
            )
    return img


def soft_vignette(base: Image.Image, strength: float = 0.12) -> Image.Image:
    w, h = base.size
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    # Edge darken
    for i in range(80):
        a = int(255 * strength * (i / 80) ** 1.6)
        draw.rectangle([i, i, w - 1 - i, h - 1 - i], outline=(20, 24, 32, a))
    return Image.alpha_composite(base.convert("RGBA"), overlay).convert("RGB")


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def drop_shadow(
    size: tuple[int, int],
    radius: int,
    blur: int = 48,
    offset: tuple[int, int] = (0, 36),
    opacity: int = 90,
) -> Image.Image:
    """Soft layered phone shadow on transparent canvas larger than phone."""
    pad = blur * 2 + max(abs(offset[0]), abs(offset[1])) + 8
    canvas = Image.new("RGBA", (size[0] + pad * 2, size[1] + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=(18, 24, 36, opacity))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, (pad + offset[0], pad + offset[1]))
    # Second softer layer
    soft = Image.new("RGBA", size, (0, 0, 0, 0))
    d2 = ImageDraw.Draw(soft)
    d2.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=(18, 24, 36, 40))
    soft = soft.filter(ImageFilter.GaussianBlur(blur + 24))
    canvas.alpha_composite(soft, (pad, pad + offset[1] // 2))
    return canvas, pad


def make_phone(screenshot: Image.Image, phone_w: int = 980) -> Image.Image:
    """Frame screenshot in a slim modern bezel.

    Captures already include status bar + Dynamic Island — do not draw a second
    island on top (that stacks into a double black pill).
    """
    bezel = 12
    top_chin = 12
    bottom_chin = 14
    corner = 78
    screen_corner = 64

    screen_w = phone_w - bezel * 2
    scale = screen_w / screenshot.width
    screen_h = int(screenshot.height * scale)
    shot = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    phone_h = screen_h + top_chin + bottom_chin
    phone = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(phone)

    # Outer bezel — deep ink, not pure black
    draw.rounded_rectangle([0, 0, phone_w - 1, phone_h - 1], radius=corner, fill=BEZEL)

    # Warm gold hairline (brand accent, not neon blue)
    inset = 3
    draw.rounded_rectangle(
        [inset, inset, phone_w - 1 - inset, phone_h - 1 - inset],
        radius=corner - 2,
        outline=(*GOLD_SOFT, 110),
        width=2,
    )

    # Inner rim
    draw.rounded_rectangle(
        [bezel - 2, top_chin - 2, phone_w - bezel + 1, phone_h - bottom_chin + 1],
        radius=screen_corner + 4,
        fill=(10, 12, 14, 255),
    )

    sx, sy = bezel, top_chin
    mask = rounded_mask((screen_w, screen_h), screen_corner)
    shot_rgba = shot.convert("RGBA")
    screen_layer = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    screen_layer.paste(shot_rgba, (0, 0), mask)
    phone.paste(screen_layer, (sx, sy), mask)

    return phone


def draw_text_block(
    canvas: Image.Image,
    kicker: str,
    lines: list[str],
    accent_line: int,
) -> int:
    """Draw kicker + headline. Returns y just below text block."""
    draw = ImageDraw.Draw(canvas)
    font_kicker = load_font(FONT_UI, 28)
    font_head = load_font(FONT_DISPLAY_BLACK, 92)

    # Try serif for a more editorial spiritual feel on headlines
    try:
        font_head = ImageFont.truetype(FONT_SERIF, 96)
    except OSError:
        pass

    margin_x = 88
    y = 120

    # Kicker
    kicker = kicker.upper()
    # letter-spacing simulation
    kicker_w = 0
    glyphs = []
    spacing = 6
    for ch in kicker:
        bw = draw.textlength(ch, font=font_kicker)
        glyphs.append((ch, bw))
        kicker_w += bw + spacing
    kicker_w -= spacing
    kx = (W - kicker_w) / 2
    x = kx
    for ch, bw in glyphs:
        draw.text((x, y), ch, font=font_kicker, fill=GOLD)
        x += bw + spacing

    # Gold diamond rule under kicker
    y += 48
    cx = W // 2
    draw.polygon(
        [(cx, y), (cx + 7, y + 7), (cx, y + 14), (cx - 7, y + 7)],
        fill=GOLD,
    )
    draw.line([(cx - 90, y + 7), (cx - 18, y + 7)], fill=GOLD_SOFT, width=2)
    draw.line([(cx + 18, y + 7), (cx + 90, y + 7)], fill=GOLD_SOFT, width=2)

    y += 48

    # Headlines — centered, tight leading
    line_heights = []
    line_widths = []
    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font_head)
        lw = bbox[2] - bbox[0]
        lh = bbox[3] - bbox[1]
        line_widths.append(lw)
        line_heights.append(lh)

    leading = 12
    for i, line in enumerate(lines):
        lw = line_widths[i]
        x = (W - lw) / 2
        # Slight ink soft for secondary lines
        color = INK if i == accent_line or i == 0 else INK
        draw.text((x, y), line, font=font_head, fill=color)

        if i == accent_line:
            # Warm gold underline under accent line
            uy = y + line_heights[i] + 10
            pad = 8
            draw.rounded_rectangle(
                [x - pad, uy, x + lw + pad, uy + 8],
                radius=4,
                fill=GOLD,
            )
            y += 18  # room for underline

        y += line_heights[i] + leading

    return y + 28


def compose(shot: dict) -> Path:
    src_path = SRC / shot["src"]
    if not src_path.exists():
        raise FileNotFoundError(src_path)

    raw = Image.open(src_path).convert("RGB")
    # Crop status-bar area is fine; use full capture

    base = vertical_gradient((W, H))
    base = soft_vignette(base, strength=0.08)
    canvas = base.convert("RGBA")

    # Text
    text_bottom = draw_text_block(
        canvas,
        shot["kicker"],
        shot["lines"],
        shot["accent_line"],
    )

    # Phone size — leave bottom margin
    max_phone_bottom = H - 100
    available_h = max_phone_bottom - text_bottom
    # Phone width tuned so device dominates
    phone_w = 1000
    phone = make_phone(raw, phone_w=phone_w)

    # Scale phone to fit remaining vertical space
    if phone.height > available_h:
        scale = available_h / phone.height
        new_w = int(phone.width * scale)
        new_h = int(phone.height * scale)
        phone = phone.resize((new_w, new_h), Image.Resampling.LANCZOS)

    shadow_img, pad = drop_shadow(
        phone.size,
        radius=max(40, int(72 * phone.width / 1000)),
        blur=52,
        offset=(0, 40),
        opacity=100,
    )

    # Position phone centered, below text
    phone_x = (W - phone.width) // 2
    phone_y = text_bottom + max(20, (available_h - phone.height) // 5)

    # Paste shadow then phone
    sx = phone_x - pad
    sy = phone_y - pad
    canvas.alpha_composite(shadow_img, (sx, sy))
    canvas.alpha_composite(phone, (phone_x, phone_y))

    # Subtle top edge highlight line (editorial)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, W, 6], fill=(*GOLD, 40))

    out_path = OUT / shot["out"]
    rgb = canvas.convert("RGB")
    # Slight sharpen
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    rgb.save(out_path, "JPEG", quality=92, optimize=True)
    # Also PNG for lossless review
    png_path = out_path.with_suffix(".png")
    rgb.save(png_path, "PNG", optimize=True)
    return out_path


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"Writing to {OUT}")
    for shot in SHOTS:
        path = compose(shot)
        print(f"  ✓ {path.name}  ←  {shot['src']}")
    print("Done.")


if __name__ == "__main__":
    main()
