"""Offline Figure 5.19 analysis for the approved lineage-merge diagnostic."""
from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Iterable, Mapping, Sequence

from PIL import Image, ImageDraw

try:
    from tests.analyze_fig519_ihx_r2_hexe_shift import (
        BASELINE_HASHES,
        PAPER_POINTS_SHA256,
        direction_sequence,
    )
    from tests.fig519_ihx_r2_hexe_contract import (
        NONFLAT_THRESHOLDS_W,
        PAPER_DIRECTIONS,
    )
except ModuleNotFoundError:  # Direct execution from tests/.
    from analyze_fig519_ihx_r2_hexe_shift import (  # type: ignore
        BASELINE_HASHES,
        PAPER_POINTS_SHA256,
        direction_sequence,
    )
    from fig519_ihx_r2_hexe_contract import (  # type: ignore
        NONFLAT_THRESHOLDS_W,
        PAPER_DIRECTIONS,
    )


ROOT = Path(__file__).resolve().parents[1]
PAPER_POINTS_PATH = ROOT / "data/provenance/steady53/fig5_19/paper_points.csv"
BASELINE_DIR = ROOT / "data/provenance/steady53/fig5_19/model_baseline"
ROOT_MODEL_SHA256 = (
    "a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159"
)
FROZEN_MODEL_SHA256 = (
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
)
PANEL_NAMES = (
    "reactor",
    "turbine",
    "compressor",
    "electrical_paper_eta",
)
PANEL_IDS = {
    "reactor": "a",
    "turbine": "b",
    "compressor": "c",
    "electrical_paper_eta": "d",
}
CURVE_COLUMNS = (
    "time_s",
    "reactor_W",
    "turbine_W",
    "compressor_W",
    "electrical_paper_eta_W",
    "electrical_historical_eta_W",
)
CURVE_COLUMN_BY_PANEL = {
    "reactor": "reactor_W",
    "turbine": "turbine_W",
    "compressor": "compressor_W",
    "electrical_paper_eta": "electrical_paper_eta_W",
}
PROMOTION = {
    "paper_reproduced": False,
    "author_initial_state_identified": False,
    "formal_promotion": False,
}


class EvidenceContractError(RuntimeError):
    """Raised when the durable experiment evidence violates its contract."""


class CurveContractError(RuntimeError):
    """Raised when a curve or paper-point array is malformed."""


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _regular(path: Path, label: str) -> Path:
    if not path.is_file() or path.is_symlink():
        raise EvidenceContractError(f"missing or unsafe {label}: {path}")
    return path


def _finite(value: object, label: str) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise CurveContractError(f"{label} is not numeric") from exc
    if not math.isfinite(number):
        raise CurveContractError(f"{label} is not finite")
    return number


def read_fixed_paper_points(
    path: Path = PAPER_POINTS_PATH,
) -> dict[str, list[tuple[float, float, float]]]:
    source = _regular(Path(path), "paper_points.csv")
    if _sha256(source) != PAPER_POINTS_SHA256:
        raise EvidenceContractError("fixed paper_points.csv SHA-256 changed")
    grouped_by_id: dict[str, list[tuple[float, float, float]]] = {
        panel: [] for panel in "abcd"
    }
    try:
        with source.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
    except (OSError, UnicodeError, csv.Error) as exc:
        raise EvidenceContractError("paper_points.csv cannot be parsed") from exc
    for row in rows:
        panel = row.get("panel_id")
        if panel not in grouped_by_id:
            raise EvidenceContractError("paper points contain an unknown panel")
        try:
            point = (
                _finite(row.get("time_s"), "paper time"),
                _finite(row.get("power_kW"), "paper power"),
                _finite(row.get("power_allowance_kW"), "paper allowance"),
            )
        except CurveContractError as exc:
            raise EvidenceContractError(str(exc)) from exc
        if point[2] <= 0:
            raise EvidenceContractError("paper allowance must be positive")
        grouped_by_id[panel].append(point)
    grouped: dict[str, list[tuple[float, float, float]]] = {}
    for name, panel in PANEL_IDS.items():
        points = grouped_by_id[panel]
        if len(points) != 15 or any(
            right[0] <= left[0] for left, right in zip(points, points[1:])
        ):
            raise EvidenceContractError(
                "each fixed paper panel must contain 15 increasing points"
            )
        if tuple(direction_sequence(points)) != tuple(PAPER_DIRECTIONS[name]):
            raise EvidenceContractError(
                f"fixed paper direction sequence changed for {name}"
            )
        grouped[name] = points
    return grouped


