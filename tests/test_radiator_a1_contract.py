import math
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from tests import radiator_a1_contract as contract


BASELINE_RELATIVE = (
    "tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx"
)
BASELINE_SHA256_LITERAL = (
    "0532e9ddf2deb7ef5e40cc1b8e619c44"
    "ea7afd36b00d807d118f4cd812a5a391"
)
PROTECTED_RELATIVE = (
    "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"
)
PROTECTED_SHA256_LITERAL = (
    "496e4bbbbe5786bbb21b63d3c320dcfd"
    "f3c741935736624ed2912ab81afc9a0a"
)
SOURCE_HASHES_LITERAL = {
    "sources/NASA-TM-2007-215003-Juhasz-2007.pdf": (
        "2f1a8b19be7deea95a43e6d30468e234"
        "e48e9955eed1dc5005b0efa3119fd732"
    ),
    "sources/NASA-TM-2008-215420-Juhasz-2008.pdf": (
        "eb332a4e13d75406c47f72d698f11e10"
        "708d1f230041aecdda591a86fae7e10f"
    ),
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf": (
        "983bfc23712221f30202a47875cbe34c"
        "9559edf79b9c332aa20931b6075e4e7a"
    ),
}
CURVE_EVIDENCE_HASHES_LITERAL = {
    "tmp/steady53_curves_20260828/radiator_scan_points.csv": (
        "6aed804bf1ac57832055dab34483bdcb2"
        "5567a5b902e5b3c6b85cb7129e8849b"
    ),
    "tmp/steady53_curves_20260828/radiator_scan_provenance.json": (
        "fe35a863731ff5394095f5d268a988cb"
        "45120a1382db9fd53bc0599e8f98e0cd"
    ),
}


