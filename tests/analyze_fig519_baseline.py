#!/usr/bin/env python3
"""Publish and describe the existing, flat Figure 5.19 power baseline.

This is a preservation and offline comparison tool.  It never runs MATLAB or a
model, and it intentionally derives electrical power from the two shaft traces.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import os
import stat
from bisect import bisect_left
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


def _hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _safe(path: Path) -> Path:
    path = Path(path)
    if ".." in path.parts:
        raise RuntimeError("refusing lexical path escape")
    probe = Path(path.anchor)
    for part in path.parts[1:]:
        probe /= part
        if os.path.lexists(probe) and stat.S_ISLNK(os.lstat(probe).st_mode):
            raise RuntimeError("refusing symlinked path")
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
    if (any(not math.isfinite(v) for v in times + values) or
            any(right < left for left, right in zip(times, times[1:]))):
        raise RuntimeError(f"{name} must have finite nondecreasing time and finite values")
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
    for row in rows:
        panel = row.get("panel_id")
        if panel not in grouped:
            raise RuntimeError("paper points have an unregistered panel")
        time_s, power_kW = float(row["time_s"]), float(row["power_kW"])
        if not (math.isfinite(time_s) and math.isfinite(power_kW) and 0.0 <= time_s <= 500.0):
            raise RuntimeError("paper points are invalid")
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
    }
    roles.update({f"{paper.BASELINE_LAYER_DIR}/{name}": ("contracted baseline source", "flat-model-baseline")
                  for name in paper.BASELINE_LAYER_NAMES})
    return roles


def _unified_manifest(output: Path, baseline: dict[str, bytes], generated: dict[str, bytes]) -> bytes:
    paper_bytes = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries = dict(paper_bytes)
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload for name, payload in baseline.items()})
    entries.update(generated)
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


def _publish_layer_atomic(output: Path, payloads: dict[str, bytes]) -> None:
    target = output / paper.BASELINE_LAYER_DIR
    staging = output / (paper.BASELINE_LAYER_DIR + ".staging")
    if os.path.lexists(staging):
        raise RuntimeError("stale baseline staging directory requires audit")
    os.mkdir(staging, 0o755)
    for name, payload in payloads.items():
        _write_exclusive(staging / name, payload)
    if {entry.name for entry in staging.iterdir()} != set(payloads):
        raise RuntimeError("baseline staging is incomplete")
    if os.path.lexists(target):
        raise RuntimeError("baseline destination appeared during publication")
    os.rename(staging, target)


def _replace_manifest(output: Path, payload: bytes) -> None:
    target = output / "manifest.csv"
    if target.read_bytes() == payload:
        return
    staged = output / "manifest.csv.task5-staging"
    if os.path.lexists(staged):
        raise RuntimeError("stale manifest staging file requires audit")
    _write_exclusive(staged, payload)
    os.replace(staged, target)


def write_manifest(output: Path, rows: list[dict[str, str]]) -> None:
    """Test helper: atomically write caller-provided manifest rows."""
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=("path", "bytes", "sha256", "role", "identity"), lineterminator="\n")
    writer.writeheader(); writer.writerows(rows)
    _replace_manifest(Path(output), stream.getvalue().encode())


def publish(output: Path = OUTPUT, source_dir: Path = SOURCE_DIR) -> None:
    output = _safe(Path(output))
    source = _literal_source_bytes(source_dir)
    if not output.is_dir() or output.is_symlink():
        raise RuntimeError("Task 4 paper layer must be published first")
    # First prove the existing paper evidence before adding a sibling layer.
    if (output / paper.BASELINE_LAYER_DIR).exists():
        paper.verify_paper_layer(output)
        baseline, generated = _expected_durable(output)
        paper._validate_registered_shape(output)
        for name, payload in generated.items():
            if (output / name).read_bytes() != payload:
                raise RuntimeError(f"conflicting existing artifact: {name}")
    else:
        paper.verify_only(output)
        _publish_layer_atomic(output, source)
        baseline, generated = _expected_durable(output)
        for name, payload in generated.items():
            _write_exclusive(output / name, payload)
    _replace_manifest(output, _unified_manifest(output, baseline, generated))
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
