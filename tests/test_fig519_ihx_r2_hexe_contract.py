from __future__ import annotations

import ast
import subprocess
import sys
import unittest
from decimal import Decimal
from pathlib import Path

from tests import fig519_ihx_r2_hexe_contract as contract


class Figure519IhxR2HexeContractTests(unittest.TestCase):
    def test_exact_literals(self):
        self.assertEqual(contract.ATTEMPT_ID, "20260901_A3")
        self.assertEqual(
            contract.ANCHOR_IDENTITY,
            "figure_5_18a_t0_visual_proxy_not_author_initial_state",
        )
        self.assertEqual(
            contract.SOURCE_MODEL_SHA256,
            "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        )
        self.assertEqual(
            contract.AVERAGE_PATH,
            "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
        )
        self.assertEqual(
            contract.OUTLET_PATH,
            "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
        )
        self.assertEqual(contract.OLD_AVERAGE_K, Decimal("1245.8184669844006"))
        self.assertEqual(contract.OLD_OUTLET_K, Decimal("1393.6037139151003"))
        self.assertEqual(contract.ANCHOR_K, Decimal("1200.0000000000000"))

    def test_candidate_is_one_delta_and_preserves_the_exact_gap(self):
        candidate = contract.candidate_contract()
        self.assertEqual(candidate["delta_K"], Decimal("-193.6037139151003"))
        self.assertEqual(candidate["new_average_K"], Decimal("1052.2147530693003"))
        self.assertEqual(candidate["new_outlet_K"], Decimal("1200.0000000000000"))
        self.assertEqual(candidate["old_gap_K"], Decimal("147.7852469306997"))
        self.assertEqual(candidate["new_gap_K"], Decimal("147.7852469306997"))
        self.assertEqual(
            candidate["new_average_K"], contract.OLD_AVERAGE_K + candidate["delta_K"]
        )
        self.assertEqual(
            candidate["new_outlet_K"], contract.OLD_OUTLET_K + candidate["delta_K"]
        )
        with self.assertRaises(TypeError):
            candidate["delta_K"] = Decimal("0")

    def test_directions_thresholds_and_promotion_flags_are_exact_and_immutable(self):
        self.assertEqual(
            dict(contract.PAPER_DIRECTIONS),
            {
                "reactor": ("fall",),
                "turbine": ("rise",),
                "compressor": ("fall", "rise"),
                "electrical_paper_eta": ("rise", "fall"),
            },
        )
        self.assertEqual(
            dict(contract.NONFLAT_THRESHOLDS_W),
            {
                "reactor": Decimal("0.5141158541664481"),
                "turbine": Decimal("1.609319536946714"),
                "compressor": Decimal("2.2659989586099982"),
                "electrical_paper_eta": Decimal("3.7926344096194953"),
            },
        )
        self.assertEqual(
            dict(contract.promotion_flags()),
            {
                "paper_reproduced": False,
                "author_initial_state_identified": False,
                "formal_promotion": False,
            },
        )
        for immutable in (
            contract.PAPER_DIRECTIONS,
            contract.NONFLAT_THRESHOLDS_W,
            contract.promotion_flags(),
        ):
            with self.assertRaises(TypeError):
                immutable["reactor"] = object()

    def test_classification_covers_every_mechanical_enum(self):
        matching_directions = dict(contract.PAPER_DIRECTIONS)
        all_nonflat = {name: True for name in contract.PAPER_DIRECTIONS}
        self.assertEqual(
            contract.classify(False, {}, {}),
            "numerical_or_physical_gate_failed",
        )
        self.assertEqual(
            contract.classify(True, matching_directions, all_nonflat),
            "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
        )
        mutated = dict(matching_directions)
        mutated["compressor"] = ("rise", "fall")
        self.assertEqual(
            contract.classify(True, mutated, all_nonflat),
            "ihx_r2_hexe_shift_alone_falsified",
        )

    def test_incomplete_extra_and_mutated_direction_or_nonflat_maps_are_falsified(self):
        directions = dict(contract.PAPER_DIRECTIONS)
        nonflat = {name: True for name in directions}
        cases = []
        incomplete_directions = dict(directions)
        incomplete_directions.pop("reactor")
        cases.append((incomplete_directions, nonflat))
        extra_directions = dict(directions, invented=("rise",))
        cases.append((extra_directions, nonflat))
        incomplete_nonflat = dict(nonflat)
        incomplete_nonflat.pop("turbine")
        cases.append((directions, incomplete_nonflat))
        false_nonflat = dict(nonflat)
        false_nonflat["electrical_paper_eta"] = False
        cases.append((directions, false_nonflat))
        non_boolean_nonflat = dict(nonflat)
        non_boolean_nonflat["reactor"] = 1
        cases.append((directions, non_boolean_nonflat))
        for candidate_directions, candidate_nonflat in cases:
            with self.subTest(
                directions=candidate_directions, nonflat=candidate_nonflat
            ):
                self.assertEqual(
                    contract.classify(True, candidate_directions, candidate_nonflat),
                    "ihx_r2_hexe_shift_alone_falsified",
                )

    def test_invalid_interface_types_raise_named_error_in_normal_and_optimized_modes(self):
        self.assertTrue(issubclass(contract.ContractError, Exception))
        with self.assertRaises(contract.ContractError):
            contract.classify(1, {}, {})
        with self.assertRaises(contract.ContractError):
            contract.classify(True, [], {})
        source = (
            "from tests import fig519_ihx_r2_hexe_contract as c\n"
            "try:\n"
            "    c.classify(1, {}, {})\n"
            "except c.ContractError:\n"
            "    print('CONTRACT_ERROR_PASS')\n"
            "else:\n"
            "    raise SystemExit('validation disappeared')\n"
        )
        for optimized in (False, True):
            command = [sys.executable]
            if optimized:
                command.append("-O")
            result = subprocess.run(
                command + ["-c", source],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "CONTRACT_ERROR_PASS\n")

    def test_production_module_contains_no_assert_statement(self):
        tree = ast.parse(Path(contract.__file__).read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
