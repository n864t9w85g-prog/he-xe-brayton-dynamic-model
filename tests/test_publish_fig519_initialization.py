"""Transaction and contract tests for the Figure 5.19 initialization audit."""
from __future__ import annotations

import csv
import hashlib
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests import publish_fig519_initialization as subject


ROOT = Path(__file__).resolve().parents[1]
DURABLE = ROOT / "data/provenance/steady53/fig5_19"


class Figure519InitializationPublicationTests(unittest.TestCase):
    def _task5_copy(self, parent: Path, name: str = "out") -> Path:
        output = parent / name
        shutil.copytree(DURABLE, output)
        audit = output / "initialization_audit.json"
        if audit.exists():
            audit.unlink()
        # Rebuild the exact Task 5 predecessor even when the durable fixture
        # has already advanced to the Task 6 layer.
        old_contract = subject.baseline._json_bytes(subject.baseline._contract())
        (output / "signal_contract.json").write_bytes(old_contract)
        entries = {artifact: (output / artifact).read_bytes()
                   for artifact in subject.paper.ARTIFACT_NAMES}
        entries.update({f"{subject.paper.BASELINE_LAYER_DIR}/{artifact}":
                        (output / subject.paper.BASELINE_LAYER_DIR / artifact).read_bytes()
                        for artifact in subject.paper.BASELINE_LAYER_NAMES})
        entries["baseline_metrics.json"] = (output / "baseline_metrics.json").read_bytes()
        entries["signal_contract.json"] = old_contract
        (output / "manifest.csv").write_bytes(
            subject.paper.manifest_bytes(entries, subject.baseline._roles()))
        return output

    def _source(self, parent: Path) -> Path:
        run = parent / "run"
        run.mkdir()
        audit = json.loads((DURABLE / "initialization_audit.json").read_text())
        source = run / "initialization_audit.json"
        source.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
        return source

    def test_structural_fake_audits_and_invented_hops_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            valid = json.loads(source.read_text())

            def fake_states(audit):
                retained = {path for mapping in
                    audit["flat_start_explanation"]["power_state_signal_mappings"]
                    for path in mapping["traced_state_paths"]}
                for index, item in enumerate(audit["state_inventory"]):
                    if item["path"] not in retained:
                        item["path"] = f"final_steady_24a/invented/state/{index}"

            def missing_residuals(audit):
                audit["initial_residuals"]["items"] = [item for item in
                    audit["initial_residuals"]["items"] if item["name"] == "shaft_excess_power"]

            def inconsistent_state(audit):
                audit["state_inventory"][0]["absolute_change"] += 1.0

            def inconsistent_near_zero(audit):
                audit["flat_start_explanation"]["near_zero_state_derivatives"] = []

            def invented_hop(audit):
                mapping = audit["flat_start_explanation"]["power_state_signal_mappings"][0]
                mapping["api_trace_records"] = [{
                    "state_path": mapping["traced_state_paths"][0],
                    "endpoint_block": "final_steady_24a/invented/endpoint",
                    "status": "verified_by_official_api",
                    "hops": [{"from_block": "invented/path", "from_port": 1,
                              "from_port_kind": "output", "to_block": "invented/path2",
                              "to_port": 1, "to_port_kind": "input",
                              "bridge_kind": "signal_line"}],
                }]

            def changed_residual_formula(audit):
                audit["initial_residuals"]["items"][0]["formula"] = "fitted formula"

            def changed_missing_signal(audit):
                item = next(item for item in audit["initial_residuals"]["items"]
                            if item["name"] == "ihx_energy")
                item["missing_direct_signals"] = ["unspecified"]

            def changed_trace_hop(audit):
                mapping = next(item for item in
                    audit["flat_start_explanation"]["power_state_signal_mappings"]
                    if item["power_definition"] == "turbine")
                mapping["api_trace_records"][0]["hops"][0]["to_port"] += 1

            def changed_trace_endpoint(audit):
                mapping = next(item for item in
                    audit["flat_start_explanation"]["power_state_signal_mappings"]
                    if item["power_definition"] == "compressor")
                mapping["api_trace_records"][0]["endpoint_block"] = \
                    "final_steady_24a/TAC/Turbine"

            def changed_generator_identity(audit):
                audit["generation_contract"]["generator_sha256"] = "0" * 64

            for label, mutation in (("fake states", fake_states),
                                    ("missing residuals", missing_residuals),
                                    ("inconsistent state", inconsistent_state),
                                    ("inconsistent near-zero", inconsistent_near_zero),
                                    ("invented hop", invented_hop),
                                    ("changed residual formula", changed_residual_formula),
                                    ("changed missing signal", changed_missing_signal),
                                    ("changed trace hop", changed_trace_hop),
                                    ("changed trace endpoint", changed_trace_endpoint),
                                    ("changed generator identity", changed_generator_identity)):
                with self.subTest(label=label):
                    fake = json.loads(json.dumps(valid))
                    mutation(fake)
                    source.write_text(json.dumps(fake))
                    with self.assertRaises(RuntimeError):
                        subject.publish(source, output)

    def test_publish_is_idempotent_and_updates_api_contract(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            before = {str(p.relative_to(output)): (p.read_bytes(), p.stat().st_mtime_ns)
                      for p in output.rglob("*") if p.is_file()}
            subject.publish(source, output)
            subject.verify_only(output)
            self.assertEqual(before, {str(p.relative_to(output)): (p.read_bytes(), p.stat().st_mtime_ns)
                                      for p in output.rglob("*") if p.is_file()})
            contract = json.loads((output / "signal_contract.json").read_text())
            signals = contract["signals"]
            self.assertEqual(signals["reactor"]["status"], "verified_by_official_api")
            self.assertEqual(signals["turbine"]["api_block_path"], "final_steady_24a/TAC/Turbine")
            self.assertEqual(signals["compressor"]["api_output_port"], 2)
            self.assertEqual(signals["electrical_paper_eta"]["status"], "no_direct_generator_signal_found")
            with (output / "manifest.csv").open(newline="") as handle:
                rows = list(csv.DictReader(handle))
            indexed = {row["path"]: row for row in rows}
            self.assertIn("initialization_audit.json", indexed)
            self.assertIn("@external/raw_reference.mat", indexed)
            raw_row = indexed["@external/raw_reference.mat"]
            self.assertEqual(raw_row["storage"], "external_tmp_not_copied")
            self.assertEqual(raw_row["repository_relative_path"], "tmp/fig519_initialization_20260831_A1/raw_reference.mat")
            self.assertEqual(raw_row["absolute_path"], str(ROOT / raw_row["repository_relative_path"]))
            self.assertEqual(raw_row["sha256"], hashlib.sha256((ROOT / raw_row["repository_relative_path"]).read_bytes()).hexdigest())
            self.assertEqual(int(raw_row["bytes"]), (ROOT / raw_row["repository_relative_path"]).stat().st_size)
            for relative, row in indexed.items():
                if row.get("storage") == "external_tmp_not_copied":
                    continue
                target = output / relative
                self.assertFalse(target.is_symlink())
                self.assertEqual(row["sha256"], hashlib.sha256(target.read_bytes()).hexdigest())
                self.assertEqual(int(row["bytes"]), target.stat().st_size)

    def test_rejects_source_outside_tmp_symlinks_and_malformed_audit(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            malformed = json.loads(source.read_text())
            malformed["direct_generator_signal_found"] = True
            source.write_text(json.dumps(malformed))
            with self.assertRaises(RuntimeError):
                subject.publish(source, output)
            outside = ROOT / "tests" / ".fig519-audit-outside.json"
            outside.write_text("{}")
            try:
                with self.assertRaises(RuntimeError):
                    subject.publish(outside, output)
            finally:
                outside.unlink()

            real = parent / "real"
            real.mkdir()
            symlink = parent / "linked"
            os.symlink(real, symlink)
            with self.assertRaises(RuntimeError):
                subject.publish(symlink / "initialization_audit.json", output)

    def test_partial_commit_is_recoverable_and_manifest_is_last(self):
        for fail_at in ("audit-commit-after", "signal-contract-commit-after", "manifest-commit-before"):
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                parent = Path(work)
                output = self._task5_copy(parent)
                source = self._source(parent)
                original_manifest = (output / "manifest.csv").read_bytes()

                def fail(point: str):
                    if point == fail_at:
                        raise OSError("injected publication interruption")

                with mock.patch.object(subject, "_publication_boundary", fail):
                    with self.assertRaises(OSError):
                        subject.publish(source, output)
                if fail_at != "manifest-commit-before":
                    self.assertEqual((output / "manifest.csv").read_bytes(), original_manifest)
                subject.publish(source, output)
                subject.verify_only(output)
                self.assertFalse(subject.transaction_dir(output).exists())

    def test_every_cleanup_boundary_is_recoverable_and_tombstone_owned(self):
        cleanup_boundaries = (
            "cleanup-tombstone-rename-before", "cleanup-tombstone-rename-after",
            "cleanup-audit-unlink-before", "cleanup-audit-unlink-after",
            "cleanup-signal-contract-unlink-before", "cleanup-signal-contract-unlink-after",
            "cleanup-manifest-unlink-before", "cleanup-manifest-unlink-after",
            "cleanup-payload-rmdir-before", "cleanup-payload-rmdir-after",
            "cleanup-record-unlink-before", "cleanup-record-unlink-after",
            "cleanup-tombstone-rmdir-before", "cleanup-tombstone-rmdir-after",
        )
        for fail_at in cleanup_boundaries:
            with self.subTest(fail_at=fail_at), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
                parent = Path(work)
                output = self._task5_copy(parent)
                source = self._source(parent)

                def fail(point: str):
                    if point == fail_at:
                        raise OSError("injected cleanup interruption")

                with mock.patch.object(subject, "_publication_boundary", fail):
                    with self.assertRaises(OSError):
                        subject.publish(source, output)
                subject.publish(source, output)
                subject.verify_only(output)
                self.assertFalse(subject.transaction_dir(output).exists())
                self.assertFalse(any("task6-cleanup" in entry.name for entry in output.parent.iterdir()))

    def test_cleanup_refuses_unowned_tombstone_without_deleting_it(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            payloads = subject._planned(source, output)
            tombstone = subject.cleanup_tombstone_path(output, payloads)
            tombstone.mkdir(mode=0o700)
            sentinel = tombstone / "not-owned-by-task6"
            sentinel.write_text("preserve")
            with self.assertRaises(RuntimeError):
                subject.publish(source, output)
            self.assertEqual(sentinel.read_text(), "preserve")

    def test_verify_only_rejects_corruption_and_writes_nothing(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            (output / "initialization_audit.json").write_bytes(b"corrupt")
            before = {str(p.relative_to(output)): p.read_bytes()
                      for p in output.rglob("*") if p.is_file()}
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)
            self.assertEqual(before, {str(p.relative_to(output)): p.read_bytes()
                                      for p in output.rglob("*") if p.is_file()})

    def test_verify_only_rejects_missing_or_tampered_raw_locator(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as work:
            parent = Path(work)
            output = self._task5_copy(parent)
            source = self._source(parent)
            subject.publish(source, output)
            audit_path = output / "initialization_audit.json"
            original = audit_path.read_bytes()
            audit = json.loads(original)
            audit["raw_reference"]["sha256"] = "0" * 64
            audit_path.write_text(json.dumps(audit))
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)
            audit_path.write_bytes(original)
            audit = json.loads(original)
            audit["raw_reference"]["repository_relative_path"] = "tmp/fig519_initialization_20260831_A1/missing.mat"
            audit["raw_reference"]["absolute_path"] = str(ROOT / audit["raw_reference"]["repository_relative_path"])
            audit_path.write_text(json.dumps(audit))
            with self.assertRaises(RuntimeError):
                subject.verify_only(output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
