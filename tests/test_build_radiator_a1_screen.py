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


def snapshot_tree(path: Path) -> dict[str, tuple[str, str]]:
    """Capture files, directories, and symlinks without following links."""
    snapshot = {}
    for item in sorted(path.rglob("*")):
        relative = str(item.relative_to(path))
        if item.is_symlink():
            snapshot[relative] = ("symlink", str(item.readlink()))
        elif item.is_dir():
            snapshot[relative] = ("directory", "")
        elif item.is_file():
            snapshot[relative] = (
                "file", hashlib.sha256(item.read_bytes()).hexdigest()
            )
    return snapshot


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

    def test_rejection_log_includes_every_noneligible_offline_status(self):
        rows = builder.a1math.generate_static_rows()
        branch = contract.BRANCHES[0]
        role = contract.ROLES[1]
        target = builder._static_for_role(rows, branch.branch_id, role)
        target_index = rows.index(target)
        rows[target_index] = replace(
            target,
            condition_status="unidentifiable_due_to_missing_input",
            rejection_reasons=("missing_input_identity_or_unit",),
        )
        with mock.patch.object(
            builder.a1math, "generate_static_rows", return_value=rows
        ), tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            with (
                output / "offline_screen/offline_rejection_log.csv"
            ).open(newline="", encoding="utf-8") as handle:
                rejected_ids = {
                    row["row_id"] for row in csv.DictReader(handle)
                }
            self.assertIn(target.row_id, rejected_ids)

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
            "kappa_kg_m2",
            "technology_maturity",
            "role_id",
            "flow_case",
            "m_dot_NaK_kg_s",
            "epsilon_case",
            "epsilon",
            "sink_case",
            "T_sink_K",
            "h_case",
            "h_W_m2K",
            "evidence_status_per_input",
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
            "input_provenance",
            "unit_contract_ref",
            "source_contract_ref",
            "equation_version",
            "spec_path",
            "spec_sha256",
            "generator_sha256",
            "contract_module_sha256",
            "math_module_sha256",
            "run_time_record",
            "paper_reproduced",
            "formal_promotion",
        ]
        for representative in package["representatives"]:
            self.assertEqual(list(representative), expected_fields)
        self.assertEqual(
            sum(row["eligible_for_slx"] for row in package["representatives"]),
            11,
        )

    def test_csv_schema_mismatch_is_rejected_before_any_write(self):
        package = builder.build_screen()
        package["representatives"][1].pop("role_id")
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            before = snapshot_tree(output)
            with mock.patch.object(
                builder, "build_screen", return_value=package
            ):
                with self.assertRaises(ValueError):
                    builder.write_screen(output)
            self.assertEqual(snapshot_tree(output), before)

    def test_json_nan_is_rejected_before_any_write(self):
        package = builder.build_screen()
        package["source_contract"]["invalid_nan"] = math.nan
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            before = snapshot_tree(output)
            with mock.patch.object(
                builder, "build_screen", return_value=package
            ):
                with self.assertRaises(ValueError):
                    builder.write_screen(output)
            self.assertEqual(snapshot_tree(output), before)

    def test_manifest_nan_and_unserializable_value_leave_no_partial_package(self):
        for invalid_value in (math.nan, object()):
            with self.subTest(value_type=type(invalid_value).__name__):
                package = builder.build_screen()
                target = next(
                    row
                    for row in package["representatives"]
                    if row["eligible_for_slx"]
                )
                target["invalid_manifest_value"] = invalid_value
                with tempfile.TemporaryDirectory(
                    dir=ROOT / "tmp"
                ) as folder:
                    output = Path(folder)
                    before = snapshot_tree(output)
                    with mock.patch.object(
                        builder, "build_screen", return_value=package
                    ):
                        with self.assertRaises((TypeError, ValueError)):
                            builder.write_screen(output)
                    self.assertEqual(snapshot_tree(output), before)

    def test_mid_write_oserror_rolls_back_only_created_tree(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            before = snapshot_tree(output)
            original = builder._write_bytes_exclusive
            call_count = 0

            def fail_midway(path, payload):
                nonlocal call_count
                call_count += 1
                if call_count == 4:
                    path.write_bytes(payload[:10])
                    raise OSError("injected_mid_write_failure")
                original(path, payload)

            with mock.patch.object(
                builder,
                "_write_bytes_exclusive",
                side_effect=fail_midway,
            ):
                with self.assertRaisesRegex(
                    OSError, "injected_mid_write_failure"
                ):
                    builder.write_screen(output)
            self.assertEqual(snapshot_tree(output), before)

    def test_unit_contract_closes_every_physical_numeric_field(self):
        package = builder.build_screen()
        units = package["unit_contract"]
        expected_units = {
            "kappa_kg_m2": "kg/m^2",
            "m_dot_NaK_kg_s": "kg/s",
            "epsilon": "1",
            "T_sink_K": "K",
            "h_W_m2K": "W/(m^2*K)",
            "cp_proxy_J_kgK": "J/(kg*K)",
            "Q_NaK_W": "W",
            "Twall_K": "K",
            "Twall_condition_K": "K",
            "A_exchange_m2": "m^2",
            "A_rad_m2": "m^2",
            "UA_W_K": "W/K",
            "M_rad_kg": "kg",
            "mass_margin_kg": "kg",
            "exchange_residual_W": "W",
            "radiation_residual_W": "W",
            "C_eff_proxy_J_K": "J/K",
            "G_effective_W_K": "W/K",
            "tau_predicted_s": "s",
        }
        self.assertEqual(units, expected_units)

        numeric_fields = set()
        for row in [*package["offline_rows"], *package["representatives"]]:
            for field, value in row.items():
                if isinstance(value, (int, float)) and not isinstance(
                    value, bool
                ):
                    numeric_fields.add(field)
                    self.assertIn(field, units)
        self.assertEqual(set(units), numeric_fields)

    def test_manifests_close_source_identity_hashes_and_equations(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            with (output / "offline_screen/offline_96.csv").open(
                newline="", encoding="utf-8"
            ) as handle:
                offline_rows = {
                    row["row_id"]: row for row in csv.DictReader(handle)
                }

            manifests = list(
                (output / "representatives").glob(
                    "*/parameter_manifest.json"
                )
            )
            self.assertEqual(len(manifests), 11)
            expected_hashes = {
                "spec_sha256": contract.sha256(
                    ROOT
                    / "docs/superpowers/specs/2026-08-30-radiator-a1-staged-parameter-envelope-design.md"
                ),
                "generator_sha256": contract.sha256(
                    ROOT / "tests/build_radiator_a1_screen.py"
                ),
                "contract_module_sha256": contract.sha256(
                    ROOT / "tests/radiator_a1_contract.py"
                ),
                "math_module_sha256": contract.sha256(
                    ROOT / "tests/radiator_a1_math.py"
                ),
            }
            for path in manifests:
                manifest = json.loads(path.read_text(encoding="utf-8"))
                source_row = offline_rows[manifest["source_row_id"]]
                for field in (
                    "flow_case",
                    "epsilon_case",
                    "sink_case",
                    "h_case",
                    "evidence_status_per_input",
                ):
                    self.assertEqual(manifest[field], source_row[field])
                for field, expected_hash in expected_hashes.items():
                    self.assertEqual(manifest[field], expected_hash)
                self.assertEqual(
                    manifest["equation_version"], "radiator_a1_static_v1"
                )
                self.assertEqual(
                    manifest["unit_contract_ref"],
                    "source_contract/unit_contract.json",
                )
                self.assertEqual(
                    manifest["source_contract_ref"],
                    "source_contract/source_contract.json",
                )
                self.assertEqual(
                    manifest["spec_path"],
                    "docs/superpowers/specs/2026-08-30-radiator-a1-staged-parameter-envelope-design.md",
                )
                self.assertEqual(
                    manifest["run_time_record"],
                    {
                        "mode": "deferred_to_execution_stage",
                        "wall_clock_utc": None,
                        "reason": "deterministic_offline_core",
                    },
                )
                self.assertEqual(
                    set(manifest["input_provenance"]),
                    {"branch", "static_inputs", "cp_proxy"},
                )

    def test_disk_outputs_independently_recompute_proxy_relations(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            with (
                output / "representatives/representative_matrix.csv"
            ).open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
            for row in rows:
                mass = float(row["M_rad_kg"])
                cp_proxy = float(row["cp_proxy_J_kgK"])
                ua = float(row["UA_W_K"])
                epsilon = float(row["epsilon"])
                area = float(row["A_rad_m2"])
                wall = float(row["Twall_condition_K"])
                capacity = mass * cp_proxy
                conductance = (
                    ua
                    + 4.0
                    * builder.a1math.SIGMA
                    * epsilon
                    * area
                    * wall**3
                )
                tau = capacity / conductance
                self.assertAlmostEqual(
                    float(row["C_eff_proxy_J_K"]), capacity, places=9
                )
                self.assertAlmostEqual(
                    float(row["G_effective_W_K"]), conductance, places=9
                )
                self.assertAlmostEqual(
                    float(row["tau_predicted_s"]), tau, places=12
                )

    def test_proxy_derived_failures_are_structured_and_never_drop_roles(self):
        base_rows = builder.a1math.generate_static_rows()
        original = builder._static_for_role
        cases = {
            "nan_mass": {"M_rad_kg": math.nan},
            "positive_infinite_mass": {"M_rad_kg": math.inf},
            "negative_infinite_mass": {"M_rad_kg": -math.inf},
            "zero_mass": {"M_rad_kg": 0.0},
            "negative_mass": {"M_rad_kg": -1.0},
            "wall_power_overflow": {"Twall_K": 1e308},
            "zero_ua": {"UA_W_K": 0.0},
            "negative_ua": {"UA_W_K": -1.0},
        }
        for case_name, replacements in cases.items():
            with self.subTest(case=case_name):
                target_branch = contract.BRANCHES[0].branch_id
                target_role = contract.ROLES[1].role_id

                def invalid_proxy_row(rows, branch_id, role):
                    row = original(rows, branch_id, role)
                    if (
                        branch_id == target_branch
                        and role.role_id == target_role
                    ):
                        return replace(row, **replacements)
                    return row

                with mock.patch.object(
                    builder,
                    "_static_for_role",
                    side_effect=invalid_proxy_row,
                ):
                    package = builder.build_screen()
                self.assertEqual(len(package["representatives"]), 12)
                target = next(
                    row
                    for row in package["representatives"]
                    if row["branch_id"] == target_branch
                    and row["role_id"] == target_role
                )
                self.assertFalse(target["eligible_for_slx"])
                self.assertEqual(
                    target["timescale_relation"], "not_available"
                )
                self.assertEqual(
                    target["rejection_reasons"].count(
                        "nonpositive_or_nonfinite_proxy_derived_quantity"
                    ),
                    1,
                )

    def test_every_ineligible_representative_has_a_machine_reason(self):
        package = builder.build_screen()
        for row in package["representatives"]:
            if not row["eligible_for_slx"]:
                self.assertTrue(row["rejection_reasons"])

        original = builder._static_for_role

        def reasonless_unidentifiable(rows, branch_id, role):
            row = original(rows, branch_id, role)
            if role.role_id == contract.ROLES[1].role_id:
                return replace(
                    row,
                    condition_status="unidentifiable_due_to_missing_input",
                    rejection_reasons=(),
                )
            return row

        with mock.patch.object(
            builder,
            "_static_for_role",
            side_effect=reasonless_unidentifiable,
        ):
            package = builder.build_screen()
        for row in package["representatives"]:
            if not row["eligible_for_slx"]:
                self.assertTrue(row["rejection_reasons"])
                if row["role_id"] == contract.ROLES[1].role_id:
                    self.assertIn(
                        "source_row_not_eligible", row["rejection_reasons"]
                    )

    def test_unplanned_output_entries_are_rejected_without_change(self):
        setup_kinds = ("file", "directory", "symlink")
        for setup_kind in setup_kinds:
            with self.subTest(kind=setup_kind), tempfile.TemporaryDirectory(
                dir=ROOT / "tmp"
            ) as folder, tempfile.TemporaryDirectory() as outside:
                output = Path(folder)
                entry = output / "unplanned"
                if setup_kind == "file":
                    entry.write_text("user-data\n", encoding="utf-8")
                elif setup_kind == "directory":
                    entry.mkdir()
                else:
                    entry.symlink_to(Path(outside) / "target")
                before = snapshot_tree(output)
                with self.assertRaises((ValueError, FileExistsError)):
                    builder.write_screen(output)
                self.assertEqual(snapshot_tree(output), before)

    def test_output_hashes_cover_exact_in_memory_planned_payloads(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            hashes_path = output / "source_contract/output_hashes.json"
            hashes = json.loads(hashes_path.read_text(encoding="utf-8"))
            final_files = {
                str(path.relative_to(output)): hashlib.sha256(
                    path.read_bytes()
                ).hexdigest()
                for path in output.rglob("*")
                if path.is_file()
            }
            self.assertNotIn(
                "source_contract/output_hashes.json", hashes
            )
            final_files.pop("source_contract/output_hashes.json")
            self.assertEqual(hashes, final_files)
            self.assertEqual(set(hashes), set(final_files))

    def test_static_role_rejects_any_source_identity_drift(self):
        rows = builder.a1math.generate_static_rows()
        branch = contract.BRANCHES[0]
        role = contract.ROLES[1]
        source = builder._static_for_role(rows, branch.branch_id, role)
        source_index = rows.index(source)
        mutations = {
            "wrong_case": {"flow_case": "wrong_case"},
            "empty_evidence": {"evidence_status_per_input": ""},
            "wrong_maturity": {"technology_maturity": "wrong"},
            "wrong_row_id": {"row_id": source.row_id + "__wrong"},
            "tolerance_drift": {
                "m_dot_NaK_kg_s": source.m_dot_NaK_kg_s + 5e-10
            },
            "invalid_condition": {"condition_status": "unknown"},
        }
        for case_name, changes in mutations.items():
            with self.subTest(case=case_name):
                mutated_rows = list(rows)
                mutated_rows[source_index] = replace(source, **changes)
                with self.assertRaises(ValueError):
                    builder._static_for_role(
                        mutated_rows, branch.branch_id, role
                    )

    def test_static_role_rejects_empty_contract_axis_evidence(self):
        role = contract.ROLES[0]
        bad_flow = replace(contract.FLOWS[0], evidence="")
        with mock.patch.object(
            builder.contract,
            "FLOWS",
            (bad_flow, *contract.FLOWS[1:]),
        ):
            with self.assertRaises(ValueError):
                builder._static_for_role(
                    builder.a1math.generate_static_rows(),
                    contract.BRANCHES[0].branch_id,
                    role,
                )

    def test_selection_and_all_layers_keep_nonpromotion_flags_false(self):
        package = builder.build_screen()
        self.assertFalse(package["paper_reproduced"])
        self.assertFalse(package["formal_promotion"])
        self.assertFalse(package["source_contract"]["paper_reproduced"])
        self.assertFalse(package["source_contract"]["formal_promotion"])
        for row in package["representatives"]:
            self.assertFalse(row["paper_reproduced"])
            self.assertFalse(row["formal_promotion"])

        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            selection = json.loads(
                (output / "representatives/selection.json").read_text(
                    encoding="utf-8"
                )
            )
            self.assertFalse(selection["paper_reproduced"])
            self.assertFalse(selection["formal_promotion"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
