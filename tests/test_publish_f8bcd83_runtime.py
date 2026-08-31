import csv
import hashlib
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import publish_f8bcd83_runtime as publisher


ROOT = Path(__file__).resolve().parents[1]


class PublishF8bcd83RuntimeTests(unittest.TestCase):
    @staticmethod
    def _hash(data):
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def _write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

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

    def test_publish_file_rejects_source_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            baseline.mkdir()
            real_source = temporary_root / "real-source"
            self._write(real_source, b"trusted")
            source_link = temporary_root / "source-link"
            source_link.symlink_to(real_source)
            destination = baseline / "runtime/file"

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(
                        source_link, destination, self._hash(b"trusted")
                    )
            self.assertFalse(os.path.lexists(destination))

    def test_publish_file_rejects_matching_destination_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            destination = baseline / "runtime/file"
            source = temporary_root / "source"
            external = temporary_root / "external"
            self._write(source, b"trusted")
            self._write(external, b"trusted")
            destination.parent.mkdir(parents=True)
            destination.symlink_to(external)

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertTrue(destination.is_symlink())

    def test_publish_file_rejects_dangling_staging_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            destination = baseline / "runtime/file"
            staging = destination.with_name(f"{destination.name}.publishing")
            source = temporary_root / "source"
            dangling_target = temporary_root / "outside/missing"
            self._write(source, b"trusted")
            staging.parent.mkdir(parents=True)
            staging.symlink_to(dangling_target)

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertTrue(staging.is_symlink())
            self.assertFalse(os.path.lexists(dangling_target))

    def test_publish_file_rejects_symlinked_destination_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            external = temporary_root / "outside"
            baseline.mkdir()
            external.mkdir()
            (baseline / "runtime").symlink_to(external, target_is_directory=True)
            source = temporary_root / "source"
            self._write(source, b"trusted")
            destination = baseline / "runtime/file"

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertFalse(os.path.lexists(external / "file"))

    def test_publish_file_rejects_destination_outside_baseline(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            baseline.mkdir()
            source = temporary_root / "source"
            destination = temporary_root / "outside/file"
            self._write(source, b"trusted")

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertFalse(os.path.lexists(destination))

    def test_publish_file_first_publication_creates_real_regular_file(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            baseline.mkdir()
            source = temporary_root / "source"
            destination = baseline / "runtime/nested/file"
            self._write(source, b"trusted")

            with mock.patch.object(publisher, "BASELINE", baseline):
                publisher.publish_file(source, destination, self._hash(b"trusted"))

            destination_stat = destination.lstat()
            self.assertTrue(stat.S_ISREG(destination_stat.st_mode))
            self.assertFalse(destination.is_symlink())
            self.assertEqual(destination.read_bytes(), b"trusted")

    def test_publish_file_matching_regular_file_is_noop(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            source = temporary_root / "source"
            destination = baseline / "runtime/file"
            self._write(source, b"trusted")
            self._write(destination, b"trusted")
            original_mtime = 1_234_567_890_000_000_000
            os.utime(destination, ns=(original_mtime, original_mtime))

            with mock.patch.object(publisher, "BASELINE", baseline):
                publisher.publish_file(source, destination, self._hash(b"trusted"))

            self.assertEqual(destination.stat().st_mtime_ns, original_mtime)
            self.assertEqual(destination.read_bytes(), b"trusted")

    def test_publish_file_rejects_source_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            baseline.mkdir()
            source = temporary_root / "source"
            destination = baseline / "runtime/file"
            self._write(source, b"untrusted")

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertFalse(os.path.lexists(destination))

    def test_publish_file_rejects_destination_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            source = temporary_root / "source"
            destination = baseline / "runtime/file"
            self._write(source, b"trusted")
            self._write(destination, b"different")

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertEqual(destination.read_bytes(), b"different")

    def test_publish_file_rejects_stale_regular_staging_file(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            source = temporary_root / "source"
            destination = baseline / "runtime/file"
            staging = destination.with_name(f"{destination.name}.publishing")
            self._write(source, b"trusted")
            self._write(staging, b"stale")

            with mock.patch.object(publisher, "BASELINE", baseline):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, self._hash(b"trusted"))
            self.assertEqual(staging.read_bytes(), b"stale")

    def test_publish_file_preserves_attacker_replaced_staging_on_hash_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            baseline = temporary_root / "baseline"
            baseline.mkdir()
            source = temporary_root / "source"
            destination = baseline / "runtime/file"
            staging = destination.with_name(f"{destination.name}.publishing")
            attacker_target = temporary_root / "attacker-target"
            self._write(source, b"trusted")
            self._write(attacker_target, b"attacker")
            real_sha256 = publisher.sha256

            def replace_staging_then_fail(path):
                path = Path(path)
                if path == staging:
                    path.unlink()
                    path.symlink_to(attacker_target)
                    raise OSError("injected staging hash failure")
                return real_sha256(path)

            with mock.patch.object(publisher, "BASELINE", baseline):
                with mock.patch.object(
                    publisher, "sha256", side_effect=replace_staging_then_fail
                ):
                    with self.assertRaises(OSError):
                        publisher.publish_file(
                            source, destination, self._hash(b"trusted")
                        )
            self.assertTrue(staging.is_symlink())
            self.assertEqual(attacker_target.read_bytes(), b"attacker")

    def test_verify_tree_rejects_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            verification_root = Path(directory)
            relative = "runtime/file"
            self._write(verification_root / relative, b"different")
            with mock.patch.object(
                publisher, "EXPECTED_SHA256", {relative: self._hash(b"trusted")}
            ):
                with self.assertRaises(publisher.PublicationError):
                    publisher.verify_tree(verification_root)

    def test_verify_tree_rejects_file_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            verification_root = Path(directory)
            relative = "runtime/file"
            external = verification_root / "external"
            self._write(external, b"trusted")
            link = verification_root / relative
            link.parent.mkdir()
            link.symlink_to(external)
            with mock.patch.object(
                publisher, "EXPECTED_SHA256", {relative: self._hash(b"trusted")}
            ):
                with self.assertRaises(publisher.PublicationError):
                    publisher.verify_tree(verification_root)

    def test_committed_runtime_tree_and_manifest_match_contract(self):
        baseline = ROOT / "data/provenance/baselines/f8bcd83"
        manifest_path = baseline / "baseline_manifest.csv"
        with manifest_path.open(newline="", encoding="utf-8") as stream:
            runtime_rows = [
                row
                for row in csv.DictReader(stream)
                if row["git_path"].startswith("runtime/")
            ]

        expected_paths = set(publisher.EXPECTED_SHA256)
        actual_paths = {row["git_path"] for row in runtime_rows}
        disk_paths = {
            path.relative_to(baseline).as_posix()
            for path in (baseline / "runtime").rglob("*")
            if not stat.S_ISDIR(path.lstat().st_mode)
        }
        self.assertEqual(len(runtime_rows), 14)
        self.assertEqual(len(actual_paths), 14)
        self.assertEqual(actual_paths, expected_paths)
        self.assertEqual(disk_paths, expected_paths)

        for row in runtime_rows:
            relative = row["git_path"]
            path = baseline / relative
            self.assertEqual(int(row["size_bytes"]), path.stat().st_size)
            self.assertEqual(row["sha256"], publisher.sha256(path))
            self.assertEqual(row["sha256"], publisher.EXPECTED_SHA256[relative])
            self.assertEqual(
                row["source_commit"],
                "f8bcd833e816eb681982b7dd04364e4b856948e3",
            )
            expected_role = (
                "steady53_test_helper"
                if relative.startswith("runtime/tests/steady53/")
                else "steady53_runtime_dependency"
            )
            self.assertEqual(row["role"], expected_role)

    def test_cli_verify_only_prints_exact_pass_line(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "tests/publish_f8bcd83_runtime.py"), "--verify-only"],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "F8BCD83_RUNTIME_PASS; FILES=14; PAPER_REPRODUCED=false\n",
        )
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
