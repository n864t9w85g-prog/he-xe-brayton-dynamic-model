"""Contract tests for preservation and analysis of the Figure 5.19 baseline."""
import csv
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

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
    def _paper_only_output(self, work: str) -> Path:
        output = Path(work) / "fig5_19"
        digitizer.publish(output=output)
        return output

    def test_interrupted_baseline_publication_is_resumable(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            original = subject._write_exclusive
            writes = 0
            def fail_second_write(path, payload):
                nonlocal writes
                writes += 1
                if writes == 2:
                    raise OSError("injected stage interruption")
                original(path, payload)
            with mock.patch.object(subject, "_write_exclusive", fail_second_write):
                with self.assertRaises(OSError):
                    subject.publish(output=output)
            with self.assertRaises(RuntimeError):
                subject.verify_only(output=output)
            subject.publish(output=output)
            subject.verify_only(output=output)
            digitizer.verify_only(output=output)

    def test_first_record_write_failure_never_publishes_canonical_transaction(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            txn = subject._transaction_dir(output)
            original = subject._write_exclusive
            def fail_record(path, payload):
                if path.name == "record.json":
                    raise OSError("injected record write failure")
                original(path, payload)
            with mock.patch.object(subject, "_write_exclusive", fail_record):
                with self.assertRaises(OSError):
                    subject.publish(output=output)
            self.assertFalse(os.path.lexists(txn))
            self.assertTrue(list(output.parent.glob(output.name + ".task5-init-*")))
            with self.assertRaises(RuntimeError):
                subject.verify_only(output=output)
            subject.publish(output=output)
            subject.verify_only(output=output)

    def test_nonreplace_commit_never_overwrites_a_concurrently_created_target(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            root = Path(work)
            staged = root / "staged.json"
            target = root / "target.json"
            payload = b"expected"
            staged.write_bytes(payload)
            original_link = os.link
            def create_conflict(source, destination, **kwargs):
                target.write_bytes(b"concurrent")
                return original_link(source, destination, **kwargs)
            with mock.patch.object(subject.os, "link", create_conflict):
                with self.assertRaises(RuntimeError):
                    subject._commit_target(staged, target, payload)
            self.assertEqual(target.read_bytes(), b"concurrent")

    def test_precanonical_boundaries_leave_only_ignorable_init_audit_directories(self):
        boundaries = (
            "init-mkdir-after", "record-write-after", "payload-mkdir-before",
            "payload-mkdir-after", "staged-first-after", "staged-middle-after",
            "staged-last-after", "canonical-rename-before",
        )
        for boundary in boundaries:
            with self.subTest(boundary=boundary), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                output = self._paper_only_output(work)
                def fail(point):
                    if point == boundary:
                        raise OSError(f"injected {point}")
                with mock.patch.object(subject, "_publication_boundary", fail):
                    with self.assertRaises(OSError):
                        subject.publish(output=output)
                self.assertFalse(os.path.lexists(subject._transaction_dir(output)))
                self.assertTrue(list(output.parent.glob(output.name + ".task5-init-*")))
                with self.assertRaises(RuntimeError):
                    subject.verify_only(output=output)
                subject.publish(output=output)
                subject.verify_only(output=output)

    def test_actual_first_middle_last_staged_write_failures_remain_precanonical(self):
        for failing_index in (0, 3, 6):
            with self.subTest(failing_index=failing_index), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                output = self._paper_only_output(work)
                original = subject._write_exclusive
                staged_writes = 0
                def fail_payload_write(path, payload):
                    nonlocal staged_writes
                    if "payload" in path.parts:
                        if staged_writes == failing_index:
                            raise OSError(f"injected staged write {failing_index}")
                        staged_writes += 1
                    original(path, payload)
                with mock.patch.object(subject, "_write_exclusive", fail_payload_write):
                    with self.assertRaises(OSError):
                        subject.publish(output=output)
                self.assertFalse(os.path.lexists(subject._transaction_dir(output)))
                subject.publish(output=output)
                subject.verify_only(output=output)

    def test_postcanonical_rename_failure_resumes_from_the_canonical_transaction(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            def fail(point):
                if point == "canonical-rename-after":
                    raise OSError("injected post-canonical rename failure")
            with mock.patch.object(subject, "_publication_boundary", fail):
                with self.assertRaises(OSError):
                    subject.publish(output=output)
            self.assertTrue(subject._transaction_dir(output).is_dir())
            subject.publish(output=output)
            subject.verify_only(output=output)

    def test_normal_publish_recovers_exact_pre_transaction_partial_layer(self):
        """An older interruption may have moved the layer before creating a record."""
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            delta = subject._planned_delta(output, SOURCE)
            layer = output / digitizer.BASELINE_LAYER_DIR
            layer.mkdir()
            for name in digitizer.BASELINE_LAYER_NAMES:
                (layer / name).write_bytes(delta[f"{digitizer.BASELINE_LAYER_DIR}/{name}"])
            with self.assertRaises(RuntimeError):
                subject.verify_only(output=output)
            subject.publish(output=output)
            subject.verify_only(output=output)
            digitizer.verify_only(output=output)

    def test_each_publication_boundary_leaves_a_resumable_partial_tree(self):
        boundaries = (
            "transaction-record", "staged-baseline", "baseline-layer-rename",
            "baseline-metrics-commit", "signal-contract-commit", "manifest-commit",
        )
        for boundary in boundaries:
            with self.subTest(boundary=boundary), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                output = self._paper_only_output(work)
                def fail(point):
                    if point == boundary:
                        raise OSError(f"injected {point}")
                # The production hook is deliberately exercised through normal
                # publication, not by calling transaction helpers directly.
                with mock.patch.object(subject, "_publication_boundary", fail, create=True):
                    with self.assertRaises(OSError):
                        subject.publish(output=output)
                with self.assertRaises(RuntimeError):
                    subject.verify_only(output=output)
                subject.publish(output=output)
                subject.verify_only(output=output)
                digitizer.verify_only(output=output)

    def test_parser_rejects_malformed_or_insufficient_csv(self):
        for payload in (b"t,value\n", b"0,nan\n", b"0,inf\n", b"1,2\n0,3\n", b"0,1\n0,2\n", b"0,1\n"):
            with self.assertRaises(RuntimeError):
                subject._read_series(payload, "synthetic.csv")

    def test_transaction_conflicts_are_rejected_without_target_overwrite(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            txn = subject._transaction_dir(output)
            os.symlink(output, txn)
            before = (output / "manifest.csv").read_bytes()
            with self.assertRaises(RuntimeError):
                subject.publish(output=output)
            self.assertEqual((output / "manifest.csv").read_bytes(), before)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            txn = subject._transaction_dir(output)
            txn.mkdir(); (txn / "record.json").write_text("not a transaction")
            (txn / "payload").mkdir()
            before = (output / "manifest.csv").read_bytes()
            with self.assertRaises(RuntimeError):
                subject.publish(output=output)
            self.assertEqual((output / "manifest.csv").read_bytes(), before)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            txn = subject._transaction_dir(output)
            txn.mkdir(); (txn / "record.json").write_text("not a transaction")
            (txn / "payload").mkdir(); (txn / "unexpected").write_text("stale")
            with self.assertRaises(RuntimeError):
                subject.publish(output=output)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            target = output / "baseline_metrics.json"
            target.write_text("conflicting direct target")
            before = target.read_bytes()
            with self.assertRaises(RuntimeError):
                subject.publish(output=output)
            self.assertEqual(target.read_bytes(), before)

    def test_completed_normal_publication_is_mtime_preserving(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = self._paper_only_output(work)
            subject.publish(output=output)
            before = {path.relative_to(output): (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns)
                      for path in output.rglob("*") if path.is_file()}
            subject.publish(output=output)
            after = {path.relative_to(output): (hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mtime_ns)
                     for path in output.rglob("*") if path.is_file()}
            self.assertEqual(after, before)
            self.assertFalse(subject._transaction_dir(output).exists())

    def test_analysis_rejects_mismatched_time_vectors_and_wrong_final_time(self):
        good = b"0,1\n14000,2\n"
        wrong_final = b"0,1\n13999,2\n"
        mismatched = b"0,1\n1,2\n14000,3\n"
        with mock.patch.object(subject, "_literal_source_bytes", return_value={
                "baseline_P_sw.csv": good, "baseline_WT_sw.csv": mismatched, "baseline_Wc_sw.csv": good}):
            with self.assertRaises(RuntimeError):
                subject.analyze()
        with mock.patch.object(subject, "_literal_source_bytes", return_value={
                "baseline_P_sw.csv": wrong_final, "baseline_WT_sw.csv": wrong_final, "baseline_Wc_sw.csv": wrong_final}):
            with self.assertRaises(RuntimeError):
                subject.analyze()

    def test_interpolation_and_paper_parser_reject_invalid_rows(self):
        with self.assertRaises(RuntimeError):
            subject._interpolate([0.0, 1.0], [0.0, 1.0], -0.1)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            paper_rows = Path(work) / "paper.csv"
            paper_rows.write_text("panel_id,time_s,power_kW\nx,0,1\n")
            with self.assertRaises(RuntimeError):
                subject._paper_rows(paper_rows)
            paper_rows.write_text("panel_id,time_s,power_kW\na,0,nope\n")
            with self.assertRaises(RuntimeError):
                subject._paper_rows(paper_rows)
            paper_rows.write_text("panel_id,time_s,power_kW\n" + "\n".join(
                ["a,0,1", "a,0,2"] + [f"{panel},{i},1" for panel in "bcd" for i in range(15)] + [f"a,{i},1" for i in range(1, 15)]) + "\n")
            with self.assertRaises(RuntimeError):
                subject._paper_rows(paper_rows)
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
        expected_contract = subject.analyze()[1]
        if (OUT / "initialization_audit.json").is_file():
            expected_contract = subject.contract_from_initialization(
                json.loads((OUT / "initialization_audit.json").read_text()))
        self.assertEqual(contract, expected_contract)
        with (OUT / "manifest.csv").open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        expected_paths = set(digitizer.ARTIFACT_NAMES) | {
            "model_baseline/baseline.mat", "model_baseline/baseline_P_sw.csv",
            "model_baseline/baseline_WT_sw.csv", "model_baseline/baseline_Wc_sw.csv",
            "baseline_metrics.json", "signal_contract.json"}
        if (OUT / "initialization_audit.json").is_file():
            expected_paths.add("initialization_audit.json")
            expected_paths.add("@external/raw_reference.mat")
        counterfactual = OUT / "reactor_ic_counterfactual.json"
        if counterfactual.is_file():
            expected_paths.add("reactor_ic_counterfactual.json")
            summary = json.loads(counterfactual.read_text())
            locator_names = {
                "candidate_slx": "@external/reactor_ic_candidate.slx",
                "patch_audit": "@external/reactor_ic_patch_audit.json",
                "raw_result": "@external/reactor_ic_raw_result.mat",
                "run_status": "@external/reactor_ic_run_status.json",
                "candidate_curves": "@external/reactor_ic_candidate_curves.csv",
                "reference_curves": "@external/reactor_ic_reference_curves.csv",
                "invocation_failure_status": "@external/reactor_ic_invocation_failure.json",
                "analysis": "@external/reactor_ic_analysis.json",
            }
            expected_paths.update(locator_names[item["identity"]]
                                  for item in summary["external_artifacts"])
        self.assertEqual({row["path"] for row in rows}, expected_paths)
        self.assertEqual(len(rows), len(expected_paths))

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
        original_manifest = (OUT / "manifest.csv").read_bytes()
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
            with self.assertRaises(RuntimeError):
                subject.publish()
        finally:
            target.write_bytes(original)
            (OUT / "manifest.csv").write_bytes(original_manifest)
        subject.verify_only()


if __name__ == "__main__":
    unittest.main(verbosity=2)
