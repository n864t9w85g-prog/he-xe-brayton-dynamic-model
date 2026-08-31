import csv
import hashlib
import json
import re
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/provenance/steady53/fig5_19"
REPORT = ROOT / "docs/steady53_fig519_progress_20260831.md"
README = EVIDENCE / "README.md"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_status() -> dict:
    text = REPORT.read_text(encoding="utf-8")
    match = re.search(
        r"<!-- FIG519_STATUS_BEGIN -->\s*```json\s*(\{.*?\})\s*```\s*"
        r"<!-- FIG519_STATUS_END -->",
        text,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError("missing machine-readable Figure 5.19 status block")
    return json.loads(match.group(1))


class Figure519EndToEndContractTests(unittest.TestCase):
    def test_all_registered_artifacts_have_matching_manifest_identity(self):
        with (EVIDENCE / "manifest.csv").open(newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
        self.assertGreaterEqual(len(rows), 13)
        self.assertEqual(len(rows), len({row["path"] for row in rows}))
        for row in rows:
            if row["path"].startswith("@external/"):
                artifact = ROOT / row["repository_relative_path"]
                self.assertEqual(row["storage"], "external_tmp_not_copied")
            else:
                artifact = EVIDENCE / row["path"]
                self.assertEqual(row["storage"], "durable")
            self.assertTrue(artifact.is_file(), row["path"])
            self.assertFalse(artifact.is_symlink(), row["path"])
            self.assertEqual(int(row["bytes"]), artifact.stat().st_size, row["path"])
            self.assertEqual(row["sha256"], sha256(artifact), row["path"])

    def test_four_paper_panels_and_signal_identities_are_complete(self):
        with (EVIDENCE / "paper_points.csv").open(newline="", encoding="utf-8") as stream:
            points = list(csv.DictReader(stream))
        self.assertEqual(Counter(row["panel_id"] for row in points), {"a": 15, "b": 15, "c": 15, "d": 15})

        signals = json.loads((EVIDENCE / "signal_contract.json").read_text())["signals"]
        self.assertEqual(signals["reactor"]["api_upstream_block"], "final_steady_24a/reactor/Integrator6")
        self.assertEqual(signals["turbine"]["api_output_port"], 4)
        self.assertEqual(signals["compressor"]["api_output_port"], 2)
        self.assertEqual(signals["load"]["api_destination_input_port"], 6)
        self.assertEqual(signals["electrical_paper_eta"]["formula"], "0.98*(WT_sw-Wc_sw)")
        self.assertIsNone(signals["electrical_paper_eta"]["direct_generator_signal"])

    def test_readme_update_does_not_change_paper_science_artifact_identities(self):
        expected = {
            "source_page_106.png": "770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2",
            "paper_points.csv": "e63607ad0f599c84fe6980ed26e05c91902b7928a53fabf5bf4a95a3de0098f2",
            "provenance.json": "987ba83306775835f903b8e6d27edfa1a8f3fe55ba15cfe115ba723782f0b79e",
            "digitization_overlay.png": "90a0c2dd69c0413cc614c35670baaa47da2bf599a24d7c513bbc1815842c6cb0",
        }
        self.assertEqual({name: sha256(EVIDENCE / name) for name in expected}, expected)

    def test_baseline_initialization_and_counterfactual_summaries_are_bound(self):
        baseline = json.loads((EVIDENCE / "baseline_metrics.json").read_text())
        initialization = json.loads((EVIDENCE / "initialization_audit.json").read_text())
        counterfactual = json.loads((EVIDENCE / "reactor_ic_counterfactual.json").read_text())

        self.assertFalse(baseline["paper_reproduced"])
        self.assertEqual(initialization["state_count"], 40)
        self.assertTrue(initialization["source_hash_unchanged"])
        self.assertFalse(initialization["direct_generator_signal_found"])
        self.assertEqual(counterfactual["attempt_count"], 2)
        self.assertEqual(counterfactual["latest_scientific_conclusion"], "reactor_ic_alone_falsified")
        self.assertEqual(counterfactual["total_formal_command_invocation_count"], 2)
        self.assertEqual(counterfactual["total_run_steady53_case_call_count"], 1)
        self.assertEqual(counterfactual["total_retry_count"], 0)

        a1, a2 = counterfactual["attempts"]
        self.assertEqual(a1["attempt_id"], "20260831_A1")
        self.assertEqual(a1["attempt_summary"]["analysis"]["run_steady53_case_call_count"], 0)
        self.assertEqual(a2["attempt_id"], "20260901_A2")
        analysis = a2["attempt_summary"]["analysis"]
        self.assertEqual(analysis["conclusion"], "reactor_ic_alone_falsified")
        self.assertTrue(analysis["falsification_question_answered"])
        self.assertFalse(analysis["direction_gate"]["all_four_panels_match"])
        self.assertFalse(analysis["nonflat_gate"]["all_required_nonflat"])
        self.assertEqual(a2["execution_record"]["candidate_final_time_s"], 500)
        self.assertEqual(a2["execution_record"]["formal_command_invocation_count"], 1)
        self.assertEqual(a2["execution_record"]["run_steady53_case_call_count"], 1)
        self.assertEqual(a2["execution_record"]["retry_count"], 0)
        self.assertEqual(a2["runtime_helper_post_hoc_evidence"]["evidence_class"], "post_hoc_git_inference")

    def test_report_status_gates_are_fixed_false_and_no_forbidden_promotion(self):
        status = load_status()
        self.assertFalse(status["figure_5_18d_reproduced"])
        self.assertFalse(status["figure_5_19_reproduced"])
        self.assertFalse(status["section_5_3_reproduced"])
        self.assertFalse(status["section_5_4_reproduced"])
        self.assertFalse(status["formal_model_modified"])
        self.assertFalse(status["formal_promotion"])
        self.assertFalse(status["paper_reproduced"])
        self.assertFalse(status["author_initial_state_identified"])
        self.assertEqual(status["result_enum"], "reactor_ic_alone_falsified")
        self.assertEqual(status["next_decision_gate"], "written_specification_approval_required")

        for key in (
            "selected_best_candidate",
            "automatic_envelope_expansion",
            "time_shifted",
            "smoothed",
            "fitted_electrical_efficiency",
            "digitized_t10_claimed_as_author_t0",
        ):
            self.assertFalse(status[key], key)

    def test_report_is_evidence_ranked_and_discloses_limits(self):
        report = REPORT.read_text(encoding="utf-8")
        for marker in ("✅", "⚠️", "❓", "❌"):
            self.assertIn(marker, report)
        for required in (
            "multiple_conditionally_feasible_packages",
            "figure_5_19_digitized_t10_proxy_not_author_t0",
            "reactor_ic_alone_falsified",
            "四个 panel 的方向序列均不匹配",
            "compressor",
            "29.450068481857393",
            "34.55500454745297",
            "63.97522843651207",
            "237.6560876219371",
            "post_hoc_git_inference",
            "cannot exclude execution-time uncommitted modifications that were later reverted",
            "A1",
            "原始 batch stdout/stderr 未归档",
            "外部 `tmp/` 定位器不是耐久存储",
            "正式模型零修改",
            "书面规格批准",
        ):
            self.assertIn(required, report)

    def test_readme_points_to_report_and_records_enum_without_changing_science_layer(self):
        readme = README.read_text(encoding="utf-8")
        self.assertIn("docs/steady53_fig519_progress_20260831.md", readme)
        self.assertIn("result_enum = reactor_ic_alone_falsified", readme)
        self.assertIn("paper_reproduced = false", readme)
        self.assertIn("formal_promotion = false", readme)
        self.assertIn("t=10 s is a proxy", readme)


if __name__ == "__main__":
    unittest.main(verbosity=2)
