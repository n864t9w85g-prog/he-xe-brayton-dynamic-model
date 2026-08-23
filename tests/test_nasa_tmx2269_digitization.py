from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import unittest

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "data" / "provenance" / "compressor_map" / "nasa_tmx2269"
CALIBRATION = PROVENANCE / "calibration.json"
POINTS = PROVENANCE / "digitized_points.csv"
SOURCE_PDF = ROOT / "sources" / "NASA-TM-X-2269-Ball-Tysl-Weigel-1971.pdf"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Tmx2269DigitizationTests(unittest.TestCase):
    def test_digitized_points_are_bound_to_source_pixels(self) -> None:
        self.assertTrue(CALIBRATION.is_file(), "missing TM X-2269 calibration")
        self.assertTrue(POINTS.is_file(), "missing TM X-2269 digitized points")

        calibration = json.loads(CALIBRATION.read_text(encoding="utf-8"))
        self.assertEqual(calibration["source_pdf_sha256"], sha256(SOURCE_PDF))
        self.assertEqual(calibration["source_report"], "NASA TM X-2269")
        self.assertEqual(calibration["render_dpi"], 300)

        for quantity in ("pressure_ratio", "efficiency"):
            source_image = ROOT / calibration[quantity]["source_image"]
            overlay_image = ROOT / calibration[quantity]["overlay_image"]
            self.assertEqual(
                calibration[quantity]["source_image_sha256"], sha256(source_image)
            )
            self.assertTrue(overlay_image.is_file(), f"missing overlay for {quantity}")
            with Image.open(source_image) as source, Image.open(overlay_image) as overlay:
                self.assertEqual(overlay.size, source.size)

        with POINTS.open(newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
        self.assertGreater(len(rows), 0)
        self.assertEqual(
            set(rows[0]),
            {
                "quantity",
                "speed_ratio",
                "point_index",
                "pixel_x",
                "pixel_y",
                "flow_eq_kg_s",
                "value",
            },
        )

        expected_speeds = {0.5, 0.6, 0.7, 0.8, 0.9, 1.0}
        for quantity in ("pressure_ratio", "efficiency"):
            subset = [row for row in rows if row["quantity"] == quantity]
            self.assertEqual({float(row["speed_ratio"]) for row in subset}, expected_speeds)
            for speed in expected_speeds:
                curve = [row for row in subset if float(row["speed_ratio"]) == speed]
                self.assertGreaterEqual(len(curve), 4, f"too few {quantity} points at {speed}")

            axes = calibration[quantity]["axes_pixels"]
            x_left = float(axes["x_left"])
            x_right = float(axes["x_right"])
            y_top = float(axes["y_top"])
            y_bottom = float(axes["y_bottom"])
            x_min, x_max = map(float, calibration[quantity]["x_range_kg_s"])
            y_min, y_max = map(float, calibration[quantity]["y_range"])

            for row in subset:
                pixel_x = float(row["pixel_x"])
                pixel_y = float(row["pixel_y"])
                expected_x = x_min + (pixel_x - x_left) * (x_max - x_min) / (x_right - x_left)
                expected_y = y_max - (pixel_y - y_top) * (y_max - y_min) / (y_bottom - y_top)
                self.assertAlmostEqual(float(row["flow_eq_kg_s"]), expected_x, places=8)
                self.assertAlmostEqual(float(row["value"]), expected_y, places=8)

            overlay_path = ROOT / calibration[quantity]["overlay_image"]
            with Image.open(overlay_path).convert("RGB") as overlay:
                for row in subset:
                    speed = f"{float(row['speed_ratio']):.1f}"
                    expected_color = tuple(calibration["overlay_colors_rgb"][speed])
                    pixel = overlay.getpixel(
                        (round(float(row["pixel_x"])), round(float(row["pixel_y"])))
                    )
                    self.assertEqual(pixel, expected_color)

        review = calibration["visual_review"]
        self.assertEqual(review["status"], "verified")
        self.assertLessEqual(float(review["maximum_marker_displacement_px"]), 2.0)

    def test_measured_and_predicted_design_points_remain_distinct(self) -> None:
        self.assertTrue(CALIBRATION.is_file(), "missing TM X-2269 calibration")
        calibration = json.loads(CALIBRATION.read_text(encoding="utf-8"))
        self.assertIn("published_design_conditions", calibration)
        self.assertIn("predicted_design_markers", calibration)
        measured = calibration["published_design_conditions"]
        self.assertAlmostEqual(measured["flow_eq_kg_s"], 0.69, places=12)
        self.assertAlmostEqual(measured["pressure_ratio"], 2.28, places=12)
        self.assertAlmostEqual(measured["efficiency"], 0.80, places=12)

        predicted = calibration["predicted_design_markers"]
        self.assertAlmostEqual(predicted["flow_eq_kg_s"], 0.69, places=12)
        self.assertAlmostEqual(predicted["pressure_ratio"], 2.30, places=12)
        self.assertAlmostEqual(predicted["efficiency"], 0.82, places=12)

        with POINTS.open(newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
        for quantity, published, tolerance in (
            ("pressure_ratio", 2.28, 0.02),
            ("efficiency", 0.80, 0.005),
        ):
            curve = sorted(
                (float(row["flow_eq_kg_s"]), float(row["value"]))
                for row in rows
                if row["quantity"] == quantity and float(row["speed_ratio"]) == 1.0
            )
            interpolated = None
            for (x0, y0), (x1, y1) in zip(curve, curve[1:]):
                if x0 <= measured["flow_eq_kg_s"] <= x1:
                    fraction = (measured["flow_eq_kg_s"] - x0) / (x1 - x0)
                    interpolated = y0 + fraction * (y1 - y0)
                    break
            self.assertIsNotNone(interpolated)
            self.assertLessEqual(abs(interpolated - published), tolerance)


if __name__ == "__main__":
    unittest.main()
