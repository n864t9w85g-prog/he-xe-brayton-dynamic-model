import math
import unittest

from tests import radiator_a1_contract as contract


class RadiatorA1ContractTests(unittest.TestCase):
    def test_parameter_axes_define_exactly_96_combinations(self):
        self.assertEqual(len(contract.BRANCHES), 4)
        self.assertEqual(len(contract.FLOWS), 2)
        self.assertEqual(len(contract.EMISSIVITIES), 2)
        self.assertEqual(len(contract.SINKS), 2)
        self.assertEqual(len(contract.H_ANCHORS), 3)
        self.assertEqual(math.prod((
            len(contract.BRANCHES),
            len(contract.FLOWS),
            len(contract.EMISSIVITIES),
            len(contract.SINKS),
            len(contract.H_ANCHORS),
        )), 96)

    def test_roles_have_exact_ids_and_fixed_parameter_tuples(self):
        roles = {role.role_id: role.as_tuple() for role in contract.ROLES}
        self.assertEqual(set(roles), {
            "legacy_transfer",
            "conservative_source",
            "optimistic_source",
        })
        self.assertEqual(roles["legacy_transfer"],
                         (6.95, 0.90, 225.0, 9.755, 900.0))
        self.assertEqual(roles["conservative_source"],
                         (7.134146337, 0.85, 225.0, 200.0, 1000.0))
        self.assertEqual(roles["optimistic_source"],
                         (6.95, 0.90, 200.0, 600.0, 777.0))

    def test_source_contract_verifies_hashes_and_preserves_status_gates(self):
        result = contract.verify_source_contract()
        self.assertEqual(result["baseline_sha256"],
                         contract.BASELINE_SHA256)
        self.assertEqual(result["protected_count"], 34)
        self.assertFalse(result["paper_reproduced"])
        self.assertFalse(result["formal_promotion"])

    def test_patch_block_set_is_exact(self):
        self.assertEqual(set(contract.PATCH_BLOCKS), {
            "Constant",
            "rediator/Tho",
            "rediator/T_env",
            "rediator/Subsystem/Constant",
            "rediator/Subsystem/Constant2",
            "rediator/Subsystem/Constant3",
            "rediator/Subsystem/Constant4",
            "rediator/Subsystem/Constant5",
        })


if __name__ == "__main__":
    unittest.main(verbosity=2)
