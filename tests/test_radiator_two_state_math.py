"""Executable specification for the radiator two-state interval algebra."""
from __future__ import annotations

from dataclasses import FrozenInstanceError, fields
import math
import unittest

from tests import radiator_two_state_contract as contract
from tests import radiator_two_state_math as model


def _sample(time_s, wall_K, outlet_K):
    return contract.Sample(0.0, 0.0, 0.0, time_s, wall_K, outlet_K)


def _inlet_cp(tin_K, tout_K, m_dot_kg_s):
    cp = 1000.0 * (
        1.061 - 3.694e-4 * tin_K + 4.615e-8 * tin_K**2
        + 1.509e-10 * tin_K**3
    )
    return m_dot_kg_s * cp * (tin_K - tout_K)


def _positive_curve():
    """Twelve samples generated from the inlet-cp interval equation."""
    tin, flow, capacity, ua = contract.TIN_K, 1.0, 100_000.0, 500.0
    heat_rate = _inlet_cp(tin, 0.0, flow) - _inlet_cp(tin, 1.0, flow)
    outlet, wall = [300.0], [300.0]
    for index in range(11):
        previous_outlet, previous_wall = outlet[-1], wall[-1]
        if index == 5:
            next_outlet = previous_outlet
            tbar = 0.8 * tin + 0.2 * previous_outlet
            next_wall = 2.0 * (tbar - _inlet_cp(tin, previous_outlet, flow) / ua) - previous_wall
        else:
            next_wall = 300.0
            denominator = 0.2 * capacity + 0.1 * ua + 0.5 * heat_rate
            numerator = (
                0.2 * capacity * previous_outlet
                - 0.5 * ua * ((0.8 * tin + 0.2 * previous_outlet - previous_wall) + (0.8 * tin - next_wall))
                + 0.5 * heat_rate * (2.0 * tin - previous_outlet)
            )
            next_outlet = numerator / denominator
        outlet.append(next_outlet)
        wall.append(next_wall)
    return tuple(_sample(float(index), wall[index], outlet[index]) for index in range(12))


