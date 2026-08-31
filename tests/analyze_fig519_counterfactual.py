#!/usr/bin/env python3
"""Analyze and atomically publish the one Figure 5.19 reactor-IC test.

The module never runs MATLAB.  It accepts only the exact API patch audit and
one-shot runner evidence, applies predeclared curve gates, and can only answer
the stated falsification question.  It cannot promote a model or identify an
author initial state.
"""
from __future__ import annotations

import argparse
import csv
import fcntl
import hashlib
import io
import json
import math
import os
import stat
import tempfile
from bisect import bisect_left
from contextlib import contextmanager
from itertools import groupby
from pathlib import Path

try:
    from tests import analyze_fig519_baseline as baseline
    from tests import digitize_fig519 as paper_module
except ModuleNotFoundError:  # pragma: no cover - direct CLI path
    import analyze_fig519_baseline as baseline
    import digitize_fig519 as paper_module


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/provenance/steady53/fig5_19"
DEFAULT_RUN_DIR = ROOT / "tmp/fig519_reactor_ic_20260831_A1"
A1_RUN_DIR = DEFAULT_RUN_DIR
A2_RUN_DIR = ROOT / "tmp/fig519_reactor_ic_20260901_A2"
A2_EXECUTION_CAPTURE = ROOT / "tmp/fig519_reactor_ic_20260901_A2_command_capture"
SOURCE_PATH = ROOT / "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
SOURCE_SHA256 = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
PAPER_POINTS_SHA256 = "e63607ad0f599c84fe6980ed26e05c91902b7928a53fabf5bf4a95a3de0098f2"
RAW_REFERENCE_SHA256 = "185d59ca6e55647ad14fb5f23599bc85e6566f8da2ca6120f42a0ef8dedbb648"
SUMMARY_NAME = "reactor_ic_counterfactual.json"
A1_DURABLE_SUMMARY_SHA256 = "fbd294ecabe7ffc04b90e1ffc5198335f099fc46ba718cd4f8c57b4b75230950"
CANDIDATE_VALUE_IDENTITY = "figure_5_19_digitized_t10_proxy_not_author_t0"
CONCLUSIONS = {
    "reactor_ic_alone_falsified",
    "reactor_ic_alone_not_falsified_but_not_validated",
    "numerical_or_physical_gate_failed",
}
DIRECTION_RULE = {
    "input": "successive fixed digitized/model samples in increasing time",
    "threshold": "panel_power_allowance_kW",
    "classification": "rise if delta>allowance; fall if delta<-allowance; otherwise flat",
    "flat_handling": "discard_before_compression",
    "compression": "collapse consecutive identical non-flat directions",
    "candidate_threshold_declared_before_experiment": True,
}
NONFLAT_RATIO = 10.0
PAPER_ETA = 0.98
HISTORICAL_ETA = 0.96527
ATTEMPTED_RUNNER_SHA256 = "42f447ae2ddfd6829b037548c2dd7d0af7d0a38aef779ee898cd30bf2ebd109b"
INVOCATION_FAILURE_SHA256 = "7c9906e3dd283624aac3ad7a6bb75de926dd5301eb1501a0c5a1178a3c733554"
EXPECTED_FORMAL_COMMAND = (
    "test ! -e tmp/fig519_reactor_ic_20260831_A1 && "
    "/Applications/MATLAB_R2025a.app/bin/matlab -batch \"addpath('tests','tests/steady53'); "
    "runDir=fullfile(pwd,'tmp','fig519_reactor_ic_20260831_A1'); "
    "create_fig519_reactor_ic_candidate(runDir); "
    "run_fig519_reactor_ic_counterfactual(runDir)\"")
EXPECTED_FAILURE_REPORT = (
    "错误使用 fopen\n权限无效。\n\n"
    "出错 run_fig519_reactor_ic_counterfactual>writeExclusiveText (第 344 行)\n"
    "file = fopen(filePath, \"x\", \"n\", \"UTF-8\");\n"
    "       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n"
    "出错 run_fig519_reactor_ic_counterfactual (第 38 行)\n"
    "writeExclusiveText(fullfile(runPath, \"experiment_started.json\"), ...\n"
    "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^")
SUCCESS_EXTERNAL_ARTIFACT_KEYS = (
    "@external/reactor_ic_candidate.slx",
    "@external/reactor_ic_patch_audit.json",
    "@external/reactor_ic_raw_result.mat",
    "@external/reactor_ic_run_status.json",
    "@external/reactor_ic_candidate_curves.csv",
    "@external/reactor_ic_reference_curves.csv",
    "@external/reactor_ic_analysis.json",
)
FAILURE_EXTERNAL_ARTIFACT_KEYS = (
    "@external/reactor_ic_candidate.slx",
    "@external/reactor_ic_patch_audit.json",
    "@external/reactor_ic_invocation_failure.json",
    "@external/reactor_ic_analysis.json",
)
A1_HISTORY_EXTERNAL_KEYS = {
    "candidate_slx": "@external/reactor_ic_a1_candidate.slx",
    "patch_audit": "@external/reactor_ic_a1_patch_audit.json",
    "invocation_failure_status": "@external/reactor_ic_a1_invocation_failure.json",
    "analysis": "@external/reactor_ic_a1_analysis.json",
}
A2_HISTORY_EXTERNAL_KEYS = {
    "candidate_slx": "@external/reactor_ic_a2_candidate.slx",
    "patch_audit": "@external/reactor_ic_a2_patch_audit.json",
    "raw_result": "@external/reactor_ic_a2_raw_result.mat",
    "run_status": "@external/reactor_ic_a2_run_status.json",
    "candidate_curves": "@external/reactor_ic_a2_candidate_curves.csv",
    "reference_curves": "@external/reactor_ic_a2_reference_curves.csv",
    "analysis": "@external/reactor_ic_a2_analysis.json",
}
A2_CAPTURE_EXTERNAL_KEYS = {
    "command.txt": "@external/reactor_ic_a2_command.txt",
    "attempted_runner.m": "@external/reactor_ic_a2_attempted_runner.m",
    "candidate_generator.m": "@external/reactor_ic_a2_candidate_generator.m",
    "preflight_status.json": "@external/reactor_ic_a2_preflight_status.json",
    "SHA256SUMS": "@external/reactor_ic_a2_preflight_SHA256SUMS",
    "stdout.log": "@external/reactor_ic_a2_stdout.log",
    "stderr.log": "@external/reactor_ic_a2_stderr.log",
    "command_started_at_utc.txt": "@external/reactor_ic_a2_command_started_at_utc.txt",
    "command_completed_at_utc.txt": "@external/reactor_ic_a2_command_completed_at_utc.txt",
    "formal_exit_code.txt": "@external/reactor_ic_a2_formal_exit_code.txt",
    "formal_command_invocation_count.txt":
        "@external/reactor_ic_a2_formal_command_invocation_count.txt",
    "retry_count.txt": "@external/reactor_ic_a2_retry_count.txt",
    "timestamp_recorder_failure.json":
        "@external/reactor_ic_a2_timestamp_recorder_failure.json",
    "execution_record.json": "@external/reactor_ic_a2_execution_record.json",
}
# Backward-compatible name used by the successful synthetic publication tests.
EXTERNAL_ARTIFACT_KEYS = SUCCESS_EXTERNAL_ARTIFACT_KEYS
_SUCCESS_EXTERNAL_IDENTITIES = {
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[0]: "candidate_slx",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[1]: "patch_audit",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[2]: "raw_result",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[3]: "run_status",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[4]: "candidate_curves",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[5]: "reference_curves",
    SUCCESS_EXTERNAL_ARTIFACT_KEYS[6]: "analysis",
}
_FAILURE_EXTERNAL_IDENTITIES = {
    FAILURE_EXTERNAL_ARTIFACT_KEYS[0]: "candidate_slx",
    FAILURE_EXTERNAL_ARTIFACT_KEYS[1]: "patch_audit",
    FAILURE_EXTERNAL_ARTIFACT_KEYS[2]: "invocation_failure_status",
    FAILURE_EXTERNAL_ARTIFACT_KEYS[3]: "analysis",
}
TRANSACTION_VERSION = 1
TARGETS = (SUMMARY_NAME, "manifest.csv")


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True,
                       allow_nan=False) + "\n").encode()


def _safe_under_repo(path: Path, *, require_exists: bool = False,
                     require_tmp: bool = False) -> Path:
    raw = Path(path)
    if not raw.is_absolute() or ".." in raw.parts:
        raise RuntimeError("path must be absolute and lexically contained")
    probe = Path(raw.anchor)
    for part in raw.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError("symlinked paths are forbidden")
            if probe != raw and not stat.S_ISDIR(mode):
                raise RuntimeError("path parent is not a directory")
    resolved = raw.resolve(strict=require_exists)
    root = ROOT.resolve()
    if resolved != root and root not in resolved.parents:
        raise RuntimeError("path is outside repository")
    if require_tmp and (ROOT / "tmp").resolve() not in resolved.parents:
        raise RuntimeError("evidence path must remain below repository tmp/")
    return resolved


def _regular_file(path: Path, *, require_tmp: bool = False) -> Path:
    try:
        resolved = _safe_under_repo(path, require_exists=True, require_tmp=require_tmp)
    except OSError as exc:
        raise RuntimeError(f"required regular file is missing: {path}") from exc
    if resolved.is_symlink() or not resolved.is_file():
        raise RuntimeError(f"required regular file is missing: {resolved}")
    return resolved


