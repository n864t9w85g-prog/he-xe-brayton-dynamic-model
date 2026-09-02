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
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import analyze_fig519_counterfactual as subject
from tests import prepare_fig519_reactor_ic_a2 as a2_capture


ROOT = Path(__file__).resolve().parents[1]
DURABLE = ROOT / "data/provenance/steady53/fig5_19"
MATLAB = Path("/Applications/MATLAB_R2025a.app/bin/matlab")
MATLAB_COLD_START_TIMEOUT_S = 300
A1 = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
A2 = ROOT / "tmp/fig519_reactor_ic_20260901_A2"
CAPTURE = ROOT / "tmp/fig519_reactor_ic_20260901_A2_command_capture"


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
            [sys.executable, "tests/analyze_fig519_counterfactual.py",
             "tmp/fig519_reactor_ic_20260831_A1", "--verify-only"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("FIG519_REACTOR_IC_COUNTERFACTUAL=numerical_or_physical_gate_failed",
                      completed.stdout)

    def test_a2_publication_appends_attempt_without_overwriting_a1(self):
        self.assertTrue(A1.is_dir() and A2.is_dir() and CAPTURE.is_dir())
        a2_capture.verify_execution(CAPTURE, A2)
        a1_before = {path.relative_to(A1).as_posix():
                     (_sha(path), path.stat().st_mtime_ns)
                     for path in A1.rglob("*") if path.is_file()}
        published = json.loads((DURABLE / subject.SUMMARY_NAME).read_text())
        original_summary = (published["attempts"][0]["attempt_summary"]
                            if published.get("summary_schema") ==
                            "steady53_fig519_reactor_ic_counterfactual_history_v2"
                            else published)
        original_summary_bytes = subject._json_bytes(original_summary)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = Path(work) / "fig5_19"
            shutil.copytree(DURABLE, output)
            (output / subject.SUMMARY_NAME).write_bytes(original_summary_bytes)
            (output / "manifest.csv").write_bytes(subject._manifest_bytes(
                output, original_summary_bytes, original_summary))
            subject.publish(A2, output, execution_capture=CAPTURE)
            subject.verify_only(A2, output, execution_capture=CAPTURE)
            subject.verify_only(A1, output, execution_capture=CAPTURE)
            summary = json.loads((output / subject.SUMMARY_NAME).read_text())
            self.assertEqual(
                summary["summary_schema"],
                "steady53_fig519_reactor_ic_counterfactual_history_v2",
            )
            self.assertEqual(summary["attempt_count"], 2)
            self.assertEqual([item["attempt_id"] for item in summary["attempts"]],
                             ["20260831_A1", "20260901_A2"])
            self.assertEqual(summary["attempts"][0]["attempt_summary"], original_summary)
            self.assertEqual(summary["attempts"][0]["source_summary_sha256"],
                             hashlib.sha256(original_summary_bytes).hexdigest())
            a2_attempt = summary["attempts"][1]
            self.assertEqual(a2_attempt["attempt_summary"]["analysis"]["conclusion"],
                             "reactor_ic_alone_falsified")
            a2_analysis = a2_attempt["attempt_summary"]["analysis"]
            self.assertEqual(a2_attempt["execution_record"]["formal_process_exit_code"], 0)
            self.assertEqual(a2_attempt["execution_record"]["formal_command_invocation_count"], 1)
            self.assertEqual(a2_attempt["execution_record"]["run_steady53_case_call_count"], 1)
            self.assertEqual(a2_attempt["execution_record"]["retry_count"], 0)
            executed_runner = a2_attempt["execution_record"]["attempted_runner_sha256"]
            self.assertEqual(a2_analysis["attempted_runner_sha256"], executed_runner)
            self.assertEqual(a2_analysis["post_fix_runner_sha256"], executed_runner)
            self.assertTrue(a2_analysis["post_fix_runner_executed_in_formal_attempt"])
            post_hoc = a2_attempt["runtime_helper_post_hoc_evidence"]
            self.assertEqual(post_hoc["evidence_class"], "post_hoc_git_inference")
            self.assertFalse(post_hoc["contemporaneously_captured_before_execution"])
            self.assertFalse(post_hoc["additional_uncaptured_command_dependency"]
                             ["commit_tree_identity_continuity_claimed"])
            self.assertEqual(summary["latest_attempt_id"], "20260901_A2")
            self.assertEqual(summary["latest_scientific_conclusion"],
                             "reactor_ic_alone_falsified")
            self.assertFalse(summary["paper_reproduced"])
            self.assertFalse(summary["author_initial_state_identified"])
            self.assertFalse(summary["formal_promotion"])
            damaged = json.loads(json.dumps(summary))
            damaged["attempts"][1]["attempt_summary"]["analysis"][
                "attempted_runner_sha256"] = None
            with self.assertRaises(RuntimeError):
                subject.validate_durable_summary(
                    damaged, run_dir=A2, execution_capture=CAPTURE)
            damaged = json.loads(json.dumps(summary))
            damaged["attempts"][1]["runtime_helper_post_hoc_evidence"][
                "evidence_class"] = "contemporaneous_capture"
            with self.assertRaises(RuntimeError):
                subject.validate_durable_summary(
                    damaged, run_dir=A2, execution_capture=CAPTURE)
            with (output / "manifest.csv").open(newline="") as handle:
                rows = {row["path"]: row for row in csv.DictReader(handle)}
            expected = {
                "@external/reactor_ic_a1_candidate.slx",
                "@external/reactor_ic_a1_patch_audit.json",
                "@external/reactor_ic_a1_invocation_failure.json",
                "@external/reactor_ic_a1_analysis.json",
                "@external/reactor_ic_a2_candidate.slx",
                "@external/reactor_ic_a2_patch_audit.json",
                "@external/reactor_ic_a2_raw_result.mat",
                "@external/reactor_ic_a2_run_status.json",
                "@external/reactor_ic_a2_candidate_curves.csv",
                "@external/reactor_ic_a2_reference_curves.csv",
                "@external/reactor_ic_a2_analysis.json",
                "@external/reactor_ic_a2_execution_record.json",
                "@external/reactor_ic_a2_stdout.log",
                "@external/reactor_ic_a2_stderr.log",
            }
            self.assertTrue(expected.issubset(rows))
            self.assertTrue(all(rows[name]["storage"] == "external_tmp_not_copied"
                                for name in expected))
            before_verify = {path.relative_to(output).as_posix():
                             (path.read_bytes(), path.stat().st_mtime_ns)
                             for path in output.rglob("*") if path.is_file()}
            subject.verify_only(A2, output, execution_capture=CAPTURE)
            self.assertEqual(before_verify,
                             {path.relative_to(output).as_posix():
                              (path.read_bytes(), path.stat().st_mtime_ns)
                              for path in output.rglob("*") if path.is_file()})
        self.assertEqual(a1_before,
                         {path.relative_to(A1).as_posix():
                          (_sha(path), path.stat().st_mtime_ns)
                          for path in A1.rglob("*") if path.is_file()})

    def test_a2_append_recovers_after_summary_commit_before_manifest(self):
        published = json.loads((DURABLE / subject.SUMMARY_NAME).read_text())
        a1_summary = published["attempts"][0]["attempt_summary"]
        a1_payload = subject._json_bytes(a1_summary)
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            output = Path(work) / "fig5_19"
            shutil.copytree(DURABLE, output)
            (output / subject.SUMMARY_NAME).write_bytes(a1_payload)
            predecessor_manifest = subject._manifest_bytes(
                output, a1_payload, a1_summary)
            (output / "manifest.csv").write_bytes(predecessor_manifest)

            def interrupt(point: str) -> None:
                if point == "manifest-commit-before":
                    raise OSError("injected A2 append interruption")

            with mock.patch.object(subject, "_publication_boundary", interrupt):
                with self.assertRaises(OSError):
                    subject.publish(A2, output, execution_capture=CAPTURE)
            interrupted = json.loads((output / subject.SUMMARY_NAME).read_text())
            self.assertEqual(interrupted["summary_schema"],
                             "steady53_fig519_reactor_ic_counterfactual_history_v2")
            self.assertEqual((output / "manifest.csv").read_bytes(), predecessor_manifest)
            self.assertTrue(subject.transaction_dir(output).is_dir())

            subject.publish(A2, output, execution_capture=CAPTURE)
            subject.verify_only(A2, output, execution_capture=CAPTURE)
            self.assertFalse(subject.transaction_dir(output).exists())

    def test_a2_completed_analysis_binds_the_executed_fixed_runner(self):
        execution = a2_capture.verify_execution(CAPTURE, A2)
        a2_analysis = subject.analyze(A2)
        runner_sha = execution["attempted_runner_sha256"]
        self.assertEqual(runner_sha,
                         "5183aa8e0add0ecc409e420ba88723639f5f53c37d42cc8a8288f0c9e186eece")
        self.assertEqual(a2_analysis["attempted_runner_sha256"], runner_sha)
        self.assertEqual(a2_analysis["post_fix_runner_sha256"], runner_sha)
        self.assertTrue(a2_analysis["post_fix_runner_executed_in_formal_attempt"])
        self.assertEqual(a2_analysis["run_steady53_case_call_count"], 1)
        self.assertEqual(a2_analysis["retry_count"], 0)

        a1_analysis = subject.analyze(A1)
        self.assertEqual(a1_analysis["attempted_runner_sha256"],
                         subject.ATTEMPTED_RUNNER_SHA256)
        self.assertNotEqual(a1_analysis["post_fix_runner_sha256"],
                            subject.ATTEMPTED_RUNNER_SHA256)
        self.assertFalse(a1_analysis["post_fix_runner_executed_in_formal_attempt"])

    def test_a2_runtime_helpers_are_explicit_post_hoc_git_inference(self):
        evidence = subject.a2_runtime_helper_post_hoc_evidence()
        self.assertEqual(evidence["evidence_class"], "post_hoc_git_inference")
        self.assertFalse(evidence["contemporaneously_captured_before_execution"])
        self.assertEqual(
            evidence["limitation"],
            "cannot exclude execution-time uncommitted modifications that were later reverted",
        )
        self.assertEqual(
            evidence["additional_uncaptured_command_dependency"][
                "repository_relative_path"],
            "tests/prepare_fig519_reactor_ic_a2.py",
        )
        self.assertFalse(
            evidence["additional_uncaptured_command_dependency"][
                "commit_tree_identity_continuity_claimed"])
        expected = {
            "tests/steady53/run_steady53_case.m": (
                "686749ffe329f71ed884e0f98d2681d6c35aa5df258ff6675917a55c20b9da42",
                "e813320a30178e2ea5b9708f0526a0f993516df2",
                "0b93df3541d91a7fbd5dcf719220653d56047c4d",
            ),
            "tests/steady53/steady53_signal_manifest.m": (
                "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd",
                "e813320a30178e2ea5b9708f0526a0f993516df2",
                "9f881fe4e4316e0f198d70188f37d625aeb07861",
            ),
            "tests/steady53/reset_steady53_property_warning_state.m": (
                "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0",
                "e813320a30178e2ea5b9708f0526a0f993516df2",
                "9f881fe4e4316e0f198d70188f37d625aeb07861",
            ),
        }
        self.assertEqual(set(evidence["files"]), set(expected))
        for path, (digest, first_commit, last_commit) in expected.items():
            item = evidence["files"][path]
            self.assertEqual(item["current_sha256"], digest)
            self.assertEqual(item["first_relevant_git_commit"], first_commit)
            self.assertEqual(item["last_relevant_git_commit"], last_commit)
            self.assertEqual(
                {row["commit"]: row["sha256"] for row in item["specified_commit_trees"]},
                {
                    "bf66dc6d68c4ddc6ffe44801e1a526e541ff845a": digest,
                    "abcb12530509223c753d6b5055e2eb65f45d58d7": digest,
                    "d2f1abc1bd218dc12a1c78c8d2bc686bd06d86c9": digest,
                },
            )
            self.assertTrue(item["all_specified_commits_and_current_identical"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
