#!/usr/bin/env python3
"""Prepare immutable command evidence for the approved, not-yet-run A2 attempt.

This module never launches MATLAB and never creates the formal A2 run
directory.  It snapshots the exact future command and its two MATLAB source
files while proving that the archived A1 evidence remains byte-identical.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
from pathlib import Path

try:
    from tests import analyze_fig519_counterfactual as analyzer
except ModuleNotFoundError:  # pragma: no cover - direct CLI path
    import analyze_fig519_counterfactual as analyzer


ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / "tmp"
A1 = TMP / "fig519_reactor_ic_20260831_A1"
A2 = TMP / "fig519_reactor_ic_20260901_A2"
CAPTURE = TMP / "fig519_reactor_ic_20260901_A2_command_capture"
EXECUTION_SPOOL = TMP / "fig519_reactor_ic_20260901_A2_execution_spool"
RUNNER = ROOT / "tests/run_fig519_reactor_ic_counterfactual.m"
GENERATOR = ROOT / "tests/create_fig519_reactor_ic_candidate.m"
SOURCE = ROOT / "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
SOURCE_SHA256 = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
SOURCE_COMMIT = "bf66dc6d68c4ddc6ffe44801e1a526e541ff845a"
CANDIDATE_VALUE_IDENTITY = "figure_5_19_digitized_t10_proxy_not_author_t0"
CANDIDATE_VALUE_W = 3186507.937
EXACT_COMMAND = (
    "python3 tests/prepare_fig519_reactor_ic_a2.py --verify-only && "
    "test ! -e tmp/fig519_reactor_ic_20260901_A2 && "
    "/Applications/MATLAB_R2025a.app/bin/matlab -batch \"addpath('tests','tests/steady53'); "
    "runDir=fullfile(pwd,'tmp','fig519_reactor_ic_20260901_A2'); "
    "create_fig519_reactor_ic_candidate(runDir); "
    "run_fig519_reactor_ic_counterfactual(runDir)\"")
CAPTURE_NAMES = {"command.txt", "attempted_runner.m", "candidate_generator.m",
                 "preflight_status.json", "SHA256SUMS"}
EXECUTION_NAMES = {
    "stdout.log", "stderr.log", "command_started_at_utc.txt",
    "command_completed_at_utc.txt", "formal_exit_code.txt",
    "formal_command_invocation_count.txt", "retry_count.txt",
    "timestamp_recorder_failure.json", "execution_record.json",
}
A2_ARTIFACT_SHA256 = {
    "candidate.slx": "1b142a979b4891c833e8625161b1cc75342064326124679458e2d6436f670511",
    "patch_audit.json": "aad41b70e3bc931ea1b769489d99d87cd52750f6f0a9eaa1b3b97d73ed0e580e",
    "run/experiment_started.json": "50d916248b99ddefb259e4c11928c9db3e5005496669393e9359f135439606cd",
    "run/raw_result.mat": "8a14e233c16d986cfbae8d83853e02f2794b9f2866b5a21553fe18dd4364bcfc",
    "run/candidate_curves.csv": "0ce17a5f0616117f70cd606f419e1fd117b8df5bc30fb98d47b4aee9b6022cd5",
    "run/reference_curves.csv": "2b84c50e605724c7792cb263ab48ce4d302c0d1a0e1c73e828d91be7e7813a50",
    "run/run_status.json": "87f8135081ed1292580814b29cd7f75087937a81a1a14e71701a5b1779e1ccb1",
}
SPOOL_SHA256 = {
    "stdout.log": "753b9aef43f9e8fd2fa3f8709150f5a9e09b58f286d3c60062c0ea2ee5d53842",
    "stderr.log": "5dead1446a90f7251d3d7afc4ec9408579a814a29cf560ed1e98a74b83d16e2b",
    "started_at_utc.txt": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "completed_at_utc.txt": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "exit_code.txt": "9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa",
    "formal_command_invocation_count.txt": "4355a46b19d348dc2f57c046f8ef63d4538ebb936000f3c9ee954a27460dd865",
    "retry_count.txt": "9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa",
}
COMMAND_STARTED_AT_UTC = "2026-08-31T17:35:51.334870Z"
COMMAND_COMPLETED_AT_UTC = "2026-08-31T17:37:43.837671Z"
A1_FIXED_HASHES = {
    "analysis.json": "9a6cfd2e3bf2315b0b1bb731a5e5be9fd3200787e5632e313e8619b8583d4948",
    "candidate.slx": "957273d1efcdfea35831dbf81bcd09085c6b4d178f7a8fcc7f1f62bcbecbd24e",
    "patch_audit.json": "a576ee9a95a35dcc52ebe41c5bd7e69937370a75c5b985744612f6fdbf733507",
    "run/invocation_failure.json": "7c9906e3dd283624aac3ad7a6bb75de926dd5301eb1501a0c5a1178a3c733554",
}


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True,
                       allow_nan=False) + "\n").encode()


def _safe_under_tmp(path: Path, *, require_exists: bool = False) -> Path:
    raw = Path(path)
    if not raw.is_absolute() or ".." in raw.parts:
        raise RuntimeError("preflight paths must be absolute and lexically contained")
    probe = Path(raw.anchor)
    for part in raw.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError("symlinked preflight paths are forbidden")
            if probe != raw and not stat.S_ISDIR(mode):
                raise RuntimeError("preflight path parent is not a directory")
    resolved = raw.resolve(strict=require_exists)
    if resolved == TMP.resolve() or TMP.resolve() not in resolved.parents:
        raise RuntimeError("preflight path must remain below repository tmp/")
    return resolved


def _regular(path: Path) -> Path:
    raw = Path(path)
    try:
        mode = os.lstat(raw).st_mode
    except OSError as exc:
        raise RuntimeError(f"required regular file is missing: {path}") from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise RuntimeError(f"required regular file is unsafe: {path}")
    resolved = raw.resolve(strict=True)
    return resolved


def validate_target_absent(target: Path) -> None:
    target = _safe_under_tmp(Path(target), require_exists=False)
    if os.path.lexists(target):
        raise RuntimeError(f"formal A2 target must remain absent: {target}")


def _a1_inventory() -> list[dict[str, object]]:
    root = _safe_under_tmp(A1, require_exists=True)
    if not root.is_dir():
        raise RuntimeError("archived A1 evidence directory is missing")
    records = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise RuntimeError("A1 contains an unsafe filesystem entry")
        if path.is_file():
            relative = path.relative_to(root).as_posix()
            records.append({"repository_relative_path": path.relative_to(ROOT).as_posix(),
                            "a1_relative_path": relative,
                            "bytes": path.stat().st_size,
                            "sha256": _hash(path.read_bytes())})
    indexed = {item["a1_relative_path"]: item["sha256"] for item in records}
    for relative, digest in A1_FIXED_HASHES.items():
        if indexed.get(relative) != digest:
            raise RuntimeError(f"archived A1 evidence changed: {relative}")
    if set(path.name for path in (A1 / "run").iterdir()) != {"invocation_failure.json"}:
        raise RuntimeError("A1 run evidence set changed")
    audit = json.loads(_regular(A1 / "patch_audit.json").read_text())
    analyzer.validate_patch_audit(audit, run_dir=A1)
    if (audit["candidate_value_identity"] != CANDIDATE_VALUE_IDENTITY or
            audit["candidate_value_W"] != CANDIDATE_VALUE_W or
            audit["changed_blocks"] != ["reactor/Integrator6"] or
            audit["changed_parameters"] != ["InitialCondition"]):
        raise RuntimeError("A1 candidate exact-one-change identity changed")
    return records


def _source_contract() -> tuple[bytes, bytes, list[dict[str, object]]]:
    runner = _regular(RUNNER).read_bytes()
    generator = _regular(GENERATOR).read_bytes()
    if b'fopen(filePath, "x"' in runner:
        raise RuntimeError("runner still uses the unsupported fopen x permission")
    for token in (b"java.nio.file.Files.createDirectory",
                  b"java.nio.file.Files.createFile"):
        if token not in runner:
            raise RuntimeError("runner lacks an atomic one-shot marker")
    executable_calls = [line for line in runner.decode().splitlines()
                        if "run_steady53_case(" in line and
                        not line.lstrip().startswith("%")]
    if executable_calls != ["    runResult = run_steady53_case(candidatePath, 500, true);"]:
        raise RuntimeError("runner must contain exactly one approved simulation call")
    if (CANDIDATE_VALUE_IDENTITY.encode() not in generator or
            b'"reactor/Integrator6"' not in generator):
        raise RuntimeError("candidate generator identity contract changed")
    artifacts = [
        {"name": "command.txt", "bytes": len((EXACT_COMMAND + "\n").encode()),
         "sha256": _hash((EXACT_COMMAND + "\n").encode())},
        {"name": "attempted_runner.m", "bytes": len(runner), "sha256": _hash(runner)},
        {"name": "candidate_generator.m", "bytes": len(generator),
         "sha256": _hash(generator)},
    ]
    return runner, generator, artifacts


def _status(inventory: list[dict[str, object]], artifacts: list[dict[str, object]]) -> dict[str, object]:
    source = _regular(SOURCE)
    if _hash(source.read_bytes()) != SOURCE_SHA256:
        raise RuntimeError("immutable source model hash changed")
    return {
        "preflight_schema": "steady53_fig519_reactor_ic_a2_preflight_v1",
        "static_preflight_passed": True,
        "formal_execution_performed": False,
        "simulation_call_count": 0,
        "retry_count": 0,
        "a2_target_repository_path": A2.relative_to(ROOT).as_posix(),
        "a2_target_absolute_path": str(A2),
        "a2_target_absent": True,
        "command_requires_target_absent": True,
        "exact_command_sha256": artifacts[0]["sha256"],
        "runner_sha256": artifacts[1]["sha256"],
        "candidate_generator_sha256": artifacts[2]["sha256"],
        "source_sha256": SOURCE_SHA256,
        "candidate_value_identity": CANDIDATE_VALUE_IDENTITY,
        "candidate_value_W": CANDIDATE_VALUE_W,
        "changed_blocks": ["reactor/Integrator6"],
        "changed_parameters": ["InitialCondition"],
        "candidate_is_circular_counterfactual": True,
        "candidate_is_author_t0": False,
        "source_commit": SOURCE_COMMIT,
        "captured_artifacts": artifacts,
        "a1_archive": {
            "attempt_id": "20260831_A1",
            "repository_path": A1.relative_to(ROOT).as_posix(),
            "file_count": len(inventory),
            "files": inventory,
            "must_remain_immutable": True,
        },
        "persistence_plan": {
            "history_mode": "append_only_attempts",
            "preserved_attempt_ids": ["20260831_A1"],
            "append_attempt_id": "20260901_A2",
            "overwrite_existing_attempts": False,
            "a1_evidence_path": A1.relative_to(ROOT).as_posix(),
            "a2_evidence_path": A2.relative_to(ROOT).as_posix(),
            "future_summary_requires_attempt_history": True,
            "future_manifest_requires_separate_a1_and_a2_locators": True,
        },
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
        "next_step": "wait_for_explicit_order_before_the_single_A2_command",
    }


def _write_exclusive(path: Path, payload: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


def prepare(capture_dir: Path = CAPTURE) -> None:
    validate_target_absent(A2)
    capture = _safe_under_tmp(Path(capture_dir), require_exists=False)
    if os.path.lexists(capture):
        raise RuntimeError("A2 command capture already exists")
    inventory = _a1_inventory()
    runner, generator, artifacts = _source_contract()
    status = _status(inventory, artifacts)
    os.mkdir(capture, 0o700)
    _write_exclusive(capture / "command.txt", (EXACT_COMMAND + "\n").encode())
    _write_exclusive(capture / "attempted_runner.m", runner)
    _write_exclusive(capture / "candidate_generator.m", generator)
    _write_exclusive(capture / "preflight_status.json", _json_bytes(status))
    sums = "".join(f"{item['sha256']}  {item['name']}\n" for item in artifacts).encode()
    _write_exclusive(capture / "SHA256SUMS", sums)
    verify_only(capture)


def _verify_preflight_snapshot(capture_dir: Path) -> None:
    capture = _safe_under_tmp(Path(capture_dir), require_exists=True)
    if not capture.is_dir() or not CAPTURE_NAMES.issubset(
            {entry.name for entry in capture.iterdir()}):
        raise RuntimeError("A2 command capture shape is invalid")
    inventory = _a1_inventory()
    runner, generator, artifacts = _source_contract()
    status = _status(inventory, artifacts)
    expected = {
        "command.txt": (EXACT_COMMAND + "\n").encode(),
        "attempted_runner.m": runner,
        "candidate_generator.m": generator,
        "preflight_status.json": _json_bytes(status),
        "SHA256SUMS": "".join(f"{item['sha256']}  {item['name']}\n"
                               for item in artifacts).encode(),
    }
    for name, payload in expected.items():
        path = _regular(capture / name)
        if path.read_bytes() != payload:
            raise RuntimeError(f"A2 command capture mismatch: {name}")


def verify_only(capture_dir: Path = CAPTURE) -> None:
    validate_target_absent(A2)
    capture = _safe_under_tmp(Path(capture_dir), require_exists=True)
    if {entry.name for entry in capture.iterdir()} != CAPTURE_NAMES:
        raise RuntimeError("A2 preflight capture must not contain execution evidence")
    _verify_preflight_snapshot(capture)


def _fixed_locator(path: Path, root: Path) -> dict[str, object]:
    path = _regular(path)
    return {
        "repository_relative_path": path.relative_to(ROOT).as_posix(),
        "root_relative_path": path.relative_to(root).as_posix(),
        "absolute_path": str(path),
        "bytes": path.stat().st_size,
        "sha256": _hash(path.read_bytes()),
        "storage": "external_tmp_not_copied",
    }


def _validate_a2(run_dir: Path) -> tuple[dict[str, object], dict[str, object]]:
    run_dir = _safe_under_tmp(Path(run_dir), require_exists=True)
    if run_dir != A2.resolve() or not run_dir.is_dir():
        raise RuntimeError("execution evidence must bind the fixed A2 directory")
    actual = {}
    for relative, expected in A2_ARTIFACT_SHA256.items():
        path = _regular(run_dir / relative)
        digest = _hash(path.read_bytes())
        if digest != expected:
            raise RuntimeError(f"A2 artifact identity changed: {relative}")
        actual[relative] = _fixed_locator(path, run_dir)
    audit = json.loads(_regular(run_dir / "patch_audit.json").read_text())
    analyzer.validate_patch_audit(audit, run_dir=run_dir)
    analysis = analyzer.analyze(run_dir)
    status = json.loads(_regular(run_dir / "run/run_status.json").read_text())
    if (status.get("experiment_status") != "completed_success" or
            status.get("candidate_success") is not True or
            status.get("candidate_final_time_s") != 500 or
            status.get("run_steady53_case_call_count") != 1 or
            status.get("retry_count") != 0 or
            status.get("rerun_forbidden") is not True or
            analysis.get("formal_command_invocation_count") != 1 or
            analysis.get("run_steady53_case_call_count") != 1 or
            analysis.get("retry_count") != 0):
        raise RuntimeError("A2 completed-run contract mismatch")
    return status, actual


def _timestamp_failure() -> dict[str, object]:
    return {
        "failure_schema": "steady53_fig519_a2_wrapper_timestamp_recorder_failure_v1",
        "scope": "outer_wrapper_timestamp_capture_only",
        "formal_command_affected": False,
        "formal_stdout_or_stderr": False,
        "missing_program": "/usr/bin/date",
        "available_program": "/bin/date",
        "raw_started_at_file_bytes": 0,
        "raw_completed_at_file_bytes": 0,
        "raw_empty_sha256": SPOOL_SHA256["started_at_utc.txt"],
        "fallback_start_source": "APFS birth time of stdout.log redirection target",
        "fallback_completion_source": "APFS birth time of exit_code.txt written after command return",
        "fallback_is_exact_wrapper_timestamp": False,
        "formal_command_exit_code_preserved": True,
        "retry_performed": False,
    }


def _execution_record(capture: Path, run_dir: Path) -> dict[str, object]:
    status, a2_artifacts = _validate_a2(run_dir)
    capture_artifacts = []
    for name in sorted((CAPTURE_NAMES | EXECUTION_NAMES) - {"execution_record.json"}):
        capture_artifacts.append({"name": name, **_fixed_locator(capture / name, capture)})
    return {
        "execution_schema": "steady53_fig519_reactor_ic_a2_execution_v1",
        "attempt_id": "20260901_A2",
        "formal_command": EXACT_COMMAND,
        "formal_command_sha256": _hash((EXACT_COMMAND + "\n").encode()),
        "formal_command_invocation_count": 1,
        "run_steady53_case_call_count": 1,
        "retry_count": 0,
        "rerun_forbidden": True,
        "formal_process_exit_code": 0,
        "command_started_at_utc": COMMAND_STARTED_AT_UTC,
        "command_completed_at_utc": COMMAND_COMPLETED_AT_UTC,
        "timestamp_quality": "filesystem_birthtime_fallback_not_wrapper_timestamp",
        "wrapper_timestamp_recorder_error": _timestamp_failure(),
        "runner_started_at_utc": status["started_at_utc"],
        "runner_completed_at_utc": status["completed_at_utc"],
        "runner_status": status["experiment_status"],
        "candidate_success": status["candidate_success"],
        "candidate_final_time_s": status["candidate_final_time_s"],
        "attempted_runner_sha256": _hash(_regular(capture / "attempted_runner.m").read_bytes()),
        "candidate_generator_sha256": _hash(
            _regular(capture / "candidate_generator.m").read_bytes()),
        "source_sha256": SOURCE_SHA256,
        "candidate_value_identity": CANDIDATE_VALUE_IDENTITY,
        "candidate_value_W": CANDIDATE_VALUE_W,
        "changed_blocks": ["reactor/Integrator6"],
        "changed_parameters": ["InitialCondition"],
        "a2_artifacts": a2_artifacts,
        "capture_artifacts": capture_artifacts,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }


def archive_execution(capture_dir: Path = CAPTURE,
                      spool_dir: Path = EXECUTION_SPOOL,
                      run_dir: Path = A2) -> None:
    """Archive the already-consumed A2 command; this function never executes it."""
    capture = _safe_under_tmp(Path(capture_dir), require_exists=True)
    spool = _safe_under_tmp(Path(spool_dir), require_exists=True)
    run_dir = _safe_under_tmp(Path(run_dir), require_exists=True)
    _verify_preflight_snapshot(capture)
    names = {entry.name for entry in capture.iterdir()}
    if names == CAPTURE_NAMES | EXECUTION_NAMES:
        verify_execution(capture, run_dir)
        return
    if names != CAPTURE_NAMES:
        raise RuntimeError("A2 capture is neither preflight-only nor complete")
    if (not spool.is_dir() or
            {entry.name for entry in spool.iterdir()} != set(SPOOL_SHA256)):
        raise RuntimeError("A2 raw execution spool shape changed")
    for name, expected in SPOOL_SHA256.items():
        path = _regular(spool / name)
        if _hash(path.read_bytes()) != expected:
            raise RuntimeError(f"A2 raw execution spool changed: {name}")
    if ((spool / "exit_code.txt").read_text() != "0\n" or
            (spool / "formal_command_invocation_count.txt").read_text() != "1\n" or
            (spool / "retry_count.txt").read_text() != "0\n" or
            (spool / "started_at_utc.txt").read_bytes() or
            (spool / "completed_at_utc.txt").read_bytes()):
        raise RuntimeError("A2 raw command counters/timestamps conflict")
    if not os.path.exists("/bin/date") or os.path.exists("/usr/bin/date"):
        raise RuntimeError("wrapper timestamp fallback root cause changed")

    payloads = {
        "stdout.log": (spool / "stdout.log").read_bytes(),
        "stderr.log": (spool / "stderr.log").read_bytes(),
        "command_started_at_utc.txt": (COMMAND_STARTED_AT_UTC + "\n").encode(),
        "command_completed_at_utc.txt": (COMMAND_COMPLETED_AT_UTC + "\n").encode(),
        "formal_exit_code.txt": b"0\n",
        "formal_command_invocation_count.txt": b"1\n",
        "retry_count.txt": b"0\n",
        "timestamp_recorder_failure.json": _json_bytes(_timestamp_failure()),
    }
    for name, payload in payloads.items():
        _write_exclusive(capture / name, payload)
    _write_exclusive(capture / "execution_record.json",
                     _json_bytes(_execution_record(capture, run_dir)))
    verify_execution(capture, run_dir)


def verify_execution(capture_dir: Path = CAPTURE,
                     run_dir: Path = A2) -> dict[str, object]:
    capture = _safe_under_tmp(Path(capture_dir), require_exists=True)
    run_dir = _safe_under_tmp(Path(run_dir), require_exists=True)
    if {entry.name for entry in capture.iterdir()} != CAPTURE_NAMES | EXECUTION_NAMES:
        raise RuntimeError("A2 post-execution capture shape is invalid")
    _verify_preflight_snapshot(capture)
    fixed_payloads = {
        "command_started_at_utc.txt": (COMMAND_STARTED_AT_UTC + "\n").encode(),
        "command_completed_at_utc.txt": (COMMAND_COMPLETED_AT_UTC + "\n").encode(),
        "formal_exit_code.txt": b"0\n",
        "formal_command_invocation_count.txt": b"1\n",
        "retry_count.txt": b"0\n",
        "timestamp_recorder_failure.json": _json_bytes(_timestamp_failure()),
    }
    for name, payload in fixed_payloads.items():
        if _regular(capture / name).read_bytes() != payload:
            raise RuntimeError(f"A2 archived execution field changed: {name}")
    for name in ("stdout.log", "stderr.log"):
        if _hash(_regular(capture / name).read_bytes()) != SPOOL_SHA256[name]:
            raise RuntimeError(f"A2 archived command log changed: {name}")
    record = json.loads(_regular(capture / "execution_record.json").read_text())
    expected = _execution_record(capture, run_dir)
    if record != expected:
        raise RuntimeError("A2 execution record differs from recomputation")
    return record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        if os.path.lexists(A2):
            verify_execution(CAPTURE, A2)
            print("FIG519_REACTOR_IC_A2_EXECUTION=VERIFIED_NO_RERUN")
            return
        verify_only(CAPTURE)
    else:
        prepare(CAPTURE)
    print("FIG519_REACTOR_IC_A2_PREFLIGHT=READY_NO_SIMULATION")


if __name__ == "__main__":
    main()
