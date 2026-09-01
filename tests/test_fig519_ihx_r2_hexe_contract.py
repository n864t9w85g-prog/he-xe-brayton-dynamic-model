from __future__ import annotations

import ast
import copy
import contextlib
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from decimal import Decimal, localcontext
from pathlib import Path
from unittest import mock

from tests import fig519_ihx_r2_hexe_contract as contract
from tests import analyze_fig519_ihx_r2_hexe_shift as analysis


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "tests/create_fig519_ihx_r2_hexe_shift_candidate.m"
MATLAB_GENERATOR_TEST = ROOT / "tests/test_create_fig519_ihx_r2_hexe_shift_candidate.m"
RUNNER = ROOT / "tests/run_fig519_ihx_r2_hexe_shift.m"
MATLAB_RUNNER_TEST = ROOT / "tests/test_run_fig519_ihx_r2_hexe_shift.m"


def _forbidden_slx_editing_intents(source: str) -> tuple[str, ...]:
    """Return findings for direct or string-indirected SLX archive editing."""
    lowered = source.lower()
    direct_patterns = {
        "simulation call": r"(?<![a-z0-9_])sim\s*\(",
        "simulation function handle": r"@\s*sim\b",
        "batch simulation API": (
            r"(?<![a-z0-9_])(?:parsim|batchsim)\s*\(|"
            r"\bsimulink\.multisim(?:\.[a-z0-9_]+)*\.simulate\s*\("
        ),
        "subprocess primitive": (
            r"(?<![a-z0-9_])(?:system|unix|dos|perl|pyrun|pyrunfile)\s*\("
        ),
        "dynamic execution primitive": (
            r"(?<![a-z0-9_])(?:eval|feval|str2func|builtin)\s*\("
        ),
        "Java Runtime execution": (
            r"\bjava\.lang\.runtime(?:\.getruntime\s*\(\))?\.exec\s*\("
        ),
        "Python subprocess execution": (
            r"\bpy\.subprocess\.(?:run|popen|call|check_call|check_output)\s*\("
        ),
        "Python process execution": (
            r"\bpy\.(?:os\.(?:system|popen|spawn[a-z0-9_]*)|"
            r"subprocess\.[a-z0-9_]+)\s*\("
        ),
        "Java process builder": r"\bjava\.lang\.processbuilder\s*\(",
        "MATLAB bang shell": r"(?m)^\s*!",
        "generic XML API": r"\b(?:xml[a-z0-9_]*|matlab\.io\.xml(?:\.[a-z0-9_]+)+)\s*\(",
        "generic ZIP API": r"\b(?:zip|unzip|java\.util\.zip(?:\.[a-z0-9_]+)+)\s*\(",
        "archive extraction API": r"\b(?:untar|extractarchive|expandarchive)\s*\(",
        "generic unpack intent": r"\b(?:unpack|unpacking|unpacked|slxunpack|slxpack)\b",
        "BlockDiagram API": r"\b(?:simulink\.)?blockdiagram(?:\.[a-z0-9_]+)?\s*\(",
        "BlockDiagram editing helper": (
            r"\b(?:edit|modify|write|unpack)[a-z0-9_]*"
            r"blockdiagram[a-z0-9_]*\b"
        ),
    }
    findings = [
        label
        for label, pattern in direct_patterns.items()
        if re.search(pattern, lowered)
    ]

    identifiers = set(
        re.findall(
            r"(?<![a-z0-9_.])([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)\s*\(",
            lowered,
        )
    )
    literals = []
    for match in re.finditer(r'"((?:[^"]|"")*)"|\'((?:[^\']|\'\')*)\'', source):
        value = match.group(1) if match.group(1) is not None else match.group(2)
        literals.append(value.replace('""', '"').replace("''", "'").lower())
    collapsed_literals = re.sub(r"\s+", "", "".join(literals))

    archive_command = re.compile(
        r"(?:^|[;&|]\s*)(?:(?:unzip|zip)\s+\S+|"
        r"tar\s+(?:-[a-z]*[xf][a-z]*|--extract)\b)"
    )
    if any(archive_command.search(literal) for literal in literals):
        findings.append("archive command string payload")
    if any(
        re.search(r"\b(?:unpack|unpacking|unpacked|slxunpack|slxpack)\b", literal)
        for literal in literals
    ):
        findings.append("unpack string payload")
    if "readstruct" in identifiers and {"filetype", "xml"}.issubset(literals):
        findings.append("readstruct XML string options")
    if "javaobject" in identifiers and any(
        literal.startswith("java.util.zip.") for literal in literals
    ):
        findings.append("javaObject ZIP class string")
    if "feval" in identifiers and any(
        literal.startswith("simulink.blockdiagram.") for literal in literals
    ):
        findings.append("feval BlockDiagram method string")
    if "javaobject" in identifiers and "java.util.zip." in collapsed_literals:
        findings.append("concatenated javaObject ZIP class string")
    if "readstruct" in identifiers and all(
        token in collapsed_literals for token in ("filetype", "xml")
    ):
        findings.append("concatenated readstruct XML options")
    if "simulink.blockdiagram." in collapsed_literals:
        findings.append("concatenated BlockDiagram method string")

    allowed_python_import = 'py.importlib.import_module("os")'
    for call in _matlab_calls(source, "py.importlib.import_module"):
        normalized = re.sub(r"\s+|\.\.\.", "", call.lower())
        if normalized != allowed_python_import:
            findings.append("non-allowlisted dynamic Python import")
    if "matlab" in collapsed_literals and "-batch" in collapsed_literals:
        findings.append("foreign MATLAB batch process payload")

    allowed_set_param = {
        'set_param(averagetarget,"initialcondition",'
        'num2str(newaveragek,"%.17g"))',
        'set_param(outlettarget,"initialcondition",'
        'num2str(newoutletk,"%.17g"))',
        'set_param(model,"simulationcommand","update")',
    }
    for call in _matlab_calls(source, "set_param"):
        normalized = re.sub(r"\s+|\.\.\.", "", call.lower())
        if normalized not in allowed_set_param:
            findings.append("non-allowlisted set_param")

    evalin_calls = len(re.findall(r"(?<![a-z0-9_])evalin\s*\(", lowered))
    allowed_startup = len(
        re.findall(
            r'evalin\s*\(\s*"base"\s*,\s*"run\("\s*\+\s*'
            r'matlabstring\(startpath\)\s*\+\s*"\)"\s*\)',
            lowered,
        )
    )
    if evalin_calls != allowed_startup:
        findings.append("non-allowlisted evalin")

    return tuple(dict.fromkeys(findings))


def _matlab_calls(source: str, identifier: str) -> list[str]:
    """Extract balanced MATLAB calls without being fooled by nested calls."""
    starts = re.finditer(rf"(?i)(?<![a-z0-9_]){re.escape(identifier)}\s*\(", source)
    calls: list[str] = []
    for match in starts:
        depth = 0
        quote: str | None = None
        index = match.start()
        while index < len(source):
            character = source[index]
            if quote is not None:
                if character == quote:
                    if index + 1 < len(source) and source[index + 1] == quote:
                        index += 2
                        continue
                    quote = None
            elif character in ('"', "'"):
                quote = character
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    calls.append(source[match.start() : index + 1])
                    break
            index += 1
    return calls


def _runner_invocation_findings(
    source: str, *, expected_direct_calls: int = 1
) -> tuple[str, ...]:
    lowered = source.lower()
    findings: list[str] = []
    direct = _matlab_calls(source, "run_steady53_case")
    if len(direct) != expected_direct_calls:
        findings.append("direct call count")
    first_local = lowered.find("\nfunction ", 1)
    if direct and first_local >= 0 and source.find(direct[0]) >= first_local:
        findings.append("call outside top level")
    forbidden = {
        "dynamic execution": r"(?<![a-z0-9_])(?:eval|feval|str2func|builtin)\s*\(",
        "workspace/script execution": (
            r"(?<![a-z0-9_])(?:run|evalin|evalc)\s*\("
        ),
        "simulation primitive": (
            r"(?<![a-z0-9_])(?:sim|parsim|batchsim)\s*\("
        ),
        "process primitive": (
            r"(?<![a-z0-9_])(?:system|unix|dos|perl|pyrun|pyrunfile)\s*\("
        ),
        "java process": r"\bjava\.lang\.(?:runtime|processbuilder)\b",
        "python process": r"\bpy\.(?:subprocess|os\.(?:system|popen|spawn))\b",
        "runner function handle": (
            r"@\s*(?:run_steady53_case|run_fig519_ihx_r2_hexe_shift|sim)\b"
        ),
    }
    for label, pattern in forbidden.items():
        if re.search(pattern, lowered):
            findings.append(label)
    main = re.search(
        r"(?im)^\s*function\s+(?:[^=\n]+?=\s*)?([a-z][a-z0-9_]*)\b",
        source,
    )
    if main is not None:
        body = source[source.find("\n", main.end()) + 1 :]
        if _matlab_calls(body, main.group(1)):
            findings.append("self recursion")
    return tuple(dict.fromkeys(findings))


