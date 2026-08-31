import unittest
from pathlib import Path

from tests import publish_f8bcd83_runtime as publisher


ROOT = Path(__file__).resolve().parents[1]


class PublishF8bcd83RuntimeTests(unittest.TestCase):
    def test_expected_hashes_match_literal_contract(self):
        self.assertEqual(
            publisher.EXPECTED_SHA256,
            {
                "runtime/HeXe_property_simulink.m": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2",
                "runtime/Lithium_property_simulink.m": "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f",
                "runtime/hexe_compressor_lookup.mat": "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579",
                "runtime/radiator_table.mat": "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304",
                "runtime/turbine_table1.mat": "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d",
                "runtime/turbine_table2.mat": "6ff94cce373b67a143e9a992ec693ef17a910440eb4218cdf796543ba48c8a38",
                "runtime/start.m": "0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec",
                "runtime/sys_param_rad_fixed.m": "bbdcf30dcd2fd7859092af0d85a79ed5dabc6da6c298f1d064ed11d612f30d5b",
                "runtime/paper54_constants.m": "545e9b7653b4a47759e746e33a52a184e69c1455911929ce096d1a6eb6558345",
                "runtime/tests/steady53/create_component_harness.m": "0f536ffaff9345e5cc85af37bdfa6a385db0e54bd7f0adcedbd81b95fdcd2dd0",
                "runtime/tests/steady53/steady53_component_boundaries.m": "8e2092ef2a9a183a7e4b3cd04fc05949d3648de873833391f262eed13f72ed26",
                "runtime/tests/steady53/steady53_signal_manifest.m": "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd",
                "runtime/tests/steady53/reset_steady53_property_warning_state.m": "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0",
                "runtime/tests/steady53/run_steady53_case.m": "6ec6f09c9d6ef32520b28248588d5ba0b31f3cf99acd0f6b0bc5bdff7f45e79a",
            },
        )

    def test_verify_tree_rejects_missing_runtime(self):
        with self.assertRaises(publisher.PublicationError):
            publisher.verify_tree(ROOT / "tmp/deliberately_missing_runtime")

    def test_status_prevents_formal_or_paper_claims(self):
        self.assertEqual(
            publisher.STATUS,
            {
                "source_commit": "f8bcd833e816eb681982b7dd04364e4b856948e3",
                "paper_reproduced": False,
                "formal_promotion": False,
            },
        )


if __name__ == "__main__":
    unittest.main()
