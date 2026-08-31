"""Zero-simulation preflight contracts for the approved Figure 5.19 A2 attempt."""
from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path

from tests import prepare_fig519_reactor_ic_a2 as subject


ROOT = Path(__file__).resolve().parents[1]
A1 = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
A2 = ROOT / "tmp/fig519_reactor_ic_20260901_A2"


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Figure519A2PreflightTests(unittest.TestCase):
    def test_exact_command_and_snapshots_are_frozen_without_creating_a2(self):
        self.assertFalse(os.path.lexists(A2))
        before = {str(path.relative_to(A1)): (_sha(path), path.stat().st_mtime_ns)
                  for path in A1.rglob("*") if path.is_file()}
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            capture = Path(work) / "capture"
            subject.prepare(capture)
            subject.verify_only(capture)
            self.assertFalse(os.path.lexists(A2))
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
            capture = parent / "capture"
            subject.prepare(capture)
            before = {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                      for path in capture.iterdir()}
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
            with self.assertRaises(RuntimeError):
                subject.prepare(linked / "capture")

        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            capture = Path(work) / "capture"
            subject.prepare(capture)
            (capture / "attempted_runner.m").unlink()
            os.symlink(subject.RUNNER, capture / "attempted_runner.m")
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
