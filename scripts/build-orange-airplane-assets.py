#!/usr/bin/env python3
"""Extract the approved Orange Bubu airplane ticket as a runtime material.

The approved design is the source of truth. This script does not redraw the
airplane: it crops the original pixels, removes only the dynamic quota number
and progress underline with texture sampled from the same paper, and recovers
transparent edges plus the real metal chair clip.
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


SOURCE_CROP = (174, 270, 516, 554)
RUNTIME_SIZE = (78.0, 65.0)
NUMBER_CENTER = (36.25, 30.90)
PROGRESS = (17.35, 38.00, 34.00)
CLIP_CENTER = (73.0, 31.0)


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
    result = np.zeros_like(mask, dtype=bool)
    if best:
        yy, xx = zip(*best)
        result[np.asarray(yy), np.asarray(xx)] = True
    return result


def fill_holes(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    outside = np.zeros_like(mask, dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True
                queue.append((y, x))
    while queue:
        cy, cx = queue.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if (
                0 <= ny < height
                and 0 <= nx < width
                and not mask[ny, nx]
                and not outside[ny, nx]
            ):
                outside[ny, nx] = True
                queue.append((ny, nx))
    return mask | ~outside


def pil_mask(mask: np.ndarray) -> Image.Image:
    return Image.fromarray((mask.astype(np.uint8) * 255), "L")


def gaussian_blur_float(array: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur for float arrays without quantizing the approved pixels."""
    radius = max(1, int(round(sigma * 3.0)))
    positions = np.arange(-radius, radius + 1, dtype=np.float32)
    kernel = np.exp(-(positions**2) / (2.0 * sigma * sigma))
    kernel /= kernel.sum()

    def blur_line(line: np.ndarray) -> np.ndarray:
        padded = np.pad(line, (radius, radius), mode="reflect")
        return np.convolve(padded, kernel, mode="valid")

    horizontal = np.apply_along_axis(blur_line, 1, array)
    return np.apply_along_axis(blur_line, 0, horizontal).astype(np.float32)


