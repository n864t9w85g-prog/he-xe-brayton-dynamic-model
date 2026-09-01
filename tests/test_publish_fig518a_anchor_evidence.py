from __future__ import annotations

import ast
import csv
import hashlib
import io
import json
import multiprocessing
import os
import re
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
REAL_PAGE = ROOT / "data/provenance/steady53/fig5_18a/source_page_105.png"


def _replace_staging_process(staging, preserved, go, done, token):
    go.wait(10)
    os.rename(staging, preserved)
    os.mkdir(staging, 0o700)
    (Path(staging) / "attacker-token").write_bytes(token)
    done.set()


def _replace_parent_process(parent, preserved, external, staging_name, go, done):
    go.wait(10)
    os.rename(parent, preserved)
    os.symlink(external, parent, target_is_directory=True)
    os.mkdir(Path(external) / staging_name, 0o700)
    done.set()


def _replace_staging_then_destination_process(
    staging,
    durable,
    preserved_staging,
    preserved_first_destination,
    stage_go,
    stage_done,
    quarantine_go,
    quarantine_done,
    first_token,
    second_token,
):
    stage_go.wait(10)
    os.rename(staging, preserved_staging)
    os.mkdir(staging, 0o700)
    (Path(staging) / "first-competitor-token").write_bytes(first_token)
    stage_done.set()
    quarantine_go.wait(10)
    os.rename(durable, preserved_first_destination)
    os.mkdir(durable, 0o700)
    (Path(durable) / "second-competitor-token").write_bytes(second_token)
    quarantine_done.set()


