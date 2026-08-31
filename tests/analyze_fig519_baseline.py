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
RAW_REFERENCE_RELATIVE = Path("tmp/fig519_initialization_20260831_A1/raw_reference.mat")
RAW_REFERENCE_SHA256 = "185d59ca6e55647ad14fb5f23599bc85e6566f8da2ca6120f42a0ef8dedbb648"
RAW_REFERENCE_BYTES = 299032
EXPECTED_STATE_PATHS = (
    "final_steady_24a/IHX/IHX_region_1/T_c1_average_Integrator",
    "final_steady_24a/IHX/IHX_region_1/T_c2_out_Integrator",
    "final_steady_24a/IHX/IHX_region_1/T_h1_average_Integrator",
    "final_steady_24a/IHX/IHX_region_1/T_h2_out_Integrator",
    "final_steady_24a/IHX/IHX_region_1/T_wall_Integrator",
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
    "final_steady_24a/IHX/IHX_region_2/T_h1_average_Integrator",
    "final_steady_24a/IHX/IHX_region_2/T_h2_out_Integrator",
    "final_steady_24a/IHX/IHX_region_2/T_wall_Integrator",
    "final_steady_24a/TAC/rotor/N_rpm_Integrator",
    "final_steady_24a/precooler/precooler_1/T_c1_average_Integrator",
    "final_steady_24a/precooler/precooler_1/T_c2_out_Integrator",
    "final_steady_24a/precooler/precooler_1/T_h1_average_Integrator",
    "final_steady_24a/precooler/precooler_1/T_h2_out_Integrator",
    "final_steady_24a/precooler/precooler_1/T_wall_Integrator",
    "final_steady_24a/precooler/precooler_2/T_c1_average_Integrator",
    "final_steady_24a/precooler/precooler_2/T_c2_out_Integrator",
    "final_steady_24a/precooler/precooler_2/T_h1_average_Integrator",
    "final_steady_24a/precooler/precooler_2/T_h2_out_Integrator",
    "final_steady_24a/precooler/precooler_2/T_wall_Integrator",
    "final_steady_24a/reactor/Integrator",
    "final_steady_24a/reactor/Integrator1",
    "final_steady_24a/reactor/Integrator2",
    "final_steady_24a/reactor/Integrator3",
    "final_steady_24a/reactor/Integrator4",
    "final_steady_24a/reactor/Integrator5",
    "final_steady_24a/reactor/Integrator6",
    "final_steady_24a/reactor/Integrator7",
    "final_steady_24a/recuperator/MannRegion_1/T_c1_average_Integrator",
    "final_steady_24a/recuperator/MannRegion_1/T_c2_out_Integrator",
    "final_steady_24a/recuperator/MannRegion_1/T_h1_average_Integrator",
    "final_steady_24a/recuperator/MannRegion_1/T_h2_out_Integrator",
    "final_steady_24a/recuperator/MannRegion_1/T_wall_Integrator",
    "final_steady_24a/recuperator/MannRegion_2/T_c1_average_Integrator",
    "final_steady_24a/recuperator/MannRegion_2/T_c2_out_Integrator",
    "final_steady_24a/recuperator/MannRegion_2/T_h1_average_Integrator",
    "final_steady_24a/recuperator/MannRegion_2/T_h2_out_Integrator",
    "final_steady_24a/recuperator/MannRegion_2/T_wall_Integrator",
    "final_steady_24a/rediator/T_rad_Integrator",
)
EXPECTED_MAPPING_STATES = {
    "reactor": (
        "final_steady_24a/reactor/Integrator6",
        "final_steady_24a/reactor/Integrator7",
    ),
    "turbine": (
        "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
        "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
    ),
    "compressor": (
        "final_steady_24a/precooler/precooler_2/T_h1_average_Integrator",
        "final_steady_24a/precooler/precooler_2/T_h2_out_Integrator",
    ),
    "electrical_paper_eta": (
        "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator",
        "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator",
        "final_steady_24a/precooler/precooler_2/T_h1_average_Integrator",
        "final_steady_24a/precooler/precooler_2/T_h2_out_Integrator",
    ),
}
EXPECTED_TRACE_ENDPOINTS = {
    "reactor": ("final_steady_24a/reactor/P_sw", 1, "input"),
    "turbine": ("final_steady_24a/TAC/Turbine", 4, "output"),
    "compressor": ("final_steady_24a/TAC/Compressor", 2, "output"),
}
# Filled from the compact audit generated by the hash-bound MATLAB generator.
EXPECTED_TRACE_HOP_SHA256: dict[tuple[str, str], str] = {
    ("reactor", "final_steady_24a/reactor/Integrator6"):
        "44c4b4fb81bbc2f0889f4427819095e1535459152dd3a711304d81633df27aa2",
    ("reactor", "final_steady_24a/reactor/Integrator7"):
        "29b7da3cd465f9fb2c26feee8c0b5206930f938338ce8abb5358c04b8501996e",
    ("turbine", "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"):
        "feb76056d6463a3c6a95490aaefd0d51f4aeae64232d97d6108a2a645453ed7b",
    ("turbine", "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"):
        "87fa8ae23d8a0d14b45201e5ea9e823dc536aee29c372efb5c7353fea276c533",
    ("compressor", "final_steady_24a/precooler/precooler_2/T_h1_average_Integrator"):
        "1361bfda8a86b5a13eff1668584949a35cfc0cb5320398b2f2bb75e0f1ad53d3",
    ("compressor", "final_steady_24a/precooler/precooler_2/T_h2_out_Integrator"):
        "22e8e311d34786626ef0a1a783224935f3389bac8caf8aa2ddd5532995a392e5",
}


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