def clean_dynamic_ink(rgb: np.ndarray, body_mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    height, width, _ = rgb.shape
    left, top, _, _ = SOURCE_CROP
    yy, xx = np.mgrid[0:height, 0:width]
    global_x = xx + left
    global_y = yy + top
    channel_max = rgb.max(axis=2)
    channel_min = rgb.min(axis=2)

    number_region = (
        (global_x >= 300)
        & (global_x <= 366)
        & (global_y >= 374)
        & (global_y <= 432)
    )
    white_number = (
        number_region
        & (channel_min > 142)
        & ((channel_max - channel_min) < 72)
    )
    # Remove the actual glyph strokes, not a rectangular text box. A narrow
    # dilation covers the antialiased white halo while preserving as much of
    # the approved paper texture as possible for the inpaint boundary.
    white_number = np.asarray(
        pil_mask(white_number).filter(ImageFilter.MaxFilter(9))
    ) > 0

    progress_band = (
        (global_x >= 247)
        & (global_x <= 401)
        & (global_y >= 428)
        & (global_y <= 438)
    )
    # The approved underline is cyan (low red, high green/blue). Selecting its
    # pixels avoids erasing a wide horizontal strip of the original plane.
    progress_ink = progress_band & (
        (
            (rgb[..., 0] < 62)
            & (rgb[..., 1] > 135)
            & (rgb[..., 2] > 190)
        )
        | (
            (rgb[..., 0] > 125)
            & (rgb[..., 1] > 180)
            & (rgb[..., 2] > 205)
        )
    )
    progress_ink = np.asarray(
        pil_mask(progress_ink).filter(ImageFilter.MaxFilter(5))
    ) > 0
    dynamic_mask = (white_number | progress_ink) & body_mask

    donor_box = (315 - left, 300 - top, 380 - left, 369 - top)
    donor = rgb[donor_box[1] : donor_box[3], donor_box[0] : donor_box[2]].astype(np.float32)
    donor_smooth = np.asarray(
        Image.fromarray(donor.astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(7.0))
    ).astype(np.float32)
    residual = donor - donor_smooth
    tiled_residual = np.tile(
        residual,
        (
            (height + residual.shape[0] - 1) // residual.shape[0],
            (width + residual.shape[1] - 1) // residual.shape[1],
            1,
        ),
    )[:height, :width]
    # Harmonic inpainting keeps the local lighting continuous across the
    # removed number/underline. Add only high-frequency residual sampled from
    # the same approved paper so no synthetic flat rectangle is introduced.
    replacement = rgb.astype(np.float32).copy()

    # Reconstruct the low-frequency blue field with a normalized blur that
    # ignores all typography and the dynamic ink. Then put back only real
    # high-frequency paper grain sampled from the approved artwork. This
    # keeps the local gradient continuous without leaving glyph-shaped or
    # rectangular patches.
    clean_blue = (
        body_mask
        & ~dynamic_mask
        & (rgb[..., 0] < 150)
        & (rgb[..., 1] > 125)
        & (rgb[..., 2] > 175)
        & ((rgb[..., 2].astype(np.int16) - rgb[..., 0].astype(np.int16)) > 48)
    )
    weight_source = clean_blue.astype(np.float32)
    weight = gaussian_blur_float(weight_source, 11.0)
    smooth_field = np.zeros_like(replacement)
    for channel in range(3):
        weighted_channel = rgb[..., channel].astype(np.float32) * weight_source
        numerator = gaussian_blur_float(weighted_channel, 11.0)
        smooth_field[..., channel] = numerator / np.maximum(weight, 1e-5)
    replacement[dynamic_mask] = (
        smooth_field[dynamic_mask] + tiled_residual[dynamic_mask] * 0.55
    )
    replacement = np.clip(replacement, 0, 255)

    feather = np.asarray(
        pil_mask(dynamic_mask).filter(ImageFilter.GaussianBlur(0.85))
    ).astype(np.float32) / 255.0
    feather = feather[..., None]
    cleaned = rgb.astype(np.float32) * (1 - feather) + replacement * feather
    return np.clip(cleaned, 0, 255).astype(np.uint8), dynamic_mask


def extract_material(source: Image.Image) -> tuple[Image.Image, dict[str, object]]:
    crop = source.crop(SOURCE_CROP).convert("RGB")
    rgb = np.asarray(crop).copy()
    red = rgb[..., 0].astype(np.int16)
    green = rgb[..., 1].astype(np.int16)
    blue = rgb[..., 2].astype(np.int16)

    blue_seed = (
        (blue - red > 38)
        & (green - red > 28)
        & (blue - green > 20)
        & (blue > 105)
    )
    blue_component = largest_component(blue_seed)
    closed = np.asarray(
        pil_mask(blue_component)
        .filter(ImageFilter.MaxFilter(5))
        .filter(ImageFilter.MinFilter(5))
    ) > 0
    body_mask = fill_holes(closed)
    cleaned, dynamic_mask = clean_dynamic_ink(rgb, body_mask)

    body_alpha = np.asarray(
        pil_mask(body_mask).filter(ImageFilter.GaussianBlur(1.15))
    ).astype(np.float32) / 255.0
    body_alpha[body_mask] = 1.0

    height, width = body_mask.shape
    yy, xx = np.mgrid[0:height, 0:width]
    global_x = xx + SOURCE_CROP[0]
    global_y = yy + SOURCE_CROP[1]
    background = np.array([249.0, 249.0, 249.0], dtype=np.float32)
    distance = np.linalg.norm(rgb.astype(np.float32) - background, axis=2)
    clip_roi = (
        (global_x >= 468)
        & (global_x < 516)
        & (global_y >= 367)
        & (global_y <= 445)
    )
    clip_alpha = np.clip((distance - 3.0) / 25.0, 0.0, 1.0) * clip_roi
    clip_alpha = np.asarray(
        Image.fromarray((clip_alpha * 255).astype(np.uint8), "L").filter(
            ImageFilter.GaussianBlur(0.65)
        )
    ).astype(np.float32) / 255.0

    body_blur = np.asarray(
        pil_mask(body_mask).filter(ImageFilter.GaussianBlur(5.0))
    ).astype(np.float32) / 255.0
    luminance = (
        rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    )
    shadow_alpha = np.clip((249.0 - luminance) / 249.0, 0.0, 0.10)
    shadow_alpha *= np.clip(body_blur - body_alpha, 0.0, 1.0)

    alpha = np.maximum.reduce((body_alpha, clip_alpha, shadow_alpha))
    foreground = cleaned.astype(np.float32)
    edge = (alpha > 0.015) & (alpha < 0.995)
    safe_alpha = np.maximum(alpha[..., None], 0.02)
    reconstructed = (foreground - background * (1.0 - safe_alpha)) / safe_alpha
    foreground[edge] = np.clip(reconstructed, 0, 255)[edge]

    shadow_only = (shadow_alpha > body_alpha) & (shadow_alpha > clip_alpha)
    foreground[shadow_only] = np.array([30.0, 72.0, 96.0], dtype=np.float32)
    foreground[alpha <= 0.005] = 0

    rgba = np.dstack(
        (np.clip(foreground, 0, 255).astype(np.uint8), np.clip(alpha * 255, 0, 255).astype(np.uint8))
    )
    output = Image.fromarray(rgba, "RGBA")
    metadata: dict[str, object] = {
        "sourceCrop": list(SOURCE_CROP),
        "sourcePixelSize": [source.width, source.height],
        "materialPixelSize": [output.width, output.height],
        "runtimeSize": {"width": RUNTIME_SIZE[0], "height": RUNTIME_SIZE[1]},
        "numberCenter": {"x": NUMBER_CENTER[0], "yFromTop": NUMBER_CENTER[1]},
        "progress": {
            "x": PROGRESS[0],
            "yFromTop": PROGRESS[1],
            "width": PROGRESS[2],
        },
        "clipCenter": {"x": CLIP_CENTER[0], "yFromTop": CLIP_CENTER[1]},
        "dynamicPixelsRemoved": int(dynamic_mask.sum()),
        "extraction": "approved-design-pixel-extraction-v1",
    }
    return output, metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--shared-output", type=Path, required=True)
    parser.add_argument("--macos-output", type=Path, required=True)
    parser.add_argument("--windows-output", type=Path, required=True)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGB")
    material, metadata = extract_material(source)
    metadata["source"] = str(args.source)
    for output_dir in (args.shared_output, args.macos_output, args.windows_output):
        output_dir.mkdir(parents=True, exist_ok=True)
        material.save(output_dir / "quota-airplane-material.png", "PNG", optimize=True)
        (output_dir / "quota-airplane-material.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == "__main__":
    main()
