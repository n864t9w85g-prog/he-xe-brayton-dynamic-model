"""Black-box contract for the paper-only Figure 5.19 digitizer."""
import csv
import hashlib
import json
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
            self.assertTrue(all(float(r["power_kW"]) == float(r["power_kW"]) for r in panel_rows))
        self.assertTrue(3150 < float(by_panel["a"][0]["power_kW"]) < 3225)
        self.assertTrue(2640 < float(by_panel["a"][-1]["power_kW"]) < 2690)
        self.assertTrue(2190 < float(by_panel["b"][-1]["power_kW"]) < 2230)
        self.assertTrue(1200 < float(by_panel["c"][-1]["power_kW"]) < 1225)
        self.assertTrue(985 < float(by_panel["d"][-1]["power_kW"]) < 1015)
        provenance = json.loads((OUT / "provenance.json").read_text())
        self.assertFalse(provenance["paper_reproduced"])
        self.assertFalse(provenance["formal_promotion"])
        self.assertIn("no smoothing", provenance["prohibitions"])

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
        def guarded_open(path, *args, **kwargs):
            if any(token in str(path).lower() for token in (".slx", ".mat", "final_dynamic", "baseline")):
                raise AssertionError("digitizer attempted to read a model path")
            return original_open(path, *args, **kwargs)
        with mock.patch("builtins.open", guarded_open):
            subject.publish()

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
