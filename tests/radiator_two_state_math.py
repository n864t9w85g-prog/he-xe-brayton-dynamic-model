"""Deterministic interval mathematics for the radiator two-state gate."""
from __future__ import annotations

from dataclasses import dataclass
import itertools
import math
from types import MappingProxyType
from typing import Callable, Iterable, Mapping

from tests import radiator_two_state_contract as contract


QFunction = Callable[[float, float, float], float]
ZERO_TOLERANCE = 1e-12


@dataclass(frozen=True)
class Coefficient:
    interval_index: int
    start_s: float
    end_s: float
    A_K: float
    B_K_s: float
    D_J: float


@dataclass(frozen=True)
class Solution:
    C_fluid_J_K: float
    UA_W_K: float
    sse_J2: float


@dataclass(frozen=True)
class ResidualRange:
    minimum_J: float
    maximum_J: float
    contains_zero: bool
    admissible_corner_count: int


@dataclass(frozen=True)
class IntervalAnalysis:
    coefficient: Coefficient
    residual_J: float
    relative_residual: float
    conditional_C_fluid_J_K: float | None
    corner_range: ResidualRange | None


@dataclass(frozen=True)
class CaseAnalysis:
    case: contract.Case
    case_enum: str
    nominal_sign_gate: Mapping[str, float | bool]
    favorable_sign_gate: Mapping[str, float | bool]
    unrestricted_solution: Solution
    nnls_solution: Solution
    equivalent_mass_kg: float | None
    all_intervals_locally_compatible: bool
    intervals: tuple[IntervalAnalysis, ...]


def _finite(*values: float) -> bool:
    return all(math.isfinite(value) for value in values)


def cp_nak_J_kgK(temperature_K: float) -> float:
    """NaK specific heat capacity in J/(kg K)."""
    if not _finite(temperature_K):
        raise ValueError("temperature must be finite")
    try:
        result = 1000.0 * (
            1.061 - 3.694e-4 * temperature_K + 4.615e-8 * temperature_K**2
            + 1.509e-10 * temperature_K**3
        )
    except OverflowError as exc:
        raise ValueError("NaK cp polynomial overflow") from exc
    if not math.isfinite(result):
        raise ValueError("NaK cp polynomial is nonfinite")
    return result


def h_nak_J_kg(temperature_K: float) -> float:
    """Analytic integral of :func:`cp_nak_J_kgK`, with zero constant."""
    if not _finite(temperature_K):
        raise ValueError("temperature must be finite")
    try:
        result = 1000.0 * (
            1.061 * temperature_K - 3.694e-4 * temperature_K**2 / 2.0
            + 4.615e-8 * temperature_K**3 / 3.0
            + 1.509e-10 * temperature_K**4 / 4.0
        )
    except OverflowError as exc:
        raise ValueError("NaK enthalpy polynomial overflow") from exc
    if not math.isfinite(result):
        raise ValueError("NaK enthalpy polynomial is nonfinite")
    return result


def q_inlet_cp_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    if not _finite(tin_K, tout_K, m_dot_kg_s):
        raise ValueError("energy inputs must be finite")
    try:
        result = m_dot_kg_s * cp_nak_J_kgK(tin_K) * (tin_K - tout_K)
    except OverflowError as exc:
        raise ValueError("inlet-cp energy overflow") from exc
    if not math.isfinite(result):
        raise ValueError("inlet-cp energy is nonfinite")
    return result


def q_integral_enthalpy_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    if not _finite(tin_K, tout_K, m_dot_kg_s):
        raise ValueError("energy inputs must be finite")
    try:
        result = m_dot_kg_s * (h_nak_J_kg(tin_K) - h_nak_J_kg(tout_K))
    except OverflowError as exc:
        raise ValueError("integral-enthalpy energy overflow") from exc
    if not math.isfinite(result):
        raise ValueError("integral-enthalpy energy is nonfinite")
    return result


ENERGY_FUNCTIONS: Mapping[str, QFunction] = MappingProxyType({
    "inlet_cp": q_inlet_cp_W,
    "integral_enthalpy": q_integral_enthalpy_W,
})
CASE_ENUMS = frozenset({
    "robustly_infeasible",
    "reading_sensitive",
    "conditionally_feasible",
    "full_interval_inconsistent",
})


def _mean_temperature(tin_K: float, outlet_K: float) -> float:
    return 0.8 * tin_K + 0.2 * outlet_K


