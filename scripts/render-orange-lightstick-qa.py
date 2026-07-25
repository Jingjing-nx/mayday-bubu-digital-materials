#!/usr/bin/env python3
"""Render deterministic Orange Bubu lightstick action and quota QA boards."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


FRAME_WIDTH = 192
FRAME_HEIGHT = 208
SCALE = 4


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
    ):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


def checker(size: tuple[int, int], cell: int = 32) -> Image.Image:
    image = Image.new("RGBA", size, (247, 249, 252, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(230, 234, 240, 255))
    return image


def frame(atlas: Image.Image, row: int, column: int = 0) -> Image.Image:
    crop = atlas.crop(
        (
            column * FRAME_WIDTH,
            row * FRAME_HEIGHT,
            (column + 1) * FRAME_WIDTH,
            (row + 1) * FRAME_HEIGHT,
        )
    )
    return crop.resize((FRAME_WIDTH * SCALE, FRAME_HEIGHT * SCALE), Image.Resampling.LANCZOS)


def paste_stick(scene: Image.Image, stick: Image.Image, x: int, y: int) -> None:
    scene.alpha_composite(stick, (x * SCALE, y * SCALE))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, required=True)
    parser.add_argument("--previews", type=Path, required=True)
    parser.add_argument("--airplane-previews", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--quota-out", type=Path)
    parser.add_argument("--design", type=Path)
    parser.add_argument("--comparison-out", type=Path)
    args = parser.parse_args()
    airplane_previews = args.airplane_previews or args.previews

    atlas = Image.open(args.atlas).convert("RGBA")
    stick_chair = Image.open(args.previews / "lightstick-chair-75.png").convert("RGBA")
    stick_sing_left = Image.open(args.previews / "lightstick-sing-left-75.png").convert("RGBA")
    stick_sing_right = Image.open(args.previews / "lightstick-sing-right-75.png").convert("RGBA")
    stick_guitar = Image.open(args.previews / "lightstick-guitar-75.png").convert("RGBA")
    airplane_chair = Image.open(airplane_previews / "airplane-75.png").convert("RGBA")

    labels = ["默认办公：椅侧单棒", "左拖唱歌：双棒应援", "右拖吉他：舞台侧单棒"]
    scene_rows = [0, 2, 1]
    scene_padding = 40
    scene_width = (FRAME_WIDTH + scene_padding * 2) * SCALE
    scene_height = FRAME_HEIGHT * SCALE
    label_height = 88
    gap = 24
    board = Image.new(
        "RGBA",
        (scene_width * 3 + gap * 4, scene_height + label_height + gap * 2),
        (244, 247, 251, 255),
    )
    draw = ImageDraw.Draw(board)
    title_font = font(27)
    default_scene: Image.Image | None = None
    for index, (label, row) in enumerate(zip(labels, scene_rows)):
        x0 = gap + index * (scene_width + gap)
        scene = checker((scene_width, scene_height))
        scene.alpha_composite(frame(atlas, row), (scene_padding * SCALE, 0))
        if index == 0:
            paste_stick(scene, stick_chair, scene_padding + 5, 104)
            paste_stick(scene, airplane_chair, scene_padding - 34, 40)
            default_scene = scene.copy()
        elif index == 1:
            paste_stick(scene, stick_sing_left, scene_padding, 104)
            paste_stick(scene, stick_sing_right, scene_padding + 154, 104)
        else:
            paste_stick(scene, stick_guitar, scene_padding + 150, 104)
        board.alpha_composite(scene, (x0, label_height))
        draw.text((x0 + 18, 28), label, font=title_font, fill=(18, 35, 55, 255))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    board.convert("RGB").save(args.out, "PNG", optimize=True)

    if args.design and args.comparison_out and default_scene is not None:
        design = Image.open(args.design).convert("RGB").crop((120, 205, 1120, 1195))
        card_size = (900, 820)

        def fit_card(source: Image.Image) -> Image.Image:
            card = Image.new("RGB", card_size, (247, 249, 252))
            contained = source.copy()
            contained.thumbnail((card_size[0] - 36, card_size[1] - 36), Image.Resampling.LANCZOS)
            card.paste(
                contained.convert("RGB"),
                ((card_size[0] - contained.width) // 2, (card_size[1] - contained.height) // 2),
            )
            return card

        comparison_gap = 28
        comparison_header = 72
        comparison = Image.new(
            "RGB",
            (card_size[0] * 2 + comparison_gap * 3, card_size[1] + comparison_header + comparison_gap),
            (238, 242, 247),
        )
        comparison.paste(fit_card(design), (comparison_gap, comparison_header))
        comparison.paste(
            fit_card(default_scene.convert("RGB")),
            (comparison_gap * 2 + card_size[0], comparison_header),
        )
        comparison_draw = ImageDraw.Draw(comparison)
        comparison_draw.text(
            (comparison_gap + 18, 22),
            "批准设计稿",
            font=title_font,
            fill=(18, 35, 55),
        )
        comparison_draw.text(
            (comparison_gap * 2 + card_size[0] + 18, 22),
            "运行时：独立原像素飞机材质",
            font=title_font,
            fill=(18, 35, 55),
        )
        args.comparison_out.parent.mkdir(parents=True, exist_ok=True)
        comparison.save(args.comparison_out, "PNG", optimize=True)

    if args.quota_out:
        values = [100, 75, 40, 15, 0]
        airplane_sample = Image.open(airplane_previews / "airplane-75.png").convert("RGBA")
        stick_width, stick_height = stick_chair.size
        card_width = max(stick_width, airplane_sample.width)
        card_height = airplane_sample.height + stick_height + 12
        quota_gap = 42
        quota_label_height = 72
        quota_board = checker(
            (
                card_width * len(values) + quota_gap * (len(values) + 1),
                card_height + quota_label_height + quota_gap,
            ),
            cell=24,
        )
        quota_draw = ImageDraw.Draw(quota_board)
        quota_font = font(26)
        for index, value in enumerate(values):
            image = Image.open(args.previews / f"lightstick-{value}.png").convert("RGBA")
            airplane = Image.open(airplane_previews / f"airplane-{value}.png").convert("RGBA")
            x = quota_gap + index * (card_width + quota_gap)
            quota_board.alpha_composite(
                airplane,
                (x + (card_width - airplane.width) // 2, quota_label_height),
            )
            quota_board.alpha_composite(
                image,
                (
                    x + (card_width - image.width) // 2,
                    quota_label_height + airplane.height + 12,
                ),
            )
            label = f"{value}%"
            bbox = quota_draw.textbbox((0, 0), label, font=quota_font)
            quota_draw.text(
                (x + (card_width - (bbox[2] - bbox[0])) / 2, 24),
                label,
                font=quota_font,
                fill=(18, 35, 55, 255),
            )
        args.quota_out.parent.mkdir(parents=True, exist_ok=True)
        quota_board.convert("RGB").save(args.quota_out, "PNG", optimize=True)


if __name__ == "__main__":
    main()
