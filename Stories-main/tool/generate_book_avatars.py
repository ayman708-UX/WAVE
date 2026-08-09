#!/usr/bin/env python3
"""Legacy flat avatar generator (superseded by realistic portrait assets).

The bundled profile avatars in assets/avatars/ are AI-generated portraits.
Only run this script if you intentionally want to replace them with flat art.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw

SIZE = 512
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "avatars")


def circle_mask(img: Image.Image) -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, SIZE - 1, SIZE - 1), fill=255)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def bg(gradient: tuple[tuple[int, int, int], tuple[int, int, int]]) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(img)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        r = int(gradient[0][0] * (1 - t) + gradient[1][0] * t)
        g = int(gradient[0][1] * (1 - t) + gradient[1][1] * t)
        b = int(gradient[0][2] * (1 - t) + gradient[1][2] * t)
        draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))
    return img


def draw_book(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    cover: tuple[int, int, int],
    spine: tuple[int, int, int],
    pages: tuple[int, int, int] = (245, 236, 220),
    open_book: bool = False,
) -> None:
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    if open_book:
        mid = x0 + w // 2
        draw.polygon(
            [(x0, y0 + h * 0.08), (mid - 4, y0), (mid - 4, y1), (x0 + w * 0.08, y1)],
            fill=pages,
        )
        draw.polygon(
            [(x1, y0 + h * 0.08), (mid + 4, y0), (mid + 4, y1), (x1 - w * 0.08, y1)],
            fill=pages,
        )
        draw.rectangle((mid - 5, y0, mid + 5, y1), fill=spine)
        draw.line([(mid, y0 + 8), (mid, y1 - 8)], fill=(180, 160, 130), width=2)
        return
    spine_w = max(10, w // 7)
    draw.rounded_rectangle((x0, y0, x1, y1), radius=10, fill=cover)
    draw.rectangle((x0, y0, x0 + spine_w, y1), fill=spine)
    draw.rectangle((x1 - 8, y0 + 10, x1, y1 - 10), fill=pages)


def face(
    draw: ImageDraw.ImageDraw,
    cx: int,
    cy: int,
    r: int,
    skin: tuple[int, int, int],
    hair: tuple[int, int, int] | None = None,
    hair_top: int | None = None,
) -> None:
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=skin)
    if hair and hair_top is not None:
        draw.pieslice((cx - r - 4, hair_top, cx + r + 4, cy + 6), 180, 360, fill=hair)
    eye_y = cy - r // 6
    eye_r = max(4, r // 7)
    draw.ellipse((cx - r // 3 - eye_r, eye_y - eye_r, cx - r // 3 + eye_r, eye_y + eye_r), fill=(30, 24, 20))
    draw.ellipse((cx + r // 3 - eye_r, eye_y - eye_r, cx + r // 3 + eye_r, eye_y + eye_r), fill=(30, 24, 20))
    draw.arc((cx - r // 3, cy + r // 8, cx + r // 3, cy + r // 2), 10, 170, fill=(120, 70, 50), width=max(2, r // 12))


def glasses(draw: ImageDraw.ImageDraw, cx: int, cy: int, r: int) -> None:
    y = cy - r // 6
    rad = r // 4
    for ox in (-r // 3, r // 3):
        draw.ellipse((cx + ox - rad, y - rad, cx + ox + rad, y + rad), outline=(40, 40, 48), width=4)
    draw.line([(cx - rad, y), (cx + rad, y)], fill=(40, 40, 48), width=4)


def avatar_wizard(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 188, 72, (255, 214, 182), (48, 34, 24), 118)
    glasses(draw, 256, 188, 72)
    draw_book(draw, (148, 250, 364, 430), (88, 52, 140), (58, 32, 98))
    draw.polygon([(300, 250), (318, 220), (336, 250)], fill=(232, 196, 106))
    for x, y in [(210, 300), (250, 285), (290, 305)]:
        draw.ellipse((x, y, x + 10, y + 10), fill=(255, 230, 120))


def avatar_detective(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    draw.polygon([(170, 150), (256, 108), (342, 150), (320, 178), (192, 178)], fill=(92, 62, 38))
    draw.rectangle((220, 118, 292, 142), fill=(72, 48, 28))
    face(draw, 256, 196, 68, (255, 220, 190), (70, 48, 28), 132)
    draw_book(draw, (150, 258, 362, 432), (96, 64, 40), (68, 42, 24))
    draw.ellipse((300, 300, 360, 360), outline=(180, 180, 190), width=6)
    draw.line([(330, 360), (330, 392)], fill=(120, 80, 50), width=5)


def avatar_princess(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 192, 70, (255, 220, 228), (255, 150, 170), 124)
    crown = [(210, 132), (230, 104), (256, 124), (282, 104), (302, 132), (292, 148), (220, 148)]
    draw.polygon(crown, fill=(255, 210, 70))
    draw_book(draw, (152, 252, 360, 430), (176, 72, 128), (130, 48, 96))
    draw.polygon([(256, 292), (236, 332), (276, 332)], fill=(255, 220, 90))


def avatar_pirate(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    draw.polygon([(168, 156), (256, 112), (344, 156), (330, 182), (182, 182)], fill=(24, 24, 28))
    face(draw, 256, 198, 66, (255, 210, 175), (120, 72, 36), 136)
    draw.rectangle((286, 186, 334, 214), fill=(18, 18, 22))
    draw_book(draw, (154, 258, 358, 432), (36, 58, 92), (24, 36, 64))
    draw.line([(256, 318), (256, 350)], fill=(210, 180, 90), width=4)
    draw.polygon([(256, 350), (240, 378), (272, 378)], fill=(210, 180, 90))


def avatar_scholar(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 190, 70, (255, 218, 188), (180, 180, 190), 126)
    draw.rounded_rectangle((198, 112, 314, 148), radius=18, fill=(40, 40, 48))
    draw_book(draw, (146, 252, 366, 434), (120, 34, 42), (88, 22, 30))
    draw.line([(220, 286), (248, 250)], fill=(240, 230, 210), width=5)
    draw.polygon([(248, 250), (292, 268), (248, 286)], fill=(210, 180, 120))


def avatar_knight(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((206, 118, 306, 210), radius=16, fill=(176, 186, 198))
    draw.rectangle((236, 168, 276, 196), fill=(40, 48, 56))
    face(draw, 256, 196, 58, (255, 214, 182), None, None)
    draw_book(draw, (154, 258, 358, 432), (52, 78, 128), (34, 52, 88))
    draw.rounded_rectangle((318, 292, 366, 360), radius=8, fill=(120, 132, 148))
    draw.ellipse((334, 318, 350, 334), fill=(232, 184, 84))


def avatar_dragon(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    draw.ellipse((188, 132, 324, 228), fill=(72, 168, 92))
    draw.ellipse((210, 164, 236, 190), fill=(255, 255, 255))
    draw.ellipse((276, 164, 302, 190), fill=(255, 255, 255))
    draw.ellipse((218, 172, 228, 182), fill=(24, 56, 32))
    draw.ellipse((284, 172, 294, 182), fill=(24, 56, 32))
    draw_book(draw, (150, 252, 362, 432), (34, 110, 72), (20, 78, 48))
    draw.polygon([(256, 300), (236, 340), (276, 340)], fill=(255, 210, 70))


def avatar_voyager(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 188, 68, (255, 214, 190), (50, 50, 60), 126)
    draw.ellipse((220, 118, 292, 150), fill=(220, 230, 240))
    draw_book(draw, (152, 254, 360, 432), (18, 42, 72), (10, 24, 48))
    draw.ellipse((286, 296, 334, 344), fill=(90, 160, 220))
    draw.ellipse((302, 308, 318, 324), fill=(210, 230, 255))
    for x, y in [(220, 300), (240, 280), (200, 320)]:
        draw.ellipse((x, y, x + 4, y + 4), fill=(255, 255, 255))


def avatar_romantic(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 190, 70, (255, 220, 214), (110, 52, 68), 126)
    draw_book(draw, (150, 254, 362, 432), (156, 48, 72), (110, 28, 48))
    draw.ellipse((228, 300, 284, 356), fill=(220, 70, 96))
    draw.polygon([(256, 318), (246, 338), (266, 338)], fill=(255, 180, 190))


def avatar_gothic(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 190, 68, (230, 220, 220), (30, 30, 36), 128)
    draw.polygon([(220, 126), (256, 104), (292, 126), (280, 150), (232, 150)], fill=(24, 24, 30))
    draw_book(draw, (154, 256, 358, 434), (28, 28, 36), (12, 12, 18))
    draw.ellipse((286, 292, 346, 352), fill=(240, 236, 210))
    draw.polygon([(310, 300), (322, 330), (298, 330)], fill=(24, 24, 30))


def avatar_storyteller(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    draw_book(draw, (108, 170, 404, 420), (232, 184, 84), (196, 148, 56), open_book=True)
    for x in range(150, 360, 28):
        draw.line([(x, 220), (x, 380)], fill=(210, 190, 160), width=2)
    draw.ellipse((236, 132, 276, 172), fill=(255, 240, 180))
    draw.ellipse((246, 142, 266, 162), fill=(255, 248, 220))


def avatar_child(img: Image.Image) -> None:
    draw = ImageDraw.Draw(img)
    face(draw, 256, 186, 74, (255, 220, 190), (255, 170, 60), 118)
    colors = [(232, 84, 84), (88, 168, 232), (104, 196, 120), (240, 196, 72)]
    x = 156
    for c in colors:
        draw.rounded_rectangle((x, 260, x + 56, 420), radius=8, fill=c)
        draw.rectangle((x, 260, x + 10, 420), fill=tuple(max(0, v - 40) for v in c))
        x += 64
    draw.arc((220, 150, 292, 210), 200, 340, fill=(255, 210, 70), width=5)


AVATARS = [
    ("01_storyteller", avatar_storyteller, ((24, 20, 32), (10, 10, 18))),
    ("02_wizard", avatar_wizard, ((34, 24, 58), (16, 12, 32))),
    ("03_detective", avatar_detective, ((38, 30, 24), (18, 14, 10))),
    ("04_princess", avatar_princess, ((58, 24, 48), (28, 12, 28))),
    ("05_pirate", avatar_pirate, ((18, 28, 48), (8, 14, 28))),
    ("06_scholar", avatar_scholar, ((42, 18, 24), (20, 10, 12))),
    ("07_knight", avatar_knight, ((28, 36, 58), (14, 18, 32))),
    ("08_dragon", avatar_dragon, ((18, 42, 32), (10, 24, 18))),
    ("09_voyager", avatar_voyager, ((12, 24, 48), (6, 12, 28))),
    ("10_romantic", avatar_romantic, ((48, 18, 32), (24, 10, 18))),
    ("11_gothic", avatar_gothic, ((22, 20, 30), (10, 8, 16))),
    ("12_dreamer", avatar_child, ((40, 28, 64), (18, 14, 34))),
]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".png"):
            os.remove(os.path.join(OUT, old))
    for slug, painter, gradient in AVATARS:
        img = bg(gradient)
        painter(img)
        img = circle_mask(img)
        path = os.path.join(OUT, f"{slug}.png")
        img.save(path, "PNG", optimize=True)
        print("wrote", path)


if __name__ == "__main__":
    main()
