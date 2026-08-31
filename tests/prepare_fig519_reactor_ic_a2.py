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


def verify_only(capture_dir: Path = CAPTURE) -> None:
    validate_target_absent(A2)
    capture = _safe_under_tmp(Path(capture_dir), require_exists=True)
    if not capture.is_dir() or {entry.name for entry in capture.iterdir()} != CAPTURE_NAMES:
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        verify_only(CAPTURE)
    else:
        prepare(CAPTURE)
    print("FIG519_REACTOR_IC_A2_PREFLIGHT=READY_NO_SIMULATION")


if __name__ == "__main__":
    main()
