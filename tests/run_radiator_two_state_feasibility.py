#!/usr/bin/env python3
"""Write a one-shot, read-only evidence bundle for the radiator two-state gate."""
from __future__ import annotations

import argparse
import csv
import ctypes
import errno
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any, Mapping

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests import radiator_two_state_contract as contract
from tests import radiator_two_state_math as model


ROOT = Path(__file__).resolve().parents[1]
SCIENTIFIC_ENUMS = frozenset({
    "constant_positive_two_state_robustly_infeasible",
    "constant_positive_two_state_nominally_infeasible_but_reading_sensitive",
    "constant_positive_two_state_conditionally_feasible",
    "constant_positive_two_state_full_interval_inconsistent",
})
_INTERVAL_HEADERS = (
    "case_id", "interval_index", "start_s", "end_s", "A_K", "B_K_s", "D_J",
    "residual_J", "relative_residual", "conditional_C_fluid_J_K",
)
_CORNER_HEADERS = (
    "case_id", "interval_index", "minimum_J", "maximum_J", "contains_zero",
    "admissible_corner_count",
)


def _atomic_text(path: Path, content: str) -> None:
    """Atomically replace one private-staging output after durable UTF-8 staging."""
    path = Path(path)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            delete=False,
            dir=str(path.parent),
            prefix=f".{path.name}.",
            suffix=".tmp",
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    except BaseException:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass
        raise


def _remove_staging_directory(staging_directory: Path | None) -> None:
    if staging_directory is None:
        return
    try:
        shutil.rmtree(staging_directory)
    except FileNotFoundError:
        pass


def _publish_directory_exclusive(staging_directory: Path, run_directory: Path) -> None:
    if sys.platform != "darwin":
        raise RuntimeError("exclusive directory publication is unsupported on this platform")
    libc = ctypes.CDLL(None, use_errno=True)
    renamex = libc.renamex_np
    renamex.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    renamex.restype = ctypes.c_int
    if run_directory.exists():
        raise FileExistsError(run_directory)
    result = renamex(
        os.fsencode(staging_directory), os.fsencode(run_directory), 0x00000004
    )
    if result == 0:
        return
    error_number = ctypes.get_errno()
    if error_number in {errno.EEXIST, errno.ENOTEMPTY}:
        raise FileExistsError(run_directory)
    raise OSError(error_number, "exclusive directory publication failed", run_directory)


def _verify_output_hashes(
    staging_directory: Path, output_hashes: Mapping[str, str]
) -> None:
    for name, expected in output_hashes.items():
        actual = _sha256(staging_directory / name)
        if actual != expected:
            raise RuntimeError(f"output hash mismatch: {name}")


def _atomic_json(path: Path, payload: Mapping[str, Any]) -> None:
    _atomic_text(
        path,
        json.dumps(
            payload, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False
        )
        + "\n",
    )


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _solution_payload(solution: model.Solution) -> dict[str, float]:
    return {
        "C_fluid_J_K": solution.C_fluid_J_K,
        "UA_W_K": solution.UA_W_K,
        "sse_J2": solution.sse_J2,
    }


def _case_payload(analysis: model.CaseAnalysis) -> dict[str, Any]:
    case = analysis.case
    return {
        "case_id": case.case_id,
        "flow_id": case.flow_id,
        "m_dot_kg_s": case.m_dot_kg_s,
        "energy_path": case.energy_path,
        "case_enum": analysis.case_enum,
        "nominal_sign_gate": dict(analysis.nominal_sign_gate),
        "favorable_sign_gate": dict(analysis.favorable_sign_gate),
        "unrestricted_solution": _solution_payload(analysis.unrestricted_solution),
        "nnls_solution": _solution_payload(analysis.nnls_solution),
        "equivalent_mass_kg": analysis.equivalent_mass_kg,
        "all_intervals_locally_compatible": analysis.all_intervals_locally_compatible,
    }


