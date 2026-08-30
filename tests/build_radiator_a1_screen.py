"""Write a deterministic offline-only radiator A1 screening package."""
from __future__ import annotations

from dataclasses import asdict
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import sys
from typing import Any, Iterable

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests import radiator_a1_contract as contract
from tests import radiator_a1_math as a1math


ROOT = Path(__file__).resolve().parents[1]


def _same(left: float, right: float) -> bool:
    """Compare contract numbers with a fixed absolute-only tolerance."""
    return math.isclose(left, right, rel_tol=0.0, abs_tol=1e-9)


def _static_for_role(rows: Iterable, branch_id: str, role):
    """Return the unique static row for one fixed branch/role pairing."""
    branches = [
        branch for branch in contract.BRANCHES if branch.branch_id == branch_id
    ]
    if len(branches) != 1:
        raise ValueError(
            "branch id must identify exactly one contract branch: "
            f"branch_id={branch_id}; matches={len(branches)}"
        )
    branch = branches[0]
    matches = [
        row
        for row in rows
        if row.branch_id == branch_id
        and _same(row.kappa_kg_m2, branch.kappa_kg_m2)
        and _same(row.m_dot_NaK_kg_s, role.flow_kg_s)
        and _same(row.epsilon, role.epsilon)
        and _same(row.T_sink_K, role.sink_K)
        and _same(row.h_W_m2K, role.h_W_m2K)
    ]
    if len(matches) != 1:
        raise ValueError(
            "fixed role must identify exactly one static row: "
            f"branch_id={branch_id}; role_id={role.role_id}; "
            f"matches={len(matches)}"
        )
    return matches[0]


def _finite_positive(value: float) -> bool:
    return math.isfinite(value) and value > 0.0


def _timescale_relation(tau_s: float) -> str:
    if not _finite_positive(tau_s):
        return "not_available"
    if 120.0 <= tau_s <= 150.0:
        return "within_120_150_s"
    if tau_s < 120.0:
        return "below_120_s"
    return "above_150_s"


def build_screen(force_reject_candidate: str | None = None) -> dict:
    """Build the fixed 96-row screen and 12-role representative matrix."""
    source_contract = contract.verify_source_contract()
    rows = a1math.generate_static_rows()
    representatives = []

    for branch in contract.BRANCHES:
        for role in contract.ROLES:
            row = _static_for_role(rows, branch.branch_id, role)
            candidate_id = f"{branch.branch_id}__{role.role_id}"
            rejection_reasons = list(row.rejection_reasons)
            if candidate_id == force_reject_candidate:
                rejection_reasons.append("test_forced_rejection")

            capacity_J_K = row.M_rad_kg * role.cp_proxy_J_kgK
            radiation_conductance_W_K = (
                4.0
                * a1math.SIGMA
                * row.epsilon
                * row.A_rad_m2
                * row.Twall_K**3
            )
            effective_conductance_W_K = (
                row.UA_W_K + radiation_conductance_W_K
            )
            if _finite_positive(capacity_J_K) and _finite_positive(
                effective_conductance_W_K
            ):
                tau_s = capacity_J_K / effective_conductance_W_K
            else:
                tau_s = math.nan

            positive_derived_values = all(
                _finite_positive(value)
                for value in (
                    capacity_J_K,
                    effective_conductance_W_K,
                    tau_s,
                )
            )
            eligible = (
                row.condition_status != "rejected"
                and not rejection_reasons
                and positive_derived_values
            )
            representatives.append(
                {
                    "candidate_id": candidate_id,
                    "source_row_id": row.row_id,
                    "branch_id": branch.branch_id,
                    "technology_maturity": branch.maturity,
                    "role_id": role.role_id,
                    "m_dot_NaK_kg_s": role.flow_kg_s,
                    "epsilon": role.epsilon,
                    "T_sink_K": role.sink_K,
                    "h_W_m2K": role.h_W_m2K,
                    "cp_proxy_J_kgK": role.cp_proxy_J_kgK,
                    "cp_identity": "sensitivity_proxy",
                    "Q_NaK_W": row.Q_NaK_W,
                    "Twall_condition_K": row.Twall_K,
                    "A_exchange_m2": row.A_exchange_m2,
                    "A_rad_m2": row.A_rad_m2,
                    "UA_W_K": row.UA_W_K,
                    "M_rad_kg": row.M_rad_kg,
                    "mass_margin_kg": row.mass_margin_kg,
                    "C_eff_proxy_J_K": capacity_J_K,
                    "G_effective_W_K": effective_conductance_W_K,
                    "tau_predicted_s": tau_s,
                    "timescale_relation": _timescale_relation(tau_s),
                    "eligible_for_slx": eligible,
                    "rejection_reasons": rejection_reasons,
                    "paper_reproduced": False,
                    "formal_promotion": False,
                }
            )

    return {
        "source_contract": source_contract,
        "unit_contract": {
            "m_dot_NaK_kg_s": "kg/s",
            "epsilon": "1",
            "T_sink_K": "K",
            "h_W_m2K": "W/(m^2*K)",
            "Q_NaK_W": "W",
            "Twall_K": "K",
            "A_exchange_m2": "m^2",
            "A_rad_m2": "m^2",
            "UA_W_K": "W/K",
            "M_rad_kg": "kg",
            "C_eff_proxy_J_K": "J/K",
            "tau_predicted_s": "s",
        },
        "offline_rows": [asdict(row) for row in rows],
        "representatives": representatives,
        "paper_reproduced": False,
        "formal_promotion": False,
    }


