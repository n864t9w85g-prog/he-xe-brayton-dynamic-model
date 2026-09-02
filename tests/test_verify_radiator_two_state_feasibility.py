"""Tests for the independent radiator two-state evidence verifier."""
from __future__ import annotations

import unittest
from pathlib import Path
import tempfile
import json
import os
import ast
import csv
import contextlib
import io
import shutil
from decimal import Decimal, localcontext
from unittest import mock


class VerifierApiTests(unittest.TestCase):
    def make_bundle(self, folder: str) -> Path:
        from tests import run_radiator_two_state_feasibility as runner
        run_dir = Path(folder) / "run"
        runner.run(run_dir)
        return run_dir

    def rewrite_output_hash(self, run_dir: Path, name: str) -> None:
        from tests import verify_radiator_two_state_feasibility as verifier
        hashes = json.loads((run_dir / "output_hashes.json").read_text(encoding="utf-8"))
        hashes[name] = verifier._sha(run_dir / name)
        (run_dir / "output_hashes.json").write_text(json.dumps(hashes, sort_keys=True), encoding="utf-8")
    def test_public_api_is_importable(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        self.assertTrue(issubclass(verifier.VerificationError, RuntimeError))
        self.assertTrue(callable(verifier.verify))
        self.assertTrue(callable(verifier.publish))

    def test_runner_bundle_verifies_idempotently(self):
        from tests import run_radiator_two_state_feasibility as runner
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder) / "run"
            runner.run(run_dir)
            first = verifier.verify(run_dir)
            evidence = run_dir / "verification.json"
            bytes_before, mtime_before = evidence.read_bytes(), evidence.stat().st_mtime_ns
            second = verifier.verify(run_dir)
            self.assertEqual(first, second)
            self.assertEqual(first["schema"], "radiator_two_state_verification_v1")
            self.assertEqual((first["verified_case_count"], first["verified_interval_count"]), (4, 44))
            self.assertTrue(first["all_checks_passed"])
            self.assertTrue(all(first[key] is False for key in ("paper_reproduced", "author_parameter_identified", "formal_promotion")))
            self.assertEqual((evidence.read_bytes(), evidence.stat().st_mtime_ns), (bytes_before, mtime_before))

    def test_arithmetic_tamper_is_rejected_even_when_output_hash_is_updated(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            with (run_dir / "intervals.csv").open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            rows[0]["D_J"] = str(float(rows[0]["D_J"]) + 1.0)
            with (run_dir / "intervals.csv").open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
            self.rewrite_output_hash(run_dir, "intervals.csv")
            with self.assertRaisesRegex(verifier.VerificationError, "arithmetic mismatch"):
                verifier.verify(run_dir)

    def test_output_hash_tamper_is_rejected(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            hashes = json.loads((run_dir / "output_hashes.json").read_text())
            hashes["summary.json"] = "0" * 64
            (run_dir / "output_hashes.json").write_text(json.dumps(hashes), encoding="utf-8")
            with self.assertRaisesRegex(verifier.VerificationError, "output hash mismatch"):
                verifier.verify(run_dir)

    def test_summary_gate_solution_and_enum_tampers_are_rejected(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        for field, mutate in (
            ("case_enum", lambda v: "conditionally_feasible"),
            ("nominal_sign_gate", lambda v: {**v, "conflict": not v["conflict"]}),
            ("unrestricted_solution", lambda v: {**v, "UA_W_K": v["UA_W_K"] + 1}),
        ):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as folder:
                run_dir = self.make_bundle(folder)
                summary = json.loads((run_dir / "summary.json").read_text())
                summary["cases"][0][field] = mutate(summary["cases"][0][field])
                (run_dir / "summary.json").write_text(json.dumps(summary, allow_nan=False), encoding="utf-8")
                self.rewrite_output_hash(run_dir, "summary.json")
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)

    def test_bad_csv_schema_order_nonfinite_and_blank_conventions_are_rejected(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        changes = {
            "headers": lambda d: (d / "intervals.csv").write_text("bad\n", encoding="utf-8"),
            "count": lambda d: (d / "intervals.csv").write_text("\n".join((d / "intervals.csv").read_text(encoding="utf-8").splitlines()[:-1]) + "\n", encoding="utf-8"),
            "order": lambda d: (d / "intervals.csv").write_text("\n".join([(d / "intervals.csv").read_text(encoding="utf-8").splitlines()[0], *reversed((d / "intervals.csv").read_text(encoding="utf-8").splitlines()[1:])]) + "\n", encoding="utf-8"),
            "nonfinite": lambda d: self._set_interval_value(d, "D_J", "nan"),
            "corner_blank": lambda d: (d / "corner_ranges.csv").write_text((d / "corner_ranges.csv").read_text().replace(",false,0", ",1,false,0", 1), encoding="utf-8"),
        }
        for label, change in changes.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as folder:
                run_dir = self.make_bundle(folder); change(run_dir)
                self.rewrite_output_hash(run_dir, "intervals.csv" if label in {"headers", "count", "order", "nonfinite"} else "corner_ranges.csv")
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)

    def _set_interval_value(self, run_dir: Path, field: str, value: str) -> None:
        path = run_dir / "intervals.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle); rows = list(reader); headers = reader.fieldnames
        rows[0][field] = value
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=headers); writer.writeheader(); writer.writerows(rows)

    def test_source_protected_and_output_drift_are_rejected(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            with mock.patch.object(verifier, "_source_hashes", return_value={"bad": "0" * 64}):
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            with mock.patch.object(verifier.contract, "snapshot_protected_files", return_value={"bad": "0" * 64}):
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            real = verifier._load_hashes
            with mock.patch.object(verifier, "_load_hashes", side_effect=(real(run_dir), verifier.VerificationError("drift"))):
                with self.assertRaisesRegex(verifier.VerificationError, "drift"): verifier.verify(run_dir)

    def test_verifier_has_no_production_math_import_or_external_apis(self):
        source = (Path(__file__).with_name("verify_radiator_two_state_feasibility.py")).read_text(encoding="utf-8")
        def imports_production_math(text):
            for node in ast.walk(ast.parse(text)):
                if isinstance(node, ast.Import) and any(alias.name == "tests.radiator_two_state_math" for alias in node.names): return True
                if isinstance(node, ast.ImportFrom) and node.module == "tests" and any(alias.name == "radiator_two_state_math" for alias in node.names): return True
                if isinstance(node, ast.ImportFrom) and node.module == "tests.radiator_two_state_math": return True
            return False
        self.assertFalse(imports_production_math(source))
        for synthetic in ("import tests.radiator_two_state_math", "from tests import radiator_two_state_math", "from tests.radiator_two_state_math import solve_nnls"):
            self.assertTrue(imports_production_math(synthetic))
        for forbidden in ("subprocess", "matlab", "wolfram", "requests", "socket", "urlopen", "sim("):
            self.assertNotIn(forbidden, source.lower())

    def test_decimal_helpers_recover_exact_coefficients_and_solution(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with localcontext() as precision:
            precision.prec = 50
            self.assertEqual(verifier._cp(Decimal("600")), Decimal("888.5684"))
            self.assertEqual(verifier._h(Decimal("600")), Decimal("578319.96"))
            row = verifier._coefficient((Decimal("0"), Decimal("280"), Decimal("300")), (Decimal("10"), Decimal("300"), Decimal("320")), Decimal("2"), "inlet_cp")
            self.assertEqual(row[0], Decimal("4.0"))
            exact = [(Decimal(1), Decimal(0), Decimal(20)), (Decimal(0), Decimal(1), Decimal(30)), (Decimal(1), Decimal(1), Decimal(50))]
            self.assertEqual(verifier._solve(exact), (Decimal(20), Decimal(30), Decimal(0)))
            self.assertEqual(verifier._nnls(exact, verifier._solve(exact)), (Decimal(20), Decimal(30), Decimal(0)))

    def test_publish_builds_minimal_manifest_and_preserves_collision(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); run_dir = self.make_bundle(folder); publication = root / "publication"
            manifest = verifier.publish(run_dir, publication)
            self.assertEqual({p.name for p in publication.iterdir()}, {"summary.json", "intervals.csv", "source_hashes.json", "verification.json", "manifest.json"})
            self.assertEqual(manifest["schema"], "radiator_two_state_publication_v1")
            for item in manifest["artifacts"]:
                path = publication / item["relative_filename"]
                self.assertEqual((verifier._sha(path), path.stat().st_size), (item["sha256"], item["byte_count"]))
            marker = publication / "marker"
            marker.write_text("preserve", encoding="utf-8")
            with self.assertRaises(FileExistsError): verifier.publish(run_dir, publication)
            self.assertEqual(marker.read_text(), "preserve")

    def test_publish_failure_cleans_only_staging(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        for injected in (KeyboardInterrupt(), OSError("copy failed")):
            with self.subTest(exception=type(injected).__name__), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); run_dir = self.make_bundle(folder); publication = root / "publication"
                with mock.patch.object(verifier.shutil, "copyfile", side_effect=injected):
                    with self.assertRaises(type(injected)): verifier.publish(run_dir, publication)
                self.assertFalse(publication.exists())
                self.assertFalse(any("publication.staging" in p.name for p in root.iterdir()))

    def test_publish_competition_collision_preserves_competitor_target(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); run_dir = self.make_bundle(folder); publication = root / "publication"
            def competitor(staging, target):
                target.mkdir(); (target / "marker").write_text("competitor", encoding="utf-8")
                raise FileExistsError(target)
            with mock.patch.object(verifier, "_publish_exclusive", side_effect=competitor):
                with self.assertRaises(FileExistsError): verifier.publish(run_dir, publication)
            self.assertEqual((publication / "marker").read_text(), "competitor")
            self.assertFalse(any("publication.staging" in p.name for p in root.iterdir()))

    def test_tampered_run_cannot_publish(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); run_dir = self.make_bundle(folder)
            (run_dir / "summary.json").write_text("{}", encoding="utf-8")
            with self.assertRaises(verifier.VerificationError): verifier.publish(run_dir, root / "publication")
            self.assertFalse((root / "publication").exists())

    def test_cli_verify_and_publish_emit_compact_status(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder); output = io.StringIO()
            with contextlib.redirect_stdout(output): self.assertEqual(verifier.main(["--run-dir", str(run_dir)]), 0)
            status = json.loads(output.getvalue()); self.assertEqual(set(status), {"run_dir", "result_enum", "all_checks_passed", "published"}); self.assertFalse(status["published"])
            output = io.StringIO(); publication = Path(folder) / "publication"
            with contextlib.redirect_stdout(output): self.assertEqual(verifier.main(["--run-dir", str(run_dir), "--publish-dir", str(publication)]), 0)
            self.assertTrue(json.loads(output.getvalue())["published"])

    def test_verify_uses_private_decimal_precision_50(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder, localcontext() as context:
            context.prec = 5
            result = verifier.verify(self.make_bundle(folder))
            self.assertTrue(result["all_checks_passed"])

    def test_summary_numbers_and_counts_require_exact_json_types(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        for key, value in (("Tin_K", "609.58"), ("case_count", 4.0), ("interval_count_per_case", True)):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as folder:
                run_dir = self.make_bundle(folder)
                summary = json.loads((run_dir / "summary.json").read_text())
                summary[key] = value
                (run_dir / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
                self.rewrite_output_hash(run_dir, "summary.json")
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)

    def test_run_bundle_entries_must_be_regular_non_symlink_files(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            original = run_dir / "report.md"; replacement = Path(folder) / "report-copy.md"
            original.rename(replacement); original.symlink_to(replacement)
            with self.assertRaisesRegex(verifier.VerificationError, "regular non-symlink"): verifier.verify(run_dir)

    def test_final_source_and_protected_drift_fails_before_verification_write(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder)
            normal = verifier._source_hashes()
            changed = dict(normal); changed[next(iter(changed))] = "0" * 64
            with mock.patch.object(verifier, "_source_hashes", side_effect=(normal, changed)):
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
            self.assertFalse((run_dir / "verification.json").exists())
        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder); normal = verifier.contract.snapshot_protected_files(); changed = dict(normal); changed[next(iter(changed))] = "0" * 64
            with mock.patch.object(verifier.contract, "snapshot_protected_files", side_effect=(normal, changed)):
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
            self.assertFalse((run_dir / "verification.json").exists())

    def test_existing_conflicting_verification_evidence_is_preserved(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder); evidence = run_dir / "verification.json"
            evidence.write_text('{"wrong":true}\n', encoding="utf-8"); before = evidence.read_bytes()
            with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
            self.assertEqual(evidence.read_bytes(), before)

    def test_atomic_collision_rechecks_new_entry_type(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); target = root / "verification.json"; outside = root / "outside.json"; payload = {"same": True}
            outside.write_text(json.dumps(payload), encoding="utf-8")
            def symlink_collision(source, destination):
                target.symlink_to(outside); raise FileExistsError(destination)
            with mock.patch.object(verifier.os, "link", side_effect=symlink_collision):
                with self.assertRaisesRegex(verifier.VerificationError, "regular non-symlink"):
                    verifier._atomic_json_exclusive(target, payload)
            self.assertTrue(target.is_symlink())
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "verification.json"; payload = {"same": True}
            def regular_collision(source, destination):
                target.write_text(json.dumps(payload), encoding="utf-8"); raise FileExistsError(destination)
            with mock.patch.object(verifier.os, "link", side_effect=regular_collision): verifier._atomic_json_exclusive(target, payload)
            self.assertEqual(json.loads(target.read_text()), payload)

    def test_late_extra_file_before_verification_write_is_rejected(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder); real = verifier._load_hashes
            def late_extra(path):
                (run_dir / "late-extra.txt").write_text("late", encoding="utf-8")
                return real(path)
            with mock.patch.object(verifier, "_load_hashes", side_effect=(real(run_dir), late_extra)):
                with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)
            self.assertFalse((run_dir / "verification.json").exists())

    def test_cases_must_be_json_list(self):
        from tests import verify_radiator_two_state_feasibility as verifier
        with tempfile.TemporaryDirectory() as folder:
            run_dir = self.make_bundle(folder); summary = json.loads((run_dir / "summary.json").read_text()); summary["cases"] = {"not": "list"}
            (run_dir / "summary.json").write_text(json.dumps(summary), encoding="utf-8"); self.rewrite_output_hash(run_dir, "summary.json")
            with self.assertRaises(verifier.VerificationError): verifier.verify(run_dir)

    def test_publish_rejects_post_verify_identity_drift(self):
        from tests import verify_radiator_two_state_feasibility as verifier

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); run_dir = self.make_bundle(folder); publication = root / "publication"; result = verifier.verify(run_dir)
            changed = dict(result["run_output_hashes"]); changed["summary.json"] = "0" * 64
            with mock.patch.object(verifier, "verify", return_value=result), mock.patch.object(verifier, "_load_hashes", return_value=changed):
                with self.assertRaises(verifier.VerificationError): verifier.publish(run_dir, publication)
            self.assertFalse(publication.exists())


if __name__ == "__main__":
    unittest.main()