def interval_coefficient(
    first: contract.Sample,
    second: contract.Sample,
    tin_K: float,
    m_dot_kg_s: float,
    q_function: QFunction,
    interval_index: int = 0,
) -> Coefficient:
    """Return trapezoidal coefficients for one ordered pair of samples."""
    values = (
        first.time_s, first.wall_K, first.outlet_K,
        second.time_s, second.wall_K, second.outlet_K, tin_K, m_dot_kg_s,
    )
    if not _finite(*values):
        raise ValueError("interval inputs must be finite")
    duration_s = second.time_s - first.time_s
    if duration_s <= 0.0:
        raise ValueError("interval duration must be finite and positive")
    mean_first = _mean_temperature(tin_K, first.outlet_K)
    mean_second = _mean_temperature(tin_K, second.outlet_K)
    try:
        q_first = q_function(tin_K, first.outlet_K, m_dot_kg_s)
        q_second = q_function(tin_K, second.outlet_K, m_dot_kg_s)
    except (ArithmeticError, TypeError, ValueError) as exc:
        raise ValueError("energy function failed") from exc
    coefficient_values = (
        mean_second - mean_first,
        duration_s * ((mean_first - first.wall_K) + (mean_second - second.wall_K)) / 2.0,
        duration_s * (q_first + q_second) / 2.0,
    )
    if not _finite(q_first, q_second, *coefficient_values):
        raise ValueError("interval coefficient is nonfinite")
    return Coefficient(interval_index, first.time_s, second.time_s, *coefficient_values)


def residual_J(row: Coefficient, C_fluid_J_K: float, UA_W_K: float) -> float:
    if not _finite(row.A_K, row.B_K_s, row.D_J, C_fluid_J_K, UA_W_K):
        raise ValueError("residual inputs must be finite")
    result = row.A_K * C_fluid_J_K + row.B_K_s * UA_W_K - row.D_J
    if not _finite(result):
        raise ValueError("residual is nonfinite")
    return result


def _validated_rows(rows: Iterable[Coefficient]) -> tuple[Coefficient, ...]:
    materialized = tuple(rows)
    if not materialized:
        raise ValueError("interval system must not be empty")
    for row in materialized:
        if not _finite(row.A_K, row.B_K_s, row.D_J):
            raise ValueError("interval system contains nonfinite coefficient")
    return materialized


def _solution(rows: tuple[Coefficient, ...], capacity: float, ua: float) -> Solution:
    if not _finite(capacity, ua):
        raise ValueError("solution parameter is nonfinite")
    try:
        sse = math.fsum(residual_J(row, capacity, ua) ** 2 for row in rows)
    except OverflowError as exc:
        raise ValueError("solution SSE overflow") from exc
    if not _finite(sse):
        raise ValueError("solution SSE is nonfinite")
    return Solution(capacity, ua, sse)


def _dot(left: tuple[float, ...], right: tuple[float, ...], label: str) -> float:
    try:
        result = math.fsum(value * other for value, other in zip(left, right))
    except OverflowError as exc:
        raise ValueError(f"{label} overflow") from exc
    if not math.isfinite(result):
        raise ValueError(f"{label} is nonfinite")
    return result


def _norm(values: tuple[float, ...], label: str) -> float:
    try:
        result = math.hypot(*values)
    except OverflowError as exc:
        raise ValueError(f"{label} overflow") from exc
    if not math.isfinite(result):
        raise ValueError(f"{label} is nonfinite")
    return result


def _axis_candidate(
    rows: tuple[Coefficient, ...], column: tuple[float, ...], axis: str
) -> Solution | None:
    scale = max(abs(value) for value in column)
    if scale == 0.0:
        return None
    scaled = tuple(value / scale for value in column)
    denominator = _dot(scaled, scaled, f"{axis} axis denominator")
    numerator = _dot(scaled, tuple(row.D_J for row in rows), f"{axis} axis numerator")
    parameter = max(0.0, numerator / denominator / scale)
    if axis == "capacity":
        return _solution(rows, parameter, 0.0)
    return _solution(rows, 0.0, parameter)


def _columns_are_exactly_collinear(
    first: tuple[float, ...], second: tuple[float, ...]
) -> bool:
    pivot = next((index for index, value in enumerate(first) if value != 0.0), None)
    if pivot is None:
        return True
    ratio = second[pivot] / first[pivot]
    return all(other == ratio * value for value, other in zip(first, second))


