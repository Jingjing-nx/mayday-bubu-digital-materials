#!/usr/bin/env python3
"""Create a Windows release ZIP with explicit UTF-8 entry names.

macOS `ditto -c -k` leaves filename encoding to the extractor.  Windows
Explorer then interprets Chinese names as legacy code-page bytes.  Python's
ZIP writer records Unicode paths with the ZIP UTF-8 (EFS) flag, which keeps
the visible folder and all .cmd filenames readable in Explorer.
"""

from __future__ import annotations

import argparse
import os
import stat
import sys
import zipfile
from datetime import datetime
from pathlib import Path


def archive_name(path: Path, stage_parent: Path) -> str:
    return path.relative_to(stage_parent).as_posix()


def zip_timestamp(path: Path) -> tuple[int, int, int, int, int, int]:
    modified = datetime.fromtimestamp(path.stat().st_mtime)
    # ZIP cannot encode timestamps earlier than 1980.
    if modified.year < 1980:
        return (1980, 1, 1, 0, 0, 0)
    return modified.timetuple()[:6]


def write_archive(stage: Path, output: Path) -> list[str]:
    entries = [path for path in sorted(stage.rglob("*")) if path.is_file()]
    if not entries:
        raise ValueError(f"Release stage is empty: {stage}")

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    if temporary.exists():
        temporary.unlink()

    names: list[str] = []
    try:
        with zipfile.ZipFile(
            temporary, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
        ) as archive:
            for source in entries:
                if source.is_symlink():
                    raise ValueError(f"Release payload cannot contain a symlink: {source}")
                name = archive_name(source, stage.parent)
                info = zipfile.ZipInfo(name, zip_timestamp(source))
                info.compress_type = zipfile.ZIP_DEFLATED
                # General-purpose bit 11 is the ZIP standard UTF-8 indicator.
                # zipfile also preserves this when serializing a non-ASCII path.
                info.flag_bits |= 0x800
                info.create_system = 3
                info.external_attr = (stat.S_IMODE(source.stat().st_mode) & 0xFFFF) << 16
                with source.open("rb") as payload:
                    archive.writestr(info, payload.read())
                names.append(name)
        temporary.replace(output)
    finally:
        if temporary.exists():
            temporary.unlink()
    return names


def verify_utf8_names(output: Path, expected_names: list[str]) -> None:
    with zipfile.ZipFile(output, mode="r") as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if names != expected_names:
            raise ValueError("ZIP entries differ from the staged release payload")
        for info in infos:
            if any(ord(character) > 127 for character in info.filename) and not (
                info.flag_bits & 0x800
            ):
                raise ValueError(f"Unicode ZIP entry lacks the UTF-8 flag: {info.filename}")
        invalid = archive.testzip()
        if invalid:
            raise ValueError(f"ZIP integrity check failed: {invalid}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    stage = args.stage.resolve()
    output = args.output.resolve()
    if not stage.is_dir():
        raise ValueError(f"Release stage does not exist: {stage}")
    names = write_archive(stage, output)
    verify_utf8_names(output, names)
    unicode_entries = sum(any(ord(character) > 127 for character in name) for name in names)
    print(f"{output} entries={len(names)} unicode-utf8-entries={unicode_entries}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"Windows ZIP build failed: {error}", file=sys.stderr)
        raise SystemExit(1)
