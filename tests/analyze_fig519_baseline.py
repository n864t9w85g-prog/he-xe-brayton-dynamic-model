#!/usr/bin/env python3
"""Publish and describe the existing, flat Figure 5.19 power baseline.

This is a preservation and offline comparison tool.  It never runs MATLAB or a
model, and it intentionally derives electrical power from the two shaft traces.
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
from pathlib import Path

try:  # Works both as ``tests.*`` and as an executable in ``tests/``.
    from tests import digitize_fig519 as paper
except ModuleNotFoundError:  # pragma: no cover - exercised by CLI test
    import digitize_fig519 as paper


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "data/provenance/steady53/fig5_19"
SOURCE_DIR = ROOT / "tmp/steady53_curves_20260828/results"
BASELINE_DIR = OUTPUT / paper.BASELINE_LAYER_DIR
SOURCE_HASHES = {
    "baseline.mat": "18975fc912ed2af87f325769d4be9ab54f4ad0c091f925e4cda5df497aa55698",
    "baseline_P_sw.csv": "288a9b031d31f8168517ea30d06f712d72c4d1dc31fd911f0a266aaa3023999f",
    "baseline_WT_sw.csv": "28b852e9b997af51a860905e53da096821ddfbdd310857d16e9df0761ca2ab23",
    "baseline_Wc_sw.csv": "f44a9bca2c006780f287e4f3a7199f63d26348cc18ad261d4ad89570b0e9ad5c",
}
PAPER_SOURCE_SHA256 = "770d193eaca80742ef5ece0ef5ba6d0bc20ad7aaa8ca2ac9b60a4799d1f0a1e2"
PAPER_PDF_SHA256 = "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"
PAPER_ETA = 0.98
HISTORICAL_METRIC_ETA = 0.96527
INITIALIZATION_AUDIT_NAME = "initialization_audit.json"


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe(path: Path) -> Path:
    path = Path(path)
    if ".." in path.parts:
        raise RuntimeError("refusing lexical path escape")
    probe = Path(path.anchor)
    for part in path.parts[1:]:
        probe /= part
        if os.path.lexists(probe):
            mode = os.lstat(probe).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError("refusing symlinked path")
            if probe != path and not stat.S_ISDIR(mode):
                raise RuntimeError("output parent is not a directory")
    resolved = path.resolve(strict=False)
    if ROOT.resolve() not in resolved.parents and resolved != ROOT.resolve():
        raise RuntimeError("path must remain under the repository root")
    return resolved


def _literal_source_bytes(source_dir: Path) -> dict[str, bytes]:
    source_dir = _safe(source_dir)
    if source_dir.is_symlink() or not source_dir.is_dir():
        raise RuntimeError("contracted baseline source directory is unsafe")
    payloads = {}
    for name, digest in SOURCE_HASHES.items():
        path = source_dir / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"baseline source is missing: {name}")
        payload = path.read_bytes()
        if _hash(payload) != digest:
            raise RuntimeError(f"baseline source hash does not match contract: {name}")
        payloads[name] = payload
    return payloads


def _read_series(payload: bytes, name: str) -> tuple[list[float], list[float]]:
    rows = list(csv.reader(io.StringIO(payload.decode("utf-8"), newline="")))
    if not rows or any(len(row) != 2 for row in rows):
        raise RuntimeError(f"{name} must be a headerless two-column CSV")
    try:
        times = [float(row[0]) for row in rows]
        values = [float(row[1]) for row in rows]
    except ValueError as exc:
        raise RuntimeError(f"{name} has non-numeric values") from exc
    if (len(rows) < 2 or any(not math.isfinite(v) for v in times + values) or
            any(right <= left for left, right in zip(times, times[1:]))):
        raise RuntimeError(f"{name} must have at least two finite samples with strictly increasing time")
    return times, values


def _series_metrics(times: list[float], values: list[float]) -> dict[str, object]:
    high, low = max(values), min(values)
    peak_index, valley_index = values.index(high), values.index(low)
    return {
        "units": "W", "samples": len(values), "start_W": values[0], "end_W": values[-1],
        "peak_to_peak_W": high - low, "peak_W": high, "peak_time_s": times[peak_index],
        "valley_W": low, "valley_time_s": times[valley_index],
        "peak_direction": "rise" if peak_index >= valley_index else "fall",
        "valley_direction": "fall" if valley_index >= peak_index else "rise",
    }


def _interpolate(times: list[float], values: list[float], query: float) -> float:
    index = bisect_left(times, query)
    if index < len(times) and times[index] == query:
        return values[index]
    if index == 0 or index == len(times):
        raise RuntimeError("paper comparison time is outside model series")
    left_t, right_t = times[index - 1], times[index]
    if right_t == left_t:
        return values[index]
    fraction = (query - left_t) / (right_t - left_t)
    return values[index - 1] + fraction * (values[index] - values[index - 1])


def _paper_rows(path: Path) -> dict[str, list[tuple[float, float]]]:
    with path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))
    grouped = {panel: [] for panel in "abcd"}
    seen: set[tuple[str, float]] = set()
    for row in rows:
        panel = row.get("panel_id")
        if panel not in grouped:
            raise RuntimeError("paper points have an unregistered panel")
        try:
            time_s, power_kW = float(row["time_s"]), float(row["power_kW"])
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError("paper points have non-numeric required values") from exc
        if not (math.isfinite(time_s) and math.isfinite(power_kW) and 0.0 <= time_s <= 500.0):
            raise RuntimeError("paper points are invalid")
        if (panel, time_s) in seen:
            raise RuntimeError("paper points have duplicate panel-time rows")
        seen.add((panel, time_s))
        grouped[panel].append((time_s, power_kW))
    if any(len(points) != 15 for points in grouped.values()):
        raise RuntimeError("each paper panel must have 15 points")
    return grouped


def _comparison(times: list[float], values: list[float], points: list[tuple[float, float]]) -> dict[str, object]:
    model_W = [_interpolate(times, values, point[0]) for point in points]
    errors_kW = [model / 1000.0 - point[1] for model, point in zip(model_W, points)]
    squares = [error * error for error in errors_kW]
    return {
        "comparison_units": {"model": "W", "paper": "kW"}, "paper_points": len(points),
        "window_s": [0.0, 500.0], "rmse_kW": math.sqrt(sum(squares) / len(squares)),
        "max_abs_error_kW": max(abs(error) for error in errors_kW),
        "start_error_kW": errors_kW[0], "end_error_kW": errors_kW[-1],
        "squared_error_contribution_kW2": sum(squares),
    }


def _contract() -> dict[str, object]:
    return {
        "figure": "5.19", "paper_reproduced": False, "formal_promotion": False,
        "signals": {
            "reactor": {"model_signal": "P_sw", "kind": "direct_workspace_signal", "api_trace_status": "required_in_task_6"},
            "turbine": {"model_signal": "WT_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"},
            "compressor": {"model_signal": "Wc_sw", "kind": "direct_component_power", "api_trace_status": "required_in_task_6"},
            "electrical_paper_eta": {"formula": "0.98*(WT_sw-Wc_sw)", "kind": "offline_derived", "direct_generator_signal": None},
            "electrical_historical_metric": {"formula": "0.96527*(WT_sw-Wc_sw)", "kind": "historical_offline_derived", "accepted_for_fig519": False},
        },
    }


def _validate_initialization_audit(audit: dict[str, object]) -> None:
    """Validate only fixed Task 6 facts needed by the durable publication."""
    if not isinstance(audit, dict):
        raise RuntimeError("initialization audit must be a JSON object")
    fixed = {
        "audit_schema": "steady53_fig519_initialization_v1",
        "model_sha256": "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        "source_hash_after": "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391",
        "source_hash_unchanged": True,
        "state_count": 40,
        "reference_final_time_s": 500,
        "reference_success": True,
        "reference_run_reason": "missing direct state and derivative evidence in prior saved baseline",
        "repeated_prior_experiment": False,
        "direct_generator_signal_found": False,
        "paper_reproduced": False,
        "formal_promotion": False,
    }
    for key, expected in fixed.items():
        if audit.get(key) != expected:
            raise RuntimeError(f"initialization audit fixed field mismatch: {key}")
    protected = audit.get("protected_manifest")
    if not isinstance(protected, dict) or any(protected.get(key) != value for key, value in
            {"row_count": 34, "resolved_count": 34, "unresolved_count": 0}.items()):
        raise RuntimeError("initialization audit protected manifest is incomplete")
    runtime = audit.get("runtime_dependency_contract")
    if (not isinstance(runtime, dict) or runtime.get("dependency_count") != 9 or
            runtime.get("all_paths_durable") is not True or
            not isinstance(runtime.get("dependencies"), list) or
            len(runtime["dependencies"]) != 9 or
            any(item.get("is_durable") is not True for item in runtime["dependencies"])):
        raise RuntimeError("initialization audit durable runtime contract is incomplete")
    if not isinstance(audit.get("state_inventory"), list) or len(audit["state_inventory"]) != 40:
        raise RuntimeError("initialization audit state inventory is incomplete")
    for section, flag in (("boundary_contract", "all_inputs_classified"),
                          ("initial_residuals", "all_items_accounted_for"),
                          ("flat_start_explanation", "has_state_evidence"),
                          ("flat_start_explanation", "has_signal_path_evidence")):
        value = audit.get(section)
        if not isinstance(value, dict) or value.get(flag) is not True:
            raise RuntimeError(f"initialization audit section is incomplete: {section}.{flag}")
    solver = audit.get("solver_contract")
    if not isinstance(solver, dict) or not solver.get("solver_name") or solver.get("stop_time_dependency_checked") is not True:
        raise RuntimeError("initialization audit solver contract is incomplete")
    paths = audit.get("power_signal_paths")
    expected_status = {
        "reactor": "verified_by_official_api", "turbine": "verified_by_official_api",
        "compressor": "verified_by_official_api", "electrical": "no_direct_generator_signal_found",
    }
    if not isinstance(paths, dict) or paths.get("direct_generator_signal_found") is not False:
        raise RuntimeError("initialization audit power paths are incomplete")
    for name, status in expected_status.items():
        if not isinstance(paths.get(name), dict) or paths[name].get("status") != status:
            raise RuntimeError(f"initialization audit power path mismatch: {name}")
    if paths["turbine"].get("block") != "final_steady_24a/TAC/Turbine" or paths["turbine"].get("output_port") != 4:
        raise RuntimeError("initialization audit turbine path mismatch")
    if paths["compressor"].get("block") != "final_steady_24a/TAC/Compressor" or paths["compressor"].get("output_port") != 2:
        raise RuntimeError("initialization audit compressor path mismatch")


def contract_from_initialization(audit: dict[str, object]) -> dict[str, object]:
    _validate_initialization_audit(audit)
    paths = audit["power_signal_paths"]
    return {
        "figure": "5.19", "paper_reproduced": False, "formal_promotion": False,
        "signals": {
            "reactor": {
                "model_signal": "P_sw", "kind": "direct_workspace_signal",
                "status": "verified_by_official_api",
                "api_workspace_block": paths["reactor"]["workspace_block"],
                "api_upstream_block": paths["reactor"]["upstream_block"],
                "api_output_port": paths["reactor"]["upstream_output_port"],
            },
            "turbine": {
                "model_signal": "WT_sw", "kind": "direct_component_power",
                "status": "verified_by_official_api", "api_block_path": paths["turbine"]["block"],
                "api_output_port": paths["turbine"]["output_port"],
            },
            "compressor": {
                "model_signal": "Wc_sw", "kind": "direct_component_power",
                "status": "verified_by_official_api", "api_block_path": paths["compressor"]["block"],
                "api_output_port": paths["compressor"]["output_port"],
            },
            "electrical_paper_eta": {
                "formula": "0.98*(WT_sw-Wc_sw)", "kind": "offline_derived",
                "direct_generator_signal": None, "status": "no_direct_generator_signal_found",
            },
            "electrical_historical_metric": {
                "formula": "0.96527*(WT_sw-Wc_sw)", "kind": "historical_offline_derived",
                "accepted_for_fig519": False,
            },
        },
    }


def _audit_from_output(output: Path) -> tuple[dict[str, object] | None, bytes | None]:
    path = output / INITIALIZATION_AUDIT_NAME
    if not os.path.lexists(path):
        return None, None
    if path.is_symlink() or not path.is_file():
        raise RuntimeError("initialization audit path is unsafe")
    payload = path.read_bytes()
    try:
        audit = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError("initialization audit is not valid JSON") from exc
    _validate_initialization_audit(audit)
    return audit, payload


def analyze(data_dir: Path | None = None, paper_points: Path | None = None) -> tuple[dict[str, object], dict[str, object]]:
    """Compute only descriptive evidence from hash-contracted CSV series."""
    payloads = _literal_source_bytes(data_dir or SOURCE_DIR)
    time_p, reactor = _read_series(payloads["baseline_P_sw.csv"], "baseline_P_sw.csv")
    time_t, turbine = _read_series(payloads["baseline_WT_sw.csv"], "baseline_WT_sw.csv")
    time_c, compressor = _read_series(payloads["baseline_Wc_sw.csv"], "baseline_Wc_sw.csv")
    if time_p != time_t or time_p != time_c or time_p[-1] != 14000.0:
        raise RuntimeError("power series must have identical time vectors ending at 14000 s")
    shaft_net = [wt - wc for wt, wc in zip(turbine, compressor)]
    electrical = [PAPER_ETA * value for value in shaft_net]
    historical = [HISTORICAL_METRIC_ETA * value for value in shaft_net]
    points = _paper_rows(paper_points or (OUTPUT / "paper_points.csv"))
    signals = {"reactor": reactor, "turbine": turbine, "compressor": compressor,
               "electrical_paper_eta": electrical, "electrical_historical_metric": historical}
    panel_to_signal = {"a": "reactor", "b": "turbine", "c": "compressor", "d": "electrical_paper_eta"}
    comparisons = {signal: _comparison(time_p, signals[signal], points[panel])
                   for panel, signal in panel_to_signal.items()}
    metrics = {
        "figure": "5.19", "final_time_s": time_p[-1], "paper_eta": PAPER_ETA,
        "historical_metric_eta": HISTORICAL_METRIC_ETA, "paper_reproduced": False,
        "formal_promotion": False, "signals": {name: _series_metrics(time_p, values) for name, values in signals.items()},
        "comparisons": comparisons,
        "final_definition_gap_kW": abs(electrical[-1] - historical[-1]) / 1000.0,
        "hashes": {"paper_source_page_sha256": PAPER_SOURCE_SHA256, "paper_pdf_sha256": PAPER_PDF_SHA256,
                   "baseline_source_sha256": SOURCE_HASHES, "model_baseline_sha256": SOURCE_HASHES},
    }
    return metrics, _contract()


def _json_bytes(value: dict[str, object]) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode()


def _expected_durable(output: Path) -> tuple[dict[str, bytes], dict[str, bytes]]:
    baseline = {name: (output / paper.BASELINE_LAYER_DIR / name).read_bytes() for name in paper.BASELINE_LAYER_NAMES}
    if {name: _hash(payload) for name, payload in baseline.items()} != SOURCE_HASHES:
        raise RuntimeError("durable baseline hash does not match contract")
    metrics, contract = analyze(output / paper.BASELINE_LAYER_DIR, output / "paper_points.csv")
    audit, _ = _audit_from_output(output)
    if audit is not None:
        contract = contract_from_initialization(audit)
    return baseline, {"baseline_metrics.json": _json_bytes(metrics), "signal_contract.json": _json_bytes(contract)}


def _roles() -> dict[str, tuple[str, str]]:
    roles = {
        "source_page_106.png": ("contracted source", "paper-106-only"),
        "paper_points.csv": ("generated digitization", "paper-106-only"),
        "provenance.json": ("generated provenance", "paper-106-only"),
        "digitization_overlay.png": ("generated overlay", "paper-106-only"),
        "README.md": ("generated documentation", "paper-106-only"),
        "baseline_metrics.json": ("generated baseline analysis", "flat-model-baseline"),
        "signal_contract.json": ("generated signal contract", "flat-model-baseline"),
        "initialization_audit.json": ("generated API initialization audit", "unmodified-500s-reference"),
    }
    roles.update({f"{paper.BASELINE_LAYER_DIR}/{name}": ("contracted baseline source", "flat-model-baseline")
                  for name in paper.BASELINE_LAYER_NAMES})
    return roles


def _unified_manifest(output: Path, baseline: dict[str, bytes], generated: dict[str, bytes]) -> bytes:
    paper_bytes = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries = dict(paper_bytes)
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload for name, payload in baseline.items()})
    entries.update(generated)
    _, audit_payload = _audit_from_output(output)
    if audit_payload is not None:
        entries[INITIALIZATION_AUDIT_NAME] = audit_payload
    return paper.manifest_bytes(entries, _roles())


def _write_exclusive(path: Path, payload: bytes) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    try:
        offset = 0
        while offset < len(payload):
            offset += os.write(fd, payload[offset:])
        os.fsync(fd)
    finally:
        os.close(fd)


TRANSACTION_VERSION = 1
_DELTA_PATHS = frozenset(
    [f"{paper.BASELINE_LAYER_DIR}/{name}" for name in paper.BASELINE_LAYER_NAMES]
    + ["baseline_metrics.json", "signal_contract.json", "manifest.csv"]
)


def _publication_boundary(point: str) -> None:
    """Named I/O boundary retained solely for deterministic failure-injection tests."""
    del point


def _fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _transaction_dir(output: Path) -> Path:
    return output.parent / (output.name + ".task5-transaction")


@contextmanager
def _publication_lock(output: Path):
    """Serialize this tool's publishers; hostile same-user path swaps are out of scope."""
    fd = os.open(output, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _transaction_record(payloads: dict[str, bytes]) -> bytes:
    data = {"version": TRANSACTION_VERSION, "state": "prepared", "targets": [
        {"path": path, "bytes": len(payloads[path]), "sha256": _hash(payloads[path])}
        for path in sorted(payloads)]}
    return _json_bytes(data)


def _require_delta_shape(payloads: dict[str, bytes]) -> None:
    if set(payloads) != _DELTA_PATHS or any(not isinstance(payload, bytes) for payload in payloads.values()):
        raise RuntimeError("Task 5 transaction delta is not the registered exact set")


def _planned_delta(output: Path, source_dir: Path) -> dict[str, bytes]:
    """Precompute every Task 5 target before creating a transaction inode."""
    baseline = _literal_source_bytes(source_dir)
    metrics, contract = analyze(source_dir, output / "paper_points.csv")
    audit, audit_payload = _audit_from_output(output)
    if audit is not None:
        contract = contract_from_initialization(audit)
    generated = {"baseline_metrics.json": _json_bytes(metrics), "signal_contract.json": _json_bytes(contract)}
    paper_bytes = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries = dict(paper_bytes)
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload for name, payload in baseline.items()})
    entries.update(generated)
    if audit_payload is not None:
        entries[INITIALIZATION_AUDIT_NAME] = audit_payload
    delta = {f"{paper.BASELINE_LAYER_DIR}/{name}": payload for name, payload in baseline.items()}
    delta.update(generated)
    delta["manifest.csv"] = paper.manifest_bytes(entries, _roles())
    _require_delta_shape(delta)
    return delta