def _qr_unrestricted_solution(rows: tuple[Coefficient, ...]) -> Solution:
    first = tuple(row.A_K for row in rows)
    second = tuple(row.B_K_s for row in rows)
    first_scale = max(abs(value) for value in first)
    second_scale = max(abs(value) for value in second)
    if first_scale == 0.0 or second_scale == 0.0:
        raise ValueError("rank-deficient interval system has a zero column")
    first_scaled = tuple(value / first_scale for value in first)
    second_scaled = tuple(value / second_scale for value in second)
    if _columns_are_exactly_collinear(first_scaled, second_scaled):
        raise ValueError("rank-deficient interval system has collinear columns")
    r11 = _norm(first_scaled, "QR first-column norm")
    if r11 == 0.0:
        raise ValueError("rank-deficient interval system")
    q1 = tuple(value / r11 for value in first_scaled)
    r12 = _dot(q1, second_scaled, "QR first projection")
    residual = tuple(value - r12 * basis for value, basis in zip(second_scaled, q1))
    correction = _dot(q1, residual, "QR re-orthogonalization")
    r12 = math.fsum((r12, correction))
    residual = tuple(value - correction * basis for value, basis in zip(residual, q1))
    r22 = _norm(residual, "QR second-column norm")
    if r22 == 0.0:
        raise ValueError("rank-deficient interval system")
    q2 = tuple(value / r22 for value in residual)
    observed = tuple(row.D_J for row in rows)
    y1 = _dot(q1, observed, "QR first right-hand projection")
    y2 = _dot(q2, observed, "QR second right-hand projection")
    scaled_ua = y2 / r22
    scaled_capacity = (y1 - r12 * scaled_ua) / r11
    capacity = scaled_capacity / first_scale
    ua = scaled_ua / second_scale
    return _solution(rows, capacity, ua)


def solve_unrestricted(rows: Iterable[Coefficient]) -> Solution:
    """Solve the full-rank two-column system by scaled, re-orthogonalized QR."""
    materialized = _validated_rows(rows)
    return _qr_unrestricted_solution(materialized)


def solve_nnls(rows: Iterable[Coefficient]) -> Solution:
    """Analytic non-negative least squares over interior, axes, and origin."""
    materialized = _validated_rows(rows)
    candidates = [_solution(materialized, 0.0, 0.0)]
    capacity_axis = _axis_candidate(
        materialized, tuple(row.A_K for row in materialized), "capacity"
    )
    ua_axis = _axis_candidate(
        materialized, tuple(row.B_K_s for row in materialized), "UA"
    )
    candidates.extend(candidate for candidate in (capacity_axis, ua_axis) if candidate)
    try:
        unrestricted = solve_unrestricted(materialized)
    except ValueError:
        unrestricted = None
    if (
        unrestricted
        and unrestricted.C_fluid_J_K >= 0.0
        and unrestricted.UA_W_K >= 0.0
    ):
        candidates.append(unrestricted)
    return min(
        candidates,
        key=lambda item: (item.sse_J2, item.C_fluid_J_K, item.UA_W_K),
    )


def _plateau_ratios_consistent(values: list[float]) -> bool:
    reference = values[0]
    return all(
        math.isclose(value, reference, rel_tol=1e-12, abs_tol=0.0)
        for value in values[1:]
    )


def _strict_positive_ratio_conflict(
    upper: float, required: float, plateau_consistent: bool
) -> bool:
    return (
        not plateau_consistent
        or upper <= 0.0
        or required <= 0.0
        or required >= upper
    )


def _gate(
    values_upper: list[float], values_required: list[float], prefix: str
) -> Mapping[str, float | bool]:
    if not values_upper or not values_required:
        raise ValueError("sign gate requires rising and plateau intervals")
    upper = min(values_upper)
    required = max(values_required)
    if not _finite(upper, required):
        raise ValueError("sign gate ratio is nonfinite")
    plateau_consistent = _plateau_ratios_consistent(values_required)
    ratio_conflict = _strict_positive_ratio_conflict(
        upper, required, plateau_consistent
    )
    return MappingProxyType({
        f"{prefix}rising_UA_upper_W_K": upper,
        f"{prefix}plateau_UA_required_W_K": required,
        "plateau_consistent": plateau_consistent,
        "strict_positive_ratio_conflict": ratio_conflict,
        "conflict": ratio_conflict,
    })


def nominal_sign_gate(rows: Iterable[Coefficient]) -> Mapping[str, float | bool]:
    materialized = _validated_rows(rows)
    rising = [
        row.D_J / row.B_K_s
        for row in materialized
        if row.A_K > ZERO_TOLERANCE and row.B_K_s > 0.0
    ]
    plateau = [
        row.D_J / row.B_K_s
        for row in materialized
        if abs(row.A_K) <= ZERO_TOLERANCE and row.B_K_s > 0.0
    ]
    return _gate(rising, plateau, "")


