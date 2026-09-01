from __future__ import annotations

import ast
import csv
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock

from tests import publish_fig518a_anchor_evidence as publisher


ROOT = Path(__file__).resolve().parents[1]
REAL_PDF = ROOT / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"
REAL_PAGE = ROOT / "tmp/steady53_recheck_20260827/paper-105.png"


class Figure518aAnchorEvidencePublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / "tmp")
        self.work = Path(self.temporary.name)
        self.pdf = self.work / "paper.pdf"
        self.page_parent = self.work / "source"
        self.page_parent.mkdir()
        self.page = self.page_parent / "paper-105.png"
        shutil.copyfile(REAL_PDF, self.pdf)
        shutil.copyfile(REAL_PAGE, self.page)
        self.durable_parent = self.work / "durable"
        self.durable_parent.mkdir()
        self.durable = self.durable_parent / "fig5_18a"

    def tearDown(self):
        self.temporary.cleanup()

    @contextmanager
    def patched(self):
        with mock.patch.multiple(
            publisher,
            PDF_PATH=self.pdf,
            SOURCE_PAGE=self.page,
            DURABLE_ROOT=self.durable,
        ):
            yield

    def snapshot(self):
        return {
            item.relative_to(self.work).as_posix(): (
                item.read_bytes(),
                item.stat().st_mtime_ns,
            )
            for item in self.work.rglob("*")
            if item.is_file() and not item.is_symlink()
        }

    def test_first_publication_has_exact_identity_inventory_and_byte_identical_page(self):
        with self.patched():
            publisher.publish()
            report = publisher.verify_only()
        self.assertEqual(report["anchor_K"], "1200.0000000000000")
        self.assertEqual(
            {item.name for item in self.durable.iterdir()},
            {"README.md", "source_page_105.png", "provenance.json", "manifest.csv"},
        )
        self.assertEqual((self.durable / "source_page_105.png").read_bytes(), self.page.read_bytes())
        provenance = json.loads((self.durable / "provenance.json").read_text())
        self.assertEqual(provenance["pdf_page"], 105)
        self.assertEqual(provenance["printed_page"], 90)
        self.assertEqual(provenance["figure"], "Figure 5.18(a)")
        self.assertEqual(provenance["anchor_K"], "1200.0000000000000")
        self.assertEqual(
            provenance["anchor_identity"],
            "figure_5_18a_t0_visual_proxy_not_author_initial_state",
        )
        self.assertIs(provenance["paper_reproduced"], False)
        self.assertIs(provenance["author_initial_state_identified"], False)
        self.assertIs(provenance["formal_promotion"], False)
        readme = (self.durable / "README.md").read_text(encoding="utf-8").lower()
        self.assertIn("visual proxy", readme)
        self.assertIn("not the author's t0", readme)
        self.assertIn("not a reproduced paper result", readme)
        self.assertIn("cannot authorize formal promotion", readme)

    def test_matching_publication_is_idempotent(self):
        with self.patched():
            publisher.publish()
            before = self.snapshot()
            publisher.publish()
            publisher.verify_only()
            after = self.snapshot()
        self.assertEqual(before, after)

    def test_staged_write_failure_is_retained_and_blocks_retry(self):
        calls = 0
        original = publisher._write_exclusive

        def fail_second(path, payload):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("injected staged-write failure")
            return original(path, payload)

        with self.patched(), mock.patch.object(
            publisher, "_write_exclusive", side_effect=fail_second
        ):
            with self.assertRaises(OSError):
                publisher.publish()
        staging = publisher.staging_path(self.durable)
        self.assertTrue(staging.is_dir())
        retained = {item.name: item.read_bytes() for item in staging.iterdir()}
        self.assertTrue(retained)
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        self.assertEqual(retained, {item.name: item.read_bytes() for item in staging.iterdir()})
        self.assertFalse(self.durable.exists())

    def test_preexisting_staging_and_conflicting_destination_are_rejected(self):
        staging = publisher.staging_path(self.durable)
        staging.mkdir()
        sentinel = staging / "preserve"
        sentinel.write_bytes(b"attacker-owned")
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        self.assertEqual(sentinel.read_bytes(), b"attacker-owned")
        shutil.rmtree(staging)
        self.durable.mkdir()
        conflict = self.durable / "README.md"
        conflict.write_bytes(b"conflict")
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
            with self.assertRaises(publisher.PublicationError):
                publisher.verify_only()
        self.assertEqual(conflict.read_bytes(), b"conflict")

    def test_source_destination_staging_and_ancestor_symlinks_are_rejected(self):
        real_pdf = self.pdf
        linked_pdf = self.work / "linked-paper.pdf"
        linked_pdf.symlink_to(real_pdf)
        with mock.patch.multiple(
            publisher,
            PDF_PATH=linked_pdf,
            SOURCE_PAGE=self.page,
            DURABLE_ROOT=self.durable,
        ):
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()

        real_source = self.work / "real-source"
        real_source.mkdir()
        shutil.copyfile(REAL_PAGE, real_source / "paper-105.png")
        linked_source = self.work / "linked-source"
        linked_source.symlink_to(real_source, target_is_directory=True)
        with mock.patch.multiple(
            publisher,
            PDF_PATH=self.pdf,
            SOURCE_PAGE=linked_source / "paper-105.png",
            DURABLE_ROOT=self.durable,
        ):
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()

        external = self.work / "external"
        external.mkdir()
        self.durable.symlink_to(external, target_is_directory=True)
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        self.durable.unlink()
        staging = publisher.staging_path(self.durable)
        staging.symlink_to(external, target_is_directory=True)
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        staging.unlink()

        real_parent = self.work / "real-durable-parent"
        real_parent.mkdir()
        linked_parent = self.work / "linked-durable-parent"
        linked_parent.symlink_to(real_parent, target_is_directory=True)
        with mock.patch.multiple(
            publisher,
            PDF_PATH=self.pdf,
            SOURCE_PAGE=self.page,
            DURABLE_ROOT=linked_parent / "fig5_18a",
        ):
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()

    def test_source_hash_mismatch_is_rejected_without_publication(self):
        self.page.write_bytes(self.page.read_bytes() + b"mutation")
        with self.patched():
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        self.assertFalse(self.durable.exists())
        self.assertFalse(publisher.staging_path(self.durable).exists())

    def test_extra_files_manifest_tamper_and_coordinated_tamper_are_rejected(self):
        with self.patched():
            publisher.publish()
            extra = self.durable / "extra.txt"
            extra.write_bytes(b"extra")
            with self.assertRaises(publisher.PublicationError):
                publisher.verify_only()
            extra.unlink()
            manifest = self.durable / "manifest.csv"
            original_manifest = manifest.read_bytes()
            manifest.write_bytes(original_manifest + b"tamper")
            with self.assertRaises(publisher.PublicationError):
                publisher.verify_only()
            manifest.write_bytes(original_manifest)

            readme = self.durable / "README.md"
            readme.write_bytes(readme.read_bytes() + b"coordinated tamper\n")
            rows = list(csv.DictReader(io.StringIO(original_manifest.decode("utf-8"))))
            row = next(item for item in rows if item["path"] == "README.md")
            row["bytes"] = str(readme.stat().st_size)
            row["sha256"] = hashlib.sha256(readme.read_bytes()).hexdigest()
            manifest.write_bytes(publisher.manifest_bytes(rows))
            with self.assertRaises(publisher.PublicationError):
                publisher.verify_only()

    def test_verify_only_recomputes_sources_and_writes_nothing(self):
        with self.patched():
            publisher.publish()
            before = self.snapshot()
            publisher.verify_only()
            self.assertEqual(before, self.snapshot())
            self.pdf.write_bytes(self.pdf.read_bytes() + b"mutated PDF")
            after_mutation = self.snapshot()
            with self.assertRaises(publisher.PublicationError):
                publisher.verify_only()
            self.assertEqual(after_mutation, self.snapshot())

    def test_cli_stdout_and_validation_hold_in_normal_and_optimized_modes(self):
        code = (
            "from pathlib import Path\n"
            "from tests import publish_fig518a_anchor_evidence as p\n"
            f"p.PDF_PATH=Path({str(self.pdf)!r})\n"
            f"p.SOURCE_PAGE=Path({str(self.page)!r})\n"
            f"p.DURABLE_ROOT=Path({str(self.durable)!r})\n"
            "p.main([])\n"
            "p.main(['--verify-only'])\n"
        )
        for optimized in (False, True):
            if self.durable.exists():
                shutil.rmtree(self.durable)
            command = [sys.executable]
            if optimized:
                command.append("-O")
            result = subprocess.run(
                command + ["-c", code], cwd=ROOT, capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout,
                "FIG518A_ANCHOR_PUBLISH_PASS\nFIG518A_ANCHOR_VERIFY_PASS\n",
            )

    def test_production_module_contains_no_assert_statement(self):
        tree = ast.parse(Path(publisher.__file__).read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))


if __name__ == "__main__":
    unittest.main(verbosity=2)