def _check_regular_payload(path: Path, payload: bytes, label: str) -> None:
    if path.is_symlink() or not path.is_file() or path.read_bytes() != payload:
        raise RuntimeError(f"transaction conflict: {label}")


def _final_has_payload(output: Path, relative: str, payload: bytes) -> bool:
    target = output / relative
    if not os.path.lexists(target):
        return False
    if target.is_symlink() or not target.is_file():
        return False
    return target.read_bytes() == payload


def _final_layer_state(output: Path, payloads: dict[str, bytes]) -> bool:
    layer = output / paper.BASELINE_LAYER_DIR
    if not os.path.lexists(layer):
        return False
    if layer.is_symlink() or not layer.is_dir():
        raise RuntimeError("transaction conflict: final baseline layer")
    if {entry.name for entry in layer.iterdir()} != set(paper.BASELINE_LAYER_NAMES):
        raise RuntimeError("transaction conflict: final baseline layer entries")
    for name in paper.BASELINE_LAYER_NAMES:
        _check_regular_payload(layer / name, payloads[f"{paper.BASELINE_LAYER_DIR}/{name}"], f"final {name}")
    return True


def _is_allowed_manifest_predecessor(output: Path, payload: bytes) -> bool:
    paper_bytes = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    return payload == paper._manifest(paper_bytes)


