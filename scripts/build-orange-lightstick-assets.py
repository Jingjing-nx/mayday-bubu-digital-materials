#!/usr/bin/env python3
"""Build aligned, high-resolution runtime layers for Orange Bubu's lightstick."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


def alpha_composite_at(canvas: Image.Image, layer: Image.Image, xy: tuple[int, int]) -> None:
    canvas.alpha_composite(layer, dest=xy)


def compress_tube(
    image: Image.Image,
    crop_box: tuple[int, int, int, int],
    collar_top: int,
    tube_scale: float,
) -> tuple[Image.Image, int]:
    left, top, right, bottom = crop_box
    tube = image.crop((left, top, right, collar_top))
    lower = image.crop((left, collar_top, right, bottom))
    target_tube_height = max(1, round(tube.height * tube_scale))
    tube = tube.resize((tube.width, target_tube_height), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (tube.width, target_tube_height + lower.height))
    alpha_composite_at(output, tube, (0, 0))
    alpha_composite_at(output, lower, (0, target_tube_height))
    return output, target_tube_height


def make_tube_mask(size: tuple[int, int], product_alpha: Image.Image, tube_bottom: int) -> Image.Image:
    mask = Image.new("L", size)
    mask.paste(product_alpha.crop((0, 0, size[0], tube_bottom)), (0, 0))
    return mask


def make_glow(mask: Image.Image) -> Image.Image:
    outer_alpha = mask.filter(ImageFilter.GaussianBlur(18)).point(lambda value: round(value * 0.58))
    inner_alpha = mask.filter(ImageFilter.GaussianBlur(7)).point(lambda value: round(value * 0.32))
    outer = Image.new("RGBA", mask.size, (0, 66, 255, 0))
    outer.putalpha(outer_alpha)
    inner = Image.new("RGBA", mask.size, (0, 221, 255, 0))
    inner.putalpha(inner_alpha)
    return Image.alpha_composite(outer, inner)


def make_specular(lit: Image.Image, mask: Image.Image) -> Image.Image:
    red = lit.getchannel("R")
    green = lit.getchannel("G")
    blue = lit.getchannel("B")
    white_floor = ImageChops.darker(red, ImageChops.darker(green, blue))
    highlight = white_floor.point(lambda value: max(0, min(255, (value - 164) * 2)))
    highlight = ImageChops.multiply(highlight, mask).filter(ImageFilter.GaussianBlur(1.2))
    highlight = highlight.point(lambda value: round(value * 0.42))
    specular = Image.new("RGBA", lit.size, (244, 252, 255, 0))
    specular.putalpha(highlight)
    return specular


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lit", type=Path, required=True)
    parser.add_argument("--unlit", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--collar-top", type=int, default=925)
    parser.add_argument("--tube-scale", type=float, default=0.75)
    parser.add_argument("--padding-x", type=int, default=28)
    parser.add_argument("--padding-y", type=int, default=24)
    args = parser.parse_args()

    lit = Image.open(args.lit).convert("RGBA")
    unlit = Image.open(args.unlit).convert("RGBA")
    if lit.size != unlit.size:
        raise SystemExit(f"source canvases differ: lit={lit.size}, unlit={unlit.size}")

    union_alpha = ImageChops.lighter(lit.getchannel("A"), unlit.getchannel("A"))
    bbox = union_alpha.getbbox()
    if not bbox:
        raise SystemExit("sources have no visible pixels")
    left = max(0, bbox[0] - args.padding_x)
    top = max(0, bbox[1] - args.padding_y)
    right = min(lit.width, bbox[2] + args.padding_x)
    bottom = min(lit.height, bbox[3] + args.padding_y)
    if not top < args.collar_top < bottom:
        raise SystemExit("collar split is outside the visible product")
    crop_box = (left, top, right, bottom)

    lit_product, tube_bottom = compress_tube(lit, crop_box, args.collar_top, args.tube_scale)
    unlit_product, unlit_tube_bottom = compress_tube(
        unlit, crop_box, args.collar_top, args.tube_scale
    )
    if tube_bottom != unlit_tube_bottom or lit_product.size != unlit_product.size:
        raise SystemExit("processed layers are not aligned")

    tube_mask = make_tube_mask(lit_product.size, lit_product.getchannel("A"), tube_bottom)
    lit_tube = Image.new("RGBA", lit_product.size)
    lit_tube.paste(lit_product, (0, 0), tube_mask)
    glow = make_glow(tube_mask)
    specular = make_specular(lit_product, tube_mask)

    args.out.mkdir(parents=True, exist_ok=True)
    save_png(lit_product, args.out / "lightstick-full-lit.png")
    save_png(unlit_product, args.out / "lightstick-unlit.png")
    save_png(lit_tube, args.out / "lightstick-tube-emission.png")
    save_png(glow, args.out / "lightstick-glow.png")
    save_png(specular, args.out / "lightstick-specular.png")
    rgba_mask = Image.new("RGBA", tube_mask.size, (255, 255, 255, 0))
    rgba_mask.putalpha(tube_mask)
    save_png(rgba_mask, args.out / "lightstick-tube-mask.png")

    tube_bbox = tube_mask.getbbox()
    if not tube_bbox:
        raise SystemExit("processed tube mask has no visible pixels")

    metadata = {
        "schemaVersion": 1,
        "canvas": {"width": lit_product.width, "height": lit_product.height},
        "tubeRect": {
            "left": tube_bbox[0],
            "top": tube_bbox[1],
            "right": tube_bbox[2],
            "bottom": tube_bbox[3],
        },
        "sourceBBox": {"left": bbox[0], "top": bbox[1], "right": bbox[2], "bottom": bbox[3]},
        "sourceCollarTop": args.collar_top,
        "tubeVerticalScale": args.tube_scale,
        "quotaEncoding": "bottom-up illuminated height; cyan hue remains fixed",
        "renderOrder": ["glow", "unlit", "tube-emission", "specular"],
    }
    (args.out / "lightstick-layers.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
