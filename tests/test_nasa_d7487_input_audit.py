from __future__ import annotations

import csv
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
AUDIT_PATH = (
    ROOT
    / "data"
    / "provenance"
    / "compressor_map"
    / "nasa_tn_d7487"
    / "target_input_audit.csv"
)

EXPECTED_FIELDS = {
    "gam",
    "rgas",
    "pop",
    "top",
    "n",
    "dit",
    "mu0",
    "cf",
    "vovcr",
    "nvovcr",
    "drat",
    "lamx",
    "b2x",
    "z",
    "vldrr",
    "b2",
    "b1mfb",
    "ar",
    "block",
    "al3",
    "adth",
    "nondes",
    "splt",
    "al1mf",
    "curvh",
    "curvt",
    "chih",
    "chit",
}

REQUIRED_COLUMNS = {
    "name",
    "value",
    "unit",
    "status",
    "source_class",
    "source_document",
    "source_location",
    "derivation",
    "notes",
}


class TargetInputAuditTests(unittest.TestCase):
    def load_rows(self) -> list[dict[str, str]]:
        self.assertTrue(AUDIT_PATH.is_file(), f"Missing D-7487 audit: {AUDIT_PATH}")
        with AUDIT_PATH.open(newline="", encoding="utf-8") as stream:
            reader = csv.DictReader(stream)
            self.assertEqual(set(reader.fieldnames or ()), REQUIRED_COLUMNS)
            return list(reader)

    def test_audit_has_each_d7487_input_exactly_once(self) -> None:
        rows = self.load_rows()
        names = [row["name"] for row in rows]

        self.assertEqual(len(names), 28)
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(set(names), EXPECTED_FIELDS)

    def test_populated_values_are_traceable_and_missing_values_are_blank(self) -> None:
        rows = self.load_rows()
        allowed_statuses = {"direct", "calculated", "algorithm_control", "missing"}
        allowed_source_classes = {
            "published_literal",
            "published_figure",
            "repeatable_calculation",
            "algorithm_definition",
            "unresolved",
        }

        for row in rows:
            with self.subTest(name=row["name"]):
                self.assertIn(row["status"], allowed_statuses)
                self.assertIn(row["source_class"], allowed_source_classes)
                if row["status"] == "missing":
                    self.assertEqual(row["value"], "")
                    self.assertEqual(row["source_class"], "unresolved")
                    self.assertTrue(row["notes"].strip())
                else:
                    self.assertTrue(row["value"].strip())
                    self.assertNotEqual(row["source_class"], "unresolved")
                    self.assertTrue(row["source_document"].strip())
                    self.assertTrue(row["source_location"].strip())
                    self.assertTrue(row["derivation"].strip())

                combined = " ".join(row.values()).lower()
                self.assertNotIn("sample_input.json", combined)
                self.assertNotIn("assumed", combined)
                self.assertNotIn("guessed", combined)


if __name__ == "__main__":
    unittest.main()