def _shift(sample: contract.Sample, outlet_delta: float, wall_delta: float, time_delta: float) -> contract.Sample:
    return contract.Sample(
        sample.x_px, sample.wall_y_px, sample.outlet_y_px, sample.time_s + time_delta,
        sample.wall_K + wall_delta, sample.outlet_K + outlet_delta,
    )


def corner_residual_range(
    first: contract.Sample,
    second: contract.Sample,
    candidate: Solution,
    tin_K: float,
    m_dot_kg_s: float,
    q_function: QFunction,
    temperature_allowance_K: float,
    time_allowance_s: float,
) -> ResidualRange:
    if not _finite(temperature_allowance_K, time_allowance_s) or temperature_allowance_K < 0.0 or time_allowance_s < 0.0:
        raise ValueError("uncertainty allowances must be finite and nonnegative")
    residuals = []
    for signs in itertools.product((-1.0, 1.0), repeat=6):
        to_a, tw_a, time_a, to_b, tw_b, time_b = signs
        shifted_first = _shift(first, to_a * temperature_allowance_K, tw_a * temperature_allowance_K, time_a * time_allowance_s)
        shifted_second = _shift(second, to_b * temperature_allowance_K, tw_b * temperature_allowance_K, time_b * time_allowance_s)
        if shifted_second.time_s <= shifted_first.time_s:
            continue
        row = interval_coefficient(shifted_first, shifted_second, tin_K, m_dot_kg_s, q_function)
        residuals.append(residual_J(row, candidate.C_fluid_J_K, candidate.UA_W_K))
    if not residuals:
        raise ValueError("no admissible ordered uncertainty corners")
    minimum, maximum = min(residuals), max(residuals)
    return ResidualRange(
        minimum, maximum,
        minimum <= ZERO_TOLERANCE and maximum >= -ZERO_TOLERANCE,
        len(residuals),
    )


def favorable_sign_gate(
    samples: Iterable[contract.Sample],
    tin_K: float,
    m_dot_kg_s: float,
    q_function: QFunction,
    temperature_allowance_K: float,
) -> Mapping[str, float | bool]:
    if not _finite(temperature_allowance_K) or temperature_allowance_K < 0.0:
        raise ValueError("temperature allowance must be finite and nonnegative")
    materialized = tuple(samples)
    nominal = tuple(
        interval_coefficient(first, second, tin_K, m_dot_kg_s, q_function, index)
        for index, (first, second) in enumerate(zip(materialized, materialized[1:]))
    )
    rising_indexes = [
        index for index, row in enumerate(nominal) if row.A_K > ZERO_TOLERANCE
    ]
    plateau_indexes = [
        index
        for index, row in enumerate(nominal)
        if abs(row.A_K) <= ZERO_TOLERANCE
    ]
    if not rising_indexes or not plateau_indexes:
        raise ValueError("sign gate requires rising and plateau intervals")
    ratio_ranges = {}
    rising_preserved = {index: True for index in rising_indexes}
    plateau_preserved = {index: True for index in plateau_indexes}
    for index, (first, second) in enumerate(zip(materialized, materialized[1:])):
        ratios = []
        for to_a, tw_a, to_b, tw_b in itertools.product((-1.0, 1.0), repeat=4):
            shifted_first = _shift(
                first,
                to_a * temperature_allowance_K,
                tw_a * temperature_allowance_K,
                0.0,
            )
            shifted_second = _shift(
                second,
                to_b * temperature_allowance_K,
                tw_b * temperature_allowance_K,
                0.0,
            )
            row = interval_coefficient(
                shifted_first,
                shifted_second,
                tin_K,
                m_dot_kg_s,
                q_function,
                index,
            )
            if index in rising_preserved and not (
                row.A_K > ZERO_TOLERANCE and row.B_K_s > 0.0
            ):
                rising_preserved[index] = False
            if index in plateau_preserved and not (
                abs(row.A_K) <= ZERO_TOLERANCE and row.B_K_s > 0.0
            ):
                plateau_preserved[index] = False
            if row.B_K_s > 0.0:
                ratio = row.D_J / row.B_K_s
                if math.isfinite(ratio):
                    ratios.append(ratio)
        ratio_ranges[index] = (
            (min(ratios), max(ratios)) if ratios else (math.nan, math.nan)
        )
    rising_upper_values = [ratio_ranges[index][1] for index in rising_indexes]
    plateau_required_values = [
        ratio_ranges[index][0] for index in plateau_indexes
    ]
    if _finite(*rising_upper_values, *plateau_required_values):
        gate = _gate(
            rising_upper_values, plateau_required_values, "favorable_"
        )
    else:
        gate = MappingProxyType({
            "favorable_rising_UA_upper_W_K": math.nan,
            "favorable_plateau_UA_required_W_K": math.nan,
            "plateau_consistent": False,
            "strict_positive_ratio_conflict": False,
            "conflict": False,
        })
    sign_class_preserved = all(rising_preserved.values()) and all(
        plateau_preserved.values()
    )
    values = dict(gate)
    values["sign_class_preserved"] = sign_class_preserved
    values["conflict"] = sign_class_preserved and bool(
        gate["strict_positive_ratio_conflict"]
    )
    return MappingProxyType(values)