def _paper_points(path: Path) -> dict[str, list[tuple[float, float, float]]]:
    path = _regular_file(Path(path))
    if _hash(path.read_bytes()) != PAPER_POINTS_SHA256:
        raise RuntimeError("paper points hash does not match Task 4")
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    grouped: dict[str, list[tuple[float, float, float]]] = {key: [] for key in "abcd"}
    seen: set[tuple[str, float]] = set()
    for row in rows:
        panel = row.get("panel_id")
        if panel not in grouped:
            raise RuntimeError("paper points contain an unknown panel")
        try:
            item = (float(row["time_s"]), float(row["power_kW"]),
                    float(row["power_allowance_kW"]))
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError("paper points contain malformed numbers") from exc
        if (not all(math.isfinite(value) for value in item) or item[2] <= 0 or
                (panel, item[0]) in seen):
            raise RuntimeError("paper points violate the fixed numeric contract")
        seen.add((panel, item[0]))
        grouped[panel].append(item)
    if any(len(points) != 15 or points != sorted(points) for points in grouped.values()):
        raise RuntimeError("each panel must have 15 increasing fixed points")
    return grouped


def direction_sequence(points: list[tuple[float, float, float]]) -> list[str]:
    directions: list[str] = []
    for left, right in zip(points, points[1:]):
        if left[2] != right[2]:
            raise RuntimeError("direction allowance must be fixed within a panel")
        delta = right[1] - left[1]
        if delta > left[2]:
            directions.append("rise")
        elif delta < -left[2]:
            directions.append("fall")
        else:
            directions.append("flat")
    nonflat = (direction for direction in directions if direction != "flat")
    return [key for key, _ in groupby(nonflat)]


def _expected_runtime() -> list[dict[str, object]]:
    audit = json.loads((OUTPUT / "initialization_audit.json").read_text())
    return list(audit["runtime_dependency_contract"]["dependencies"])


def _expected_states() -> list[dict[str, object]]:
    audit = json.loads((OUTPUT / "initialization_audit.json").read_text())
    return list(audit["state_inventory"])


def _expected_protected() -> list[dict[str, str]]:
    path = ROOT / "data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv"
    if _hash(path.read_bytes()) != "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64":
        raise RuntimeError("protected manifest identity changed")
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 34:
        raise RuntimeError("protected manifest must contain 34 rows")
    return rows


def _before_after(name: str, relative: str, absolute: str, digest: str) -> dict[str, object]:
    return {"name": name, "repository_relative_path": relative,
            "absolute_path": absolute, "before_sha256": digest,
            "after_sha256": digest, "unchanged": True}


def synthetic_patch_audit(*, candidate_path: Path,
                          candidate_sha256: str) -> dict[str, object]:
    """Return a fully contracted audit fixture; production reads MATLAB JSON."""
    state_records = []
    for item in _expected_states():
        relative = item["path"].removeprefix("final_steady_24a/")
        source = item["initial_condition_expression"]
        candidate = "3186507.937" if relative == "reactor/Integrator6" else source
        state_records.append({"path": relative, "source_expression": source,
                              "candidate_expression": candidate,
                              "unchanged": relative != "reactor/Integrator6"})
    runtime = []
    for item in _expected_runtime():
        absolute = item["resolved_path"]
        relative = Path(absolute).relative_to(ROOT).as_posix()
        runtime.append(_before_after(item["name"], relative, absolute, item["sha256"]))
    protected = []
    for item in _expected_protected():
        absolute = item["resolved_path"]
        try:
            relative = Path(absolute).relative_to(ROOT).as_posix()
        except ValueError:
            relative = ""
        protected.append(_before_after(item["original_path"], relative, absolute,
                                       item["resolved_sha256"]))
    candidate_path = Path(candidate_path)
    return {
        "patch_schema": "steady53_fig519_reactor_ic_counterfactual_patch_v1",
        "source_repository_relative_path": SOURCE_PATH.relative_to(ROOT).as_posix(),
        "source_absolute_path": str(SOURCE_PATH), "source_sha256": SOURCE_SHA256,
        "source_sha256_after": SOURCE_SHA256, "source_hash_unchanged": True,
        "candidate_repository_relative_path": (candidate_path.relative_to(ROOT).as_posix()
                                                  if ROOT in candidate_path.parents else str(candidate_path)),
        "candidate_absolute_path": str(candidate_path),
        "candidate_sha256": candidate_sha256,
        "candidate_value_identity": CANDIDATE_VALUE_IDENTITY,
        "candidate_value_W": 3186507.937,
        "paper_point": {"panel_id": "a", "time_s": 10.0,
                        "power_kW": 3186.507937,
                        "conversion": "1000*power_kW", "is_author_t0": False,
                        "limitation": "digitized t=10 proxy; not an author t0 value"},
        "circular_counterfactual": True,
        "counterfactual_question": "Can the full four-power transient be explained by changing the reactor power state alone?",
        "changed_blocks": ["reactor/Integrator6"],
        "changed_parameters": ["InitialCondition"], "state_count": 40,
        "state_initial_conditions": state_records,
        "solver_contract": {"unchanged": True, "parameter_count": 39,
                            "parameters": [{"name": f"solver_{i:02d}", "value": "fixed"}
                                           for i in range(39)]},
        "semantic_snapshot": {"unchanged": True,
                              "source": {"block_count": 1, "edge_count": 1,
                                         "block_fingerprint": "a" * 64,
                                         "edge_fingerprint": "b" * 64},
                              "candidate": {"block_count": 1, "edge_count": 1,
                                            "block_fingerprint": "a" * 64,
                                            "edge_fingerprint": "b" * 64}},
        "runtime_dependencies": runtime,
        "mat_files": [item for item in runtime if item["name"].endswith(".mat")],
        "property_files": [item for item in runtime if item["name"] in
                           {"HeXe_property_simulink.m", "Lithium_property_simulink.m"}],
        "protected_manifest_sha256": "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64",
        "protected_files": protected, "paper_reproduced": False,
        "author_initial_state_identified": False, "formal_promotion": False,
    }


def _validate_identity_records(records: object, expected: list[tuple[str, str]],
                               *, require_files: bool,
                               allow_external: bool = False) -> list[dict[str, object]]:
    if not isinstance(records, list) or len(records) != len(expected):
        raise RuntimeError("identity record count mismatch")
    output: list[dict[str, object]] = []
    for item, (name, digest) in zip(records, expected):
        if not isinstance(item, dict) or item.get("name") != name:
            raise RuntimeError("identity record name/order mismatch")
        if (item.get("before_sha256") != digest or item.get("after_sha256") != digest or
                item.get("unchanged") is not True):
            raise RuntimeError(f"identity changed: {name}")
        relative, absolute = item.get("repository_relative_path"), item.get("absolute_path")
        if not isinstance(relative, str) or not isinstance(absolute, str):
            raise RuntimeError("identity paths are missing")
        expected_absolute = Path(absolute) if allow_external and not relative else ROOT / relative
        if expected_absolute != Path(absolute):
            raise RuntimeError("identity relative/absolute paths disagree")
        if require_files:
            if allow_external and not relative:
                path = expected_absolute.resolve(strict=True)
                if path.is_symlink() or not path.is_file():
                    raise RuntimeError(f"external protected identity is unsafe: {name}")
            else:
                path = _regular_file(expected_absolute)
            if _hash(path.read_bytes()) != digest:
                raise RuntimeError(f"identity file hash changed: {name}")
        output.append(item)
    return output