class Figure518aAnchorEvidencePublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.work = Path(self.temporary.name).resolve()
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
            with self.assertRaises(publisher.PublicationError) as raised:
                publisher.publish()
        self.assertIsInstance(raised.exception.__cause__, OSError)
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

    def test_verify_only_wraps_filesystem_errors_as_publication_error(self):
        with self.patched():
            publisher.publish()
            injected = OSError("injected verify filesystem failure")
            with mock.patch.object(
                publisher, "_verify_directory", side_effect=injected
            ):
                with self.assertRaises(publisher.PublicationError) as raised:
                    publisher.verify_only()
        self.assertIs(raised.exception.__cause__, injected)

    def test_existing_publication_does_not_require_ignored_source_page(self):
        with self.patched():
            publisher.publish()
            before = self.snapshot()
            missing = self.work / "ignored-tmp-source-is-absent.png"
            with mock.patch.object(publisher, "SOURCE_PAGE", missing):
                publisher.publish()
                publisher.verify_only()
            self.assertEqual(before, self.snapshot())

    def test_initial_publication_still_requires_the_hash_contracted_source_page(self):
        missing = self.work / "missing-source-page.png"
        with mock.patch.multiple(
            publisher,
            PDF_PATH=self.pdf,
            SOURCE_PAGE=missing,
            DURABLE_ROOT=self.durable,
        ):
            with self.assertRaises(publisher.PublicationError):
                publisher.publish()
        self.assertFalse(self.durable.exists())

    def test_active_staging_replacement_is_quarantined_without_invalid_destination(self):
        context = multiprocessing.get_context("fork")
        go = context.Event()
        done = context.Event()
        staging = publisher.staging_path(self.durable)
        preserved = self.durable_parent / ".fig5_18a.original-owned-staging"
        token = b"active attacker replacement must be preserved"
        competitor = context.Process(
            target=_replace_staging_process,
            args=(staging, preserved, go, done, token),
        )
        original = publisher._exclusive_rename

        def replace_before_rename(*args):
            go.set()
            if not done.wait(10):
                raise RuntimeError("competitor did not replace staging")
            return original(*args)

        competitor.start()
        try:
            with self.patched(), mock.patch.object(
                publisher, "_exclusive_rename", side_effect=replace_before_rename
            ):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish()
        finally:
            competitor.join(10)
            if competitor.is_alive():
                competitor.terminate()
                competitor.join()
        self.assertEqual(competitor.exitcode, 0)
        self.assertFalse(self.durable.exists(), "invalid durable destination remained")
        preserved_tokens = [
            item for item in self.durable_parent.rglob("attacker-token")
            if item.is_file() and item.read_bytes() == token
        ]
        self.assertEqual(len(preserved_tokens), 1, "attacker replacement was unlinked")
        self.assertTrue(preserved.is_dir(), "owned staging moved by attacker was lost")

    def test_second_replacement_cannot_leave_a_false_inode_quarantine_label(self):
        context = multiprocessing.get_context("fork")
        stage_go = context.Event()
        stage_done = context.Event()
        quarantine_go = context.Event()
        quarantine_done = context.Event()
        staging = publisher.staging_path(self.durable)
        preserved_staging = self.durable_parent / ".fig5_18a.original-owned-staging"
        preserved_first = self.durable_parent / ".fig5_18a.first-competitor-preserved"
        first_token = b"first competing directory"
        second_token = b"second competing directory"
        competitor = context.Process(
            target=_replace_staging_then_destination_process,
            args=(
                staging,
                self.durable,
                preserved_staging,
                preserved_first,
                stage_go,
                stage_done,
                quarantine_go,
                quarantine_done,
                first_token,
                second_token,
            ),
        )
        original = publisher._exclusive_rename
        rename_call = 0

        def replace_at_both_rename_boundaries(*args):
            nonlocal rename_call
            rename_call += 1
            if rename_call == 1:
                stage_go.set()
                if not stage_done.wait(10):
                    raise RuntimeError("competitor did not replace staging")
            elif rename_call == 2:
                quarantine_go.set()
                if not quarantine_done.wait(10):
                    raise RuntimeError("competitor did not replace quarantine source")
            return original(*args)

        competitor.start()
        try:
            with self.patched(), mock.patch.object(
                publisher,
                "_exclusive_rename",
                side_effect=replace_at_both_rename_boundaries,
            ):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish()
        finally:
            competitor.join(10)
            if competitor.is_alive():
                competitor.terminate()
                competitor.join()
        self.assertEqual(competitor.exitcode, 0)
        self.assertFalse(self.durable.exists(), "invalid durable destination remained")
        self.assertEqual(
            (preserved_first / "first-competitor-token").read_bytes(), first_token
        )
        quarantines = [
            entry for entry in self.durable_parent.iterdir()
            if entry.name.startswith(".fig5_18a.rejected-")
        ]
        self.assertEqual(len(quarantines), 1)
        quarantine = quarantines[0]
        self.assertEqual(
            (quarantine / "second-competitor-token").read_bytes(), second_token
        )
        identity_label = re.fullmatch(
            r"\.fig5_18a\.rejected-([0-9a-f]+)-([0-9a-f]+)-[0-9]+",
            quarantine.name,
        )
        if identity_label is not None:
            quarantined_stat = quarantine.lstat()
            self.assertEqual(
                (int(identity_label.group(1), 16), int(identity_label.group(2), 16)),
                (quarantined_stat.st_dev, quarantined_stat.st_ino),
                "quarantine name claims the inode sampled before a competing swap",
            )

    def test_active_parent_replacement_cannot_redirect_staged_writes(self):
        context = multiprocessing.get_context("fork")
        go = context.Event()
        done = context.Event()
        preserved_parent = self.work / "preserved-owned-parent"
        external = self.work / "attacker-external"
        external.mkdir()
        staging_name = publisher.staging_path(self.durable).name
        competitor = context.Process(
            target=_replace_parent_process,
            args=(
                self.durable_parent,
                preserved_parent,
                external,
                staging_name,
                go,
                done,
            ),
        )
        original = publisher._write_exclusive
        first = True

        def replace_parent_before_first_write(*args):
            nonlocal first
            if first:
                first = False
                go.set()
                if not done.wait(10):
                    raise RuntimeError("competitor did not replace parent")
            return original(*args)

        competitor.start()
        try:
            with self.patched(), mock.patch.object(
                publisher,
                "_write_exclusive",
                side_effect=replace_parent_before_first_write,
            ):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish()
        finally:
            competitor.join(10)
            if competitor.is_alive():
                competitor.terminate()
                competitor.join()
        self.assertEqual(competitor.exitcode, 0)
        self.assertTrue(self.durable_parent.is_symlink(), "attacker ancestor was unlinked")
        self.assertFalse((external / "fig5_18a").exists())
        escaped_artifacts = {
            item.name for item in external.rglob("*") if item.is_file()
        } & set(publisher.ARTIFACT_NAMES)
        self.assertEqual(escaped_artifacts, set(), "payload escaped the held parent tree")

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