def _manifest_is_expected_or_allowed(output: Path, expected: bytes) -> bool:
    target = output / "manifest.csv"
    if not os.path.lexists(target):
        return False
    if target.is_symlink() or not target.is_file():
        raise RuntimeError("transaction conflict: manifest")
    payload = target.read_bytes()
    if payload == expected:
        return True
    if not _is_allowed_manifest_predecessor(output, payload):
        raise RuntimeError("transaction conflict: manifest predecessor")
    return False


def _pending_targets(output: Path, payloads: dict[str, bytes]) -> set[str]:
    pending: set[str] = set()
    if not _final_layer_state(output, payloads):
        pending.update(f"{paper.BASELINE_LAYER_DIR}/{name}" for name in paper.BASELINE_LAYER_NAMES)
    for name in ("baseline_metrics.json", "signal_contract.json"):
        target = output / name
        if os.path.lexists(target):
            _check_regular_payload(target, payloads[name], f"final {name}")
        else:
            pending.add(name)
    if not _manifest_is_expected_or_allowed(output, payloads["manifest.csv"]):
        pending.add("manifest.csv")
    return pending


def _validate_transaction_structure(txn: Path, record: bytes) -> Path:
    if txn.is_symlink() or not txn.is_dir():
        raise RuntimeError("transaction directory is unsafe")
    txn_stat = txn.stat()
    if txn_stat.st_uid != os.geteuid() or txn_stat.st_mode & 0o077:
        raise RuntimeError("transaction directory ownership is unsafe")
    if {entry.name for entry in txn.iterdir()} != {"record.json", "payload"}:
        raise RuntimeError("transaction has unexpected entries")
    record_path = txn / "record.json"
    _check_regular_payload(record_path, record, "transaction record")
    payload_root = txn / "payload"
    if payload_root.is_symlink() or not payload_root.is_dir():
        raise RuntimeError("transaction payload directory is unsafe")
    allowed_dirs = {Path("payload"), Path("payload") / paper.BASELINE_LAYER_DIR}
    allowed_files = {Path("record.json")} | {Path("payload") / relative for relative in _DELTA_PATHS}
    for path in txn.rglob("*"):
        relative = path.relative_to(txn)
        if path.is_symlink() or (path.is_dir() and relative not in allowed_dirs) or (path.is_file() and relative not in allowed_files):
            raise RuntimeError("transaction has unexpected or unsafe entries")
        if not path.is_dir() and not path.is_file():
            raise RuntimeError("transaction has nonregular entries")
    return payload_root


