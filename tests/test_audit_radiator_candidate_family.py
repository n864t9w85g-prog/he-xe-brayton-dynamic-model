import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tests import audit_radiator_candidate_family as audit


ROOT = Path(__file__).resolve().parents[1]


class CandidateFamilyAuditTests(unittest.TestCase):
    def test_build_has_16_branches_and_keeps_statuses_separate(self):
        result = audit.build_audit()
        self.assertEqual(len(result["candidate_family"]), 16)
        self.assertEqual(result["identifiability"]["NaK_mass_flow_author"],
                         "unknown")
        self.assertEqual(result["identifiability"]["NaK_flow_6p95"],
                         "project_boundary")
        self.assertEqual(result["identifiability"]["NaK_flow_energy_closure"],
                         "conditional")
        self.assertFalse(result["paper_reproduced"])
        self.assertTrue(result["no_model_load_or_simulation"])

    def test_legacy_current_is_rejected_by_scheme_b_mass_gate(self):
        result = audit.build_audit()
        legacy = result["legacy_current"]
        self.assertEqual(legacy["M_rad_kg"], 5744.0)
        self.assertEqual(legacy["mass_constraint_status"], "rejected")
        self.assertIn("5744 > 4650", legacy["rejection_reasons"])

    def test_write_outputs_has_stable_schema(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            audit.write_outputs(output, audit.build_audit())
            expected = {
                "candidate_family.csv", "identifiability.json",
                "rejection_log.csv", "mass_energy_envelope.csv",
            }
            self.assertEqual({p.name for p in output.iterdir()}, expected)
            with (output / "candidate_family.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 16)
            ident = json.loads((output / "identifiability.json").read_text())
            self.assertEqual(ident["author_implementation_status"],
                             "not_uniquely_identified")

    def test_candidate_execution_path_contains_no_model_api(self):
        paths = [
            ROOT / "tests/radiator_candidate_math.py",
            ROOT / "tests/audit_radiator_candidate_family.py",
        ]
        forbidden = ("load_system", "save_system", "sim(", "matlab.engine",
                     "ZipFile", ".slx")
        combined = "\n".join(path.read_text() for path in paths)
        for token in forbidden:
            self.assertNotIn(token, combined)

    def test_direct_script_entry_writes_outputs(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder) / "direct_output"
            completed = subprocess.run(
                [sys.executable,
                 str(ROOT / "tests/audit_radiator_candidate_family.py"),
                 str(output)],
                cwd=ROOT, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn("RADIATOR_CANDIDATE_FAMILY_PASS", completed.stdout)
            self.assertTrue((output / "identifiability.json").is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
