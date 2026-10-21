#!/usr/bin/env python3
"""生成 App 图标（书 + 左页 5 / 右页 E）。

图标是程序画的，改设计只需改这里的参数后重跑：
    python3 Scripts/make-icon.py
依赖 Pillow。输出到 i5E/Assets.xcassets/AppIcon.appiconset/。
"""

from PIL import Image, ImageChops, ImageDraw, ImageFont

SIZE = 1024
BRAND_RED = (139, 29, 29)
PAPER = (244, 239, 230)
DARK_BG = (23, 25, 28)
DARK_PAPER = (231, 233, 236)
DARK_RED = (181, 60, 60)
OUT = "i5E/Assets.xcassets/AppIcon.appiconset"

# 书页轮廓：两页向中间抬起，中缝留出底色形成书脊
SPINE = 0.50
GAP = 0.022
TOP_INNER, TOP_OUTER = 0.300, 0.355
BOTTOM_OUTER, BOTTOM_INNER = 0.725, 0.775
LEFT_EDGE, RIGHT_EDGE = 0.15, 0.85
LETTER_CENTER_Y = 0.545
LETTER_SIZE = 0.215
LEFT_LETTER_X, RIGHT_LETTER_X = 0.322, 0.678


def _font(px: int) -> ImageFont.FreeTypeFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
        "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
        "/System/Library/Fonts/NewYork.ttf",
    ):
        try:
            return ImageFont.truetype(path, int(px))
        except OSError:
            continue
    return ImageFont.load_default()


def _pages(width: int, color: tuple[int, int, int]) -> Image.Image:
    layer = Image.new("RGBA", (width, width), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    gap = width * GAP / 2
    left = [
        (width * SPINE - gap, width * TOP_INNER),
        (width * LEFT_EDGE, width * TOP_OUTER),
        (width * LEFT_EDGE, width * BOTTOM_OUTER),
        (width * SPINE - gap, width * BOTTOM_INNER),
    ]
    right = [
        (width * SPINE + gap, width * TOP_INNER),
        (width * RIGHT_EDGE, width * TOP_OUTER),
        (width * RIGHT_EDGE, width * BOTTOM_OUTER),
        (width * SPINE + gap, width * BOTTOM_INNER),
    ]
    draw.polygon(left, fill=color + (255,))
    draw.polygon(right, fill=color + (255,))
    return layer


def compose(background, page_color, letter_color, transparent=False) -> Image.Image:
    width = SIZE * 4
    canvas = Image.new(
        "RGBA", (width, width), (0, 0, 0, 0) if transparent else background + (255,)
    )
    canvas = Image.alpha_composite(canvas, _pages(width, page_color))

    font = _font(width * LETTER_SIZE)
    draw = ImageDraw.Draw(canvas)
    for text, center_x in (("5", LEFT_LETTER_X), ("E", RIGHT_LETTER_X)):
        box = draw.textbbox((0, 0), text, font=font)
        x = width * center_x - (box[2] - box[0]) / 2 - box[0]
        y = width * LETTER_CENTER_Y - (box[3] - box[1]) / 2 - box[1]
        if transparent:
            # tinted 变体：字母与中缝镂空，交给系统着色
            hole = Image.new("L", (width, width), 0)
            ImageDraw.Draw(hole).text((x, y), text, font=font, fill=255)
            canvas.putalpha(ImageChops.subtract(canvas.getchannel("A"), hole))
        else:
            draw.text((x, y), text, font=font, fill=letter_color + (255,))

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    light = compose(BRAND_RED, PAPER, BRAND_RED)
    dark = compose(DARK_BG, DARK_PAPER, DARK_RED)
    tinted = compose((0, 0, 0), (255, 255, 255), (0, 0, 0), transparent=True)

    light.save(f"{OUT}/AppIcon.png")
    dark.save(f"{OUT}/AppIcon-Dark.png")
    tinted.save(f"{OUT}/AppIcon-Tinted.png")

    # macOS 的 size × scale
    for size in (16, 32, 64, 128, 256, 512, 1024):
        light.resize((size, size), Image.LANCZOS).save(f"{OUT}/mac-{size}.png")


if __name__ == "__main__":
    main()