def _staged_paths(payload_root: Path) -> set[str]:
    return {str(path.relative_to(payload_root)) for path in payload_root.rglob("*") if path.is_file()}


def _validate_staged_payloads(payload_root: Path, pending: set[str], payloads: dict[str, bytes], output: Path) -> None:
    staged = _staged_paths(payload_root)
    retained_links = {name for name in ("baseline_metrics.json", "signal_contract.json")
                      if name in staged and _final_has_payload(output, name, payloads[name])}
    if not pending <= staged or staged - (pending | retained_links):
        raise RuntimeError("transaction payload set is incomplete or unexpected")
    for relative in staged:
        _check_regular_payload(payload_root / relative, payloads[relative], f"staged {relative}")
    baseline_staged = {f"{paper.BASELINE_LAYER_DIR}/{name}" for name in paper.BASELINE_LAYER_NAMES} & staged
    if baseline_staged and baseline_staged != {f"{paper.BASELINE_LAYER_DIR}/{name}" for name in paper.BASELINE_LAYER_NAMES}:
        raise RuntimeError("transaction baseline layer is only partially staged")
    layer = payload_root / paper.BASELINE_LAYER_DIR
    if bool(baseline_staged) != layer.exists():
        raise RuntimeError("transaction baseline staging directory is inconsistent")


