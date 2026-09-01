"""Write a deterministic offline-only radiator A1 screening package."""
from __future__ import annotations

from dataclasses import asdict
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Iterable

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests import radiator_a1_contract as contract
from tests import radiator_a1_math as a1math


ROOT = Path(__file__).resolve().parents[1]
SPEC_RELATIVE = (
    "docs/superpowers/specs/"
    "2026-08-30-radiator-a1-staged-parameter-envelope-design.md"
)
UNIT_CONTRACT = {
    "kappa_kg_m2": "kg/m^2",
    "m_dot_NaK_kg_s": "kg/s",
    "epsilon": "1",
    "T_sink_K": "K",
    "h_W_m2K": "W/(m^2*K)",
    "cp_proxy_J_kgK": "J/(kg*K)",
    "Q_NaK_W": "W",
    "Twall_K": "K",
    "Twall_condition_K": "K",
    "A_exchange_m2": "m^2",
    "A_rad_m2": "m^2",
    "UA_W_K": "W/K",
    "M_rad_kg": "kg",
    "mass_margin_kg": "kg",
    "exchange_residual_W": "W",
    "radiation_residual_W": "W",
    "C_eff_proxy_J_K": "J/K",
    "G_effective_W_K": "W/K",
    "tau_predicted_s": "s",
}


