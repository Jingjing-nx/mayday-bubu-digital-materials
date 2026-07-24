#!/usr/bin/env python3
"""Build and validate the low-CPU running-task badge GIF."""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (
    ROOT / "macos/BubuQuotaPanel/Resources/task-running-badge.gif",
    ROOT / "windows/BubuQuotaPanel/task-running-badge.gif",
)
SIZE = 32
FRAME_COUNT = 12
FRAME_DURATION_MS = 100
SUPERSAMPLE = 4
BLUE = (31, 118, 245, 255)
WHITE = (255, 255, 255, 255)


def build_frame(rotation_degrees: float) -> Image.Image:
    canvas_size = SIZE * SUPERSAMPLE
    frame = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    margin = 2.0 * SUPERSAMPLE
    draw.ellipse(
        (margin, margin, canvas_size - margin, canvas_size - margin),
        fill=BLUE,
    )

    center = canvas_size / 2.0
    radius = 8.4 * SUPERSAMPLE
    sweep = math.radians(278)
    start = math.radians(rotation_degrees - 72)
    points: list[tuple[float, float]] = []
    for index in range(41):
        angle = start + sweep * index / 40
        points.append(
            (
                center + math.cos(angle) * radius,
                center + math.sin(angle) * radius,
            )
        )
    draw.line(
        points,
        fill=WHITE,
        width=round(2.8 * SUPERSAMPLE),
        joint="curve",
    )

    end = start + sweep
    tip = points[-1]
    tangent = (-math.sin(end), math.cos(end))
    normal = (-tangent[1], tangent[0])
    head_length = 5.6 * SUPERSAMPLE
    head_half_width = 3.3 * SUPERSAMPLE
    base = (
        tip[0] - tangent[0] * head_length,
        tip[1] - tangent[1] * head_length,
    )
    draw.polygon(
        (
            tip,
            (
                base[0] + normal[0] * head_half_width,
                base[1] + normal[1] * head_half_width,
            ),
            (
                base[0] - normal[0] * head_half_width,
                base[1] - normal[1] * head_half_width,
            ),
        ),
        fill=WHITE,
    )

    return frame.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def build() -> None:
    frames = [
        build_frame(index * 360.0 / FRAME_COUNT)
        for index in range(FRAME_COUNT)
    ]
    for output in OUTPUTS:
        output.parent.mkdir(parents=True, exist_ok=True)
        frames[0].save(
            output,
            format="GIF",
            save_all=True,
            append_images=frames[1:],
            duration=FRAME_DURATION_MS,
            loop=0,
            disposal=2,
            optimize=True,
        )


def validate() -> None:
    digests: list[str] = []
    for output in OUTPUTS:
        if not output.is_file():
            raise SystemExit(f"missing running-task GIF: {output}")
        digests.append(hashlib.sha256(output.read_bytes()).hexdigest())
        with Image.open(output) as image:
            if image.size != (SIZE, SIZE):
                raise SystemExit(f"unexpected GIF size: {image.size}")
            if image.n_frames != FRAME_COUNT:
                raise SystemExit(f"unexpected GIF frame count: {image.n_frames}")
            if image.info.get("loop") != 0:
                raise SystemExit("running-task GIF does not loop forever")
            for frame_index in range(image.n_frames):
                image.seek(frame_index)
                if image.info.get("duration") != FRAME_DURATION_MS:
                    raise SystemExit(
                        f"unexpected frame duration at {frame_index}: "
                        f"{image.info.get('duration')}"
                    )
                rgba = image.convert("RGBA")
                if rgba.getbbox() is None:
                    raise SystemExit(f"empty GIF frame: {frame_index}")
    if len(set(digests)) != 1:
        raise SystemExit("macOS and Windows running-task GIFs differ")
    print(
        "task-running-gif: "
        f"size={SIZE}x{SIZE}; frames={FRAME_COUNT}; "
        f"duration={FRAME_DURATION_MS}ms; loop=forever; copies=identical"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate existing GIFs without rebuilding them",
    )
    args = parser.parse_args()
    if not args.check:
        build()
    validate()


if __name__ == "__main__":
    main()
