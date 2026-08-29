import csv
from pathlib import Path
import tempfile
import unittest

from tests import audit_radiator_candidate_family as audit
from tests import render_radiator_candidate_family as render


ROOT = Path(__file__).resolve().parents[1]


class CandidateFamilyRenderTests(unittest.TestCase):
    def test_svg_contains_16_labeled_source_branches(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            audit.write_outputs(output, audit.build_audit())
            svg = output / "mass_area_envelope.svg"
            render.render(output / "candidate_family.csv", svg)
            text = svg.read_text()
            self.assertTrue(text.startswith("<svg"))
            self.assertIn('viewBox="0 0 1200 760"', text)
            self.assertIn("Scheme-B radiator branches", text)
            self.assertIn("mass-derived area upper bound, not design area", text)
            self.assertEqual(text.count('class="branch"'), 16)
            self.assertIn("T300_fd1p45_one", text)
            self.assertIn("APG_fd1p00_two", text)
            self.assertIn("upper bound, not design area", text)

    def test_renderer_rejects_missing_or_duplicate_branches(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            path = Path(folder) / "bad.csv"
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=[
                    "candidate_id", "kappa_kg_m2",
                    "A_rad_upper_if_TAC_zero_m2",
                    "technology_evidence_grade",
                ])
                writer.writeheader()
                writer.writerow({
                    "candidate_id": "duplicate", "kappa_kg_m2": 1.0,
                    "A_rad_upper_if_TAC_zero_m2": 4650.0,
                    "technology_evidence_grade": "projected",
                })
            with self.assertRaises(ValueError):
                render.render(path, Path(folder) / "bad.svg")


if __name__ == "__main__":
    unittest.main(verbosity=2)