def _csv_text(headers: tuple[str, ...], rows: list[dict[str, Any]]) -> str:
    content = io.StringIO(newline="")
    writer = csv.DictWriter(content, fieldnames=headers, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return content.getvalue()


def _interval_rows(analyses: tuple[model.CaseAnalysis, ...]) -> list[dict[str, Any]]:
    rows = []
    for analysis in analyses:
        for item in analysis.intervals:
            coefficient = item.coefficient
            rows.append({
                "case_id": analysis.case.case_id,
                "interval_index": coefficient.interval_index,
                "start_s": coefficient.start_s,
                "end_s": coefficient.end_s,
                "A_K": coefficient.A_K,
                "B_K_s": coefficient.B_K_s,
                "D_J": coefficient.D_J,
                "residual_J": item.residual_J,
                "relative_residual": item.relative_residual,
                "conditional_C_fluid_J_K": item.conditional_C_fluid_J_K,
            })
    return rows


def _corner_rows(analyses: tuple[model.CaseAnalysis, ...]) -> list[dict[str, Any]]:
    rows = []
    for analysis in analyses:
        for item in analysis.intervals:
            corner = item.corner_range
            rows.append({
                "case_id": analysis.case.case_id,
                "interval_index": item.coefficient.interval_index,
                "minimum_J": "" if corner is None else corner.minimum_J,
                "maximum_J": "" if corner is None else corner.maximum_J,
                "contains_zero": "false" if corner is None else str(corner.contains_zero).lower(),
                "admissible_corner_count": 0 if corner is None else corner.admissible_corner_count,
            })
    return rows


def _source_hashes() -> dict[str, str]:
    paths = (
        contract.SPEC,
        contract.PAPER,
        contract.POINTS_CSV,
        contract.POINTS_PROVENANCE,
        ROOT / "tests/radiator_two_state_contract.py",
        ROOT / "tests/radiator_two_state_math.py",
        ROOT / "tests/run_radiator_two_state_feasibility.py",
    )
    return {
        path.relative_to(ROOT).as_posix(): _sha256(path)
        for path in paths
    }


def _frozen_source_path(key: str) -> Path:
    paths = {
        "spec": contract.SPEC,
        "paper": contract.PAPER,
        "points_csv": contract.POINTS_CSV,
        "points_provenance": contract.POINTS_PROVENANCE,
    }
    return paths[key]


def _validate_source_pre(source_pre: Mapping[str, str]) -> None:
    for key, expected in contract.INPUT_HASHES.items():
        relative = _frozen_source_path(key).relative_to(ROOT).as_posix()
        if source_pre.get(relative) != expected:
            raise RuntimeError(f"frozen source digest mismatch: {key}")


def _validate_contract_evidence(
    evidence: contract.Evidence, source_pre: Mapping[str, str]
) -> None:
    for key, expected in contract.INPUT_HASHES.items():
        relative = _frozen_source_path(key).relative_to(ROOT).as_posix()
        observed = evidence.source_hashes.get(key)
        if observed != expected or observed != source_pre.get(relative):
            raise RuntimeError(f"contract evidence source digest mismatch: {key}")


def _report(
    result_enum: str,
    analyses: tuple[model.CaseAnalysis, ...],
    source_hashes: Mapping[str, str],
    protected_hashes: Mapping[str, str],
    protected_snapshot_status: str,
) -> str:
    case_lines = "\n".join(
        f"- `{analysis.case.case_id}`: `{analysis.case_enum}`"
        for analysis in analyses
    )
    source_rows = []
    for category, path in (
        ("approved spec", contract.SPEC),
        ("thesis PDF", contract.PAPER),
        ("digitized CSV", contract.POINTS_CSV),
        ("provenance JSON", contract.POINTS_PROVENANCE),
        ("contract script", ROOT / "tests/radiator_two_state_contract.py"),
        ("math script", ROOT / "tests/radiator_two_state_math.py"),
        ("runner script", ROOT / "tests/run_radiator_two_state_feasibility.py"),
    ):
        relative = path.relative_to(ROOT).as_posix()
        source_rows.append(f"| {category} | `{relative}` | `{source_hashes[relative]}` |")
    protected_rows = [
        "| protected snapshot | "
        f"`{protected_snapshot_status}` | `seven protected identities` |"
    ]
    protected_rows.extend(
        f"| protected file | `{relative}` | `{digest}` |"
        for relative, digest in protected_hashes.items()
    )
    identity_rows = "\n".join(source_rows + protected_rows)
    return f"""# 散热器两状态离线可行性证据

## 范围与证据身份

本运行只读取已冻结的论文、规格、图 5.18(d) 数字化点及其出处；不加载、仿真或修改 SLX。
✅ 受保护文件在本次运行前后字节完全一致；这不构成获批基线身份认定。
⚠️ 结果只针对固定入口、常正 `C_fluid` 与常正 `UA` 的两状态方程族。
❓ 该离线条件检查不能识别作者参数，也不能建立唯一的全局曲线。

| Category | Path/Identity | SHA-256/Status |
| --- | --- | --- |
{identity_rows}

## 四个预注册案例

{case_lines}

## 总分类

`{result_enum}`

## 边界声明

- `paper_reproduced=false`
- `author_parameter_identified=false`
- `formal_promotion=false`
- This is not paper reproduction, not author parameter identification, and not formal promotion.
"""


def _sanitized_exception(exception: contract.EvidenceContractError) -> dict[str, str]:
    message = " ".join(str(exception).split())
    return {
        "exception_type": type(exception).__name__,
        "exception_message": message[:1000],
    }


def _contract_failure(
    run_dir: Path,
    protected_before: dict[str, str] | None,
    exception: contract.EvidenceContractError,
) -> dict[str, Any]:
    if protected_before is None:
        protected_after = None
        protected_snapshot_status = "initial_unavailable"
    else:
        try:
            protected_after = contract.snapshot_protected_files()
        except contract.EvidenceContractError:
            protected_after = None
            protected_snapshot_status = "final_unavailable"
        else:
            if protected_before != protected_after:
                raise RuntimeError("protected files changed during evidence-contract failure")
            protected_snapshot_status = "verified_unchanged"
    payload = {
        "schema": "radiator_two_state_contract_failure_v1",
        "result_enum": "evidence_contract_failure",
        **_sanitized_exception(exception),
        "protected_before": protected_before,
        "protected_after": protected_after,
        "protected_snapshot_status": protected_snapshot_status,
        **dict(contract.FALSE_FLAGS),
    }
    _atomic_json(run_dir / "contract_failure.json", payload)
    return payload


def run(
    run_dir: Path | str, points_path: Path | str = contract.POINTS_CSV
) -> dict[str, Any]:
    """Publish one complete, self-hashed read-only evidence bundle or nothing."""
    normalized_run_dir = Path(run_dir).expanduser().resolve()
    normalized_points_path = Path(points_path).expanduser().resolve()
    if normalized_run_dir.exists():
        raise FileExistsError(normalized_run_dir)
    normalized_run_dir.parent.mkdir(parents=True, exist_ok=True)
    staging_directory: Path | None = Path(tempfile.mkdtemp(
        prefix=f".{normalized_run_dir.name}.staging.",
        dir=str(normalized_run_dir.parent),
    ))
    try:
        source_pre = _source_hashes()
        _validate_source_pre(source_pre)
        protected_before: dict[str, str] | None = None
        try:
            protected_before = contract.snapshot_protected_files()
            evidence = contract.verify_input_contract(normalized_points_path)
        except contract.EvidenceContractError as exception:
            failure = _contract_failure(
                staging_directory, protected_before, exception
            )
            _publish_directory_exclusive(staging_directory, normalized_run_dir)
            staging_directory = None
            return failure

        _validate_contract_evidence(evidence, source_pre)
        source_post_verify = _source_hashes()
        if source_post_verify != source_pre:
            raise RuntimeError("source files changed after verify")
        analyses = tuple(
            model.analyze_case(case, evidence.samples) for case in contract.CASES
        )
        result_enum = model.aggregate_case_enums(
            analysis.case_enum for analysis in analyses
        )
        protected_after = contract.snapshot_protected_files()
        if protected_before != protected_after:
            raise RuntimeError("protected files changed during scientific evidence run")

        summary = {
            "schema": "radiator_two_state_feasibility_v1",
            "result_enum": result_enum,
            "case_count": 4,
            "interval_count_per_case": 11,
            "Tin_K": contract.TIN_K,
            "temperature_allowance_K": contract.TEMPERATURE_ALLOWANCE_K,
            "time_allowance_s": contract.TIME_ALLOWANCE_S,
            "cases": [_case_payload(analysis) for analysis in analyses],
            **dict(contract.FALSE_FLAGS),
        }
        _atomic_json(staging_directory / "summary.json", summary)
        _atomic_text(
            staging_directory / "intervals.csv",
            _csv_text(_INTERVAL_HEADERS, _interval_rows(analyses)),
        )
        _atomic_text(
            staging_directory / "corner_ranges.csv",
            _csv_text(_CORNER_HEADERS, _corner_rows(analyses)),
        )
        _atomic_json(staging_directory / "source_hashes.json", source_pre)
        _atomic_json(staging_directory / "protected_before.json", protected_before)
        _atomic_json(staging_directory / "protected_after.json", protected_after)
        _atomic_text(
            staging_directory / "report.md",
            _report(
                result_enum,
                analyses,
                source_pre,
                protected_after,
                "verified_unchanged",
            ),
        )
        output_hashes = {
            name: _sha256(staging_directory / name)
            for name in (
                "summary.json", "intervals.csv", "corner_ranges.csv", "source_hashes.json",
                "protected_before.json", "protected_after.json", "report.md",
            )
        }
        _atomic_json(staging_directory / "output_hashes.json", output_hashes)
        _verify_output_hashes(staging_directory, output_hashes)
        source_final = _source_hashes()
        if source_final != source_pre:
            raise RuntimeError("source files changed during final publication check")
        protected_final = contract.snapshot_protected_files()
        if protected_final != protected_before:
            raise RuntimeError("protected files changed during final publication check")
        _publish_directory_exclusive(staging_directory, normalized_run_dir)
        staging_directory = None
        return summary
    except BaseException:
        _remove_staging_directory(staging_directory)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path)
    arguments = parser.parse_args(argv)
    normalized_run_dir = arguments.run_dir.expanduser().resolve()
    result = run(normalized_run_dir)
    status = {
        "run_dir": str(normalized_run_dir),
        "result_enum": result["result_enum"],
        **dict(contract.FALSE_FLAGS),
    }
    print(json.dumps(status, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False))
    return 2 if result["result_enum"] == "evidence_contract_failure" else 0


if __name__ == "__main__":
    raise SystemExit(main())