MALICIOUS_DYNAMIC_EXECUTION = {
    "spaced sim": 'sim (model)',
    "feval sim": 'feval("sim", model)',
    "split feval sim": 'feval("s" + "im", model)',
    "str2func sim": 'runner = str2func("s" + "im")',
    "builtin sim": 'builtin("sim", model)',
    "eval sim": 'eval("s" + "im(model)")',
    "system primitive": 'system("true")',
    "unix primitive": 'unix("true")',
    "dos primitive": 'dos("true")',
    "perl primitive": 'perl("tool.pl")',
    "python primitive": 'pyrun("print(1)")',
    "split zip class": 'javaObject("java.util." + "zip.ZipFile", path)',
    "split XML": 'readstruct(path, "File" + "Type", "x" + "ml")',
    "split BlockDiagram": 'feval("Simulink.Block" + "Diagram.modify", model)',
    "function handle sim": 'runner = @sim; runner(model)',
    "parallel sim": 'parsim(inputs)',
    "rapid accelerator batch": 'simulink.multisim.DesignStudy.simulate(inputs)',
    "single quoted start": "set_param(model, 'SimulationCommand', 'start')",
    "split simulation start": (
        'set_param(model, "Simulation" + "Command", "st" + "art")'
    ),
    "java runtime exec": 'java.lang.Runtime.getRuntime().exec("tool")',
    "python subprocess": 'py.subprocess.run(args)',
    "indirect SimulationCommand": (
        'parameterName = "SimulationCommand"; command = "start"; '
        'set_param(model, parameterName, command)'
    ),
    "bang shell unzip": '!unzip candidate.slx',
    "java process builder": (
        'java.lang.ProcessBuilder("unzip", "candidate.slx").start()'
    ),
    "python os process": 'py.os.system("unzip candidate.slx")',
    "dynamic Python import and MATLAB batch sim": (
        'py.importlib.import_module("sub"+"process").run('
        '["matlab","-batch","s"+"im(model)"])'
    ),
}


