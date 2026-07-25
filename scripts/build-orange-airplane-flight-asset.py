#!/usr/bin/env python3
"""Extract the generated standalone Orange Bubu airplane ticket.

Image generation removes the chair clamp and reconstructs the ticket tail.
This deterministic pass only keys the required magenta backdrop, cleans edge
spill, and fits the result to the existing 342x284 runtime material canvas.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


CANVAS_SIZE = (342, 284)


def largest_component(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=bool)
    best: list[tuple[int, int]] = []
    for y in range(height):
        for x in range(width):
            if not mask[y, x] or visited[y, x]:
                continue
            queue = deque([(y, x)])
            visited[y, x] = True
            component: list[tuple[int, int]] = []
            while queue:
                cy, cx = queue.popleft()
                component.append((cy, cx))
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if (
                        0 <= ny < height
                        and 0 <= nx < width
                        and mask[ny, nx]
                        and not visited[ny, nx]
                    ):
                        visited[ny, nx] = True
                        queue.append((ny, nx))
            if len(component) > len(best):
                best = component
    output = np.zeros_like(mask, dtype=bool)
    if best:
        yy, xx = zip(*best)
        output[np.asarray(yy), np.asarray(xx)] = True
    return output


def extract(source: Image.Image) -> tuple[Image.Image, dict[str, object]]:
    rgb = np.asarray(source.convert("RGB"), dtype=np.float32)
    border = np.concatenate((rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]), axis=0)
    key = np.median(border, axis=0)
    distance = np.linalg.norm(rgb - key, axis=2)
    component = largest_component(distance > 72.0)
    solid = np.asarray(
        Image.fromarray((component * 255).astype(np.uint8), "L")
        .filter(ImageFilter.MaxFilter(5))
        .filter(ImageFilter.MinFilter(5))
    ) > 0
    alpha = np.asarray(
        Image.fromarray((solid * 255).astype(np.uint8), "L").filter(
            ImageFilter.GaussianBlur(0.75)
        )
    ).astype(np.float32) / 255.0
    alpha[solid] = 1.0

    safe_alpha = np.maximum(alpha[..., None], 0.02)
    foreground = (rgb - key * (1.0 - safe_alpha)) / safe_alpha
    foreground = np.clip(foreground, 0, 255)
    foreground[alpha <= 0.005] = 0
    rgba = np.dstack((foreground.astype(np.uint8), (alpha * 255).astype(np.uint8)))

    ys, xs = np.where(alpha > 0.01)
    if not len(xs):
        raise ValueError("no standalone ticket component found")
    padding = 8
    left = max(0, int(xs.min()) - padding)
    top = max(0, int(ys.min()) - padding)
    right = min(source.width, int(xs.max()) + padding + 1)
    bottom = min(source.height, int(ys.max()) + padding + 1)
    cutout = Image.fromarray(rgba, "RGBA").crop((left, top, right, bottom))

    target_inner = (CANVAS_SIZE[0] - 8, CANVAS_SIZE[1] - 8)
    cutout.thumbnail(target_inner, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    offset = ((CANVAS_SIZE[0] - cutout.width) // 2, (CANVAS_SIZE[1] - cutout.height) // 2)
    canvas.alpha_composite(cutout, offset)

    pixels = np.asarray(canvas).copy()
    pixels[pixels[..., 3] == 0, :3] = 0
    output = Image.fromarray(pixels, "RGBA")
    metadata: dict[str, object] = {
        "sourcePixelSize": [source.width, source.height],
        "sourceKeyRGB": [round(float(value), 3) for value in key],
        "sourceCrop": [left, top, right, bottom],
        "materialPixelSize": list(CANVAS_SIZE),
        "runtimeSize": {"width": 78.0, "height": 65.0},
        "numberCenter": {"x": 36.25, "yFromTop": 30.9},
        "progress": {"x": 17.35, "yFromTop": 38.0, "width": 34.0},
        "attachment": "none; standalone flight material",
        "extraction": "imagegen-magenta-key-largest-component-v1",
    }
    return output, metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, action="append", required=True)
    args = parser.parse_args()

    material, metadata = extract(Image.open(args.source))
    metadata["source"] = str(args.source)
    for output_dir in args.output_dir:
        output_dir.mkdir(parents=True, exist_ok=True)
        material.save(output_dir / "quota-airplane-flight-material.png", optimize=True)
        (output_dir / "quota-airplane-flight-material.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