def _validate_time(times: Sequence[float]) -> list[float]:
    normalized = [_finite(value, "time") for value in times]
    if (
        len(normalized) < 2
        or normalized[0] != 0.0
        or normalized[-1] != 500.0
        or any(right <= left for left, right in zip(normalized, normalized[1:]))
    ):
        raise CurveContractError(
            "time must be finite, strictly increasing, and span exactly 0..500 s"
        )
    return normalized


def _validate_curves(
    times: Sequence[float], curves: Mapping[str, Sequence[float]]
) -> tuple[list[float], dict[str, list[float]]]:
    time = _validate_time(times)
    if set(curves) != set(PANEL_NAMES):
        raise CurveContractError("curves must contain exactly the four Figure 5.19 panels")
    normalized: dict[str, list[float]] = {}
    for name in PANEL_NAMES:
        values = [_finite(value, f"{name} value") for value in curves[name]]
        if len(values) != len(time):
            raise CurveContractError(f"{name} does not align with time")
        normalized[name] = values
    return time, normalized


def _interpolate(times: Sequence[float], values: Sequence[float], query: float) -> float:
    index = bisect.bisect_left(times, query)
    if index < len(times) and times[index] == query:
        return values[index]
    if index == 0 or index == len(times):
        raise CurveContractError("curve does not cover a paper comparison time")
    left, right = times[index - 1], times[index]
    fraction = (query - left) / (right - left)
    return values[index - 1] + fraction * (values[index] - values[index - 1])


def _metrics(times: Sequence[float], values: Sequence[float]) -> dict[str, float | int]:
    peak = max(values)
    valley = min(values)
    peak_index = values.index(peak)
    valley_index = values.index(valley)
    return {
        "samples": len(values),
        "start_W": values[0],
        "end_W": values[-1],
        "peak_W": peak,
        "peak_time_s": times[peak_index],
        "valley_W": valley,
        "valley_time_s": times[valley_index],
        "peak_to_peak_W": peak - valley,
    }


def _comparison(
    times: Sequence[float],
    values: Sequence[float],
    points: Sequence[tuple[float, float, float]],
) -> tuple[dict[str, object], list[dict[str, float]]]:
    model_k_w = [_interpolate(times, values, point[0]) / 1000.0 for point in points]
    errors = [actual - point[1] for actual, point in zip(model_k_w, points)]
    model_points = [
        (point[0], value, point[2]) for point, value in zip(points, model_k_w)
    ]
    rows = [
        {
            "time_s": point[0],
            "paper_kW": point[1],
            "candidate_kW": actual,
            "error_kW": error,
        }
        for point, actual, error in zip(points, model_k_w, errors)
    ]
    metrics: dict[str, object] = {
        "rmse_kW": math.sqrt(sum(error * error for error in errors) / len(errors)),
        "max_abs_error_kW": max(abs(error) for error in errors),
        "candidate_direction_sequence": direction_sequence(model_points),
        "paper_direction_sequence": direction_sequence(list(points)),
    }
    return metrics, rows