class RadiatorTwoStateMathTests(unittest.TestCase):
    def test_analytic_nak_cp_and_enthalpy_values_and_integral_sanity(self):
        temperature = 609.58
        self.assertAlmostEqual(model.cp_nak_J_kgK(temperature), 887.1506566206109, places=10)
        self.assertAlmostEqual(model.h_nak_J_kg(temperature), 586825.6073986125, places=7)
        lower, upper = 450.0, 700.0
        midpoint_sum = sum(model.cp_nak_J_kgK(lower + (upper - lower) * (i + 0.5) / 100_000) for i in range(100_000))
        numerical_integral = (upper - lower) * midpoint_sum / 100_000
        self.assertAlmostEqual(model.h_nak_J_kg(upper) - model.h_nak_J_kg(lower), numerical_integral, places=3)

    def test_public_records_are_frozen_and_have_required_fields(self):
        expected = {
            model.Coefficient: ("interval_index", "start_s", "end_s", "A_K", "B_K_s", "D_J"),
            model.Solution: ("C_fluid_J_K", "UA_W_K", "sse_J2"),
            model.ResidualRange: ("minimum_J", "maximum_J", "contains_zero", "admissible_corner_count"),
            model.IntervalAnalysis: ("coefficient", "residual_J", "relative_residual", "conditional_C_fluid_J_K", "corner_range"),
            model.CaseAnalysis: ("case", "case_enum", "nominal_sign_gate", "favorable_sign_gate", "unrestricted_solution", "nnls_solution", "equivalent_mass_kg", "all_intervals_locally_compatible", "intervals"),
        }
        for record, names in expected.items():
            with self.subTest(record=record.__name__):
                self.assertEqual(tuple(item.name for item in fields(record)), names)
        row = model.Coefficient(0, 0.0, 1.0, 1.0, 2.0, 3.0)
        with self.assertRaises(FrozenInstanceError):
            row.A_K = 4.0
        with self.assertRaises(TypeError):
            model.ENERGY_FUNCTIONS["inlet_cp"] = _inlet_cp

    def test_interval_coefficient_matches_hand_integral(self):
        first = _sample(0.0, 280.0, 300.0)
        second = _sample(10.0, 300.0, 320.0)
        row = model.interval_coefficient(
            first, second, 600.0, 2.0,
            lambda tin, tout, flow: flow * 1000.0 * (tin - tout),
        )
        self.assertEqual(row.A_K, 4.0)
        self.assertEqual(row.B_K_s, 2520.0)
        self.assertEqual(row.D_J, 5_800_000.0)

    def test_unrestricted_and_nnls_solvers_cover_interior_and_boundary(self):
        exact = (
            model.Coefficient(0, 0, 1, 1, 0, 20),
            model.Coefficient(1, 1, 2, 0, 1, 30),
            model.Coefficient(2, 2, 3, 1, 1, 50),
        )
        self.assertEqual(model.solve_unrestricted(exact), model.Solution(20, 30, 0))
        self.assertEqual(model.solve_nnls(exact), model.Solution(20, 30, 0))
        boundary = (
            model.Coefficient(0, 0, 1, 1, 0, -1),
            model.Coefficient(1, 1, 2, 0, 1, 2),
        )
        self.assertEqual(model.solve_nnls(boundary), model.Solution(0, 2, 1))

    def test_corner_range_straddles_zero_and_discards_nonpositive_duration(self):
        first, second = _sample(0, 280, 300), _sample(2, 300, 320)
        row = model.interval_coefficient(first, second, 600, 2, _inlet_cp)
        candidate = model.Solution(10, (row.D_J - 40) / row.B_K_s, 0)
        bounds = model.corner_residual_range(first, second, candidate, 600, 2, _inlet_cp, 3, 2)
        self.assertLessEqual(bounds.minimum_J, 0)
        self.assertGreaterEqual(bounds.maximum_J, 0)
        self.assertTrue(bounds.contains_zero)
        self.assertGreater(bounds.admissible_corner_count, 0)
        self.assertLess(bounds.admissible_corner_count, 64)

    def test_nominal_and_favorable_sign_gates_cover_conflict_and_nonconflict(self):
        conflict = (
            model.Coefficient(0, 0, 1, 1, 1, 2),
            model.Coefficient(1, 1, 2, 0, 1, 3),
        )
        compatible = (
            model.Coefficient(0, 0, 1, 1, 1, 4),
            model.Coefficient(1, 1, 2, 0, 1, 3),
        )
        self.assertTrue(model.nominal_sign_gate(conflict)["conflict"])
        self.assertFalse(model.nominal_sign_gate(compatible)["conflict"])
        favorable_compatible = (_sample(0, 300, 300), _sample(1, 300, 320), _sample(2, 300, 320))
        favorable_conflict = (_sample(0, 100, 300), _sample(1, 450, 320), _sample(2, 450, 320))
        self.assertFalse(model.favorable_sign_gate(favorable_compatible, 600, 2, _inlet_cp, 3)["conflict"])
        self.assertTrue(model.favorable_sign_gate(favorable_conflict, 600, 2, _inlet_cp, 3)["conflict"])

    def test_analyze_case_has_eleven_rows_plateau_none_and_positive_corner_ranges(self):
        case = contract.Case("synthetic", "synthetic", 1.0, "inlet_cp")
        analysis = model.analyze_case(case, _positive_curve())
        self.assertEqual(len(analysis.intervals), 11)
        self.assertTrue(all(item.corner_range is not None for item in analysis.intervals))
        self.assertTrue(analysis.unrestricted_solution.C_fluid_J_K > 0)
        self.assertTrue(analysis.unrestricted_solution.UA_W_K > 0)
        self.assertIsNotNone(analysis.equivalent_mass_kg)
        self.assertIsNone(analysis.intervals[5].conditional_C_fluid_J_K)

    def test_analyze_case_nonpositive_candidate_has_no_corner_ranges(self):
        case = contract.Case("synthetic", "synthetic", 1.0, "inlet_cp")
        points = ((300.0, 100.0),) + ((320.0, 450.0),) * 11
        samples = tuple(_sample(float(index), wall, outlet) for index, (outlet, wall) in enumerate(points))
        analysis = model.analyze_case(case, samples)
        self.assertFalse(analysis.all_intervals_locally_compatible)
        self.assertTrue(all(item.corner_range is None for item in analysis.intervals))
        self.assertIsNone(analysis.equivalent_mass_kg)

    def test_global_classification_order_is_fixed_and_requires_four_cases(self):
        self.assertEqual(model.aggregate_case_enums(["robustly_infeasible"] * 4), "constant_positive_two_state_robustly_infeasible")
        self.assertEqual(model.aggregate_case_enums(["robustly_infeasible", "reading_sensitive"] * 2), "constant_positive_two_state_nominally_infeasible_but_reading_sensitive")
        self.assertEqual(model.aggregate_case_enums(["robustly_infeasible", "full_interval_inconsistent", "conditionally_feasible", "full_interval_inconsistent"]), "constant_positive_two_state_conditionally_feasible")
        self.assertEqual(model.aggregate_case_enums(["robustly_infeasible", "full_interval_inconsistent", "reading_sensitive", "full_interval_inconsistent"]), "constant_positive_two_state_full_interval_inconsistent")
        with self.assertRaises(ValueError):
            model.aggregate_case_enums(["robustly_infeasible"] * 3)

    def test_invalid_times_rank_energy_paths_and_nonfinite_inputs_are_rejected(self):
        with self.assertRaises(ValueError):
            model.interval_coefficient(_sample(2, 300, 300), _sample(1, 300, 301), 600, 1, _inlet_cp)
        with self.assertRaises(ValueError):
            model.solve_unrestricted((model.Coefficient(0, 0, 1, 1, 1, 1),))
        with self.assertRaises(ValueError):
            model.analyze_case(contract.Case("bad", "bad", 1, "unknown"), _positive_curve())
        with self.assertRaises(ValueError):
            model.analyze_case(contract.Case("bad", "bad", 1, "inlet_cp"), _positive_curve()[:-1])
        with self.assertRaises(ValueError):
            model.interval_coefficient(_sample(0, math.nan, 300), _sample(1, 300, 301), 600, 1, _inlet_cp)


if __name__ == "__main__":
    unittest.main(verbosity=2)