def _contract_axis(values, expected_value: float, expected_unit: str, label: str):
    matches = [value for value in values if value.value == expected_value]
    if len(matches) != 1:
        raise ValueError(
            f"{label} value must identify exactly one contract axis: "
            f"value={expected_value}; matches={len(matches)}"
        )
    selected = matches[0]
    if selected.unit != expected_unit or not selected.evidence:
        raise ValueError(
            f"{label} contract identity is incomplete: "
            f"case_id={selected.case_id}; unit={selected.unit!r}; "
            f"evidence={selected.evidence!r}"
        )
    return selected


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
    if not branch.maturity:
        raise ValueError(f"branch maturity is empty: branch_id={branch_id}")
    flow = _contract_axis(
        contract.FLOWS, role.flow_kg_s, "kg/s", "flow"
    )
    emissivity = _contract_axis(
        contract.EMISSIVITIES, role.epsilon, "1", "emissivity"
    )
    sink = _contract_axis(contract.SINKS, role.sink_K, "K", "sink")
    h_anchor = _contract_axis(
        contract.H_ANCHORS, role.h_W_m2K, "W/(m^2*K)", "h"
    )
    expected_row_id = "__".join(
        (
            branch.branch_id,
            flow.case_id,
            emissivity.case_id,
            sink.case_id,
            h_anchor.case_id,
        )
    )
    expected_evidence = "|".join(
        (
            branch.maturity,
            flow.evidence,
            emissivity.evidence,
            sink.evidence,
            h_anchor.evidence,
        )
    )
    valid_statuses = {
        "not_rejected_under_necessary_conditions",
        "rejected",
        "unidentifiable_due_to_missing_input",
    }
    matches = [
        row
        for row in rows
        if row.row_id == expected_row_id
        and row.branch_id == branch_id
        and row.kappa_kg_m2 == branch.kappa_kg_m2
        and row.technology_maturity == branch.maturity
        and row.flow_case == flow.case_id
        and row.m_dot_NaK_kg_s == flow.value
        and row.epsilon_case == emissivity.case_id
        and row.epsilon == emissivity.value
        and row.sink_case == sink.case_id
        and row.T_sink_K == sink.value
        and row.h_case == h_anchor.case_id
        and row.h_W_m2K == h_anchor.value
        and row.evidence_status_per_input == expected_evidence
        and row.condition_status in valid_statuses
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
    candidate_ids = tuple(
        f"{branch.branch_id}__{role.role_id}"
        for branch in contract.BRANCHES
        for role in contract.ROLES
    )
    if len(set(candidate_ids)) != len(candidate_ids):
        raise RuntimeError("fixed candidate ids must be unique")
    if (
        force_reject_candidate is not None
        and force_reject_candidate not in candidate_ids
    ):
        raise ValueError(
            "unknown force_reject_candidate: "
            f"{force_reject_candidate}"
        )

    source_contract = contract.verify_source_contract()
    rows = a1math.generate_static_rows()
    representatives = []
    identity_hashes = {
        "spec_sha256": contract.sha256(ROOT / SPEC_RELATIVE),
        "generator_sha256": contract.sha256(Path(__file__)),
        "contract_module_sha256": contract.sha256(
            ROOT / "tests/radiator_a1_contract.py"
        ),
        "math_module_sha256": contract.sha256(
            ROOT / "tests/radiator_a1_math.py"
        ),
    }

    candidate_index = 0
    for branch in contract.BRANCHES:
        for role in contract.ROLES:
            row = _static_for_role(rows, branch.branch_id, role)
            candidate_id = candidate_ids[candidate_index]
            candidate_index += 1
            rejection_reasons = list(row.rejection_reasons)
            if (
                row.condition_status
                != "not_rejected_under_necessary_conditions"
            ):
                rejection_reasons.append("source_row_not_eligible")
            if candidate_id == force_reject_candidate:
                rejection_reasons.append("test_forced_rejection")

            try:
                capacity_J_K = row.M_rad_kg * role.cp_proxy_J_kgK
            except (ArithmeticError, ValueError):
                capacity_J_K = math.nan
            proxy_inputs_are_valid = all(
                _finite_positive(value)
                for value in (
                    row.M_rad_kg,
                    role.cp_proxy_J_kgK,
                    row.UA_W_K,
                    row.epsilon,
                    row.A_rad_m2,
                    row.Twall_K,
                )
            )
            if proxy_inputs_are_valid and _finite_positive(capacity_J_K):
                try:
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
                    tau_s = capacity_J_K / effective_conductance_W_K
                except (ArithmeticError, OverflowError, ValueError):
                    effective_conductance_W_K = math.nan
                    tau_s = math.nan
            else:
                effective_conductance_W_K = math.nan
                tau_s = math.nan
            proxy_derived_values_are_valid = all(
                _finite_positive(value)
                for value in (
                    capacity_J_K,
                    effective_conductance_W_K,
                    tau_s,
                )
            )
            if not proxy_derived_values_are_valid:
                rejection_reasons.append(
                    "nonpositive_or_nonfinite_proxy_derived_quantity"
                )
            rejection_reasons = list(dict.fromkeys(rejection_reasons))
            eligible = (
                row.condition_status
                == "not_rejected_under_necessary_conditions"
                and not rejection_reasons
                and proxy_derived_values_are_valid
            )
            input_provenance = {
                "branch": {
                    "branch_id": branch.branch_id,
                    "kappa_kg_m2": branch.kappa_kg_m2,
                    "technology_maturity": branch.maturity,
                },
                "static_inputs": {
                    "flow_case": row.flow_case,
                    "epsilon_case": row.epsilon_case,
                    "sink_case": row.sink_case,
                    "h_case": row.h_case,
                    "evidence_status_per_input": (
                        row.evidence_status_per_input
                    ),
                },
                "cp_proxy": {
                    "value_J_kgK": role.cp_proxy_J_kgK,
                    "identity": "sensitivity_proxy",
                    "evidence": "approved_engineering_sensitivity_axis",
                },
            }
            representatives.append(
                {
                    "candidate_id": candidate_id,
                    "source_row_id": row.row_id,
                    "branch_id": branch.branch_id,
                    "kappa_kg_m2": branch.kappa_kg_m2,
                    "technology_maturity": branch.maturity,
                    "role_id": role.role_id,
                    "flow_case": row.flow_case,
                    "m_dot_NaK_kg_s": role.flow_kg_s,
                    "epsilon_case": row.epsilon_case,
                    "epsilon": role.epsilon,
                    "sink_case": row.sink_case,
                    "T_sink_K": role.sink_K,
                    "h_case": row.h_case,
                    "h_W_m2K": role.h_W_m2K,
                    "evidence_status_per_input": (
                        row.evidence_status_per_input
                    ),
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
                    "input_provenance": input_provenance,
                    "unit_contract_ref": (
                        "source_contract/unit_contract.json"
                    ),
                    "source_contract_ref": (
                        "source_contract/source_contract.json"
                    ),
                    "equation_version": "radiator_a1_static_v1",
                    "spec_path": SPEC_RELATIVE,
                    **identity_hashes,
                    "run_time_record": {
                        "mode": "deferred_to_execution_stage",
                        "wall_clock_utc": None,
                        "reason": "deterministic_offline_core",
                    },
                    "paper_reproduced": False,
                    "formal_promotion": False,
                }
            )

    return {
        "source_contract": source_contract,
        "unit_contract": UNIT_CONTRACT,
        "offline_rows": [asdict(row) for row in rows],
        "representatives": representatives,
        "paper_reproduced": False,
        "formal_promotion": False,
    }


def _normalize_csv_value(value: Any) -> Any:
    if isinstance(value, (list, tuple, dict, bool)):
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            allow_nan=False,
        )
    return value


def _csv_bytes(rows: list[dict]) -> bytes:
    """Render a nonempty, schema-closed deterministic CSV."""
    if not rows:
        raise ValueError("refuse empty CSV")
    fieldnames = list(rows[0])
    if any(list(row) != fieldnames for row in rows):
        raise ValueError("CSV rows must have identical ordered schema")
    normalized_rows = [
        {key: _normalize_csv_value(value) for key, value in row.items()}
        for row in rows
    ]
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(
        buffer, fieldnames=fieldnames, lineterminator="\n"
    )
    writer.writeheader()
    writer.writerows(normalized_rows)
    return buffer.getvalue().encode("utf-8")


