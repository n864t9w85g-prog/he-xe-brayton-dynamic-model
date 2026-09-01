from __future__ import annotations

import copy
import csv
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tests import analyze_steady53_lineage_merge as analyzer


TIMES = [0.0, 250.0, 500.0]
MATCHING = {
    "reactor": [3.186e6, 2.666e6, 2.664e6],
    "turbine": [2.130e6, 2.252e6, 2.252e6],
    "compressor": [1.238e6, 1.164e6, 1.232e6],
    "electrical_paper_eta": [874_160.0, 1_066_240.0, 999_600.0],
}
PAPER = {
    name: [
        (time, value / 1000.0, 0.01)
        for time, value in zip(TIMES, values)
    ]
    for name, values in MATCHING.items()
}


class LineageMergeAnalysisTests(unittest.TestCase):
    def test_all_four_directions_support_the_hypothesis(self) -> None:
        result = analyzer.analyze_arrays(TIMES, MATCHING, PAPER)
        self.assertEqual(
            result["result_enum"], "lineage_initial_state_split_supported"
        )
        self.assertEqual(result["passed_panel_count"], 4)
        self.assertFalse(result["paper_reproduced"])
        self.assertFalse(result["author_initial_state_identified"])
        self.assertFalse(result["formal_promotion"])

    def test_partial_and_flat_results_are_not_promoted(self) -> None:
        partial = {name: [1000.0] * 3 for name in MATCHING}
        partial["reactor"] = MATCHING["reactor"]
        flat = {name: [1000.0] * 3 for name in MATCHING}
        self.assertEqual(
            analyzer.analyze_arrays(TIMES, partial, PAPER)["result_enum"],
            "lineage_initial_state_split_partially_supported",
        )
        self.assertEqual(
            analyzer.analyze_arrays(TIMES, flat, PAPER)["result_enum"],
            "lineage_initial_state_split_not_supported",
        )
        for curves in (partial, flat):
            result = analyzer.analyze_arrays(TIMES, curves, PAPER)
            self.assertFalse(result["paper_reproduced"])
            self.assertFalse(result["author_initial_state_identified"])
            self.assertFalse(result["formal_promotion"])

    def test_curve_contract_rejects_bad_time_or_nonfinite_values(self) -> None:
        with self.assertRaises(analyzer.CurveContractError):
            analyzer.analyze_arrays([0.0, 500.0, 250.0], MATCHING, PAPER)
        invalid = copy.deepcopy(MATCHING)
        invalid["reactor"][1] = float("nan")
        with self.assertRaises(analyzer.CurveContractError):
            analyzer.analyze_arrays(TIMES, invalid, PAPER)

    def test_fixed_paper_reader_rejects_changed_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "paper_points.csv"
            path.write_text("panel_id,time_s,power_kW,power_allowance_kW\n")
            with self.assertRaises(analyzer.EvidenceContractError):
                analyzer.read_fixed_paper_points(path)

    def test_run_evidence_requires_exact_counts_call_and_stop_time(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            self._write_valid_evidence(run_dir)
            result = analyzer.analyze_run(run_dir)
            self.assertEqual(
                result["result_enum"],
                "lineage_initial_state_split_supported",
            )

            audit_path = run_dir / "candidate_audit.json"
            audit = json.loads(audit_path.read_text())
            audit["assigned_state_count"] = 39
            audit_path.write_text(json.dumps(audit))
            with self.assertRaises(analyzer.EvidenceContractError):
                analyzer.analyze_run(run_dir)

            audit["assigned_state_count"] = 40
            audit_path.write_text(json.dumps(audit))
            status_path = run_dir / "run" / "run_status.json"
            status = json.loads(status_path.read_text())
            status["run_steady53_case_call_count"] = 2
            status_path.write_text(json.dumps(status))
            with self.assertRaises(analyzer.EvidenceContractError):
                analyzer.analyze_run(run_dir)

            status["run_steady53_case_call_count"] = 1
            status["final_time_s"] = 499.0
            status_path.write_text(json.dumps(status))
            with self.assertRaises(analyzer.EvidenceContractError):
                analyzer.analyze_run(run_dir)

    def test_failure_status_is_truthful_and_never_promoted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run_dir = Path(directory)
            self._write_valid_evidence(run_dir)
            status_path = run_dir / "run" / "run_status.json"
            status = json.loads(status_path.read_text())
            status.update(
                experiment_status="completed_model_failure",
                final_time_s=None,
                curves_present=False,
                error_id="steady53:ExampleFailure",
                error_report="controlled failure",
            )
            status_path.write_text(json.dumps(status))
            (run_dir / "run" / "curves.csv").unlink()
            result = analyzer.analyze_run(run_dir)
            self.assertEqual(result["result_enum"], "numerical_or_contract_failure")
            self.assertFalse(result["paper_reproduced"])
            self.assertFalse(result["formal_promotion"])

    def _write_valid_evidence(self, run_dir: Path) -> None:
        candidate = run_dir / "candidate.slx"
        candidate.write_bytes(b"synthetic-candidate")
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        audit = {
            "schema": "steady53_lineage_merge_candidate_v1",
            "root_model_sha256": analyzer.ROOT_MODEL_SHA256,
            "frozen_model_sha256": analyzer.FROZEN_MODEL_SHA256,
            "candidate_model_sha256": digest,
            "state_count": 40,
            "assigned_state_count": 40,
            "changed_state_count": 39,
            "unchanged_state_count": 1,
            "block_inventory_unchanged": True,
            "topology_unchanged": True,
            "non_ic_dialog_parameters_unchanged": True,
            "solver_parameters_unchanged": True,
            "simulation_call_count": 0,
            "paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False,
            "state_assignments": [
                {
                    "relative_path": (
                        "TAC/rotor/N_rpm_Integrator"
                        if index == 39
                        else f"synthetic/state_{index:02d}"
                    ),
                    "value_changed": index != 39,
                    "candidate_matches_root": True,
                }
                for index in range(40)
            ],
        }
        (run_dir / "candidate_audit.json").write_text(json.dumps(audit))
        run = run_dir / "run"
        run.mkdir()
        (run / "raw_result.mat").write_bytes(b"synthetic-raw")
        curves = run / "curves.csv"
        with curves.open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(analyzer.CURVE_COLUMNS)
            for index, time in enumerate(TIMES):
                writer.writerow(
                    [
                        time,
                        MATCHING["reactor"][index],
                        MATCHING["turbine"][index],
                        MATCHING["compressor"][index],
                        MATCHING["electrical_paper_eta"][index],
                        0.96527
                        * (
                            MATCHING["turbine"][index]
                            - MATCHING["compressor"][index]
                        ),
                    ]
                )
        status = {
            "schema": "steady53_lineage_merge_run_status_v1",
            "experiment_status": "completed_success",
            "run_steady53_case_call_count": 1,
            "retry_count": 0,
            "requested_stop_time_s": 500,
            "final_time_s": 500,
            "raw_result_present": True,
            "curves_present": True,
            "candidate_model_sha256_before": digest,
            "candidate_model_sha256_after": digest,
            "error_id": "",
            "error_report": "",
            "paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False,
        }
        (run / "run_status.json").write_text(json.dumps(status))


if __name__ == "__main__":
    unittest.main()
