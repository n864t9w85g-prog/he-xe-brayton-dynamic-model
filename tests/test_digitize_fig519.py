"""Black-box contract for the paper-only Figure 5.19 digitizer."""
import csv
import hashlib
import io
import json
import math
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import digitize_fig519 as subject


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/provenance/steady53/fig5_19"
SOURCE_HASH = "770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2"
TIMES = (10, 15, 20, 30, 40, 50, 75, 100, 150, 200, 230, 300, 400, 450, 495)


class Figure519DigitizationTests(unittest.TestCase):
    def test_literal_calibrations_and_fixed_times(self):
        self.assertEqual(subject.PANELS[0], subject.Panel("a", (179, 503, 0.0, 500.0), (341, 593, 3750.0, 1750.0), 25.0))
        self.assertEqual(subject.PANELS[1], subject.Panel("b", (555, 880, 0.0, 500.0), (338, 580, 2300.0, 1800.0), 6.0))
        self.assertEqual(subject.PANELS[2], subject.Panel("c", (179, 503, 0.0, 500.0), (675, 925, 1350.0, 1100.0), 3.0))
        self.assertEqual(subject.PANELS[3], subject.Panel("d", (555, 881, 0.0, 500.0), (701, 925, 1100.0, 600.0), 8.0))
        self.assertEqual(subject.SAMPLE_TIMES, TIMES)

    def test_publication_has_complete_paper_only_contract(self):
        subject.publish()
        self.assertEqual(hashlib.sha256((OUT / "source_page_106.png").read_bytes()).hexdigest(), SOURCE_HASH)
        with (OUT / "paper_points.csv").open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 60)
        by_panel = {panel: [r for r in rows if r["panel_id"] == panel] for panel in "abcd"}
        for panel, panel_rows in by_panel.items():
            self.assertEqual(tuple(float(r["time_s"]) for r in panel_rows), TIMES)
            self.assertEqual(len({r["time_s"] for r in panel_rows}), 15)
            self.assertEqual(len(panel_rows), 15)
            self.assertEqual(len({(r["panel_id"], r["time_s"]) for r in panel_rows}), 15)
            for row in panel_rows:
                for field in ("x_px", "y_px", "time_s", "power_kW", "power_allowance_kW", "time_allowance_s"):
                    self.assertTrue(math.isfinite(float(row[field])), f"{panel}:{field}")
            self.assertTrue(all(float(left["x_px"]) < float(right["x_px"]) for left, right in zip(panel_rows, panel_rows[1:])))
        self.assertTrue(3150 < float(by_panel["a"][0]["power_kW"]) < 3225)
        self.assertTrue(2640 < float(by_panel["a"][-1]["power_kW"]) < 2690)
        self.assertTrue(2190 < float(by_panel["b"][-1]["power_kW"]) < 2230)
        self.assertTrue(1200 < float(by_panel["c"][-1]["power_kW"]) < 1225)
        self.assertTrue(985 < float(by_panel["d"][-1]["power_kW"]) < 1015)
        provenance = json.loads((OUT / "provenance.json").read_text())
        self.assertEqual(provenance["source_page_sha256"], SOURCE_HASH)
        self.assertEqual(provenance["source_pdf_sha256"], "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a")
        self.assertEqual((provenance["pdf_page"], provenance["printed_page"], provenance["figure"]), (106, 91, "5.19"))
        self.assertEqual(provenance["panels"], json.loads(json.dumps([panel.__dict__ for panel in subject.PANELS])))
        self.assertEqual(provenance["grayscale_threshold"], 120)
        self.assertEqual(provenance["x_neighborhood"], "x-1 through x+1 (width 3)")
        self.assertIn("backward", provenance["trace_rule"])
        self.assertIn("contiguous", provenance["trace_rule"])
        self.assertIn("nearest", provenance["trace_rule"])
        self.assertIn("axis-border", provenance["rejections"])
        self.assertIn("80", provenance["rejections"])
        self.assertEqual(tuple(provenance["fixed_times_s"]), TIMES)
        self.assertEqual(provenance["time_allowance_s"], 3)
        self.assertIn("no smoothing", provenance["prohibitions"])
        self.assertIn("no time shifting", provenance["prohibitions"])
        self.assertIn("no model-guided selection", provenance["prohibitions"])
        self.assertIn("near-vertical", provenance["limitations"])
        self.assertIn("t=10", provenance["limitations"])
        self.assertIn("not author t0", provenance["limitations"])
        self.assertFalse(provenance["paper_reproduced"])
        self.assertFalse(provenance["formal_promotion"])

    def test_manifest_idempotence_verify_only_and_no_model_reads(self):
        subject.publish()
        before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()}
        subject.publish()
        self.assertEqual(before, {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()})
        subject.verify_only()
        self.assertEqual(before, {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.iterdir() if p.is_file()})
        with (OUT / "manifest.csv").open(newline="") as handle:
            manifest = list(csv.DictReader(handle))
        self.assertEqual({r["path"] for r in manifest}, {"source_page_106.png", "paper_points.csv", "provenance.json", "digitization_overlay.png", "README.md"})
        for row in manifest:
            artifact = OUT / row["path"]
            self.assertEqual(row["sha256"], hashlib.sha256(artifact.read_bytes()).hexdigest())
            self.assertEqual(int(row["bytes"]), artifact.stat().st_size)
        original_open = open
        original_io_open = io.open
        def guarded_open(path, *args, **kwargs):
            if any(token in str(path).lower() for token in (".slx", ".mat", "model_baseline", "baseline_p", "baseline_wt", "baseline_wc", "final_dynamic", "model_output")):
                raise AssertionError("digitizer attempted to read a model path")
            return original_open(path, *args, **kwargs)
        def guarded_io_open(path, *args, **kwargs):
            if any(token in str(path).lower() for token in (".slx", ".mat", "model_baseline", "baseline_p", "baseline_wt", "baseline_wc", "final_dynamic", "model_output")):
                raise AssertionError("digitizer attempted to read a model path")
            return original_io_open(path, *args, **kwargs)
        with mock.patch("builtins.open", guarded_open), mock.patch("io.open", guarded_io_open):
            with self.assertRaises(AssertionError):
                Path("forbidden_model.slx").read_bytes()
            subject.publish()

    def test_cli_reports_deterministic_counts_and_verify_only_preserves_mtimes(self):
        normal = subprocess.run([sys.executable, "tests/digitize_fig519.py"], cwd=ROOT, text=True, capture_output=True, check=False)
        self.assertEqual(normal.returncode, 0, normal.stderr)
        self.assertIn("POINTS=60 PANELS=4", normal.stdout)
        before = {p.name: (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns) for p in OUT.iterdir() if p.is_file()}
        verify = subprocess.run([sys.executable, "tests/digitize_fig519.py", "--verify-only"], cwd=ROOT, text=True, capture_output=True, check=False)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        self.assertIn("POINTS=60 PANELS=4", verify.stdout)
        self.assertEqual(before, {p.name: (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns) for p in OUT.iterdir() if p.is_file()})

    def test_source_has_no_forbidden_model_path_literals(self):
        source = Path(subject.__file__).read_text().lower()
        for forbidden in (".slx", ".mat", "model_baseline", "baseline_p", "baseline_wt", "baseline_wc", "final_dynamic", "model_output"):
            self.assertNotIn(forbidden, source)

    def test_rejects_conflicting_destination_and_verify_only_writes_nothing(self):
        with tempfile.TemporaryDirectory() as work:
            output = Path(work) / "out"
            subject.publish(output=output)
            (output / "README.md").write_text("conflict")
            with self.assertRaises(RuntimeError):
                subject.publish(output=output)
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            with self.assertRaises(RuntimeError):
                subject.verify_only(output=output)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})


if __name__ == "__main__":
    unittest.main(verbosity=2)