def _finite_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _as_list(value: object) -> list[object]:
    if value == []:
        return []
    return value if isinstance(value, list) else [value]


def _close(actual: object, expected: float, *, absolute: float = 1e-15) -> bool:
    return _finite_number(actual) and math.isclose(actual, expected, rel_tol=1e-12, abs_tol=absolute)


def _validate_generation_contract(audit: dict[str, object]) -> None:
    contract = audit.get("generation_contract")
    generator = ROOT / "tests/audit_fig519_initialization.m"
    if (not isinstance(contract, dict) or
            contract.get("schema_version") != "steady53_fig519_initialization_v2_api_graph" or
            contract.get("generator_repository_path") != "tests/audit_fig519_initialization.m" or
            contract.get("generator_sha256") != _hash(generator.read_bytes()) or
            contract.get("model_sha256") != audit.get("model_sha256") or
            contract.get("raw_reference_sha256") != RAW_REFERENCE_SHA256 or
            "does not recompute MATLAB state values" not in contract.get("python_validation_scope", "") or
            "Simulink official API graph" not in contract.get("matlab_evidence_scope", "")):
        raise RuntimeError("initialization audit generation identity is incomplete")


def _validate_state_contract(audit: dict[str, object]) -> dict[str, dict[str, object]]:
    inventory = audit.get("state_inventory")
    required = {"path", "fluid", "kind", "sign_policy", "initial_condition_expression",
                "initial_condition", "t0_value", "t500_value", "absolute_change",
                "relative_change", "relative_change_defined", "first_sample_slope",
                "first_sample_slope_unit"}
    if not isinstance(inventory, list) or len(inventory) != 40 or any(not isinstance(item, dict) for item in inventory):
        raise RuntimeError("initialization audit state inventory is incomplete")
    paths = [item.get("path") for item in inventory]
    if len(set(paths)) != 40 or set(paths) != set(EXPECTED_STATE_PATHS):
        raise RuntimeError("initialization audit state path set mismatch")
    indexed: dict[str, dict[str, object]] = {}
    for state in inventory:
        if not required.issubset(state):
            raise RuntimeError("initialization audit state schema mismatch")
        if (not all(isinstance(state[field], str) and state[field] for field in
                    ("path", "fluid", "kind", "sign_policy", "initial_condition_expression",
                     "first_sample_slope_unit")) or
                not all(_finite_number(state[field]) for field in
                        ("initial_condition", "t0_value", "t500_value", "absolute_change",
                         "relative_change", "first_sample_slope")) or
                not isinstance(state["relative_change_defined"], bool)):
            raise RuntimeError(f"initialization audit state field is invalid: {state.get('path')}")
        t0 = state["t0_value"]
        delta = state["t500_value"] - t0
        relative_defined = t0 != 0.0
        if (not _close(state["initial_condition"], t0, absolute=1e-12) or
                not _close(state["absolute_change"], delta) or
                state["relative_change_defined"] is not relative_defined or
                (relative_defined and not _close(state["relative_change"], delta / t0))):
            raise RuntimeError(f"initialization audit state cross-field mismatch: {state['path']}")
        indexed[state["path"]] = state
    if indexed["final_steady_24a/reactor/Integrator6"]["initial_condition"] != 2660960.9141046703:
        raise RuntimeError("initialization audit reactor power IC mismatch")
    if indexed["final_steady_24a/reactor/Integrator7"]["initial_condition"] != 1721.8648882133552:
        raise RuntimeError("initialization audit reactor temperature IC mismatch")
    return indexed