def _normalize_csv_value(value: Any) -> Any:
    if isinstance(value, (list, tuple, dict, bool)):
        return json.dumps(value, ensure_ascii=False)
    return value


def _write_csv(path: Path, rows: list[dict]) -> None:
    """Create a nonempty UTF-8 CSV without replacing an existing file."""
    if not rows:
        raise ValueError(f"refuse empty CSV: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized_rows = [
        {key: _normalize_csv_value(value) for key, value in row.items()}
        for row in rows
    ]
    fieldnames = list(normalized_rows[0])
    with path.open("x", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(normalized_rows)


def _write_json(path: Path, value: Any) -> None:
    """Create deterministic strict JSON without replacing existing data."""
    serialized = json.dumps(
        value,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
        allow_nan=False,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        handle.write(serialized)
        handle.write("\n")


def write_screen(output: Path) -> None:
    """Write the deterministic A1 package strictly beneath ``ROOT/tmp``."""
    output = output.resolve()
    tmp_root = (ROOT / "tmp").resolve()
    if output == tmp_root or not output.is_relative_to(tmp_root):
        raise ValueError("output must be a strict descendant of ROOT/tmp")

    package = build_screen()
    offline_directory = output / "offline_screen"
    representatives_directory = output / "representatives"

    _write_json(
        output / "source_contract/source_contract.json",
        package["source_contract"],
    )
    _write_json(
        output / "source_contract/unit_contract.json",
        package["unit_contract"],
    )
    _write_csv(
        offline_directory / "offline_96.csv", package["offline_rows"]
    )
    rejected_rows = [
        row
        for row in package["offline_rows"]
        if row["condition_status"] == "rejected"
    ]
    _write_csv(
        offline_directory / "offline_rejection_log.csv",
        rejected_rows or [{"status": "none_rejected"}],
    )
    _write_csv(
        representatives_directory / "representative_matrix.csv",
        package["representatives"],
    )

    eligible_representatives = [
        row
        for row in package["representatives"]
        if row["eligible_for_slx"]
    ]
    _write_json(
        representatives_directory / "selection.json",
        {
            "eligible_candidate_ids": [
                row["candidate_id"] for row in eligible_representatives
            ],
            "eligible_count": len(eligible_representatives),
            "fixed_role_count": len(package["representatives"]),
            "replacement_allowed": False,
            "paper_reproduced": False,
        },
    )
    for representative in eligible_representatives:
        _write_json(
            representatives_directory
            / representative["candidate_id"]
            / "parameter_manifest.json",
            representative,
        )

    output_hashes = {
        str(path.relative_to(output)): hashlib.sha256(
            path.read_bytes()
        ).hexdigest()
        for path in sorted(output.rglob("*"))
        if path.is_file()
    }
    _write_json(
        output / "source_contract/output_hashes.json", output_hashes
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    write_screen(arguments.output)
    print("RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD")


if __name__ == "__main__":
    main()
