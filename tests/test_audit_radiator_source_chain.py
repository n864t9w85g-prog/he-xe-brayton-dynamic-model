import importlib.util
from pathlib import Path
import unittest


MODULE = Path(__file__).with_name("audit_radiator_source_chain.py")
SPEC = importlib.util.spec_from_file_location("radiator_source_audit", MODULE)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class RadiatorSourceChainTests(unittest.TestCase):
    def test_nasa_table_i_is_a_branch_family_not_one_universal_kappa(self):
        branches = AUDIT.table_i_specific_mass()
        values = {
            value
            for side in branches.values()
            for density in side.values()
            for value in density
        }
        self.assertEqual(len(values), 16)
        self.assertEqual(min(values), 0.92)
        self.assertEqual(max(values), 4.22)

    def test_source_matrix_keeps_missing_author_inputs_explicit(self):
        audit = AUDIT.build_audit()
        self.assertFalse(audit["model_acceptance_passed"])
        self.assertIn("NaK_mass_flow", audit["missing_quantities"])
        self.assertIn("radiator_radiating_area", audit["missing_quantities"])
        self.assertIn("optimization_source_code", audit["missing_quantities"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
