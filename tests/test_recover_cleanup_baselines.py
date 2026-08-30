from __future__ import annotations

import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

from tests import recover_cleanup_baselines as recovery


class RecoverCleanupBaselinesTests(unittest.TestCase):
    def make_source(self, root: Path) -> tuple[Path, str, dict[str, bytes]]:
        source = root / "source"
        source.mkdir()
        subprocess.run(["git", "init", "-q", str(source)], check=True)
        subprocess.run(
            ["git", "-C", str(source), "config", "user.name", "test"],
            check=True,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(source),
                "config",
                "user.email",
                "test@example.invalid",
            ],
            check=True,
        )
        payloads = {
            "final_steady_24a.slx": b"synthetic-steady-slx\x00",
            "final_dynamic_24a.slx": b"synthetic-dynamic-slx\x00",
        }
        for name, payload in payloads.items():
            (source / name).write_bytes(payload)
        subprocess.run(
            ["git", "-C", str(source), "add", "--all"], check=True
        )
        subprocess.run(
            ["git", "-C", str(source), "commit", "-qm", "fixture"],
            check=True,
        )
        commit = subprocess.run(
            ["git", "-C", str(source), "rev-parse", "HEAD"],
            check=True,
            stdout=subprocess.PIPE,
            text=True,
        ).stdout.strip()
        return source, commit, payloads

    def test_recover_publishes_exact_atomic_package(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            expected = {
                name: recovery.ExpectedBlob(
                    hashlib.sha256(payload).hexdigest(), len(payload), role
                )
                for (name, payload), role in zip(
                    payloads.items(),
                    ("a1_steady_authority", "historical_dynamic_only"),
                    strict=True,
                )
            }
            output = root / "out" / "f8bcd83"
            recovery.recover(
                source, commit, output, expected, "2026-08-31"
            )
            for name, payload in payloads.items():
                self.assertEqual((output / name).read_bytes(), payload)
            self.assertTrue((output / "baseline_manifest.csv").is_file())
            self.assertTrue((output / "README.md").is_file())
            for name in ("baseline_manifest.csv", "README.md"):
                text = (output / name).read_text(encoding="utf-8")
                self.assertFalse(
                    any(line.endswith(" ") for line in text.splitlines())
                )

    def test_wrong_hash_leaves_no_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            expected = {
                name: recovery.ExpectedBlob(
                    "0" * 64, len(payload), "invalid"
                )
                for name, payload in payloads.items()
            }
            output = root / "out" / "f8bcd83"
            with self.assertRaises(recovery.RecoveryError):
                recovery.recover(
                    source, commit, output, expected, "2026-08-31"
                )
            self.assertFalse(output.exists())

    def test_existing_mismatched_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source, commit, payloads = self.make_source(root)
            output = root / "out" / "f8bcd83"
            output.mkdir(parents=True)
            marker = output / "user-data.txt"
            marker.write_text("preserve\n", encoding="utf-8")
            expected = {
                name: recovery.ExpectedBlob(
                    hashlib.sha256(payload).hexdigest(), len(payload), "role"
                )
                for name, payload in payloads.items()
            }
            with self.assertRaises(FileExistsError):
                recovery.recover(
                    source, commit, output, expected, "2026-08-31"
                )
            self.assertEqual(marker.read_text(encoding="utf-8"), "preserve\n")

    def test_materialize_exact_file_is_idempotent_and_refuses_mismatch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "durable.slx"
            target = root / "tmp" / "compatibility.slx"
            source.write_bytes(b"exact-baseline")
            expected = hashlib.sha256(source.read_bytes()).hexdigest()
            recovery.materialize_exact_file(source, target, expected)
            recovery.materialize_exact_file(source, target, expected)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            target.write_bytes(b"different-user-file")
            with self.assertRaises(FileExistsError):
                recovery.materialize_exact_file(source, target, expected)
            self.assertEqual(target.read_bytes(), b"different-user-file")


if __name__ == "__main__":
    unittest.main(verbosity=2)
