#!/usr/bin/env python3
"""Make the hidden right-drag restart frame visually identical to singing.

Codex restarts a non-idle animation only after its state changes. The quota
helper briefly crosses into running-right before returning to running-left.
Copying the first running-left cell over the first running-right cell makes
that five-millisecond transition visually continuous, even when it lands on a
display refresh boundary. The remaining seven running-right guitar cells are
left untouched.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from PIL import Image, ImageChops


FRAME_WIDTH = 192
FRAME_HEIGHT = 208
RUNNING_RIGHT_ROW = 1
RUNNING_LEFT_ROW = 2


def cell_box(row: int, column: int = 0) -> tuple[int, int, int, int]:
    left = column * FRAME_WIDTH
    top = row * FRAME_HEIGHT
    return left, top, left + FRAME_WIDTH, top + FRAME_HEIGHT


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("atlas", type=Path)
    args = parser.parse_args()

    atlas_path = args.atlas.resolve()
    with Image.open(atlas_path) as source:
        atlas = source.convert("RGBA")

    if atlas.size != (FRAME_WIDTH * 8, FRAME_HEIGHT * 11):
        raise SystemExit(f"unexpected atlas size: {atlas.size}")

    singing_first_frame = atlas.crop(cell_box(RUNNING_LEFT_ROW))
    atlas.paste(singing_first_frame, cell_box(RUNNING_RIGHT_ROW)[:2])

    if ImageChops.difference(
        atlas.crop(cell_box(RUNNING_RIGHT_ROW)),
        singing_first_frame,
    ).getbbox() is not None:
        raise SystemExit("restart-safe frame copy failed")

    temporary_path = atlas_path.with_suffix(".restart-safe.tmp.webp")
    atlas.save(temporary_path, format="WEBP", lossless=True, method=6, exact=True)
    os.replace(temporary_path, atlas_path)
    print(
        "restart-frame-safe: running-right[0]=running-left[0]; "
        "running-right[1...7]=unchanged"
    )


if __name__ == "__main__":
    main()