class RadiatorA1ContractTests(unittest.TestCase):
    def test_primary_paths_and_hashes_are_locked_to_literals(self):
        self.assertEqual(
            str(contract.BASELINE.relative_to(contract.ROOT)),
            BASELINE_RELATIVE,
        )
        self.assertEqual(contract.BASELINE_SHA256, BASELINE_SHA256_LITERAL)
        self.assertEqual(
            str(contract.PROTECTED.relative_to(contract.ROOT)),
            PROTECTED_RELATIVE,
        )
        self.assertEqual(contract.PROTECTED_SHA256, PROTECTED_SHA256_LITERAL)

    def test_source_hashes_are_complete_literal_contract(self):
        self.assertEqual(contract.SOURCE_HASHES, SOURCE_HASHES_LITERAL)

    def test_curve_evidence_hashes_are_complete_literal_contract(self):
        self.assertEqual(
            contract.CURVE_EVIDENCE_HASHES,
            CURVE_EVIDENCE_HASHES_LITERAL,
        )

    def test_parameter_axes_define_exactly_96_literal_combinations(self):
        branches = tuple(
            (value.branch_id, value.kappa_kg_m2, value.maturity)
            for value in contract.BRANCHES
        )
        flows = tuple(
            (value.case_id, value.value, value.unit, value.evidence)
            for value in contract.FLOWS
        )
        emissivities = tuple(
            (value.case_id, value.value, value.unit, value.evidence)
            for value in contract.EMISSIVITIES
        )
        sinks = tuple(
            (value.case_id, value.value, value.unit, value.evidence)
            for value in contract.SINKS
        )
        h_anchors = tuple(
            (value.case_id, value.value, value.unit, value.evidence)
            for value in contract.H_ANCHORS
        )
        self.assertEqual(branches, (
            ("T300_fd1p45_one", 4.22, "tested"),
            ("T300_fd1p45_two", 2.11, "tested"),
            ("P95_WG_fd1p45_two", 1.57, "built_not_tested"),
            ("APG_fd1p00_two", 0.92, "projected"),
        ))
        self.assertEqual(flows, (
            ("project_flow", 6.95, "kg/s", "project_boundary"),
            ("energy_closure_flow", 7.134146337, "kg/s", "conditional"),
        ))
        self.assertEqual(emissivities, (
            ("NASA_surface_0p85", 0.85, "1", "other_system_anchor"),
            ("NASA_surface_0p90", 0.90, "1", "other_system_anchor"),
        ))
        self.assertEqual(sinks, (
            ("NASA_120_example", 200.0, "K", "other_system_anchor"),
            ("legacy_project", 225.0, "K", "project_boundary"),
        ))
        self.assertEqual(h_anchors, (
            (
                "legacy_inverse",
                9.755,
                "W/(m^2*K)",
                "conditional_inverse",
            ),
            (
                "NASA_120_low",
                200.0,
                "W/(m^2*K)",
                "other_system_anchor",
            ),
            (
                "NASA_120_high",
                600.0,
                "W/(m^2*K)",
                "other_system_anchor",
            ),
        ))
        self.assertEqual(
            math.prod(tuple(map(len, (
                branches,
                flows,
                emissivities,
                sinks,
                h_anchors,
            )))),
            96,
        )

    def test_roles_have_exact_ids_and_fixed_parameter_tuples(self):
        roles = tuple(
            (role.role_id, *role.as_tuple()) for role in contract.ROLES
        )
        self.assertEqual(roles, (
            ("legacy_transfer", 6.95, 0.90, 225.0, 9.755, 900.0),
            (
                "conservative_source",
                7.134146337,
                0.85,
                225.0,
                200.0,
                1000.0,
            ),
            ("optimistic_source", 6.95, 0.90, 200.0, 600.0, 777.0),
        ))

    def test_source_contract_verifies_hashes_and_preserves_status_gates(self):
        result = contract.verify_source_contract()
        self.assertEqual(result["baseline_path"], BASELINE_RELATIVE)
        self.assertEqual(result["baseline_sha256"], BASELINE_SHA256_LITERAL)
        self.assertEqual(result["source_hashes"], SOURCE_HASHES_LITERAL)
        self.assertEqual(
            result["curve_evidence_hashes"],
            CURVE_EVIDENCE_HASHES_LITERAL,
        )
        self.assertEqual(result["protected_manifest"], PROTECTED_RELATIVE)
        self.assertEqual(result["protected_count"], 34)
        self.assertFalse(result["paper_reproduced"])
        self.assertFalse(result["formal_promotion"])

    def test_baseline_hash_mismatch_raises_contract_error_under_optimization(self):
        wrong_hash = "0" * 64
        with mock.patch.object(contract, "BASELINE_SHA256", wrong_hash):
            with self.assertRaises(contract.A1ContractError) as raised:
                contract.verify_source_contract()
        message = str(raised.exception)
        self.assertIn("category=baseline", message)
        self.assertIn(f"path={contract.BASELINE}", message)
        self.assertIn(f"expected={wrong_hash}", message)
        self.assertIn(f"actual={BASELINE_SHA256_LITERAL}", message)
        self.assertEqual(contract.BASELINE_SHA256, BASELINE_SHA256_LITERAL)

    def test_verify_hashes_rejects_wrong_hash_without_real_evidence_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            evidence = Path(folder) / "synthetic-evidence.bin"
            evidence.write_bytes(b"synthetic A1 contract evidence")
            wrong_hash = "0" * 64
            with self.assertRaises(contract.A1ContractError) as raised:
                contract._verify_hashes({str(evidence): wrong_hash})
            message = str(raised.exception)
            self.assertIn(f"path={evidence}", message)
            self.assertIn(f"expected={wrong_hash}", message)
            self.assertIn("actual=", message)

    def test_patch_block_actions_are_exact_literal_mapping(self):
        self.assertEqual(contract.PATCH_BLOCKS, {
            "Constant": "Value",
            "rediator/Tho": "replace_with_integral_enthalpy_function",
            "rediator/T_env": "Value",
            "rediator/Subsystem/Constant": "Value",
            "rediator/Subsystem/Constant2": "Value",
            "rediator/Subsystem/Constant3": "Value",
            "rediator/Subsystem/Constant4": "Value",
            "rediator/Subsystem/Constant5": "Value",
        })


if __name__ == "__main__":
    unittest.main(verbosity=2)
