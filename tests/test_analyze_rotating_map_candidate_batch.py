import csv
import json
import tempfile
import unittest
from pathlib import Path

from tests import analyze_rotating_map_candidate_batch as subject


class RotatingMapGateTests(unittest.TestCase):
    def _write_case(self, root, case_id, values, *, final=500.0,
                    success=True, lookup_clear=True):
        case_dir = root / "runs" / case_id / "500s"
        case_dir.mkdir(parents=True)
        status = {
            "case_id": case_id,
            "requested_stop_time_s": 500.0,
            "success": success,
            "final_valid_time_s": final,
            "lookup_assertion_clear": lookup_clear,
            "all_logged_values_finite": True,
            "error_id": "",
            "stop_reason": "completed" if success else "failed",
        }
        (case_dir / "run_status.json").write_text(json.dumps(status))
        with (case_dir / "signals.csv").open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=["time_s", *values])
            writer.writeheader()
            writer.writerow({"time_s": final, **values})

    def _run(self, candidates):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        targets = subject.TABLE52_TARGETS
        baseline = {name: value * 1.10 for name, value in targets.items()}
        self._write_case(root, "C0", baseline)
        for case_id, settings in candidates.items():
            values = settings.pop("values")
            self._write_case(root, case_id, values, **settings)
        return subject.analyze(root, 500.0)

    def test_selects_candidate_at_exact_twenty_percent_improvement(self):
        targets = subject.TABLE52_TARGETS
        candidate = {name: value * 1.08 for name, value in targets.items()}
        decision = self._run({"C1": {"values": candidate}})
        self.assertTrue(decision["eligible_for_14000"])
        self.assertEqual(decision["winner"], "C1")
        self.assertAlmostEqual(
            decision["cases"]["C1"]["relative_median_improvement"], 0.2)

    def test_rejects_less_than_twenty_percent_improvement(self):
        targets = subject.TABLE52_TARGETS
        candidate = {name: value * 1.081 for name, value in targets.items()}
        decision = self._run({"C1": {"values": candidate}})
        self.assertFalse(decision["eligible_for_14000"])
        self.assertIsNone(decision["winner"])

    def test_rejects_regression_of_a_formerly_passing_signal(self):
        targets = subject.TABLE52_TARGETS
        baseline = {name: value * 1.04 for name, value in targets.items()}
        candidate = {name: value for name, value in targets.items()}
        first = next(iter(candidate))
        candidate[first] = targets[first] * 1.06
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self._write_case(root, "C0", baseline)
            self._write_case(root, "C1", candidate)
            decision = subject.analyze(root, 500.0)
        self.assertFalse(decision["cases"]["C1"]["no_five_percent_regression"])
        self.assertFalse(decision["eligible_for_14000"])

    def test_rejects_incomplete_or_lookup_asserting_run(self):
        targets = subject.TABLE52_TARGETS
        good = {name: value for name, value in targets.items()}
        incomplete = self._run({"C1": {"values": good, "final": 499.0}})
        self.assertFalse(incomplete["eligible_for_14000"])
        lookup = self._run({
            "C1": {"values": good, "lookup_clear": False},
        })
        self.assertFalse(lookup["eligible_for_14000"])

    def test_prefers_smallest_change_then_fixed_case_order(self):
        targets = subject.TABLE52_TARGETS
        same = {name: value * 1.05 for name, value in targets.items()}
        decision = self._run({
            "C1": {"values": dict(same)},
            "C2": {"values": dict(same)},
            "C3": {"values": dict(same)},
        })
        self.assertEqual(decision["winner"], "C1")

    def test_single_map_candidate_precedes_slightly_better_joint_case(self):
        targets = subject.TABLE52_TARGETS
        c2 = {name: value * 1.05 for name, value in targets.items()}
        c3 = {name: value * 1.049 for name, value in targets.items()}
        decision = self._run({
            "C2": {"values": c2},
            "C3": {"values": c3},
        })
        self.assertEqual(decision["winner"], "C2")


if __name__ == "__main__":
    unittest.main()