def _birth_transaction(txn: Path, payloads: dict[str, bytes], output: Path, record: bytes) -> None:
    """Build a complete private skeleton before exposing the canonical name."""
    pending = _pending_targets(output, payloads)
    init = Path(tempfile.mkdtemp(prefix=txn.name.replace("transaction", "init") + "-", dir=txn.parent))
    _publication_boundary("init-mkdir-after")
    _publication_boundary("transaction-record")
    _publication_boundary("record-write-before")
    _write_exclusive(init / "record.json", record)
    _publication_boundary("record-write-after")
    _publication_boundary("payload-mkdir-before")
    payload_root = init / "payload"
    os.mkdir(payload_root, 0o700)
    _publication_boundary("payload-mkdir-after")
    baseline_pending = {f"{paper.BASELINE_LAYER_DIR}/{name}" for name in paper.BASELINE_LAYER_NAMES} & pending
    if baseline_pending:
        os.mkdir(payload_root / paper.BASELINE_LAYER_DIR, 0o700)
    ordered = sorted(pending)
    for index, relative in enumerate(ordered):
        if relative.startswith(f"{paper.BASELINE_LAYER_DIR}/"):
            _publication_boundary("staged-baseline")
        label = "first" if index == 0 else "last" if index == len(ordered) - 1 else "middle"
        _publication_boundary(f"staged-{label}-before")
        _write_exclusive(payload_root / relative, payloads[relative])
        _publication_boundary(f"staged-{label}-after")
    _validate_transaction_structure(init, record)
    _validate_staged_payloads(payload_root, pending, payloads, output)
    if (payload_root / paper.BASELINE_LAYER_DIR).exists():
        _fsync_directory(payload_root / paper.BASELINE_LAYER_DIR)
    _fsync_directory(payload_root)
    _fsync_directory(init)
    _publication_boundary("canonical-rename-before")
    if os.path.lexists(txn):
        raise RuntimeError("canonical transaction appeared during initialization")
    # The directory lock serializes this tool's publishers.  An adversarial
    # same-user replacement between this check and rename is outside Task 4/5's
    # threat model; verify immediately after the rename before committing data.
    os.rename(init, txn)
    _fsync_directory(txn.parent)
    _publication_boundary("canonical-rename-after")


