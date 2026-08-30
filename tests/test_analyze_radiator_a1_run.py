import math
import unittest

from tests import analyze_radiator_a1_run as analyze


class AnalyzeRadiatorA1RunTests(unittest.TestCase):
    def test_energy_gate_uses_approved_thresholds(self):
        self.assertTrue(analyze.energy_gate(0.999, 999.999, True))
        self.assertFalse(analyze.energy_gate(1.0, 999.0, True))
        self.assertFalse(analyze.energy_gate(0.5, 1000.0, True))
        self.assertFalse(analyze.energy_gate(0.5, 500.0, False))

    def test_persistent_growth_needs_five_consecutive_increasing_ranges(self):
        growing = []
        for amplitude in (1, 2, 4, 8, 16):
            growing.extend([0.0, float(amplitude)])
        self.assertTrue(analyze.persistent_growth(growing))
        bounded = [0.0, 2.0, 0.0, 2.1, 0.0, 1.9,
                   0.0, 2.0, 0.0, 2.0]
        self.assertFalse(analyze.persistent_growth(bounded))

    def test_finite_real_rejects_nonfinite_and_complex(self):
        self.assertTrue(analyze.all_finite_real([1.0, 2.0]))
        self.assertFalse(analyze.all_finite_real([1.0, math.inf]))
        self.assertFalse(analyze.all_finite_real([1.0, complex(2.0, 1.0)]))

    def test_paper_target_is_not_reused_as_input_credit(self):
        comparison = analyze.paper_comparison({
            "cooler_cold_inlet_T": 360.10,
            "cooler_cold_outlet_T": 609.58,
            "reactor_inlet_T": 1443.27,
        })
        self.assertEqual(
            comparison["cooler_cold_inlet_T"]["independent_validation"],
            False,
        )
        self.assertEqual(
            comparison["cooler_cold_outlet_T"]["independent_validation"],
            False,
        )
        self.assertEqual(
            comparison["reactor_inlet_T"]["independent_validation"],
            True,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
