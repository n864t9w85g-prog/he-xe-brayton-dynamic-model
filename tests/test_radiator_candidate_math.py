import math
import unittest

from tests import radiator_candidate_math as mathlib


class CandidateBranchTests(unittest.TestCase):
    def test_all_16_source_branches_have_unique_identity(self):
        rows = mathlib.material_branches()
        self.assertEqual(len(rows), 16)
        self.assertEqual(len({row.candidate_id for row in rows}), 16)
        self.assertEqual({row.material for row in rows},
                         {"T300", "P95_WG", "K1100", "APG"})
        self.assertEqual(min(row.kappa_kg_m2 for row in rows), 0.92)
        self.assertEqual(max(row.kappa_kg_m2 for row in rows), 4.22)

    def test_maturity_does_not_upgrade_projected_branches(self):
        lookup = {row.candidate_id: row for row in mathlib.material_branches()}
        self.assertEqual(lookup["T300_fd1p45_one"].maturity, "tested")
        self.assertEqual(lookup["P95_WG_fd1p45_two"].maturity,
                         "built_not_tested")
        self.assertEqual(lookup["APG_fd1p00_two"].maturity, "projected")

    def test_mass_area_upper_bound_is_relation_not_replacement_area(self):
        t300 = next(row for row in mathlib.material_branches()
                    if row.candidate_id == "T300_fd1p45_one")
        self.assertTrue(math.isclose(
            mathlib.area_upper_bound_m2(t300.kappa_kg_m2),
            4650.0 / 4.22, rel_tol=0.0, abs_tol=1e-12))
        self.assertLess(mathlib.area_upper_bound_m2(t300.kappa_kg_m2), 1113.0)

    def test_nak_triplet_remains_conditional_not_author_input(self):
        delta_h = mathlib.nak_enthalpy_J_kg(609.58) - mathlib.nak_enthalpy_J_kg(360.10)
        self.assertTrue(math.isclose(delta_h, 227357.265107,
                                     rel_tol=0.0, abs_tol=1e-6))
        self.assertTrue(math.isclose(
            mathlib.conditional_flow_kg_s(1_622_000.0, delta_h),
            7.134146337, rel_tol=0.0, abs_tol=1e-9))
        self.assertTrue(math.isclose(6.95 * delta_h / 1000.0,
                                     1580.132992, rel_tol=0.0, abs_tol=1e-6))

    def test_ideal_radiation_relation_uses_explicit_sink(self):
        epsilon_area = mathlib.ideal_epsilon_area_required_m2(
            1_622_000.0, 360.10, 609.58, 0.0)
        self.assertTrue(math.isclose(epsilon_area, 456.8180744750801,
                                     rel_tol=0.0, abs_tol=1e-9))
        self.assertGreater(
            mathlib.ideal_epsilon_area_required_m2(
                1_622_000.0, 360.10, 609.58, 225.0),
            epsilon_area)
        with self.assertRaises(ValueError):
            mathlib.ideal_epsilon_area_required_m2(
                1_622_000.0, 360.10, 609.58, 360.10)

    def test_timescale_output_is_combination_not_material_cp(self):
        epsilon_area = 456.8180744750801
        conductance = mathlib.linearized_radiation_conductance_W_K(
            epsilon_area, 418.0)
        self.assertTrue(math.isclose(conductance, 7566.85086298154,
                                     rel_tol=0.0, abs_tol=1e-9))
        relation = mathlib.radiative_capacity_relation_J_K(
            epsilon_area, 418.0, 120.0, 150.0)
        self.assertEqual(relation["status"], "conditional_combination")
        self.assertTrue(math.isclose(relation["C_rad_120s_J_K"],
                                     908022.1035577848,
                                     rel_tol=0.0, abs_tol=1e-6))


if __name__ == "__main__":
    unittest.main(verbosity=2)
