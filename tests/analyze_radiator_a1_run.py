#!/usr/bin/env python3
"""Independent A1 run gates; reads CSV/JSON only and never loads an SLX."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from tests import radiator_candidate_math as base_math


ROOT = Path(__file__).resolve().parents[1]
PAPER_TARGETS = {
    "reactor_inlet_T": (1443.27, True, "thesis_table_5_2"),
    "reactor_outlet_T": (1600.00, True, "thesis_table_5_2"),
    "turbine_inlet_T": (1522.96, True, "thesis_table_5_2"),
    "turbine_outlet_T": (1162.00, True, "thesis_table_5_2"),
    "compressor_inlet_T": (405.16, True, "thesis_table_5_2"),
    "compressor_outlet_T": (601.90, True, "thesis_table_5_2"),
    "recuperator_hot_outlet_T": (663.63, True, "thesis_table_5_2"),
    "recuperator_cold_outlet_T": (1100.91, True, "thesis_table_5_2"),
    "cooler_cold_inlet_T": (360.10, False, "used_in_candidate_conditioning"),
    "cooler_cold_outlet_T": (609.58, False, "used_in_candidate_conditioning"),
    "P_sw": (2_664_000.0, True, "thesis_table_5_2_or_section_5_3_1"),
    "WT_sw": (2_252_200.0, True, "thesis_table_5_2"),
    "Wc_sw": (1_231_600.0, True, "thesis_table_5_2"),
}
RADIATOR_SCAN = ROOT / "tmp/steady53_curves_20260828/radiator_scan_points.csv"


def all_finite_real(values) -> bool:
    return all(
        not isinstance(value, complex) and math.isfinite(float(value))
        for value in values
    )


def persistent_growth(values) -> bool:
    values = [float(value) for value in values]
    if len(values) < 10 or not all_finite_real(values):
        return False
    bins = [
        values[round(i * len(values) / 5):round((i + 1) * len(values) / 5)]
        for i in range(5)
    ]
    ranges = [max(chunk) - min(chunk) for chunk in bins if chunk]
    scale = max(1.0, max(abs(value) for value in values))
    return (
        len(ranges) == 5
        and ranges[-1] > 1e-6 * scale
        and all(
            right > 1.05 * left
            for left, right in zip(ranges, ranges[1:])
        )
    )


def energy_gate(
    enthalpy_convection_residual_W: float,
    loop_residual_W: float,
    signs_consistent: bool,
) -> bool:
    return (
        abs(enthalpy_convection_residual_W) < 1.0
        and abs(loop_residual_W) < 1000.0
        and signs_consistent
    )


def read_series(path: Path) -> tuple[list[float], list[float]]:
    with path.open() as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"empty series: {path}")
    time = [float(row["time_s"]) for row in rows]
    values = [float(row["value"]) for row in rows]
    if not all_finite_real(time + values):
        raise ValueError(f"nonfinite series: {path}")
    if any(right < left for left, right in zip(time, time[1:])):
        raise ValueError(f"nonmonotone time: {path}")
    return time, values


def paper_comparison(final_values: dict[str, float]) -> dict:
    result = {}
    for name, value in final_values.items():
        if name not in PAPER_TARGETS:
            continue
        target, independent, source = PAPER_TARGETS[name]
        result[name] = {
            "value": value,
            "paper_target": target,
            "relative_error": (value - target) / target,
            "independent_validation": independent,
            "target_source": source,
        }
    return result


def interpolate(time: list[float], values: list[float], target: float) -> float:
    if not (time[0] <= target <= time[-1]):
        raise ValueError("target is outside recorded time")
    for index in range(1, len(time)):
        if time[index] >= target:
            left_t, right_t = time[index - 1], time[index]
            if right_t == left_t:
                return values[index]
            weight = (target - left_t) / (right_t - left_t)
            return values[index - 1] + weight * (
                values[index] - values[index - 1]
            )
    return values[-1]


def curve_comparison(
    series: dict[str, tuple[list[float], list[float]]],
) -> dict:
    with RADIATOR_SCAN.open() as handle:
        points = list(csv.DictReader(handle))
    times = [float(row["time_s"]) for row in points]
    observed_wall = [float(row["wall_K"]) for row in points]
    observed_outlet = [float(row["outlet_K"]) for row in points]
    wall = [interpolate(*series["state_040"], target) for target in times]
    outlet = [
        interpolate(*series["cooler_cold_inlet_T"], target)
        for target in times
    ]

    def rmse(left, right):
        return math.sqrt(
            sum((a - b) ** 2 for a, b in zip(left, right)) / len(left)
        )

    return {
        "figure_5_18d_radiator_wall_rmse_K": rmse(wall, observed_wall),
        "figure_5_18d_radiator_outlet_rmse_K": rmse(outlet, observed_outlet),
        "scan_reading_allowance_K": 3.0,
        "scan_reading_allowance_s": 2.0,
        "comparison_identity": (
            "comparison_only_due_to_whole_system_context_and_prior_conditioning"
        ),
        "independent_validation": False,
    }


def trajectory_metrics(time: list[float], values: list[float]) -> dict:
    final = values[-1]
    band = 0.01 * max(abs(final), 1.0)
    last_outside = max(
        (
            index
            for index, value in enumerate(values)
            if abs(value - final) > band
        ),
        default=-1,
    )
    settling = 0.0 if last_outside < 0 else (
        time[last_outside + 1]
        if last_outside + 1 < len(time)
        else None
    )
    return {
        "initial": values[0],
        "final": final,
        "minimum": min(values),
        "maximum": max(values),
        "settling_time_1pct_s": settling,
        "direction": (
            "rise" if final > values[0]
            else "fall" if final < values[0]
            else "flat"
        ),
    }


def analyze_run(run_root: Path, candidate_id: str, stop_time: int) -> dict:
    run_root = run_root.resolve()
    if not run_root.is_relative_to(ROOT / "tmp"):
        raise ValueError("run root must be below tmp/")
    stage = "candidates_500s" if stop_time == 500 else "candidates_14000s"
    run_dir = run_root / stage / candidate_id / "run"
    status = json.loads((run_dir / "simulation_status.json").read_text())
    manifest = json.loads(
        (
            run_root / "representatives" / candidate_id
            / "parameter_manifest.json"
        ).read_text()
    )
    result = {
        "candidate_id": candidate_id,
        "stop_time_s": stop_time,
        "simulation_success": bool(status["success"]),
        "actual_final_time_s": status.get("actual_final_time_s"),
        "energy_gate_pass": False,
        "growth_gate_pass": False,
        "simulation_gate_pass": False,
        "rejection_reasons": [],
        "paper_reproduced": False,
        "formal_promotion": False,
    }
    if not status["success"] or status.get("actual_final_time_s") != stop_time:
        result["rejection_reasons"].append("simulation_incomplete_or_failed")
        return result
    names = [
        "cooler_cold_outlet_T",
        "cooler_cold_inlet_T",
        "state_040",
        "state_012",
        "state_016",
        "state_017",
        "state_021",
    ]
    series = {
        name: read_series(run_dir / f"{name}.csv")
        for name in names
    }
    if any(time[-1] != stop_time for time, _ in series.values()):
        result["rejection_reasons"].append("logged_series_does_not_reach_stop")
        return result
    tin = series["cooler_cold_outlet_T"][1][-1]
    tout = series["cooler_cold_inlet_T"][1][-1]
    wall = series["state_040"][1][-1]
    m_dot = float(manifest["m_dot_NaK_kg_s"])
    h = float(manifest["h_W_m2K"])
    area = float(manifest["A_exchange_m2"])
    epsilon = float(manifest["epsilon"])
    sink = float(manifest["T_sink_K"])
    q_enthalpy = m_dot * (
        base_math.nak_enthalpy_J_kg(tin)
        - base_math.nak_enthalpy_J_kg(tout)
    )
    q_convection = h * area * (0.8 * tin + 0.2 * tout - wall)
    q_radiation = epsilon * 5.67e-8 * area * (wall**4 - sink**4)
    q_precooler = 0.0
    for cold_name, wall_name in (
        ("state_012", "state_016"),
        ("state_017", "state_021"),
    ):
        cold = series[cold_name][1][-1]
        region_wall = series[wall_name][1][-1]
        q_precooler += 94550.0 * 12.256 * (region_wall - cold)
    enthalpy_convection = q_enthalpy - q_convection
    loop_residual = q_precooler - q_enthalpy
    signs = q_enthalpy > 0.0 and q_convection > 0.0 and q_radiation > 0.0
    result["energy"] = {
        "q_enthalpy_W": q_enthalpy,
        "q_convection_W": q_convection,
        "q_radiation_W": q_radiation,
        "q_precooler_W": q_precooler,
        "enthalpy_minus_convection_W": enthalpy_convection,
        "precooler_minus_enthalpy_W": loop_residual,
        "signs_consistent": signs,
        "precooler_constants_source": "read-only source snapshot inventory",
    }
    result["energy_gate_pass"] = energy_gate(
        enthalpy_convection, loop_residual, signs
    )
    growing = {
        name: persistent_growth(values[-max(10, len(values) // 5):])
        for name, (_, values) in series.items()
    }
    result["persistent_growth"] = growing
    result["growth_gate_pass"] = not any(growing.values())
    if not result["energy_gate_pass"]:
        result["rejection_reasons"].append("energy_gate_failed")
    if not result["growth_gate_pass"]:
        result["rejection_reasons"].append("persistent_end_window_growth")
    final_values = {}
    for name in PAPER_TARGETS:
        path = run_dir / f"{name}.csv"
        if path.is_file():
            final_values[name] = read_series(path)[1][-1]
    result["paper_comparison"] = paper_comparison(final_values)
    result["curve_comparison"] = curve_comparison(series)
    result["curve_comparison"]["figure_5_19_power_shape"] = {
        name: trajectory_metrics(*read_series(run_dir / f"{name}.csv"))
        for name in ("P_sw", "WT_sw", "Wc_sw")
        if (run_dir / f"{name}.csv").is_file()
    }
    result["simulation_gate_pass"] = (
        result["simulation_success"]
        and result["energy_gate_pass"]
        and result["growth_gate_pass"]
        and bool(status["protected_hashes_unchanged"])
        and status["candidate_sha256_before"]
        == status["candidate_sha256_after"]
    )
    return result


def write_analysis(run_root: Path, candidate_id: str, stop_time: int) -> dict:
    result = analyze_run(run_root, candidate_id, stop_time)
    stage = "candidates_500s" if stop_time == 500 else "candidates_14000s"
    run_dir = run_root / stage / candidate_id / "run"
    (run_dir / "energy_balance.json").write_text(
        json.dumps(
            {
                key: result[key]
                for key in result
                if key != "paper_comparison"
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + "\n"
    )
    (run_dir / "paper_comparison.json").write_text(
        json.dumps(
            result.get("paper_comparison", {}),
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        ) + "\n"
    )
    (run_dir / "gate.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("candidate_id")
    parser.add_argument("stop_time", type=int, choices=(500, 14000))
    args = parser.parse_args()
    result = write_analysis(
        args.run_root.resolve(), args.candidate_id, args.stop_time
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
