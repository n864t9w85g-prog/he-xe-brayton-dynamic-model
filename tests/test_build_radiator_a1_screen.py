"""Tests for the deterministic, offline-only radiator A1 screen package."""
from __future__ import annotations

import csv
from dataclasses import replace
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from tests import build_radiator_a1_screen as builder
from tests import radiator_a1_contract as contract


ROOT = Path(__file__).resolve().parents[1]


def digest_tree(path: Path) -> dict[str, str]:
    """Return a relative-path SHA256 tree for every regular output file."""
    return {
        str(item.relative_to(path)): hashlib.sha256(item.read_bytes()).hexdigest()
        for item in sorted(path.rglob("*"))
        if item.is_file()
    }


class BuildRadiatorA1ScreenTests(unittest.TestCase):
    def test_output_has_exactly_96_rows_and_12_fixed_roles(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            with (output / "offline_screen/offline_96.csv").open(
                newline="", encoding="utf-8"
            ) as handle:
                rows = list(csv.DictReader(handle))
            with (output / "representatives/representative_matrix.csv").open(
                newline="", encoding="utf-8"
            ) as handle:
                representatives = list(csv.DictReader(handle))

            self.assertEqual(len(rows), 96)
            self.assertEqual(len(representatives), 12)
            self.assertEqual(
                len({row["candidate_id"] for row in representatives}), 12
            )
            self.assertEqual(
                {row["role_id"] for row in representatives},
                {
                    "legacy_transfer",
                    "conservative_source",
                    "optimistic_source",
                },
            )

    def test_proxy_capacity_and_timescale_are_finite_only_when_eligible(self):
        package = builder.build_screen()
        for representative in package["representatives"]:
            self.assertIn(
                representative["cp_proxy_J_kgK"], (777.0, 900.0, 1000.0)
            )
            self.assertEqual(
                representative["cp_identity"], "sensitivity_proxy"
            )
            if representative["eligible_for_slx"]:
                for field in (
                    "C_eff_proxy_J_K",
                    "G_effective_W_K",
                    "tau_predicted_s",
                ):
                    self.assertTrue(math.isfinite(representative[field]))
                    self.assertGreater(representative[field], 0.0)

    def test_rejected_fixed_role_is_not_replaced(self):
        normal = builder.build_screen()
        forced = builder.build_screen(
            force_reject_candidate="APG_fd1p00_two__optimistic_source"
        )
        representatives = forced["representatives"]
        self.assertEqual(len(representatives), 12)
        target = next(
            row
            for row in representatives
            if row["candidate_id"]
            == "APG_fd1p00_two__optimistic_source"
        )
        self.assertFalse(target["eligible_for_slx"])
        self.assertIn("test_forced_rejection", target["rejection_reasons"])
        self.assertEqual(
            sum(row["eligible_for_slx"] for row in representatives),
            sum(row["eligible_for_slx"] for row in normal["representatives"])
            - 1,
        )

    def test_outputs_are_byte_deterministic(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as first, tempfile.TemporaryDirectory(
            dir=ROOT / "tmp"
        ) as second:
            first_path = Path(first)
            second_path = Path(second)
            builder.write_screen(first_path)
            builder.write_screen(second_path)
            self.assertEqual(digest_tree(first_path), digest_tree(second_path))

    def test_every_eligible_candidate_has_exactly_one_manifest(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            selection = json.loads(
                (output / "representatives/selection.json").read_text(
                    encoding="utf-8"
                )
            )
            manifests = list(
                (output / "representatives").glob(
                    "*/parameter_manifest.json"
                )
            )
            manifest_ids = {path.parent.name for path in manifests}
            self.assertEqual(len(manifests), selection["eligible_count"])
            self.assertEqual(
                manifest_ids, set(selection["eligible_candidate_ids"])
            )
            for manifest in manifests:
                payload = json.loads(manifest.read_text(encoding="utf-8"))
                self.assertTrue(payload["eligible_for_slx"])
                self.assertEqual(payload["candidate_id"], manifest.parent.name)

    def test_nonfinite_representative_is_ineligible_and_not_available(self):
        rows = builder.a1math.generate_static_rows()
        original = builder._static_for_role

        def nonfinite_row(all_rows, branch_id, role):
            row = original(all_rows, branch_id, role)
            if branch_id == contract.BRANCHES[0].branch_id:
                return replace(row, M_rad_kg=math.nan)
            return row

        with mock.patch.object(
            builder, "_static_for_role", side_effect=nonfinite_row
        ):
            package = builder.build_screen()

        affected = package["representatives"][: len(contract.ROLES)]
        self.assertTrue(affected)
        for representative in affected:
            self.assertFalse(representative["eligible_for_slx"])
            self.assertEqual(
                representative["timescale_relation"], "not_available"
            )
            self.assertTrue(math.isnan(representative["C_eff_proxy_J_K"]))

    def test_static_role_ambiguity_is_a_hard_gate_under_optimization(self):
        rows = builder.a1math.generate_static_rows()
        branch = contract.BRANCHES[0]
        role = contract.ROLES[0]
        matching = builder._static_for_role(rows, branch.branch_id, role)
        with self.assertRaises(ValueError):
            builder._static_for_role(
                [*rows, matching], branch.branch_id, role
            )
        with self.assertRaises(ValueError):
            builder._static_for_role([], branch.branch_id, role)

    def test_json_and_csv_writers_refuse_overwrite_and_empty_csv(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            root = Path(folder)
            csv_path = root / "nested/data.csv"
            json_path = root / "nested/data.json"
            with self.assertRaises(ValueError):
                builder._write_csv(csv_path, [])
            builder._write_csv(
                csv_path,
                [{"flag": False, "items": [1, 2], "mapping": {"a": 1}}],
            )
            builder._write_json(json_path, {"paper_reproduced": False})
            with self.assertRaises(FileExistsError):
                builder._write_csv(csv_path, [{"flag": True}])
            with self.assertRaises(FileExistsError):
                builder._write_json(json_path, {"paper_reproduced": True})
            with csv_path.open(newline="", encoding="utf-8") as handle:
                row = next(csv.DictReader(handle))
            self.assertEqual(row["flag"], "false")
            self.assertEqual(row["items"], "[1, 2]")
            self.assertEqual(row["mapping"], '{"a": 1}')

    def test_write_screen_refuses_tmp_root_and_outside_paths(self):
        with tempfile.TemporaryDirectory() as outside:
            with self.assertRaises(ValueError):
                builder.write_screen(Path(outside) / "screen")
        with self.assertRaises(ValueError):
            builder.write_screen(ROOT / "tmp")

    def test_write_screen_refuses_to_overwrite_any_existing_product(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            before = digest_tree(output)
            with self.assertRaises(FileExistsError):
                builder.write_screen(output)
            self.assertEqual(digest_tree(output), before)

    def test_late_matrix_collision_cannot_leave_a_partial_package(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            collision = output / "representatives/representative_matrix.csv"
            collision.parent.mkdir(parents=True)
            collision.write_text("reserved\n", encoding="utf-8")
            before = digest_tree(output)

            with self.assertRaises(FileExistsError):
                builder.write_screen(output)

            self.assertEqual(digest_tree(output), before)

    def test_late_manifest_collision_cannot_leave_a_partial_package(self):
        package = builder.build_screen()
        candidate_id = next(
            row["candidate_id"]
            for row in package["representatives"]
            if row["eligible_for_slx"]
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            collision = (
                output
                / "representatives"
                / candidate_id
                / "parameter_manifest.json"
            )
            collision.parent.mkdir(parents=True)
            collision.write_text("reserved\n", encoding="utf-8")
            before = digest_tree(output)

            with self.assertRaises(FileExistsError):
                builder.write_screen(output)

            self.assertEqual(digest_tree(output), before)

    def test_symlinked_output_component_cannot_escape_output(self):
        with (
            tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder,
            tempfile.TemporaryDirectory() as outside,
        ):
            output = Path(folder)
            outside_path = Path(outside)
            (output / "representatives").symlink_to(
                outside_path, target_is_directory=True
            )

            with self.assertRaises(ValueError):
                builder.write_screen(output)

            self.assertEqual(digest_tree(outside_path), {})
            self.assertEqual(digest_tree(output), {})

    def test_output_hash_manifest_covers_prior_files_but_not_itself(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            hashes_path = output / "source_contract/output_hashes.json"
            hashes = json.loads(hashes_path.read_text(encoding="utf-8"))
            actual = digest_tree(output)
            self.assertNotIn("source_contract/output_hashes.json", hashes)
            actual.pop("source_contract/output_hashes.json")
            self.assertEqual(hashes, actual)

    def test_direct_script_entry_writes_temporary_package(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            completed = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tests/build_radiator_a1_screen.py"),
                    folder,
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                completed.stdout.strip(),
                "RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD",
            )
            self.assertTrue(
                (Path(folder) / "offline_screen/offline_96.csv").is_file()
            )

    def test_unidentifiable_row_with_missing_reason_is_never_eligible(self):
        self._verify_unidentifiable_role_is_not_written(
            ("missing_input_identity_or_unit",)
        )

    def test_unidentifiable_row_without_reason_is_never_eligible(self):
        self._verify_unidentifiable_role_is_not_written(())

    def _verify_unidentifiable_role_is_not_written(self, reasons):
        target_branch = contract.BRANCHES[0].branch_id
        target_role = contract.ROLES[1].role_id
        target_id = f"{target_branch}__{target_role}"
        original = builder._static_for_role

        def unidentifiable_row(rows, branch_id, role):
            row = original(rows, branch_id, role)
            if branch_id == target_branch and role.role_id == target_role:
                return replace(
                    row,
                    condition_status="unidentifiable_due_to_missing_input",
                    rejection_reasons=reasons,
                )
            return row

        with mock.patch.object(
            builder, "_static_for_role", side_effect=unidentifiable_row
        ):
            package = builder.build_screen()
            target = next(
                row
                for row in package["representatives"]
                if row["candidate_id"] == target_id
            )
            self.assertFalse(target["eligible_for_slx"])
            self.assertTrue(math.isfinite(target["tau_predicted_s"]))
            self.assertGreater(target["tau_predicted_s"], 0.0)
            with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
                output = Path(folder)
                builder.write_screen(output)
                self.assertFalse(
                    (
                        output
                        / "representatives"
                        / target_id
                        / "parameter_manifest.json"
                    ).exists()
                )

    def test_unknown_forced_rejection_id_fails_before_source_verification(self):
        unknown = "unknown_branch__unknown_role"
        with mock.patch.object(
            builder.contract, "verify_source_contract"
        ) as verify:
            with self.assertRaisesRegex(ValueError, re.escape(unknown)):
                builder.build_screen(force_reject_candidate=unknown)
            verify.assert_not_called()

    def test_build_screen_exact_fields_units_order_and_statuses(self):
        package = builder.build_screen()
        expected_candidates = [
            f"{branch.branch_id}__{role.role_id}"
            for branch in contract.BRANCHES
            for role in contract.ROLES
        ]
        self.assertEqual(
            [row["candidate_id"] for row in package["representatives"]],
            expected_candidates,
        )
        self.assertEqual(
            package["unit_contract"],
            {
                "m_dot_NaK_kg_s": "kg/s",
                "epsilon": "1",
                "T_sink_K": "K",
                "h_W_m2K": "W/(m^2*K)",
                "Q_NaK_W": "W",
                "Twall_K": "K",
                "A_exchange_m2": "m^2",
                "A_rad_m2": "m^2",
                "UA_W_K": "W/K",
                "M_rad_kg": "kg",
                "C_eff_proxy_J_K": "J/K",
                "tau_predicted_s": "s",
            },
        )
        self.assertFalse(package["paper_reproduced"])
        self.assertFalse(package["formal_promotion"])
        self.assertEqual(len(package["offline_rows"]), 96)
        expected_fields = [
            "candidate_id",
            "source_row_id",
            "branch_id",
            "technology_maturity",
            "role_id",
            "m_dot_NaK_kg_s",
            "epsilon",
            "T_sink_K",
            "h_W_m2K",
            "cp_proxy_J_kgK",
            "cp_identity",
            "Q_NaK_W",
            "Twall_condition_K",
            "A_exchange_m2",
            "A_rad_m2",
            "UA_W_K",
            "M_rad_kg",
            "mass_margin_kg",
            "C_eff_proxy_J_K",
            "G_effective_W_K",
            "tau_predicted_s",
            "timescale_relation",
            "eligible_for_slx",
            "rejection_reasons",
            "paper_reproduced",
            "formal_promotion",
        ]
        for representative in package["representatives"]:
            self.assertEqual(list(representative), expected_fields)
        self.assertEqual(
            sum(row["eligible_for_slx"] for row in package["representatives"]),
            11,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