def _validate_residual_contract(audit: dict[str, object],
                                states: dict[str, dict[str, object]]) -> None:
    section = audit.get("initial_residuals")
    records = section.get("items") if isinstance(section, dict) else None
    names = {item.get("name") for item in records} if isinstance(records, list) and all(
        isinstance(item, dict) for item in records) else set()
    expected = {
        "reactor_power_derivative": ("computed", "W/s",
            "(P_state(t1)-P_state(t0))/(t1-t0)",
            ("final_steady_24a/reactor/Integrator6",), ()),
        "shaft_excess_power": ("computed", "W", "WT(t0)-Wc(t0)-Pload",
            ("final_steady_24a/TAC/Turbine", "final_steady_24a/TAC/Compressor",
             "final_steady_24a/Constant14", "final_steady_24a/TAC/Pload"), ()),
        "ihx_energy": ("not_observable", "W",
            "Q_hot_in-Q_hot_out-(Q_cold_out-Q_cold_in)-dU_wall/dt",
            ("final_steady_24a/IHX",),
            ("IHX direct hot-side enthalpy-flow inlet/outlet",
             "IHX direct cold-side enthalpy-flow inlet/outlet", "IHX wall-energy derivative")),
        "recuperator_energy": ("not_observable", "W",
            "Q_hot_in-Q_hot_out-(Q_cold_out-Q_cold_in)-dU_wall/dt",
            ("final_steady_24a/recuperator",),
            ("recuperator direct hot-side enthalpy-flow inlet/outlet",
             "recuperator direct cold-side enthalpy-flow inlet/outlet",
             "recuperator wall-energy derivative")),
        "precooler_energy": ("not_observable", "W",
            "Q_hot_in-Q_hot_out-Q_coolant-dU_wall/dt", ("final_steady_24a/precooler",),
            ("precooler direct He-Xe enthalpy-flow inlet/outlet",
             "precooler direct coolant heat-flow inlet/outlet", "precooler wall-energy derivative")),
        "radiator_energy": ("not_observable", "W",
            "Q_coolant_in-Q_coolant_out-Q_radiated-dU_radiator/dt",
            ("final_steady_24a/rediator",),
            ("rediator direct coolant enthalpy-flow inlet/outlet",
             "rediator direct radiative heat rejection", "rediator stored-energy derivative")),
    }
    if names != set(expected) or len(records) != 6:
        raise RuntimeError("initialization audit residual set mismatch")
    for item in records:
        status, unit, formula, source_paths, missing = expected[item["name"]]
        if (item.get("status") != status or item.get("unit") != unit or
                item.get("formula") != formula or tuple(_as_list(item.get("source_paths"))) != source_paths or
                tuple(_as_list(item.get("missing_direct_signals"))) != missing):
            raise RuntimeError(f"initialization audit residual schema mismatch: {item['name']}")
        if status == "not_observable" and item.get("value") is not None:
            raise RuntimeError(f"initialization audit residual must remain unobserved: {item['name']}")
        if status == "computed" and not _finite_number(item.get("value")):
            raise RuntimeError(f"initialization audit computed residual is invalid: {item['name']}")
    indexed = {item["name"]: item for item in records}
    if not _close(indexed["reactor_power_derivative"]["value"],
                  states["final_steady_24a/reactor/Integrator6"]["first_sample_slope"]):
        raise RuntimeError("initialization audit reactor residual mismatch")
    if not _close(indexed["shaft_excess_power"]["value"], 35934.17908170889, absolute=1e-6):
        raise RuntimeError("initialization audit shaft residual mismatch")


