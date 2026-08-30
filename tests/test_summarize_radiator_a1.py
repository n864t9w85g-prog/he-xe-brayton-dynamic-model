import unittest

from tests import summarize_radiator_a1 as summary


class SummarizeRadiatorA1Tests(unittest.TestCase):
    def test_zero_pass_does_not_expand_envelope(self):
        result = summary.summarize_records([], 500)
        self.assertEqual(result["advance_candidate_ids"], [])
        self.assertFalse(result["expand_envelope"])
        self.assertFalse(result["paper_reproduced"])

    def test_multiple_passes_preserve_nonuniqueness(self):
        records = [
            {
                "candidate_id": "projected",
                "simulation_gate_pass": True,
                "technology_maturity": "projected",
                "paper_error": 0.001,
            },
            {
                "candidate_id": "tested",
                "simulation_gate_pass": True,
                "technology_maturity": "tested",
                "paper_error": 0.05,
            },
        ]
        result = summary.summarize_records(records, 14000)
        self.assertEqual(
            result["ranked_candidate_ids"], ["tested", "projected"]
        )
        self.assertEqual(
            result["identifiability"],
            "multiple_conditionally_feasible_packages",
        )
        self.assertIsNone(result["selected_best_candidate"])

    def test_failed_candidate_never_advances(self):
        records = [
            {
                "candidate_id": "pass",
                "simulation_gate_pass": True,
                "technology_maturity": "tested",
                "paper_error": 0.2,
            },
            {
                "candidate_id": "fail",
                "simulation_gate_pass": False,
                "technology_maturity": "tested",
                "paper_error": 0.0,
            },
        ]
        result = summary.summarize_records(records, 500)
        self.assertEqual(result["advance_candidate_ids"], ["pass"])

    def test_report_language_cannot_claim_reproduction(self):
        report = summary.render_report(summary.summarize_records([], 14000))
        self.assertNotIn("paper_reproduced=true", report)
        self.assertIn("未晋升正式模型", report)


if __name__ == "__main__":
    unittest.main(verbosity=2)
