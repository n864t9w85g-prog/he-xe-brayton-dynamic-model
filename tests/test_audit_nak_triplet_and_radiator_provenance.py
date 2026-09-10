import importlib.util
import math
from pathlib import Path
import unittest


MODULE = Path(__file__).with_name("audit_nak_triplet_and_radiator_provenance.py")
SPEC = importlib.util.spec_from_file_location("nak_audit", MODULE)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class AuditArithmeticTests(unittest.TestCase):
    def test_scheme_b_mass_data_excludes_5744_kg_radiator(self):
        remainder = AUDIT.scheme_b_radiator_tac_upper_bound_kg()
        self.assertEqual(remainder, 4650)
        self.assertLess(remainder, 5744)

    def test_active_nak_property_triplet_is_not_closed_at_695(self):
        delta_h = AUDIT.nak_enthalpy_J_kg(609.58) - AUDIT.nak_enthalpy_J_kg(360.10)
        self.assertTrue(math.isclose(delta_h, 227357.265107, abs_tol=1e-6))
        self.assertTrue(math.isclose(6.95 * delta_h / 1000, 1580.132992, abs_tol=1e-6))
        self.assertTrue(math.isclose(1622000 / delta_h, 7.134146, abs_tol=1e-6))


if __name__ == "__main__":
    unittest.main(verbosity=2)
