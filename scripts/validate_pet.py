import json
import pathlib
import sys

from PIL import Image


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

print("Blue Bubu manifest and 8x11 atlas geometry: OK")
