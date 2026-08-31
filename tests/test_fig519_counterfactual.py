"""Task 7 contracts for the Figure 5.19 reactor-IC counterfactual.

The Python suite never runs the counterfactual simulation.  A single MATLAB
test may create an API-edited candidate below an owned temporary directory;
the blocking runner is checked structurally and is reserved for the one
approved experiment.
"""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import analyze_fig519_counterfactual as subject


ROOT = Path(__file__).resolve().parents[1]
DURABLE = ROOT / "data/provenance/steady53/fig5_19"
MATLAB = Path("/Applications/MATLAB_R2025a.app/bin/matlab")
MATLAB_COLD_START_TIMEOUT_S = 300


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Figure519CounterfactualTests(unittest.TestCase):
    def _write_curves(self, path: Path, rows: list[tuple[float, float, float, float]]) -> None:
        with path.open("x", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("time_s", "reactor_W", "turbine_W", "compressor_W"))
            writer.writerows(rows)

    def _synthetic_run(self, parent: Path, *, success: bool = True) -> Path:
        run_dir = parent / "experiment"
        run = run_dir / "run"
        run.mkdir(parents=True)
        paper = subject._paper_points(DURABLE / "paper_points.csv")
        times = [point[0] for point in paper["a"]]
        candidate = []
        reference = []
        for index, time_s in enumerate(times):
            reactor = paper["a"][index][1] * 1000.0
            turbine = paper["b"][index][1] * 1000.0
            compressor = paper["c"][index][1] * 1000.0
            candidate.append((time_s, reactor, turbine, compressor))
            reference.append((time_s, 2660960.9141046703, 2212300.0, 1211000.0))
        self._write_curves(run / "candidate_curves.csv", candidate)
        self._write_curves(run / "reference_curves.csv", reference)
        (run_dir / "candidate.slx").write_bytes(b"synthetic-candidate")
        (run / "raw_result.mat").write_bytes(b"synthetic-raw")
        audit = subject.synthetic_patch_audit(
            candidate_path=run_dir / "candidate.slx",
            candidate_sha256=_sha(run_dir / "candidate.slx"),
        )
        (run_dir / "patch_audit.json").write_text(
            json.dumps(audit, indent=2, sort_keys=True) + "\n")
        status = subject.synthetic_run_status(
            run_dir,
            success=success,
            candidate_curves=run / "candidate_curves.csv",
            reference_curves=run / "reference_curves.csv",
            raw_result=run / "raw_result.mat",
        )
        (run / "run_status.json").write_text(
            json.dumps(status, indent=2, sort_keys=True) + "\n")
        if not success:
            (run / "candidate_curves.csv").unlink()
        return run_dir

    def test_candidate_contract_is_exactly_one_change_and_never_promotes(self):
        audit = subject.synthetic_patch_audit(
            candidate_path=ROOT / "tmp/placeholder/candidate.slx",
            candidate_sha256="1" * 64,
        )
        subject.validate_patch_audit(audit, require_files=False)
        self.assertEqual(audit["changed_blocks"], ["reactor/Integrator6"])
        self.assertEqual(audit["changed_parameters"], ["InitialCondition"])
        self.assertEqual(
            audit["source_sha256"],
            "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        )
        self.assertEqual(
            audit["candidate_value_identity"],
            "figure_5_19_digitized_t10_proxy_not_author_t0",
        )
        self.assertEqual(audit["candidate_value_W"], 3186507.937)
        self.assertEqual(audit["state_count"], 40)
        self.assertEqual(sum(not row["unchanged"] for row in audit["state_initial_conditions"]), 1)
        self.assertTrue(audit["solver_contract"]["unchanged"])
        self.assertTrue(audit["semantic_snapshot"]["unchanged"])
        self.assertEqual(len(audit["runtime_dependencies"]), 9)
        self.assertEqual(len(audit["protected_files"]), 34)
        self.assertFalse(audit["paper_reproduced"])
        self.assertFalse(audit["author_initial_state_identified"])
        self.assertFalse(audit["formal_promotion"])

    def test_validator_rejects_each_identity_or_exact_one_change_violation(self):
        valid = subject.synthetic_patch_audit(
            candidate_path=ROOT / "tmp/placeholder/candidate.slx",
            candidate_sha256="1" * 64,
        )
        mutations = {
            "second state": lambda a: a["state_initial_conditions"][0].update(unchanged=False),
            "solver": lambda a: a["solver_contract"].update(unchanged=False),
            "runtime": lambda a: a["runtime_dependencies"][0].update(after_sha256="2" * 64),
            "MAT": lambda a: a["mat_files"][0].update(after_sha256="2" * 64),
            "property": lambda a: a["property_files"][0].update(after_sha256="2" * 64),
            "protected": lambda a: a["protected_files"][0].update(after_sha256="2" * 64),
            "topology": lambda a: a["semantic_snapshot"].update(unchanged=False),
            "identity": lambda a: a.update(candidate_value_identity="author_t0"),
            "promotion": lambda a: a.update(formal_promotion=True),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                damaged = json.loads(json.dumps(valid))
                mutate(damaged)
                with self.assertRaises(RuntimeError):
                    subject.validate_patch_audit(damaged, require_files=False)

    def test_direction_rule_is_predeclared_and_mechanical_for_all_panels(self):
        paper = subject._paper_points(DURABLE / "paper_points.csv")
        expected = {"a": ["fall"], "b": ["rise"],
                    "c": ["fall", "rise"], "d": ["rise", "fall"]}
        self.assertEqual(subject.DIRECTION_RULE["threshold"], "panel_power_allowance_kW")
        self.assertEqual(subject.DIRECTION_RULE["flat_handling"], "discard_before_compression")
        self.assertEqual(
            {panel: subject.direction_sequence(points) for panel, points in paper.items()},
            expected,
        )
        rise_flat_rise = [(0.0, 0.0, 1.0), (1.0, 2.0, 1.0),
                          (2.0, 2.5, 1.0), (3.0, 4.0, 1.0)]
        self.assertEqual(subject.direction_sequence(rise_flat_rise), ["rise"])

    def test_analyzer_declares_five_curves_and_uses_fixed_noise_gate(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            run_dir = self._synthetic_run(Path(work))
            result = subject.analyze(run_dir)
            self.assertEqual(
                set(result["curves"]),
                {"reactor", "turbine", "compressor", "electrical_paper_eta",
                 "electrical_historical_metric"},
            )
            self.assertEqual(result["nonflat_rule"]["ratio"], 10.0)
            self.assertTrue(result["direction_gate"]["all_four_panels_match"])
            self.assertEqual(
                result["conclusion"],
                "reactor_ic_alone_not_falsified_but_not_validated",
            )
            for curve in result["curves"].values():
                self.assertIn("paper_comparison", curve)
                self.assertIn("reference_change", curve)
                self.assertIn("peak_time_s", curve["candidate_metrics"])
                self.assertIn("valley_time_s", curve["candidate_metrics"])
            self.assertFalse(result["paper_reproduced"])
            self.assertFalse(result["author_initial_state_identified"])
            self.assertFalse(result["formal_promotion"])

    def test_gate_failure_and_falsification_enums_are_mechanical(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            failed = self._synthetic_run(parent / "failed", success=False)
            self.assertEqual(subject.analyze(failed)["conclusion"],
                             "numerical_or_physical_gate_failed")
            flat = self._synthetic_run(parent / "flat")
            curves = flat / "run/candidate_curves.csv"
            with curves.open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            with curves.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=rows[0], lineterminator="\n")
                writer.writeheader()
                for row in rows:
                    row.update(reactor_W="2660960.9141046703",
                               turbine_W="2212300", compressor_W="1211000")
                    writer.writerow(row)
            status_path = flat / "run/run_status.json"
            status = json.loads(status_path.read_text())
            status["artifacts"] = subject._artifact_locators(
                flat,
                candidate_curves=curves,
                reference_curves=flat / "run/reference_curves.csv",
                raw_result=flat / "run/raw_result.mat",
                include_analysis=False,
                include_run_status=False,
            )
            status_path.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")
            self.assertEqual(subject.analyze(flat)["conclusion"],
                             "reactor_ic_alone_falsified")

    def test_incomplete_output_status_keeps_its_written_candidate_curves(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            run_dir = self._synthetic_run(Path(work))
            status_path = run_dir / "run/run_status.json"
            status = json.loads(status_path.read_text())
            status["experiment_status"] = "completed_incomplete_output"
            status["candidate_final_time_s"] = 499.0
            status_path.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")
            result = subject.analyze(run_dir)
            self.assertEqual(result["conclusion"],
                             "numerical_or_physical_gate_failed")
            self.assertEqual(result["gate_failure_class"],
                             "completed_incomplete_output")

    def test_completed_model_failure_publishes_without_candidate_curve_locator(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            run_dir = self._synthetic_run(parent / "inputs", success=False)
            self.assertFalse((run_dir / "run/candidate_curves.csv").exists())
            output = parent / "fig5_19"
            shutil.copytree(DURABLE, output)
            summary_path = output / "reactor_ic_counterfactual.json"
            if summary_path.exists():
                summary_path.unlink()
            subject.rebuild_task6_manifest(output)
            subject.publish(run_dir, output)
            subject.verify_only(run_dir, output)
            summary = json.loads(summary_path.read_text())
            identities = {item["identity"] for item in summary["external_artifacts"]}
            self.assertNotIn("candidate_curves", identities)
            self.assertEqual(summary["analysis"]["conclusion"],
                             "numerical_or_physical_gate_failed")

    def test_runner_source_contains_exactly_one_blocking_call_and_no_retry(self):
        source = (ROOT / "tests/run_fig519_reactor_ic_counterfactual.m").read_text()
        executable = [line for line in source.splitlines()
                      if "run_steady53_case(" in line and not line.lstrip().startswith("%")]
        self.assertEqual(len(executable), 1)
        top_level = source[:source.index("function runDir = validateExistingRunDirectory")]
        self.assertNotIn("while ", top_level)
        self.assertNotIn("for attempt", top_level)
        self.assertIn("run_steady53_case(candidatePath, 500, true)", source)
        self.assertIn("java.nio.file.Files.createDirectory", source)
        self.assertIn("java.nio.file.Files.createFile", source)
        self.assertNotIn("mkdir(runPath)", source)

    def test_success_status_binds_all_identity_groups_and_exact_artifact_set(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            run_dir = self._synthetic_run(Path(work))
            audit = json.loads((run_dir / "patch_audit.json").read_text())
            status_path = run_dir / "run/run_status.json"
            valid = json.loads(status_path.read_text())
            subject._validate_run_status(valid, run_dir, audit)
            mutations = {
                "runtime missing": lambda s: s["identity_before"].update(
                    runtime_dependencies=s["identity_before"]["runtime_dependencies"][:-1]),
                "MAT changed": lambda s: s["identity_before"]["mat_files"][0].update(
                    sha256="0" * 64),
                "property missing": lambda s: s["identity_before"].update(property_files=[]),
                "protected missing": lambda s: s["identity_before"].update(
                    protected_files=s["identity_before"]["protected_files"][:-1]),
                "extra artifact": lambda s: s["artifacts"].append(
                    {**s["artifacts"][0], "identity": "invented_extra"}),
            }
            for label, mutate in mutations.items():
                with self.subTest(label=label):
                    damaged = json.loads(json.dumps(valid))
                    mutate(damaged)
                    damaged["identity_after"] = json.loads(
                        json.dumps(damaged["identity_before"]))
                    with self.assertRaises(RuntimeError):
                        subject._validate_run_status(damaged, run_dir, audit)

    def test_pre_simulation_failure_is_analyzed_without_fake_curves_or_raw(self):
        run_dir = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
        failure = run_dir / "run/invocation_failure.json"
        self.assertTrue(failure.is_file(), "the consumed one-shot attempt must be frozen")
        evidence = json.loads(failure.read_text())
        self.assertEqual(evidence["attempted_runner_sha256"],
                         subject.ATTEMPTED_RUNNER_SHA256)
        self.assertEqual(evidence["formal_command_invocation_count"], 1)
        self.assertEqual(evidence["run_steady53_case_call_count"], 0)
        self.assertEqual(evidence["retry_count"], 0)
        self.assertEqual(evidence["process_exit_code"], 1)
        result = subject.analyze(run_dir)
        self.assertEqual(result["conclusion"], "numerical_or_physical_gate_failed")
        self.assertEqual(result["gate_failure_class"],
                         "pre_simulation_infrastructure")
        self.assertFalse(result["falsification_question_answered"])
        self.assertEqual(result["curves"], {})
        self.assertEqual(result["direction_gate"]["panels"], {})
        self.assertEqual(result["nonflat_gate"]["signals"], {})
        self.assertEqual(result["attempted_runner_sha256"],
                         subject.ATTEMPTED_RUNNER_SHA256)
        self.assertNotEqual(result["post_fix_runner_sha256"],
                            subject.ATTEMPTED_RUNNER_SHA256)
        self.assertFalse(result["post_fix_runner_executed_in_formal_attempt"])
        self.assertFalse(result["paper_reproduced"])
        self.assertFalse(result["author_initial_state_identified"])
        self.assertFalse(result["formal_promotion"])
        for forbidden in ("raw_result.mat", "candidate_curves.csv",
                          "reference_curves.csv", "run_status.json"):
            self.assertFalse((run_dir / "run" / forbidden).exists())

    def test_pre_simulation_failure_publication_has_only_truthful_external_locators(self):
        run_dir = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = Path(work) / "fig5_19"
            shutil.copytree(DURABLE, output)
            summary_path = output / "reactor_ic_counterfactual.json"
            if summary_path.exists():
                summary_path.unlink()
            subject.rebuild_task6_manifest(output)
            subject.publish(run_dir, output)
            subject.verify_only(run_dir, output)
            summary = json.loads(summary_path.read_text())
            self.assertEqual(summary["experiment_evidence_kind"],
                             "pre_simulation_failure_stub_not_raw_output")
            identities = {item["identity"] for item in summary["external_artifacts"]}
            self.assertEqual(identities,
                             {"candidate_slx", "patch_audit",
                              "invocation_failure_status", "analysis"})
            with (output / "manifest.csv").open(newline="") as handle:
                rows = {row["path"]: row for row in csv.DictReader(handle)}
            self.assertTrue(set(subject.FAILURE_EXTERNAL_ARTIFACT_KEYS).issubset(rows))
            self.assertTrue(set(subject.SUCCESS_EXTERNAL_ARTIFACT_KEYS[2:6]).isdisjoint(rows))
            for locator in subject.FAILURE_EXTERNAL_ARTIFACT_KEYS:
                self.assertEqual(rows[locator]["storage"], "external_tmp_not_copied")

    @unittest.skipUnless(MATLAB.is_file(), "MATLAB R2025a is required")
    def test_runner_exclusive_file_helper_works_in_r2025a_without_simulation(self):
        source = (ROOT / "tests/run_fig519_reactor_ic_counterfactual.m").read_text()
        self.assertNotIn('fopen(filePath, "x"', source)
        completed = subprocess.run(
            [str(MATLAB), "-batch",
             "addpath('tests'); run_fig519_reactor_ic_counterfactual('__fig519_test_write_exclusive__')"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=MATLAB_COLD_START_TIMEOUT_S,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("FIG519_EXCLUSIVE_WRITE_TEST=PASS", completed.stdout)

    @unittest.skipUnless(MATLAB.is_file(), "MATLAB R2025a is required")
    def test_api_candidate_generator_in_owned_temporary_directory_without_simulation(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            run_dir = Path(work) / "candidate_case"
            command = (
                "addpath('tests','tests/steady53');"
                f"create_fig519_reactor_ic_candidate('{str(run_dir).replace(chr(39), chr(39)*2)}')"
            )
            completed = subprocess.run(
                [str(MATLAB), "-batch", command], cwd=ROOT,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                timeout=MATLAB_COLD_START_TIMEOUT_S,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            audit = json.loads((run_dir / "patch_audit.json").read_text())
            subject.validate_patch_audit(audit, run_dir=run_dir)
            self.assertEqual(_sha(ROOT / audit["source_repository_relative_path"]),
                             subject.SOURCE_SHA256)

    def test_publication_is_manifest_last_recoverable_and_verify_only_writes_nothing(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            run_dir = self._synthetic_run(parent / "inputs")
            output = parent / "fig5_19"
            shutil.copytree(DURABLE, output)
            for name in ("reactor_ic_counterfactual.json",):
                target = output / name
                if target.exists():
                    target.unlink()
            subject.rebuild_task6_manifest(output)

            def fail(point: str) -> None:
                if point == "manifest-commit-before":
                    raise OSError("injected publication interruption")

            with mock.patch.object(subject, "_publication_boundary", fail):
                with self.assertRaises(OSError):
                    subject.publish(run_dir, output)
            subject.publish(run_dir, output)
            subject.verify_only(run_dir, output)
            self.assertFalse(subject.transaction_dir(output).exists())
            before = {str(path.relative_to(output)): (path.read_bytes(), path.stat().st_mtime_ns)
                      for path in output.rglob("*") if path.is_file()}
            subject.verify_only(run_dir, output)
            self.assertEqual(before, {str(path.relative_to(output)): (path.read_bytes(), path.stat().st_mtime_ns)
                                      for path in output.rglob("*") if path.is_file()})
            with (output / "manifest.csv").open(newline="") as handle:
                rows = {row["path"]: row for row in csv.DictReader(handle)}
            self.assertIn("reactor_ic_counterfactual.json", rows)
            for locator in subject.EXTERNAL_ARTIFACT_KEYS:
                self.assertEqual(rows[locator]["storage"], "external_tmp_not_copied")

    def test_paths_symlinks_malformed_numbers_and_hash_pollution_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            run_dir = self._synthetic_run(parent / "valid")
            analysis = subject.analyze(run_dir)
            analysis["curves"]["reactor"]["candidate_metrics"]["start_W"] = float("nan")
            with self.assertRaises(RuntimeError):
                subject.validate_analysis(analysis)
            candidate = run_dir / "candidate.slx"
            candidate.write_bytes(b"polluted")
            with self.assertRaises(RuntimeError):
                subject.analyze(run_dir)
            linked = parent / "linked"
            os.symlink(run_dir, linked)
            with self.assertRaises(RuntimeError):
                subject.analyze(linked)

    def test_actual_publication_verifies_when_the_one_experiment_exists(self):
        actual = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
        summary = DURABLE / "reactor_ic_counterfactual.json"
        if not actual.exists() and not summary.exists():
            self.skipTest("approved one-shot experiment has not run yet")
        self.assertTrue(actual.is_dir() and summary.is_file())
        subject.verify_only(actual, DURABLE)

    def test_cli_accepts_the_plan_relative_run_directory_in_verify_only_mode(self):
        completed = subprocess.run(
            ["python3", "tests/analyze_fig519_counterfactual.py",
             "tmp/fig519_reactor_ic_20260831_A1", "--verify-only"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("FIG519_REACTOR_IC_COUNTERFACTUAL=numerical_or_physical_gate_failed",
                      completed.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
