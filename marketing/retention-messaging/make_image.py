# Retention message image, 3840x2160: one phone (the Puzzles shelves), bleeding off the bottom
# so it stays legible in Apple's small card.
# Run: python3 make_image.py <shelves frame .png> ../promo/app-store-search-2026-11-22/build <out.png>
import sys
from PIL import Image
SHOT, B, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
W, H = 3840, 2160
SW, SH, BZ, PAD, SCALE, TOP = 1250, 2716, 34, 220, 1.1, 150
bg = Image.open(f"{B}/bg.png").convert("RGBA").resize((W, H), Image.LANCZOS)
p = Image.open(f"{B}/body.png").convert("RGBA")
s = Image.open(SHOT).convert("RGBA").resize((SW, SH), Image.LANCZOS)
p.paste(s, (PAD + BZ, PAD + BZ), Image.open(f"{B}/mask.png").convert("L"))
p = p.resize((round(p.width * SCALE), round(p.height * SCALE)), Image.LANCZOS)
bg.alpha_composite(p, (W // 2 - p.width // 2, TOP - round(PAD * SCALE)))
bg.convert("RGB").save(OUT, optimize=True)
