"""Deterministic pure-math necessary-condition screen for radiator A1."""
from __future__ import annotations

from dataclasses import dataclass
import itertools
import math

from tests import radiator_a1_contract as contract
from tests import radiator_candidate_math


SIGMA = 5.67e-8
T_IN_K = 609.58
T_OUT_K = 360.10
T_MEAN_K = 0.8 * T_IN_K + 0.2 * T_OUT_K
MASS_UPPER_KG = 4650.0


@dataclass(frozen=True)
class StaticRow:
    row_id: str
    branch_id: str
    kappa_kg_m2: float
    technology_maturity: str
    flow_case: str
    m_dot_NaK_kg_s: float
    epsilon_case: str
    epsilon: float
    sink_case: str
    T_sink_K: float
    h_case: str
    h_W_m2K: float
    Q_NaK_W: float
    Twall_K: float
    A_exchange_m2: float
    A_rad_m2: float
    UA_W_K: float
    M_rad_kg: float
    mass_margin_kg: float
    exchange_residual_W: float
    radiation_residual_W: float
    condition_status: str
    evidence_status_per_input: str
    rejection_reasons: tuple[str, ...]


def _enthalpy_rise_J_kg() -> float:
    return (
        radiator_candidate_math.nak_enthalpy_J_kg(T_IN_K)
        - radiator_candidate_math.nak_enthalpy_J_kg(T_OUT_K)
    )


def _wall_root(epsilon: float, sink_K: float, h_W_m2K: float) -> float:
    def balance(twall_K: float) -> float:
        return h_W_m2K * (T_MEAN_K - twall_K) - epsilon * SIGMA * (
            twall_K**4 - sink_K**4
        )

    low_K = math.nextafter(sink_K, T_MEAN_K)
    high_K = math.nextafter(T_MEAN_K, sink_K)
    low_balance = balance(low_K)
    high_balance = balance(high_K)
    if not (low_balance > 0.0 and high_balance < 0.0):
        raise ValueError("no_physical_wall_root")

    for _ in range(100):
        midpoint_K = (low_K + high_K) / 2.0
        if balance(midpoint_K) > 0.0:
            low_K = midpoint_K
        else:
            high_K = midpoint_K
    return (low_K + high_K) / 2.0


def solve_static_case(
    *,
    branch_id: str,
    kappa_kg_m2: float,
    flow_case: str,
    m_dot_kg_s: float,
    epsilon_case: str,
    epsilon: float,
    sink_case: str,
    sink_K: float,
    h_case: str,
    h_W_m2K: float,
    evidence_status_per_input: str,
    technology_maturity: str = "test",
) -> StaticRow:
    row_id = "__".join(
        (branch_id, flow_case, epsilon_case, sink_case, h_case)
    )
    rejection_reasons = []
    if not (0.0 < epsilon <= 1.0):
        rejection_reasons.append("epsilon_out_of_range")
    if any(
        not math.isfinite(value) or value <= 0.0
        for value in (kappa_kg_m2, m_dot_kg_s, h_W_m2K, sink_K)
    ):
        rejection_reasons.append("nonpositive_or_nonfinite_input")
    if sink_K >= T_OUT_K:
        rejection_reasons.append("sink_not_below_cold_endpoint")

    nan = math.nan
    if rejection_reasons:
        return StaticRow(
            row_id,
            branch_id,
            kappa_kg_m2,
            technology_maturity,
            flow_case,
            m_dot_kg_s,
            epsilon_case,
            epsilon,
            sink_case,
            sink_K,
            h_case,
            h_W_m2K,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            "rejected",
            evidence_status_per_input,
            tuple(rejection_reasons),
        )

    power_W = m_dot_kg_s * _enthalpy_rise_J_kg()
    try:
        wall_K = _wall_root(epsilon, sink_K, h_W_m2K)
    except ValueError as exc:
        if str(exc) != "no_physical_wall_root":
            raise
        return StaticRow(
            row_id,
            branch_id,
            kappa_kg_m2,
            technology_maturity,
            flow_case,
            m_dot_kg_s,
            epsilon_case,
            epsilon,
            sink_case,
            sink_K,
            h_case,
            h_W_m2K,
            power_W,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            nan,
            "rejected",
            evidence_status_per_input,
            ("no_physical_wall_root",),
        )

    area_m2 = power_W / (h_W_m2K * (T_MEAN_K - wall_K))
    ua_W_K = h_W_m2K * area_m2
    mass_kg = kappa_kg_m2 * area_m2
    mass_margin_kg = MASS_UPPER_KG - mass_kg
    exchange_W = h_W_m2K * area_m2 * (T_MEAN_K - wall_K)
    radiation_W = epsilon * SIGMA * area_m2 * (
        wall_K**4 - sink_K**4
    )
    exchange_residual_W = exchange_W - power_W
    radiation_residual_W = radiation_W - power_W

    derived_values = (area_m2, ua_W_K, mass_kg)
    rejection_reasons = []
    if any(
        not math.isfinite(value) or value <= 0.0
        for value in derived_values
    ):
        rejection_reasons.append("nonpositive_or_nonfinite_derived_quantity")
    if mass_kg > MASS_UPPER_KG:
        rejection_reasons.append("mass_above_4650_kg")
    if radiation_W + 1e-6 < power_W:
        rejection_reasons.append("insufficient_radiation_capacity")

    condition_status = (
        "rejected"
        if rejection_reasons
        else "not_rejected_under_necessary_conditions"
    )
    return StaticRow(
        row_id,
        branch_id,
        kappa_kg_m2,
        technology_maturity,
        flow_case,
        m_dot_kg_s,
        epsilon_case,
        epsilon,
        sink_case,
        sink_K,
        h_case,
        h_W_m2K,
        power_W,
        wall_K,
        area_m2,
        area_m2,
        ua_W_K,
        mass_kg,
        mass_margin_kg,
        exchange_residual_W,
        radiation_residual_W,
        condition_status,
        evidence_status_per_input,
        tuple(rejection_reasons),
    )


def generate_static_rows() -> list[StaticRow]:
    rows = []
    for branch, flow, emissivity, sink, h_anchor in itertools.product(
        contract.BRANCHES,
        contract.FLOWS,
        contract.EMISSIVITIES,
        contract.SINKS,
        contract.H_ANCHORS,
    ):
        evidence = "|".join(
            (
                branch.maturity,
                flow.evidence,
                emissivity.evidence,
                sink.evidence,
                h_anchor.evidence,
            )
        )
        rows.append(
            solve_static_case(
                branch_id=branch.branch_id,
                kappa_kg_m2=branch.kappa_kg_m2,
                technology_maturity=branch.maturity,
                flow_case=flow.case_id,
                m_dot_kg_s=flow.value,
                epsilon_case=emissivity.case_id,
                epsilon=emissivity.value,
                sink_case=sink.case_id,
                sink_K=sink.value,
                h_case=h_anchor.case_id,
                h_W_m2K=h_anchor.value,
                evidence_status_per_input=evidence,
            )
        )
    return rows