def _validate_flat_state_evidence(audit: dict[str, object],
                                  states: dict[str, dict[str, object]]) -> None:
    flat = audit.get("flat_start_explanation")
    if not isinstance(flat, dict):
        raise RuntimeError("initialization audit flat-start evidence is missing")
    rule = flat.get("near_zero_rule")
    if (not isinstance(rule, dict) or
            rule.get("metric") != "abs(first_sample_slope)/max(abs(t0_value),1)" or
            rule.get("threshold_per_s") != 1e-6 or
            rule.get("classification") != "numerical diagnostic only; does not alter physical equations"):
        raise RuntimeError("initialization audit flat-start rule mismatch")
    derivative = _as_list(flat.get("state_derivative_evidence"))
    near_zero = _as_list(flat.get("near_zero_state_derivatives"))
    if any(not isinstance(item, dict) for item in derivative + near_zero):
        raise RuntimeError("initialization audit flat-start state evidence schema mismatch")
    derivative_by_path = {item.get("path"): item for item in derivative}
    if len(derivative_by_path) != 40 or set(derivative_by_path) != set(EXPECTED_STATE_PATHS):
        raise RuntimeError("initialization audit derivative state set mismatch")
    expected_near: set[str] = set()
    for path, state in states.items():
        normalized = abs(state["first_sample_slope"]) / max(abs(state["t0_value"]), 1.0)
        expected_flag = normalized <= rule["threshold_per_s"]
        evidence = derivative_by_path[path]
        if (not _close(evidence.get("first_sample_slope"), state["first_sample_slope"]) or
                not _close(evidence.get("normalized_first_sample_slope_per_s"), normalized) or
                evidence.get("near_zero_by_rule") is not expected_flag or
                not _close(evidence.get("absolute_change_500s"), state["absolute_change"])):
            raise RuntimeError(f"initialization audit derivative cross-field mismatch: {path}")
        if expected_flag:
            expected_near.add(path)
    near_by_path = {item.get("path"): item for item in near_zero}
    if len(near_by_path) != len(near_zero) or set(near_by_path) != expected_near:
        raise RuntimeError("initialization audit near-zero state set mismatch")
    for path, evidence in near_by_path.items():
        if evidence != derivative_by_path[path]:
            raise RuntimeError(f"initialization audit near-zero evidence mismatch: {path}")


