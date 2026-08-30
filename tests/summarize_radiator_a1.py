#!/usr/bin/env python3
"""Summarize A1 gates without fitting, replacement, or formal promotion."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import sys

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests import analyze_radiator_a1_run as analyze


ROOT = Path(__file__).resolve().parents[1]
MATURITY_RANK = {
    "tested": 0,
    "built_not_tested": 1,
    "projected": 2,
    "sensitivity_only": 3,
}


def _metric(value) -> float:
    return float("inf") if value is None else abs(float(value))


def summarize_records(records: list[dict], stage: int) -> dict:
    passed = [row for row in records if row.get("simulation_gate_pass")]
    ranked = sorted(
        passed,
        key=lambda row: (
            MATURITY_RANK.get(row.get("technology_maturity"), 99),
            _metric(row.get("energy_residual")),
            _metric(row.get("paper_error")),
            row["candidate_id"],
        ),
    )
    return {
        "stage_s": stage,
        "record_count": len(records),
        "passed_count": len(passed),
        "advance_candidate_ids": (
            [row["candidate_id"] for row in passed]
            if stage == 500
            else []
        ),
        "ranked_candidate_ids": [row["candidate_id"] for row in ranked],
        "selected_best_candidate": None,
        "identifiability": (
            "no_feasible_candidate_in_approved_envelope"
            if not passed
            else "one_conditionally_feasible_package"
            if len(passed) == 1
            else "multiple_conditionally_feasible_packages"
        ),
        "expand_envelope": False,
        "paper_reproduced": False,
        "formal_promotion": False,
    }


def _records(run_root: Path, stage: int) -> list[dict]:
    matrix = run_root / "representatives/representative_matrix.csv"
    with matrix.open() as handle:
        representatives = {
            row["candidate_id"]: row for row in csv.DictReader(handle)
        }
    selection = json.loads(
        (run_root / "representatives/selection.json").read_text()
    )
    ids = (
        selection["eligible_candidate_ids"]
        if stage == 500
        else json.loads(
            (run_root / "comparisons/advance_14000.json").read_text()
        )["candidate_ids"]
    )
    folder = "candidates_500s" if stage == 500 else "candidates_14000s"
    rows = []
    for candidate_id in ids:
        gate_path = run_root / folder / candidate_id / "run/gate.json"
        if gate_path.is_file():
            gate = json.loads(gate_path.read_text())
        else:
            try:
                gate = analyze.write_analysis(run_root, candidate_id, stage)
            except Exception as exception:
                gate = {
                    "candidate_id": candidate_id,
                    "simulation_gate_pass": False,
                    "rejection_reasons": [
                        "analysis_failed: "
                        + type(exception).__name__
                        + ": "
                        + str(exception)
                    ],
                }
        rep = representatives[candidate_id]
        errors = [
            abs(value["relative_error"])
            for value in gate.get("paper_comparison", {}).values()
            if value["independent_validation"]
        ]
        energy = gate.get("energy", {})
        rows.append(
            {
                **gate,
                "technology_maturity": rep["technology_maturity"],
                "paper_error": max(errors) if errors else None,
                "energy_residual": (
                    abs(float(energy["precooler_minus_enthalpy_W"]))
                    if "precooler_minus_enthalpy_W" in energy
                    else None
                ),
            }
        )
    return rows


def render_report(summary: dict, records: list[dict] | None = None) -> str:
    records = records or []
    candidate_lines = []
    for row in records:
        candidate_lines.extend(
            [
                f"### `{row['candidate_id']}`",
                "",
                (
                    "- 数值完整性/推进门："
                    f"`{row.get('simulation_gate_pass', False)}`"
                ),
                (
                    f"- 能量门：`{row.get('energy_gate_pass', False)}`；"
                    f"整环残差 `{row.get('energy_residual')}` W"
                ),
                (
                    "- 论文独立指标最大相对误差："
                    f"`{row.get('paper_error')}`"
                ),
                f"- 来源成熟度：`{row.get('technology_maturity')}`",
                f"- 失败原因：`{row.get('rejection_reasons', [])}`",
                "",
            ]
        )
    candidates = "\n".join(candidate_lines) or "- 无进入本阶段的候选"
    ranking = (
        "\n".join(
            "- `" + value + "`"
            for value in summary["ranked_candidate_ids"]
        )
        or "- 无"
    )
    return f"""# 散热器 A1 分阶段参数包实验结果

## 范围

本报告只记录探索区 A1 候选。正式 SLX、正式 MAT 和物性函数未晋升正式模型。

## 状态

- 阶段：{summary['stage_s']} s
- 记录数：{summary['record_count']}
- 通过数：{summary['passed_count']}
- 可识别性：`{summary['identifiability']}`
- 自动扩大包络：`false`
- 自动选择最佳候选：`false`

## 条件可行候选的来源排序

{ranking}

## 每候选四层结果摘要

{candidates}

## 结论边界

曲线接近不构成作者参数来源证据。本阶段结果不恢复作者实现、不修改正式模型、
不宣称第 5.3.1 节或第 5.4 节已经复现。
"""


def summarize_run(run_root: Path, stage: int) -> dict:
    records = _records(run_root, stage)
    summary = summarize_records(records, stage)
    comparisons = run_root / "comparisons"
    final = run_root / "final_audit"
    comparisons.mkdir(exist_ok=True)
    final.mkdir(exist_ok=True)
    if stage == 500:
        (comparisons / "advance_14000.json").write_text(
            json.dumps(
                {
                    "candidate_ids": summary["advance_candidate_ids"],
                    "source_stage": 500,
                    "replacement_allowed": False,
                    "expand_envelope": False,
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )
    payload = {"summary": summary, "records": records}
    (final / f"summary_{stage}.json").write_text(
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    )
    if stage == 14000:
        (final / "report.md").write_text(render_report(summary, records))
    return summary


def publish_report(run_root: Path, destination: Path) -> None:
    expected = ROOT / "docs/radiator_A1_results_20260830.md"
    if destination.resolve() != expected.resolve() or destination.exists():
        raise ValueError("destination must be the new approved A1 report path")
    payload = json.loads(
        (run_root / "final_audit/summary_14000.json").read_text()
    )
    destination.write_text(
        render_report(payload["summary"], payload["records"])
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("stage", type=int, choices=(500, 14000))
    parser.add_argument("--publish", type=Path)
    args = parser.parse_args()
    run_root = args.run_root.resolve()
    if not run_root.is_relative_to(ROOT / "tmp"):
        raise ValueError("run root must be below tmp/")
    result = summarize_run(run_root, args.stage)
    if args.publish is not None:
        if args.stage != 14000:
            raise ValueError("only the final 14000-s summary may be published")
        publish_report(run_root, args.publish)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
