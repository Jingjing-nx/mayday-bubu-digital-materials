import json
import pathlib
import sys

from PIL import Image, ImageChops


root = pathlib.Path(__file__).resolve().parents[1]
pet_ids = ("bubu-office",)

for pet_id in pet_ids:
    pet_dir = root / "shared" / "pet" / pet_id
    manifest = json.loads((pet_dir / "pet.json").read_text(encoding="utf-8"))
    with Image.open(pet_dir / "spritesheet.webp") as atlas:
        assert manifest["id"] == pet_id
        assert manifest["spriteVersionNumber"] == 2
        assert manifest["spritesheetPath"] == "spritesheet.webp"
        assert atlas.size == (1536, 2288)
        assert atlas.mode == "RGBA"
        assert atlas.getextrema()[3][0] == 0, "atlas must contain transparent pixels"

        cell_width = atlas.width // 8
        cell_height = atlas.height // 11
        right_restart = atlas.crop((0, cell_height, cell_width, cell_height * 2))
        left_restart = atlas.crop((0, cell_height * 2, cell_width, cell_height * 3))
        assert ImageChops.difference(right_restart, left_restart).getbbox() is None, (
            "running-right restart cell must match the singing restart cell"
        )

        right_guitar = atlas.crop(
            (cell_width, cell_height, cell_width * 2, cell_height * 2)
        )
        assert ImageChops.difference(right_guitar, left_restart).getbbox() is not None, (
            "running-right guitar frames must remain available after the safe restart cell"
        )

print("Blue Bubu manifest, 8x11 atlas geometry, and restart-safe cell: OK")