class Figure519IhxR2HexeContractTests(unittest.TestCase):
    def _generator_source(self):
        self.assertTrue(GENERATOR.is_file(), "the A3 MATLAB generator is required")
        return GENERATOR.read_text(encoding="utf-8")

    def _runner_source(self):
        self.assertTrue(RUNNER.is_file(), "the A3 MATLAB runner is required")
        return RUNNER.read_text(encoding="utf-8")

    def test_a3_runner_has_exactly_one_blocking_case_call_and_no_retry(self):
        source = self._runner_source()
        self.assertRegex(
            source,
            r"(?m)^function status = "
            r"run_fig519_ihx_r2_hexe_shift\(runDir, repoRoot\)$",
        )
        calls = re.findall(
            r"runResult\s*=\s*run_steady53_case\(candidatePath,\s*500,\s*true\)\s*;",
            source,
        )
        self.assertEqual(calls, [
            "runResult = run_steady53_case(candidatePath, 500, true);"
        ])
        self.assertEqual(len(re.findall(r"\brun_steady53_case\s*\(", source)), 1)
        top_level = source[: source.index("\nfunction ", 1)]
        self.assertNotRegex(top_level, r"(?im)^\s*(?:for|while)\b")
        self.assertNotRegex(top_level, r"(?i)\b(?:retry|rerun)\s*\(")
        self.assertIn('"run_steady53_case_call_count", 1', source)
        self.assertIn('"retry_count", 0', source)
        self.assertEqual(_runner_invocation_findings(source), ())

    def test_runner_invocation_gate_rejects_dynamic_and_duplicate_calls(self):
        fixtures = {
            "helper twice": (
                "function x=f()\n"
                "x=run_steady53_case(candidatePath,500,true);\n"
                "x=run_steady53_case(candidatePath,500,true);\nend"
            ),
            "feval": (
                "function x=f()\n"
                'x=feval("run_steady53_case",candidatePath,500,true);\nend'
            ),
            "function handle": (
                "function x=f()\nrunner=@run_steady53_case; x=runner();\nend"
            ),
            "self recursion": (
                "function x=f()\n"
                "x=run_steady53_case(candidatePath,500,true); x=f();\nend"
            ),
            "run script": (
                "function x=f()\n"
                "x=run_steady53_case(candidatePath,500,true); run('x.m');\nend"
            ),
            "split evalin run": (
                "function x=f()\n"
                "x=run_steady53_case(candidatePath,500,true); "
                'evalin("base","r"+"un(\'x.m\')");\nend'
            ),
            "split evalc": (
                "function x=f()\n"
                "x=run_steady53_case(candidatePath,500,true); "
                'evalc("r"+"un(\'x.m\')");\nend'
            ),
        }
        for label, fixture in fixtures.items():
            with self.subTest(label=label):
                self.assertTrue(_runner_invocation_findings(fixture))

    def test_a3_runner_freezes_schema_paths_and_truthful_artifact_contract(self):
        source = self._runner_source()
        for literal in (
            '"steady53_fig519_ihx_r2_hexe_shift_candidate_v1"',
            '"steady53_fig519_ihx_r2_hexe_shift_run_v1"',
            '"20260901_A3"',
            '"figure_5_18a_t0_visual_proxy_not_author_initial_state"',
            '"IHX/IHX_region_2/T_c1_average_Integrator"',
            '"IHX/IHX_region_2/T_c2_out_Integrator"',
            '"time_s,reactor_W,turbine_W,compressor_W,ihx_r2_average_K,ihx_r2_outlet_K\\n"',
            '"paper_reproduced", false',
            '"author_initial_state_identified", false',
            '"formal_promotion", false',
            'fullfile(runPath, "experiment_started.json")',
            'fullfile(runPath, "raw_result.mat")',
            'fullfile(runPath, "candidate_curves.csv")',
            'fullfile(runPath, "reference_curves.csv")',
            'fullfile(runPath, "run_status.json")',
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)
        self.assertNotIn('save_system(', source)
        self.assertNotRegex(source, r'(?i)\bsim\s*\(')

    def test_a3_runner_matlab_test_uses_hooks_only(self):
        self.assertTrue(
            MATLAB_RUNNER_TEST.is_file(), "the A3 MATLAB runner test is required"
        )
        source = MATLAB_RUNNER_TEST.read_text(encoding="utf-8")
        self.assertIn(
            'hooks = run_fig519_ihx_r2_hexe_shift("__a3_test_hooks__", pwd);',
            source,
        )
        self.assertIn("hooks.testExclusiveTextCreation();", source)
        self.assertIn("hooks.testExclusiveDirectoryCreation();", source)
        self.assertIn("hooks.testThrownCallArtifactTruthfulness();", source)
        self.assertNotIn("BEGIN_A3_500", source)
        self.assertEqual(_matlab_calls(source, "run_steady53_case"), [])
        self.assertEqual(
            _runner_invocation_findings(source, expected_direct_calls=0), ()
        )

    def test_a3_runner_never_saves_synthetic_raw_after_a_thrown_call(self):
        source = self._runner_source()
        self.assertIn("callReturned = false;", source)
        self.assertIn("callReturned = true;", source)
        self.assertIn("if ~callReturned", source)
        self.assertIn('"run_steady53_case_returned", callReturned', source)
        self.assertNotIn("emptyFailureResult", source)

    def test_a3_runner_binds_inputs_raw_publication_and_exact_audit_sets(self):
        source = self._runner_source()
        for literal in (
            "bindInvocationInputs",
            "assertInvocationBindings",
            "assertInvocationHashes",
            "auditByteHash",
            "candidateFrozenHash",
            "createLink",
            "assertSameIdentity(stagingIdentity",
            "assertPosixDirectoryMode0700",
            '"33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"',
            "validateExactRuntimeSet",
            "validateExactProtectedSet",
            "validateProtectedRecords",
            "recalcProtectedRecords",
            "validateExactFormalSet",
            "validateStateInventoryValues",
            "assertNoSymlinkAncestors(filePath, repoRoot)",
            "bindCapturedMatlabHelpers",
            "assertCapturedMatlabHelpers",
            '"686749ffe329f71ed884e0f98d2681d6c35aa5df258ff6675917a55c20b9da42"',
            '"7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd"',
            '"04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0"',
            "freezeHookSandboxInventory",
            "assertHookInventoryUnchanged",
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)
        self.assertNotIn(
            "recalcRecords(audit.protected_files, repoRoot)", source
        )
        self.assertNotIn(
            'validateUnchangedRecords(audit.protected_files, repoRoot, "protected file")',
            source,
        )
        self.assertNotIn("cleanupHookOwnedDirectory", source)

    def test_a3_candidate_generator_has_the_frozen_public_contract(self):
        source = self._generator_source()
        self.assertRegex(
            source,
            r"(?m)^function audit = "
            r"create_fig519_ihx_r2_hexe_shift_candidate\(runDir, repoRoot\)$",
        )
        for literal in (
            "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
            "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
            "figure_5_18a_t0_visual_proxy_not_author_initial_state",
            "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)

    def test_a3_candidate_generator_uses_only_the_frozen_api_patch(self):
        source = self._generator_source()
        initial_condition_calls = re.findall(
            r"set_param\([^,\n]+,\s*(?:\.\.\.\s*)?[\r\n\s]*"
            r'"InitialCondition"\s*,',
            source,
        )
        self.assertEqual(len(initial_condition_calls), 2)
        update_calls = re.findall(
            r'set_param\([^,\n]+,\s*"SimulationCommand"\s*,\s*"update"\s*\)',
            source,
        )
        self.assertEqual(len(update_calls), 1)
        lowered = source.lower()
        for forbidden in (
            "sim(",
            '"simulationcommand", "start"',
            "run_steady53_case",
            "xmlread",
            "xmlwrite",
            "unzip(",
            "zip(",
            "blockdiagram.modify",
            "simulink.blockdiagram",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, lowered)
        self.assertEqual(_forbidden_slx_editing_intents(source), ())

    def test_static_editing_gate_rejects_indirect_string_payloads(self):
        malicious = {
            "system unzip": 'system("unzip candidate.slx")',
            "system zip": 'system("zip candidate.slx payload")',
            "system tar": 'system("tar -xf candidate.slx")',
            "readstruct XML": 'readstruct(path,"FileType","xml")',
            "javaObject ZIP": 'javaObject("java.util.zip.ZipFile",path)',
            "feval BlockDiagram": 'feval("Simulink.BlockDiagram.modify",model)',
        }
        for label, snippet in malicious.items():
            with self.subTest(label=label):
                self.assertTrue(_forbidden_slx_editing_intents(snippet), snippet)

        legitimate = "\n".join(
            (
                'sourcePath = fullfile(repo, "candidate.slx");',
                'hash = java.security.MessageDigest.getInstance("SHA-256");',
                'relative = extractAfter(canonical, prefix);',
                'set_param(averageTarget, "InitialCondition", '
                'num2str(newAverageK, "%.17g"));',
                'set_param(outletTarget, "InitialCondition", '
                'num2str(newOutletK, "%.17g"));',
                'set_param(model, "SimulationCommand", "update");',
            )
        )
        self.assertEqual(_forbidden_slx_editing_intents(legitimate), ())

    def test_static_gate_rejects_dynamic_execution_and_concatenated_payloads(self):
        for label, snippet in MALICIOUS_DYNAMIC_EXECUTION.items():
            with self.subTest(label=label):
                self.assertTrue(_forbidden_slx_editing_intents(snippet), snippet)

    def test_real_generator_has_one_narrow_startup_evalin_and_no_other_dynamic_exec(self):
        source = self._generator_source()
        self.assertEqual(_forbidden_slx_editing_intents(source), ())
        self.assertEqual(
            len(re.findall(r'\bevalin\s*\(', source, re.IGNORECASE)), 1
        )
        self.assertIn(
            'evalin("base", "run(" + matlabString(startPath) + ")")', source
        )
        self.assertNotRegex(
            source,
            r"(?i)\b(?:system|unix|dos|perl|pyrun|str2func|builtin|eval|feval)\s*\(",
        )
        simulation_commands = re.findall(
            r"set_param\s*\([^;]+?[\"']SimulationCommand[\"'][^;]+?\)",
            source,
            re.IGNORECASE | re.DOTALL,
        )
        self.assertEqual(
            simulation_commands,
            ['set_param(model, "SimulationCommand", "update")'],
        )
        self.assertIn(
            "ancestorConstructionCleanup = onCleanup", source
        )
        self.assertIn("restoreCallerStateOnCleanup", source)
        self.assertIn("fig519a3:FileDescriptorCloseFailed", source)
        self.assertNotRegex(
            source,
            r"clear\s+runFdCleanup\s*\n\s*closePythonFd",
        )

    def test_real_generator_set_param_calls_match_the_exact_literal_allowlist(self):
        source = self._generator_source()
        calls = _matlab_calls(source, "set_param")
        self.assertEqual(
            calls,
            [
                'set_param(averageTarget, "InitialCondition", '
                'num2str(newAverageK, "%.17g"))',
                'set_param(outletTarget, "InitialCondition", '
                'num2str(newOutletK, "%.17g"))',
                'set_param(model, "SimulationCommand", "update")',
            ],
        )

    def test_test_harness_has_no_marker_or_environment_cleanup_authority(self):
        source = MATLAB_GENERATOR_TEST.read_text(encoding="utf-8")
        for forbidden in (
            "FIG519A3_CLEAN_VERIFIED_HISTORICAL",
            "cleanupVerifiedOwnedSandboxes",
            "recoverOwnedTestSandbox",
            '"execute-verified-owned"',
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, source)

    def test_a3_candidate_generator_freezes_counts_flags_and_candidate_only_save(self):
        source = self._generator_source()
        for literal in (
            '"attempt_id", "20260901_A3"',
            '"delta_T_K", deltaTK',
            '"changed_state_count", 2',
            '"unchanged_state_count", 38',
            '"state_count", 40',
            '"solver_parameter_count", 37',
            '"update_diagram_count", 1',
            '"paper_reproduced", false',
            '"author_initial_state_identified", false',
            '"formal_promotion", false',
            "createPrivateStagingDirectory",
            "save_system(model, stagingCandidatePath)",
            "moveFileExclusive(stagingCandidatePath, candidatePath)",
            "assertSameIdentity(runIdentity",
            "assertSameIdentity(stagingIdentity",
            'activeFileGeneration = Simulink.fileGenControl("getConfig")',
            "openFileExclusive(auditPath)",
            "writeOpenChannel(auditChannel",
            '"patch_schema", "steady53_fig519_ihx_r2_hexe_shift_candidate_v1"',
            'string(get_param(blocks(index), "Mask"))',
            'string(get_param(blocks(index), "MaskType"))',
            '"mask_inventory", maskInventory',
            '"mask_fingerprint", sha256Text(strjoin(maskRecords, newline))',
            '"formal_identity_schema"',
            '"formal_files"',
            '"threat_model"',
            '"line_inventory"',
            '"file_key"',
            '"fig519a3_test_failure_point"',
            '"replace_hashed_candidate"',
            '"replace_staging_directory"',
            '"install_public_candidate"',
            '"install_symlink_directory"',
            "activateTestCapability",
            '"capability_file_key"',
            '"run_parent_file_key"',
            "PosixFilePermissions.asFileAttribute",
            "FileAlreadyExistsException",
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)
        self.assertNotRegex(source, r'save_system\([^\n]*(?:final_steady|final_dynamic)')
        self.assertNotRegex(source, r'set_param\([^\n]*(?:final_steady|final_dynamic)')
        self.assertNotIn('copyfile(sourcePath, candidatePath, "f")', source)
        self.assertNotIn('fopen(filePath, "w"', source)
        self.assertNotRegex(source, r"(?i)(?<![a-z0-9_])system\s*\(")
        self.assertNotIn("shasum", source.lower())
        save_at = source.index("save_system(model, stagingCandidatePath)")
        reopen_at = source.index("load_system(stagingCandidatePath)", save_at)
        update_at = source.index(
            'set_param(model, "SimulationCommand", "update")', reopen_at
        )
        audit_at = source.index("candidateStates = stateSnapshot(model)", update_at)
        self.assertLess(save_at, reopen_at)
        self.assertLess(reopen_at, update_at)
        self.assertLess(update_at, audit_at)
        tree = ast.parse(Path(contract.__file__).read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))
        self.assertNotRegex(source, r"(?m)^\s*assert\s*\(")

    def test_exact_literals(self):
        self.assertEqual(contract.ATTEMPT_ID, "20260901_A3")
        self.assertEqual(
            contract.ANCHOR_IDENTITY,
            "figure_5_18a_t0_visual_proxy_not_author_initial_state",
        )
        self.assertEqual(
            contract.SOURCE_MODEL_SHA256,
            "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        )
        self.assertEqual(
            contract.AVERAGE_PATH,
            "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
        )
        self.assertEqual(
            contract.OUTLET_PATH,
            "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
        )
        self.assertEqual(contract.OLD_AVERAGE_K, Decimal("1245.8184669844006"))
        self.assertEqual(contract.OLD_OUTLET_K, Decimal("1393.6037139151003"))
        self.assertEqual(contract.ANCHOR_K, Decimal("1200.0000000000000"))

    def test_candidate_is_one_delta_and_preserves_the_exact_gap(self):
        candidate = contract.candidate_contract()
        self.assertEqual(candidate["delta_K"], Decimal("-193.6037139151003"))
        self.assertEqual(candidate["new_average_K"], Decimal("1052.2147530693003"))
        self.assertEqual(candidate["new_outlet_K"], Decimal("1200.0000000000000"))
        self.assertEqual(candidate["old_gap_K"], Decimal("147.7852469306997"))
        self.assertEqual(candidate["new_gap_K"], Decimal("147.7852469306997"))
        self.assertEqual(
            candidate["new_average_K"], contract.OLD_AVERAGE_K + candidate["delta_K"]
        )
        self.assertEqual(
            candidate["new_outlet_K"], contract.OLD_OUTLET_K + candidate["delta_K"]
        )
        with self.assertRaises(TypeError):
            candidate["delta_K"] = Decimal("0")

    def test_candidate_is_independent_of_ambient_decimal_precision(self):
        for precision in (16, 8):
            with self.subTest(precision=precision), localcontext() as context:
                context.prec = precision
                candidate = contract.candidate_contract()
                self.assertEqual(candidate["delta_K"], Decimal("-193.6037139151003"))
                self.assertEqual(
                    candidate["new_average_K"], Decimal("1052.2147530693003")
                )
                self.assertEqual(
                    candidate["new_outlet_K"], Decimal("1200.0000000000000")
                )
                self.assertEqual(candidate["old_gap_K"], Decimal("147.7852469306997"))
                self.assertEqual(candidate["new_gap_K"], Decimal("147.7852469306997"))

    def test_directions_thresholds_and_promotion_flags_are_exact_and_immutable(self):
        self.assertEqual(
            dict(contract.PAPER_DIRECTIONS),
            {
                "reactor": ("fall",),
                "turbine": ("rise",),
                "compressor": ("fall", "rise"),
                "electrical_paper_eta": ("rise", "fall"),
            },
        )
        self.assertEqual(
            dict(contract.NONFLAT_THRESHOLDS_W),
            {
                "reactor": Decimal("0.5141158541664481"),
                "turbine": Decimal("1.609319536946714"),
                "compressor": Decimal("2.2659989586099982"),
                "electrical_paper_eta": Decimal("3.7926344096194953"),
            },
        )
        self.assertEqual(
            dict(contract.promotion_flags()),
            {
                "paper_reproduced": False,
                "author_initial_state_identified": False,
                "formal_promotion": False,
            },
        )
        for immutable in (
            contract.PAPER_DIRECTIONS,
            contract.NONFLAT_THRESHOLDS_W,
            contract.promotion_flags(),
        ):
            with self.assertRaises(TypeError):
                immutable["reactor"] = object()

    def test_classification_covers_every_mechanical_enum(self):
        matching_directions = dict(contract.PAPER_DIRECTIONS)
        all_nonflat = {name: True for name in contract.PAPER_DIRECTIONS}
        self.assertEqual(
            contract.classify(False, {}, {}),
            "numerical_or_physical_gate_failed",
        )
        self.assertEqual(
            contract.classify(True, matching_directions, all_nonflat),
            "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
        )
        mutated = dict(matching_directions)
        mutated["compressor"] = ("rise", "fall")
        self.assertEqual(
            contract.classify(True, mutated, all_nonflat),
            "ihx_r2_hexe_shift_alone_falsified",
        )

    def test_incomplete_extra_and_mutated_direction_or_nonflat_maps_are_falsified(self):
        directions = dict(contract.PAPER_DIRECTIONS)
        nonflat = {name: True for name in directions}
        cases = []
        incomplete_directions = dict(directions)
        incomplete_directions.pop("reactor")
        cases.append((incomplete_directions, nonflat))
        extra_directions = dict(directions, invented=("rise",))
        cases.append((extra_directions, nonflat))
        incomplete_nonflat = dict(nonflat)
        incomplete_nonflat.pop("turbine")
        cases.append((directions, incomplete_nonflat))
        false_nonflat = dict(nonflat)
        false_nonflat["electrical_paper_eta"] = False
        cases.append((directions, false_nonflat))
        non_boolean_nonflat = dict(nonflat)
        non_boolean_nonflat["reactor"] = 1
        cases.append((directions, non_boolean_nonflat))
        for candidate_directions, candidate_nonflat in cases:
            with self.subTest(
                directions=candidate_directions, nonflat=candidate_nonflat
            ):
                self.assertEqual(
                    contract.classify(True, candidate_directions, candidate_nonflat),
                    "ihx_r2_hexe_shift_alone_falsified",
                )

    def test_invalid_interface_types_raise_named_error_in_normal_and_optimized_modes(self):
        self.assertTrue(issubclass(contract.ContractError, Exception))
        with self.assertRaises(contract.ContractError):
            contract.classify(1, {}, {})
        with self.assertRaises(contract.ContractError):
            contract.classify(True, [], {})
        source = (
            "from tests import fig519_ihx_r2_hexe_contract as c\n"
            "try:\n"
            "    c.classify(1, {}, {})\n"
            "except c.ContractError:\n"
            "    print('CONTRACT_ERROR_PASS')\n"
            "else:\n"
            "    raise SystemExit('validation disappeared')\n"
        )
        for optimized in (False, True):
            command = [sys.executable]
            if optimized:
                command.append("-O")
            result = subprocess.run(
                command + ["-c", source],
                cwd=Path(__file__).resolve().parents[1],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "CONTRACT_ERROR_PASS\n")

    def test_production_module_contains_no_assert_statement(self):
        tree = ast.parse(Path(contract.__file__).read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))

    def test_matlab_cleanup_is_secure_handle_relative_and_never_path_recursive(self):
        source = MATLAB_GENERATOR_TEST.read_text(encoding="utf-8")
        for literal in (
            "SecureDirectoryStream-equivalent",
            'py.importlib.import_module("os")',
            "O_NOFOLLOW",
            'pyargs("dir_fd"',
            "os.stat",
            "os.unlink",
            "os.rmdir",
            '"retained_untrusted"',
            '"fig519a3_current_process_cleanup_snapshot_v1"',
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)
        self.assertNotRegex(source, r"(?i)\brmdir\s*\([^\n]*[\"']s[\"']")
        self.assertNotRegex(source, r"(?i)\btempname\s*\(")
        self.assertNotIn("claimOwnedTestSandbox", source)


