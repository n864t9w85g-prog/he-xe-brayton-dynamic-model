import math
from dataclasses import fields, replace
import itertools
import sys
import unittest
from unittest import mock

from tests import radiator_a1_math as a1_math
from tests import radiator_a1_contract as contract


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
    @staticmethod
    def _valid_kwargs():
        return {
            "branch_id": "synthetic_branch",
            "kappa_kg_m2": 1.0,
            "flow_case": "synthetic_flow",
            "m_dot_kg_s": 6.95,
            "epsilon_case": "synthetic_epsilon",
            "epsilon": 0.85,
            "sink_case": "synthetic_sink",
            "sink_K": 200.0,
            "h_case": "synthetic_h",
            "h_W_m2K": 200.0,
            "evidence_status_per_input": "synthetic_test",
        }

    def test_static_rows_are_exactly_96_unique_and_deterministic(self):
        first = a1_math.generate_static_rows()
        second = a1_math.generate_static_rows()
        expected_row_ids = [
            "__".join((
                branch.branch_id,
                flow.case_id,
                emissivity.case_id,
                sink.case_id,
                h_anchor.case_id,
            ))
            for branch, flow, emissivity, sink, h_anchor in itertools.product(
                contract.BRANCHES,
                contract.FLOWS,
                contract.EMISSIVITIES,
                contract.SINKS,
                contract.H_ANCHORS,
            )
        ]

        self.assertEqual(
            tuple(field.name for field in fields(a1_math.StaticRow)),
            EXPECTED_STATIC_ROW_FIELDS,
        )
        self.assertEqual(len(first), 96)
        self.assertTrue(all(isinstance(row, a1_math.StaticRow) for row in first))
        self.assertEqual(len({row.row_id for row in first}), 96)
        self.assertEqual([row.row_id for row in first], expected_row_ids)
        self.assertTrue(all(row.row_id for row in first))
        self.assertTrue(all(row.technology_maturity for row in first))
        self.assertTrue(all(row.evidence_status_per_input for row in first))
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

    def test_every_rooted_row_recomputes_all_derived_relations(self):
        for row in a1_math.generate_static_rows():
            if not math.isfinite(row.Twall_K):
                continue
            with self.subTest(row_id=row.row_id):
                exchange_residual_W = (
                    row.h_W_m2K
                    * row.A_exchange_m2
                    * (a1_math.T_MEAN_K - row.Twall_K)
                    - row.Q_NaK_W
                )
                radiation_residual_W = (
                    row.epsilon
                    * a1_math.SIGMA
                    * row.A_rad_m2
                    * (row.Twall_K**4 - row.T_sink_K**4)
                    - row.Q_NaK_W
                )
                self.assertEqual(row.A_exchange_m2, row.A_rad_m2)
                self.assertEqual(
                    row.UA_W_K,
                    row.h_W_m2K * row.A_exchange_m2,
                )
                self.assertEqual(
                    row.M_rad_kg,
                    row.kappa_kg_m2 * row.A_rad_m2,
                )
                self.assertEqual(
                    row.mass_margin_kg,
                    a1_math.MASS_UPPER_KG - row.M_rad_kg,
                )
                self.assertEqual(
                    row.exchange_residual_W,
                    exchange_residual_W,
                )
                self.assertEqual(
                    row.radiation_residual_W,
                    radiation_residual_W,
                )
                self.assertEqual(
                    "mass_above_4650_kg" in row.rejection_reasons,
                    row.M_rad_kg > a1_math.MASS_UPPER_KG,
                )

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

    def test_nonfinite_nonpositive_input_matrix_is_structurally_rejected(self):
        invalid_values = (math.nan, math.inf, -math.inf, 0.0, -1.0)
        parameters = (
            "epsilon",
            "kappa_kg_m2",
            "m_dot_kg_s",
            "h_W_m2K",
            "sink_K",
        )
        for parameter, value in itertools.product(parameters, invalid_values):
            kwargs = self._valid_kwargs()
            kwargs[parameter] = value
            with self.subTest(parameter=parameter, value=value):
                row = a1_math.solve_static_case(**kwargs)
                self.assertEqual(row.condition_status, "rejected")
                expected_reason = (
                    "epsilon_out_of_range"
                    if parameter == "epsilon"
                    else "nonpositive_or_nonfinite_input"
                )
                self.assertIn(expected_reason, row.rejection_reasons)
                self.assertTrue(math.isnan(row.Q_NaK_W))

    def test_multiple_input_reasons_have_fixed_order(self):
        kwargs = self._valid_kwargs()
        kwargs.update({
            "branch_id": "",
            "epsilon": 0.0,
            "kappa_kg_m2": -1.0,
            "sink_K": math.inf,
            "input_units_complete": False,
        })
        row = a1_math.solve_static_case(**kwargs)
        self.assertEqual(row.condition_status, "rejected")
        self.assertEqual(row.rejection_reasons, (
            "epsilon_out_of_range",
            "nonpositive_or_nonfinite_input",
            "sink_not_below_cold_endpoint",
            "missing_input_identity_or_unit",
        ))

    def test_missing_identity_or_unit_is_unidentifiable(self):
        identity_fields = (
            "branch_id",
            "flow_case",
            "epsilon_case",
            "sink_case",
            "h_case",
            "technology_maturity",
            "evidence_status_per_input",
        )
        for field_name in identity_fields:
            kwargs = self._valid_kwargs()
            kwargs[field_name] = (
                None if field_name == "evidence_status_per_input" else ""
            )
            with self.subTest(field_name=field_name):
                row = a1_math.solve_static_case(**kwargs)
                self.assertEqual(
                    row.condition_status,
                    "unidentifiable_due_to_missing_input",
                )
                self.assertEqual(
                    row.rejection_reasons,
                    ("missing_input_identity_or_unit",),
                )

        kwargs = self._valid_kwargs()
        kwargs["input_units_complete"] = False
        row = a1_math.solve_static_case(**kwargs)
        self.assertEqual(
            row.condition_status,
            "unidentifiable_due_to_missing_input",
        )
        self.assertEqual(
            row.rejection_reasons,
            ("missing_input_identity_or_unit",),
        )

    def test_no_physical_root_preserves_power_and_nan_derived_values(self):
        kwargs = self._valid_kwargs()
        expected_power_W = (
            kwargs["m_dot_kg_s"] * a1_math._enthalpy_rise_J_kg()
        )
        with mock.patch.object(
            a1_math,
            "_wall_root",
            side_effect=a1_math.NoPhysicalWallRoot("synthetic no root"),
        ):
            row = a1_math.solve_static_case(**kwargs)

        self.assertEqual(row.Q_NaK_W, expected_power_W)
        for value in (
            row.Twall_K,
            row.A_exchange_m2,
            row.A_rad_m2,
            row.UA_W_K,
            row.M_rad_kg,
            row.mass_margin_kg,
            row.exchange_residual_W,
            row.radiation_residual_W,
        ):
            self.assertTrue(math.isnan(value))
        self.assertEqual(row.condition_status, "rejected")
        self.assertEqual(
            row.rejection_reasons,
            ("no_physical_wall_root",),
        )

    def test_invalid_wall_root_values_are_structurally_rejected(self):
        kwargs = self._valid_kwargs()
        expected_power_W = (
            kwargs["m_dot_kg_s"] * a1_math._enthalpy_rise_J_kg()
        )
        invalid_wall_values = (
            math.nan,
            math.inf,
            -math.inf,
            kwargs["sink_K"],
            a1_math.T_MEAN_K,
            math.nextafter(a1_math.T_MEAN_K, math.inf),
            sys.float_info.max,
        )
        for wall_K in invalid_wall_values:
            with self.subTest(wall_K=wall_K):
                with mock.patch.object(
                    a1_math,
                    "_wall_root",
                    return_value=wall_K,
                ):
                    row = a1_math.solve_static_case(**kwargs)
                self.assertEqual(row.Q_NaK_W, expected_power_W)
                for value in (
                    row.Twall_K,
                    row.A_exchange_m2,
                    row.A_rad_m2,
                    row.UA_W_K,
                    row.M_rad_kg,
                    row.mass_margin_kg,
                    row.exchange_residual_W,
                    row.radiation_residual_W,
                ):
                    self.assertTrue(math.isnan(value))
                self.assertEqual(row.condition_status, "rejected")
                self.assertEqual(row.rejection_reasons, (
                    "nonpositive_or_nonfinite_derived_quantity",
                    "equation_residual_above_tolerance",
                ))

        kwargs["input_units_complete"] = False
        with mock.patch.object(
            a1_math,
            "_wall_root",
            return_value=math.nan,
        ):
            row = a1_math.solve_static_case(**kwargs)
        self.assertEqual(row.condition_status, "rejected")
        self.assertEqual(row.rejection_reasons, (
            "nonpositive_or_nonfinite_derived_quantity",
            "equation_residual_above_tolerance",
            "missing_input_identity_or_unit",
        ))

    def test_generator_checks_each_evidence_component_before_joining(self):
        baseline_rows = a1_math.generate_static_rows()
        baseline_by_id = {row.row_id: row for row in baseline_rows}
        evidence_axes = (
            ("BRANCHES", "maturity", "branch_id", "branch_id"),
            ("FLOWS", "evidence", "case_id", "flow_case"),
            (
                "EMISSIVITIES",
                "evidence",
                "case_id",
                "epsilon_case",
            ),
            ("SINKS", "evidence", "case_id", "sink_case"),
            ("H_ANCHORS", "evidence", "case_id", "h_case"),
        )
        for axis_name, evidence_field, key_field, row_field in evidence_axes:
            original_axis = getattr(contract, axis_name)
            changed_value = replace(
                original_axis[0],
                **{evidence_field: ""},
            )
            changed_axis = (changed_value, *original_axis[1:])
            affected_key = getattr(changed_value, key_field)
            with self.subTest(axis=axis_name):
                with mock.patch.object(contract, axis_name, changed_axis):
                    actual_rows = a1_math.generate_static_rows()

                self.assertEqual(len(actual_rows), len(baseline_rows))
                for actual in actual_rows:
                    baseline = baseline_by_id[actual.row_id]
                    if getattr(actual, row_field) != affected_key:
                        self.assertEqual(actual, baseline)
                        continue

                    expected_reasons = (
                        baseline.rejection_reasons
                        + ("missing_input_identity_or_unit",)
                    )
                    expected_status = (
                        "rejected"
                        if baseline.rejection_reasons
                        else "unidentifiable_due_to_missing_input"
                    )
                    self.assertEqual(
                        actual.rejection_reasons,
                        expected_reasons,
                    )
                    self.assertEqual(actual.condition_status, expected_status)

                self.assertEqual(
                    a1_math.generate_static_rows(),
                    baseline_rows,
                )

    def test_finite_huge_flow_is_structurally_rejected_without_exception(self):
        kwargs = self._valid_kwargs()
        kwargs.update({
            "m_dot_kg_s": sys.float_info.max,
            "kappa_kg_m2": 1e-300,
        })
        row = a1_math.solve_static_case(**kwargs)
        self.assertEqual(row.condition_status, "rejected")
        self.assertIn(
            "nonpositive_or_nonfinite_derived_quantity",
            row.rejection_reasons,
        )
        self.assertIn(
            "equation_residual_above_tolerance",
            row.rejection_reasons,
        )

    def test_large_flow_roundoff_cannot_pass_residual_gate(self):
        kwargs = self._valid_kwargs()
        kwargs.update({"m_dot_kg_s": 1e8, "kappa_kg_m2": 1e-12})
        row = a1_math.solve_static_case(**kwargs)
        self.assertEqual(row.condition_status, "rejected")
        self.assertIn(
            "equation_residual_above_tolerance",
            row.rejection_reasons,
        )
        self.assertGreater(
            abs(row.radiation_residual_W),
            a1_math.RESIDUAL_TOLERANCE_W,
        )

    def test_mass_gate_is_strictly_above_boundary(self):
        kwargs = self._valid_kwargs()
        base = a1_math.solve_static_case(**kwargs)
        boundary_kappa = a1_math.MASS_UPPER_KG / base.A_rad_m2
        cases = (
            (math.nextafter(boundary_kappa, 0.0), False),
            (boundary_kappa, False),
            (math.nextafter(boundary_kappa, math.inf), True),
        )
        for kappa, expected_rejected in cases:
            kwargs = self._valid_kwargs()
            kwargs["kappa_kg_m2"] = kappa
            row = a1_math.solve_static_case(**kwargs)
            with self.subTest(kappa=kappa, mass=row.M_rad_kg):
                self.assertEqual(
                    "mass_above_4650_kg" in row.rejection_reasons,
                    expected_rejected,
                )

    def test_normal_family_retains_88_to_8_gate_distribution(self):
        rows = a1_math.generate_static_rows()
        statuses = [row.condition_status for row in rows]
        self.assertEqual(len(rows), 96)
        self.assertEqual(
            statuses.count("not_rejected_under_necessary_conditions"),
            88,
        )
        self.assertEqual(statuses.count("rejected"), 8)
        self.assertEqual(
            {
                reason
                for row in rows
                for reason in row.rejection_reasons
            },
            {"mass_above_4650_kg"},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