def _ensure_safe_transaction(txn: Path, payloads: dict[str, bytes], output: Path) -> None:
    _require_delta_shape(payloads)
    record = _transaction_record(payloads)
    if not os.path.lexists(txn):
        _birth_transaction(txn, payloads, output, record)
    payload_root = _validate_transaction_structure(txn, record)
    _validate_staged_payloads(payload_root, _pending_targets(output, payloads), payloads, output)


def _commit_target(staged: Path, target: Path, payload: bytes, replace: bool = False) -> None:
    """Commit one already-hashed target; manifest is the only replaceable marker."""
    if os.path.lexists(target):
        if not replace:
            _check_regular_payload(target, payload, f"final {target.name}")
            return
        if _final_has_payload(target.parent, target.name, payload):
            return
    if staged.is_symlink() or not staged.is_file():
        raise RuntimeError(f"transaction is missing staged target: {target.name}")
    if replace:
        os.replace(staged, target)
    else:
        try:
            os.link(staged, target, follow_symlinks=False)
        except FileExistsError:
            _check_regular_payload(target, payload, f"concurrently committed {target.name}")
            return
    _check_regular_payload(target, payload, f"committed {target.name}")
    _fsync_directory(target.parent)


def _cleanup_transaction(txn: Path, output: Path, payloads: dict[str, bytes]) -> None:
    """Remove only the exact, verified transaction left after a full commit."""
    payload_root = txn / "payload"
    _validate_transaction_structure(txn, _transaction_record(payloads))
    for name in ("baseline_metrics.json", "signal_contract.json"):
        staged = payload_root / name
        if os.path.lexists(staged):
            _check_regular_payload(staged, payloads[name], f"cleanup staged {name}")
            _check_regular_payload(output / name, payloads[name], f"cleanup final {name}")
            os.unlink(staged)
    staged_layer = payload_root / paper.BASELINE_LAYER_DIR
    if os.path.lexists(staged_layer):
        if staged_layer.is_symlink() or not staged_layer.is_dir():
            raise RuntimeError("transaction cleanup ownership cannot be guaranteed")
        os.rmdir(staged_layer)
    if os.path.lexists(payload_root):
        if payload_root.is_symlink() or not payload_root.is_dir() or any(payload_root.iterdir()):
            raise RuntimeError("transaction cleanup ownership cannot be guaranteed")
        os.rmdir(payload_root)
    record = txn / "record.json"
    if not record.is_file() or record.is_symlink() or {entry.name for entry in txn.iterdir()} != {"record.json"}:
        raise RuntimeError("transaction cleanup ownership cannot be guaranteed")
    # At this point no payload can be discarded; the record is the only owned
    # entry left and its parent contains no unrecognised name.
    os.unlink(record)
    try:
        os.rmdir(txn)
    except OSError as exc:
        raise RuntimeError("transaction cleanup ownership cannot be guaranteed") from exc
    _fsync_directory(txn.parent)


