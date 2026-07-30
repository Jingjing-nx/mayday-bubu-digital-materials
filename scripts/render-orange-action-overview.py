#!/usr/bin/env python3
"""Render the orange Bubu sprite sheet as a GitHub-friendly action overview."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shared/pet/bubu-orange/spritesheet.webp"
OUTPUT = ROOT / "shared/preview/橙色卜卜动作总览.png"

COLS = 8
ROWS = 11
SOURCE_CELL = (192, 208)
CELL = (96, 104)
HEADER_HEIGHT = 22
ROW_HEIGHT = HEADER_HEIGHT + CELL[1]

ROWS_INFO = (
    ("row 0: idle", 6),
    ("row 1: running-right", 8),
    ("row 2: running-left", 8),
    ("row 3: waving", 4),
    ("row 4: jumping", 5),
    ("row 5: failed", 8),
    ("row 6: waiting", 6),
    ("row 7: running", 6),
    ("row 8: review", 6),
    ("row 9: look 000-157.5", 8),
    ("row 10: look 180-337.5", 8),
)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/Library/Fonts/Arial.ttf",
    ):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    expected = (COLS * SOURCE_CELL[0], ROWS * SOURCE_CELL[1])
    if source.size != expected:
        raise ValueError(f"Unexpected sprite sheet dimensions: {source.size}; expected {expected}")

    overview = Image.new("RGB", (COLS * CELL[0], ROWS * ROW_HEIGHT), "white")
    draw = ImageDraw.Draw(overview)
    heading_font = font(11)
    frame_font = font(10)

    for row, (label, frame_count) in enumerate(ROWS_INFO):
        y = row * ROW_HEIGHT
        draw.rectangle((0, y, overview.width, y + HEADER_HEIGHT - 1), fill="#111111")
        draw.text((3, y + 3), label, fill="white", font=heading_font)
        draw.text(
            (overview.width - 118, y + 3),
            "6 + neutral" if row == 0 else f"{frame_count} frames",
            fill="white",
            font=heading_font,
        )

        for col in range(COLS):
            x = col * CELL[0]
            cell_y = y + HEADER_HEIGHT
            color = "#008f52" if col < frame_count else "#e53935"
            draw.rectangle((x, cell_y, x + CELL[0] - 1, cell_y + CELL[1] - 1), fill="white", outline=color)
            for square_y in range(cell_y + 1, cell_y + CELL[1] - 1, 12):
                for square_x in range(x + 1, x + CELL[0] - 1, 12):
                    parity = ((square_x - x) // 12 + (square_y - cell_y) // 12) % 2
                    if parity:
                        draw.rectangle((square_x, square_y, square_x + 11, square_y + 11), fill="#e9edf2")

            frame = source.crop(
                (
                    col * SOURCE_CELL[0],
                    row * SOURCE_CELL[1],
                    (col + 1) * SOURCE_CELL[0],
                    (row + 1) * SOURCE_CELL[1],
                )
            ).resize(CELL, Image.Resampling.LANCZOS)
            overview.paste(frame, (x, cell_y), frame)
            draw.text((x + 2, cell_y + 2), str(col), fill="#111111", font=frame_font)

    overview.save(OUTPUT, optimize=True)


if __name__ == "__main__":
    main()
