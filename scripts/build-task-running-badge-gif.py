#!/usr/bin/env python3
"""Build the low-power 32px running-task badge used by both desktop panels."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = (
    ROOT / "macos/BubuQuotaPanel/Resources/task-running-badge.gif",
    ROOT / "windows/BubuQuotaPanel/task-running-badge.gif",
)
SIZE = 32
SCALE = 4
FRAME_COUNT = 12
FRAME_DURATION_MS = 100
BLUE = (31, 118, 245, 255)
WHITE = (255, 255, 255, 255)


def render_frame(index: int) -> Image.Image:
    canvas_size = SIZE * SCALE
    frame = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)

    margin = 1.5 * SCALE
    draw.ellipse(
        (margin, margin, canvas_size - margin, canvas_size - margin),
        fill=BLUE,
    )

    rotation = index * (360 / FRAME_COUNT)
    start = rotation - 72
    end = start + 280
    radius = 8.7 * SCALE
    center = canvas_size / 2
    arc_box = (
        center - radius,
        center - radius,
        center + radius,
        center + radius,
    )
    draw.arc(arc_box, start=start, end=end, fill=WHITE, width=3 * SCALE)

    end_radians = math.radians(end)
    tip = (
        center + math.cos(end_radians) * radius,
        center + math.sin(end_radians) * radius,
    )
    tangent = (-math.sin(end_radians), math.cos(end_radians))
    normal = (-tangent[1], tangent[0])
    head_length = 5.0 * SCALE
    head_half_width = 3.1 * SCALE
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


def indexed_gif_frame(frame: Image.Image) -> Image.Image:
    alpha = frame.getchannel("A")
    # GIF has binary transparency. Preserve smooth internal antialiasing while
    # keeping a single transparent palette entry around the circular badge.
    rgb = Image.new("RGB", frame.size, BLUE[:3])
    rgb.paste(frame.convert("RGB"), mask=alpha)
    quantized = rgb.quantize(colors=255, method=Image.Quantize.MEDIANCUT)

    output = Image.new("P", frame.size, 0)
    source_pixels = list(quantized.get_flattened_data())
    alpha_pixels = list(alpha.get_flattened_data())
    output.putdata(
        [0 if alpha_value < 128 else palette_index + 1
         for palette_index, alpha_value in zip(source_pixels, alpha_pixels)]
    )
    source_palette = quantized.getpalette()[: 255 * 3]
    output.putpalette([0, 0, 0, *source_palette, *([0, 0, 0] * (255 - len(source_palette) // 3))])
    output.info["transparency"] = 0
    return output


def verify(path: Path) -> None:
    with Image.open(path) as image:
        assert image.size == (SIZE, SIZE), image.size
        assert image.n_frames == FRAME_COUNT, image.n_frames
        assert image.info.get("loop") == 0, image.info.get("loop")
        durations = []
        for frame_index in range(image.n_frames):
            image.seek(frame_index)
            durations.append(image.info.get("duration"))
        assert durations == [FRAME_DURATION_MS] * FRAME_COUNT, durations


def main() -> None:
    frames = [indexed_gif_frame(render_frame(index)) for index in range(FRAME_COUNT)]
    for output in OUTPUTS:
        output.parent.mkdir(parents=True, exist_ok=True)
        frames[0].save(
            output,
            save_all=True,
            append_images=frames[1:],
            duration=[FRAME_DURATION_MS] * FRAME_COUNT,
            loop=0,
            transparency=0,
            disposal=2,
            optimize=False,
        )
        verify(output)
        print(output)


if __name__ == "__main__":
    main()