def _recover_or_publish_delta(output: Path, payloads: dict[str, bytes]) -> None:
    with _publication_lock(output):
        txn = _transaction_dir(output)
        _ensure_safe_transaction(txn, payloads, output)
        staged_root = txn / "payload"
        layer_target = output / paper.BASELINE_LAYER_DIR
        staged_layer = staged_root / paper.BASELINE_LAYER_DIR
        if not _final_layer_state(output, payloads):
            _publication_boundary("baseline-layer-rename")
            os.rename(staged_layer, layer_target)
            _fsync_directory(output)
            for name in paper.BASELINE_LAYER_NAMES:
                _check_regular_payload(layer_target / name, payloads[f"{paper.BASELINE_LAYER_DIR}/{name}"], f"committed {name}")
        for name in ("baseline_metrics.json", "signal_contract.json"):
            _publication_boundary("baseline-metrics-commit" if name == "baseline_metrics.json" else "signal-contract-commit")
            _commit_target(staged_root / name, output / name, payloads[name])
        # Manifest is deliberately last: before this replace, verify-only rejects
        # the partial tree; after it, it is the complete publication marker.
        _publication_boundary("manifest-commit")
        manifest_target = output / "manifest.csv"
        if not _manifest_is_expected_or_allowed(output, payloads["manifest.csv"]):
            _commit_target(staged_root / "manifest.csv", manifest_target, payloads["manifest.csv"], replace=True)
        _cleanup_transaction(txn, output, payloads)


