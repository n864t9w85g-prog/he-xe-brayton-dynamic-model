"""Pure source-constrained radiator relations; no file or model I/O."""
from __future__ import annotations

from dataclasses import dataclass


SCHEME_B_RADIATOR_TAC_REMAINDER_KG = 4650.0
MATERIAL_ORDER = ("T300", "P95_WG", "K1100", "APG")
TABLE_I = {
    ("one", 1.45): (4.22, 3.14, 2.65, 2.38),
    ("one", 1.00): (3.46, 2.50, 2.07, 1.83),
    ("two", 1.45): (2.11, 1.57, 1.32, 1.19),
    ("two", 1.00): (1.73, 1.25, 1.04, 0.92),
}


@dataclass(frozen=True)
class MaterialBranch:
    candidate_id: str
    material: str
    fin_density_g_cc: float
    radiation_sides: str
    kappa_kg_m2: float
    maturity: str
    source_id: str = "NASA_TM_2008_215420_Table_I"


def _maturity(material: str, density: float) -> str:
    if material == "T300" and density == 1.45:
        return "tested"
    if material == "P95_WG" and density == 1.45:
        return "built_not_tested"
    return "projected"


def material_branches() -> list[MaterialBranch]:
    rows = []
    for (sides, density), values in TABLE_I.items():
        density_id = "1p45" if density == 1.45 else "1p00"
        for material, kappa in zip(MATERIAL_ORDER, values, strict=True):
            rows.append(MaterialBranch(
                candidate_id=f"{material}_fd{density_id}_{sides}",
                material=material,
                fin_density_g_cc=density,
                radiation_sides=sides,
                kappa_kg_m2=kappa,
                maturity=_maturity(material, density),
            ))
    return rows


def area_upper_bound_m2(kappa_kg_m2: float) -> float:
    if kappa_kg_m2 <= 0.0:
        raise ValueError("kappa must be positive")
    return SCHEME_B_RADIATOR_TAC_REMAINDER_KG / kappa_kg_m2


SIGMA_W_M2_K4 = 5.67e-8


def nak_enthalpy_J_kg(temperature_K: float) -> float:
    t = temperature_K
    return 1000.0 * (
        1.061 * t
        - 3.694e-4 * t**2 / 2.0
        + 4.615e-8 * t**3 / 3.0
        + 1.509e-10 * t**4 / 4.0
    )


def conditional_flow_kg_s(power_W: float, delta_h_J_kg: float) -> float:
    if power_W <= 0.0 or delta_h_J_kg <= 0.0:
        raise ValueError("power and enthalpy rise must be positive")
    return power_W / delta_h_J_kg


def linear_temperature_fourth_mean_K4(low_K: float, high_K: float) -> float:
    if low_K <= 0.0 or high_K <= low_K:
        raise ValueError("require 0 < low temperature < high temperature")
    return (high_K**5 - low_K**5) / (5.0 * (high_K - low_K))


def ideal_epsilon_area_required_m2(
        power_W: float, low_K: float, high_K: float, sink_K: float) -> float:
    if power_W <= 0.0:
        raise ValueError("power must be positive")
    if sink_K < 0.0 or sink_K >= low_K:
        raise ValueError("sink must be explicit and below the cold endpoint")
    mean_t4 = linear_temperature_fourth_mean_K4(low_K, high_K)
    return power_W / (SIGMA_W_M2_K4 * (mean_t4 - sink_K**4))


def linearized_radiation_conductance_W_K(
        epsilon_area_m2: float, wall_K: float) -> float:
    if epsilon_area_m2 <= 0.0 or wall_K <= 0.0:
        raise ValueError("epsilon-area and wall temperature must be positive")
    return 4.0 * SIGMA_W_M2_K4 * epsilon_area_m2 * wall_K**3


def radiative_capacity_relation_J_K(
        epsilon_area_m2: float, wall_K: float,
        tau_low_s: float, tau_high_s: float) -> dict[str, float | str]:
    if tau_low_s <= 0.0 or tau_high_s < tau_low_s:
        raise ValueError("invalid time interval")
    conductance = linearized_radiation_conductance_W_K(
        epsilon_area_m2, wall_K)
    return {
        "status": "conditional_combination",
        "G_rad_W_K": conductance,
        "C_rad_120s_J_K": tau_low_s * conductance,
        "C_rad_150s_J_K": tau_high_s * conductance,
        "limitation": "Radiative-only relation; unknown exchange conductance prevents unique wall capacity.",
    }