def analyze_arrays(
    times: Sequence[float],
    curves: Mapping[str, Sequence[float]],
    paper_points: Mapping[str, Sequence[tuple[float, float, float]]],
    baseline: tuple[Sequence[float], Mapping[str, Sequence[float]]] | None = None,
) -> dict[str, object]:
    time, normalized = _validate_curves(times, curves)
    if set(paper_points) != set(PANEL_NAMES):
        raise CurveContractError("paper point mapping must contain exactly four panels")
    baseline_time: list[float] | None = None
    baseline_curves: dict[str, list[float]] | None = None
    if baseline is not None:
        baseline_time, baseline_curves = _validate_curves(baseline[0], baseline[1])
    panels: dict[str, dict[str, object]] = {}
    comparison_rows: list[dict[str, object]] = []
    passed = 0
    for name in PANEL_NAMES:
        points = [tuple(point) for point in paper_points[name]]
        if len(points) < 2:
            raise CurveContractError(f"{name} needs at least two paper points")
        comparison, rows = _comparison(time, normalized[name], points)
        expected_direction = list(PAPER_DIRECTIONS[name])
        direction_ok = comparison["candidate_direction_sequence"] == expected_direction
        threshold = float(NONFLAT_THRESHOLDS_W[name])
        metrics = _metrics(time, normalized[name])
        nonflat_ok = float(metrics["peak_to_peak_W"]) >= threshold
        gate = bool(direction_ok and nonflat_ok)
        passed += int(gate)
        baseline_comparison: dict[str, object] | None = None
        if baseline_time is not None and baseline_curves is not None:
            baseline_comparison, _ = _comparison(
                baseline_time, baseline_curves[name], points
            )
            comparison["baseline_rmse_kW"] = baseline_comparison["rmse_kW"]
            comparison["rmse_change_vs_baseline_kW"] = (
                float(comparison["rmse_kW"])
                - float(baseline_comparison["rmse_kW"])
            )
        panels[name] = {
            "metrics": metrics,
            "paper_comparison": comparison,
            "expected_direction_sequence": expected_direction,
            "direction_match": direction_ok,
            "nonflat_threshold_W": threshold,
            "nonflat": nonflat_ok,
            "panel_gate_passed": gate,
        }
        for row in rows:
            comparison_rows.append({"panel": name, **row})
    if passed == 4:
        result_enum = "lineage_initial_state_split_supported"
    elif passed > 0:
        result_enum = "lineage_initial_state_split_partially_supported"
    else:
        result_enum = "lineage_initial_state_split_not_supported"
    return {
        "analysis_schema": "steady53_lineage_merge_analysis_v1",
        "numerical_gate_passed": True,
        "result_enum": result_enum,
        "passed_panel_count": passed,
        "panels": panels,
        "comparison_rows": comparison_rows,
        **PROMOTION,
    }


def _read_json(path: Path, label: str) -> dict[str, object]:
    source = _regular(path, label)
    try:
        value = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceContractError(f"malformed {label}") from exc
    if not isinstance(value, dict):
        raise EvidenceContractError(f"{label} must be a JSON object")
    return value


def _false_promotions(value: Mapping[str, object]) -> bool:
    return all(value.get(name) is False for name in PROMOTION)


