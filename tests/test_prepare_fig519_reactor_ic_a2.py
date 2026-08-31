"""Zero-simulation preflight contracts for the approved Figure 5.19 A2 attempt."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import prepare_fig519_reactor_ic_a2 as subject


ROOT = Path(__file__).resolve().parents[1]
A1 = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
A2 = ROOT / "tmp/fig519_reactor_ic_20260901_A2"


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Figure519A2PreflightTests(unittest.TestCase):
    def test_exact_command_and_snapshots_are_frozen_without_creating_a2(self):
        before = {str(path.relative_to(A1)): (_sha(path), path.stat().st_mtime_ns)
                  for path in A1.rglob("*") if path.is_file()}
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            fake_a2 = Path(work) / "formal_A2_must_remain_absent"
            capture = Path(work) / "capture"
            with mock.patch.object(subject, "A2", fake_a2):
                subject.prepare(capture)
                subject.verify_only(capture)
            self.assertFalse(os.path.lexists(fake_a2))
            self.assertEqual((capture / "command.txt").read_text(),
                             subject.EXACT_COMMAND + "\n")
            self.assertTrue(subject.EXACT_COMMAND.startswith(
                "python3 tests/prepare_fig519_reactor_ic_a2.py --verify-only && "))
            self.assertEqual((capture / "attempted_runner.m").read_bytes(),
                             subject.RUNNER.read_bytes())
            self.assertEqual((capture / "candidate_generator.m").read_bytes(),
                             subject.GENERATOR.read_bytes())
            status = json.loads((capture / "preflight_status.json").read_text())
            self.assertTrue(status["static_preflight_passed"])
            self.assertFalse(status["formal_execution_performed"])
            self.assertEqual(status["simulation_call_count"], 0)
            self.assertTrue(status["a2_target_absent"])
            self.assertEqual(status["candidate_value_W"], 3186507.937)
            self.assertEqual(status["candidate_value_identity"],
                             "figure_5_19_digitized_t10_proxy_not_author_t0")
            self.assertEqual(status["runner_sha256"], _sha(subject.RUNNER))
            self.assertEqual(status["candidate_generator_sha256"],
                             _sha(subject.GENERATOR))
            self.assertEqual(status["source_sha256"], subject.SOURCE_SHA256)
            self.assertEqual(status["source_commit"], subject.SOURCE_COMMIT)
            plan = status["persistence_plan"]
            self.assertEqual(plan["preserved_attempt_ids"], ["20260831_A1"])
            self.assertEqual(plan["append_attempt_id"], "20260901_A2")
            self.assertFalse(plan["overwrite_existing_attempts"])
            self.assertTrue(plan["future_summary_requires_attempt_history"])
        after = {str(path.relative_to(A1)): (_sha(path), path.stat().st_mtime_ns)
                 for path in A1.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_verify_only_is_idempotent_and_rejects_tampering_or_symlinks(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            fake_a2 = parent / "formal_A2_must_remain_absent"
            capture = parent / "capture"
            with mock.patch.object(subject, "A2", fake_a2):
                subject.prepare(capture)
            before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                      for path in capture.iterdir()}
            with mock.patch.object(subject, "A2", fake_a2):
                subject.verify_only(capture)
            self.assertEqual(before, {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                                      for path in capture.iterdir()})
            (capture / "command.txt").write_text("tampered\n")
            with self.assertRaises(RuntimeError):
                subject.verify_only(capture)

            real = parent / "real"
            real.mkdir()
            linked = parent / "linked"
            os.symlink(real, linked)
            with mock.patch.object(subject, "A2", fake_a2):
                with self.assertRaises(RuntimeError):
                    subject.prepare(linked / "capture")

        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            fake_a2 = Path(work) / "formal_A2_must_remain_absent"
            capture = Path(work) / "capture"
            with mock.patch.object(subject, "A2", fake_a2):
                subject.prepare(capture)
            (capture / "attempted_runner.m").unlink()
            os.symlink(subject.RUNNER, capture / "attempted_runner.m")
            with mock.patch.object(subject, "A2", fake_a2):
                with self.assertRaises(RuntimeError):
                    subject.verify_only(capture)

    def test_preflight_rejects_any_existing_a2_target(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            fake_target = Path(work) / "A2"
            fake_target.mkdir()
            with self.assertRaises(RuntimeError):
                subject.validate_target_absent(fake_target)

    def test_runner_atomic_markers_and_cold_start_budget_are_not_weakened(self):
        runner = subject.RUNNER.read_text()
        self.assertNotIn('fopen(filePath, "x"', runner)
        self.assertIn("java.nio.file.Files.createDirectory", runner)
        self.assertIn("java.nio.file.Files.createFile", runner)
        test_source = (ROOT / "tests/test_fig519_counterfactual.py").read_text()
        self.assertIn("MATLAB_COLD_START_TIMEOUT_S = 300", test_source)
        self.assertGreaterEqual(test_source.count("timeout=MATLAB_COLD_START_TIMEOUT_S"), 2)
        preflight_source = (ROOT / "tests/prepare_fig519_reactor_ic_a2.py").read_text()
        self.assertNotIn('git", "rev-parse", "HEAD', preflight_source)

    def test_archive_execution_copies_raw_logs_and_records_truthful_fallback_times_once(self):
        spool = ROOT / "tmp/fig519_reactor_ic_20260901_A2_execution_spool"
        self.assertTrue(A2.is_dir(), "the approved A2 attempt must already be consumed")
        self.assertTrue(spool.is_dir(), "the raw execution spool must be preserved")
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            capture = Path(work) / "capture"
            capture.mkdir()
            for name in subject.CAPTURE_NAMES:
                shutil.copy2(subject.CAPTURE / name, capture / name)
            subject.archive_execution(capture, spool, A2)
            record = subject.verify_execution(capture, A2)
            self.assertEqual(record["formal_command_invocation_count"], 1)
            self.assertEqual(record["run_steady53_case_call_count"], 1)
            self.assertEqual(record["retry_count"], 0)
            self.assertEqual(record["formal_process_exit_code"], 0)
            self.assertEqual(record["runner_status"], "completed_success")
            self.assertEqual(record["candidate_final_time_s"], 500)
            self.assertEqual(record["timestamp_quality"],
                             "filesystem_birthtime_fallback_not_wrapper_timestamp")
            self.assertEqual(record["wrapper_timestamp_recorder_error"]["missing_program"],
                             "/usr/bin/date")
            self.assertEqual((capture / "stdout.log").read_bytes(),
                             (spool / "stdout.log").read_bytes())
            self.assertEqual((capture / "stderr.log").read_bytes(),
                             (spool / "stderr.log").read_bytes())
            self.assertEqual((capture / "formal_exit_code.txt").read_text(), "0\n")
            self.assertEqual((capture / "formal_command_invocation_count.txt").read_text(),
                             "1\n")
            self.assertEqual((capture / "retry_count.txt").read_text(), "0\n")
            before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                      for path in capture.iterdir()}
            subject.archive_execution(capture, spool, A2)
            self.assertEqual(before, {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                                      for path in capture.iterdir()})

    def test_execution_verifier_rejects_log_tampering_and_never_invokes_runner(self):
        spool = ROOT / "tmp/fig519_reactor_ic_20260901_A2_execution_spool"
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            capture = Path(work) / "capture"
            capture.mkdir()
            for name in subject.CAPTURE_NAMES:
                shutil.copy2(subject.CAPTURE / name, capture / name)
            subject.archive_execution(capture, spool, A2)
            (capture / "stdout.log").write_bytes(b"tampered")
            with self.assertRaises(RuntimeError):
                subject.verify_execution(capture, A2)
        source = (ROOT / "tests/prepare_fig519_reactor_ic_a2.py").read_text()
        archive_section = source[source.index("def archive_execution"):]
        self.assertNotIn("subprocess", archive_section)
        self.assertNotIn("run_steady53_case(", archive_section)

    def test_cli_verify_only_switches_to_consumed_attempt_verification(self):
        completed = subprocess.run(
            ["python3", "tests/prepare_fig519_reactor_ic_a2.py", "--verify-only"],
            cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("FIG519_REACTOR_IC_A2_EXECUTION=VERIFIED_NO_RERUN",
                      completed.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