def _trace_fingerprint(hops: list[dict[str, object]]) -> str:
    payload = json.dumps(hops, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return _hash(payload)


def _validate_power_mappings(audit: dict[str, object],
                             states: dict[str, dict[str, object]]) -> None:
    flat = audit["flat_start_explanation"]
    mappings = _as_list(flat.get("power_state_signal_mappings"))
    if len(mappings) != 4 or any(not isinstance(item, dict) for item in mappings):
        raise RuntimeError("initialization audit power mappings are incomplete")
    indexed = {item.get("power_definition"): item for item in mappings}
    if len(indexed) != 4 or set(indexed) != set(EXPECTED_MAPPING_STATES):
        raise RuntimeError("initialization audit power mapping definitions mismatch")
    near_paths = {item["path"] for item in _as_list(flat["near_zero_state_derivatives"])}
    hop_fields = {"from_block", "from_port", "from_port_kind", "to_block", "to_port",
                  "to_port_kind", "bridge_kind"}
    allowed_bridges = {"signal_line", "subsystem_inport", "subsystem_outport",
                       "goto_from", "block_dependency"}
    for name, expected_states in EXPECTED_MAPPING_STATES.items():
        mapping = indexed[name]
        traced_states = tuple(_as_list(mapping.get("traced_state_paths")))
        if traced_states != expected_states or not set(traced_states).issubset(states) or not set(traced_states).issubset(near_paths):
            raise RuntimeError(f"initialization audit mapped state set mismatch: {name}")
        signal_paths = _as_list(mapping.get("traced_signal_paths"))
        if not signal_paths or any(not isinstance(path, str) or not path.startswith("final_steady_24a/")
                                   and not path.startswith("offline ") for path in signal_paths):
            raise RuntimeError(f"initialization audit mapped signal path mismatch: {name}")
        traces = _as_list(mapping.get("api_trace_records"))
        if name == "electrical_paper_eta":
            if (mapping.get("api_verification_status") != "verified_offline_composition_of_api_traces" or
                    mapping.get("direct_model_endpoint_claimed") is not False or traces or
                    tuple(_as_list(mapping.get("composition_sources"))) != ("turbine", "compressor")):
                raise RuntimeError("initialization audit electrical mapping overclaims a direct endpoint")
            continue
        endpoint, endpoint_port, endpoint_port_kind = EXPECTED_TRACE_ENDPOINTS[name]
        if (mapping.get("api_verification_status") != "verified_by_official_api_graph" or
                mapping.get("direct_model_endpoint_claimed") is not True or
                _as_list(mapping.get("composition_sources")) or len(traces) != len(expected_states)):
            raise RuntimeError(f"initialization audit API mapping status mismatch: {name}")
        trace_by_state = {trace.get("state_path"): trace for trace in traces if isinstance(trace, dict)}
        if set(trace_by_state) != set(expected_states) or len(trace_by_state) != len(traces):
            raise RuntimeError(f"initialization audit API trace state set mismatch: {name}")
        for state_path in expected_states:
            trace = trace_by_state[state_path]
            hops = _as_list(trace.get("hops"))
            if (trace.get("status") != "verified_by_official_api_graph" or
                    trace.get("endpoint_block") != endpoint or not hops or
                    trace.get("endpoint_port") != endpoint_port or
                    trace.get("endpoint_port_kind") != endpoint_port_kind or
                    any(not isinstance(hop, dict) or set(hop) != hop_fields for hop in hops)):
                raise RuntimeError(f"initialization audit API trace schema mismatch: {name}:{state_path}")
            for index, hop in enumerate(hops):
                if (not all(isinstance(hop[field], str) and hop[field] for field in
                            ("from_block", "from_port_kind", "to_block", "to_port_kind", "bridge_kind")) or
                        not all(_finite_number(hop[field]) and float(hop[field]).is_integer() and hop[field] > 0
                                for field in ("from_port", "to_port")) or
                        hop["from_port_kind"] not in {"input", "output"} or
                        hop["to_port_kind"] not in {"input", "output"} or
                        hop["bridge_kind"] not in allowed_bridges or
                        not hop["from_block"].startswith("final_steady_24a/") or
                        not hop["to_block"].startswith("final_steady_24a/")):
                    raise RuntimeError(f"initialization audit API hop mismatch: {name}:{state_path}")
                if index and (hops[index - 1]["to_block"], hops[index - 1]["to_port"],
                              hops[index - 1]["to_port_kind"]) != (
                                  hop["from_block"], hop["from_port"], hop["from_port_kind"]):
                    raise RuntimeError(f"initialization audit API hop chain is discontinuous: {name}:{state_path}")
            if hops[0]["from_block"] != state_path or hops[0]["from_port_kind"] != "output":
                raise RuntimeError(f"initialization audit API trace source mismatch: {name}:{state_path}")
            if (hops[-1]["to_block"] != endpoint or hops[-1]["to_port"] != endpoint_port or
                    hops[-1]["to_port_kind"] != endpoint_port_kind):
                raise RuntimeError(f"initialization audit API trace endpoint mismatch: {name}:{state_path}")
            expected_hash = EXPECTED_TRACE_HOP_SHA256.get((name, state_path))
            if expected_hash is None or _trace_fingerprint(hops) != expected_hash:
                raise RuntimeError(f"initialization audit API trace identity mismatch: {name}:{state_path}")


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
        "compressor": "verified_by_official_api", "load": "verified_by_official_api",
        "electrical": "no_direct_generator_signal_found",
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
    load = paths["load"]
    if any(load.get(key) != value for key, value in {
            "source_block": "final_steady_24a/Constant14",
            "destination_block": "final_steady_24a/TAC",
            "destination_input_port": 6,
            "destination_inport_block": "final_steady_24a/TAC/Pload",
            "value_W": 1000210.0,
    }.items()):
        raise RuntimeError("initialization audit load path mismatch")
    boundary = audit["boundary_contract"]
    if boundary.get("load_input_classified") is not True:
        raise RuntimeError("initialization audit load boundary is not classified")
    residuals = audit["initial_residuals"].get("items")
    if not isinstance(residuals, list):
        raise RuntimeError("initialization audit residual records are missing")
    shaft = [item for item in residuals if item.get("name") == "shaft_excess_power"]
    required_paths = {"final_steady_24a/TAC/Turbine", "final_steady_24a/TAC/Compressor",
                      "final_steady_24a/Constant14", "final_steady_24a/TAC/Pload"}
    shaft_value = shaft[0].get("value") if len(shaft) == 1 else None
    if (len(shaft) != 1 or shaft[0].get("status") != "computed" or
            shaft[0].get("unit") != "W" or
            shaft[0].get("formula") != "WT(t0)-Wc(t0)-Pload" or
            not isinstance(shaft_value, (int, float)) or
            not math.isclose(shaft_value, 35934.17908170889,
                             rel_tol=0.0, abs_tol=1e-6) or
            not required_paths.issubset(set(shaft[0].get("source_paths", [])))):
        raise RuntimeError("initialization audit shaft residual mismatch")
    flat = audit["flat_start_explanation"]
    rule = flat.get("near_zero_rule")
    near_zero = flat.get("near_zero_state_derivatives")
    mappings = flat.get("power_state_signal_mappings")
    if (not isinstance(rule, dict) or
            rule.get("metric") != "abs(first_sample_slope)/max(abs(t0_value),1)" or
            not isinstance(rule.get("threshold_per_s"), (int, float)) or
            rule["threshold_per_s"] <= 0 or not isinstance(near_zero, list) or not near_zero or
            not isinstance(mappings, list) or len(mappings) != 4 or
            flat.get("paper_initial_state_identified") is not False):
        raise RuntimeError("initialization audit flat-start rule is incomplete")
    expected_definitions = {"reactor", "turbine", "compressor", "electrical_paper_eta"}
    if {item.get("power_definition") for item in mappings} != expected_definitions:
        raise RuntimeError("initialization audit power-state mapping definitions mismatch")
    inventory_paths = {item.get("path") for item in audit["state_inventory"]}
    for mapping in mappings:
        states = mapping.get("traced_state_paths")
        signals = mapping.get("traced_signal_paths")
        if (not isinstance(states, list) or not states or not set(states).issubset(inventory_paths) or
                not isinstance(signals, list) or not signals or
                any(not isinstance(path, str) or not path for path in signals)):
            raise RuntimeError("initialization audit power-state mapping is incomplete")
    samples = solver.get("compiled_sample_times")
    if not isinstance(samples, list) or not samples:
        raise RuntimeError("initialization audit sample-time semantics are missing")
    constant_samples = [item for item in samples if item.get("description") == "Constant"]
    if (len(constant_samples) != 1 or constant_samples[0].get("is_infinite") is not True or
            constant_samples[0].get("semantic") != "constant sample time (infinite period)" or
            constant_samples[0].get("infinite_positions") != 1):
        raise RuntimeError("initialization audit constant sample-time semantics mismatch")
    sources = boundary.get("root_source_blocks")
    if not isinstance(sources, list) or len(sources) != 2:
        raise RuntimeError("initialization audit root source enumeration mismatch")
    source_by_path = {item.get("path"): item for item in sources}
    expected_destinations = {
        "final_steady_24a/Constant": ("6.95", "final_steady_24a/precooler", 2),
        "final_steady_24a/Constant14": ("1000.21e3", "final_steady_24a/TAC", 6),
    }
    if set(source_by_path) != set(expected_destinations):
        raise RuntimeError("initialization audit root source path mismatch")
    for path, (expression, destination, port) in expected_destinations.items():
        source = source_by_path[path]
        connections = _as_list(source.get("destination_connections"))
        if (source.get("block_type") != "Constant" or source.get("value_expression") != expression or
                len(connections) != 1 or connections[0].get("to_block") != destination or
                connections[0].get("to_port") != port or
                connections[0].get("bridge_kind") != "signal_line"):
            raise RuntimeError(f"initialization audit root source destination mismatch: {path}")
    if not {"p_e", "wgen", "pgen", "pelec"}.issubset(set(paths["electrical"].get("search_terms", []))):
        raise RuntimeError("initialization audit direct generator negative search is incomplete")
    _validate_generation_contract(audit)
    exact_states = _validate_state_contract(audit)
    _validate_residual_contract(audit, exact_states)
    _validate_flat_state_evidence(audit, exact_states)
    _validate_power_mappings(audit, exact_states)


def _validate_raw_reference(audit: dict[str, object]) -> dict[str, object]:
    raw = audit.get("raw_reference")
    expected = ROOT / RAW_REFERENCE_RELATIVE
    if (not isinstance(raw, dict) or
            raw.get("repository_relative_path") != RAW_REFERENCE_RELATIVE.as_posix() or
            raw.get("absolute_path") != str(expected) or
            raw.get("sha256") != RAW_REFERENCE_SHA256 or
            raw.get("bytes") != RAW_REFERENCE_BYTES):
        raise RuntimeError("initialization audit raw reference identity mismatch")
    checked = _safe(expected)
    if checked != expected or checked.is_symlink() or not checked.is_file():
        raise RuntimeError("initialization audit raw reference is missing or unsafe")
    payload = checked.read_bytes()
    if len(payload) != RAW_REFERENCE_BYTES or _hash(payload) != RAW_REFERENCE_SHA256:
        raise RuntimeError("initialization audit raw reference hash or byte count mismatch")
    return raw


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
            "load": {
                "model_signal": "Pload", "kind": "fixed_boundary_power",
                "status": "verified_by_official_api",
                "api_source_block": paths["load"]["source_block"],
                "api_destination_block": paths["load"]["destination_block"],
                "api_destination_input_port": paths["load"]["destination_input_port"],
                "api_destination_inport_block": paths["load"]["destination_inport_block"],
                "value_W": paths["load"]["value_W"],
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
    _validate_raw_reference(audit)
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


def manifest_bytes_with_external(output: Path, entries: dict[str, bytes],
                                 roles: dict[str, tuple[str, str]],
                                 audit: dict[str, object]) -> bytes:
    """Build the compatible durable manifest plus one external raw locator.

    The external row records identity and location only.  It deliberately does
    not imply that the raw MAT file was copied into the durable publication.
    """
    raw = _validate_raw_reference(audit)
    output = _safe(output)
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
    writer.writerow(("@external/raw_reference.mat", raw["bytes"], raw["sha256"],
                     "external raw evidence locator",
                     "unmodified-500s-reference;not-copied-to-durable-publication",
                     "external_tmp_not_copied", raw["repository_relative_path"],
                     raw["absolute_path"]))
    return stream.getvalue().encode()


def _unified_manifest(output: Path, baseline: dict[str, bytes], generated: dict[str, bytes]) -> bytes:
    paper_bytes = {name: (output / name).read_bytes() for name in paper.ARTIFACT_NAMES}
    entries = dict(paper_bytes)
    entries.update({f"{paper.BASELINE_LAYER_DIR}/{name}": payload for name, payload in baseline.items()})
    entries.update(generated)
    audit, audit_payload = _audit_from_output(output)
    if audit_payload is not None:
        entries[INITIALIZATION_AUDIT_NAME] = audit_payload
        return manifest_bytes_with_external(output, entries, _roles(), audit)
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
    if audit is not None:
        delta["manifest.csv"] = manifest_bytes_with_external(
            output, entries, _roles(), audit)
    else:
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
    base = ("path", "bytes", "sha256", "role", "identity")
    extended = base + ("storage", "repository_relative_path", "absolute_path")
    fieldnames = extended if rows and set(rows[0]) == set(extended) else base
    writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
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
