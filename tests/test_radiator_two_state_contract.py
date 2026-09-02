import csv
import math
import tempfile
import unittest
from pathlib import Path

from tests import radiator_two_state_contract as contract


class RadiatorTwoStateContractTests(unittest.TestCase):
    @staticmethod
    def _rows():
        with contract.POINTS_CSV.open(encoding="utf-8", newline="") as handle:
            return list(csv.reader(handle))

    def test_repository_input_and_case_contract(self):
        evidence = contract.verify_input_contract()
        self.assertEqual(evidence.header, contract.EXPECTED_HEADER)
        self.assertEqual(len(evidence.samples), 12)
        self.assertEqual(evidence.samples[0].time_s, 4.62962962962963)
        self.assertEqual(evidence.samples[-1].time_s, 187.96296296296296)
        self.assertEqual(tuple(case.case_id for case in contract.CASES), (
            "project_flow__inlet_cp",
            "project_flow__integral_enthalpy",
            "energy_closure_flow__inlet_cp",
            "energy_closure_flow__integral_enthalpy",
        ))
        self.assertEqual(set(evidence.source_hashes), set(contract.INPUT_HASHES))

    def test_protected_snapshot_has_exact_order_and_digests(self):
        snapshot = contract.snapshot_protected_files()
        self.assertEqual(tuple(snapshot), contract.PROTECTED_RELATIVE_PATHS)
        self.assertTrue(all(len(digest) == 64 for digest in snapshot.values()))

    def test_modified_curve_is_rejected_by_frozen_digest(self):
        with tempfile.TemporaryDirectory() as folder:
            temporary = Path(folder) / "points.csv"
            rows = self._rows()
            rows[1][2] = "nan"
            with temporary.open("w", newline="", encoding="utf-8") as handle:
                csv.writer(handle).writerows(rows)
            with self.assertRaisesRegex(contract.EvidenceContractError, "curve_sha256"):
                contract.parse_points(temporary, contract.INPUT_HASHES["points_csv"])

    def test_structurally_incomplete_curve_is_rejected_without_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            temporary = Path(folder) / "points.csv"
            rows = self._rows()
            rows.pop(1)
            with temporary.open("w", newline="", encoding="utf-8") as handle:
                csv.writer(handle).writerows(rows)
            with self.assertRaisesRegex(contract.EvidenceContractError, "rows"):
                contract.parse_points(temporary, expected_sha256=None)

    def test_malformed_header_nonfinite_and_nonincreasing_time_are_rejected(self):
        rows = self._rows()
        for label, mutate in (
            ("header", lambda data: data.__setitem__(0, ["bad"])),
            ("nonfinite", lambda data: data[1].__setitem__(4, "nan")),
            ("time", lambda data: data[2].__setitem__(3, data[1][3])),
        ):
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                temporary = Path(folder) / "points.csv"
                data = [row[:] for row in rows]
                mutate(data)
                with temporary.open("w", newline="", encoding="utf-8") as handle:
                    csv.writer(handle).writerows(data)
                with self.assertRaises(contract.EvidenceContractError):
                    contract.parse_points(temporary, expected_sha256=None)


if __name__ == "__main__":
    unittest.main()