def aggregate_case_enums(case_enums: Iterable[str]) -> str:
    values = tuple(case_enums)
    if len(values) != 4:
        raise ValueError("exactly four fixed cases are required")
    if any(value not in CASE_ENUMS for value in values):
        raise ValueError("unknown case enum")
    if all(value == "robustly_infeasible" for value in values):
        return "constant_positive_two_state_robustly_infeasible"
    if all(value in {"robustly_infeasible", "reading_sensitive"} for value in values):
        return "constant_positive_two_state_nominally_infeasible_but_reading_sensitive"
    if any(value == "conditionally_feasible" for value in values):
        return "constant_positive_two_state_conditionally_feasible"
    return "constant_positive_two_state_full_interval_inconsistent"


def analyze_case(case: contract.Case, samples: Iterable[contract.Sample]) -> CaseAnalysis:
    """Analyze one frozen flow/energy identity against exactly twelve samples."""
    if not isinstance(case, contract.Case):
        raise ValueError("case must be a contract Case")
    if case.energy_path not in ENERGY_FUNCTIONS:
        raise ValueError("unknown energy path")
    if not _finite(case.m_dot_kg_s) or case.m_dot_kg_s <= 0.0:
        raise ValueError("case flow must be finite and positive")
    materialized = tuple(samples)
    if len(materialized) != 12:
        raise ValueError("exactly 12 samples are required")
    for sample in materialized:
        if not isinstance(sample, contract.Sample) or not _finite(sample.x_px, sample.wall_y_px, sample.outlet_y_px, sample.time_s, sample.wall_K, sample.outlet_K):
            raise ValueError("sample must be finite contract data")
    if any(second.time_s <= first.time_s for first, second in zip(materialized, materialized[1:])):
        raise ValueError("sample times must be strictly increasing")
    q_function = ENERGY_FUNCTIONS[case.energy_path]
    rows = tuple(
        interval_coefficient(first, second, contract.TIN_K, case.m_dot_kg_s, q_function, index)
        for index, (first, second) in enumerate(zip(materialized, materialized[1:]))
    )
    nominal = nominal_sign_gate(rows)
    favorable = favorable_sign_gate(materialized, contract.TIN_K, case.m_dot_kg_s, q_function, contract.TEMPERATURE_ALLOWANCE_K)
    unrestricted = solve_unrestricted(rows)
    nnls = solve_nnls(rows)
    positive_candidate = unrestricted.C_fluid_J_K > 0.0 and unrestricted.UA_W_K > 0.0
    corner_ranges = ()
    if positive_candidate:
        corner_ranges = tuple(
            corner_residual_range(first, second, unrestricted, contract.TIN_K, case.m_dot_kg_s, q_function, contract.TEMPERATURE_ALLOWANCE_K, contract.TIME_ALLOWANCE_S)
            for first, second in zip(materialized, materialized[1:])
        )
    intervals = tuple(
        IntervalAnalysis(
            row,
            residual_J(row, unrestricted.C_fluid_J_K, unrestricted.UA_W_K),
            residual_J(row, unrestricted.C_fluid_J_K, unrestricted.UA_W_K) / max(abs(row.D_J), 1.0),
            (row.D_J - row.B_K_s * unrestricted.UA_W_K) / row.A_K if abs(row.A_K) > ZERO_TOLERANCE else None,
            corner_ranges[index] if positive_candidate else None,
        )
        for index, row in enumerate(rows)
    )
    locally_compatible = positive_candidate and all(item.contains_zero for item in corner_ranges)
    if nominal["conflict"] and favorable["conflict"]:
        case_enum = "robustly_infeasible"
    elif nominal["conflict"]:
        case_enum = "reading_sensitive"
    elif locally_compatible:
        case_enum = "conditionally_feasible"
    else:
        case_enum = "full_interval_inconsistent"
    return CaseAnalysis(
        case, case_enum, nominal, favorable, unrestricted, nnls,
        unrestricted.C_fluid_J_K / cp_nak_J_kgK(contract.TIN_K) if unrestricted.C_fluid_J_K > 0.0 else None,
        locally_compatible, intervals,
    )
