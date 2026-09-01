#!/usr/bin/env python3
"""Offline analysis and transactional evidence publication for A3.

This module never starts MATLAB and never loads a Simulink model.  It accepts
only the frozen two-state/one-delta candidate audit, the one-shot run record,
captured CSV/raw bytes, and the contemporaneous execution capture.
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
from bisect import bisect_left
from contextlib import contextmanager
from decimal import Decimal
from itertools import groupby
from pathlib import Path
from types import MappingProxyType

try:
    from tests import fig519_ihx_r2_hexe_contract as contract
except ModuleNotFoundError:  # pragma: no cover - direct captured CLI execution
    import fig519_ihx_r2_hexe_contract as contract


ROOT = Path(__file__).resolve().parents[1]
INVOCATION_ROOT = Path.cwd().resolve()
FIG519_DIR = ROOT / "data/provenance/steady53/fig5_19"
PAPER_POINTS_PATH = FIG519_DIR / "paper_points.csv"
SIGNAL_CONTRACT_PATH = FIG519_DIR / "signal_contract.json"
INITIALIZATION_AUDIT_PATH = FIG519_DIR / "initialization_audit.json"
REACTOR_HISTORY = FIG519_DIR / "reactor_ic_counterfactual.json"
SOURCE_PATH = ROOT / "data/provenance/baselines/f8bcd83/final_steady_24a.slx"
MODEL_BASELINE_DIR = FIG519_DIR / "model_baseline"
RUNTIME_DIR = ROOT / "data/provenance/baselines/f8bcd83/runtime"
PROTECTED_MANIFEST_PATH = (
    ROOT / "data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv"
)

PAPER_POINTS_SHA256 = "e63607ad0f599c84fe6980ed26e05c91902b7928a53fabf5bf4a95a3de0098f2"
SIGNAL_CONTRACT_SHA256 = "de619fd27f0757dc88eb2c50e6da9eb282648735fab94b4015ebbcca430c5d05"
INITIALIZATION_AUDIT_SHA256 = "390c1d8e4c75ae70f697884d8a9397fd919c1d0791fcbaf9d9956815b569ae80"
REACTOR_HISTORY_SHA256 = "e1c2c1179dc7f4c7e7848f24f24141a3300e1809021d19be7d7c40b6cae690cd"
BASELINE_HASHES = MappingProxyType({
    "baseline_P_sw.csv": "288a9b031d31f8168517ea30d06f712d72c4d1dc31fd911f0a266aaa3023999f",
    "baseline_WT_sw.csv": "28b852e9b997af51a860905e53da096821ddfbdd310857d16e9df0761ca2ab23",
    "baseline_Wc_sw.csv": "f44a9bca2c006780f287e4f3a7199f63d26348cc18ad261d4ad89570b0e9ad5c",
})
RUNTIME_HASHES = MappingProxyType({
    "HeXe_property_simulink.m": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2",
    "Lithium_property_simulink.m": "666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f",
    "hexe_compressor_lookup.mat": "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579",
    "radiator_table.mat": "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304",
    "turbine_table1.mat": "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d",
    "turbine_table2.mat": "6ff94cce373b67a143e9a992ec693ef17a910440eb4218cdf796543ba48c8a38",
    "paper54_constants.m": "545e9b7653b4a47759e746e33a52a184e69c1455911929ce096d1a6eb6558345",
    "sys_param_rad_fixed.m": "bbdcf30dcd2fd7859092af0d85a79ed5dabc6da6c298f1d064ed11d612f30d5b",
    "start.m": "0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec",
})
FORMAL_NAMES = (
    "final_steady_24a.slx", "final_dynamic_24a.slx",
    "HeXe_property_simulink.m", "Lithium_property_simulink.m",
    "hexe_compressor_lookup.mat", "radiator_table.mat",
    "turbine_table1.mat", "turbine_table2.mat",
)

PAPER_ETA = 0.98
EXACT_FORMAL_COMMAND = (
    "python3 tmp/fig519_ihx_r2_hexe_20260901_A3_capture/"
    "repo_snapshot/tests/execute_fig519_ihx_r2_hexe_a3_once.py --execute"
)
A2_DIRECTION_RULE = MappingProxyType({
    "input": "successive fixed digitized/model samples in increasing time",
    "threshold": "panel_power_allowance_kW",
    "classification": "rise if delta>allowance; fall if delta<-allowance; otherwise flat",
    "flat_handling": "discard_before_compression",
    "compression": "collapse consecutive identical non-flat directions",
    "candidate_threshold_declared_before_experiment": True,
})
DIRECTION_RULE = A2_DIRECTION_RULE
NONFLAT_THRESHOLDS_W = contract.NONFLAT_THRESHOLDS_W
CONCLUSIONS = frozenset({
    "ihx_r2_hexe_shift_alone_falsified",
    "ihx_r2_hexe_shift_alone_not_falsified_but_not_validated",
    "numerical_or_physical_gate_failed",
})
PROMOTION = MappingProxyType(dict(contract.promotion_flags()))

CANDIDATE_COLUMNS = (
    "time_s", "reactor_W", "turbine_W", "compressor_W",
    "ihx_r2_average_K", "ihx_r2_outlet_K",
)
REFERENCE_COLUMNS = ("time_s", "reactor_W", "turbine_W", "compressor_W")
CAPTURE_ROOT_FILES = (
    "tracked_diff.patch", "git_head.txt", "git_status_porcelain_v1_z.bin",
    "untracked_paths.json", "preflight_status.json",
    "command.txt", "stdout.log", "stderr.log", "formal_exit_code.txt",
    "formal_invocation.claim", "execution_record.json",
    "consumed_execution_manifest.json",
)
CAPTURE_EXECUTABLES = (
    "tests/prepare_fig519_ihx_r2_hexe_a3.py",
    "tests/create_fig519_ihx_r2_hexe_shift_candidate.m",
    "tests/run_fig519_ihx_r2_hexe_shift.m",
    "tests/steady53/run_steady53_case.m",
    "tests/steady53/steady53_signal_manifest.m",
    "tests/steady53/reset_steady53_property_warning_state.m",
    "tests/analyze_fig519_ihx_r2_hexe_shift.py",
    "tests/fig519_ihx_r2_hexe_contract.py",
    "tests/execute_fig519_ihx_r2_hexe_a3_once.py",
)
CAPTURE_DATA_GROUPS = (
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


def _declared_snapshot_paths() -> tuple[str, ...]:
    names = set(CAPTURE_EXECUTABLES)
    for group in CAPTURE_DATA_GROUPS:
        path = ROOT / group
        if path.is_file() and not path.is_symlink():
            names.add(group)
            continue
        if not path.is_dir() or path.is_symlink():
            raise RuntimeError(f"A3 immutable data group is unsafe/missing: {group}")
        for item in path.rglob("*"):
            if item.is_symlink():
                raise RuntimeError(f"A3 immutable data group contains symlink: {item}")
            if item.is_file():
                names.add(item.relative_to(ROOT).as_posix())
    return tuple(sorted(names))


CAPTURE_IMMUTABLES = _declared_snapshot_paths()
RUN_FILES = MappingProxyType({
    "patch_audit.json": "patch_audit.json",
    "run_status.json": "run/run_status.json",
    "raw_result.mat": "run/raw_result.mat",
    "candidate_curves.csv": "run/candidate_curves.csv",
    "reference_curves.csv": "run/reference_curves.csv",
})
RUN_AUTHENTICITY_SOURCES = MappingProxyType({
    "patch_audit": "patch_audit.json",
    "run_status": "run/run_status.json",
    "raw_result": "run/raw_result.mat",
    "candidate_curves": "run/candidate_curves.csv",
    "reference_curves": "run/reference_curves.csv",
})
PUBLICATION_DATA_FILES = (
    "patch_audit.json", "run_status.json", "raw_result.mat",
    "candidate_curves.csv", "reference_curves.csv", "analysis.json",
    "command.txt", "stdout.log", "stderr.log", "formal_exit_code.txt",
    "formal_invocation.claim", "execution_record.json",
    "tracked_diff.patch", "git_head.txt", "git_status_porcelain_v1_z.bin",
    "untracked_paths.json", "preflight_status.json",
    "consumed_execution_manifest.json",
    "captured/SHA256SUMS",
    *tuple("captured/" + name for name in CAPTURE_IMMUTABLES),
    "a3_summary.json",
)
MANIFEST_NAME = "manifest.csv"
HISTORY_SCHEMA = "steady53_fig519_initial_state_counterfactual_history_v1"
ANALYSIS_SCHEMA = "steady53_fig519_ihx_r2_hexe_shift_analysis_v1"
SUMMARY_SCHEMA = "steady53_fig519_ihx_r2_hexe_shift_summary_v1"
TRANSACTION_VERSION = 1


class A3AnalysisError(RuntimeError):
    """Base class for named, optimization-safe A3 validation failures."""


class PathValidationError(A3AnalysisError):
    pass


class PatchAuditError(A3AnalysisError):
    pass


class RunStatusError(A3AnalysisError):
    pass


class CurveDataError(A3AnalysisError):
    pass


class DirectionError(A3AnalysisError):
    pass


class SignalContractError(A3AnalysisError):
    pass


class PublicationError(A3AnalysisError):
    pass


class ExecutionAuthenticityError(PublicationError):
    pass


class VerificationError(A3AnalysisError):
    pass


class InjectedPublicationCrash(PublicationError):
    """Test-only fault type; production never raises it by itself."""


def _hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _json_bytes(value: object) -> bytes:
    try:
        text = json.dumps(
            value, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False
        )
    except (TypeError, ValueError) as exc:
        raise A3AnalysisError("JSON payload is not finite/serializable") from exc
    return (text + "\n").encode()


def _safe_path(path: Path, *, exists: bool = False,
               under: Path | None = None) -> Path:
    raw = Path(path)
    if not raw.is_absolute() or ".." in raw.parts:
        raise PathValidationError("path must be absolute and lexically contained")
    probe = Path(raw.anchor)
    for part in raw.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise PathValidationError(f"symlinked path is forbidden: {probe}")
            if probe != raw and not stat.S_ISDIR(mode):
                raise PathValidationError(f"path parent is not a directory: {probe}")
    try:
        resolved = raw.resolve(strict=exists)
    except OSError as exc:
        raise PathValidationError(f"path is missing: {raw}") from exc
    boundary = (under or ROOT).resolve(strict=True)
    if resolved != boundary and boundary not in resolved.parents:
        raise PathValidationError(f"path escaped its boundary: {raw}")
    return resolved


def _regular_file(path: Path, *, under: Path | None = None) -> Path:
    resolved = _safe_path(Path(path), exists=True, under=under)
    mode = os.lstat(resolved).st_mode
    if not stat.S_ISREG(mode):
        raise PathValidationError(f"required regular file is missing: {path}")
    return resolved


def _real_directory(path: Path, *, under: Path | None = None) -> Path:
    resolved = _safe_path(Path(path), exists=True, under=under)
    if not stat.S_ISDIR(os.lstat(resolved).st_mode):
        raise PathValidationError(f"required real directory is missing: {path}")
    return resolved


def _read_json(path: Path, *, error_type: type[A3AnalysisError]) -> object:
    try:
        return json.loads(_regular_file(path).read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError, PathValidationError) as exc:
        raise error_type(f"invalid JSON artifact: {path}") from exc


def _finite_number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise A3AnalysisError(f"{label} must be numeric")
    output = float(value)
    if not math.isfinite(output):
        raise A3AnalysisError(f"{label} must be finite")
    return output


def _finite_tree(value: object, label: str = "root") -> None:
    if isinstance(value, float) and not math.isfinite(value):
        raise A3AnalysisError(f"nonfinite value in {label}")
    if isinstance(value, dict):
        for key, child in value.items():
            _finite_tree(child, f"{label}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _finite_tree(child, f"{label}[{index}]")


def _paper_points() -> dict[str, list[tuple[float, float, float]]]:
    path = _regular_file(PAPER_POINTS_PATH)
    if _hash(path.read_bytes()) != PAPER_POINTS_SHA256:
        raise CurveDataError("A2 paper_points.csv identity changed")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
    grouped: dict[str, list[tuple[float, float, float]]] = {
        panel: [] for panel in "abcd"
    }
    seen: set[tuple[str, float]] = set()
    for row in rows:
        panel = row.get("panel_id")
        if panel not in grouped:
            raise CurveDataError("paper points contain an unknown panel")
        try:
            item = (
                float(row["time_s"]), float(row["power_kW"]),
                float(row["power_allowance_kW"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise CurveDataError("paper points contain malformed numbers") from exc
        if (not all(math.isfinite(number) for number in item) or item[2] <= 0 or
                (panel, item[0]) in seen):
            raise CurveDataError("paper points violate the A2 numeric contract")
        seen.add((panel, item[0]))
        grouped[panel].append(item)
    if any(len(points) != 15 or points != sorted(points) for points in grouped.values()):
        raise CurveDataError("each paper panel needs 15 increasing fixed points")
    return grouped


def direction_sequence(points: list[tuple[float, float, float]]) -> list[str]:
    if not isinstance(points, list) or len(points) < 2:
        raise DirectionError("direction input needs at least two fixed points")
    normalized: list[tuple[float, float, float]] = []
    for item in points:
        if not isinstance(item, tuple) or len(item) != 3:
            raise DirectionError("direction point must be a three-tuple")
        try:
            numeric = tuple(float(value) for value in item)
        except (TypeError, ValueError) as exc:
            raise DirectionError("direction point is nonnumeric") from exc
        if not all(math.isfinite(value) for value in numeric) or numeric[2] <= 0:
            raise DirectionError("direction point is nonfinite or has invalid allowance")
        normalized.append(numeric)
    if any(right[0] <= left[0] for left, right in zip(normalized, normalized[1:])):
        raise DirectionError("direction times must strictly increase")
    directions: list[str] = []
    for left, right in zip(normalized, normalized[1:]):
        if left[2] != right[2]:
            raise DirectionError("direction allowance must be fixed within a panel")
        delta = right[1] - left[1]
        directions.append(
            "rise" if delta > left[2] else
            "fall" if delta < -left[2] else "flat"
        )
    nonflat = (item for item in directions if item != "flat")
    return [key for key, _ in groupby(nonflat)]


def _signal_contract() -> dict[str, object]:
    path = _regular_file(SIGNAL_CONTRACT_PATH)
    if _hash(path.read_bytes()) != SIGNAL_CONTRACT_SHA256:
        raise SignalContractError("A2 signal_contract.json identity changed")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SignalContractError("signal contract is malformed") from exc
    if not isinstance(payload, dict) or payload.get("figure") != "5.19":
        raise SignalContractError("signal contract schema changed")
    signals = payload.get("signals")
    if not isinstance(signals, dict):
        raise SignalContractError("signal identities are missing")
    fixed = {
        "reactor": "P_sw", "turbine": "WT_sw", "compressor": "Wc_sw",
    }
    for name, identity in fixed.items():
        if not isinstance(signals.get(name), dict) or signals[name].get("model_signal") != identity:
            raise SignalContractError(f"captured signal identity changed: {name}")
    electrical = signals.get("electrical_paper_eta")
    if (not isinstance(electrical, dict) or
            electrical.get("formula") != "0.98*(WT_sw-Wc_sw)" or
            electrical.get("direct_generator_signal") is not None or
            electrical.get("kind") != "offline_derived"):
        raise SignalContractError("paper electrical signal formula/identity changed")
    historical = signals.get("electrical_historical_metric")
    if (not isinstance(historical, dict) or
            historical.get("accepted_for_fig519") is not False):
        raise SignalContractError("historical 0.96527 exclusion changed")
    return payload


def _initialization_states() -> list[dict[str, object]]:
    path = _regular_file(INITIALIZATION_AUDIT_PATH)
    if _hash(path.read_bytes()) != INITIALIZATION_AUDIT_SHA256:
        raise PatchAuditError("initialization audit identity changed")
    try:
        payload = json.loads(path.read_text())
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PatchAuditError("initialization audit is malformed") from exc
    states = payload.get("state_inventory") if isinstance(payload, dict) else None
    if not isinstance(states, list) or len(states) != 40:
        raise PatchAuditError("initialization audit must contain 40 states")
    return states


def _exact_record_index(records: object, expected: set[str], label: str,
                        *, name_key: str = "name") -> dict[str, dict[str, object]]:
    if not isinstance(records, list) or len(records) != len(expected):
        raise PatchAuditError(f"{label} identity count is not exact")
    indexed: dict[str, dict[str, object]] = {}
    for item in records:
        if not isinstance(item, dict) or not isinstance(item.get(name_key), str):
            raise PatchAuditError(f"{label} identity is malformed")
        name = item[name_key]
        if name in indexed:
            raise PatchAuditError(f"{label} identity is duplicated: {name}")
        indexed[name] = item
    if set(indexed) != expected:
        raise PatchAuditError(f"{label} identity set has missing or extra entries")
    return indexed


def _validate_audit_identities(audit: dict[str, object]) -> None:
    runtime_rel = "data/provenance/baselines/f8bcd83/runtime/"
    runtime = _exact_record_index(
        audit.get("runtime_dependencies"), set(RUNTIME_HASHES), "runtime"
    )
    for name, digest in RUNTIME_HASHES.items():
        item = runtime[name]
        path = _regular_file(RUNTIME_DIR / name)
        if (item.get("repository_relative_path") != runtime_rel + name or
                Path(str(item.get("absolute_path"))) != path or
                item.get("before_sha256") != digest or
                item.get("after_sha256") != digest or
                item.get("unchanged") is not True or
                _hash(path.read_bytes()) != digest):
            raise PatchAuditError(f"runtime identity mismatch: {name}")

    manifest = _regular_file(PROTECTED_MANIFEST_PATH)
    if _hash(manifest.read_bytes()) != (
            "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"):
        raise PatchAuditError("protected manifest bytes changed")
    try:
        with manifest.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
    except (OSError, UnicodeDecodeError, csv.Error) as exc:
        raise PatchAuditError("protected manifest is malformed") from exc
    if len(rows) != 34 or len({row.get("original_path") for row in rows}) != 34:
        raise PatchAuditError("protected manifest exact set changed")
    expected_protected = {str(row["original_path"]) for row in rows}
    protected = _exact_record_index(
        audit.get("protected_files"), expected_protected, "protected"
    )
    for row in rows:
        name = str(row["original_path"])
        item = protected[name]
        declared_path = Path(str(row["resolved_path"]))
        path = _regular_file(declared_path, under=Path(declared_path.anchor))
        try:
            relative = path.relative_to(ROOT).as_posix()
        except ValueError:
            relative = ""
        digest = str(row["resolved_sha256"])
        if (item.get("repository_relative_path") != relative or
                Path(str(item.get("absolute_path"))) != path or
                item.get("before_sha256") != digest or
                item.get("after_sha256") != digest or
                item.get("unchanged") is not True or
                _hash(path.read_bytes()) != digest):
            raise PatchAuditError(f"protected identity mismatch: {name}")

    formal = _exact_record_index(
        audit.get("formal_files"), set(FORMAL_NAMES), "formal",
        name_key="repository_relative_path",
    )
    for name in FORMAL_NAMES:
        item = formal[name]
        path = ROOT / name
        exists = path.is_file() and not path.is_symlink()
        digest = _hash(path.read_bytes()) if exists else ""
        before_key = item.get("before_file_key")
        after_key = item.get("after_file_key")
        if (Path(str(item.get("absolute_path"))) != path or
                item.get("exists_before") is not exists or
                item.get("exists_after") is not exists or
                item.get("before_sha256") != digest or
                item.get("after_sha256") != digest or
                item.get("unchanged") is not True or
                (exists and (not isinstance(before_key, str) or not before_key or
                             before_key != after_key)) or
                (not exists and (before_key != "" or after_key != ""))):
            raise PatchAuditError(f"formal identity mismatch: {name}")


def validate_patch_audit(audit: object, candidate: Path) -> dict[str, object]:
    if not isinstance(audit, dict):
        raise PatchAuditError("patch audit must be an object")
    fixed = {
        "patch_schema": "steady53_fig519_ihx_r2_hexe_shift_candidate_v1",
        "attempt_id": contract.ATTEMPT_ID,
        "candidate_value_identity": contract.ANCHOR_IDENTITY,
        "source_model_sha256": contract.SOURCE_MODEL_SHA256,
        "source_sha256": contract.SOURCE_MODEL_SHA256,
        "source_sha256_after": contract.SOURCE_MODEL_SHA256,
        "source_hash_unchanged": True,
        "changed_state_count": 2,
        "unchanged_state_count": 38,
        "state_count": 40,
        "solver_parameter_count": 37,
        "update_diagram_count": 1,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    for key, expected in fixed.items():
        if audit.get(key) != expected:
            raise PatchAuditError(f"patch audit fixed field mismatch: {key}")
    numeric = {
        "anchor_K": 1200.0,
        "delta_T_K": -193.6037139151003,
        "old_gap_K": 147.7852469306997,
        "new_gap_K": 147.7852469306997,
    }
    for key, expected in numeric.items():
        try:
            actual = _finite_number(audit.get(key), key)
        except A3AnalysisError as exc:
            raise PatchAuditError(str(exc)) from exc
        if abs(actual - expected) > 1e-12:
            raise PatchAuditError(f"patch audit decimal mismatch: {key}")
    source_relative = SOURCE_PATH.relative_to(ROOT).as_posix()
    if (audit.get("source_repository_relative_path") != source_relative or
            Path(str(audit.get("source_absolute_path"))) != SOURCE_PATH):
        raise PatchAuditError("source locator differs from the captured source")
    source = _regular_file(SOURCE_PATH)
    if _hash(source.read_bytes()) != contract.SOURCE_MODEL_SHA256:
        raise PatchAuditError("captured source model hash changed")

    candidate_path = _regular_file(Path(candidate))
    try:
        relative = candidate_path.relative_to(ROOT).as_posix()
    except ValueError as exc:
        raise PatchAuditError("candidate is outside the captured repository") from exc
    digest = audit.get("candidate_sha256")
    if (audit.get("candidate_repository_relative_path") != relative or
            Path(str(audit.get("candidate_absolute_path"))) != candidate_path or
            not isinstance(digest, str) or len(digest) != 64 or
            _hash(candidate_path.read_bytes()) != digest):
        raise PatchAuditError("candidate locator/hash mismatch")

    expected_states = _initialization_states()
    records = audit.get("state_initial_conditions")
    if not isinstance(records, list) or len(records) != 40:
        raise PatchAuditError("patch audit must contain exactly 40 state records")
    targets = {
        contract.AVERAGE_PATH: ("1245.8184669844006", "1052.2147530693003"),
        contract.OUTLET_PATH: ("1393.6037139151003", "1200.0000000000000"),
    }
    changed_paths: set[str] = set()
    source_paths: set[str] = set()
    candidate_paths: set[str] = set()
    for record, expected in zip(records, expected_states):
        if not isinstance(record, dict):
            raise PatchAuditError("state record is not an object")
        path = expected["path"]
        source_expression = expected["initial_condition_expression"]
        candidate_expected = targets.get(path, (source_expression, source_expression))[1]
        expected_candidate_path = path.replace("final_steady_24a/", "candidate/", 1)
        if (record.get("source_path") != path or
                record.get("candidate_path") != expected_candidate_path or
                record.get("source_expression") != source_expression or
                record.get("candidate_expression") != candidate_expected):
            raise PatchAuditError(f"state inventory value/path mismatch: {path}")
        same = source_expression == candidate_expected
        if record.get("unchanged") is not same:
            raise PatchAuditError(f"state unchanged flag mismatch: {path}")
        source_paths.add(path)
        candidate_paths.add(expected_candidate_path)
        if not same:
            changed_paths.add(path)
    if (len(source_paths) != 40 or len(candidate_paths) != 40 or
            changed_paths != set(targets)):
        raise PatchAuditError("state inventory is duplicated or changes extra states")

    changes = audit.get("changed_states")
    if not isinstance(changes, list) or len(changes) != 2:
        raise PatchAuditError("changed state list must contain two dependent states")
    indexed = {item.get("path"): item for item in changes if isinstance(item, dict)}
    if set(indexed) != set(targets):
        raise PatchAuditError("changed state paths differ from A3")
    for path, (old_text, new_text) in targets.items():
        item = indexed[path]
        expected_candidate_path = path.replace("final_steady_24a/", "candidate/", 1)
        values = (
            item.get("old_initial_condition_K"), item.get("new_initial_condition_K"),
            item.get("delta_T_K"),
        )
        if (item.get("candidate_path") != expected_candidate_path or
                any(isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(float(value)) for value in values) or
                abs(float(values[0]) - float(old_text)) > 1e-12 or
                abs(float(values[1]) - float(new_text)) > 1e-12 or
                abs(float(values[2]) + 193.6037139151003) > 1e-12):
            raise PatchAuditError(f"changed state common-delta mismatch: {path}")

    solver = audit.get("solver_contract")
    if (not isinstance(solver, dict) or solver.get("unchanged") is not True or
            solver.get("parameter_count") != 37 or
            not isinstance(solver.get("parameters"), list) or
            len(solver["parameters"]) != 37 or
            len({item.get("name") for item in solver["parameters"]
                 if isinstance(item, dict)}) != 37):
        raise PatchAuditError("37-parameter solver contract is incomplete")
    semantic = audit.get("semantic_snapshot")
    workspace = audit.get("model_workspace")
    if (not isinstance(semantic, dict) or semantic.get("unchanged") is not True or
            semantic.get("source") != semantic.get("candidate")):
        raise PatchAuditError("semantic topology changed")
    if (not isinstance(workspace, dict) or workspace.get("unchanged") is not True or
            workspace.get("source") != workspace.get("candidate")):
        raise PatchAuditError("model workspace changed")
    _validate_audit_identities(audit)
    if audit.get("protected_manifest_sha256") != (
            "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"):
        raise PatchAuditError("protected manifest identity changed")
    _finite_tree(audit)
    return audit


def _read_curves(path: Path, expected: tuple[str, ...],
                 *, error_type: type[CurveDataError]) -> dict[str, list[float]]:
    try:
        source = _regular_file(Path(path))
        with source.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            if tuple(reader.fieldnames or ()) != expected:
                raise error_type("curve CSV schema mismatch")
            rows = list(reader)
    except (OSError, UnicodeDecodeError, csv.Error, PathValidationError) as exc:
        raise error_type(f"cannot read curve CSV: {path}") from exc
    if len(rows) < 2:
        raise error_type("curve CSV needs at least two samples")
    output = {name: [] for name in expected}
    try:
        for row in rows:
            if set(row) != set(expected):
                raise error_type("curve CSV row schema mismatch")
            for name in expected:
                output[name].append(float(row[name]))
    except (TypeError, ValueError) as exc:
        raise error_type("curve CSV contains nonnumeric values") from exc
    if any(not math.isfinite(value) for values in output.values() for value in values):
        raise error_type("curve CSV contains nonfinite values")
    if any(right <= left for left, right in zip(output["time_s"], output["time_s"][1:])):
        raise error_type("curve time vector is not strictly increasing")
    return output


def read_candidate_curves(path: Path) -> dict[str, list[float]]:
    return _read_curves(Path(path), CANDIDATE_COLUMNS, error_type=CurveDataError)


def _read_reference_curves(path: Path) -> dict[str, list[float]]:
    return _read_curves(Path(path), REFERENCE_COLUMNS, error_type=CurveDataError)


def _artifact_index(status: dict[str, object], run_dir: Path) -> dict[str, dict[str, object]]:
    records = status.get("artifacts")
    if not isinstance(records, list):
        raise RunStatusError("run artifact locators are missing")
    indexed: dict[str, dict[str, object]] = {}
    for item in records:
        if not isinstance(item, dict) or not isinstance(item.get("identity"), str):
            raise RunStatusError("run artifact locator is malformed")
        identity = item["identity"]
        if identity in indexed:
            raise RunStatusError("run artifact identity is duplicated")
        relative = item.get("repository_relative_path")
        absolute = item.get("absolute_path")
        if not isinstance(relative, str) or not isinstance(absolute, str):
            raise RunStatusError("run artifact paths are malformed")
        try:
            path = _regular_file(ROOT / relative)
        except PathValidationError as exc:
            raise RunStatusError(f"run artifact is unsafe: {identity}") from exc
        if (path != Path(absolute) or run_dir not in path.parents or
                item.get("sha256") != _hash(path.read_bytes()) or
                item.get("bytes") != path.stat().st_size or
                item.get("storage") != "external_tmp_not_copied"):
            raise RunStatusError(f"run artifact locator/hash mismatch: {identity}")
        indexed[identity] = item
    return indexed


def validate_run_status(status: object, run_dir: Path) -> dict[str, object]:
    if not isinstance(status, dict):
        raise RunStatusError("run status must be an object")
    try:
        selected = _real_directory(Path(run_dir))
    except PathValidationError as exc:
        raise RunStatusError("run directory is unsafe") from exc
    fixed = {
        "run_schema": "steady53_fig519_ihx_r2_hexe_shift_run_v1",
        "attempt_id": contract.ATTEMPT_ID,
        "candidate_value_identity": contract.ANCHOR_IDENTITY,
        "run_steady53_case_call_count": 1,
        "retry_count": 0,
        "rerun_forbidden": True,
        "identity_unchanged": True,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    for key, expected in fixed.items():
        if status.get(key) != expected:
            raise RunStatusError(f"run status fixed field mismatch: {key}")
    allowed = {
        "completed_success", "completed_model_failure",
        "completed_incomplete_output", "runner_or_hash_gate_failed",
    }
    if status.get("experiment_status") not in allowed:
        raise RunStatusError("run status enum is invalid")
    if status.get("identity_before") != status.get("identity_after"):
        raise RunStatusError("run before/after identities differ")
    identity = status.get("identity_before")
    if (not isinstance(identity, dict) or
            identity.get("source_sha256") != contract.SOURCE_MODEL_SHA256):
        raise RunStatusError("run source identity differs from A3")
    candidate = _regular_file(selected / "candidate.slx")
    audit = _read_json(selected / "patch_audit.json", error_type=RunStatusError)
    validated_audit = validate_patch_audit(audit, candidate)
    def snapshot(records: object) -> list[dict[str, object]]:
        if not isinstance(records, list):
            raise RunStatusError("audit identity record set is malformed")
        return [{
            "repository_relative_path": item["repository_relative_path"],
            "sha256": item["before_sha256"],
        } for item in records]
    expected_runtime = snapshot(validated_audit["runtime_dependencies"])
    expected_formal = [{
        "repository_relative_path": item["repository_relative_path"],
        "exists": item["exists_before"],
        "sha256": item["before_sha256"],
    } for item in validated_audit["formal_files"]]
    expected_reference = [{"name": name, "sha256": digest}
                          for name, digest in BASELINE_HASHES.items()]
    expected_fixed = {
        "source_sha256": contract.SOURCE_MODEL_SHA256,
        "candidate_sha256": validated_audit["candidate_sha256"],
    }
    if (set(identity) != {
            "source_sha256", "candidate_sha256", "runtime_dependencies",
            "protected_files", "formal_files", "reference_curves"} or
            any(identity.get(key) != value for key, value in expected_fixed.items()) or
            identity.get("runtime_dependencies") != expected_runtime or
            identity.get("formal_files") != expected_formal or
            identity.get("reference_curves") != expected_reference):
        raise RunStatusError("run candidate identity differs from patch audit")
    protected_snapshot = identity.get("protected_files")
    audit_protected = validated_audit["protected_files"]
    if not isinstance(protected_snapshot, list) or len(protected_snapshot) != 34:
        raise RunStatusError("run protected identity set differs from patch audit")
    expected_protected = {item["name"]: item for item in audit_protected}
    seen: set[str] = set()
    for item in protected_snapshot:
        if not isinstance(item, dict) or set(item) != {
                "name", "resolved_path", "sha256", "file_key", "device", "inode"}:
            raise RunStatusError("run protected identity record is malformed")
        name = item.get("name")
        if not isinstance(name, str) or name in seen or name not in expected_protected:
            raise RunStatusError("run protected identity set is duplicated or changed")
        seen.add(name)
        expected = expected_protected[name]
        path = Path(str(expected["absolute_path"]))
        stat_result = os.stat(path, follow_symlinks=False)
        if (item.get("resolved_path") != str(path.resolve(strict=True)) or
                item.get("sha256") != expected["before_sha256"] or
                not isinstance(item.get("file_key"), str) or not item["file_key"] or
                str(item.get("device")) != str(stat_result.st_dev) or
                str(item.get("inode")) != str(stat_result.st_ino)):
            raise RunStatusError(f"run protected identity mismatch: {name}")
    if seen != set(expected_protected):
        raise RunStatusError("run protected identity set has missing entries")
    artifacts = _artifact_index(status, selected)
    allowed_artifacts = {
        "candidate_slx", "patch_audit", "raw_result",
        "candidate_curves", "reference_curves",
    }
    required = {"candidate_slx", "patch_audit"}
    if status.get("run_steady53_case_returned") is True:
        required.add("raw_result")
    elif "raw_result" in artifacts:
        raise RunStatusError("thrown call cannot claim a raw result")
    if status.get("experiment_status") == "completed_success":
        required.update({"raw_result", "candidate_curves", "reference_curves"})
    if not required.issubset(artifacts) or set(artifacts) - allowed_artifacts:
        raise RunStatusError("run artifact locator set is inconsistent")
    return status


def _interpolate(times: list[float], values: list[float], query: float) -> float:
    index = bisect_left(times, query)
    if index < len(times) and times[index] == query:
        return values[index]
    if index == 0 or index == len(times):
        raise CurveDataError("curve does not cover a paper comparison time")
    left, right = times[index - 1], times[index]
    fraction = (query - left) / (right - left)
    return values[index - 1] + fraction * (values[index] - values[index - 1])


def _metrics(times: list[float], values: list[float]) -> dict[str, object]:
    high, low = max(values), min(values)
    high_i, low_i = values.index(high), values.index(low)
    return {
        "units": "W", "samples": len(values), "start_W": values[0],
        "end_W": values[-1], "peak_to_peak_W": high - low,
        "peak_W": high, "peak_time_s": times[high_i],
        "valley_W": low, "valley_time_s": times[low_i],
    }


def _paper_comparison(times: list[float], values: list[float],
                      points: list[tuple[float, float, float]]) -> dict[str, object]:
    model = [_interpolate(times, values, point[0]) / 1000.0 for point in points]
    errors = [actual - point[1] for actual, point in zip(model, points)]
    model_points = [
        (point[0], actual, point[2]) for point, actual in zip(points, model)
    ]
    squares = [error * error for error in errors]
    paper_direction = direction_sequence(points)
    candidate_direction = direction_sequence(model_points)
    return {
        "paper_points": len(points),
        "rmse_kW": math.sqrt(sum(squares) / len(squares)),
        "max_abs_error_kW": max(abs(error) for error in errors),
        "start_error_kW": errors[0], "end_error_kW": errors[-1],
        "squared_error_contribution_kW2": sum(squares),
        "paper_direction_sequence": paper_direction,
        "candidate_direction_sequence": candidate_direction,
        "direction_sequence_match": candidate_direction == paper_direction,
    }


def _reference_change(candidate_t: list[float], candidate: list[float],
                      reference_t: list[float], reference: list[float],
                      fixed_threshold: Decimal) -> dict[str, object]:
    reference_at_candidate = [
        _interpolate(reference_t, reference, time) for time in candidate_t
    ]
    delta = [left - right for left, right in zip(candidate, reference_at_candidate)]
    p2p = max(candidate) - min(candidate)
    threshold = float(fixed_threshold)
    return {
        "rmse_change_W": math.sqrt(sum(value * value for value in delta) / len(delta)),
        "max_abs_change_W": max(abs(value) for value in delta),
        "start_change_W": delta[0], "end_change_W": delta[-1],
        "candidate_peak_to_peak_W": p2p,
        "reference_peak_to_peak_noise_W": max(reference) - min(reference),
        "nonflat_threshold_W": threshold,
        "nonflat": p2p >= threshold,
    }


def _validate_reference_identity(reference: dict[str, list[float]]) -> None:
    names = ("baseline_P_sw.csv", "baseline_WT_sw.csv", "baseline_Wc_sw.csv")
    columns = ("reactor_W", "turbine_W", "compressor_W")
    expected_series = []
    for name in names:
        path = _regular_file(MODEL_BASELINE_DIR / name)
        if _hash(path.read_bytes()) != BASELINE_HASHES[name]:
            raise CurveDataError(f"A2 baseline curve identity changed: {name}")
        try:
            with path.open(newline="") as handle:
                values = [[float(value) for value in row] for row in csv.reader(handle)]
        except (OSError, ValueError, csv.Error) as exc:
            raise CurveDataError(f"A2 baseline curve is malformed: {name}") from exc
        expected_series.append(values)
    for index, column in enumerate(columns):
        if (reference["time_s"] != [item[0] for item in expected_series[index]] or
                reference[column] != [item[1] for item in expected_series[index]]):
            raise CurveDataError(f"reference curves do not byte-semantically reuse A2: {column}")


def validate_analysis(result: object) -> dict[str, object]:
    if not isinstance(result, dict):
        raise A3AnalysisError("analysis must be an object")
    if (result.get("analysis_schema") != ANALYSIS_SCHEMA or
            result.get("conclusion") not in CONCLUSIONS or
            result.get("promotion") != dict(PROMOTION) or
            any(result.get(key) is not False for key in PROMOTION)):
        raise A3AnalysisError("analysis fixed contract mismatch")
    passed = result.get("numerical_gate_passed")
    if not isinstance(passed, bool):
        raise A3AnalysisError("numerical gate must be boolean")
    if not passed and result["conclusion"] != "numerical_or_physical_gate_failed":
        raise A3AnalysisError("failed numerical gate has the wrong conclusion")
    failure_classes = {
        "pre_simulation_infrastructure", "compile", "property_domain",
        "model_runtime", "incomplete_output",
    }
    if ((passed and result.get("gate_failure_class") is not None) or
            (not passed and result.get("gate_failure_class") not in failure_classes) or
            result.get("derived_electrical_paper_eta_formula") !=
            "0.98*(WT_sw-Wc_sw)" or
            result.get("direction_rule") != dict(DIRECTION_RULE) or
            result.get("nonflat_thresholds_W") != {
                name: float(value) for name, value in NONFLAT_THRESHOLDS_W.items()
            }):
        raise A3AnalysisError("analysis formula/rule/failure class changed")
    if passed:
        directions = result.get("directions")
        nonflat = result.get("nonflat")
        if (not isinstance(directions, dict) or set(directions) != set(contract.PAPER_DIRECTIONS) or
                not isinstance(nonflat, dict) or set(nonflat) != set(contract.PAPER_DIRECTIONS)):
            raise A3AnalysisError("analysis must contain all four gates")
        expected = contract.classify(
            True, {name: tuple(value) for name, value in directions.items()}, nonflat
        )
        if result["conclusion"] != expected:
            raise A3AnalysisError("analysis conclusion is not mechanical")
    _finite_tree(result)
    return result


def _verify_durable_scientific_derivation(durable: Path,
                                          result: dict[str, object]) -> None:
    execution = _read_json(durable / "execution_record.json", error_type=VerificationError)
    if not isinstance(execution, dict):
        raise VerificationError("durable execution record is malformed")
    try:
        exit_code = int(_regular_file(durable / "formal_exit_code.txt").read_text().strip())
    except (UnicodeDecodeError, ValueError, PathValidationError) as exc:
        raise VerificationError("durable formal exit code is malformed") from exc
    if (_regular_file(durable / "command.txt").read_bytes() !=
            (EXACT_FORMAL_COMMAND + "\n").encode() or
            execution.get("formal_process_exit_code") != exit_code or
            result.get("run_steady53_case_call_count") !=
            execution.get("run_steady53_case_call_count") or
            result.get("retry_count") != execution.get("retry_count")):
        raise VerificationError("durable execution claims conflict with analysis")
    if result["numerical_gate_passed"]:
        if (exit_code != 0 or execution.get("matlab_subprocess_start_count") != 1 or
                execution.get("run_steady53_case_call_count") != 1):
            raise VerificationError("positive scientific result lacks exact execution proof")
    else:
        status_path = durable / "run_status.json"
        if status_path.is_file() and not status_path.is_symlink():
            status = _read_json(status_path, error_type=VerificationError)
            audit = _read_json(durable / "patch_audit.json", error_type=VerificationError)
            if (not isinstance(status, dict) or not isinstance(audit, dict) or
                    result.get("gate_failure_class") !=
                    _failure_subclass(status, {"exit_code": exit_code}) or
                    result.get("candidate_sha256") != audit.get("candidate_sha256")):
                raise VerificationError("failed analysis is not derived from run evidence")
        elif (result.get("gate_failure_class") != "pre_simulation_infrastructure" or
              result.get("candidate_sha256") is not None or
              result.get("observed_error_id") != execution.get("error_id") or
              result.get("observed_error_report") != execution.get("error_report") or
              result.get("formal_process_exit_code") != exit_code):
            raise VerificationError("pre-simulation analysis is not derived from execution evidence")
        return
    candidate = read_candidate_curves(durable / "candidate_curves.csv")
    reference = _read_reference_curves(durable / "reference_curves.csv")
    _validate_reference_identity(reference)
    paper = _paper_points()
    derived = [
        PAPER_ETA * (turbine - compressor)
        for turbine, compressor in zip(candidate["turbine_W"], candidate["compressor_W"])
    ]
    reference_electrical = [
        PAPER_ETA * (turbine - compressor)
        for turbine, compressor in zip(reference["turbine_W"], reference["compressor_W"])
    ]
    candidate_signals = {
        "reactor": candidate["reactor_W"], "turbine": candidate["turbine_W"],
        "compressor": candidate["compressor_W"],
        "electrical_paper_eta": derived,
    }
    reference_signals = {
        "reactor": reference["reactor_W"], "turbine": reference["turbine_W"],
        "compressor": reference["compressor_W"],
        "electrical_paper_eta": reference_electrical,
    }
    panels = {"reactor": "a", "turbine": "b", "compressor": "c",
              "electrical_paper_eta": "d"}
    directions: dict[str, list[str]] = {}
    nonflat: dict[str, bool] = {}
    curves: dict[str, dict[str, object]] = {}
    for name, panel in panels.items():
        comparison = _paper_comparison(
            candidate["time_s"], candidate_signals[name], paper[panel]
        )
        change = _reference_change(
            candidate["time_s"], candidate_signals[name], reference["time_s"],
            reference_signals[name], NONFLAT_THRESHOLDS_W[name],
        )
        directions[name] = comparison["candidate_direction_sequence"]
        nonflat[name] = bool(change["nonflat"])
        curves[name] = {
            "candidate_metrics": _metrics(candidate["time_s"], candidate_signals[name]),
            "paper_comparison": comparison,
            "reference_change": change,
        }
    conclusion = contract.classify(
        True, {name: tuple(value) for name, value in directions.items()}, nonflat
    )
    if (result.get("directions") != directions or result.get("nonflat") != nonflat or
            result.get("curves") != curves or
            result.get("derived_electrical_paper_eta_W") != derived or
            result.get("conclusion") != conclusion):
        raise VerificationError("durable analysis is not derivable from captured CSV bytes")


def _failure_subclass(status: dict[str, object] | None,
                      evidence: dict[str, object] | None = None) -> str:
    if status is None:
        return "pre_simulation_infrastructure"
    experiment = status.get("experiment_status")
    if experiment == "completed_incomplete_output":
        return "incomplete_output"
    text = " ".join(str(status.get(key, "")) for key in (
        "candidate_error_id", "candidate_error_report",
        "runner_exception_id", "runner_exception_report",
    )).lower()
    if any(token in text for token in (
            "hexe", "virial", "property", "domain", "correctedflow",
            "corrected flow", "assertion")):
        return "property_domain"
    if any(token in text for token in (
            "compile", "compilation", "update diagram", "updatediagram")):
        return "compile"
    if (experiment == "runner_or_hash_gate_failed" or
            (evidence is not None and evidence.get("exit_code") != 0 and
             status.get("run_steady53_case_returned") is not True)):
        return "pre_simulation_infrastructure"
    if (status.get("run_steady53_case_returned") is True and
            status.get("candidate_final_time_s") != 500 and not text):
        return "incomplete_output"
    return "model_runtime"


def _failure_result(*, failure_class: str, call_count: int, retry_count: int,
                    candidate_sha256: str | None, error_id: str = "",
                    error_report: str = "", exit_code: int | None = None,
                    missing_run_artifacts: list[str] | None = None) -> dict[str, object]:
    result = {
        "analysis_schema": ANALYSIS_SCHEMA,
        "attempt_id": contract.ATTEMPT_ID,
        "anchor_identity": contract.ANCHOR_IDENTITY,
        "counterfactual_question": (
            "Does the frozen IHX region-2 He-Xe two-state common translation alone "
            "pass all four predeclared Figure 5.19 direction/nonflat gates?"
        ),
        "numerical_gate_passed": False,
        "gate_failure_class": failure_class,
        "directions": {}, "nonflat": {},
        "direction_rule": dict(DIRECTION_RULE),
        "nonflat_thresholds_W": {
            name: float(value) for name, value in NONFLAT_THRESHOLDS_W.items()
        },
        "curves": {},
        "derived_electrical_paper_eta_formula": "0.98*(WT_sw-Wc_sw)",
        "derived_electrical_paper_eta_W": [],
        "conclusion": "numerical_or_physical_gate_failed",
        "promotion": dict(PROMOTION),
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
        "run_steady53_case_call_count": call_count,
        "retry_count": retry_count,
        "candidate_sha256": candidate_sha256,
        "observed_error_id": error_id,
        "observed_error_report": error_report,
        "formal_process_exit_code": exit_code,
        "missing_run_artifacts": list(missing_run_artifacts or []),
    }
    return validate_analysis(result)


def analyze(run_dir: Path) -> dict[str, object]:
    try:
        selected = _real_directory(Path(run_dir))
    except PathValidationError as exc:
        raise A3AnalysisError("run directory is unsafe") from exc
    candidate = _regular_file(selected / "candidate.slx")
    audit = validate_patch_audit(
        _read_json(selected / "patch_audit.json", error_type=PatchAuditError), candidate
    )
    status = validate_run_status(
        _read_json(selected / "run/run_status.json", error_type=RunStatusError), selected
    )
    _signal_contract()
    paper = _paper_points()
    numerical_gate = (
        status["experiment_status"] == "completed_success" and
        status.get("candidate_success") is True and
        status.get("candidate_final_time_s") == 500 and
        status.get("run_steady53_case_returned") is True
    )
    directions: dict[str, list[str]] = {}
    nonflat: dict[str, bool] = {}
    curves: dict[str, dict[str, object]] = {}
    derived_electrical: list[float] = []
    if numerical_gate:
        candidate_curves = read_candidate_curves(selected / "run/candidate_curves.csv")
        reference_curves = _read_reference_curves(selected / "run/reference_curves.csv")
        _validate_reference_identity(reference_curves)
        if candidate_curves["time_s"][0] > 0 or candidate_curves["time_s"][-1] != 500:
            raise CurveDataError("candidate curve window must cover 0 through exactly 500 s")
        for name, expected in (
            ("ihx_r2_average_K", 1052.2147530693003),
            ("ihx_r2_outlet_K", 1200.0),
        ):
            if abs(candidate_curves[name][0] - expected) > 1e-12:
                raise CurveDataError(f"candidate state t0 differs from A3: {name}")
        derived_electrical = [
            PAPER_ETA * (turbine - compressor)
            for turbine, compressor in zip(
                candidate_curves["turbine_W"], candidate_curves["compressor_W"]
            )
        ]
        reference_electrical = [
            PAPER_ETA * (turbine - compressor)
            for turbine, compressor in zip(
                reference_curves["turbine_W"], reference_curves["compressor_W"]
            )
        ]
        candidate_signals = {
            "reactor": candidate_curves["reactor_W"],
            "turbine": candidate_curves["turbine_W"],
            "compressor": candidate_curves["compressor_W"],
            "electrical_paper_eta": derived_electrical,
        }
        reference_signals = {
            "reactor": reference_curves["reactor_W"],
            "turbine": reference_curves["turbine_W"],
            "compressor": reference_curves["compressor_W"],
            "electrical_paper_eta": reference_electrical,
        }
        panel = {"reactor": "a", "turbine": "b", "compressor": "c",
                 "electrical_paper_eta": "d"}
        for name in panel:
            comparison = _paper_comparison(
                candidate_curves["time_s"], candidate_signals[name], paper[panel[name]]
            )
            change = _reference_change(
                candidate_curves["time_s"], candidate_signals[name],
                reference_curves["time_s"], reference_signals[name],
                NONFLAT_THRESHOLDS_W[name],
            )
            directions[name] = comparison["candidate_direction_sequence"]
            nonflat[name] = bool(change["nonflat"])
            curves[name] = {
                "candidate_metrics": _metrics(
                    candidate_curves["time_s"], candidate_signals[name]
                ),
                "paper_comparison": comparison,
                "reference_change": change,
            }
    conclusion = contract.classify(
        numerical_gate,
        {name: tuple(value) for name, value in directions.items()},
        nonflat,
    )
    result = {
        "analysis_schema": ANALYSIS_SCHEMA,
        "attempt_id": contract.ATTEMPT_ID,
        "anchor_identity": contract.ANCHOR_IDENTITY,
        "counterfactual_question": (
            "Does the frozen IHX region-2 He-Xe two-state common translation alone "
            "pass all four predeclared Figure 5.19 direction/nonflat gates?"
        ),
        "numerical_gate_passed": numerical_gate,
        "gate_failure_class": None if numerical_gate else _failure_subclass(status),
        "directions": directions,
        "nonflat": nonflat,
        "direction_rule": dict(DIRECTION_RULE),
        "nonflat_thresholds_W": {
            name: float(value) for name, value in NONFLAT_THRESHOLDS_W.items()
        },
        "curves": curves,
        "derived_electrical_paper_eta_formula": "0.98*(WT_sw-Wc_sw)",
        "derived_electrical_paper_eta_W": derived_electrical,
        "conclusion": conclusion,
        "promotion": dict(PROMOTION),
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
        "run_steady53_case_call_count": status["run_steady53_case_call_count"],
        "retry_count": status["retry_count"],
        "candidate_sha256": audit["candidate_sha256"],
    }
    return validate_analysis(result)


def _authenticity_record(identity: str, location: str, path: Path) -> dict[str, object]:
    source = _regular_file(path)
    return {
        "identity": identity,
        "location": location,
        "sha256": _hash(source.read_bytes()),
        "bytes": source.stat().st_size,
    }


def _execution_authenticity(capture_dir: Path, run_dir: Path) -> dict[str, object]:
    try:
        capture = _real_directory(Path(capture_dir), under=INVOCATION_ROOT)
        selected = _safe_path(Path(run_dir), exists=False)
    except PathValidationError as exc:
        raise ExecutionAuthenticityError("capture or selected run path is unsafe") from exc
    claim_payload = _regular_file(
        capture / "formal_invocation.claim", under=capture
    ).read_bytes()
    if not claim_payload:
        raise ExecutionAuthenticityError("formal invocation claim is empty")
    command_payload = _regular_file(capture / "command.txt", under=capture).read_bytes()
    if command_payload != (EXACT_FORMAL_COMMAND + "\n").encode():
        raise ExecutionAuthenticityError("captured command is not the exact Task 5 command")
    try:
        exit_payload = _regular_file(
            capture / "formal_exit_code.txt", under=capture
        ).read_text(encoding="ascii")
        if not exit_payload.endswith("\n") or exit_payload.strip() == "":
            raise ValueError("missing exit code")
        exit_code = int(exit_payload.strip())
    except (UnicodeDecodeError, ValueError) as exc:
        raise ExecutionAuthenticityError("formal exit code is malformed") from exc
    try:
        execution = json.loads(
            _regular_file(capture / "execution_record.json", under=capture).read_text()
        )
        preflight = json.loads(
            _regular_file(capture / "preflight_status.json", under=capture).read_text()
        )
        untracked = json.loads(
            _regular_file(capture / "untracked_paths.json", under=capture).read_text()
        )
        consumed = json.loads(
            _regular_file(
                capture / "consumed_execution_manifest.json", under=capture
            ).read_text()
        )
    except (UnicodeDecodeError, json.JSONDecodeError, PathValidationError) as exc:
        raise ExecutionAuthenticityError("captured execution JSON is malformed/missing") from exc
    if not isinstance(untracked, list):
        raise ExecutionAuthenticityError("captured untracked path inventory is malformed")
    git_head = _regular_file(capture / "git_head.txt", under=capture).read_text().strip()
    if len(git_head) != 40 or any(character not in "0123456789abcdef" for character in git_head):
        raise ExecutionAuthenticityError("captured Git HEAD is malformed")
    _regular_file(capture / "tracked_diff.patch", under=capture)
    _regular_file(capture / "git_status_porcelain_v1_z.bin", under=capture)
    command_sha = _hash(command_payload)
    if (not isinstance(preflight, dict) or
            preflight.get("attempt_id") != contract.ATTEMPT_ID or
            preflight.get("formal_command_sha256") != command_sha or
            preflight.get("formal_command_invocation_count") != 0 or
            preflight.get("run_steady53_case_call_count") != 0 or
            preflight.get("simulation_call_count") != 0):
        raise ExecutionAuthenticityError("preflight status conflicts with the exact command")
    fixed_execution = {
        "execution_schema": "steady53_fig519_ihx_r2_hexe_a3_execution_v1",
        "attempt_id": contract.ATTEMPT_ID,
        "formal_command": EXACT_FORMAL_COMMAND,
        "formal_command_sha256": command_sha,
        "formal_command_invocation_count": 1,
        "retry_count": 0,
        "formal_process_exit_code": exit_code,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    if not isinstance(execution, dict):
        raise ExecutionAuthenticityError("execution record must be an object")
    for key, expected in fixed_execution.items():
        if execution.get(key) != expected:
            raise ExecutionAuthenticityError(f"execution record mismatch: {key}")
    for key in ("matlab_subprocess_start_count", "run_steady53_case_call_count"):
        if type(execution.get(key)) is not int or execution[key] not in (0, 1):
            raise ExecutionAuthenticityError(f"execution counter is invalid: {key}")
    if (execution["run_steady53_case_call_count"] >
            execution["matlab_subprocess_start_count"]):
        raise ExecutionAuthenticityError("model call count exceeds subprocess starts")
    if exit_code == 0:
        if (execution.get("failure_stage") is not None or
                execution.get("error_id") != "" or
                execution.get("error_report") != ""):
            raise ExecutionAuthenticityError("successful process carries a failure claim")
    elif (not isinstance(execution.get("failure_stage"), str) or
          not execution["failure_stage"] or
          not isinstance(execution.get("error_id"), str) or
          not execution["error_id"] or
          not isinstance(execution.get("error_report"), str) or
          not execution["error_report"]):
        raise ExecutionAuthenticityError("failed process lacks truthful failure evidence")
    if exit_code != 0:
        stderr_payload = _regular_file(capture / "stderr.log", under=capture).read_bytes()
        if str(execution["error_report"]).encode() not in stderr_payload:
            raise ExecutionAuthenticityError("failure report is absent from captured stderr")

    capture_identities = (
        "formal_invocation.claim", "command.txt", "stdout.log", "stderr.log",
        "formal_exit_code.txt", "execution_record.json",
    )
    actual = [
        _authenticity_record(name, "capture/" + name, capture / name)
        for name in capture_identities
    ]
    run_exists = os.path.lexists(selected)
    if run_exists:
        try:
            selected = _real_directory(selected)
        except PathValidationError as exc:
            raise ExecutionAuthenticityError("consumed run directory is unsafe") from exc
    missing_run: list[str] = []
    for identity, relative in RUN_AUTHENTICITY_SOURCES.items():
        path = selected / relative
        if run_exists and os.path.lexists(path):
            try:
                actual.append(_authenticity_record(
                    identity, "run/" + relative, _regular_file(path, under=selected)
                ))
            except PathValidationError as exc:
                raise ExecutionAuthenticityError(
                    f"consumed run artifact is unsafe: {identity}"
                ) from exc
        else:
            missing_run.append(identity)
    actual = sorted(actual, key=lambda item: item["identity"])
    if (not isinstance(consumed, dict) or set(consumed) != {
            "manifest_schema", "attempt_id", "invocation_claimed",
            "formal_command", "formal_process_exit_code", "artifacts",
            "missing_run_artifacts",
        } or
            consumed.get("manifest_schema") !=
            "steady53_fig519_ihx_r2_hexe_a3_consumed_execution_v1" or
            consumed.get("attempt_id") != contract.ATTEMPT_ID or
            consumed.get("invocation_claimed") is not True or
            consumed.get("formal_command") != EXACT_FORMAL_COMMAND or
            consumed.get("formal_process_exit_code") != exit_code or
            consumed.get("artifacts") != actual or
            consumed.get("missing_run_artifacts") != sorted(missing_run)):
        raise ExecutionAuthenticityError(
            "consumed execution manifest does not exactly bind existing artifacts"
        )
    success_eligible = (
        exit_code == 0 and execution["matlab_subprocess_start_count"] == 1 and
        execution["run_steady53_case_call_count"] == 1 and run_exists and
        not ({"patch_audit", "run_status", "raw_result",
              "candidate_curves", "reference_curves"} & set(missing_run))
    )
    return {
        "capture_dir": capture,
        "run_dir": selected,
        "run_exists": run_exists,
        "exit_code": exit_code,
        "execution_record": execution,
        "consumed_manifest": consumed,
        "success_eligible": success_eligible,
        "missing_run_artifacts": sorted(missing_run),
    }


def _capture_files(capture_dir: Path) -> dict[str, bytes]:
    try:
        capture = _real_directory(Path(capture_dir), under=INVOCATION_ROOT)
        snapshot = _real_directory(capture / "repo_snapshot", under=capture)
    except PathValidationError as exc:
        raise PublicationError("execution capture path is unsafe") from exc
    sums_path = _regular_file(snapshot / "SHA256SUMS")
    declared: dict[str, str] = {}
    for line in sums_path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2 or len(parts[0]) != 64 or not parts[1] or parts[1] in declared:
            raise PublicationError("captured SHA256SUMS is malformed")
        relative = Path(parts[1])
        if relative.is_absolute() or ".." in relative.parts:
            raise PublicationError("captured SHA256SUMS path escaped snapshot")
        path = _regular_file(snapshot / relative, under=snapshot)
        if stat.S_IMODE(path.stat().st_mode) != 0o400:
            raise PublicationError(f"captured immutable file mode is not 0400: {relative}")
        if _hash(path.read_bytes()) != parts[0]:
            raise PublicationError(f"captured immutable hash mismatch: {relative}")
        declared[parts[1]] = parts[0]
    if set(declared) != set(CAPTURE_IMMUTABLES):
        raise PublicationError(
            "captured SHA256SUMS set differs from executable/data-group allowlist"
        )
    analyzer_name = "tests/analyze_fig519_ihx_r2_hexe_shift.py"
    captured_analyzer = _regular_file(snapshot / analyzer_name, under=snapshot)
    executing_analyzer = _regular_file(Path(__file__).resolve(), under=ROOT)
    if captured_analyzer.read_bytes() != executing_analyzer.read_bytes():
        raise PublicationError("executing analyzer differs from captured analyzer bytes")
    output: dict[str, bytes] = {}
    for name in CAPTURE_ROOT_FILES:
        output[name] = _regular_file(capture / name, under=capture).read_bytes()
    output["captured/SHA256SUMS"] = sums_path.read_bytes()
    for name in CAPTURE_IMMUTABLES:
        output["captured/" + name] = _regular_file(
            snapshot / name, under=snapshot
        ).read_bytes()
    return output


def _artifact_record(payload: bytes, role: str) -> dict[str, object]:
    return {"sha256": _hash(payload), "bytes": len(payload), "role": role}


def _rebuild_consumed_manifest(durable: Path) -> dict[str, object]:
    capture_identities = (
        "formal_invocation.claim", "command.txt", "stdout.log", "stderr.log",
        "formal_exit_code.txt", "execution_record.json",
    )
    artifacts = [
        _authenticity_record(name, "capture/" + name, durable / name)
        for name in capture_identities
    ]
    public_by_identity = {
        "patch_audit": "patch_audit.json", "run_status": "run_status.json",
        "raw_result": "raw_result.mat",
        "candidate_curves": "candidate_curves.csv",
        "reference_curves": "reference_curves.csv",
    }
    missing: list[str] = []
    for identity, relative in RUN_AUTHENTICITY_SOURCES.items():
        public = public_by_identity[identity]
        path = durable / public
        if os.path.lexists(path):
            artifacts.append(_authenticity_record(
                identity, "run/" + relative, _regular_file(path, under=durable)
            ))
        else:
            missing.append(identity)
    try:
        exit_code = int(
            _regular_file(durable / "formal_exit_code.txt", under=durable)
            .read_text(encoding="ascii").strip()
        )
    except (UnicodeDecodeError, ValueError, PathValidationError) as exc:
        raise VerificationError("durable formal exit code cannot rebuild consumption") from exc
    return {
        "manifest_schema": "steady53_fig519_ihx_r2_hexe_a3_consumed_execution_v1",
        "attempt_id": contract.ATTEMPT_ID,
        "invocation_claimed": True,
        "formal_command": EXACT_FORMAL_COMMAND,
        "formal_process_exit_code": exit_code,
        "artifacts": sorted(artifacts, key=lambda item: item["identity"]),
        "missing_run_artifacts": sorted(missing),
    }


def _verify_durable_consumed_manifest(durable: Path) -> None:
    consumed = _read_json(
        durable / "consumed_execution_manifest.json", error_type=VerificationError
    )
    rebuilt = _rebuild_consumed_manifest(durable)
    if consumed != rebuilt:
        raise VerificationError(
            "durable consumed execution manifest does not rebuild from durable bytes"
        )


def _verify_durable_snapshot(durable: Path) -> None:
    sums = _regular_file(durable / "captured/SHA256SUMS", under=durable)
    declared: dict[str, str] = {}
    try:
        for line in sums.read_text(encoding="utf-8").splitlines():
            parts = line.split("  ", 1)
            if (len(parts) != 2 or len(parts[0]) != 64 or not parts[1] or
                    parts[1] in declared):
                raise VerificationError("durable captured SHA256SUMS is malformed")
            declared[parts[1]] = parts[0]
    except UnicodeDecodeError as exc:
        raise VerificationError("durable captured SHA256SUMS is not UTF-8") from exc
    if set(declared) != set(CAPTURE_IMMUTABLES):
        raise VerificationError("durable captured immutable set is not exact")
    for relative, digest in declared.items():
        path = _regular_file(durable / "captured" / relative, under=durable)
        if _hash(path.read_bytes()) != digest:
            raise VerificationError(f"durable captured immutable hash changed: {relative}")


def _history_payload(summary: dict[str, object]) -> dict[str, object]:
    reactor = _regular_file(REACTOR_HISTORY)
    payload = reactor.read_bytes()
    if _hash(payload) != REACTOR_HISTORY_SHA256:
        raise PublicationError("immutable A1/A2 reactor history changed")
    history = {
        "summary_schema": HISTORY_SCHEMA,
        "history_mode": "append_only_attempt_references",
        "reactor_history": {
            "path": "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json",
            "sha256": _hash(payload),
            "attempt_ids": ["20260831_A1", "20260901_A2"],
        },
        "attempts": [{"attempt_id": contract.ATTEMPT_ID, "summary": summary}],
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
    }
    return history


def _manifest_bytes(files: dict[str, bytes], history_payload: bytes) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.writer(stream, lineterminator="\n")
    writer.writerow(["path", "sha256", "bytes", "role"])
    for name in sorted(files):
        writer.writerow([name, _hash(files[name]), len(files[name]), "durable_a3_evidence"])
    writer.writerow([
        "@history/initial_state_counterfactual_history.json",
        _hash(history_payload), len(history_payload), "append_only_cross_family_history",
    ])
    return stream.getvalue().encode()


def _planned(run_dir: Path, capture_dir: Path) -> tuple[dict[str, bytes], bytes]:
    evidence = _execution_authenticity(Path(capture_dir), Path(run_dir))
    selected = Path(evidence["run_dir"])
    execution = evidence["execution_record"]
    missing_identities = set(evidence["missing_run_artifacts"])
    analyzable_run = evidence["run_exists"] and not (
        {"patch_audit", "run_status"} & missing_identities
    )
    if analyzable_run:
        result = analyze(selected)
        status = _read_json(selected / "run/run_status.json", error_type=RunStatusError)
        if not isinstance(status, dict):
            raise PublicationError("consumed run status is malformed")
        status_consistent = (
            status.get("run_steady53_case_call_count") ==
            execution["run_steady53_case_call_count"] and
            status.get("retry_count") == execution["retry_count"]
        )
        if not evidence["success_eligible"] or not status_consistent:
            result = _failure_result(
                failure_class=_failure_subclass(status, evidence),
                call_count=execution["run_steady53_case_call_count"],
                retry_count=execution["retry_count"],
                candidate_sha256=result.get("candidate_sha256"),
                error_id=str(execution.get("error_id", "")),
                error_report=str(execution.get("error_report", "")),
                exit_code=int(evidence["exit_code"]),
                missing_run_artifacts=list(evidence["missing_run_artifacts"]),
            )
    else:
        result = _failure_result(
            failure_class="pre_simulation_infrastructure",
            call_count=execution["run_steady53_case_call_count"],
            retry_count=execution["retry_count"],
            candidate_sha256=None,
            error_id=str(execution.get("error_id", "")),
            error_report=str(execution.get("error_report", "")),
            exit_code=int(evidence["exit_code"]),
            missing_run_artifacts=list(evidence["missing_run_artifacts"]),
        )
    files: dict[str, bytes] = {}
    missing: dict[str, str] = {}
    for public_name, relative in RUN_FILES.items():
        path = selected / relative
        if os.path.lexists(path):
            files[public_name] = _regular_file(path, under=selected).read_bytes()
        else:
            missing[public_name] = "not_generated_by_consumed_attempt"
    required_run = {"patch_audit.json", "run_status.json"}
    if analyzable_run and required_run & set(missing):
        raise PublicationError("consumed runner evidence lacks patch audit or run status")
    files["analysis.json"] = _json_bytes(result)
    capture_files = _capture_files(Path(capture_dir))
    files.update(capture_files)
    artifacts = {
        name: _artifact_record(payload, "captured_or_run_evidence")
        for name, payload in sorted(files.items())
    }
    summary = {
        "summary_schema": SUMMARY_SCHEMA,
        "attempt_id": contract.ATTEMPT_ID,
        "anchor_identity": contract.ANCHOR_IDENTITY,
        "single_scalar_delta_T_K": -193.6037139151003,
        "analysis": result,
        "artifacts": artifacts,
        "missing_artifacts": missing,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
        "second_anchor_used": False,
        "parameter_scan_performed": False,
        "extended_to_14000_s": False,
        "formal_model_modified": False,
    }
    files["a3_summary.json"] = _json_bytes(summary)
    history_payload = _json_bytes(_history_payload(summary))
    files[MANIFEST_NAME] = _manifest_bytes(
        {name: payload for name, payload in files.items() if name != MANIFEST_NAME},
        history_payload,
    )
    return files, history_payload


def transaction_dir(durable_dir: Path) -> Path:
    durable = Path(durable_dir)
    return durable.parent / ("." + durable.name + ".publication-transaction")


def _record(files: dict[str, bytes], history: bytes) -> bytes:
    targets = [
        {"path": name, "sha256": _hash(payload), "bytes": len(payload)}
        for name, payload in sorted(files.items())
    ]
    targets.append({"path": "@history", "sha256": _hash(history), "bytes": len(history)})
    return _json_bytes({"version": TRANSACTION_VERSION, "targets": targets})


def _publication_boundary(point: str) -> None:
    del point


def _write_exclusive(path: Path, payload: bytes) -> None:
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except OSError as exc:
        raise PublicationError(f"exclusive staging creation failed: {path}") from exc
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


@contextmanager
def _lock(parent: Path):
    fd = os.open(parent, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _stage_path(payload_root: Path, name: str) -> Path:
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise PublicationError("transaction target path is unsafe")
    return payload_root / relative


def _ensure_directory_chain(base: Path, target: Path) -> Path:
    """Create only missing real directories without following an existing link."""
    base = _real_directory(base, under=base)
    try:
        relative = target.relative_to(base)
    except ValueError as exc:
        raise PublicationError("directory target escaped its owned base") from exc
    current = base
    for part in relative.parts:
        current = current / part
        if os.path.lexists(current):
            try:
                _real_directory(current, under=base)
            except PathValidationError as exc:
                raise PublicationError(f"unsafe publication directory: {current}") from exc
        else:
            try:
                os.mkdir(current, 0o700)
            except OSError as exc:
                raise PublicationError(f"exclusive directory creation failed: {current}") from exc
            _fsync_directory(current.parent)
    return current


def _ensure_transaction(txn: Path, files: dict[str, bytes], history: bytes) -> None:
    parent = txn.parent
    if not os.path.lexists(txn):
        os.mkdir(txn, 0o700)
        _fsync_directory(parent)
    txn = _real_directory(txn, under=parent)
    if txn.stat().st_uid != os.geteuid() or txn.stat().st_mode & 0o077:
        raise PublicationError("publication transaction permissions/owner are unsafe")
    record = txn / "record.json"
    expected_record = _record(files, history)
    if not os.path.lexists(record):
        _write_exclusive(record, expected_record)
        _publication_boundary("after-stage:record.json")
    elif _regular_file(record, under=txn).read_bytes() != expected_record:
        raise PublicationError("publication transaction record conflicts")
    payload_root = txn / "payload"
    if not os.path.lexists(payload_root):
        os.mkdir(payload_root, 0o700)
    payload_root = _real_directory(payload_root, under=txn)
    staged = dict(files)
    staged["@history"] = history
    for name, payload in sorted(staged.items()):
        path = _stage_path(payload_root, name)
        _ensure_directory_chain(payload_root, path.parent)
        if not os.path.lexists(path):
            _write_exclusive(path, payload)
            _publication_boundary(f"after-stage:{name}")
        elif _regular_file(path, under=payload_root).read_bytes() != payload:
            raise PublicationError(f"staged payload conflicts: {name}")
    _fsync_directory(payload_root)
    _fsync_directory(txn)


def _commit_file(staged: Path, target: Path, payload: bytes,
                 *, target_parent: Path) -> None:
    if os.path.lexists(target):
        try:
            existing = _regular_file(target, under=target_parent)
        except PathValidationError as exc:
            raise PublicationError(f"unsafe existing publication target: {target}") from exc
        if existing.read_bytes() != payload:
            raise PublicationError(f"publication target conflicts: {target.name}")
        return
    try:
        os.link(staged, target, follow_symlinks=False)
    except OSError as exc:
        if os.path.lexists(target):
            _commit_file(staged, target, payload, target_parent=target_parent)
            return
        raise PublicationError(f"exclusive publication failed: {target}") from exc
    _fsync_directory(target.parent)


def _commit(txn: Path, files: dict[str, bytes], history: bytes,
            durable: Path, history_path: Path) -> None:
    payload_root = _real_directory(txn / "payload", under=txn)
    if not os.path.lexists(durable):
        os.mkdir(durable, 0o700)
        _fsync_directory(durable.parent)
    durable = _real_directory(durable, under=durable.parent)
    for name in sorted(files):
        if name == MANIFEST_NAME:
            continue
        staged = _regular_file(_stage_path(payload_root, name), under=payload_root)
        target = durable / name
        _ensure_directory_chain(durable, target.parent)
        _commit_file(staged, target, files[name], target_parent=durable)
        _publication_boundary(f"after-commit:{name}")
    staged_history = _regular_file(payload_root / "@history", under=payload_root)
    _commit_file(
        staged_history, history_path, history,
        target_parent=history_path.parent,
    )
    _publication_boundary("after-commit:@history")
    _publication_boundary("before-manifest-commit")
    staged_manifest = _regular_file(payload_root / MANIFEST_NAME, under=payload_root)
    _commit_file(
        staged_manifest, durable / MANIFEST_NAME, files[MANIFEST_NAME],
        target_parent=durable,
    )
    _publication_boundary("after-manifest-commit")


def _cleanup_transaction(txn: Path, files: dict[str, bytes], history: bytes) -> None:
    if not os.path.lexists(txn):
        return
    txn = _real_directory(txn, under=txn.parent)
    payload_root = _real_directory(txn / "payload", under=txn)
    staged = dict(files)
    staged["@history"] = history
    for name, payload in sorted(staged.items(), reverse=True):
        path = _regular_file(_stage_path(payload_root, name), under=payload_root)
        if path.read_bytes() != payload:
            raise PublicationError(f"refusing to clean changed staged payload: {name}")
        os.unlink(path)
    directories = sorted(
        [path for path in payload_root.rglob("*") if path.is_dir()],
        key=lambda item: len(item.parts), reverse=True,
    )
    for directory in directories:
        _real_directory(directory, under=payload_root)
        os.rmdir(directory)
    os.rmdir(payload_root)
    record = _regular_file(txn / "record.json", under=txn)
    if record.read_bytes() != _record(files, history):
        raise PublicationError("refusing to clean changed transaction record")
    os.unlink(record)
    os.rmdir(txn)
    _fsync_directory(txn.parent)


def publication_crash_points(run_dir: Path, capture_dir: Path,
                             durable_dir: Path, history_path: Path) -> list[str]:
    del durable_dir, history_path
    files, _ = _planned(Path(run_dir), Path(capture_dir))
    points = ["after-stage:record.json"]
    points.extend(f"after-stage:{name}" for name in sorted({**files, "@history": b""}))
    points.extend(f"after-commit:{name}" for name in sorted(files) if name != MANIFEST_NAME)
    points.extend(["after-commit:@history", "before-manifest-commit", "after-manifest-commit"])
    return points


def publish(run_dir: Path, capture_dir: Path, durable_dir: Path,
            history_path: Path) -> None:
    durable = Path(durable_dir)
    history_target = Path(history_path)
    if not durable.is_absolute() or not history_target.is_absolute():
        raise PublicationError("publication paths must be absolute")
    if durable.parent != history_target.parent:
        raise PublicationError("durable evidence and history must share one parent")
    try:
        parent = _real_directory(durable.parent, under=INVOCATION_ROOT)
    except PathValidationError as exc:
        raise PublicationError("publication parent is outside the invocation repository") from exc
    if history_target.name != "initial_state_counterfactual_history.json":
        raise PublicationError("history target name differs from the A3 contract")
    files, history = _planned(Path(run_dir), Path(capture_dir))
    txn = transaction_dir(durable)
    with _lock(parent):
        if os.path.lexists(durable / MANIFEST_NAME) and not os.path.lexists(txn):
            verify_only(durable, history_target)
            return
        _ensure_transaction(txn, files, history)
        _commit(txn, files, history, durable, history_target)
        verify_only(durable, history_target)
        _cleanup_transaction(txn, files, history)
    verify_only(durable, history_target)


def _manifest_rows(payload: bytes) -> list[dict[str, str]]:
    try:
        text = payload.decode("utf-8")
        reader = csv.DictReader(io.StringIO(text))
        if reader.fieldnames != ["path", "sha256", "bytes", "role"]:
            raise VerificationError("manifest schema mismatch")
        rows = list(reader)
    except (UnicodeDecodeError, csv.Error) as exc:
        raise VerificationError("manifest is malformed") from exc
    if len({row.get("path") for row in rows}) != len(rows):
        raise VerificationError("manifest paths are duplicated")
    return rows


def _validate_summary(summary: object) -> dict[str, object]:
    if not isinstance(summary, dict):
        raise VerificationError("A3 durable summary must be an object")
    fixed = {
        "summary_schema": SUMMARY_SCHEMA,
        "attempt_id": contract.ATTEMPT_ID,
        "anchor_identity": contract.ANCHOR_IDENTITY,
        "single_scalar_delta_T_K": -193.6037139151003,
        "paper_reproduced": False,
        "author_initial_state_identified": False,
        "formal_promotion": False,
        "second_anchor_used": False,
        "parameter_scan_performed": False,
        "extended_to_14000_s": False,
        "formal_model_modified": False,
    }
    for key, expected in fixed.items():
        if summary.get(key) != expected:
            raise VerificationError(f"A3 summary fixed field mismatch: {key}")
    try:
        validate_analysis(summary.get("analysis"))
    except A3AnalysisError as exc:
        raise VerificationError("A3 summary analysis is invalid") from exc
    artifacts = summary.get("artifacts")
    missing = summary.get("missing_artifacts")
    expected = set(PUBLICATION_DATA_FILES) - {"a3_summary.json"}
    if not isinstance(artifacts, dict) or not isinstance(missing, dict):
        raise VerificationError("A3 summary artifact/missing sets are absent")
    if (set(artifacts) & set(missing) or set(artifacts) | set(missing) != expected or
            any(value != "not_generated_by_consumed_attempt"
                for value in missing.values()) or
            set(missing) - set(RUN_FILES)):
        raise VerificationError("A3 summary artifact/missing sets are not exact")
    if (summary["analysis"].get("gate_failure_class") !=
            "pre_simulation_infrastructure" and
            {"patch_audit.json", "run_status.json"} & set(missing)):
        raise VerificationError("A3 summary is missing required runner audit evidence")
    return summary


def _validate_history(history: object, summary: dict[str, object]) -> dict[str, object]:
    if not isinstance(history, dict) or set(history) != {
        "summary_schema", "history_mode", "reactor_history", "attempts",
        "paper_reproduced", "author_initial_state_identified", "formal_promotion",
    }:
        raise VerificationError("cross-family history schema is not exact")
    if (history.get("summary_schema") != HISTORY_SCHEMA or
            history.get("history_mode") != "append_only_attempt_references" or
            any(history.get(key) is not False for key in PROMOTION)):
        raise VerificationError("cross-family history fixed fields changed")
    reactor = history.get("reactor_history")
    current = _regular_file(REACTOR_HISTORY).read_bytes()
    if (_hash(current) != REACTOR_HISTORY_SHA256 or reactor != {
        "path": "data/provenance/steady53/fig5_19/reactor_ic_counterfactual.json",
        "sha256": REACTOR_HISTORY_SHA256,
        "attempt_ids": ["20260831_A1", "20260901_A2"],
    }):
        raise VerificationError("immutable A1/A2 history reference changed")
    if history.get("attempts") != [{"attempt_id": contract.ATTEMPT_ID, "summary": summary}]:
        raise VerificationError("A3 append-only attempt reference changed")
    return history


def verify_only(durable_dir: Path, history_path: Path) -> None:
    expected_history = (
        Path(durable_dir).parent / "initial_state_counterfactual_history.json"
    )
    if Path(history_path) != expected_history:
        raise VerificationError("history path is not the canonical durable sibling")
    try:
        durable = _real_directory(Path(durable_dir), under=INVOCATION_ROOT)
        history_file = _regular_file(Path(history_path), under=durable.parent)
        manifest_path = _regular_file(durable / MANIFEST_NAME, under=durable)
        summary_path = _regular_file(durable / "a3_summary.json", under=durable)
    except PathValidationError as exc:
        raise VerificationError("durable A3 publication path is unsafe") from exc
    try:
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        history = json.loads(history_file.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise VerificationError("durable A3 JSON is malformed") from exc
    summary = _validate_summary(summary)
    _validate_history(history, summary)
    artifact_names = set(summary["artifacts"])
    expected_names = artifact_names | {"a3_summary.json", MANIFEST_NAME}
    actual_names = {
        path.relative_to(durable).as_posix()
        for path in durable.rglob("*") if path.is_file()
    }
    if actual_names != expected_names:
        raise VerificationError("durable A3 file set is not exact")
    if any(path.is_symlink() for path in durable.rglob("*")):
        raise VerificationError("durable A3 tree contains a symlink")
    files: dict[str, bytes] = {}
    for name in sorted(artifact_names | {"a3_summary.json"}):
        files[name] = _regular_file(durable / name, under=durable).read_bytes()
    if files["analysis.json"] != _json_bytes(summary["analysis"]):
        raise VerificationError("durable analysis differs from summary")
    try:
        _verify_durable_snapshot(durable)
        _verify_durable_consumed_manifest(durable)
        _verify_durable_scientific_derivation(durable, summary["analysis"])
    except A3AnalysisError as exc:
        if isinstance(exc, VerificationError):
            raise
        raise VerificationError("durable scientific derivation is invalid") from exc
    artifacts = summary["artifacts"]
    for name in artifact_names:
        expected = _artifact_record(files[name], "captured_or_run_evidence")
        if artifacts.get(name) != expected:
            raise VerificationError(f"A3 summary artifact hash changed: {name}")
    expected_manifest = _manifest_bytes(
        {name: payload for name, payload in files.items() if name != MANIFEST_NAME},
        history_file.read_bytes(),
    )
    if manifest_path.read_bytes() != expected_manifest:
        raise VerificationError("manifest-last A3 binding changed")
    rows = _manifest_rows(manifest_path.read_bytes())
    if len(rows) != len(files) + 1:
        raise VerificationError("manifest row count is not exact")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--capture-dir", type=Path)
    parser.add_argument("--durable-dir", type=Path, required=True)
    parser.add_argument("--history-path", type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    def absolute(path: Path | None) -> Path | None:
        if path is None or path.is_absolute():
            return path
        return INVOCATION_ROOT / path
    durable = absolute(args.durable_dir)
    history = absolute(args.history_path)
    if args.verify_only:
        verify_only(durable, history)
        print("FIG519_IHX_R2_HEXE_A3_VERIFY_PASS")
        return
    run_dir = absolute(args.run_dir)
    capture_dir = absolute(args.capture_dir)
    if run_dir is None or capture_dir is None:
        raise SystemExit("--run-dir and --capture-dir are required for publication")
    publish(run_dir, capture_dir, durable, history)
    verify_only(durable, history)
    try:
        published = json.loads(
            _regular_file(durable / "analysis.json", under=durable).read_text()
        )
    except (UnicodeDecodeError, json.JSONDecodeError, PathValidationError) as exc:
        raise VerificationError("published durable analysis is unreadable") from exc
    published = validate_analysis(published)
    print("FIG519_IHX_R2_HEXE_A3=" + str(published["conclusion"]))


if __name__ == "__main__":
    main()
