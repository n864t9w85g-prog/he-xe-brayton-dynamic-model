import math
from dataclasses import fields
import unittest

from tests import radiator_a1_math as a1_math


EXPECTED_STATIC_ROW_FIELDS = (
    "row_id",
    "branch_id",
    "kappa_kg_m2",
    "technology_maturity",
    "flow_case",
    "m_dot_NaK_kg_s",
    "epsilon_case",
    "epsilon",
    "sink_case",
    "T_sink_K",
    "h_case",
    "h_W_m2K",
    "Q_NaK_W",
    "Twall_K",
    "A_exchange_m2",
    "A_rad_m2",
    "UA_W_K",
    "M_rad_kg",
    "mass_margin_kg",
    "exchange_residual_W",
    "radiation_residual_W",
    "condition_status",
    "evidence_status_per_input",
    "rejection_reasons",
)


class RadiatorA1MathTests(unittest.TestCase):
    def test_static_rows_are_exactly_96_unique_and_deterministic(self):
        first = a1_math.generate_static_rows()
        second = a1_math.generate_static_rows()

        self.assertEqual(
            tuple(field.name for field in fields(a1_math.StaticRow)),
            EXPECTED_STATIC_ROW_FIELDS,
        )
        self.assertEqual(len(first), 96)
        self.assertTrue(all(isinstance(row, a1_math.StaticRow) for row in first))
        self.assertEqual(len({row.row_id for row in first}), 96)
        self.assertEqual(first, second)

    def test_nonrejected_rows_satisfy_physical_order_and_balances(self):
        rows = [
            row
            for row in a1_math.generate_static_rows()
            if row.condition_status == "not_rejected_under_necessary_conditions"
        ]

        self.assertGreater(len(rows), 0)
        for row in rows:
            with self.subTest(row_id=row.row_id):
                self.assertLess(row.T_sink_K, row.Twall_K)
                self.assertLess(row.Twall_K, a1_math.T_MEAN_K)
                self.assertGreater(row.A_rad_m2, 0.0)
                self.assertGreater(row.UA_W_K, 0.0)
                self.assertLess(abs(row.exchange_residual_W), 1e-6)
                self.assertLess(abs(row.radiation_residual_W), 1e-6)

    def test_4650_kg_is_only_an_upper_bound_rejection_gate(self):
        rows = [
            row
            for row in a1_math.generate_static_rows()
            if "mass_above_4650_kg" in row.rejection_reasons
        ]

        self.assertGreater(len(rows), 0)
        for row in rows:
            with self.subTest(row_id=row.row_id):
                self.assertGreater(row.M_rad_kg, a1_math.MASS_UPPER_KG)
                self.assertEqual(row.condition_status, "rejected")

    def test_flow_cases_preserve_integral_enthalpy_energy_identity(self):
        rows = a1_math.generate_static_rows()
        project_q_values = {
            row.Q_NaK_W for row in rows if row.flow_case == "project_flow"
        }
        closure_q_values = {
            row.Q_NaK_W
            for row in rows
            if row.flow_case == "energy_closure_flow"
        }

        self.assertEqual(len(project_q_values), 1)
        self.assertAlmostEqual(
            project_q_values.pop(),
            1_580_132.9924937415,
            places=6,
        )
        self.assertEqual(len(closure_q_values), 1)
        self.assertTrue(
            math.isclose(
                closure_q_values.pop(),
                1_622_000.0,
                rel_tol=0.0,
                abs_tol=1e-3,
            )
        )

    def test_zero_epsilon_is_rejected_without_hiding_invalid_root(self):
        row = a1_math.solve_static_case(
            branch_id="synthetic_branch",
            kappa_kg_m2=1.0,
            flow_case="synthetic_flow",
            m_dot_kg_s=1.0,
            epsilon_case="synthetic_epsilon",
            epsilon=0.0,
            sink_case="synthetic_sink",
            sink_K=200.0,
            h_case="synthetic_h",
            h_W_m2K=200.0,
            evidence_status_per_input="synthetic_test",
        )

        self.assertEqual(row.condition_status, "rejected")
        self.assertIn("epsilon_out_of_range", row.rejection_reasons)
        self.assertTrue(math.isnan(row.Twall_K))


if __name__ == "__main__":
    unittest.main(verbosity=2)
