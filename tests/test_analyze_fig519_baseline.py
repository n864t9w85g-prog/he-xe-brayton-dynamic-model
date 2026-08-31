"""Contract tests for preservation and analysis of the Figure 5.19 baseline."""
import csv
import hashlib
import json
import math
import os
import subprocess
import sys
import unittest
from pathlib import Path

from tests import analyze_fig519_baseline as subject
from tests import digitize_fig519 as digitizer


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/provenance/steady53/fig5_19"
BASELINE = OUT / "model_baseline"
SOURCE = ROOT / "tmp/steady53_curves_20260828/results"
SOURCE_HASHES = {
    "baseline.mat": "18975fc912ed2af87f325769d4be9ab54f4ad0c091f925e4cda5df497aa55698",
    "baseline_P_sw.csv": "288a9b031d31f8168517ea30d06f712d72c4d1dc31fd911f0a266aaa3023999f",
    "baseline_WT_sw.csv": "28b852e9b997af51a860905e53da096821ddfbdd310857d16e9df0761ca2ab23",
    "baseline_Wc_sw.csv": "f44a9bca2c006780f287e4f3a7199f63d26348cc18ad261d4ad89570b0e9ad5c",
}


class Figure519BaselineTests(unittest.TestCase):
    def test_contract_is_literal_and_analysis_reports_flat_nonreproduction(self):
        metrics, contract = subject.analyze()
        self.assertEqual(metrics["final_time_s"], 14000.0)
        self.assertLess(metrics["signals"]["reactor"]["peak_to_peak_W"], 0.2)
        self.assertLess(metrics["signals"]["turbine"]["peak_to_peak_W"], 0.2)
        self.assertLess(metrics["signals"]["compressor"]["peak_to_peak_W"], 0.3)
        self.assertLess(metrics["signals"]["electrical_paper_eta"]["peak_to_peak_W"], 0.5)
        self.assertFalse(metrics["paper_reproduced"])
        self.assertEqual(metrics["paper_eta"], 0.98)
        self.assertEqual(metrics["historical_metric_eta"], 0.96527)
        self.assertIsNone(contract["signals"]["electrical_paper_eta"]["direct_generator_signal"])
        self.assertGreater(metrics["final_definition_gap_kW"], 15.0)
        self.assertEqual(contract["paper_reproduced"], False)
        self.assertEqual(contract["formal_promotion"], False)
        self.assertEqual(contract["signals"]["reactor"], {
            "model_signal": "P_sw", "kind": "direct_workspace_signal", "api_trace_status": "required_in_task_6"})
        self.assertEqual(contract["signals"]["turbine"], {
            "model_signal": "WT_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"})
        self.assertEqual(contract["signals"]["compressor"], {
            "model_signal": "Wc_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"})
        self.assertEqual(contract["signals"]["electrical_historical_metric"], {
            "formula": "0.96527*(WT_sw-Wc_sw)", "kind": "historical_offline_derived", "accepted_for_fig519": False})

    def test_publication_preserves_sources_and_unified_manifest_layers(self):
        subject.publish()
        self.assertEqual({p.name for p in BASELINE.iterdir()}, set(SOURCE_HASHES))
        for name, expected in SOURCE_HASHES.items():
            self.assertEqual(hashlib.sha256((BASELINE / name).read_bytes()).hexdigest(), expected)
            self.assertEqual((BASELINE / name).read_bytes(), (SOURCE / name).read_bytes())
        metrics = json.loads((OUT / "baseline_metrics.json").read_text())
        contract = json.loads((OUT / "signal_contract.json").read_text())
        self.assertEqual(metrics, subject.analyze()[0])
        self.assertEqual(contract, subject.analyze()[1])
        with (OUT / "manifest.csv").open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual({row["path"] for row in rows}, set(digitizer.ARTIFACT_NAMES) | {
            "model_baseline/baseline.mat", "model_baseline/baseline_P_sw.csv",
            "model_baseline/baseline_WT_sw.csv", "model_baseline/baseline_Wc_sw.csv",
            "baseline_metrics.json", "signal_contract.json"})
        self.assertEqual(len(rows), 11)

    def test_four_comparisons_have_finite_interpolated_metrics_and_locked_csv_schema(self):
        metrics, _ = subject.analyze()
        self.assertEqual(set(metrics["comparisons"]), {"reactor", "turbine", "compressor", "electrical_paper_eta"})
        for comparison in metrics["comparisons"].values():
            self.assertEqual(comparison["comparison_units"], {"model": "W", "paper": "kW"})
            self.assertEqual(comparison["paper_points"], 15)
            for key in ("rmse_kW", "max_abs_error_kW", "start_error_kW", "end_error_kW", "squared_error_contribution_kW2"):
                self.assertTrue(math.isfinite(comparison[key]), key)
        for name in ("baseline_P_sw.csv", "baseline_WT_sw.csv", "baseline_Wc_sw.csv"):
            with (SOURCE / name).open(newline="") as handle:
                rows = list(csv.reader(handle))
            self.assertTrue(rows and all(len(row) == 2 for row in rows))

    def test_verify_only_is_durable_source_independent_and_no_write(self):
        subject.publish()
        before = {p.relative_to(OUT): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns)
                  for p in OUT.rglob("*") if p.is_file()}
        original = subject.SOURCE_DIR
        try:
            subject.SOURCE_DIR = ROOT / "tmp/no-longer-available"
            subject.verify_only()
        finally:
            subject.SOURCE_DIR = original
        after = {p.relative_to(OUT): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns)
                 for p in OUT.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_changed_external_source_is_rejected_before_publication(self):
        source = SOURCE / "baseline_P_sw.csv"
        original = source.read_bytes()
        source.write_bytes(original + b"\n")
        try:
            with self.assertRaises(RuntimeError):
                subject.publish()
        finally:
            source.write_bytes(original)

    def test_layers_verify_in_either_order_and_reject_unregistered_extra(self):
        subject.publish()
        digitizer.publish()
        digitizer.verify_only()
        subject.verify_only()
        subject.verify_only()
        digitizer.verify_only()
        extra = OUT / "model_baseline" / "unregistered.txt"
        extra.write_text("no")
        try:
            with self.assertRaises(RuntimeError):
                subject.verify_only()
            with self.assertRaises(RuntimeError):
                digitizer.verify_only()
        finally:
            extra.unlink()

    def test_cli_and_coordinated_corruption_are_rejected(self):
        subject.publish()
        normal = subprocess.run([sys.executable, "tests/analyze_fig519_baseline.py"], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(normal.returncode, 0, normal.stderr)
        verify = subprocess.run([sys.executable, "tests/analyze_fig519_baseline.py", "--verify-only"], cwd=ROOT, text=True, capture_output=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        target = OUT / "baseline_metrics.json"
        original = target.read_bytes()
        target.write_bytes(original + b" ")
        try:
            # A coordinated manifest rewrite cannot bypass recomputation from durable data.
            with (OUT / "manifest.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            for row in rows:
                if row["path"] == "baseline_metrics.json":
                    row["bytes"] = str(target.stat().st_size)
                    row["sha256"] = hashlib.sha256(target.read_bytes()).hexdigest()
            subject.write_manifest(OUT, rows)
            with self.assertRaises(RuntimeError):
                subject.verify_only()
        finally:
            target.write_bytes(original)
            subject.publish()


if __name__ == "__main__":
    unittest.main(verbosity=2)