def validate_patch_audit(audit: object, run_dir: Path | None = None,
                         *, require_files: bool = True) -> dict[str, object]:
    if not isinstance(audit, dict):
        raise RuntimeError("patch audit must be an object")
    paper = _paper_points(OUTPUT / "paper_points.csv")
    proxy = paper["a"][0]
    if proxy != (10.0, 3186.507937, 25.0):
        raise RuntimeError("fixed t=10 paper proxy changed")
    fixed = {
        "patch_schema": "steady53_fig519_reactor_ic_counterfactual_patch_v1",
        "source_sha256": SOURCE_SHA256, "source_sha256_after": SOURCE_SHA256,
        "source_hash_unchanged": True,
        "candidate_value_identity": CANDIDATE_VALUE_IDENTITY,
        "candidate_value_W": 1000.0 * proxy[1], "circular_counterfactual": True,
        "changed_blocks": ["reactor/Integrator6"],
        "changed_parameters": ["InitialCondition"], "state_count": 40,
        "paper_reproduced": False, "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    for key, value in fixed.items():
        if audit.get(key) != value:
            raise RuntimeError(f"patch audit fixed field mismatch: {key}")
    point = audit.get("paper_point")
    if (not isinstance(point, dict) or point.get("panel_id") != "a" or
            point.get("time_s") != 10 or point.get("power_kW") != proxy[1] or
            point.get("conversion") != "1000*power_kW" or
            point.get("is_author_t0") is not False):
        raise RuntimeError("patch audit paper proxy is invalid")
    source_relative = audit.get("source_repository_relative_path")
    if source_relative != SOURCE_PATH.relative_to(ROOT).as_posix():
        raise RuntimeError("patch audit source path mismatch")
    if audit.get("source_absolute_path") != str(SOURCE_PATH):
        raise RuntimeError("patch audit absolute source mismatch")
    if require_files and _hash(_regular_file(SOURCE_PATH).read_bytes()) != SOURCE_SHA256:
        raise RuntimeError("source model changed")

    states = audit.get("state_initial_conditions")
    expected_states = _expected_states()
    if not isinstance(states, list) or len(states) != 40:
        raise RuntimeError("patch audit must contain 40 state IC records")
    changed = []
    for item, expected in zip(states, expected_states):
        relative = expected["path"].removeprefix("final_steady_24a/")
        if item.get("path") != relative or item.get("source_expression") != expected["initial_condition_expression"]:
            raise RuntimeError("state path/source expression mismatch")
        same = item.get("source_expression") == item.get("candidate_expression")
        if item.get("unchanged") is not same:
            raise RuntimeError("state unchanged flag is inconsistent")
        if not same:
            changed.append(item)
    if len(changed) != 1 or changed[0]["path"] != "reactor/Integrator6":
        raise RuntimeError("exactly reactor/Integrator6 must change")
    try:
        changed_value = float(changed[0]["candidate_expression"])
    except (TypeError, ValueError) as exc:
        raise RuntimeError("candidate IC expression is not a numeric scalar") from exc
    if not math.isfinite(changed_value) or changed_value != fixed["candidate_value_W"]:
        raise RuntimeError("candidate IC value does not equal the paper proxy conversion")

    solver = audit.get("solver_contract")
    if (not isinstance(solver, dict) or solver.get("unchanged") is not True or
            not isinstance(solver.get("parameters"), list) or
            solver.get("parameter_count") != len(solver["parameters"]) or
            solver["parameter_count"] < 30 or
            len({row.get("name") for row in solver["parameters"]}) != solver["parameter_count"]):
        raise RuntimeError("complete unchanged solver contract is missing")
    semantic = audit.get("semantic_snapshot")
    if (not isinstance(semantic, dict) or semantic.get("unchanged") is not True or
            semantic.get("source") != semantic.get("candidate")):
        raise RuntimeError("semantic topology contract changed")
    for field in ("block_fingerprint", "edge_fingerprint"):
        digest = semantic["source"].get(field)
        if not isinstance(digest, str) or len(digest) != 64:
            raise RuntimeError("semantic fingerprint is invalid")

    runtime_expected = [(item["name"], item["sha256"]) for item in _expected_runtime()]
    runtime = _validate_identity_records(audit.get("runtime_dependencies"), runtime_expected,
                                         require_files=require_files)
    mats = [item for item in runtime if item["name"].endswith(".mat")]
    properties = [item for item in runtime if item["name"] in
                  {"HeXe_property_simulink.m", "Lithium_property_simulink.m"}]
    if audit.get("mat_files") != mats or audit.get("property_files") != properties:
        raise RuntimeError("MAT/property identity subsets are not exact")
    protected_rows = _expected_protected()
    protected_expected = [(row["original_path"], row["resolved_sha256"])
                          for row in protected_rows]
    _validate_identity_records(audit.get("protected_files"), protected_expected,
                               require_files=require_files, allow_external=True)
    if audit.get("protected_manifest_sha256") != "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64":
        raise RuntimeError("protected manifest hash is invalid")

    candidate_relative = audit.get("candidate_repository_relative_path")
    candidate_absolute = audit.get("candidate_absolute_path")
    digest = audit.get("candidate_sha256")
    if (not isinstance(candidate_relative, str) or not isinstance(candidate_absolute, str) or
            not isinstance(digest, str) or len(digest) != 64):
        raise RuntimeError("candidate locator is malformed")
    if require_files:
        candidate = _regular_file(ROOT / candidate_relative, require_tmp=True)
        if candidate != Path(candidate_absolute) or _hash(candidate.read_bytes()) != digest:
            raise RuntimeError("candidate locator/hash mismatch")
        if run_dir is not None and candidate.parent != _safe_under_repo(Path(run_dir), require_exists=True,
                                                                        require_tmp=True):
            raise RuntimeError("candidate is outside the selected run directory")
    return audit


def _read_curves(path: Path) -> dict[str, list[float]]:
    path = _regular_file(path, require_tmp=True)
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != ["time_s", "reactor_W", "turbine_W", "compressor_W"]:
            raise RuntimeError("curve CSV schema mismatch")
        rows = list(reader)
    if len(rows) < 2:
        raise RuntimeError("curve CSV needs at least two samples")
    output = {key: [] for key in reader.fieldnames}
    try:
        for row in rows:
            for key in output:
                output[key].append(float(row[key]))
    except (TypeError, ValueError) as exc:
        raise RuntimeError("curve CSV contains nonnumeric values") from exc
    flat = [value for values in output.values() for value in values]
    if (any(not math.isfinite(value) for value in flat) or
            any(right <= left for left, right in zip(output["time_s"], output["time_s"][1:]))):
        raise RuntimeError("curve CSV values/time vector are invalid")
    return output


def _interpolate(times: list[float], values: list[float], query: float) -> float:
    index = bisect_left(times, query)
    if index < len(times) and times[index] == query:
        return values[index]
    if index == 0 or index == len(times):
        raise RuntimeError("curve does not cover a paper comparison time")
    left, right = times[index - 1], times[index]
    fraction = (query - left) / (right - left)
    return values[index - 1] + fraction * (values[index] - values[index - 1])


def _metrics(times: list[float], values: list[float]) -> dict[str, object]:
    high, low = max(values), min(values)
    high_i, low_i = values.index(high), values.index(low)
    start = values[0]
    return {"units": "W", "samples": len(values), "start_W": start,
            "end_W": values[-1], "peak_to_peak_W": high - low,
            "peak_W": high, "peak_time_s": times[high_i],
            "peak_direction": "rise" if high > start else "flat",
            "valley_W": low, "valley_time_s": times[low_i],
            "valley_direction": "fall" if low < start else "flat"}


def _paper_comparison(times: list[float], values: list[float],
                      points: list[tuple[float, float, float]]) -> dict[str, object]:
    model = [_interpolate(times, values, point[0]) / 1000.0 for point in points]
    errors = [actual - point[1] for actual, point in zip(model, points)]
    squares = [error * error for error in errors]
    model_points = [(point[0], actual, point[2]) for point, actual in zip(points, model)]
    return {"paper_points": len(points), "rmse_kW": math.sqrt(sum(squares) / len(squares)),
            "max_abs_error_kW": max(abs(error) for error in errors),
            "start_error_kW": errors[0], "end_error_kW": errors[-1],
            "squared_error_contribution_kW2": sum(squares),
            "peak_time_s": times[values.index(max(values))],
            "valley_time_s": times[values.index(min(values))],
            "paper_direction_sequence": direction_sequence(points),
            "candidate_direction_sequence": direction_sequence(model_points),
            "direction_sequence_match": direction_sequence(points) == direction_sequence(model_points)}


def _reference_change(candidate_t: list[float], candidate: list[float],
                      reference_t: list[float], reference: list[float]) -> dict[str, object]:
    reference_at_candidate = [_interpolate(reference_t, reference, time)
                              for time in candidate_t]
    delta = [left - right for left, right in zip(candidate, reference_at_candidate)]
    candidate_p2p = max(candidate) - min(candidate)
    reference_p2p = max(reference) - min(reference)
    threshold = NONFLAT_RATIO * reference_p2p
    return {"rmse_change_W": math.sqrt(sum(value * value for value in delta) / len(delta)),
            "max_abs_change_W": max(abs(value) for value in delta),
            "start_change_W": delta[0], "end_change_W": delta[-1],
            "candidate_peak_to_peak_W": candidate_p2p,
            "reference_peak_to_peak_noise_W": reference_p2p,
            "nonflat_threshold_W": threshold,
            "nonflat": candidate_p2p > threshold}


def _artifact_locators(run_dir: Path, *, candidate_curves: Path,
                       reference_curves: Path, raw_result: Path,
                       include_analysis: bool,
                       include_run_status: bool = True) -> list[dict[str, object]]:
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    paths = {
        "candidate_slx": run_dir / "candidate.slx",
        "patch_audit": run_dir / "patch_audit.json",
        "raw_result": Path(raw_result),
        "candidate_curves": Path(candidate_curves),
        "reference_curves": Path(reference_curves),
    }
    if include_run_status:
        paths["run_status"] = run_dir / "run/run_status.json"
    if include_analysis:
        paths["analysis"] = run_dir / "analysis.json"
    output = []
    for identity, path in paths.items():
        file_path = _regular_file(path, require_tmp=True)
        output.append({"identity": identity,
                       "repository_relative_path": file_path.relative_to(ROOT).as_posix(),
                       "absolute_path": str(file_path), "sha256": _hash(file_path.read_bytes()),
                       "bytes": file_path.stat().st_size,
                       "storage": "external_tmp_not_copied"})
    return output


def _failure_artifact_locators(run_dir: Path, *, include_analysis: bool) -> list[dict[str, object]]:
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    paths = {
        "candidate_slx": run_dir / "candidate.slx",
        "patch_audit": run_dir / "patch_audit.json",
        "invocation_failure_status": run_dir / "run/invocation_failure.json",
    }
    if include_analysis:
        paths["analysis"] = run_dir / "analysis.json"
    output = []
    for identity, path in paths.items():
        file_path = _regular_file(path, require_tmp=True)
        output.append({"identity": identity,
                       "repository_relative_path": file_path.relative_to(ROOT).as_posix(),
                       "absolute_path": str(file_path), "sha256": _hash(file_path.read_bytes()),
                       "bytes": file_path.stat().st_size,
                       "storage": "external_tmp_not_copied"})
    return output


def _completed_artifact_locators(run_dir: Path, status: dict[str, object],
                                 *, include_analysis: bool) -> list[dict[str, object]]:
    """Rebuild truthful locators from the exact validated runner artifact set."""
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    records = status.get("artifacts")
    if not isinstance(records, list):
        raise RuntimeError("completed runner artifact records are missing")
    by_identity = {item["identity"]: item for item in records}
    paths = {identity: ROOT / item["repository_relative_path"]
             for identity, item in by_identity.items()}
    paths["run_status"] = run_dir / "run/run_status.json"
    if include_analysis:
        paths["analysis"] = run_dir / "analysis.json"
    order = ("candidate_slx", "patch_audit", "raw_result", "run_status",
             "candidate_curves", "reference_curves", "analysis")
    output = []
    for identity in order:
        if identity not in paths:
            continue
        file_path = _regular_file(paths[identity], require_tmp=True)
        output.append({"identity": identity,
                       "repository_relative_path": file_path.relative_to(ROOT).as_posix(),
                       "absolute_path": str(file_path), "sha256": _hash(file_path.read_bytes()),
                       "bytes": file_path.stat().st_size,
                       "storage": "external_tmp_not_copied"})
    return output


def synthetic_run_status(run_dir: Path, *, success: bool, candidate_curves: Path,
                         reference_curves: Path, raw_result: Path) -> dict[str, object]:
    audit = json.loads((Path(run_dir) / "patch_audit.json").read_text())
    artifacts = _artifact_locators(Path(run_dir), candidate_curves=candidate_curves,
                                   reference_curves=reference_curves,
                                   raw_result=raw_result, include_analysis=False,
                                   include_run_status=False)
    if not success:
        artifacts = [item for item in artifacts
                     if item["identity"] != "candidate_curves"]
    def snapshot(records: list[dict[str, object]]) -> list[dict[str, object]]:
        return [{"name": item["name"],
                 "repository_relative_path": item["repository_relative_path"],
                 "absolute_path": item["absolute_path"],
                 "sha256": item["before_sha256"]} for item in records]
    identity = {"source_sha256": SOURCE_SHA256,
                "candidate_sha256": audit["candidate_sha256"],
                "runtime_dependencies": snapshot(audit["runtime_dependencies"]),
                "mat_files": snapshot(audit["mat_files"]),
                "property_files": snapshot(audit["property_files"]),
                "protected_files": snapshot(audit["protected_files"])}
    return {"run_schema": "steady53_fig519_reactor_ic_counterfactual_run_v1",
            "experiment_status": "completed_success" if success else "completed_model_failure",
            "started_at_utc": "2026-08-31T00:00:00.000Z",
            "completed_at_utc": "2026-08-31T00:01:00.000Z",
            "run_steady53_case_call_count": 1, "retry_count": 0,
            "rerun_forbidden": True, "candidate_success": success,
            "candidate_final_time_s": 500.0 if success else None,
            "candidate_error_id": "" if success else "synthetic:modelFailure",
            "candidate_error_report": "", "runner_exception_id": "",
            "runner_exception_report": "", "identity_unchanged": True,
            "identity_before": identity, "identity_after": identity,
            "artifacts": artifacts, "paper_reproduced": False,
            "author_initial_state_identified": False, "formal_promotion": False}


def _validate_run_status(status: object, run_dir: Path,
                         audit: dict[str, object]) -> dict[str, object]:
    if not isinstance(status, dict):
        raise RuntimeError("run status must be an object")
    fixed = {"run_schema": "steady53_fig519_reactor_ic_counterfactual_run_v1",
             "run_steady53_case_call_count": 1, "retry_count": 0,
             "rerun_forbidden": True, "identity_unchanged": True,
             "paper_reproduced": False, "author_initial_state_identified": False,
             "formal_promotion": False}
    for key, value in fixed.items():
        if status.get(key) != value:
            raise RuntimeError(f"run status fixed field mismatch: {key}")
    if status.get("experiment_status") not in {
        "completed_success", "completed_model_failure", "completed_incomplete_output",
        "runner_or_hash_gate_failed"}:
        raise RuntimeError("run status enum is invalid")
    if status.get("identity_before") != status.get("identity_after"):
        raise RuntimeError("before/after run identities differ")
    identities = status["identity_before"]
    def expected_snapshot(records: object) -> list[dict[str, object]]:
        if not isinstance(records, list):
            raise RuntimeError("patch identity records are malformed")
        return [{"name": item["name"],
                 "repository_relative_path": item["repository_relative_path"],
                 "absolute_path": item["absolute_path"],
                 "sha256": item["before_sha256"]} for item in records]
    expected_identities = {
        "source_sha256": SOURCE_SHA256,
        "candidate_sha256": audit["candidate_sha256"],
        "runtime_dependencies": expected_snapshot(audit["runtime_dependencies"]),
        "mat_files": expected_snapshot(audit["mat_files"]),
        "property_files": expected_snapshot(audit["property_files"]),
        "protected_files": expected_snapshot(audit["protected_files"]),
    }
    if identities != expected_identities:
        raise RuntimeError("run identity snapshot conflicts with patch audit")
    # The runner locators deliberately exclude run_status (self hash) and analysis.
    records = status.get("artifacts")
    if not isinstance(records, list):
        raise RuntimeError("run artifact locators are missing")
    indexed = {item.get("identity"): item for item in records if isinstance(item, dict)}
    required = {"candidate_slx", "patch_audit", "raw_result", "reference_curves"}
    if status.get("experiment_status") in {
            "completed_success", "completed_incomplete_output"}:
        required.add("candidate_curves")
    if len(records) != len(indexed) or set(indexed) != required:
        raise RuntimeError("run artifact locator set is not exact")
    for identity, item in indexed.items():
        path = _regular_file(ROOT / item["repository_relative_path"], require_tmp=True)
        if (path != Path(item["absolute_path"]) or item.get("storage") != "external_tmp_not_copied" or
                item.get("sha256") != _hash(path.read_bytes()) or
                item.get("bytes") != path.stat().st_size):
            raise RuntimeError(f"run artifact locator mismatch: {identity}")
        if run_dir not in path.parents and path != run_dir:
            raise RuntimeError("run artifact escaped its run directory")
    return status


def _validate_invocation_failure(failure: object, run_dir: Path,
                                 audit: dict[str, object]) -> dict[str, object]:
    """Validate the immutable evidence from the consumed pre-simulation attempt."""
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    failure_path = _regular_file(run_dir / "run/invocation_failure.json", require_tmp=True)
    if _hash(failure_path.read_bytes()) != INVOCATION_FAILURE_SHA256:
        raise RuntimeError("pre-simulation invocation evidence hash changed")
    if not isinstance(failure, dict):
        raise RuntimeError("pre-simulation invocation evidence must be an object")
    fixed = {
        "failure_schema": "steady53_fig519_reactor_ic_pre_simulation_failure_v1",
        "failure_stub": True,
        "not_raw_simulation_output": True,
        "formal_command_invocation_count": 1,
        "run_steady53_case_call_count": 0,
        "retry_count": 0,
        "rerun_forbidden_without_new_human_approval": True,
        "process_exit_code": 1,
        "command": EXPECTED_FORMAL_COMMAND,
        "run_directory_created_local_time": "2026-09-01T00:06:56+08:00",
        "command_completion_time": "not captured by the yielded PTY result",
        "experiment_status": "pre_call_wrapper_failure",
        "gate_failure_class": "pre_simulation_infrastructure",
        "error_id": "MATLAB:badpermission_mx",
        "error_report": EXPECTED_FAILURE_REPORT,
        "failure_point": "after run directory creation and before experiment_started.json creation",
        "attempted_runner_repository_path": "tests/run_fig519_reactor_ic_counterfactual.m",
        "attempted_runner_sha256": ATTEMPTED_RUNNER_SHA256,
        "attempted_runner_line": 'file = fopen(filePath, "x", "n", "UTF-8");',
        "candidate_repository_path": "tmp/fig519_reactor_ic_20260831_A1/candidate.slx",
        "candidate_sha256": audit["candidate_sha256"],
        "patch_audit_repository_path": "tmp/fig519_reactor_ic_20260831_A1/patch_audit.json",
        "source_repository_path": SOURCE_PATH.relative_to(ROOT).as_posix(),
        "source_sha256": SOURCE_SHA256,
        "raw_simulation_output": None,
        "candidate_curve_output": None,
        "conclusion": "numerical_or_physical_gate_failed",
        "falsification_question_answered": False,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    for key, expected in fixed.items():
        if failure.get(key) != expected:
            raise RuntimeError(f"pre-simulation evidence fixed field mismatch: {key}")
    if failure.get("patch_audit_sha256") != _hash(
            _regular_file(run_dir / "patch_audit.json", require_tmp=True).read_bytes()):
        raise RuntimeError("failure evidence patch audit hash mismatch")
    candidate = _regular_file(run_dir / "candidate.slx", require_tmp=True)
    if _hash(candidate.read_bytes()) != audit["candidate_sha256"]:
        raise RuntimeError("failure evidence candidate hash mismatch")
    if _hash(_regular_file(SOURCE_PATH).read_bytes()) != SOURCE_SHA256:
        raise RuntimeError("failure evidence source hash mismatch")
    expected_state = {"exists": True, "is_directory": True,
                      "is_symlink": False, "entries": []}
    if failure.get("run_directory_state_at_failure") != expected_state:
        raise RuntimeError("recorded failure-time run directory state is invalid")
    note = failure.get("enum_semantic_note")
    if (not isinstance(note, str) or "broader" not in note or
            "pre_simulation_infrastructure" not in note or
            "no numerical integration" not in note):
        raise RuntimeError("failure enum semantic qualification is missing")
    id_evidence = failure.get("error_id_evidence")
    if (not isinstance(id_evidence, str) or "no-model probe" not in id_evidence or
            "MATLAB:badpermission_mx" not in id_evidence):
        raise RuntimeError("failure error-ID provenance is missing")
    run_path = _safe_under_repo(run_dir / "run", require_exists=True, require_tmp=True)
    if not run_path.is_dir() or run_path.is_symlink():
        raise RuntimeError("failure evidence run path is unsafe")
    allowed = {"invocation_failure.json"}
    if {entry.name for entry in run_path.iterdir()} != allowed:
        raise RuntimeError("pre-simulation run path contains unapproved or fabricated output")
    for forbidden in ("experiment_started.json", "run_status.json", "raw_result.mat",
                      "candidate_curves.csv", "reference_curves.csv"):
        if os.path.lexists(run_path / forbidden):
            raise RuntimeError(f"pre-simulation failure cannot contain {forbidden}")
    current_runner = _regular_file(ROOT / "tests/run_fig519_reactor_ic_counterfactual.m")
    if _hash(current_runner.read_bytes()) == ATTEMPTED_RUNNER_SHA256:
        raise RuntimeError("runner compatibility fix has not been applied")
    return failure


def analyze(run_dir: Path) -> dict[str, object]:
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    if not run_dir.is_dir():
        raise RuntimeError("run directory is missing")
    audit = validate_patch_audit(json.loads((run_dir / "patch_audit.json").read_text()),
                                 run_dir=run_dir)
    status_path = run_dir / "run/run_status.json"
    failure_path = run_dir / "run/invocation_failure.json"
    has_status, has_failure = os.path.lexists(status_path), os.path.lexists(failure_path)
    if has_status == has_failure:
        raise RuntimeError("exactly one run status or pre-simulation failure record is required")
    pre_simulation_failure = has_failure
    if pre_simulation_failure:
        status = _validate_invocation_failure(json.loads(failure_path.read_text()),
                                              run_dir, audit)
        numerical_gate = False
    else:
        status = _validate_run_status(json.loads(status_path.read_text()), run_dir, audit)
        numerical_gate = (status["experiment_status"] == "completed_success" and
                          status["candidate_success"] is True and
                          status["candidate_final_time_s"] == 500)
    curves: dict[str, dict[str, object]] = {}
    direction_panels: dict[str, dict[str, object]] = {}
    paper_points = _paper_points(OUTPUT / "paper_points.csv")
    if numerical_gate:
        candidate = _read_curves(run_dir / "run/candidate_curves.csv")
        reference = _read_curves(run_dir / "run/reference_curves.csv")
        ct, rt = candidate["time_s"], reference["time_s"]
        candidate_signals = {
            "reactor": candidate["reactor_W"], "turbine": candidate["turbine_W"],
            "compressor": candidate["compressor_W"],
            "electrical_paper_eta": [PAPER_ETA * (a - b) for a, b in
                                     zip(candidate["turbine_W"], candidate["compressor_W"])],
            "electrical_historical_metric": [HISTORICAL_ETA * (a - b) for a, b in
                                              zip(candidate["turbine_W"], candidate["compressor_W"])],
        }
        reference_signals = {
            "reactor": reference["reactor_W"], "turbine": reference["turbine_W"],
            "compressor": reference["compressor_W"],
            "electrical_paper_eta": [PAPER_ETA * (a - b) for a, b in
                                     zip(reference["turbine_W"], reference["compressor_W"])],
            "electrical_historical_metric": [HISTORICAL_ETA * (a - b) for a, b in
                                              zip(reference["turbine_W"], reference["compressor_W"])],
        }
        panel_map = {"reactor": "a", "turbine": "b", "compressor": "c",
                     "electrical_paper_eta": "d", "electrical_historical_metric": "d"}
        for name, values in candidate_signals.items():
            comparison = _paper_comparison(ct, values, paper_points[panel_map[name]])
            curves[name] = {"candidate_metrics": _metrics(ct, values),
                            "paper_comparison": comparison,
                            "reference_change": _reference_change(
                                ct, values, rt, reference_signals[name])}
            if name != "electrical_historical_metric":
                direction_panels[panel_map[name]] = {
                    "signal": name,
                    "paper_sequence": comparison["paper_direction_sequence"],
                    "candidate_sequence": comparison["candidate_direction_sequence"],
                    "match": comparison["direction_sequence_match"],
                }
        all_directions = len(direction_panels) == 4 and all(
            item["match"] for item in direction_panels.values())
        nonflat = {name: curves[name]["reference_change"]["nonflat"] for name in
                   ("reactor", "turbine", "compressor", "electrical_paper_eta")}
        all_nonflat = all(nonflat.values())
        conclusion = ("reactor_ic_alone_not_falsified_but_not_validated"
                      if all_directions and all_nonflat else "reactor_ic_alone_falsified")
    else:
        all_directions = False
        nonflat = ({} if pre_simulation_failure else
                   {name: False for name in
                    ("reactor", "turbine", "compressor", "electrical_paper_eta")})
        all_nonflat = False
        conclusion = "numerical_or_physical_gate_failed"
    gate_failure_class = ("pre_simulation_infrastructure" if pre_simulation_failure else
                          (None if numerical_gate else status["experiment_status"]))
    result = {
        "analysis_schema": "steady53_fig519_reactor_ic_counterfactual_analysis_v1",
        "counterfactual_question": audit["counterfactual_question"],
        "candidate_value_identity": CANDIDATE_VALUE_IDENTITY,
        "candidate_value_W": audit["candidate_value_W"],
        "circular_reproduction_counterfactual": True,
        "numerical_or_physical_gate_passed": numerical_gate,
        "gate_failure_class": gate_failure_class,
        "gate_failure_enum_semantic_note": (status["enum_semantic_note"]
                                               if pre_simulation_failure else None),
        "falsification_question_answered": numerical_gate,
        "formal_command_invocation_count": (status["formal_command_invocation_count"]
                                                if pre_simulation_failure else 1),
        "run_steady53_case_call_count": status["run_steady53_case_call_count"],
        "retry_count": status["retry_count"],
        "attempted_runner_sha256": (status["attempted_runner_sha256"]
                                       if pre_simulation_failure else None),
        "post_fix_runner_sha256": (_hash(_regular_file(
            ROOT / "tests/run_fig519_reactor_ic_counterfactual.m").read_bytes())
            if pre_simulation_failure else None),
        "post_fix_runner_executed_in_formal_attempt": False,
        "direction_rule": DIRECTION_RULE,
        "nonflat_rule": {"formula": "candidate peak-to-peak > ratio * unmodified reference peak-to-peak noise",
                         "ratio": NONFLAT_RATIO, "declared_before_candidate_result": True},
        "curves": curves,
        "direction_gate": {"panels": direction_panels,
                           "all_four_panels_match": all_directions},
        "nonflat_gate": {"signals": nonflat, "all_required_nonflat": all_nonflat},
        "conclusion": conclusion, "paper_reproduced": False,
        "author_initial_state_identified": False, "formal_promotion": False,
    }
    validate_analysis(result)
    return result


def _finite_tree(value: object, path: str = "root") -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise RuntimeError(f"nonfinite number in {path}")
    if isinstance(value, dict):
        for key, child in value.items():
            _finite_tree(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _finite_tree(child, f"{path}[{index}]")


def validate_analysis(result: object) -> dict[str, object]:
    if not isinstance(result, dict):
        raise RuntimeError("analysis must be an object")
    if (result.get("analysis_schema") != "steady53_fig519_reactor_ic_counterfactual_analysis_v1" or
            result.get("conclusion") not in CONCLUSIONS or
            result.get("paper_reproduced") is not False or
            result.get("author_initial_state_identified") is not False or
            result.get("formal_promotion") is not False or
            result.get("candidate_value_identity") != CANDIDATE_VALUE_IDENTITY or
            result.get("direction_rule") != DIRECTION_RULE or
            result.get("nonflat_rule", {}).get("ratio") != NONFLAT_RATIO):
        raise RuntimeError("analysis fixed contract mismatch")
    if result["numerical_or_physical_gate_passed"]:
        if set(result.get("curves", {})) != {"reactor", "turbine", "compressor",
                                                 "electrical_paper_eta",
                                                 "electrical_historical_metric"}:
            raise RuntimeError("analysis must contain exactly five curves")
        if set(result.get("direction_gate", {}).get("panels", {})) != set("abcd"):
            raise RuntimeError("analysis must check all four paper panels")
        if result.get("falsification_question_answered") is not True:
            raise RuntimeError("successful gate must answer the falsification question")
    elif result["conclusion"] != "numerical_or_physical_gate_failed":
        raise RuntimeError("failed numerical gate has the wrong conclusion")
    if result.get("gate_failure_class") == "pre_simulation_infrastructure":
        if (result.get("falsification_question_answered") is not False or
                result.get("curves") != {} or
                result.get("direction_gate") != {"panels": {},
                                                  "all_four_panels_match": False} or
                result.get("nonflat_gate") != {"signals": {},
                                                "all_required_nonflat": False} or
                result.get("formal_command_invocation_count") != 1 or
                result.get("run_steady53_case_call_count") != 0 or
                result.get("retry_count") != 0 or
                result.get("attempted_runner_sha256") != ATTEMPTED_RUNNER_SHA256 or
                not isinstance(result.get("post_fix_runner_sha256"), str) or
                result.get("post_fix_runner_sha256") == ATTEMPTED_RUNNER_SHA256 or
                result.get("post_fix_runner_executed_in_formal_attempt") is not False):
            raise RuntimeError("pre-simulation failure analysis contract mismatch")
        note = result.get("gate_failure_enum_semantic_note")
        if not isinstance(note, str) or "broader" not in note:
            raise RuntimeError("pre-simulation enum qualification is missing")
    _finite_tree(result)
    return result


def _ensure_analysis_file(run_dir: Path, result: dict[str, object]) -> Path:
    path = run_dir / "analysis.json"
    payload = _json_bytes(result)
    if os.path.lexists(path):
        if path.is_symlink() or not path.is_file() or path.read_bytes() != payload:
            raise RuntimeError("existing analysis.json conflicts with recomputation")
    else:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.write(fd, payload)
            os.fsync(fd)
        finally:
            os.close(fd)
    return path


def _summary(run_dir: Path, result: dict[str, object]) -> dict[str, object]:
    audit = validate_patch_audit(json.loads((run_dir / "patch_audit.json").read_text()),
                                 run_dir=run_dir)
    failure_path = run_dir / "run/invocation_failure.json"
    if os.path.lexists(failure_path):
        status = _validate_invocation_failure(json.loads(failure_path.read_text()),
                                              run_dir, audit)
        locators = _failure_artifact_locators(run_dir, include_analysis=True)
        evidence_kind = "pre_simulation_failure_stub_not_raw_output"
        storage_note = ("candidate/patch/failure status/analysis remain in tmp and are not "
                        "copied to durable publication; no raw or curve output exists")
    else:
        status = _validate_run_status(json.loads((run_dir / "run/run_status.json").read_text()),
                                      run_dir, audit)
        locators = _completed_artifact_locators(run_dir, status, include_analysis=True)
        evidence_kind = "completed_runner_status_and_raw_output"
        storage_note = "candidate/raw/CSV/run audit remain in tmp and are not copied to durable publication"
    return {"summary_schema": "steady53_fig519_reactor_ic_counterfactual_summary_v1",
            "patch_audit": audit, "analysis": result,
            "experiment_evidence_kind": evidence_kind,
            "run_status": status, "external_artifacts": locators,
            "external_storage_note": storage_note,
            "paper_reproduced": False, "author_initial_state_identified": False,
            "formal_promotion": False}


def _verified_a2_execution(capture: Path,
                           run_dir: Path = A2_RUN_DIR) -> dict[str, object]:
    # Lazy import avoids a module cycle: the preflight/archive module reuses
    # this analyzer's exact-one-change and completed-run validators.
    try:
        from tests import prepare_fig519_reactor_ic_a2 as a2_archive
    except ModuleNotFoundError:  # pragma: no cover - direct CLI path
        import prepare_fig519_reactor_ic_a2 as a2_archive
    return a2_archive.verify_execution(capture, run_dir)


def _history_summary(output: Path, run_dir: Path,
                     result: dict[str, object],
                     execution_capture: Path) -> dict[str, object]:
    if run_dir != A2_RUN_DIR.resolve():
        raise RuntimeError("only the fixed A2 attempt may append Task 7 history")
    predecessor_path = _regular_file(output / SUMMARY_NAME)
    predecessor_payload = predecessor_path.read_bytes()
    predecessor = json.loads(predecessor_payload)
    if predecessor.get("summary_schema") == (
            "steady53_fig519_reactor_ic_counterfactual_history_v2"):
        attempts = predecessor.get("attempts")
        if (not isinstance(attempts, list) or len(attempts) != 2 or
                attempts[0].get("attempt_id") != "20260831_A1"):
            raise RuntimeError("existing Task 7 history is malformed")
        a1_entry = attempts[0]
    else:
        if (_hash(predecessor_payload) != A1_DURABLE_SUMMARY_SHA256 or
                predecessor.get("summary_schema") !=
                "steady53_fig519_reactor_ic_counterfactual_summary_v1"):
            raise RuntimeError("A2 append requires the immutable A1 durable summary")
        validate_durable_summary(predecessor, run_dir=A1_RUN_DIR)
        a1_entry = {
            "attempt_id": "20260831_A1",
            "source_summary_sha256": _hash(predecessor_payload),
            "attempt_summary": predecessor,
        }
    if (a1_entry.get("source_summary_sha256") != A1_DURABLE_SUMMARY_SHA256 or
            _hash(_json_bytes(a1_entry.get("attempt_summary"))) !=
            A1_DURABLE_SUMMARY_SHA256):
        raise RuntimeError("A1 attempt was not preserved byte-for-byte canonically")
    execution = _verified_a2_execution(execution_capture, run_dir)
    a2_summary = _summary(run_dir, result)
    a2_entry = {
        "attempt_id": "20260901_A2",
        "execution_record_sha256": _hash(_json_bytes(execution)),
        "execution_record": execution,
        "attempt_summary": a2_summary,
    }
    history = {
        "summary_schema": "steady53_fig519_reactor_ic_counterfactual_history_v2",
        "history_mode": "append_only_attempts",
        "attempt_count": 2,
        "attempts": [a1_entry, a2_entry],
        "latest_attempt_id": "20260901_A2",
        "total_formal_command_invocation_count": 2,
        "total_run_steady53_case_call_count": 1,
        "total_retry_count": 0,
        "latest_scientific_conclusion": result["conclusion"],
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    validate_durable_summary(history, run_dir=run_dir,
                             execution_capture=execution_capture)
    return history


def _v1_external_rows(summary: dict[str, object]) -> list[tuple[str, dict[str, object]]]:
    """Return the original single-attempt locator set."""
    artifacts = summary.get("external_artifacts")
    if not isinstance(artifacts, list):
        raise RuntimeError("summary external artifacts are missing")
    by_identity = {item.get("identity"): item for item in artifacts if isinstance(item, dict)}
    if summary.get("experiment_evidence_kind") == "pre_simulation_failure_stub_not_raw_output":
        mapping = _FAILURE_EXTERNAL_IDENTITIES
        keys = FAILURE_EXTERNAL_ARTIFACT_KEYS
    else:
        status = summary.get("run_status")
        if not isinstance(status, dict) or not isinstance(status.get("artifacts"), list):
            raise RuntimeError("completed summary run artifact records are missing")
        expected_identities = {item.get("identity") for item in status["artifacts"]
                               if isinstance(item, dict)} | {"run_status", "analysis"}
        mapping = {key: identity for key, identity in _SUCCESS_EXTERNAL_IDENTITIES.items()
                   if identity in expected_identities}
        keys = tuple(key for key in SUCCESS_EXTERNAL_ARTIFACT_KEYS if key in mapping)
    if set(by_identity) != set(mapping.values()):
        raise RuntimeError("summary external artifact identities are incomplete")
    rows = []
    for key in keys:
        item = by_identity[mapping[key]]
        path = _regular_file(ROOT / item["repository_relative_path"], require_tmp=True)
        if (str(path) != item.get("absolute_path") or _hash(path.read_bytes()) != item.get("sha256") or
                path.stat().st_size != item.get("bytes") or
                item.get("storage") != "external_tmp_not_copied"):
            raise RuntimeError(f"summary locator mismatch: {key}")
        rows.append((key, item))
    return rows


def _external_rows(summary: dict[str, object]) -> list[tuple[str, dict[str, object]]]:
    if summary.get("summary_schema") != (
            "steady53_fig519_reactor_ic_counterfactual_history_v2"):
        return _v1_external_rows(summary)
    attempts = summary["attempts"]
    a1_rows = _v1_external_rows(attempts[0]["attempt_summary"])
    a2_rows = _v1_external_rows(attempts[1]["attempt_summary"])
    rows: list[tuple[str, dict[str, object]]] = []
    for _, item in a1_rows:
        rows.append((A1_HISTORY_EXTERNAL_KEYS[item["identity"]], item))
    for _, item in a2_rows:
        rows.append((A2_HISTORY_EXTERNAL_KEYS[item["identity"]], item))
    execution = attempts[1]["execution_record"]
    capture_items = {item["name"]: item for item in execution["capture_artifacts"]}
    capture_dir = Path(execution["capture_artifacts"][0]["absolute_path"]).parent
    record_path = _regular_file(capture_dir / "execution_record.json", require_tmp=True)
    record_item = {
        "identity": "execution_record",
        "repository_relative_path": record_path.relative_to(ROOT).as_posix(),
        "absolute_path": str(record_path),
        "bytes": record_path.stat().st_size,
        "sha256": _hash(record_path.read_bytes()),
        "storage": "external_tmp_not_copied",
    }
    capture_items["execution_record.json"] = record_item
    if set(capture_items) != set(A2_CAPTURE_EXTERNAL_KEYS):
        raise RuntimeError("A2 execution capture locator set is incomplete")
    for name, key in A2_CAPTURE_EXTERNAL_KEYS.items():
        item = dict(capture_items[name])
        item.setdefault("identity", f"execution_capture/{name}")
        path = _regular_file(ROOT / item["repository_relative_path"], require_tmp=True)
        if (str(path) != item.get("absolute_path") or
                _hash(path.read_bytes()) != item.get("sha256") or
                path.stat().st_size != item.get("bytes") or
                item.get("storage") != "external_tmp_not_copied"):
            raise RuntimeError(f"A2 capture locator mismatch: {name}")
        rows.append((key, item))
    if len({key for key, _ in rows}) != len(rows):
        raise RuntimeError("attempt history external locator collision")
    return rows


def _manifest_bytes(output: Path, summary_payload: bytes,
                    summary: dict[str, object]) -> bytes:
    init = json.loads((output / "initialization_audit.json").read_text())
    baseline._validate_initialization_audit(init)
    raw = baseline._validate_raw_reference(init)
    entries = {name: (output / name).read_bytes() for name in paper_module.ARTIFACT_NAMES}
    entries.update({f"{paper_module.BASELINE_LAYER_DIR}/{name}":
                    (output / paper_module.BASELINE_LAYER_DIR / name).read_bytes()
                    for name in paper_module.BASELINE_LAYER_NAMES})
    entries["baseline_metrics.json"] = (output / "baseline_metrics.json").read_bytes()
    entries["signal_contract.json"] = (output / "signal_contract.json").read_bytes()
    entries[baseline.INITIALIZATION_AUDIT_NAME] = (output / baseline.INITIALIZATION_AUDIT_NAME).read_bytes()
    entries[SUMMARY_NAME] = summary_payload
    roles = baseline._roles() | {
        SUMMARY_NAME: ("generated single-variable counterfactual summary",
                       "reactor-IC-only-falsification;no-formal-promotion")}
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(("path", "bytes", "sha256", "role", "identity", "storage",
                     "repository_relative_path", "absolute_path"))
    for name in sorted(entries):
        payload = entries[name]
        role, identity = roles[name]
        target = output / name
        writer.writerow((name, len(payload), _hash(payload), role, identity, "durable",
                         target.relative_to(ROOT).as_posix(), str(target)))
    for key, item in _external_rows(summary):
        writer.writerow((key, item["bytes"], item["sha256"],
                         "external Task 7 evidence locator",
                         f"{item['identity']};not-copied-to-durable-publication",
                         "external_tmp_not_copied", item["repository_relative_path"],
                         item["absolute_path"]))
    # Keep the Task 6 raw-reference locator as the final manifest row so all
    # predecessor readers that intentionally inspect that sentinel stay valid.
    writer.writerow(("@external/raw_reference.mat", raw["bytes"], raw["sha256"],
                     "external raw evidence locator",
                     "unmodified-500s-reference;not-copied-to-durable-publication",
                     "external_tmp_not_copied", raw["repository_relative_path"],
                     raw["absolute_path"]))
    return stream.getvalue().encode()


def rebuild_task6_manifest(output: Path) -> None:
    """Test helper restoring the exact Task 6 predecessor manifest."""
    output = _safe_under_repo(Path(output), require_exists=True)
    if os.path.lexists(output / SUMMARY_NAME):
        raise RuntimeError("cannot rebuild Task 6 manifest while Task 7 summary exists")
    durable, generated = baseline._expected_durable(output)
    payload = baseline._unified_manifest(output, durable, generated)
    target = output / "manifest.csv"
    staging = output / ".task7-test-manifest"
    staging.write_bytes(payload)
    os.replace(staging, target)


def transaction_dir(output: Path) -> Path:
    return output.parent / (output.name + ".task7-transaction")


def _tombstone(output: Path, payloads: dict[str, bytes]) -> Path:
    return output.parent / (output.name + ".task7-cleanup-" +
                            _hash(_record(payloads))[:20])


def _record(payloads: dict[str, bytes]) -> bytes:
    return _json_bytes({"version": TRANSACTION_VERSION, "state": "prepared",
                        "targets": [{"path": name, "bytes": len(payloads[name]),
                                     "sha256": _hash(payloads[name])} for name in TARGETS]})


def _publication_boundary(point: str) -> None:
    del point


def _write_exclusive(path: Path, payload: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@contextmanager
def _lock(output: Path):
    fd = os.open(output, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _planned(run_dir: Path, output: Path,
             execution_capture: Path | None = None) -> tuple[dict[str, bytes], dict[str, object]]:
    result = analyze(run_dir)
    _ensure_analysis_file(run_dir, result)
    if os.path.lexists(output / SUMMARY_NAME):
        if run_dir == A2_RUN_DIR.resolve():
            summary = _history_summary(
                output, run_dir, result,
                _safe_under_repo(execution_capture or A2_EXECUTION_CAPTURE,
                                 require_exists=True, require_tmp=True),
            )
        else:
            existing = json.loads(_regular_file(output / SUMMARY_NAME).read_text())
            if existing != _summary(run_dir, result):
                raise RuntimeError("existing Task 7 summary is not idempotent")
            summary = existing
    else:
        summary = _summary(run_dir, result)
    summary_payload = _json_bytes(summary)
    return {SUMMARY_NAME: summary_payload,
            "manifest.csv": _manifest_bytes(output, summary_payload, summary)}, summary


def _check_file(path: Path, payload: bytes, label: str) -> None:
    if path.is_symlink() or not path.is_file() or path.read_bytes() != payload:
        raise RuntimeError(f"Task 7 transaction conflict: {label}")


def _task6_manifest(output: Path) -> bytes:
    audit = json.loads((output / baseline.INITIALIZATION_AUDIT_NAME).read_text())
    baseline._validate_initialization_audit(audit)
    entries = {name: (output / name).read_bytes() for name in paper_module.ARTIFACT_NAMES}
    entries.update({f"{paper_module.BASELINE_LAYER_DIR}/{name}":
                    (output / paper_module.BASELINE_LAYER_DIR / name).read_bytes()
                    for name in paper_module.BASELINE_LAYER_NAMES})
    entries["baseline_metrics.json"] = (output / "baseline_metrics.json").read_bytes()
    entries["signal_contract.json"] = (output / "signal_contract.json").read_bytes()
    entries[baseline.INITIALIZATION_AUDIT_NAME] = (
        output / baseline.INITIALIZATION_AUDIT_NAME).read_bytes()
    return baseline.manifest_bytes_with_external(output, entries, baseline._roles(), audit)


def _history_predecessors(output: Path,
                          payloads: dict[str, bytes]) -> dict[str, bytes]:
    planned = json.loads(payloads[SUMMARY_NAME])
    if planned.get("summary_schema") != (
            "steady53_fig519_reactor_ic_counterfactual_history_v2"):
        return {"manifest.csv": _task6_manifest(output)}
    attempts = planned.get("attempts")
    if not isinstance(attempts, list) or len(attempts) != 2:
        raise RuntimeError("planned Task 7 history lacks its A1 predecessor")
    a1_summary = attempts[0].get("attempt_summary")
    a1_payload = _json_bytes(a1_summary)
    if _hash(a1_payload) != A1_DURABLE_SUMMARY_SHA256:
        raise RuntimeError("planned Task 7 history changed the A1 predecessor")
    return {
        SUMMARY_NAME: a1_payload,
        "manifest.csv": _manifest_bytes(output, a1_payload, a1_summary),
    }


def _target_state(output: Path, payloads: dict[str, bytes]) -> dict[str, str]:
    states = {}
    predecessors = _history_predecessors(output, payloads)
    for name in TARGETS:
        path = output / name
        if not os.path.lexists(path):
            if name != SUMMARY_NAME:
                raise RuntimeError("Task 7 manifest predecessor is missing")
            states[name] = "missing"
        elif path.is_symlink() or not path.is_file():
            raise RuntimeError(f"unsafe Task 7 target: {name}")
        elif path.read_bytes() == payloads[name]:
            states[name] = "expected"
        elif name in predecessors and path.read_bytes() == predecessors[name]:
            states[name] = "predecessor"
        else:
            raise RuntimeError(f"unregistered Task 7 target predecessor: {name}")
    return states


def _validate_txn(txn: Path, payloads: dict[str, bytes], output: Path) -> Path:
    if txn.is_symlink() or not txn.is_dir() or txn.stat().st_uid != os.geteuid() or txn.stat().st_mode & 0o077:
        raise RuntimeError("Task 7 transaction directory is unsafe")
    if {entry.name for entry in txn.iterdir()} != {"record.json", "payload"}:
        raise RuntimeError("Task 7 transaction entries are invalid")
    _check_file(txn / "record.json", _record(payloads), "record")
    root = txn / "payload"
    if root.is_symlink() or not root.is_dir() or {entry.name for entry in root.iterdir()} - set(TARGETS):
        raise RuntimeError("Task 7 transaction payload is unsafe")
    states = _target_state(output, payloads)
    for name in TARGETS:
        staged = root / name
        if os.path.lexists(staged):
            _check_file(staged, payloads[name], f"staged {name}")
        elif states[name] != "expected":
            raise RuntimeError(f"Task 7 transaction lost pending target: {name}")
    return root


def _birth(txn: Path, payloads: dict[str, bytes], output: Path) -> None:
    init = Path(tempfile.mkdtemp(prefix=txn.name.replace("transaction", "init") + "-",
                                 dir=txn.parent))
    os.chmod(init, 0o700)
    _write_exclusive(init / "record.json", _record(payloads))
    root = init / "payload"
    os.mkdir(root, 0o700)
    for name in TARGETS:
        _publication_boundary(f"{name}-stage-before")
        _write_exclusive(root / name, payloads[name])
        _publication_boundary(f"{name}-stage-after")
    _validate_txn(init, payloads, output)
    _fsync(root); _fsync(init)
    _publication_boundary("canonical-rename-before")
    if os.path.lexists(txn):
        raise RuntimeError("Task 7 canonical transaction appeared concurrently")
    os.rename(init, txn)
    _fsync(txn.parent)
    _publication_boundary("canonical-rename-after")


def _commit(output: Path, txn: Path, payloads: dict[str, bytes]) -> None:
    root = _validate_txn(txn, payloads, output)
    states = _target_state(output, payloads)
    _publication_boundary("summary-commit-before")
    if states[SUMMARY_NAME] == "missing":
        try:
            os.link(root / SUMMARY_NAME, output / SUMMARY_NAME, follow_symlinks=False)
        except FileExistsError:
            _check_file(output / SUMMARY_NAME, payloads[SUMMARY_NAME], "concurrent summary")
        _fsync(output)
    elif states[SUMMARY_NAME] == "predecessor":
        os.replace(root / SUMMARY_NAME, output / SUMMARY_NAME)
        os.link(output / SUMMARY_NAME, root / SUMMARY_NAME, follow_symlinks=False)
        _fsync(output)
    _publication_boundary("summary-commit-after")
    _publication_boundary("manifest-commit-before")
    if states["manifest.csv"] != "expected":
        os.replace(root / "manifest.csv", output / "manifest.csv")
        os.link(output / "manifest.csv", root / "manifest.csv", follow_symlinks=False)
        _fsync(output)
    _publication_boundary("manifest-commit-after")


def _cleanup(txn: Path, payloads: dict[str, bytes], output: Path) -> None:
    _validate_txn(txn, payloads, output)
    if any(state != "expected" for state in _target_state(output, payloads).values()):
        raise RuntimeError("refusing to clean incomplete Task 7 transaction")
    tomb = _tombstone(output, payloads)
    _publication_boundary("cleanup-tombstone-rename-before")
    if os.path.lexists(tomb):
        raise RuntimeError("Task 7 cleanup tombstone conflict")
    os.rename(txn, tomb)
    _fsync(tomb.parent)
    _publication_boundary("cleanup-tombstone-rename-after")
    root = tomb / "payload"
    for name in TARGETS:
        staged = root / name
        if os.path.lexists(staged):
            _check_file(staged, payloads[name], f"cleanup {name}")
            os.unlink(staged)
    os.rmdir(root)
    _check_file(tomb / "record.json", _record(payloads), "cleanup record")
    os.unlink(tomb / "record.json")
    os.rmdir(tomb)
    _fsync(tomb.parent)


def publish(run_dir: Path = DEFAULT_RUN_DIR, output: Path = OUTPUT,
            *, execution_capture: Path | None = None) -> None:
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    output = _safe_under_repo(Path(output), require_exists=True)
    if output.is_symlink() or not output.is_dir():
        raise RuntimeError("durable output directory is unsafe")
    payloads, _ = _planned(run_dir, output, execution_capture)
    with _lock(output):
        txn = transaction_dir(output)
        tomb = _tombstone(output, payloads)
        if os.path.lexists(tomb):
            raise RuntimeError("Task 7 cleanup tombstone requires audit")
        if not os.path.lexists(txn):
            try:
                verify_only(run_dir, output, execution_capture=execution_capture)
            except RuntimeError:
                pass
            else:
                return
            _birth(txn, payloads, output)
        _commit(output, txn, payloads)
        _cleanup(txn, payloads, output)
    verify_only(run_dir, output, execution_capture=execution_capture)


def validate_durable_summary(summary: object, run_dir: Path | None = None,
                             *, execution_capture: Path | None = None) -> dict[str, object]:
    if not isinstance(summary, dict):
        raise RuntimeError("Task 7 summary schema is invalid")
    if summary.get("summary_schema") == (
            "steady53_fig519_reactor_ic_counterfactual_history_v2"):
        if any(summary.get(key) is not False for key in
               ("paper_reproduced", "author_initial_state_identified", "formal_promotion")):
            raise RuntimeError("Task 7 history makes a forbidden promotion")
        attempts = summary.get("attempts")
        if (summary.get("history_mode") != "append_only_attempts" or
                summary.get("attempt_count") != 2 or not isinstance(attempts, list) or
                [item.get("attempt_id") for item in attempts] !=
                ["20260831_A1", "20260901_A2"] or
                summary.get("latest_attempt_id") != "20260901_A2" or
                summary.get("total_formal_command_invocation_count") != 2 or
                summary.get("total_run_steady53_case_call_count") != 1 or
                summary.get("total_retry_count") != 0):
            raise RuntimeError("Task 7 append-only attempt history is invalid")
        a1 = attempts[0]
        a1_summary = a1.get("attempt_summary")
        if (a1.get("source_summary_sha256") != A1_DURABLE_SUMMARY_SHA256 or
                _hash(_json_bytes(a1_summary)) != A1_DURABLE_SUMMARY_SHA256):
            raise RuntimeError("Task 7 A1 attempt history changed")
        validate_durable_summary(a1_summary, run_dir=A1_RUN_DIR)
        a2 = attempts[1]
        a2_summary = a2.get("attempt_summary")
        validate_durable_summary(a2_summary, run_dir=A2_RUN_DIR)
        capture = _safe_under_repo(execution_capture or A2_EXECUTION_CAPTURE,
                                   require_exists=True, require_tmp=True)
        execution = _verified_a2_execution(capture, A2_RUN_DIR)
        if (a2.get("execution_record") != execution or
                a2.get("execution_record_sha256") != _hash(_json_bytes(execution))):
            raise RuntimeError("Task 7 A2 execution record changed")
        analysis = a2_summary["analysis"]
        if (summary.get("latest_scientific_conclusion") != analysis["conclusion"] or
                analysis.get("falsification_question_answered") is not True):
            raise RuntimeError("Task 7 latest conclusion is not bound to A2")
        if run_dir is not None:
            selected = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
            if selected not in {A1_RUN_DIR.resolve(), A2_RUN_DIR.resolve()}:
                raise RuntimeError("Task 7 history verifier selected an unknown attempt")
        _external_rows(summary)
        return summary
    if summary.get("summary_schema") != "steady53_fig519_reactor_ic_counterfactual_summary_v1":
        raise RuntimeError("Task 7 summary schema is invalid")
    if any(summary.get(key) is not False for key in
           ("paper_reproduced", "author_initial_state_identified", "formal_promotion")):
        raise RuntimeError("Task 7 summary makes a forbidden promotion")
    audit = validate_patch_audit(summary.get("patch_audit"), run_dir=run_dir)
    analysis = validate_analysis(summary.get("analysis"))
    selected = run_dir or Path(audit["candidate_absolute_path"]).parent
    evidence_kind = summary.get("experiment_evidence_kind")
    if evidence_kind == "pre_simulation_failure_stub_not_raw_output":
        _validate_invocation_failure(summary.get("run_status"), selected, audit)
        if (analysis.get("gate_failure_class") != "pre_simulation_infrastructure" or
                analysis.get("falsification_question_answered") is not False):
            raise RuntimeError("failure summary and analysis disagree")
    elif evidence_kind == "completed_runner_status_and_raw_output":
        _validate_run_status(summary.get("run_status"), selected, audit)
    else:
        raise RuntimeError("Task 7 experiment evidence kind is invalid")
    _external_rows(summary)
    return summary


def expected_manifest_from_output(output: Path) -> bytes:
    summary_path = output / SUMMARY_NAME
    summary_payload = _regular_file(summary_path).read_bytes()
    try:
        summary = json.loads(summary_payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("durable Task 7 summary is malformed") from exc
    validate_durable_summary(summary)
    return _manifest_bytes(output, summary_payload, summary)


def verify_only(run_dir: Path = DEFAULT_RUN_DIR, output: Path = OUTPUT,
                *, execution_capture: Path | None = None) -> None:
    run_dir = _safe_under_repo(Path(run_dir), require_exists=True, require_tmp=True)
    output = _safe_under_repo(Path(output), require_exists=True)
    summary_path = _regular_file(output / SUMMARY_NAME)
    summary = json.loads(summary_path.read_text())
    validate_durable_summary(summary, run_dir=run_dir,
                             execution_capture=execution_capture)
    if summary.get("summary_schema") == (
            "steady53_fig519_reactor_ic_counterfactual_history_v2"):
        indexed = {item["attempt_id"]: item["attempt_summary"]
                   for item in summary["attempts"]}
        for attempt_id, attempt_dir in (("20260831_A1", A1_RUN_DIR),
                                        ("20260901_A2", A2_RUN_DIR)):
            recomputed = analyze(attempt_dir)
            if indexed[attempt_id]["analysis"] != recomputed:
                raise RuntimeError(f"durable {attempt_id} analysis differs from recomputation")
            analysis_path = _regular_file(attempt_dir / "analysis.json", require_tmp=True)
            if analysis_path.read_bytes() != _json_bytes(recomputed):
                raise RuntimeError(f"external {attempt_id} analysis differs from recomputation")
    else:
        recomputed = analyze(run_dir)
        if summary["analysis"] != recomputed:
            raise RuntimeError("durable analysis differs from recomputation")
        analysis_path = _regular_file(run_dir / "analysis.json", require_tmp=True)
        if analysis_path.read_bytes() != _json_bytes(recomputed):
            raise RuntimeError("external analysis JSON differs from recomputation")
    if _regular_file(output / "manifest.csv").read_bytes() != _manifest_bytes(
            output, summary_path.read_bytes(), summary):
        raise RuntimeError("Task 7 unified manifest mismatch")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", nargs="?", type=Path, default=DEFAULT_RUN_DIR)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    run_dir = args.run_dir if args.run_dir.is_absolute() else ROOT / args.run_dir
    if args.verify_only:
        verify_only(run_dir, OUTPUT)
        result = analyze(run_dir)
    else:
        publish(run_dir, OUTPUT)
        result = analyze(run_dir)
    print("FIG519_REACTOR_IC_COUNTERFACTUAL=" + result["conclusion"])


if __name__ == "__main__":
    main()
