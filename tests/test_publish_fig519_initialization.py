"""Transaction and contract tests for the Figure 5.19 initialization audit."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import publish_fig519_initialization as subject


ROOT = Path(__file__).resolve().parents[1]
DURABLE = ROOT / "data/provenance/steady53/fig5_19"


class Figure519InitializationPublicationTests(unittest.TestCase):
    def _task5_copy(self, parent: Path, name: str = "out") -> Path:
        output = parent / name
        shutil.copytree(DURABLE, output)
        audit = output / "initialization_audit.json"
        if audit.exists():
            audit.unlink()
        # Rebuild the exact Task 5 predecessor even when the durable fixture
        # has already advanced to the Task 6 layer.
        old_contract = subject.baseline._json_bytes(subject.baseline._contract())
        (output / "signal_contract.json").write_bytes(old_contract)
        entries = {artifact: (output / artifact).read_bytes()
                   for artifact in subject.paper.ARTIFACT_NAMES}
        entries.update({f"{subject.paper.BASELINE_LAYER_DIR}/{artifact}":
                        (output / subject.paper.BASELINE_LAYER_DIR / artifact).read_bytes()
                        for artifact in subject.paper.BASELINE_LAYER_NAMES})
        entries["baseline_metrics.json"] = (output / "baseline_metrics.json").read_bytes()
        entries["signal_contract.json"] = old_contract
        (output / "manifest.csv").write_bytes(
            subject.paper.manifest_bytes(entries, subject.baseline._roles()))
        return output

    def _source(self, parent: Path) -> Path:
        run = parent / "run"
        run.mkdir()
        raw = ROOT / "tmp/fig519_initialization_20260831_A1/raw_reference.mat"
        self.assertTrue(raw.is_file())
        audit = {
            "audit_schema": "steady53_fig519_initialization_v1",
            "model_sha256": "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
            "source_hash_after": "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
            "source_hash_unchanged": True,
            "state_count": 40,
            "reference_final_time_s": 500,
            "reference_success": True,
            "reference_run_reason": "missing direct state and derivative evidence in prior saved baseline",
            "repeated_prior_experiment": False,
            "direct_generator_signal_found": False,
            "paper_reproduced": False,
            "formal_promotion": False,
            "raw_reference": {
                "repository_relative_path": str(raw.relative_to(ROOT)),
                "absolute_path": str(raw),
                "sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
                "bytes": raw.stat().st_size,
            },
            "protected_manifest": {"row_count": 34, "resolved_count": 34, "unresolved_count": 0},
            "runtime_dependency_contract": {
                "dependency_count": 9, "all_paths_durable": True,
                "dependencies": [{"is_durable": True} for _ in range(9)],
            },
            "state_inventory": ([
                {"path": "final_steady_24a/reactor/Integrator6"},
                {"path": "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"},
                {"path": "final_steady_24a/precooler/precooler_2/T_h2_out_Integrator"},
                {"path": "final_steady_24a/TAC/rotor/N_rpm_Integrator"},
            ] + [{"path": f"final_steady_24a/state/{i}"} for i in range(36)]),
            "boundary_contract": {"all_inputs_classified": True, "load_input_classified": True},
            "solver_contract": {"solver_name": "ode15s", "stop_time_dependency_checked": True},
            "power_signal_paths": {
                "reactor": {"status": "verified_by_official_api", "workspace_block": "final_steady_24a/reactor/P_sw", "upstream_block": "final_steady_24a/reactor/Integrator6", "upstream_output_port": 1},
                "turbine": {"status": "verified_by_official_api", "block": "final_steady_24a/TAC/Turbine", "output_port": 4},
                "compressor": {"status": "verified_by_official_api", "block": "final_steady_24a/TAC/Compressor", "output_port": 2},
                "load": {"status": "verified_by_official_api", "source_block": "final_steady_24a/Constant14", "destination_block": "final_steady_24a/TAC", "destination_input_port": 6, "destination_inport_block": "final_steady_24a/TAC/Pload", "value_W": 1000210.0},
                "electrical": {"status": "no_direct_generator_signal_found"},
                "direct_generator_signal_found": False,
            },
            "initial_residuals": {"all_items_accounted_for": True, "items": [
                {"name": "shaft_excess_power", "status": "computed", "value": 35934.17908170889,
                 "unit": "W", "formula": "WT(t0)-Wc(t0)-Pload",
                 "source_paths": ["final_steady_24a/TAC/Turbine", "final_steady_24a/TAC/Compressor", "final_steady_24a/Constant14", "final_steady_24a/TAC/Pload"]}
            ]},
            "flat_start_explanation": {
                "has_state_evidence": True, "has_signal_path_evidence": True,
                "near_zero_rule": {"metric": "abs(first_sample_slope)/max(abs(t0_value),1)", "threshold_per_s": 1e-6},
                "near_zero_state_derivatives": [{"path": "final_steady_24a/reactor/Integrator6"}],
                "power_state_signal_mappings": [
                    {"power_definition": name, "traced_state_paths": ["final_steady_24a/reactor/Integrator6"], "traced_signal_paths": ["verified/path"]}
                    for name in ("reactor", "turbine", "compressor", "electrical_paper_eta")
                ],
                "paper_initial_state_identified": False,
            },
        }
        source = run / "initialization_audit.json"
        source.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
        return source

    def test_publish_is_idempotent_and_updates_api_contract(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            before = {str(p.relative_to(output)): (p.read_bytes(), p.stat().st_mtime_ns)
                      for p in output.rglob("*") if p.is_file()}
            subject.publish(source, output)
            subject.verify_only(output)
            self.assertEqual(before, {str(p.relative_to(output)): (p.read_bytes(), p.stat().st_mtime_ns)
                                      for p in output.rglob("*") if p.is_file()})
            contract = json.loads((output / "signal_contract.json").read_text())
            signals = contract["signals"]
            self.assertEqual(signals["reactor"]["status"], "verified_by_official_api")
            self.assertEqual(signals["turbine"]["api_block_path"], "final_steady_24a/TAC/Turbine")
            self.assertEqual(signals["compressor"]["api_output_port"], 2)
            self.assertEqual(signals["electrical_paper_eta"]["status"], "no_direct_generator_signal_found")
            with (output / "manifest.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            indexed = {row["path"]: row for row in rows}
            self.assertIn("initialization_audit.json", indexed)
            self.assertIn("@external/raw_reference.mat", indexed)
            raw_row = indexed["@external/raw_reference.mat"]
            self.assertEqual(raw_row["storage"], "external_tmp_not_copied")
            self.assertEqual(raw_row["repository_relative_path"], "tmp/fig519_initialization_20260831_A1/raw_reference.mat")
            self.assertEqual(raw_row["absolute_path"], str(ROOT / raw_row["repository_relative_path"]))
            self.assertEqual(raw_row["sha256"], hashlib.sha256((ROOT / raw_row["repository_relative_path"]).read_bytes()).hexdigest())
            self.assertEqual(int(raw_row["bytes"]), (ROOT / raw_row["repository_relative_path"]).stat().st_size)
            for relative, row in indexed.items():
                if row.get("storage") == "external_tmp_not_copied":
                    continue
                target = output / relative
                self.assertFalse(target.is_symlink())
                self.assertEqual(row["sha256"], hashlib.sha256(target.read_bytes()).hexdigest())
                self.assertEqual(int(row["bytes"]), target.stat().st_size)

    def test_rejects_source_outside_tmp_symlinks_and_malformed_audit(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            malformed = json.loads(source.read_text())
            malformed["direct_generator_signal_found"] = True
            source.write_text(json.dumps(malformed))
            with self.assertRaises(RuntimeError):
                subject.publish(source, output)
            outside = ROOT / "tests" / ".fig519-audit-outside.json"
            outside.write_text("{}")
            try:
                with self.assertRaises(RuntimeError):
                    subject.publish(outside, output)
            finally:
                outside.unlink()

            real = parent / "real"
            real.mkdir()
            symlink = parent / "linked"
            os.symlink(real, symlink)
            with self.assertRaises(RuntimeError):
                subject.publish(symlink / "initialization_audit.json", output)

    def test_partial_commit_is_recoverable_and_manifest_is_last(self):
        for fail_at in ("audit-commit-after", "signal-contract-commit-after", "manifest-commit-before"):
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                parent = Path(work)
                output = self._task5_copy(parent)
                source = self._source(parent)
                original_manifest = (output / "manifest.csv").read_bytes()

                def fail(point: str):
                    if point == fail_at:
                        raise OSError("injected publication interruption")

                with mock.patch.object(subject, "_publication_boundary", fail):
                    with self.assertRaises(OSError):
                        subject.publish(source, output)
                if fail_at != "manifest-commit-before":
                    self.assertEqual((output / "manifest.csv").read_bytes(), original_manifest)
                subject.publish(source, output)
                subject.verify_only(output)
                self.assertFalse(subject.transaction_dir(output).exists())

    def test_verify_only_rejects_corruption_and_writes_nothing(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            (output / "initialization_audit.json").write_bytes(b"corrupt")
            before = {str(p.relative_to(output)): p.read_bytes()
                      for p in output.rglob("*") if p.is_file()}
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)
            self.assertEqual(before, {str(p.relative_to(output)): p.read_bytes()
                                      for p in output.rglob("*") if p.is_file()})

    def test_verify_only_rejects_missing_or_tampered_raw_locator(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            audit_path = output / "initialization_audit.json"
            original = audit_path.read_bytes()
            audit = json.loads(original)
            audit["raw_reference"]["sha256"] = "0" * 64
            audit_path.write_text(json.dumps(audit))
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)
            audit_path.write_bytes(original)
            audit = json.loads(original)
            audit["raw_reference"]["repository_relative_path"] = "tmp/fig519_initialization_20260831_A1/missing.mat"
            audit["raw_reference"]["absolute_path"] = str(ROOT / audit["raw_reference"]["repository_relative_path"])
            audit_path.write_text(json.dumps(audit))
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
