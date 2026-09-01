import csv
import json
from pathlib import Path
import tempfile
import unittest

from tests import build_radiator_a1_screen as builder
from tests import radiator_a1_contract as contract


ROOT = Path(__file__).resolve().parents[1]


class RadiatorA1EndToEndContractTests(unittest.TestCase):
    def test_offline_schema_has_units_sources_unique_ids_and_no_replacement(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            units = json.loads(
                (output / "source_contract/unit_contract.json").read_text()
            )
            self.assertTrue(units)
            self.assertTrue(all(units.values()))
            with (output / "offline_screen/offline_96.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 96)
            self.assertEqual(len({row["row_id"] for row in rows}), 96)
            self.assertTrue(
                all(row["evidence_status_per_input"] for row in rows)
            )
            selection = json.loads(
                (output / "representatives/selection.json").read_text()
            )
            self.assertFalse(selection["replacement_allowed"])
            self.assertFalse(selection["paper_reproduced"])

    def test_protected_contract_covers_formal_model_mat_and_properties(self):
        evidence = contract.verify_source_contract()
        self.assertEqual(evidence["protected_count"], 34)
        with contract.PROTECTED.open() as handle:
            paths = {
                Path(row["paths"]).name for row in csv.DictReader(handle)
            }
        self.assertIn("final_steady_24a.slx", paths)
        self.assertIn("HeXe_property_simulink.m", paths)
        self.assertIn("Lithium_property_simulink.m", paths)
        self.assertTrue(any(name.endswith(".mat") for name in paths))

    def test_python_execution_path_cannot_load_or_write_slx(self):
        paths = [
            ROOT / "tests/radiator_a1_contract.py",
            ROOT / "tests/radiator_a1_math.py",
            ROOT / "tests/build_radiator_a1_screen.py",
            ROOT / "tests/analyze_radiator_a1_run.py",
            ROOT / "tests/summarize_radiator_a1.py",
        ]
        combined = "\n".join(path.read_text() for path in paths)
        for forbidden in (
            "load_system",
            "save_system",
            "matlab.engine",
            "ZipFile",
            "writestr(",
        ):
            self.assertNotIn(forbidden, combined)

    def test_matlab_write_path_uses_official_api_and_runtime_stop_time(self):
        patch = (ROOT / "tests/patch_radiator_a1_candidate.m").read_text()
        runner = (ROOT / "tests/run_radiator_a1_candidate.m").read_text()
        self.assertIn("set_param", patch)
        self.assertIn("save_system", patch)
        self.assertIn("Simulink.SimulationInput", runner)
        self.assertIn("setModelParameter", runner)
        self.assertNotIn("save_system", runner)
        self.assertNotIn("unzip", patch + runner)

    def test_no_runtime_code_can_promote_or_expand(self):
        paths = [
            ROOT / "tests/build_radiator_a1_screen.py",
            ROOT / "tests/analyze_radiator_a1_run.py",
            ROOT / "tests/summarize_radiator_a1.py",
        ]
        combined = "\n".join(path.read_text() for path in paths)
        self.assertIn('"paper_reproduced": False', combined)
        self.assertIn('"formal_promotion": False', combined)
        self.assertIn('"expand_envelope": False', combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
