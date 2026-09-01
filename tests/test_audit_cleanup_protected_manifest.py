from __future__ import annotations

import csv
import hashlib
from pathlib import Path
import tempfile
import unittest

from tests import audit_cleanup_protected_manifest as audit


class AuditCleanupProtectedManifestTests(unittest.TestCase):
    def write_manifest(
        self, path: Path, rows: list[tuple[Path, str]]
    ) -> None:
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("paths", "hashes"))
            for original, expected_hash in rows:
                writer.writerow((str(original), expected_hash))

    def test_resolves_present_durable_and_unresolved_rows(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            present = root / "present.bin"
            present.write_bytes(b"present")
            durable = root / "durable.bin"
            durable.write_bytes(b"durable")
            manifest = root / "protected.csv"
            present_hash = hashlib.sha256(present.read_bytes()).hexdigest()
            durable_hash = hashlib.sha256(durable.read_bytes()).hexdigest()
            missing_hash = hashlib.sha256(b"missing").hexdigest()
            self.write_manifest(
                manifest,
                [
                    (present, present_hash),
                    (root / "missing-but-durable.bin", durable_hash),
                    (root / "unresolved.bin", missing_hash),
                ],
            )

            rows, summary = audit.resolve_manifest(manifest, [durable])

            self.assertEqual(
                rows[0]["resolution"], "original_path_hash_match"
            )
            self.assertEqual(
                rows[1]["resolution"], "durable_hash_equivalent"
            )
            self.assertEqual(rows[2]["resolution"], "unresolved")
            self.assertEqual(summary["row_count"], 3)
            self.assertEqual(summary["resolved_count"], 2)
            self.assertEqual(summary["unresolved_count"], 1)

    def test_duplicate_durable_hash_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            first = root / "first.bin"
            second = root / "second.bin"
            first.write_bytes(b"same")
            second.write_bytes(b"same")
            expected_hash = hashlib.sha256(b"same").hexdigest()
            manifest = root / "protected.csv"
            self.write_manifest(
                manifest, [(root / "missing.bin", expected_hash)]
            )

            with self.assertRaises(audit.AuditError):
                audit.resolve_manifest(manifest, [first, second])

    def test_existing_hash_mismatch_is_not_hidden_by_durable_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = root / "original.bin"
            original.write_bytes(b"changed")
            durable = root / "durable.bin"
            durable.write_bytes(b"expected")
            expected_hash = hashlib.sha256(b"expected").hexdigest()
            manifest = root / "protected.csv"
            self.write_manifest(manifest, [(original, expected_hash)])

            rows, summary = audit.resolve_manifest(manifest, [durable])

            self.assertEqual(rows[0]["original_state"], "hash_mismatch")
            self.assertEqual(rows[0]["resolution"], "unresolved")
            self.assertEqual(summary["unresolved_count"], 1)

    def test_duplicate_manifest_path_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = root / "missing.bin"
            expected_hash = hashlib.sha256(b"missing").hexdigest()
            manifest = root / "protected.csv"
            self.write_manifest(
                manifest,
                [(original, expected_hash), (original, expected_hash)],
            )

            with self.assertRaises(audit.AuditError):
                audit.resolve_manifest(manifest, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
