import json
import pathlib
import sys

from PIL import Image


root = pathlib.Path(__file__).resolve().parents[1]
pet_dir = root / "shared" / "pet" / "bubu-office"
manifest = json.loads((pet_dir / "pet.json").read_text(encoding="utf-8"))
atlas = Image.open(pet_dir / "spritesheet.webp")

assert manifest["id"] == "bubu-office"
assert manifest["spriteVersionNumber"] == 2
assert manifest["spritesheetPath"] == "spritesheet.webp"
assert atlas.size == (1536, 2288)
assert atlas.mode == "RGBA"
assert atlas.getextrema()[3][0] == 0, "atlas must contain transparent pixels"

print("Pet manifest and 8x11 atlas geometry: OK")
