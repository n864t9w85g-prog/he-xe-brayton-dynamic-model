from __future__ import annotations

import ast
import re
import subprocess
import sys
import unittest
from decimal import Decimal, localcontext
from pathlib import Path

from tests import fig519_ihx_r2_hexe_contract as contract


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
            "validateExactFormalSet",
            "validateStateInventoryValues",
            "assertNoSymlinkAncestors(filePath, repoRoot)",
        ):
            with self.subTest(literal=literal):
                self.assertIn(literal, source)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
