#!/usr/bin/env python3
"""
Compose 13" iPad App Store screenshots from raw simulator captures.

Same "Quiet Morning" system as compose_appstore_shots.py (which this imports
for the palette, gradient, shadow and font helpers) on the 2064×2752 canvas,
with an iPad slab frame instead of the phone bezel. The lead shot is the
split game layout — the one composition an iPhone screenshot cannot show.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from compose_appstore_shots import (
    BEZEL,
    FONT_SERIF,
    FONT_UI,
    GOLD,
    GOLD_SOFT,
    INK,
    ROOT,
    drop_shadow,
    load_font,
    rounded_mask,
    soft_vignette,
    vertical_gradient,
)

# 13" iPad App Store portrait
W, H = 2064, 2752

SRC = ROOT / "simulator-screenshots" / "appstore-13"
OUT = SRC / "composited"

SHOTS = [
    {
        "src": "02-crossword-split.png",
        "out": "padImage1.jpg",
        "kicker": "MADE FOR IPAD",
        "lines": ["Grid and clues,", "side by side"],
        "accent_line": 0,
    },
    {
        "src": "01-today-home.png",
        "out": "padImage2.jpg",
        "kicker": "EVERY MORNING",
        "lines": ["A new Bible crossword", "every day"],
        "accent_line": 1,
    },
    {
        "src": "03-packs.png",
        "out": "padImage3.jpg",
        "kicker": "THEMED COLLECTIONS",
        "lines": ["Stories you know.", "Puzzles you'll love."],
        "accent_line": 0,
    },
]


def make_pad(screenshot: Image.Image, pad_w: int) -> Image.Image:
    """Frame a capture in an iPad slab: uniform bezel, no chin, no island."""
    bezel = 26
    corner = 96
    screen_corner = 48

    screen_w = pad_w - bezel * 2
    scale = screen_w / screenshot.width
    screen_h = int(screenshot.height * scale)
    shot = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)

    pad_h = screen_h + bezel * 2
    pad = Image.new("RGBA", (pad_w, pad_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(pad)

    draw.rounded_rectangle([0, 0, pad_w - 1, pad_h - 1], radius=corner, fill=BEZEL)
    inset = 4
    draw.rounded_rectangle(
        [inset, inset, pad_w - 1 - inset, pad_h - 1 - inset],
        radius=corner - 3,
        outline=(*GOLD_SOFT, 110),
        width=3,
    )
    draw.rounded_rectangle(
        [bezel - 3, bezel - 3, pad_w - bezel + 2, pad_h - bezel + 2],
        radius=screen_corner + 5,
        fill=(10, 12, 14, 255),
    )

    mask = rounded_mask((screen_w, screen_h), screen_corner)
    screen_layer = Image.new("RGBA", (screen_w, screen_h), (0, 0, 0, 0))
    screen_layer.paste(shot.convert("RGBA"), (0, 0), mask)
    pad.paste(screen_layer, (bezel, bezel), mask)
    return pad


def draw_text_block(canvas: Image.Image, kicker: str, lines: list[str], accent_line: int) -> int:
    """The phone script's block, re-measured for the wider canvas."""
    draw = ImageDraw.Draw(canvas)
    font_kicker = load_font(FONT_UI, 42)
    try:
        font_head = ImageFont.truetype(FONT_SERIF, 138)
    except OSError:
        font_head = load_font(FONT_UI, 132)

    y = 170

    kicker = kicker.upper()
    spacing = 9
    glyphs = [(ch, draw.textlength(ch, font=font_kicker)) for ch in kicker]
    kicker_w = sum(bw for _, bw in glyphs) + spacing * (len(glyphs) - 1)
    x = (W - kicker_w) / 2
    for ch, bw in glyphs:
        draw.text((x, y), ch, font=font_kicker, fill=GOLD)
        x += bw + spacing

    y += 70
    cx = W // 2
    draw.polygon([(cx, y), (cx + 10, y + 10), (cx, y + 20), (cx - 10, y + 10)], fill=GOLD)
    draw.line([(cx - 130, y + 10), (cx - 26, y + 10)], fill=GOLD_SOFT, width=3)
    draw.line([(cx + 26, y + 10), (cx + 130, y + 10)], fill=GOLD_SOFT, width=3)
    y += 70

    metrics = [draw.textbbox((0, 0), line, font=font_head) for line in lines]
    leading = 18
    for i, line in enumerate(lines):
        lw = metrics[i][2] - metrics[i][0]
        lh = metrics[i][3] - metrics[i][1]
        x = (W - lw) / 2
        draw.text((x, y), line, font=font_head, fill=INK)
        if i == accent_line:
            uy = y + lh + 14
            draw.rounded_rectangle([x - 12, uy, x + lw + 12, uy + 11], radius=5, fill=GOLD)
            y += 26
        y += lh + leading

    return y + 40


def compose(shot: dict) -> Path:
    src_path = SRC / shot["src"]
    raw = Image.open(src_path).convert("RGB")

    base = vertical_gradient((W, H))
    base = soft_vignette(base, strength=0.08)
    canvas = base.convert("RGBA")

    text_bottom = draw_text_block(canvas, shot["kicker"], shot["lines"], shot["accent_line"])

    available_h = (H - 120) - text_bottom
    pad = make_pad(raw, pad_w=1660)
    if pad.height > available_h:
        scale = available_h / pad.height
        pad = pad.resize((int(pad.width * scale), int(pad.height * scale)), Image.Resampling.LANCZOS)

    shadow_img, spad = drop_shadow(
        pad.size,
        radius=max(56, int(96 * pad.width / 1660)),
        blur=64,
        offset=(0, 48),
        opacity=100,
    )

    pad_x = (W - pad.width) // 2
    pad_y = text_bottom + max(28, (available_h - pad.height) // 5)
    canvas.alpha_composite(shadow_img, (pad_x - spad, pad_y - spad))
    canvas.alpha_composite(pad, (pad_x, pad_y))

    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, W, 8], fill=(*GOLD, 40))

    out_path = OUT / shot["out"]
    rgb = canvas.convert("RGB")
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    rgb.save(out_path, "JPEG", quality=92, optimize=True)
    rgb.save(out_path.with_suffix(".png"), "PNG", optimize=True)
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
