import csv
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import publish_fig518d_evidence as publisher


EXPECTED_REPORT = {
    "paper_point_count": 12,
    "ic_mat_count": 2,
    "offline_row_count": 96,
    "representative_count": 12,
    "eligible_count": 11,
    "representative_manifest_count": 11,
    "ineligible_without_manifest": ["T300_fd1p45_one__legacy_transfer"],
    "stage_500_passed": 3,
    "stage_14000_passed": 3,
    "a1_identifiability": "multiple_conditionally_feasible_packages",
    "paper_reproduced": False,
    "formal_promotion": False,
}

README_MACHINE_LINES = (
    "paper_reproduced = false",
    "author_implementation_status = not_uniquely_identified",
    "current_equation_family_status = incompatible_with_both_digitized_curves",
    "a1_identifiability = multiple_conditionally_feasible_packages",
    "formal_promotion = false",
)


class PublishFigure518dEvidenceTests(unittest.TestCase):
    def _publish_to_temporary_root(self, directory):
        durable_root = Path(directory) / "fig5_18d"
        with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
            publisher.publish_all()
        return durable_root

    def test_published_contract_and_readme_machine_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            durable_root = self._publish_to_temporary_root(directory)
            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                report = publisher.verify_published()

            self.assertEqual(report, EXPECTED_REPORT)
            readme = (durable_root / "README.md").read_text(encoding="utf-8")
            for line in README_MACHINE_LINES:
                self.assertIn(f"\n{line}\n", f"\n{readme}\n")
            self.assertIn("representative_matrix.csv has 12 fixed roles", readme)
            self.assertIn("selection.json has eligible_count=11", readme)
            self.assertIn("exactly 11 per-candidate manifests exist", readme)
            self.assertIn("T300_fd1p45_one__legacy_transfer", readme)
            self.assertIn("rejected before SLX preparation", readme)
            self.assertIn("not a missing-file error", readme)

            with (durable_root / "manifest.csv").open(
                newline="", encoding="utf-8"
            ) as stream:
                manifest_rows = list(csv.DictReader(stream))
            self.assertEqual(len(manifest_rows), 34)
            self.assertEqual(
                list(manifest_rows[0]),
                [
                    "source_path",
                    "durable_path",
                    "purpose",
                    "byte_count",
                    "sha256",
                    "is_original_output",
                    "is_regenerable",
                    "evidence_grade",
                ],
            )

    def test_publish_and_verify_reject_nonmatching_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            durable_root = self._publish_to_temporary_root(directory)
            mismatching = durable_root / "paper_curve/points.csv"
            mismatching.write_bytes(b"mismatching durable evidence\n")

            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_all()
                with self.assertRaises(publisher.PublicationError):
                    publisher.verify_published()

    def test_readme_documents_exact_manifest_schema(self):
        readme = (publisher.DURABLE_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("is_original_output", readme)
        self.assertIn("is_regenerable", readme)
        self.assertNotIn("`original_output`", readme)
        self.assertNotIn("`regenerable`", readme)

    def test_readme_template_matches_durable_and_normal_publish_is_idempotent(self):
        committed = publisher.ROOT / "data/provenance/steady53/fig5_18d/README.md"
        self.assertEqual(committed.read_bytes(), publisher.README.encode("utf-8"))
        with tempfile.TemporaryDirectory() as directory:
            durable_root = self._publish_to_temporary_root(directory)
            self.assertEqual((durable_root / "README.md").read_bytes(), committed.read_bytes())
        before = {p: p.stat().st_mtime_ns for p in publisher.DURABLE_ROOT.rglob("*") if p.is_file()}
        command = [sys.executable, str(Path(__file__).parents[0] / "publish_fig518d_evidence.py")]
        for _ in range(2):
            result = subprocess.run(command, cwd=publisher.ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "FIG518D_EVIDENCE_PASS; PAPER_POINTS=12; A1_14000_PASS=3")
        after = {p: p.stat().st_mtime_ns for p in publisher.DURABLE_ROOT.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_registered_two_state_extension_is_verified_and_unknown_files_are_rejected(self):
        publisher.verify_published()
        with tempfile.TemporaryDirectory() as directory:
            durable_root = Path(directory) / "fig5_18d"
            shutil.copytree(publisher.DURABLE_ROOT, durable_root)
            summary = durable_root / "two_state_feasibility/summary.json"
            summary.write_bytes(summary.read_bytes() + b"tamper")
            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                with self.assertRaises(publisher.PublicationError):
                    publisher.verify_published()

            shutil.copyfile(
                publisher.DURABLE_ROOT / "two_state_feasibility/summary.json",
                summary,
            )
            self.assertEqual(
                hashlib.sha256(summary.read_bytes()).hexdigest(),
                publisher.REGISTERED_EXTENSION_SHA256[
                    "two_state_feasibility/summary.json"
                ],
            )
            (durable_root / "unknown-evidence.txt").write_text("unregistered")
            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                with self.assertRaises(publisher.PublicationError):
                    publisher.verify_published()

    def test_verify_is_durable_only_and_publication_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            durable_root = self._publish_to_temporary_root(directory)
            mtimes = {
                path.relative_to(durable_root).as_posix(): path.stat().st_mtime_ns
                for path in durable_root.rglob("*")
                if path.is_file()
            }

            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                publisher.publish_all()
                with mock.patch.object(
                    publisher,
                    "source_entries",
                    side_effect=AssertionError("verify touched volatile sources"),
                ):
                    self.assertEqual(publisher.verify_published(), EXPECTED_REPORT)

            self.assertEqual(
                mtimes,
                {
                    path.relative_to(durable_root).as_posix(): path.stat().st_mtime_ns
                    for path in durable_root.rglob("*")
                    if path.is_file()
                },
            )

    def test_publish_file_rejects_outside_destination_and_source_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            durable_root = temporary_root / "fig5_18d"
            durable_root.mkdir()
            real_source = temporary_root / "source"
            real_source.write_bytes(b"trusted")
            source_link = temporary_root / "source-link"
            source_link.symlink_to(real_source)

            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(
                        real_source,
                        temporary_root / "outside/file",
                        publisher.sha256(real_source),
                    )
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(
                        source_link,
                        durable_root / "inside/file",
                        publisher.sha256(real_source),
                    )

    def test_publish_file_rejects_parent_symlink_and_stale_staging(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary_root = Path(directory)
            durable_root = temporary_root / "fig5_18d"
            durable_root.mkdir()
            external = temporary_root / "external"
            external.mkdir()
            (durable_root / "linked").symlink_to(external, target_is_directory=True)
            source = temporary_root / "source"
            source.write_bytes(b"trusted")
            expected = publisher.sha256(source)

            with mock.patch.object(publisher, "DURABLE_ROOT", durable_root):
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(
                        source, durable_root / "linked/file", expected
                    )

                destination = durable_root / "safe/file"
                destination.parent.mkdir()
                staging = destination.with_name(f"{destination.name}.publishing")
                staging.write_bytes(b"audit-preserved")
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_file(source, destination, expected)

            self.assertEqual(staging.read_bytes(), b"audit-preserved")
            self.assertFalse(os.path.lexists(external / "file"))

    def test_immutable_contract_keys_and_current_sources(self):
        self.assertEqual(
            set(publisher.EXPECTED_SHA256),
            {spec["durable_path"] for spec in publisher.SOURCE_SPECS},
        )
        self.assertEqual(len(publisher.EXPECTED_SHA256), 34)
        for spec in publisher.SOURCE_SPECS:
            digest = publisher.EXPECTED_SHA256[spec["durable_path"]]
            self.assertEqual(publisher.sha256(publisher.ROOT / spec["source_path"]), digest)

    def test_mutated_source_is_refused_by_literal_contract(self):
        spec = publisher.SOURCE_SPECS[0]
        source = publisher.ROOT / spec["source_path"]
        original = source.read_bytes()
        try:
            source.write_bytes(original + b"mutation")
            with self.assertRaises(publisher.PublicationError):
                publisher.source_entries()
        finally:
            source.write_bytes(original)

    def test_representative_semantics_rejects_identity_and_eligibility_drift(self):
        rows = [{"candidate_id": i, "eligible_for_slx": "false" if i in publisher.EXPECTED_INELIGIBLE_IDS else "true"}
                for i in publisher.EXPECTED_REPRESENTATIVE_IDS]
        manifests = [{"candidate_id": i, "eligible_for_slx": True}
                     for i in publisher.EXPECTED_REPRESENTATIVE_IDS if i not in publisher.EXPECTED_INELIGIBLE_IDS]
        selection = {"eligible_candidate_ids": [m["candidate_id"] for m in manifests], "eligible_count": 11}
        publisher.validate_representative_semantics(rows, selection, manifests)
        rows[-1]["eligible_for_slx"] = "false"
        with self.assertRaises(publisher.PublicationError):
            publisher.validate_representative_semantics(rows, selection, manifests)


if __name__ == "__main__":
    unittest.main()