def write_manifest(output: Path, rows: list[dict[str, str]]) -> None:
    """Test helper: atomically write caller-provided manifest rows."""
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=("path", "bytes", "sha256", "role", "identity"), lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
    target = Path(output) / "manifest.csv"
    staged = target.parent / "manifest.csv.test-staging"
    if os.path.lexists(staged):
        raise RuntimeError("stale test manifest staging file")
    _write_exclusive(staged, stream.getvalue().encode())
    os.replace(staged, target)


def publish(output: Path = OUTPUT, source_dir: Path = SOURCE_DIR) -> None:
    output = _safe(Path(output))
    if not output.is_dir() or output.is_symlink():
        raise RuntimeError("Task 4 paper layer must be published first")
    paper.verify_paper_layer(output)
    delta = _planned_delta(output, Path(source_dir))
    txn = _transaction_dir(output)
    if not os.path.lexists(txn):
        try:
            verify_only(output)
        except RuntimeError:
            pass
        else:
            # A committed tree is an mtime-preserving no-op.
            return
    _recover_or_publish_delta(output, delta)
    verify_only(output)


def verify_only(output: Path = OUTPUT) -> None:
    output = _safe(Path(output))
    paper._validate_registered_shape(output)
    paper.verify_paper_layer(output)
    baseline, generated = _expected_durable(output)
    for name, payload in generated.items():
        target = output / name
        if target.is_symlink() or not target.is_file() or target.read_bytes() != payload:
            raise RuntimeError(f"generated baseline artifact mismatch: {name}")
    expected_manifest = _unified_manifest(output, baseline, generated)
    if (output / "manifest.csv").read_bytes() != expected_manifest:
        raise RuntimeError("unified manifest mismatch")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    (verify_only if args.verify_only else publish)()
    print("BASELINE=flat FIG519_COMPARISONS=4")


if __name__ == "__main__":
    main()