def _json_bytes(value: Any) -> bytes:
    """Render strict deterministic JSON and reject NaN/Infinity."""
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _write_bytes_exclusive(path: Path, payload: bytes) -> None:
    """Create one payload without replacing an existing path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as handle:
        handle.write(payload)


def _write_csv(path: Path, rows: list[dict]) -> None:
    """Create a nonempty UTF-8 CSV without replacing an existing file."""
    _write_bytes_exclusive(path, _csv_bytes(rows))


def _write_json(path: Path, value: Any) -> None:
    """Create deterministic strict JSON without replacing existing data."""
    _write_bytes_exclusive(path, _json_bytes(value))


def _preflight_output(output: Path) -> tuple[Path, bool]:
    tmp_root = (ROOT / "tmp").resolve()
    if output.is_symlink():
        raise ValueError(f"symlinked output root is forbidden: {output}")
    resolved = output.resolve(strict=False)
    if resolved == tmp_root or not resolved.is_relative_to(tmp_root):
        raise ValueError("output must be a strict descendant of ROOT/tmp")
    existed = output.exists()
    if existed:
        if not output.is_dir():
            raise FileExistsError(f"output root is not a directory: {output}")
        entries = list(output.iterdir())
        if any(entry.is_symlink() for entry in entries):
            raise ValueError(
                f"symlinked output entry is forbidden: {output}"
            )
        if entries:
            raise FileExistsError(
                f"output directory must be empty: {output}"
            )
    return resolved, existed


def _planned_payloads(package: dict) -> dict[str, bytes]:
    eligible_representatives = [
        row
        for row in package["representatives"]
        if row["eligible_for_slx"]
    ]
    rejected_rows = [
        row
        for row in package["offline_rows"]
        if row["condition_status"]
        != "not_rejected_under_necessary_conditions"
    ]
    planned = {
        "source_contract/source_contract.json": _json_bytes(
            package["source_contract"]
        ),
        "source_contract/unit_contract.json": _json_bytes(
            package["unit_contract"]
        ),
        "offline_screen/offline_96.csv": _csv_bytes(
            package["offline_rows"]
        ),
        "offline_screen/offline_rejection_log.csv": _csv_bytes(
            rejected_rows or [{"status": "none_rejected"}]
        ),
        "representatives/representative_matrix.csv": _csv_bytes(
            package["representatives"]
        ),
        "representatives/selection.json": _json_bytes(
            {
                "eligible_candidate_ids": [
                    row["candidate_id"]
                    for row in eligible_representatives
                ],
                "eligible_count": len(eligible_representatives),
                "fixed_role_count": len(package["representatives"]),
                "replacement_allowed": False,
                "paper_reproduced": False,
                "formal_promotion": False,
            }
        ),
    }
    for representative in eligible_representatives:
        relative = (
            "representatives/"
            f"{representative['candidate_id']}/parameter_manifest.json"
        )
        if relative in planned:
            raise RuntimeError(f"duplicate planned payload: {relative}")
        planned[relative] = _json_bytes(representative)

    output_hashes = {
        relative: hashlib.sha256(payload).hexdigest()
        for relative, payload in sorted(planned.items())
    }
    planned["source_contract/output_hashes.json"] = _json_bytes(
        output_hashes
    )
    return planned


def write_screen(output: Path) -> None:
    """Write the deterministic A1 package strictly beneath ``ROOT/tmp``."""
    output, output_existed = _preflight_output(output)
    package = build_screen()
    planned = _planned_payloads(package)
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(
            prefix=f".{output.name}.screen-", dir=output.parent
        )
    )
    removed_empty_output = False
    try:
        for relative, payload in planned.items():
            relative_path = Path(relative)
            if (
                relative_path.is_absolute()
                or ".." in relative_path.parts
                or not relative_path.parts
            ):
                raise ValueError(f"unsafe planned output path: {relative}")
            _write_bytes_exclusive(staging / relative_path, payload)

        actual_files = {
            str(path.relative_to(staging)): hashlib.sha256(
                path.read_bytes()
            ).hexdigest()
            for path in staging.rglob("*")
            if path.is_file()
        }
        planned_files = {
            relative: hashlib.sha256(payload).hexdigest()
            for relative, payload in planned.items()
        }
        if actual_files != planned_files:
            raise RuntimeError("staged output does not match planned payloads")

        if output_existed:
            output.rmdir()
            removed_empty_output = True
        os.replace(staging, output)
        removed_empty_output = False
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        if removed_empty_output and not output.exists():
            output.mkdir()
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    write_screen(arguments.output)
    print("RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD")


if __name__ == "__main__":
    main()