def _validate_audit(run_dir: Path) -> tuple[dict[str, object], str]:
    candidate = _regular(run_dir / "candidate.slx", "candidate.slx")
    audit = _read_json(run_dir / "candidate_audit.json", "candidate audit")
    digest = _sha256(candidate)
    assignments = audit.get("state_assignments")
    if (
        audit.get("schema") != "steady53_lineage_merge_candidate_v1"
        or audit.get("root_model_sha256") != ROOT_MODEL_SHA256
        or audit.get("frozen_model_sha256") != FROZEN_MODEL_SHA256
        or audit.get("candidate_model_sha256") != digest
        or audit.get("state_count") != 40
        or audit.get("assigned_state_count") != 40
        or audit.get("changed_state_count") != 39
        or audit.get("unchanged_state_count") != 1
        or any(audit.get(name) is not True for name in (
            "block_inventory_unchanged",
            "topology_unchanged",
            "non_ic_dialog_parameters_unchanged",
            "solver_parameters_unchanged",
        ))
        or audit.get("simulation_call_count") != 0
        or not _false_promotions(audit)
        or not isinstance(assignments, list)
        or len(assignments) != 40
    ):
        raise EvidenceContractError("candidate audit violates the 40/39/1 contract")
    changed = 0
    unchanged_paths: list[str] = []
    for item in assignments:
        if not isinstance(item, dict) or item.get("candidate_matches_root") is not True:
            raise EvidenceContractError("candidate state assignment is malformed")
        if item.get("value_changed") is True:
            changed += 1
        elif item.get("value_changed") is False:
            unchanged_paths.append(str(item.get("relative_path")))
        else:
            raise EvidenceContractError("candidate state change flag is malformed")
    if changed != 39 or unchanged_paths != ["TAC/rotor/N_rpm_Integrator"]:
        raise EvidenceContractError("candidate state assignments do not prove 40/39/1")
    return audit, digest


def _validate_status(run_dir: Path, digest: str) -> dict[str, object]:
    status = _read_json(run_dir / "run" / "run_status.json", "run status")
    if (
        status.get("schema") != "steady53_lineage_merge_run_status_v1"
        or status.get("run_steady53_case_call_count") != 1
        or status.get("retry_count") != 0
        or status.get("requested_stop_time_s") != 500
        or status.get("candidate_model_sha256_before") != digest
        or status.get("candidate_model_sha256_after") != digest
        or not _false_promotions(status)
    ):
        raise EvidenceContractError("run status violates the one-shot contract")
    experiment = status.get("experiment_status")
    if experiment == "completed_success":
        if (
            status.get("final_time_s") != 500
            or status.get("raw_result_present") is not True
            or status.get("curves_present") is not True
            or not (run_dir / "run" / "raw_result.mat").is_file()
            or not (run_dir / "run" / "curves.csv").is_file()
        ):
            raise EvidenceContractError("successful run lacks exact 500 s artifacts")
    elif experiment not in {
        "completed_model_failure",
        "numerical_or_contract_failure",
    }:
        raise EvidenceContractError("run status enum is invalid")
    return status


def _read_curves(path: Path) -> tuple[list[float], dict[str, list[float]]]:
    source = _regular(path, "curves.csv")
    try:
        with source.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            if tuple(reader.fieldnames or ()) != CURVE_COLUMNS:
                raise CurveContractError("curves.csv columns changed")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise CurveContractError("curves.csv cannot be parsed") from exc
    time = [_finite(row["time_s"], "curve time") for row in rows]
    raw = {
        name: [_finite(row[column], column) for row in rows]
        for name, column in CURVE_COLUMN_BY_PANEL.items()
    }
    turbine = raw["turbine"]
    compressor = raw["compressor"]
    paper = raw["electrical_paper_eta"]
    historical = [
        _finite(row["electrical_historical_eta_W"], "historical electrical")
        for row in rows
    ]
    for index, (turbine_value, compressor_value) in enumerate(
        zip(turbine, compressor)
    ):
        expected_paper = 0.98 * (turbine_value - compressor_value)
        expected_historical = 0.96527 * (turbine_value - compressor_value)
        tolerance = 1e-9 * max(1.0, abs(expected_paper), abs(expected_historical))
        if (
            abs(paper[index] - expected_paper) > tolerance
            or abs(historical[index] - expected_historical) > tolerance
        ):
            raise CurveContractError("electrical curve formulas changed")
    return _validate_curves(time, raw)


