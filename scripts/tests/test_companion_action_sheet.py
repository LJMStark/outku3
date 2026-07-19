import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


SCRIPT = Path(__file__).parents[1] / "companion_action_sheet.py"
SPEC = importlib.util.spec_from_file_location("companion_action_sheet", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CompanionActionSheetTests(unittest.TestCase):
    def test_grid_split_preserves_alpha_and_output_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = Image.new("RGB", (220, 110), (234, 235, 234))
            draw = ImageDraw.Draw(source)
            draw.rectangle((12, 12, 98, 98), fill=(120, 70, 30))
            draw.ellipse((145, 20, 205, 100), fill=(20, 120, 70))
            source_path = root / "fixture.png"
            source.save(source_path)

            written = MODULE.split_sheet(
                sheet_path=source_path,
                character="joy",
                catalog=root / "Media.xcassets",
                review_output=root / "contact.png",
                grid=MODULE.Grid(rows=1, columns=2),
                motions=("idle",),
                canvas_size=128,
                placement="cell",
                padding=8,
                vertical_lifts={},
                extraction="grid",
                manifest_output=root / "manifest.json",
            )

            self.assertEqual(len(written), 2)
            self.assertEqual(written[0].parent.name, "joy-idle-01.imageset")
            self.assertTrue((written[0].parent / "Contents.json").exists())
            self.assertTrue((root / "contact.png").exists())
            manifest = json.loads((root / "manifest.json").read_text())
            self.assertEqual(manifest["frameCount"], 2)
            self.assertEqual(manifest["frames"][0]["anchor"], {"x": 0.5, "y": 1.0})
            frame = Image.open(written[0])
            self.assertEqual(frame.size, (128, 128))
            self.assertEqual(frame.mode, "RGBA")
            self.assertEqual(frame.getchannel("A").getextrema(), (0, 255))

    def test_component_extraction_ignores_nominal_grid_boundaries(self):
        source = Image.new("RGB", (220, 120), (234, 235, 234))
        draw = ImageDraw.Draw(source)
        draw.rectangle((20, 10, 80, 105), fill=(120, 70, 30))
        draw.ellipse((135, 2, 205, 112), fill=(20, 120, 70))

        frames = MODULE.extract_component_frames(
            source,
            expected_count=2,
            columns=2,
            minimum_area=500,
        )

        self.assertEqual(len(frames), 2)
        self.assertGreater(frames[0].height, 90)
        self.assertGreater(frames[1].height, 100)

    def test_single_motion_layout_numbers_all_cells_and_can_preserve_scene(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = Image.new("RGB", (200, 200), (246, 240, 220))
            source_path = root / "scene.png"
            source.save(source_path)

            written = MODULE.split_sheet(
                sheet_path=source_path,
                character="joy",
                catalog=root / "Media.xcassets",
                review_output=root / "contact.png",
                grid=MODULE.Grid(rows=2, columns=2),
                motions=("pet-scene-react",),
                canvas_size=128,
                placement="cell",
                padding=0,
                layout="single-motion",
                remove_background=False,
            )

            self.assertEqual(len(written), 4)
            self.assertEqual(written[-1].parent.name, "joy-pet-scene-react-04.imageset")
            self.assertEqual(Image.open(written[0]).getchannel("A").getextrema(), (255, 255))

    def test_motion_region_keeps_every_pixel_outside_character_region_stable(self):
        base = Image.new("RGBA", (64, 64), (240, 230, 190, 255))
        changed = base.copy()
        base.putpixel((8, 54), (20, 140, 40, 255))
        changed.putpixel((8, 54), (220, 40, 40, 255))
        changed.putpixel((32, 24), (30, 60, 180, 255))

        stabilized = MODULE.stabilize_motion_region(
            [base, changed],
            region=(16, 8, 32, 32),
            feather=0,
        )

        self.assertEqual(stabilized[1].getpixel((8, 54)), base.getpixel((8, 54)))
        self.assertEqual(stabilized[1].getpixel((32, 24)), changed.getpixel((32, 24)))
        MODULE.validate_stable_outside_region(
            stabilized,
            region=(16, 8, 32, 32),
            feather=0,
        )


if __name__ == "__main__":
    unittest.main()
