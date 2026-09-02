#!/usr/bin/env python3
"""Analyze the fixed rotating-map candidate gate without changing a model."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from pathlib import Path


TABLE52_TARGETS = {
    "reactor_inlet_T": 1443.27,
    "reactor_outlet_T": 1600.00,
    "turbine_inlet_T": 1522.96,
    "turbine_inlet_P": 1.539e6,
    "turbine_outlet_T": 1162.00,
    "turbine_outlet_P": 0.676e6,
    "compressor_inlet_T": 405.16,
    "compressor_inlet_P": 0.658e6,
    "compressor_outlet_T": 601.90,
    "compressor_outlet_P": 1.551e6,
    "recuperator_hot_outlet_T": 663.63,
    "recuperator_hot_outlet_P": 0.676e6,
    "recuperator_cold_outlet_T": 1100.91,
    "recuperator_cold_outlet_P": 1.543e6,
    "cooler_cold_inlet_T": 360.10,
    "cooler_cold_outlet_T": 609.58,
    "turbine_power": 2252.2e3,
    "compressor_power": 1231.6e3,
    "reactor_power": 2.664e6,
    "rotor_speed": 55090.0,
}

CASE_ORDER = ("C0", "C1", "C2", "C3")
FIVE_PERCENT = 0.05
MINIMUM_IMPROVEMENT = 0.20
TIME_TOLERANCE_S = 1e-6


def _read_case(run_root: Path, case_id: str, stop_time: float):
    case_dir = run_root / "runs" / case_id / f"{stop_time:g}s"
    status_path = case_dir / "run_status.json"
    signal_path = case_dir / "signals.csv"
    if not status_path.is_file():
        return None
    status = json.loads(status_path.read_text(encoding="utf-8"))
    if not signal_path.is_file():
        rows = []
    else:
        with signal_path.open(newline="", encoding="utf-8") as stream:
            rows = list(csv.DictReader(stream))
    return status, rows


def _metrics(status, rows, stop_time):
    comparable = bool(rows) and all(name in rows[-1] for name in TABLE52_TARGETS)
    signal_metrics = {}
    all_values_finite = bool(status.get("all_logged_values_finite", False))
    if comparable:
        final = rows[-1]
        for name, target in TABLE52_TARGETS.items():
            observed = float(final[name])
            finite = math.isfinite(observed)
            all_values_finite = all_values_finite and finite
            error = abs(observed - target) / abs(target) if finite else math.inf
            signal_metrics[name] = {
                "target": target,
                "observed": observed,
                "normalized_absolute_error": error,
                "within_five_percent": error <= FIVE_PERCENT + 1e-12,
            }
    errors = [item["normalized_absolute_error"] for item in signal_metrics.values()]
    median_error = statistics.median(errors) if errors else None
    final_time = status.get("final_valid_time_s")
    completed = (
        bool(status.get("success", False))
        and isinstance(final_time, (int, float))
        and math.isfinite(final_time)
        and final_time + TIME_TOLERANCE_S >= stop_time
    )
    hard_gate_passed = (
        completed
        and bool(status.get("lookup_assertion_clear", False))
        and all_values_finite
        and comparable
    )
    return {
        "status": status,
        "completed_requested_time": completed,
        "lookup_assertion_clear": bool(status.get("lookup_assertion_clear", False)),
        "all_values_finite": all_values_finite,
        "all_targets_comparable": comparable,
        "hard_gate_passed": hard_gate_passed,
        "median_normalized_absolute_error": median_error,
        "signals": signal_metrics,
    }


def analyze(run_root: Path | str, stop_time: float = 500.0):
    run_root = Path(run_root).resolve()
    stop_time = float(stop_time)
    if stop_time != 500.0:
        raise ValueError("Gate 2 analysis accepts only the approved 500 s batch")
    cases = {}
    for case_id in CASE_ORDER:
        loaded = _read_case(run_root, case_id, stop_time)
        if loaded is not None:
            cases[case_id] = _metrics(*loaded, stop_time)
    if "C0" not in cases:
        raise RuntimeError("C0 run evidence is required for Gate 2")

    baseline = cases["C0"]
    eligible = []
    baseline_median = baseline["median_normalized_absolute_error"]
    for case_id in CASE_ORDER[1:]:
        if case_id not in cases:
            continue
        candidate = cases[case_id]
        candidate_median = candidate["median_normalized_absolute_error"]
        if baseline_median is None or candidate_median is None or baseline_median <= 0:
            improvement = None
            improved_enough = False
        else:
            improvement = (baseline_median - candidate_median) / baseline_median
            improved_enough = improvement + 1e-12 >= MINIMUM_IMPROVEMENT
        regressions = []
        for name, baseline_signal in baseline["signals"].items():
            candidate_signal = candidate["signals"].get(name)
            if (
                baseline_signal["within_five_percent"]
                and (candidate_signal is None or not candidate_signal["within_five_percent"])
            ):
                regressions.append(name)
        no_regression = not regressions
        no_earlier_failure = (
            candidate["status"].get("final_valid_time_s") is not None
            and baseline["status"].get("final_valid_time_s") is not None
            and candidate["status"]["final_valid_time_s"] + TIME_TOLERANCE_S
            >= baseline["status"]["final_valid_time_s"]
        )
        candidate.update({
            "relative_median_improvement": improvement,
            "improvement_at_least_twenty_percent": improved_enough,
            "five_percent_regressions": regressions,
            "no_five_percent_regression": no_regression,
            "no_earlier_failure_than_C0": no_earlier_failure,
        })
        passes = (
            baseline["hard_gate_passed"]
            and candidate["hard_gate_passed"]
            and improved_enough
            and no_regression
            and no_earlier_failure
        )
        candidate["eligible_for_14000"] = passes
        if passes:
            eligible.append(case_id)

    change_rank = {"C1": 1, "C2": 1, "C3": 2}
    eligible.sort(key=lambda case_id: (
        cases[case_id]["median_normalized_absolute_error"],
        change_rank[case_id],
        CASE_ORDER.index(case_id),
    ))
    winner = eligible[0] if eligible else None
    return {
        "schema": "rotating_map_gate2_decision_v1",
        "requested_stop_time_s": stop_time,
        "targets_source": "Xu Chi thesis Table 5.2 and Section 5.3.1",
        "normalized_error_definition": "abs(model-paper)/abs(paper)",
        "minimum_relative_median_improvement": MINIMUM_IMPROVEMENT,
        "five_percent_no_regression_threshold": FIVE_PERCENT,
        "eligible_for_14000": winner is not None,
        "winner": winner,
        "eligible_cases": eligible,
        "cases": cases,
        "formal_promotion": False,
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--stop-time", type=float, required=True)
    args = parser.parse_args(argv)
    decision = analyze(args.run_root, args.stop_time)
    output = args.run_root / "gate2_decision.json"
    output.write_text(
        json.dumps(decision, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "eligible_for_14000": decision["eligible_for_14000"],
        "winner": decision["winner"],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