def _read_two_column_curve(path: Path, expected_hash: str) -> tuple[list[float], list[float]]:
    source = _regular(path, path.name)
    if _sha256(source) != expected_hash:
        raise EvidenceContractError(f"baseline curve SHA-256 changed: {path.name}")
    try:
        with source.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))
        time = [_finite(row[0], "baseline time") for row in rows]
        values = [_finite(row[1], "baseline value") for row in rows]
    except (OSError, UnicodeError, csv.Error, IndexError) as exc:
        raise EvidenceContractError(f"malformed baseline curve: {path.name}") from exc
    if len(time) < 2 or len(time) != len(values) or any(
        right <= left for left, right in zip(time, time[1:])
    ):
        raise EvidenceContractError(f"invalid baseline time axis: {path.name}")
    return time, values


def _read_baseline() -> tuple[list[float], dict[str, list[float]]]:
    names = {
        "reactor": "baseline_P_sw.csv",
        "turbine": "baseline_WT_sw.csv",
        "compressor": "baseline_Wc_sw.csv",
    }
    time: list[float] | None = None
    curves: dict[str, list[float]] = {}
    for panel, filename in names.items():
        panel_time, values = _read_two_column_curve(
            BASELINE_DIR / filename, BASELINE_HASHES[filename]
        )
        if time is None:
            time = panel_time
        elif time != panel_time:
            raise EvidenceContractError("baseline time axes differ")
        curves[panel] = values
    if time is None:
        raise EvidenceContractError("baseline curves are empty")
    curves["electrical_paper_eta"] = [
        0.98 * (turbine - compressor)
        for turbine, compressor in zip(curves["turbine"], curves["compressor"])
    ]
    # Analysis is limited to the approved 0..500 s window.
    indices = [index for index, value in enumerate(time) if value <= 500]
    if not indices or time[indices[-1]] != 500:
        # Add an exact interpolated 500 s endpoint if the frozen output grid skips it.
        clipped_time = [time[index] for index in indices]
        clipped_curves = {
            name: [values[index] for index in indices] for name, values in curves.items()
        }
        clipped_time.append(500.0)
        for name in PANEL_NAMES:
            clipped_curves[name].append(_interpolate(time, curves[name], 500.0))
        return clipped_time, clipped_curves
    return (
        [time[index] for index in indices],
        {name: [values[index] for index in indices] for name, values in curves.items()},
    )


def analyze_run(run_dir: Path) -> dict[str, object]:
    selected = Path(run_dir).resolve(strict=True)
    if not selected.is_dir() or selected.is_symlink():
        raise EvidenceContractError("run directory is missing or unsafe")
    _, digest = _validate_audit(selected)
    status = _validate_status(selected, digest)
    if status["experiment_status"] != "completed_success":
        return {
            "analysis_schema": "steady53_lineage_merge_analysis_v1",
            "numerical_gate_passed": False,
            "result_enum": "numerical_or_contract_failure",
            "passed_panel_count": 0,
            "panels": {},
            "comparison_rows": [],
            "candidate_model_sha256": digest,
            "run_steady53_case_call_count": 1,
            "retry_count": 0,
            "observed_error_id": status.get("error_id", ""),
            "observed_error_report": status.get("error_report", ""),
            **PROMOTION,
        }
    time, curves = _read_curves(selected / "run" / "curves.csv")
    paper = read_fixed_paper_points()
    baseline = _read_baseline()
    result = analyze_arrays(time, curves, paper, baseline)
    result.update(
        candidate_model_sha256=digest,
        run_steady53_case_call_count=1,
        retry_count=0,
    )
    return result


def _exclusive_text(path: Path, text: str) -> None:
    try:
        with path.open("x", encoding="utf-8", newline="") as handle:
            handle.write(text)
    except FileExistsError as exc:
        raise EvidenceContractError(f"refusing to overwrite {path.name}") from exc


def _comparison_csv(rows: Iterable[Mapping[str, object]]) -> str:
    buffer = io.StringIO(newline="")
    fieldnames = ("panel", "time_s", "paper_kW", "candidate_kW", "error_kW")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow({name: row[name] for name in fieldnames})
    return buffer.getvalue()


