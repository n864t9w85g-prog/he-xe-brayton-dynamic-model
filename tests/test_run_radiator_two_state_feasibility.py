import ast
import contextlib
import csv
import hashlib
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock

from tests import radiator_two_state_contract as contract


ROOT = Path(__file__).resolve().parents[1]
RUNTIME_PATHS = (
    ROOT / "tests/radiator_two_state_contract.py",
    ROOT / "tests/radiator_two_state_math.py",
    ROOT / "tests/run_radiator_two_state_feasibility.py",
)
OUTPUT_NAMES = {
    "summary.json",
    "intervals.csv",
    "corner_ranges.csv",
    "source_hashes.json",
    "protected_before.json",
    "protected_after.json",
    "report.md",
    "output_hashes.json",
}


class RadiatorTwoStateFeasibilityRunnerTests(unittest.TestCase):
    def temporary_run_dir(self):
        folder = tempfile.TemporaryDirectory(dir=ROOT / "tmp")
        self.addCleanup(folder.cleanup)
        return Path(folder.name) / "run"

    def temporary_parent_and_run_dir(self):
        folder = tempfile.TemporaryDirectory(dir=ROOT / "tmp")
        self.addCleanup(folder.cleanup)
        parent = Path(folder.name)
        return parent, parent / "published_run"

    @staticmethod
    def sha256(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def test_fresh_run_writes_complete_verifiable_scientific_bundle(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        result = runner.run(run_dir)
        self.assertEqual(set(path.name for path in run_dir.iterdir()), OUTPUT_NAMES)
        self.assertIn(result["result_enum"], runner.SCIENTIFIC_ENUMS)
        summary = json.loads((run_dir / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(summary["schema"], "radiator_two_state_feasibility_v1")
        self.assertEqual(summary["result_enum"], result["result_enum"])
        self.assertEqual(summary["case_count"], 4)
        self.assertEqual(summary["interval_count_per_case"], 11)
        self.assertEqual(summary["Tin_K"], contract.TIN_K)
        self.assertEqual(summary["temperature_allowance_K"], contract.TEMPERATURE_ALLOWANCE_K)
        self.assertEqual(summary["time_allowance_s"], contract.TIME_ALLOWANCE_S)
        self.assertEqual(summary["paper_reproduced"], False)
        self.assertEqual(summary["author_parameter_identified"], False)
        self.assertEqual(summary["formal_promotion"], False)
        expected_case_keys = {
            "case_id", "flow_id", "m_dot_kg_s", "energy_path", "case_enum",
            "nominal_sign_gate", "favorable_sign_gate", "unrestricted_solution",
            "nnls_solution", "equivalent_mass_kg", "all_intervals_locally_compatible",
        }
        self.assertEqual(len(summary["cases"]), 4)
        self.assertTrue(all(set(item) == expected_case_keys for item in summary["cases"]))
        for item in summary["cases"]:
            self.assertEqual(
                set(item["unrestricted_solution"]),
                {"C_fluid_J_K", "UA_W_K", "sse_J2"},
            )
            self.assertEqual(
                set(item["nnls_solution"]),
                {"C_fluid_J_K", "UA_W_K", "sse_J2"},
            )
        with (run_dir / "intervals.csv").open(newline="", encoding="utf-8") as handle:
            interval_rows = list(csv.DictReader(handle))
            self.assertEqual(
                tuple(interval_rows[0]),
                ("case_id", "interval_index", "start_s", "end_s", "A_K", "B_K_s", "D_J", "residual_J", "relative_residual", "conditional_C_fluid_J_K"),
            )
        self.assertEqual(len(interval_rows), 44)
        with (run_dir / "corner_ranges.csv").open(newline="", encoding="utf-8") as handle:
            corner_rows = list(csv.DictReader(handle))
            self.assertEqual(
                tuple(corner_rows[0]),
                ("case_id", "interval_index", "minimum_J", "maximum_J", "contains_zero", "admissible_corner_count"),
            )
        self.assertEqual(len(corner_rows), 44)
        before = json.loads((run_dir / "protected_before.json").read_text())
        after = json.loads((run_dir / "protected_after.json").read_text())
        self.assertEqual(before, after)
        self.assertEqual(before, contract.snapshot_protected_files())
        self.assertEqual(set(before), set(contract.PROTECTED_RELATIVE_PATHS))
        source_hashes = json.loads((run_dir / "source_hashes.json").read_text())
        expected_sources = {
            path.relative_to(ROOT).as_posix()
            for path in (
                contract.SPEC, contract.PAPER, contract.POINTS_CSV,
                contract.POINTS_PROVENANCE, *RUNTIME_PATHS,
            )
        }
        self.assertEqual(set(source_hashes), expected_sources)
        self.assertTrue(all(len(value) == 64 and value == value.lower() for value in source_hashes.values()))
        self.assertEqual(
            source_hashes,
            {relative: self.sha256(ROOT / relative) for relative in source_hashes},
        )
        output_hashes = json.loads((run_dir / "output_hashes.json").read_text())
        self.assertEqual(set(output_hashes), OUTPUT_NAMES - {"output_hashes.json"})
        self.assertEqual(
            output_hashes,
            {name: self.sha256(run_dir / name) for name in output_hashes},
        )
        self.assertNotIn("NaN", (run_dir / "summary.json").read_text())
        evidence = contract.verify_input_contract()
        expected_analyses = tuple(
            runner.model.analyze_case(case, evidence.samples)
            for case in contract.CASES
        )
        self.assertEqual(
            [item["case_id"] for item in summary["cases"]],
            [analysis.case.case_id for analysis in expected_analyses],
        )
        self.assertEqual(
            [item["case_enum"] for item in summary["cases"]],
            [analysis.case_enum for analysis in expected_analyses],
        )
        expected_intervals = [
            (analysis, item)
            for analysis in expected_analyses
            for item in analysis.intervals
        ]
        self.assertEqual(len(expected_intervals), 44)
        for row, (analysis, expected) in zip(interval_rows, expected_intervals):
            coefficient = expected.coefficient
            self.assertEqual(row["case_id"], analysis.case.case_id)
            self.assertEqual(int(row["interval_index"]), coefficient.interval_index)
            for field, value in (
                ("start_s", coefficient.start_s), ("end_s", coefficient.end_s),
                ("A_K", coefficient.A_K), ("B_K_s", coefficient.B_K_s),
                ("D_J", coefficient.D_J), ("residual_J", expected.residual_J),
                ("relative_residual", expected.relative_residual),
            ):
                self.assertEqual(float(row[field]), value)
            if expected.conditional_C_fluid_J_K is None:
                self.assertEqual(row["conditional_C_fluid_J_K"], "")
            else:
                self.assertEqual(
                    float(row["conditional_C_fluid_J_K"]),
                    expected.conditional_C_fluid_J_K,
                )
        for row, (analysis, expected) in zip(corner_rows, expected_intervals):
            corner = expected.corner_range
            self.assertEqual(row["case_id"], analysis.case.case_id)
            self.assertEqual(int(row["interval_index"]), expected.coefficient.interval_index)
            if corner is None:
                self.assertEqual((row["minimum_J"], row["maximum_J"], row["contains_zero"], row["admissible_corner_count"]), ("", "", "false", "0"))
            else:
                self.assertEqual(float(row["minimum_J"]), corner.minimum_J)
                self.assertEqual(float(row["maximum_J"]), corner.maximum_J)
                self.assertEqual(row["contains_zero"], str(corner.contains_zero).lower())
                self.assertEqual(int(row["admissible_corner_count"]), corner.admissible_corner_count)
        report = (run_dir / "report.md").read_text(encoding="utf-8")
        self.assertIn("| Category | Path/Identity | SHA-256/Status |", report)
        for path in (
            contract.SPEC,
            contract.PAPER,
            contract.POINTS_CSV,
            contract.POINTS_PROVENANCE,
        ):
            relative = path.relative_to(ROOT).as_posix()
            self.assertIn(relative, report)
            self.assertIn(source_hashes[relative], report)
        for path in RUNTIME_PATHS:
            relative = path.relative_to(ROOT).as_posix()
            self.assertIn(relative, report)
            self.assertIn(source_hashes[relative], report)
        self.assertIn("verified_unchanged", report)
        self.assertIn("受保护文件在本次运行前后字节完全一致", report)
        self.assertIn("不构成获批基线身份认定", report)
        for flag in contract.FALSE_FLAGS:
            self.assertIn(f"`{flag}=false`", report)

    def test_existing_run_directory_is_rejected_without_touching_marker(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        run_dir.mkdir()
        marker = run_dir / "marker.txt"
        marker.write_text("keep", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            runner.run(run_dir)
        self.assertEqual(marker.read_text(encoding="utf-8"), "keep")
        self.assertEqual(set(path.name for path in run_dir.iterdir()), {"marker.txt"})

    def test_exclusive_directory_publish_preserves_existing_empty_target(self):
        from tests import run_radiator_two_state_feasibility as runner

        parent, run_dir = self.temporary_parent_and_run_dir()
        run_dir.mkdir()
        staging = Path(tempfile.mkdtemp(prefix=".stage.", dir=parent))
        try:
            with self.assertRaises(FileExistsError):
                runner._publish_directory_exclusive(staging, run_dir)
            self.assertTrue(run_dir.is_dir())
            self.assertEqual(list(run_dir.iterdir()), [])
            self.assertTrue(staging.is_dir())
        finally:
            runner._remove_staging_directory(staging)

    def test_altered_points_produces_contract_failure_only(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            points = Path(folder) / "points.csv"
            shutil.copyfile(contract.POINTS_CSV, points)
            points.write_text(points.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            result = runner.run(run_dir, points)
        self.assertEqual(result["result_enum"], "evidence_contract_failure")
        self.assertEqual(set(path.name for path in run_dir.iterdir()), {"contract_failure.json"})
        failure = json.loads((run_dir / "contract_failure.json").read_text())
        self.assertEqual(failure["schema"], "radiator_two_state_contract_failure_v1")
        self.assertEqual(failure["result_enum"], "evidence_contract_failure")
        self.assertEqual(failure["protected_snapshot_status"], "verified_unchanged")
        self.assertEqual(failure["protected_before"], failure["protected_after"])
        self.assertEqual(failure["protected_before"], contract.snapshot_protected_files())
        self.assertEqual(failure["paper_reproduced"], False)
        self.assertEqual(failure["author_parameter_identified"], False)
        self.assertEqual(failure["formal_promotion"], False)
        self.assertEqual(
            set(failure),
            {
                "schema", "result_enum", "exception_type", "exception_message",
                "protected_before", "protected_after", "protected_snapshot_status",
                "paper_reproduced", "author_parameter_identified", "formal_promotion",
            },
        )
        for scientific_key in ("cases", "case_count", "interval_count_per_case", "Tin_K"):
            self.assertNotIn(scientific_key, failure)

    def test_protected_snapshot_contract_error_is_labeled_as_contract_failure(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        failure = contract.EvidenceContractError("protected input unavailable")
        with mock.patch.object(
            runner.contract, "snapshot_protected_files", side_effect=failure
        ):
            result = runner.run(run_dir)
        self.assertEqual(result["result_enum"], "evidence_contract_failure")
        payload = json.loads((run_dir / "contract_failure.json").read_text())
        self.assertEqual(payload["protected_snapshot_status"], "initial_unavailable")
        self.assertIsNone(payload["protected_before"])
        self.assertIsNone(payload["protected_after"])
        self.assertEqual(
            set(payload),
            {
                "schema", "result_enum", "exception_type", "exception_message",
                "protected_before", "protected_after", "protected_snapshot_status",
                "paper_reproduced", "author_parameter_identified", "formal_promotion",
            },
        )

    def test_final_protected_snapshot_error_is_not_presented_as_unchanged(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        before = contract.snapshot_protected_files()
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            points = Path(folder) / "points.csv"
            shutil.copyfile(contract.POINTS_CSV, points)
            points.write_text(points.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with mock.patch.object(
                runner.contract,
                "snapshot_protected_files",
                side_effect=(before, contract.EvidenceContractError("final unavailable")),
            ):
                runner.run(run_dir, points)
        payload = json.loads((run_dir / "contract_failure.json").read_text())
        self.assertEqual(payload["protected_snapshot_status"], "final_unavailable")
        self.assertEqual(payload["protected_before"], before)
        self.assertIsNone(payload["protected_after"])

    def test_intervals_write_failure_removes_the_entire_staged_bundle(self):
        from tests import run_radiator_two_state_feasibility as runner

        parent, run_dir = self.temporary_parent_and_run_dir()
        real_atomic_text = runner._atomic_text

        def fail_intervals(path, content):
            if Path(path).name == "intervals.csv":
                raise OSError("injected intervals failure")
            return real_atomic_text(path, content)

        with mock.patch.object(runner, "_atomic_text", side_effect=fail_intervals):
            with self.assertRaisesRegex(OSError, "injected intervals failure"):
                runner.run(run_dir)
        self.assertFalse(run_dir.exists())
        self.assertFalse((run_dir / "summary.json").exists())
        self.assertFalse(any(run_dir.name in path.name for path in parent.iterdir()))

    def test_keyboard_interrupt_during_atomic_write_removes_the_entire_staged_bundle(self):
        from tests import run_radiator_two_state_feasibility as runner

        parent, run_dir = self.temporary_parent_and_run_dir()
        with mock.patch.object(runner.os, "fsync", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                runner.run(run_dir)
        self.assertFalse(run_dir.exists())
        self.assertFalse((run_dir / "summary.json").exists())
        self.assertFalse(any(run_dir.name in path.name for path in parent.iterdir()))

    def test_source_hash_change_before_write_aborts_without_publication(self):
        from tests import run_radiator_two_state_feasibility as runner

        _, run_dir = self.temporary_parent_and_run_dir()
        before = runner._source_hashes()
        changed_after = dict(before)
        first_key = next(iter(changed_after))
        changed_after[first_key] = "0" * 64
        with mock.patch.object(
            runner, "_source_hashes", side_effect=(before, changed_after)
        ):
            with self.assertRaisesRegex(RuntimeError, "source files changed"):
                runner.run(run_dir)
        self.assertFalse(run_dir.exists())

    def test_zero_source_hashes_fail_before_contract_verification_or_publication(self):
        from tests import run_radiator_two_state_feasibility as runner

        parent, run_dir = self.temporary_parent_and_run_dir()
        zeroes = {name: "0" * 64 for name in runner._source_hashes()}
        with mock.patch.object(runner, "_source_hashes", return_value=zeroes):
            with mock.patch.object(
                runner.contract,
                "verify_input_contract",
                side_effect=AssertionError("verify must not run"),
            ):
                with self.assertRaisesRegex(RuntimeError, "frozen source digest"):
                    runner.run(run_dir)
        self.assertFalse(run_dir.exists())
        self.assertFalse(any(run_dir.name in path.name for path in parent.iterdir()))

    def test_source_change_after_verify_aborts_before_analysis_or_publication(self):
        from tests import run_radiator_two_state_feasibility as runner

        parent, run_dir = self.temporary_parent_and_run_dir()
        before = runner._source_hashes()
        changed = dict(before)
        changed[next(iter(changed))] = "0" * 64
        with mock.patch.object(runner, "_source_hashes", side_effect=(before, changed)):
            with mock.patch.object(
                runner.model,
                "analyze_case",
                side_effect=AssertionError("analysis must not run"),
            ):
                with self.assertRaisesRegex(RuntimeError, "source files changed after verify"):
                    runner.run(run_dir)
        self.assertFalse(run_dir.exists())
        self.assertFalse(any(run_dir.name in path.name for path in parent.iterdir()))

    def test_contract_returned_source_identity_mismatch_aborts_without_publication(self):
        from tests import run_radiator_two_state_feasibility as runner

        _, run_dir = self.temporary_parent_and_run_dir()
        evidence = contract.verify_input_contract()
        bad_sources = dict(evidence.source_hashes)
        bad_sources["spec"] = "0" * 64
        bad_evidence = contract.Evidence(evidence.header, evidence.samples, bad_sources)
        with mock.patch.object(
            runner.contract, "verify_input_contract", return_value=bad_evidence
        ):
            with self.assertRaisesRegex(RuntimeError, "contract evidence source digest"):
                runner.run(run_dir)
        self.assertFalse(run_dir.exists())

    def test_source_or_protected_final_change_aborts_after_staging_without_publication(self):
        from tests import run_radiator_two_state_feasibility as runner

        for label in ("source", "protected"):
            with self.subTest(label=label):
                parent, run_dir = self.temporary_parent_and_run_dir()
                if label == "source":
                    before = runner._source_hashes()
                    changed = dict(before)
                    changed[next(iter(changed))] = "0" * 64
                    source_patch = mock.patch.object(
                        runner, "_source_hashes", side_effect=(before, before, changed)
                    )
                    protected_patch = contextlib.nullcontext()
                    message = "source files changed during final publication check"
                else:
                    before = contract.snapshot_protected_files()
                    changed = dict(before)
                    changed[next(iter(changed))] = "0" * 64
                    source_patch = contextlib.nullcontext()
                    protected_patch = mock.patch.object(
                        runner.contract,
                        "snapshot_protected_files",
                        side_effect=(before, before, changed),
                    )
                    message = "protected files changed during final publication check"
                with source_patch, protected_patch:
                    with self.assertRaisesRegex(RuntimeError, message):
                        runner.run(run_dir)
                self.assertFalse(run_dir.exists())
                self.assertFalse(any(run_dir.name in path.name for path in parent.iterdir()))

    def test_math_error_propagates_and_is_not_labeled_as_contract_failure(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        with mock.patch.object(runner.model, "analyze_case", side_effect=ValueError("boom")):
            with self.assertRaisesRegex(ValueError, "boom"):
                runner.run(run_dir)
        self.assertFalse((run_dir / "contract_failure.json").exists())

    def test_analyze_case_is_called_exactly_once_per_case_in_contract_order(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        real_analyze = runner.model.analyze_case
        called = []

        def recording(case, samples):
            called.append(case.case_id)
            return real_analyze(case, samples)

        with mock.patch.object(runner.model, "analyze_case", side_effect=recording):
            runner.run(run_dir)
        self.assertEqual(called, [case.case_id for case in contract.CASES])

    def test_runtime_modules_contain_no_model_or_external_execution_path(self):
        combined = "\n".join(path.read_text(encoding="utf-8") for path in RUNTIME_PATHS)
        for forbidden in (
            "load_system", "save_system", "sim(", "matlab.engine", "subprocess",
            "zipfile", "writestr(", "wolfram", "__import__", "import_module",
            "urlopen", "requests", "socket", "http.client", "ftplib", "aiohttp",
            "httpx",
        ):
            self.assertNotIn(forbidden, combined.lower())

    def test_runtime_modules_use_only_the_offline_import_allowlist(self):
        allowed = {
            "__future__", "argparse", "csv", "ctypes", "dataclasses", "errno", "hashlib", "io",
            "itertools", "json", "math", "os", "pathlib", "shutil", "sys", "tempfile",
            "tests", "types", "typing",
        }
        for path in RUNTIME_PATHS:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for node in ast.walk(tree):
                if isinstance(node, ast.Import):
                    roots = [item.name.split(".", 1)[0] for item in node.names]
                elif isinstance(node, ast.ImportFrom):
                    roots = [node.module.split(".", 1)[0]] if node.module else []
                else:
                    continue
                for root in roots:
                    self.assertIn(root, allowed, f"{path}: unexpected import {root}")

    @staticmethod
    def _ast_boundary_violations(source: str) -> list[str]:
        allowed = {
            "__future__", "argparse", "csv", "ctypes", "dataclasses", "errno", "hashlib", "io",
            "itertools", "json", "math", "os", "pathlib", "shutil", "sys",
            "tempfile", "tests", "types", "typing",
        }
        powerful = {"os", "shutil", "ctypes"}
        allowed_chains = {
            "os": {("os", "fdopen"), ("os", "fsync"), ("os", "replace"), ("os", "fsencode")},
            "shutil": {("shutil", "rmtree")},
            "ctypes": {
                ("ctypes", "CDLL"), ("ctypes", "get_errno"),
                ("ctypes", "c_char_p"), ("ctypes", "c_uint"),
                ("ctypes", "c_int"),
            },
        }
        aliases = {}
        native_handles = {}
        rename_functions = set()
        violations = []
        tree = ast.parse(source)

        def chain(node):
            if isinstance(node, ast.Name):
                return (node.id,)
            if isinstance(node, ast.Attribute):
                parent = chain(node.value)
                return None if parent is None else parent + (node.attr,)
            if isinstance(node, ast.Call):
                return chain(node.func)
            return None

        def module_chain(candidate):
            if not candidate or candidate[0] not in aliases:
                return None
            return (aliases[candidate[0]],) + candidate[1:]

        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for item in node.names:
                    root = item.name.split(".", 1)[0]
                    if root not in allowed:
                        violations.append(f"import:{root}")
                    if root in powerful:
                        aliases[item.asname or root] = root
            elif isinstance(node, ast.ImportFrom) and node.module:
                root = node.module.split(".", 1)[0]
                if root not in allowed:
                    violations.append(f"import:{root}")
                if root in powerful:
                    violations.append(f"from-import:{root}")
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assign):
                continue
            targets = [target.id for target in node.targets if isinstance(target, ast.Name)]
            if not targets:
                continue
            if isinstance(node.value, ast.Name) and node.value.id in aliases:
                for target in targets:
                    aliases[target] = aliases[node.value.id]
                continue
            value_chain = chain(node.value)
            normalized = module_chain(value_chain)
            if isinstance(node.value, ast.Call) and normalized == ("ctypes", "CDLL"):
                for target in targets:
                    native_handles[target] = "ctypes"
                continue
            if (
                isinstance(node.value, ast.Attribute)
                and value_chain
                and value_chain[0] in native_handles
                and value_chain == (value_chain[0], "renamex_np")
            ):
                rename_functions.update(targets)
        for node in ast.walk(tree):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
                direct = node.func.id
                if direct in {"eval", "exec", "__import__", "compile", "import_module", "system"}:
                    violations.append(f"dynamic:{direct}")
                if direct in {"getattr", "vars", "globals", "locals"}:
                    powerful_argument = any(
                        (candidate := chain(argument))
                        and (candidate[0] in aliases or candidate[0] in native_handles)
                        for argument in node.args
                    )
                    if direct != "getattr" or powerful_argument:
                        violations.append(f"dynamic:{direct}")
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Attribute, ast.Call)):
                continue
            candidate = chain(node if isinstance(node, ast.Attribute) else node.func)
            if not candidate:
                continue
            normalized = module_chain(candidate)
            if normalized is not None:
                module = normalized[0]
                if normalized not in allowed_chains[module]:
                    violations.append("chain:" + ".".join(normalized))
                continue
            if candidate[0] in native_handles:
                allowed_handle_attribute = candidate == (candidate[0], "renamex_np")
                if not allowed_handle_attribute:
                    violations.append("handle:ctypes." + ".".join(candidate[1:]))
                elif isinstance(node, ast.Call):
                    violations.append("handle:ctypes.renamex_np")
                continue
            if candidate[0] in rename_functions:
                allowed = (
                    candidate == (candidate[0],)
                    and isinstance(node, ast.Call)
                ) or candidate in {
                    (candidate[0], "argtypes"), (candidate[0], "restype"),
                }
                if not allowed:
                    violations.append("rename-function:" + ".".join(candidate))
        return violations

    def test_ast_boundary_guard_rejects_dangerous_synthetic_constructs(self):
        self.assertIn("chain:os.system", self._ast_boundary_violations("import os as alias\nalias.system('x')"))
        self.assertIn("from-import:os", self._ast_boundary_violations("from os import system\nsystem('x')"))
        self.assertIn("chain:shutil.move", self._ast_boundary_violations("import shutil as s\ns.move('a', 'b')"))
        self.assertIn("chain:ctypes.CDLL.system", self._ast_boundary_violations("import ctypes as c\nc.CDLL(None).system('x')"))
        self.assertIn("handle:ctypes.system", self._ast_boundary_violations("import ctypes\nlibc = ctypes.CDLL(None)\nlibc.system('x')"))
        self.assertIn("chain:os.system", self._ast_boundary_violations("import os\nrunner = os\nrunner.system('x')"))
        self.assertIn("dynamic:getattr", self._ast_boundary_violations("import os\ngetattr(os, 'system')('x')"))
        self.assertIn("import:socket", self._ast_boundary_violations("import socket as safe"))
        self.assertIn("dynamic:__import__", self._ast_boundary_violations("__import__('socket')"))

    def test_runtime_modules_pass_ast_call_boundary(self):
        for path in RUNTIME_PATHS:
            self.assertEqual(self._ast_boundary_violations(path.read_text(encoding="utf-8")), [])

    def test_main_prints_compact_status_and_uses_scientific_exit_zero(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            exit_code = runner.main(["--run-dir", str(run_dir)])
        self.assertEqual(exit_code, 0)
        line = stdout.getvalue()
        self.assertEqual(line.count("\n"), 1)
        payload = json.loads(line)
        self.assertEqual(
            set(payload),
            {
                "run_dir", "result_enum", "paper_reproduced",
                "author_parameter_identified", "formal_promotion",
            },
        )
        self.assertEqual(payload["run_dir"], str(run_dir.resolve()))
        self.assertIn(payload["result_enum"], runner.SCIENTIFIC_ENUMS)
        self.assertNotIn("--points-path", (ROOT / "tests/run_radiator_two_state_feasibility.py").read_text())

    def test_main_prints_compact_contract_failure_and_uses_exit_two(self):
        from tests import run_radiator_two_state_feasibility as runner

        run_dir = self.temporary_run_dir()
        result = {
            "result_enum": "evidence_contract_failure",
            **dict(contract.FALSE_FLAGS),
        }
        stdout = io.StringIO()
        with mock.patch.object(runner, "run", return_value=result) as mocked_run:
            with contextlib.redirect_stdout(stdout):
                exit_code = runner.main(["--run-dir", str(run_dir)])
        self.assertEqual(exit_code, 2)
        mocked_run.assert_called_once_with(run_dir.resolve())
        payload = json.loads(stdout.getvalue())
        self.assertEqual(
            payload,
            {
                "run_dir": str(run_dir.resolve()),
                "result_enum": "evidence_contract_failure",
                **dict(contract.FALSE_FLAGS),
            },
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
