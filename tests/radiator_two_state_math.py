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
    return 1000.0 * (
        1.061 - 3.694e-4 * temperature_K + 4.615e-8 * temperature_K**2
        + 1.509e-10 * temperature_K**3
    )


def h_nak_J_kg(temperature_K: float) -> float:
    """Analytic integral of :func:`cp_nak_J_kgK`, with zero constant."""
    if not _finite(temperature_K):
        raise ValueError("temperature must be finite")
    return 1000.0 * (
        1.061 * temperature_K - 3.694e-4 * temperature_K**2 / 2.0
        + 4.615e-8 * temperature_K**3 / 3.0
        + 1.509e-10 * temperature_K**4 / 4.0
    )


def q_inlet_cp_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    if not _finite(tin_K, tout_K, m_dot_kg_s):
        raise ValueError("energy inputs must be finite")
    return m_dot_kg_s * cp_nak_J_kgK(tin_K) * (tin_K - tout_K)


def q_integral_enthalpy_W(tin_K: float, tout_K: float, m_dot_kg_s: float) -> float:
    if not _finite(tin_K, tout_K, m_dot_kg_s):
        raise ValueError("energy inputs must be finite")
    return m_dot_kg_s * (h_nak_J_kg(tin_K) - h_nak_J_kg(tout_K))


ENERGY_FUNCTIONS: Mapping[str, QFunction] = MappingProxyType({
    "inlet_cp": q_inlet_cp_W,
    "integral_enthalpy": q_integral_enthalpy_W,
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
    sse = sum(residual_J(row, capacity, ua) ** 2 for row in rows)
    if not _finite(sse):
        raise ValueError("solution SSE is nonfinite")
    return Solution(capacity, ua, sse)


def _normal_terms(rows: tuple[Coefficient, ...]) -> tuple[float, float, float, float, float]:
    aa = sum(row.A_K**2 for row in rows)
    ab = sum(row.A_K * row.B_K_s for row in rows)
    bb = sum(row.B_K_s**2 for row in rows)
    ad = sum(row.A_K * row.D_J for row in rows)
    bd = sum(row.B_K_s * row.D_J for row in rows)
    if not _finite(aa, ab, bb, ad, bd):
        raise ValueError("normal equations are nonfinite")
    return aa, ab, bb, ad, bd


def solve_unrestricted(rows: Iterable[Coefficient]) -> Solution:
    """Solve the exact two-by-two normal equations with no optimizer."""
    materialized = _validated_rows(rows)
    aa, ab, bb, ad, bd = _normal_terms(materialized)
    determinant = aa * bb - ab * ab
    scale = max(abs(aa * bb), abs(ab * ab), 1.0)
    if not math.isfinite(determinant) or determinant <= ZERO_TOLERANCE * scale:
        raise ValueError("rank-deficient interval system")
    capacity = (ad * bb - bd * ab) / determinant
    ua = (bd * aa - ad * ab) / determinant
    return _solution(materialized, capacity, ua)


def solve_nnls(rows: Iterable[Coefficient]) -> Solution:
    """Analytic non-negative least squares over interior, axes, and origin."""
    materialized = _validated_rows(rows)
    aa, _ab, bb, ad, bd = _normal_terms(materialized)
    if aa <= ZERO_TOLERANCE or bb <= ZERO_TOLERANCE:
        raise ValueError("NNLS boundary denominator is rank-deficient")
    unrestricted = solve_unrestricted(materialized)
    candidates = [_solution(materialized, 0.0, 0.0)]
    if unrestricted.C_fluid_J_K >= 0.0 and unrestricted.UA_W_K >= 0.0:
        candidates.append(unrestricted)
    candidates.append(_solution(materialized, max(0.0, ad / aa), 0.0))
    candidates.append(_solution(materialized, 0.0, max(0.0, bd / bb)))
    return min(candidates, key=lambda item: (item.sse_J2, item.C_fluid_J_K, item.UA_W_K))


def _gate(values_upper: list[float], values_required: list[float], prefix: str) -> Mapping[str, float | bool]:
    if not values_upper or not values_required:
        raise ValueError("sign gate requires rising and plateau intervals")
    upper = min(values_upper)
    required = max(values_required)
    if not _finite(upper, required):
        raise ValueError("sign gate ratio is nonfinite")
    return MappingProxyType({
        f"{prefix}rising_UA_upper_W_K": upper,
        f"{prefix}plateau_UA_required_W_K": required,
        "conflict": required > upper,
    })


def nominal_sign_gate(rows: Iterable[Coefficient]) -> Mapping[str, float | bool]:
    materialized = _validated_rows(rows)
    rising = [row.D_J / row.B_K_s for row in materialized if row.A_K > ZERO_TOLERANCE and row.B_K_s > 0.0]
    plateau = [row.D_J / row.B_K_s for row in materialized if abs(row.A_K) <= ZERO_TOLERANCE and row.B_K_s > 0.0]
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
    rising_indexes = [index for index, row in enumerate(nominal) if row.A_K > ZERO_TOLERANCE]
    plateau_indexes = [index for index, row in enumerate(nominal) if abs(row.A_K) <= ZERO_TOLERANCE]
    if not rising_indexes or not plateau_indexes:
        raise ValueError("sign gate requires rising and plateau intervals")
    ratio_ranges = {}
    for index, (first, second) in enumerate(zip(materialized, materialized[1:])):
        ratios = []
        for to_a, tw_a, to_b, tw_b in itertools.product((-1.0, 1.0), repeat=4):
            shifted_first = _shift(first, to_a * temperature_allowance_K, tw_a * temperature_allowance_K, 0.0)
            shifted_second = _shift(second, to_b * temperature_allowance_K, tw_b * temperature_allowance_K, 0.0)
            row = interval_coefficient(shifted_first, shifted_second, tin_K, m_dot_kg_s, q_function, index)
            if row.B_K_s > 0.0:
                ratio = row.D_J / row.B_K_s
                if math.isfinite(ratio):
                    ratios.append(ratio)
        if not ratios:
            raise ValueError("uncertainty sign gate has no positive B interval")
        ratio_ranges[index] = (min(ratios), max(ratios))
    return _gate(
        [ratio_ranges[index][1] for index in rising_indexes],
        [ratio_ranges[index][0] for index in plateau_indexes],
        "favorable_",
    )


def aggregate_case_enums(case_enums: Iterable[str]) -> str:
    values = tuple(case_enums)
    if len(values) != 4:
        raise ValueError("exactly four fixed cases are required")
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