def _draw_polyline(
    draw: ImageDraw.ImageDraw,
    points: Sequence[tuple[float, float]],
    color: str,
    width: int,
) -> None:
    if len(points) >= 2:
        draw.line(points, fill=color, width=width, joint="curve")


def _figure_bytes(run_dir: Path, result: Mapping[str, object]) -> bytes:
    image = Image.new("RGB", (1600, 1000), "white")
    draw = ImageDraw.Draw(image)
    draw.text((40, 20), "Figure 5.19 lineage-merge diagnostic (500 s)", fill="black")
    if result.get("numerical_gate_passed") is not True:
        draw.text((40, 80), "No valid curves: numerical_or_contract_failure", fill="red")
    else:
        time, curves = _read_curves(run_dir / "run" / "curves.csv")
        paper = read_fixed_paper_points()
        baseline_time, baseline_curves = _read_baseline()
        for index, name in enumerate(PANEL_NAMES):
            row, column = divmod(index, 2)
            left, top = 70 + column * 780, 80 + row * 440
            right, bottom = left + 700, top + 350
            draw.rectangle((left, top, right, bottom), outline="#555555", width=2)
            paper_values = [point[1] * 1000.0 for point in paper[name]]
            all_values = list(curves[name]) + paper_values + list(baseline_curves[name])
            low, high = min(all_values), max(all_values)
            pad = max(1.0, (high - low) * 0.08)
            low, high = low - pad, high + pad

            def xy(t_value: float, y_value: float) -> tuple[float, float]:
                x_pixel = left + (t_value / 500.0) * (right - left)
                y_pixel = bottom - ((y_value - low) / (high - low)) * (bottom - top)
                return x_pixel, y_pixel

            _draw_polyline(
                draw,
                [xy(t, y) for t, y in zip(baseline_time, baseline_curves[name])],
                "#999999",
                2,
            )
            _draw_polyline(
                draw,
                [xy(t, y) for t, y in zip(time, curves[name])],
                "#0066cc",
                3,
            )
            for point in paper[name]:
                x_pixel, y_pixel = xy(point[0], point[1] * 1000.0)
                draw.ellipse(
                    (x_pixel - 4, y_pixel - 4, x_pixel + 4, y_pixel + 4),
                    fill="#cc2222",
                )
            panel = result["panels"][name]  # type: ignore[index]
            label = (
                f"{name}: direction={panel['direction_match']} "
                f"nonflat={panel['nonflat']}"
            )
            draw.text((left + 8, top + 8), label, fill="black")
            draw.text((left, bottom + 8), "0 s", fill="black")
            draw.text((right - 35, bottom + 8), "500 s", fill="black")
        draw.text((70, 970), "blue=candidate, gray=frozen baseline, red=paper points", fill="black")
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def publish(run_dir: Path) -> dict[str, object]:
    selected = Path(run_dir).resolve(strict=True)
    result = analyze_run(selected)
    analysis_path = selected / "analysis.json"
    comparison_path = selected / "comparison.csv"
    figure_path = selected / "figure5_19_lineage_merge.png"
    if any(path.exists() for path in (analysis_path, comparison_path, figure_path)):
        raise EvidenceContractError("analysis artifacts already exist; overwrite refused")
    _exclusive_text(
        analysis_path,
        json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
    )
    _exclusive_text(comparison_path, _comparison_csv(result["comparison_rows"]))
    try:
        with figure_path.open("xb") as handle:
            handle.write(_figure_bytes(selected, result))
    except FileExistsError as exc:
        raise EvidenceContractError("refusing to overwrite analysis figure") from exc
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, required=True)
    args = parser.parse_args()
    result = publish(args.run_dir)
    print(json.dumps({
        "result_enum": result["result_enum"],
        "passed_panel_count": result["passed_panel_count"],
        "paper_reproduced": False,
        "formal_promotion": False,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
