"""Build source-constrained radiator candidate evidence without SLX execution."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests import audit_radiator_source_chain as source_audit
from tests import radiator_candidate_math as mathlib


ROOT = Path(__file__).resolve().parents[1]
PROVENANCE = ROOT / "data/provenance/radiator_source/juhasz"
PROTECTED = ROOT / "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"
POWER_W = 1_622_000.0
LOW_K = 360.10
HIGH_K = 609.58
SINK_SCENARIOS = (
    ("theoretical_zero_K", 0.0, "mathematical_lower_bound"),
    ("NASA_120_example_200_K", 200.0, "other_system_sensitivity"),
    ("legacy_project_225_K", 225.0, "project_comparison_not_thesis"),
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_protected() -> int:
    with PROTECTED.open() as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 34:
        raise AssertionError(f"expected 34 protected files, got {len(rows)}")
    for row in rows:
        if sha256(Path(row["paths"])) != row["hashes"]:
            raise AssertionError(f"protected file changed: {row['paths']}")
    return len(rows)


def _candidate_rows() -> list[dict]:
    rows = []
    for branch in mathlib.material_branches():
        rows.append({
            "candidate_id": branch.candidate_id,
            "material_branch": branch.material,
            "fin_density_g_cc": branch.fin_density_g_cc,
            "radiation_sides": branch.radiation_sides,
            "kappa_kg_m2": branch.kappa_kg_m2,
            "technology_evidence_grade": branch.maturity,
            "A_rad_upper_if_TAC_zero_m2":
                mathlib.area_upper_bound_m2(branch.kappa_kg_m2),
            "A_rad_status": "bounded_not_identified",
            "epsilon_status": "unknown",
            "UA_status": "unknown_combination",
            "C_wall_status": "unknown_combination",
            "NaK_flow_status": "author_unknown",
            "identifiability_status": "conditionally_feasible_pending_unknowns",
            "source_ids": branch.source_id,
        })
    return rows


def _mass_energy_rows(candidates: list[dict]) -> list[dict]:
    rows = []
    for candidate in candidates:
        for name, sink_K, status in SINK_SCENARIOS:
            epsilon_area = mathlib.ideal_epsilon_area_required_m2(
                POWER_W, LOW_K, HIGH_K, sink_K)
            area_upper = candidate["A_rad_upper_if_TAC_zero_m2"]
            epsilon_min = epsilon_area / area_upper
            rows.append({
                "candidate_id": candidate["candidate_id"],
                "sink_scenario": name,
                "sink_K": sink_K,
                "sink_status": status,
                "ideal_epsilon_A_required_m2": epsilon_area,
                "A_rad_upper_if_TAC_zero_m2": area_upper,
                "epsilon_min_at_loose_mass_bound": epsilon_min,
                "necessary_condition_status":
                    "not_rejected" if epsilon_min <= 1.0 else "rejected",
                "limitation": "Ideal wall=local NaK and TAC=0 bounds; not a design point.",
            })
    return rows


def build_audit() -> dict:
    source_contract = source_audit.build_audit()
    protected_count = verify_protected()
    if source_contract["protected_count"] != protected_count:
        raise AssertionError("source and candidate protected counts disagree")
    candidates = _candidate_rows()
    delta_h = mathlib.nak_enthalpy_J_kg(HIGH_K) - mathlib.nak_enthalpy_J_kg(LOW_K)
    conditional_flow = mathlib.conditional_flow_kg_s(POWER_W, delta_h)
    envelope = _mass_energy_rows(candidates)
    epsilon_area_zero = mathlib.ideal_epsilon_area_required_m2(
        POWER_W, LOW_K, HIGH_K, 0.0)
    timescale = mathlib.radiative_capacity_relation_J_K(
        epsilon_area_zero, 418.0, 120.0, 150.0)
    return {
        "scope": "offline source-constrained necessary conditions only",
        "candidate_family": candidates,
        "mass_energy_envelope": envelope,
        "identifiability": {
            "NaK_mass_flow_author": "unknown",
            "NaK_flow_6p95": "project_boundary",
            "NaK_flow_energy_closure": "conditional",
            "NaK_flow_energy_closure_kg_s": conditional_flow,
            "epsilon": "unknown",
            "A_rad": "bounded_not_identified",
            "UA": "unknown_combination",
            "C_wall": "unknown_combination",
            "radiative_timescale_relation": timescale,
            "author_implementation_status": "not_uniquely_identified",
        },
        "legacy_current": {
            "M_rad_kg": 5744.0,
            "A_rad_m2": 1113.0,
            "h_W_m2_K": 9.755,
            "epsilon": 0.9,
            "Cp_wall_J_kg_K": 900.0,
            "NaK_flow_kg_s": 6.95,
            "mass_constraint_status": "rejected",
            "rejection_reasons": [
                "5744 > 4650",
                "area and h are endpoint inversions rather than independent sources",
                "epsilon and Cp_wall have no verified scheme-B source",
            ],
        },
        "source_hashes": source_contract["source_hashes"],
        "protected_count": protected_count,
        "paper_reproduced": False,
        "no_model_load_or_simulation": True,
        "no_formal_model_change": True,
    }


def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"refuse empty output: {path.name}")
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def write_outputs(output: Path, audit: dict) -> None:
    output.mkdir(parents=True, exist_ok=True)
    _write_csv(output / "candidate_family.csv", audit["candidate_family"])
    _write_csv(output / "mass_energy_envelope.csv",
               audit["mass_energy_envelope"])
    _write_csv(output / "rejection_log.csv", [{
        "candidate_id": "legacy_current",
        "status": audit["legacy_current"]["mass_constraint_status"],
        "reasons": " | ".join(audit["legacy_current"]["rejection_reasons"]),
    }])
    (output / "identifiability.json").write_text(json.dumps({
        **audit["identifiability"],
        "source_hashes": audit["source_hashes"],
        "protected_count": audit["protected_count"],
        "paper_reproduced": audit["paper_reproduced"],
        "no_model_load_or_simulation": audit["no_model_load_or_simulation"],
        "author_implementation_status":
            audit["identifiability"]["author_implementation_status"],
    }, ensure_ascii=False, indent=2) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if not output.is_relative_to(ROOT / "tmp") or output.exists():
        raise ValueError("output must be a new directory below tmp/")
    result = build_audit()
    write_outputs(output, result)
    print(json.dumps({
        "output": str(output),
        "candidate_count": len(result["candidate_family"]),
        "envelope_count": len(result["mass_energy_envelope"]),
        "author_implementation_status":
            result["identifiability"]["author_implementation_status"],
    }, ensure_ascii=False, indent=2))
    print("RADIATOR_CANDIDATE_FAMILY_PASS; NO_MODEL_LOAD; PROTECTED=34")


if __name__ == "__main__":
    main()