class Figure519IhxR2HexeOfflineAnalysisTests(unittest.TestCase):
    """A3 Task 4 fixtures stay below a test-owned temporary directory."""

    maxDiff = None

    def setUp(self):
        tmp_root = ROOT / "tmp"
        tmp_root.mkdir(exist_ok=True)
        self._temporary = tempfile.TemporaryDirectory(
            prefix="fig519-a3-analysis-test-", dir=tmp_root
        )
        self.root = Path(self._temporary.name)

    def tearDown(self):
        self._temporary.cleanup()

    @staticmethod
    def _sha(path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    @staticmethod
    def _json_bytes(value: object) -> bytes:
        return (
            json.dumps(
                value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False
            )
            + "\n"
        ).encode()

    def _paper(self):
        grouped = {panel: [] for panel in "abcd"}
        with (ROOT / "data/provenance/steady53/fig5_19/paper_points.csv").open(
            newline=""
        ) as handle:
            for row in csv.DictReader(handle):
                grouped[row["panel_id"]].append(
                    (float(row["time_s"]), float(row["power_kW"]))
                )
        return grouped

    def _write_curves(self, run_dir: Path, *, reactor_scale: float = 1.0):
        paper = self._paper()
        times = [0.0] + [item[0] for item in paper["a"]] + [500.0]
        panel_values = {}
        for panel in "abc":
            values = [item[1] * 1000.0 for item in paper[panel]]
            panel_values[panel] = [values[0]] + values + [values[-1]]
        panel_values["a"] = [value * reactor_scale for value in panel_values["a"]]
        candidate = run_dir / "run/candidate_curves.csv"
        with candidate.open("w", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(
                [
                    "time_s",
                    "reactor_W",
                    "turbine_W",
                    "compressor_W",
                    "ihx_r2_average_K",
                    "ihx_r2_outlet_K",
                ]
            )
            for index, sample_time in enumerate(times):
                writer.writerow(
                    [
                        f"{sample_time:.17g}",
                        f"{panel_values['a'][index]:.17g}",
                        f"{panel_values['b'][index]:.17g}",
                        f"{panel_values['c'][index]:.17g}",
                        "1052.2147530693003",
                        "1200.0000000000000",
                    ]
                )

        baseline = ROOT / "data/provenance/steady53/fig5_19/model_baseline"
        series = []
        for name in ("baseline_P_sw.csv", "baseline_WT_sw.csv", "baseline_Wc_sw.csv"):
            with (baseline / name).open(newline="") as handle:
                series.append([[float(value) for value in row] for row in csv.reader(handle)])
        reference = run_dir / "run/reference_curves.csv"
        with reference.open("w", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["time_s", "reactor_W", "turbine_W", "compressor_W"])
            for reactor, turbine, compressor in zip(*series):
                self.assertEqual(reactor[0], turbine[0])
                self.assertEqual(reactor[0], compressor[0])
                writer.writerow(
                    [
                        f"{reactor[0]:.17g}",
                        f"{reactor[1]:.17g}",
                        f"{turbine[1]:.17g}",
                        f"{compressor[1]:.17g}",
                    ]
                )
        return candidate, reference

    def _patch_audit(self, run_dir: Path, candidate: Path):
        initialization = json.loads(
            (ROOT / "data/provenance/steady53/fig5_19/initialization_audit.json").read_text()
        )
        targets = {
            contract.AVERAGE_PATH: "1052.2147530693003",
            contract.OUTLET_PATH: "1200.0000000000000",
        }
        states = []
        for row in initialization["state_inventory"]:
            source_path = row["path"]
            source_expression = row["initial_condition_expression"]
            candidate_expression = targets.get(source_path, source_expression)
            states.append(
                {
                    "source_path": source_path,
                    "candidate_path": source_path.replace(
                        "final_steady_24a/", "candidate/", 1
                    ),
                    "source_expression": source_expression,
                    "candidate_expression": candidate_expression,
                    "unchanged": source_expression == candidate_expression,
                }
            )
        changed = [
            {
                "path": contract.AVERAGE_PATH,
                "candidate_path": contract.AVERAGE_PATH.replace(
                    "final_steady_24a/", "candidate/", 1
                ),
                "old_initial_condition_K": 1245.8184669844006,
                "new_initial_condition_K": 1052.2147530693003,
                "delta_T_K": -193.6037139151003,
            },
            {
                "path": contract.OUTLET_PATH,
                "candidate_path": contract.OUTLET_PATH.replace(
                    "final_steady_24a/", "candidate/", 1
                ),
                "old_initial_condition_K": 1393.6037139151003,
                "new_initial_condition_K": 1200.0,
                "delta_T_K": -193.6037139151003,
            },
        ]
        source = ROOT / "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
        runtime = []
        runtime_root = ROOT / "data/provenance/baselines/f8bcd83/runtime"
        for name, digest in analysis.RUNTIME_HASHES.items():
            path = runtime_root / name
            runtime.append({
                "name": name,
                "repository_relative_path": path.relative_to(ROOT).as_posix(),
                "absolute_path": str(path),
                "before_sha256": digest, "after_sha256": digest,
                "unchanged": True,
            })
        protected = []
        with (ROOT / "data/provenance/baselines/f8bcd83/"
              "protected_manifest_recovery.csv").open(newline="") as handle:
            for row in csv.DictReader(handle):
                path = Path(row["resolved_path"])
                try:
                    relative = path.relative_to(ROOT).as_posix()
                except ValueError:
                    relative = ""
                protected.append({
                    "name": row["original_path"],
                    "repository_relative_path": relative,
                    "absolute_path": str(path),
                    "before_sha256": row["resolved_sha256"],
                    "after_sha256": row["resolved_sha256"],
                    "unchanged": True,
                })
        formal = []
        for name in analysis.FORMAL_NAMES:
            path = ROOT / name
            exists = path.is_file() and not path.is_symlink()
            digest = self._sha(path) if exists else ""
            key = f"fixture:{name}" if exists else ""
            formal.append({
                "repository_relative_path": name,
                "exists_before": exists, "exists_after": exists,
                "absolute_path": str(path),
                "before_file_key": key, "after_file_key": key,
                "before_sha256": digest, "after_sha256": digest,
                "unchanged": True,
            })
        return {
            "patch_schema": "steady53_fig519_ihx_r2_hexe_shift_candidate_v1",
            "attempt_id": "20260901_A3",
            "candidate_value_identity": contract.ANCHOR_IDENTITY,
            "source_repository_relative_path": source.relative_to(ROOT).as_posix(),
            "source_absolute_path": str(source),
            "source_model_sha256": contract.SOURCE_MODEL_SHA256,
            "source_sha256": contract.SOURCE_MODEL_SHA256,
            "source_sha256_after": contract.SOURCE_MODEL_SHA256,
            "source_hash_unchanged": True,
            "candidate_repository_relative_path": candidate.relative_to(ROOT).as_posix(),
            "candidate_absolute_path": str(candidate),
            "candidate_sha256": self._sha(candidate),
            "anchor_K": 1200.0,
            "delta_T_K": -193.6037139151003,
            "old_gap_K": 147.7852469306997,
            "new_gap_K": 147.7852469306997,
            "changed_states": changed,
            "changed_state_count": 2,
            "unchanged_state_count": 38,
            "state_count": 40,
            "state_initial_conditions": states,
            "solver_parameter_count": 37,
            "solver_contract": {
                "unchanged": True,
                "parameter_count": 37,
                "parameters": [
                    {"name": f"solver_{index:02d}", "value": "fixed"}
                    for index in range(37)
                ],
            },
            "semantic_snapshot": {
                "unchanged": True,
                "source": {"block_fingerprint": "a" * 64, "edge_fingerprint": "b" * 64},
                "candidate": {"block_fingerprint": "a" * 64, "edge_fingerprint": "b" * 64},
            },
            "model_workspace": {"unchanged": True, "source": [], "candidate": []},
            "runtime_dependencies": runtime,
            "protected_files": protected,
            "formal_files": formal,
            "protected_manifest_sha256": (
                "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"
            ),
            "update_diagram_count": 1,
            "paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False,
        }

    def _artifact(self, identity: str, path: Path):
        return {
            "identity": identity,
            "repository_relative_path": path.relative_to(ROOT).as_posix(),
            "absolute_path": str(path),
            "sha256": self._sha(path),
            "bytes": path.stat().st_size,
            "storage": "external_tmp_not_copied",
        }

    def _make_run(self, *, success: bool = True, reactor_scale: float = 1.0):
        stem = "success" if success else "failure"
        run_dir = self.root / f"{stem}-{len(list(self.root.glob(stem + '-*')))}"
        (run_dir / "run").mkdir(parents=True)
        candidate = run_dir / "candidate.slx"
        candidate.write_bytes(b"synthetic A3 candidate bytes\n")
        audit = self._patch_audit(run_dir, candidate)
        audit_path = run_dir / "patch_audit.json"
        audit_path.write_bytes(self._json_bytes(audit))
        raw = run_dir / "run/raw_result.mat"
        raw.write_bytes(b"synthetic raw bytes\x00\x01")
        candidate_csv, reference_csv = self._write_curves(
            run_dir, reactor_scale=reactor_scale
        )
        if not success:
            candidate_csv.unlink()
        def snapshot(records):
            return [{
                "repository_relative_path": item["repository_relative_path"],
                "sha256": item["before_sha256"],
            } for item in records]
        formal_snapshot = [{
            "repository_relative_path": item["repository_relative_path"],
            "exists": item["exists_before"],
            "sha256": item["before_sha256"],
        } for item in audit["formal_files"]]
        protected_snapshot = []
        for item in audit["protected_files"]:
            path = Path(item["absolute_path"])
            stat_result = path.stat()
            protected_snapshot.append({
                "name": item["name"], "resolved_path": str(path.resolve()),
                "sha256": item["before_sha256"],
                "file_key": f"fixture:{stat_result.st_dev}:{stat_result.st_ino}",
                "device": str(stat_result.st_dev), "inode": str(stat_result.st_ino),
            })
        reference_snapshot = [
            {"name": name, "sha256": digest}
            for name, digest in analysis.BASELINE_HASHES.items()
        ]
        identity = {
            "source_sha256": contract.SOURCE_MODEL_SHA256,
            "candidate_sha256": self._sha(candidate),
            "runtime_dependencies": snapshot(audit["runtime_dependencies"]),
            "protected_files": protected_snapshot,
            "formal_files": formal_snapshot,
            "reference_curves": reference_snapshot,
        }
        status = {
            "run_schema": "steady53_fig519_ihx_r2_hexe_shift_run_v1",
            "attempt_id": "20260901_A3",
            "candidate_value_identity": contract.ANCHOR_IDENTITY,
            "experiment_status": "completed_success" if success else "completed_model_failure",
            "started_at_utc": "2026-09-01T00:00:00.000Z",
            "completed_at_utc": "2026-09-01T00:01:00.000Z",
            "run_steady53_case_call_count": 1,
            "run_steady53_case_returned": True,
            "retry_count": 0,
            "rerun_forbidden": True,
            "candidate_success": success,
            "candidate_final_time_s": 500.0 if success else None,
            "candidate_error_id": "" if success else "synthetic:modelFailure",
            "candidate_error_report": "",
            "runner_exception_id": "",
            "runner_exception_report": "",
            "identity_unchanged": True,
            "identity_before": identity,
            "identity_after": copy.deepcopy(identity),
            "artifacts": [
                self._artifact("candidate_slx", candidate),
                self._artifact("patch_audit", audit_path),
                self._artifact("raw_result", raw),
                self._artifact("reference_curves", reference_csv),
            ] + ([self._artifact("candidate_curves", candidate_csv)] if success else []),
            "paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False,
        }
        (run_dir / "run/run_status.json").write_bytes(self._json_bytes(status))
        return run_dir

    def _make_capture(self, run_dir: Path | None = None, *, archive: bool = True,
                      exit_code: int | None = None,
                      error_id: str = "", error_report: str = ""):
        capture = self.root / "capture"
        snapshot = capture / "repo_snapshot"
        immutable = {}
        for name in analysis.CAPTURE_EXECUTABLES:
            path = snapshot / name
            path.parent.mkdir(parents=True, exist_ok=True)
            payload = (
                Path(analysis.__file__).read_bytes()
                if name == "tests/analyze_fig519_ihx_r2_hexe_shift.py"
                else ("captured executable: " + name + "\n").encode()
            )
            path.write_bytes(payload)
            immutable[name] = path
        data_groups = (
            "data/provenance/baselines/f8bcd83/final_steady_24a.slx",
            "data/provenance/baselines/f8bcd83/runtime",
            "data/provenance/steady53/fig5_18a",
            "data/provenance/steady53/fig5_19/paper_points.csv",
            "data/provenance/steady53/fig5_19/model_baseline",
            "data/provenance/steady53/fig5_19/signal_contract.json",
            "data/provenance/steady53/fig5_19/initialization_audit.json",
            "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json",
            "data/provenance/steady53/fig5_19/manifest.csv",
        )
        for group in data_groups:
            source = ROOT / group
            sources = [source] if source.is_file() else sorted(source.rglob("*"))
            for item in sources:
                if not item.is_file() or item.is_symlink():
                    continue
                relative = item.relative_to(ROOT).as_posix()
                target = snapshot / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(item.read_bytes())
                immutable[relative] = target
        exact_command = (
            "python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/"
            "repo_snapshot/tests/execute_fig519_ihx_r2_hexe_a3_once.py --execute\n"
        ).encode()
        if exit_code is None:
            exit_code = 0 if run_dir is not None else 99
        execution = {
            "execution_schema": "steady53_fig519_ihx_r2_hexe_a3_execution_v1",
            "attempt_id": "20260901_A3",
            "formal_command": exact_command.decode().rstrip("\n"),
            "formal_command_sha256": hashlib.sha256(exact_command).hexdigest(),
            "formal_command_invocation_count": 1,
            "matlab_subprocess_start_count": 1 if run_dir is not None else 0,
            "run_steady53_case_call_count": 1 if run_dir is not None else 0,
            "retry_count": 0,
            "formal_process_exit_code": exit_code,
            "failure_stage": None if exit_code == 0 else "self_hash_or_subprocess_start",
            "error_id": error_id or ("synthetic:preSimulationFailure" if exit_code else ""),
            "error_report": error_report or ("synthetic pre-simulation failure" if exit_code else ""),
            "paper_reproduced": False,
            "author_initial_state_identified": False,
            "formal_promotion": False,
        }
        for name, payload in {
            "tracked_diff.patch": b"synthetic tracked diff\n",
            "git_head.txt": ("d351579414ed94a6afa3acdc917c9cd70469182f\n").encode(),
            "git_status_porcelain_v1_z.bin": b"",
            "untracked_paths.json": self._json_bytes([]),
            "preflight_status.json": self._json_bytes({
                "attempt_id": "20260901_A3",
                "formal_command_sha256": hashlib.sha256(exact_command).hexdigest(),
                "formal_command_invocation_count": 0,
                "run_steady53_case_call_count": 0,
                "simulation_call_count": 0,
            }),
            "command.txt": exact_command,
            "stdout.log": b"BEGIN_A3_500\n",
            "stderr.log": ((str(execution["error_report"]) + "\n").encode()
                           if execution["error_report"] else b""),
            "formal_exit_code.txt": f"{exit_code}\n".encode(),
            "formal_invocation.claim": b"20260901_A3\n",
            "execution_record.json": self._json_bytes(execution),
        }.items():
            (capture / name).write_bytes(payload)
        sums = "".join(
            f"{self._sha(path)}  {name}\n" for name, path in sorted(immutable.items())
        ).encode()
        (snapshot / "SHA256SUMS").write_bytes(sums)
        for path in immutable.values():
            path.chmod(0o400)
        if archive:
            artifacts = []
            for name in (
                "formal_invocation.claim", "command.txt", "stdout.log", "stderr.log",
                "formal_exit_code.txt", "execution_record.json",
            ):
                path = capture / name
                artifacts.append({
                    "identity": name,
                    "location": "capture/" + name,
                    "sha256": self._sha(path),
                    "bytes": path.stat().st_size,
                })
            run_sources = {
                "patch_audit": "patch_audit.json",
                "run_status": "run/run_status.json",
                "raw_result": "run/raw_result.mat",
                "candidate_curves": "run/candidate_curves.csv",
                "reference_curves": "run/reference_curves.csv",
            }
            missing = []
            for identity, relative in run_sources.items():
                path = (run_dir / relative) if run_dir is not None else None
                if path is not None and path.is_file():
                    artifacts.append({
                        "identity": identity,
                        "location": "run/" + relative,
                        "sha256": self._sha(path),
                        "bytes": path.stat().st_size,
                    })
                else:
                    missing.append(identity)
            manifest = {
                "manifest_schema": "steady53_fig519_ihx_r2_hexe_a3_consumed_execution_v1",
                "attempt_id": "20260901_A3",
                "invocation_claimed": True,
                "formal_command": exact_command.decode().rstrip("\n"),
                "formal_process_exit_code": exit_code,
                "artifacts": sorted(artifacts, key=lambda item: item["identity"]),
                "missing_run_artifacts": sorted(missing),
            }
            (capture / "consumed_execution_manifest.json").write_bytes(
                self._json_bytes(manifest)
            )
        return capture

    def test_a2_scientific_inputs_are_byte_identical_and_direction_behavior_is_frozen(self):
        self.assertEqual(
            self._sha(ROOT / "data/provenance/steady53/fig5_19/paper_points.csv"),
            analysis.PAPER_POINTS_SHA256,
        )
        self.assertEqual(
            self._sha(ROOT / "data/provenance/steady53/fig5_19/signal_contract.json"),
            analysis.SIGNAL_CONTRACT_SHA256,
        )
        self.assertEqual(analysis.PAPER_ETA, 0.98)
        self.assertEqual(analysis.DIRECTION_RULE, analysis.A2_DIRECTION_RULE)
        self.assertEqual(analysis.NONFLAT_THRESHOLDS_W, contract.NONFLAT_THRESHOLDS_W)
        points = [(0.0, 0.0, 2.0), (1.0, 1.0, 2.0), (2.0, 4.0, 2.0),
                  (3.0, 8.0, 2.0), (4.0, 7.0, 2.0), (5.0, 3.0, 2.0)]
        self.assertEqual(analysis.direction_sequence(points), ["rise", "fall"])

    def test_public_validators_raise_named_non_assertion_errors(self):
        run_dir = self._make_run()
        candidate = run_dir / "candidate.slx"
        audit = json.loads((run_dir / "patch_audit.json").read_text())
        status = json.loads((run_dir / "run/run_status.json").read_text())
        self.assertIs(analysis.validate_patch_audit(audit, candidate), audit)
        self.assertIs(analysis.validate_run_status(status, run_dir), status)
        curves = analysis.read_candidate_curves(run_dir / "run/candidate_curves.csv")
        self.assertEqual(set(curves), {
            "time_s", "reactor_W", "turbine_W", "compressor_W",
            "ihx_r2_average_K", "ihx_r2_outlet_K",
        })
        cases = (
            (analysis.validate_patch_audit, ([], candidate), analysis.PatchAuditError),
            (analysis.validate_run_status, ([], run_dir), analysis.RunStatusError),
            (analysis.read_candidate_curves, (self.root / "missing.csv",), analysis.CurveDataError),
            (analysis.direction_sequence, ([(0.0, float("nan"), 1.0)],), analysis.DirectionError),
        )
        for function, arguments, error_type in cases:
            with self.subTest(function=function.__name__):
                self.assertTrue(issubclass(error_type, Exception))
                self.assertFalse(issubclass(error_type, AssertionError))
                with self.assertRaises(error_type):
                    function(*arguments)

    def test_three_enums_and_false_promotions(self):
        success = self._make_run()
        result = analysis.analyze(success)
        self.assertEqual(
            result["conclusion"],
            "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
        )
        self.assertEqual(result["promotion"], dict(contract.promotion_flags()))
        self.assertEqual(
            result["directions"],
            {name: list(value) for name, value in contract.PAPER_DIRECTIONS.items()},
        )
        falsified = self._make_run(reactor_scale=-1.0)
        self.assertEqual(
            analysis.analyze(falsified)["conclusion"],
            "ihx_r2_hexe_shift_alone_falsified",
        )
        failed = self._make_run(success=False)
        self.assertEqual(
            analysis.analyze(failed)["conclusion"],
            "numerical_or_physical_gate_failed",
        )

    def test_fourth_panel_is_only_paper_eta_and_exact_captured_signal_identity(self):
        run_dir = self._make_run()
        result = analysis.analyze(run_dir)
        curves = analysis.read_candidate_curves(run_dir / "run/candidate_curves.csv")
        expected = [
            0.98 * (turbine - compressor)
            for turbine, compressor in zip(curves["turbine_W"], curves["compressor_W"])
        ]
        self.assertEqual(result["derived_electrical_paper_eta_W"], expected)

        contract_path = ROOT / "data/provenance/steady53/fig5_19/signal_contract.json"
        original = json.loads(contract_path.read_text())
        attacks = []
        historical = copy.deepcopy(original)
        historical["signals"]["electrical_paper_eta"]["formula"] = "0.96527*(WT_sw-Wc_sw)"
        attacks.append(historical)
        alias = copy.deepcopy(original)
        alias["signals"]["electrical_paper_eta"]["direct_generator_signal"] = "generator_W"
        attacks.append(alias)
        reversal = copy.deepcopy(original)
        reversal["signals"]["electrical_paper_eta"]["formula"] = "0.98*(Wc_sw-WT_sw)"
        attacks.append(reversal)
        wrong_signal = copy.deepcopy(original)
        wrong_signal["signals"]["turbine"]["model_signal"] = "not_WT_sw"
        attacks.append(wrong_signal)
        for index, payload in enumerate(attacks):
            path = self.root / f"signal-contract-attack-{index}.json"
            path.write_bytes(self._json_bytes(payload))
            with self.subTest(index=index), mock.patch.object(
                analysis, "SIGNAL_CONTRACT_PATH", path
            ), mock.patch.object(
                analysis, "SIGNAL_CONTRACT_SHA256", self._sha(path)
            ):
                with self.assertRaises(analysis.SignalContractError):
                    analysis.analyze(run_dir)

        attacked_csv = run_dir / "run/direct-generator.csv"
        attacked_csv.write_text(
            "time_s,reactor_W,turbine_W,compressor_W,ihx_r2_average_K,"
            "ihx_r2_outlet_K,generator_W\n0,1,2,1,1052,1200,1\n1,1,2,1,1052,1200,1\n"
        )
        with self.assertRaises(analysis.CurveDataError):
            analysis.read_candidate_curves(attacked_csv)

    def test_publication_recovers_every_stage_and_is_idempotent(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        durable = self.root / "durable" / "ihx_r2_hexe_shift_A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        reactor_history = ROOT / "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json"
        old_reactor_bytes = reactor_history.read_bytes()

        for point in analysis.publication_crash_points(run_dir, capture, durable, history):
            with self.subTest(point=point):
                if durable.exists():
                    shutil.rmtree(durable)
                if history.exists():
                    history.unlink()
                txn = analysis.transaction_dir(durable)
                if txn.exists():
                    shutil.rmtree(txn)

                def fail(selected):
                    if selected == point:
                        raise analysis.InjectedPublicationCrash(point)

                with mock.patch.object(analysis, "_publication_boundary", fail):
                    with self.assertRaises(analysis.InjectedPublicationCrash):
                        analysis.publish(run_dir, capture, durable, history)
                analysis.publish(run_dir, capture, durable, history)
                before = {
                    path.relative_to(durable.parent).as_posix(): (
                        path.read_bytes(), path.stat().st_mtime_ns
                    )
                    for path in durable.parent.rglob("*")
                    if path.is_file()
                }
                analysis.publish(run_dir, capture, durable, history)
                analysis.verify_only(durable, history)
                after = {
                    path.relative_to(durable.parent).as_posix(): (
                        path.read_bytes(), path.stat().st_mtime_ns
                    )
                    for path in durable.parent.rglob("*")
                    if path.is_file()
                }
                self.assertEqual(before, after)
                self.assertEqual(reactor_history.read_bytes(), old_reactor_bytes)

    def test_publication_binds_raw_csv_capture_and_rejects_symlink_or_tamper(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        durable = self.root / "published" / "ihx_r2_hexe_shift_A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        analysis.verify_only(durable, history)
        summary = json.loads((durable / "a3_summary.json").read_text())
        for name in (
            "raw_result.mat", "candidate_curves.csv", "reference_curves.csv",
            "run_status.json", "stdout.log", "stderr.log",
        ):
            self.assertEqual(summary["artifacts"][name]["sha256"], self._sha(durable / name))

        before_mtimes = {
            path: path.stat().st_mtime_ns
            for path in [history, *[item for item in durable.rglob("*") if item.is_file()]]
        }
        time.sleep(0.002)
        analysis.verify_only(durable, history)
        self.assertEqual(
            before_mtimes, {path: path.stat().st_mtime_ns for path in before_mtimes}
        )

        original_summary = (durable / "a3_summary.json").read_bytes()
        original_manifest = (durable / "manifest.csv").read_bytes()
        tampered = json.loads(original_summary)
        tampered["paper_reproduced"] = True
        (durable / "a3_summary.json").write_bytes(self._json_bytes(tampered))
        rows = list(csv.DictReader(original_manifest.decode().splitlines()))
        for row in rows:
            if row["path"] == "a3_summary.json":
                row["sha256"] = self._sha(durable / "a3_summary.json")
                row["bytes"] = str((durable / "a3_summary.json").stat().st_size)
        stream = ["path,sha256,bytes,role\n"]
        stream.extend(
            f'{row["path"]},{row["sha256"]},{row["bytes"]},{row["role"]}\n'
            for row in rows
        )
        (durable / "manifest.csv").write_text("".join(stream))
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, history)
        (durable / "a3_summary.json").write_bytes(original_summary)
        (durable / "manifest.csv").write_bytes(original_manifest)

        victim = durable / "stdout.log"
        victim.unlink()
        victim.symlink_to(capture / "stdout.log")
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, history)

    def test_failed_run_publication_records_missing_curve_without_placeholder(self):
        run_dir = self._make_run(success=False)
        capture = self._make_capture(run_dir)
        durable = self.root / "failed-publication" / "ihx_r2_hexe_shift_A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        analysis.verify_only(durable, history)
        self.assertFalse((durable / "candidate_curves.csv").exists())
        summary = json.loads((durable / "a3_summary.json").read_text())
        self.assertEqual(
            summary["analysis"]["conclusion"],
            "numerical_or_physical_gate_failed",
        )
        self.assertEqual(
            summary["missing_artifacts"]["candidate_curves.csv"],
            "not_generated_by_consumed_attempt",
        )

    def test_publication_rejects_unarchived_execution_without_consumed_manifest(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir, archive=False)
        durable = self.root / "unconsumed" / "ihx_r2_hexe_shift_A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        self.assertFalse((capture / "consumed_execution_manifest.json").exists())
        with self.assertRaises(analysis.PublicationError):
            analysis.publish(run_dir, capture, durable, history)

    def test_consumed_pre_simulation_failure_publishes_without_fake_run_artifacts(self):
        capture = self._make_capture(None, exit_code=99)
        run_dir = self.root / "absent-consumed-run"
        durable = self.root / "pre-sim" / "ihx_r2_hexe_shift_A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        analysis.verify_only(durable, history)
        summary = json.loads((durable / "a3_summary.json").read_text())
        self.assertEqual(summary["analysis"]["conclusion"], "numerical_or_physical_gate_failed")
        self.assertEqual(summary["analysis"]["gate_failure_class"], "pre_simulation_infrastructure")
        for forbidden in ("candidate.slx", "patch_audit.json", "run_status.json", "raw_result.mat",
                          "candidate_curves.csv", "reference_curves.csv"):
            self.assertFalse((durable / forbidden).exists())

    def test_execution_manifest_binds_every_claim_and_nonzero_exit_never_promotes(self):
        for name in ("formal_invocation.claim", "command.txt", "stdout.log",
                     "stderr.log", "execution_record.json",
                     "consumed_execution_manifest.json"):
            with self.subTest(name=name):
                run_dir = self._make_run()
                capture = self._make_capture(run_dir)
                path = capture / name
                path.write_bytes(path.read_bytes() + b"tamper")
                durable = self.root / ("tamper-" + name.replace(".", "-")) / "A3"
                durable.parent.mkdir()
                with self.assertRaises(analysis.PublicationError):
                    analysis.publish(
                        run_dir, capture, durable,
                        durable.parent / "initial_state_counterfactual_history.json",
                    )
                shutil.rmtree(capture)
        run_dir = self._make_run()
        capture = self._make_capture(
            run_dir, exit_code=99, error_id="synthetic:exit99",
            error_report="formal process failed after the run",
        )
        durable = self.root / "exit99" / "A3"
        durable.parent.mkdir()
        analysis.publish(
            run_dir, capture, durable,
            durable.parent / "initial_state_counterfactual_history.json",
        )
        result = json.loads((durable / "analysis.json").read_text())
        self.assertFalse(result["numerical_gate_passed"])
        self.assertEqual(result["conclusion"], "numerical_or_physical_gate_failed")

    def test_failure_subclasses_are_mechanical_and_exact(self):
        cases = (
            ("completed_model_failure", "Simulink:Engine:CompileError",
             "compile failed while updating diagram", "compile"),
            ("completed_model_failure", "HeXe:PropertyDomain",
             "Virial property assertion", "property_domain"),
            ("completed_model_failure", "Simulink:RuntimeError",
             "integration stopped", "model_runtime"),
            ("completed_incomplete_output", "", "", "incomplete_output"),
        )
        for experiment, error_id, report, expected in cases:
            with self.subTest(expected=expected):
                run_dir = self._make_run(success=False)
                path = run_dir / "run/run_status.json"
                status = json.loads(path.read_text())
                status["experiment_status"] = experiment
                status["candidate_error_id"] = error_id
                status["candidate_error_report"] = report
                path.write_bytes(self._json_bytes(status))
                self.assertEqual(analysis.analyze(run_dir)["gate_failure_class"], expected)

    def test_exact_audit_and_run_identity_sets_reject_missing_extra_or_duplicate(self):
        mutations = (
            ("runtime_dependencies", "pop"),
            ("runtime_dependencies", "duplicate"),
            ("protected_files", "pop"),
            ("formal_files", "extra"),
        )
        for field, operation in mutations:
            with self.subTest(field=field, operation=operation):
                run_dir = self._make_run()
                candidate = run_dir / "candidate.slx"
                audit = json.loads((run_dir / "patch_audit.json").read_text())
                if operation == "pop":
                    audit[field].pop()
                elif operation == "duplicate":
                    audit[field][-1] = copy.deepcopy(audit[field][0])
                else:
                    audit[field].append(copy.deepcopy(audit[field][0]))
                with self.assertRaises(analysis.PatchAuditError):
                    analysis.validate_patch_audit(audit, candidate)
        run_dir = self._make_run()
        path = run_dir / "run/run_status.json"
        status = json.loads(path.read_text())
        status["identity_after"]["reference_curves"][0]["sha256"] = "0" * 64
        with self.assertRaises(analysis.RunStatusError):
            analysis.validate_run_status(status, run_dir)

    def test_durable_capture_is_complete_and_verify_requires_canonical_history_sibling(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        durable = self.root / "complete-capture" / "A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        for name in analysis.CAPTURE_ROOT_FILES:
            self.assertTrue((durable / name).is_file(), name)
        for name in analysis.CAPTURE_EXECUTABLES:
            self.assertTrue((durable / "captured" / name).is_file(), name)
        alternate = durable.parent / "alternate_history.json"
        alternate.write_bytes(history.read_bytes())
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, alternate)

    def test_coordinated_analysis_summary_history_and_manifest_tamper_is_rederived(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        durable = self.root / "coordinated" / "A3"
        durable.parent.mkdir()
        history_path = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history_path)
        summary = json.loads((durable / "a3_summary.json").read_text())
        summary["analysis"]["curves"]["reactor"]["paper_comparison"]["rmse_kW"] += 1.0
        analysis_payload = self._json_bytes(summary["analysis"])
        (durable / "analysis.json").write_bytes(analysis_payload)
        summary["artifacts"]["analysis.json"] = {
            "sha256": hashlib.sha256(analysis_payload).hexdigest(),
            "bytes": len(analysis_payload),
            "role": "captured_or_run_evidence",
        }
        summary_payload = self._json_bytes(summary)
        (durable / "a3_summary.json").write_bytes(summary_payload)
        history = json.loads(history_path.read_text())
        history["attempts"][0]["summary"] = summary
        history_payload = self._json_bytes(history)
        history_path.write_bytes(history_payload)
        files = {
            path.relative_to(durable).as_posix(): path.read_bytes()
            for path in durable.rglob("*")
            if path.is_file() and path.name != analysis.MANIFEST_NAME
        }
        (durable / analysis.MANIFEST_NAME).write_bytes(
            analysis._manifest_bytes(files, history_payload)
        )
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, history_path)

    def test_full_task5_snapshot_shape_is_accepted_and_every_declared_byte_archived(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        declared = {}
        for line in (capture / "repo_snapshot/SHA256SUMS").read_text().splitlines():
            digest, relative = line.split("  ", 1)
            declared[relative] = digest
        self.assertGreater(len(declared), len(analysis.CAPTURE_EXECUTABLES))
        durable = self.root / "full-snapshot" / "A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        for relative, digest in declared.items():
            archived = durable / "captured" / relative
            self.assertTrue(archived.is_file(), relative)
            self.assertEqual(self._sha(archived), digest)
        analysis.verify_only(durable, history)

    def test_task5_snapshot_missing_extra_writable_or_tampered_entries_are_rejected(self):
        for attack in ("missing", "extra", "writable", "tampered"):
            with self.subTest(attack=attack):
                run_dir = self._make_run()
                capture = self._make_capture(run_dir)
                snapshot = capture / "repo_snapshot"
                sums_path = snapshot / "SHA256SUMS"
                lines = sums_path.read_text().splitlines()
                victim_relative = next(
                    line.split("  ", 1)[1] for line in lines
                    if line.split("  ", 1)[1].startswith("data/")
                )
                victim = snapshot / victim_relative
                if attack == "missing":
                    sums_path.write_text("\n".join(
                        line for line in lines if not line.endswith("  " + victim_relative)
                    ) + "\n")
                elif attack == "extra":
                    extra = snapshot / "data/not-approved.bin"
                    extra.parent.mkdir(parents=True, exist_ok=True)
                    extra.write_bytes(b"extra immutable\n")
                    extra.chmod(0o400)
                    sums_path.write_text(
                        sums_path.read_text() + f"{self._sha(extra)}  data/not-approved.bin\n"
                    )
                else:
                    victim.chmod(0o600)
                    if attack == "tampered":
                        victim.write_bytes(victim.read_bytes() + b"tamper")
                        victim.chmod(0o400)
                durable = self.root / ("snapshot-" + attack) / "A3"
                durable.parent.mkdir()
                with self.assertRaises(analysis.PublicationError):
                    analysis.publish(
                        run_dir, capture, durable,
                        durable.parent / "initial_state_counterfactual_history.json",
                    )
                for path in snapshot.rglob("*"):
                    if path.is_file():
                        path.chmod(0o600)
                shutil.rmtree(capture)

    def test_failure_class_cannot_be_coordinated_from_model_runtime_to_property_domain(self):
        run_dir = self._make_run(success=False)
        capture = self._make_capture(run_dir)
        durable = self.root / "failure-class-tamper" / "A3"
        durable.parent.mkdir()
        history_path = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history_path)
        status = json.loads((durable / "run_status.json").read_text())
        status["candidate_error_id"] = "HeXe:PropertyDomain"
        status["candidate_error_report"] = "coordinated property-domain claim"
        status_payload = self._json_bytes(status)
        (durable / "run_status.json").write_bytes(status_payload)
        summary = json.loads((durable / "a3_summary.json").read_text())
        summary["analysis"]["gate_failure_class"] = "property_domain"
        analysis_payload = self._json_bytes(summary["analysis"])
        (durable / "analysis.json").write_bytes(analysis_payload)
        for name, payload in (("run_status.json", status_payload),
                              ("analysis.json", analysis_payload)):
            summary["artifacts"][name] = {
                "sha256": hashlib.sha256(payload).hexdigest(), "bytes": len(payload),
                "role": "captured_or_run_evidence",
            }
        (durable / "a3_summary.json").write_bytes(self._json_bytes(summary))
        history = json.loads(history_path.read_text())
        history["attempts"][0]["summary"] = summary
        history_payload = self._json_bytes(history)
        history_path.write_bytes(history_payload)
        files = {
            path.relative_to(durable).as_posix(): path.read_bytes()
            for path in durable.rglob("*")
            if path.is_file() and path.name != analysis.MANIFEST_NAME
        }
        (durable / analysis.MANIFEST_NAME).write_bytes(
            analysis._manifest_bytes(files, history_payload)
        )
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, history_path)

    def test_synchronized_consumed_manifest_tamper_is_still_outer_bound(self):
        run_dir = self._make_run()
        capture = self._make_capture(run_dir)
        durable = self.root / "consumed-sync-tamper" / "A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        analysis.publish(run_dir, capture, durable, history)
        (durable / "stdout.log").write_bytes(b"coordinated new stdout\n")
        (durable / "consumed_execution_manifest.json").write_bytes(
            self._json_bytes(analysis._rebuild_consumed_manifest(durable))
        )
        with self.assertRaises(analysis.VerificationError):
            analysis.verify_only(durable, history)

    def test_cli_prints_only_durable_conclusion_after_publish_and_verify(self):
        durable = self.root / "cli" / "A3"
        durable.parent.mkdir()
        history = durable.parent / "initial_state_counterfactual_history.json"
        result = analysis._failure_result(
            failure_class="pre_simulation_infrastructure", call_count=0,
            retry_count=0, candidate_sha256=None,
            error_id="synthetic:cli", error_report="synthetic CLI failure",
            exit_code=99, missing_run_artifacts=list(analysis.RUN_AUTHENTICITY_SOURCES),
        )
        def fake_publish(run_dir, capture_dir, durable_dir, history_path):
            del run_dir, capture_dir, history_path
            durable_dir.mkdir()
            (durable_dir / "analysis.json").write_bytes(self._json_bytes(result))
        argv = [
            "analyze", "--run-dir", str(self.root / "absent-run"),
            "--capture-dir", str(self.root / "capture"),
            "--durable-dir", str(durable), "--history-path", str(history),
        ]
        output = io.StringIO()
        with (mock.patch.object(sys, "argv", argv),
              mock.patch.object(analysis, "publish", side_effect=fake_publish),
              mock.patch.object(analysis, "verify_only") as verifier,
              mock.patch.object(analysis, "analyze",
                                side_effect=AssertionError("must not reread run_dir")) as live,
              contextlib.redirect_stdout(output)):
            analysis.main()
        verifier.assert_called_once_with(durable, history)
        live.assert_not_called()
        self.assertEqual(
            output.getvalue().strip(),
            "FIG519_IHX_R2_HEXE_A3=numerical_or_physical_gate_failed",
        )

    def test_cli_prints_failure_for_exit99_complete_run_and_absent_presim_run(self):
        complete = self._make_run()
        cases = (("exit99-complete", complete), ("presim-absent", None))
        for label, selected in cases:
            with self.subTest(label=label):
                capture = self._make_capture(
                    selected, exit_code=99,
                    error_id="synthetic:" + label,
                    error_report="synthetic " + label + " failure",
                )
                run_dir = selected or (self.root / "absent-presim-run")
                durable = self.root / label / "A3"
                durable.parent.mkdir()
                history = durable.parent / "initial_state_counterfactual_history.json"
                argv = [
                    "analyze", "--run-dir", str(run_dir),
                    "--capture-dir", str(capture),
                    "--durable-dir", str(durable), "--history-path", str(history),
                ]
                output = io.StringIO()
                with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
                    analysis.main()
                self.assertEqual(
                    output.getvalue().strip(),
                    "FIG519_IHX_R2_HEXE_A3=numerical_or_physical_gate_failed",
                )
                if capture.exists():
                    shutil.rmtree(capture)

    def test_analyzer_production_source_has_no_assert_and_optimized_validation_survives(self):
        source_path = Path(analysis.__file__)
        tree = ast.parse(source_path.read_text(encoding="utf-8"))
        self.assertFalse(any(isinstance(node, ast.Assert) for node in ast.walk(tree)))
        command = [
            sys.executable,
            "-O",
            "-c",
            (
                "from pathlib import Path\n"
                "from tests import analyze_fig519_ihx_r2_hexe_shift as a\n"
                "try:\n"
                " a.validate_patch_audit([], Path('/missing'))\n"
                "except a.PatchAuditError:\n"
                " print('A3_ANALYSIS_OPTIMIZED_VALIDATION_PASS')\n"
                "else:\n"
                " raise SystemExit('validation disappeared')\n"
            ),
        ]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "A3_ANALYSIS_OPTIMIZED_VALIDATION_PASS\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
