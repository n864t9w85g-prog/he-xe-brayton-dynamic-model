# 方案 B 散热器来源约束候选族实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不加载、仿真或修改正式 SLX 的前提下，建立方案 B 散热器/NaK 回路的16个来源分支、质量—能量—辐射—时间尺度约束与机器可读的不可识别性报告。

**Architecture:** 使用一个无文件副作用的纯数学模块表示材料分支和必要条件，一个只读编排器锁定来源哈希并生成CSV/JSON证据，一个只依赖Python标准库的SVG渲染器显示质量—面积可行域。论文直接量、项目边界、条件反推量和作者未知量在数据模型中使用不同状态字段，任何曲线或终点反推都不能被标为独立来源。

**Tech Stack:** Python 3标准库（`dataclasses`、`csv`、`json`、`hashlib`、`unittest`、`pathlib`）、Git、既有PDF/CSV/JSON溯源材料；禁止MATLAB、Simulink、SLX解析与网络依赖。

---

## 文件职责与变更边界

| 文件 | 操作 | 单一职责 |
|---|---|---|
| `sources/NASA-TM-2007-215003-Juhasz-2007.pdf` | 纳入版本控制 | [120]原始来源固定副本 |
| `sources/NASA-TM-2008-215420-Juhasz-2008.pdf` | 纳入版本控制 | [147]原始来源固定副本 |
| `data/provenance/radiator_source/juhasz/source.md` | 纳入版本控制 | 人工可读的来源边界 |
| `data/provenance/radiator_source/juhasz/SHA256SUMS.txt` | 纳入版本控制 | 原始文件哈希合同 |
| `data/provenance/radiator_source/juhasz/published_missing_matrix.csv` | 纳入版本控制 | 论文公开量/作者缺失量机器可读合同 |
| `tests/audit_radiator_source_chain.py` | 纳入版本控制 | 既有来源链只读审计 |
| `tests/test_audit_radiator_source_chain.py` | 纳入版本控制 | 既有来源合同测试 |
| `tests/radiator_candidate_math.py` | 新建 | 纯数学分支、质量、焓、辐射和时间尺度关系 |
| `tests/test_radiator_candidate_math.py` | 新建 | 纯数学单元测试与数值回归 |
| `tests/audit_radiator_candidate_family.py` | 新建 | 哈希守卫、候选编排和CSV/JSON输出 |
| `tests/test_audit_radiator_candidate_family.py` | 新建 | 输出模式、证据分级和禁止路径测试 |
| `tests/render_radiator_candidate_family.py` | 新建 | 从CSV生成无外部依赖SVG |
| `tests/test_render_radiator_candidate_family.py` | 新建 | SVG结构、分支数和标签测试 |
| `docs/steady53_curve_recheck_20260828.md` | 修改 | 追加候选族结果、限制和哈希 |
| `tmp/radiator_candidate_family_<run>/` | 运行时新建 | CSV、JSON、SVG证据；不纳入正式模型依赖 |

不修改`final_steady_24a.slx`、任何`.mat`、`HeXe_property_simulink.m`、NaK正式物性实现或验收阈值。

### Task 1: 固定并提交散热器来源合同

**Files:**
- Add: `sources/NASA-TM-2007-215003-Juhasz-2007.pdf`
- Add: `sources/NASA-TM-2008-215420-Juhasz-2008.pdf`
- Add: `data/provenance/radiator_source/juhasz/source.md`
- Add: `data/provenance/radiator_source/juhasz/SHA256SUMS.txt`
- Add: `data/provenance/radiator_source/juhasz/published_missing_matrix.csv`
- Add: `tests/audit_radiator_source_chain.py`
- Add: `tests/test_audit_radiator_source_chain.py`

- [ ] **Step 1: 运行既有来源合同测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_audit_radiator_source_chain.py
```

Expected: `Ran 2 tests`、`OK`，且没有`ResourceWarning`。

- [ ] **Step 2: 核对三份原始文件哈希**

Run:

```bash
(cd data/provenance/radiator_source/juhasz && shasum -a 256 -c SHA256SUMS.txt)
```

Expected:

```text
../../../../sources/NASA-TM-2007-215003-Juhasz-2007.pdf: OK
../../../../sources/NASA-TM-2008-215420-Juhasz-2008.pdf: OK
../../../../空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf: OK
```

- [ ] **Step 3: 生成一次只读来源审计作为提交前证据**

Run:

```bash
run_dir="$(mktemp -d tmp/radiator_source_chain_plan_XXXXXX)"
rmdir "$run_dir"
python3 tests/audit_radiator_source_chain.py "$run_dir"
```

Expected: 输出包含
`RADIATOR_SOURCE_CHAIN_AUDIT_PASS; NO_MODEL_LOAD; PROTECTED=34`。

- [ ] **Step 4: 确认本任务暂存范围不含其他工作区文件**

Run:

```bash
git add -- \
  sources/NASA-TM-2007-215003-Juhasz-2007.pdf \
  sources/NASA-TM-2008-215420-Juhasz-2008.pdf \
  data/provenance/radiator_source/juhasz \
  tests/audit_radiator_source_chain.py \
  tests/test_audit_radiator_source_chain.py
git diff --cached --check
git diff --cached --name-only
```

Expected: 只列出上述7个来源/审计路径，不列出正式SLX、MAT或其他历史测试。

- [ ] **Step 5: 提交来源合同**

```bash
git commit -m "记录方案B散热器NASA来源链"
```

### Task 2: 用TDD建立纯数学候选引擎

**Files:**
- Create: `tests/radiator_candidate_math.py`
- Create: `tests/test_radiator_candidate_math.py`

- [ ] **Step 1: 写入材料分支和质量边界的失败测试**

Create `tests/test_radiator_candidate_math.py` with:

```python
import math
import unittest

from tests import radiator_candidate_math as mathlib


class CandidateBranchTests(unittest.TestCase):
    def test_all_16_source_branches_have_unique_identity(self):
        rows = mathlib.material_branches()
        self.assertEqual(len(rows), 16)
        self.assertEqual(len({row.candidate_id for row in rows}), 16)
        self.assertEqual({row.material for row in rows},
                         {"T300", "P95_WG", "K1100", "APG"})
        self.assertEqual(min(row.kappa_kg_m2 for row in rows), 0.92)
        self.assertEqual(max(row.kappa_kg_m2 for row in rows), 4.22)

    def test_maturity_does_not_upgrade_projected_branches(self):
        lookup = {row.candidate_id: row for row in mathlib.material_branches()}
        self.assertEqual(lookup["T300_fd1p45_one"].maturity, "tested")
        self.assertEqual(lookup["P95_WG_fd1p45_two"].maturity,
                         "built_not_tested")
        self.assertEqual(lookup["APG_fd1p00_two"].maturity, "projected")

    def test_mass_area_upper_bound_is_relation_not_replacement_area(self):
        t300 = next(row for row in mathlib.material_branches()
                    if row.candidate_id == "T300_fd1p45_one")
        self.assertTrue(math.isclose(
            mathlib.area_upper_bound_m2(t300.kappa_kg_m2),
            4650.0 / 4.22, rel_tol=0.0, abs_tol=1e-12))
        self.assertLess(mathlib.area_upper_bound_m2(t300.kappa_kg_m2), 1113.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认因模块缺失而失败**

Run:

```bash
python3 -m unittest -v tests/test_radiator_candidate_math.py
```

Expected: `ImportError`，指出不能导入`radiator_candidate_math`。

- [ ] **Step 3: 实现16个分支和质量关系的最小代码**

Create `tests/radiator_candidate_math.py` with:

```python
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
```

- [ ] **Step 4: 运行分支测试确认通过**

Run:

```bash
python3 -m unittest -v tests/test_radiator_candidate_math.py
```

Expected: `Ran 3 tests`、`OK`。

- [ ] **Step 5: 增加NaK焓、辐射能力和时间尺度失败测试**

Append to `CandidateBranchTests` before the `if __name__` block:

```python
    def test_nak_triplet_remains_conditional_not_author_input(self):
        delta_h = mathlib.nak_enthalpy_J_kg(609.58) - mathlib.nak_enthalpy_J_kg(360.10)
        self.assertTrue(math.isclose(delta_h, 227357.265107,
                                     rel_tol=0.0, abs_tol=1e-6))
        self.assertTrue(math.isclose(
            mathlib.conditional_flow_kg_s(1_622_000.0, delta_h),
            7.134146337, rel_tol=0.0, abs_tol=1e-9))
        self.assertTrue(math.isclose(6.95 * delta_h / 1000.0,
                                     1580.132992, rel_tol=0.0, abs_tol=1e-6))

    def test_ideal_radiation_relation_uses_explicit_sink(self):
        epsilon_area = mathlib.ideal_epsilon_area_required_m2(
            1_622_000.0, 360.10, 609.58, 0.0)
        self.assertTrue(math.isclose(epsilon_area, 456.8180744750801,
                                     rel_tol=0.0, abs_tol=1e-9))
        self.assertGreater(
            mathlib.ideal_epsilon_area_required_m2(
                1_622_000.0, 360.10, 609.58, 225.0),
            epsilon_area)
        with self.assertRaises(ValueError):
            mathlib.ideal_epsilon_area_required_m2(
                1_622_000.0, 360.10, 609.58, 360.10)

    def test_timescale_output_is_combination_not_material_cp(self):
        epsilon_area = 456.8180744750801
        conductance = mathlib.linearized_radiation_conductance_W_K(
            epsilon_area, 418.0)
        self.assertTrue(math.isclose(conductance, 7566.85086298154,
                                     rel_tol=0.0, abs_tol=1e-9))
        relation = mathlib.radiative_capacity_relation_J_K(
            epsilon_area, 418.0, 120.0, 150.0)
        self.assertEqual(relation["status"], "conditional_combination")
        self.assertTrue(math.isclose(relation["C_rad_120s_J_K"],
                                     908022.1035577848,
                                     rel_tol=0.0, abs_tol=1e-6))
```

- [ ] **Step 6: 运行测试确认新函数缺失**

Run:

```bash
python3 -m unittest -v tests/test_radiator_candidate_math.py
```

Expected: 3个原测试通过，新增测试因`AttributeError`失败。

- [ ] **Step 7: 实现焓、辐射和时间尺度关系**

Append to `tests/radiator_candidate_math.py`:

```python
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
```

- [ ] **Step 8: 运行全部纯数学测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_candidate_math.py
```

Expected: `Ran 6 tests`、`OK`。

- [ ] **Step 9: 提交纯数学引擎**

```bash
git add -- tests/radiator_candidate_math.py tests/test_radiator_candidate_math.py
git diff --cached --check
git commit -m "实现散热器候选族必要条件"
```

### Task 3: 用TDD建立只读候选编排器

**Files:**
- Create: `tests/audit_radiator_candidate_family.py`
- Create: `tests/test_audit_radiator_candidate_family.py`
- Read: `data/provenance/radiator_source/juhasz/published_missing_matrix.csv`
- Read: `tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv`

- [ ] **Step 1: 写入候选输出模式的失败测试**

Create `tests/test_audit_radiator_candidate_family.py` with:

```python
import csv
import json
from pathlib import Path
import tempfile
import unittest

from tests import audit_radiator_candidate_family as audit


ROOT = Path(__file__).resolve().parents[1]


class CandidateFamilyAuditTests(unittest.TestCase):
    def test_build_has_16_branches_and_keeps_statuses_separate(self):
        result = audit.build_audit()
        self.assertEqual(len(result["candidate_family"]), 16)
        self.assertEqual(result["identifiability"]["NaK_mass_flow_author"],
                         "unknown")
        self.assertEqual(result["identifiability"]["NaK_flow_6p95"],
                         "project_boundary")
        self.assertEqual(result["identifiability"]["NaK_flow_energy_closure"],
                         "conditional")
        self.assertFalse(result["paper_reproduced"])
        self.assertTrue(result["no_model_load_or_simulation"])

    def test_legacy_current_is_rejected_by_scheme_b_mass_gate(self):
        result = audit.build_audit()
        legacy = result["legacy_current"]
        self.assertEqual(legacy["M_rad_kg"], 5744.0)
        self.assertEqual(legacy["mass_constraint_status"], "rejected")
        self.assertIn("5744 > 4650", legacy["rejection_reasons"])

    def test_write_outputs_has_stable_schema(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            audit.write_outputs(output, audit.build_audit())
            expected = {
                "candidate_family.csv", "identifiability.json",
                "rejection_log.csv", "mass_energy_envelope.csv",
            }
            self.assertEqual({p.name for p in output.iterdir()}, expected)
            with (output / "candidate_family.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 16)
            ident = json.loads((output / "identifiability.json").read_text())
            self.assertEqual(ident["author_implementation_status"],
                             "not_uniquely_identified")


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认编排器模块缺失**

Run:

```bash
python3 -m unittest -v tests/test_audit_radiator_candidate_family.py
```

Expected: `ImportError`，指出不能导入`audit_radiator_candidate_family`。

- [ ] **Step 3: 实现编排器的来源守卫与数据构建**

Create `tests/audit_radiator_candidate_family.py` with these complete interfaces:

```python
"""Build source-constrained radiator candidate evidence without SLX execution."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

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
```

- [ ] **Step 4: 运行编排器测试确认通过**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_audit_radiator_candidate_family.py
```

Expected: `Ran 3 tests`、`OK`。

- [ ] **Step 5: 增加禁止模型路径的静态测试**

Append to `CandidateFamilyAuditTests`:

```python
    def test_candidate_execution_path_contains_no_model_api(self):
        paths = [
            ROOT / "tests/radiator_candidate_math.py",
            ROOT / "tests/audit_radiator_candidate_family.py",
        ]
        forbidden = ("load_system", "save_system", "sim(", "matlab.engine",
                     "ZipFile", ".slx")
        combined = "\n".join(path.read_text() for path in paths)
        for token in forbidden:
            self.assertNotIn(token, combined)
```

- [ ] **Step 6: 运行测试并执行一次真实输出**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_candidate_math.py \
  tests/test_audit_radiator_candidate_family.py
run_dir="$(mktemp -d tmp/radiator_candidate_family_XXXXXX)"
rmdir "$run_dir"
python3 tests/audit_radiator_candidate_family.py "$run_dir"
find "$run_dir" -maxdepth 1 -type f -print | sort
```

Expected:

- 10项测试全部通过；
- 审计标记`RADIATOR_CANDIDATE_FAMILY_PASS; NO_MODEL_LOAD; PROTECTED=34`；
- `candidate_count=16`；
- `envelope_count=48`；
- 目录恰有4个CSV/JSON文件。

- [ ] **Step 7: 提交只读编排器**

```bash
git add -- \
  tests/audit_radiator_candidate_family.py \
  tests/test_audit_radiator_candidate_family.py
git diff --cached --check
git commit -m "生成散热器候选族可识别性证据"
```

### Task 4: 用TDD建立标准库SVG可行域图

**Files:**
- Create: `tests/render_radiator_candidate_family.py`
- Create: `tests/test_render_radiator_candidate_family.py`
- Read: `tmp/radiator_candidate_family_<run>/candidate_family.csv`
- Read: `tmp/radiator_candidate_family_<run>/mass_energy_envelope.csv`

- [ ] **Step 1: 写SVG失败测试**

Create `tests/test_render_radiator_candidate_family.py` with:

```python
import csv
from pathlib import Path
import tempfile
import unittest

from tests import audit_radiator_candidate_family as audit
from tests import render_radiator_candidate_family as render


ROOT = Path(__file__).resolve().parents[1]


class CandidateFamilyRenderTests(unittest.TestCase):
    def test_svg_contains_16_labeled_source_branches(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            audit.write_outputs(output, audit.build_audit())
            svg = output / "mass_area_envelope.svg"
            render.render(output / "candidate_family.csv", svg)
            text = svg.read_text()
            self.assertTrue(text.startswith("<svg"))
            self.assertEqual(text.count('class="branch"'), 16)
            self.assertIn("T300_fd1p45_one", text)
            self.assertIn("APG_fd1p00_two", text)
            self.assertIn("upper bound, not design area", text)

    def test_renderer_rejects_missing_or_duplicate_branches(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            path = Path(folder) / "bad.csv"
            with path.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=[
                    "candidate_id", "kappa_kg_m2",
                    "A_rad_upper_if_TAC_zero_m2",
                    "technology_evidence_grade",
                ])
                writer.writeheader()
                writer.writerow({
                    "candidate_id": "duplicate", "kappa_kg_m2": 1.0,
                    "A_rad_upper_if_TAC_zero_m2": 4650.0,
                    "technology_evidence_grade": "projected",
                })
            with self.assertRaises(ValueError):
                render.render(path, Path(folder) / "bad.svg")


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认渲染器缺失**

Run:

```bash
python3 -m unittest -v tests/test_render_radiator_candidate_family.py
```

Expected: `ImportError`，指出不能导入`render_radiator_candidate_family`。

- [ ] **Step 3: 实现无外部依赖SVG渲染器**

Create `tests/render_radiator_candidate_family.py` with:

```python
"""Render the 16-branch mass/area envelope as deterministic SVG."""
from __future__ import annotations

import argparse
import csv
from html import escape
from pathlib import Path


def render(candidate_csv: Path, output_svg: Path) -> None:
    with candidate_csv.open() as handle:
        rows = list(csv.DictReader(handle))
    ids = [row["candidate_id"] for row in rows]
    if len(rows) != 16 or len(set(ids)) != 16:
        raise ValueError("renderer requires exactly 16 unique source branches")
    width, height = 1200, 760
    left, top, chart_w, chart_h = 90, 80, 760, 600
    kmax = max(float(row["kappa_kg_m2"]) for row in rows)
    amax = max(float(row["A_rad_upper_if_TAC_zero_m2"]) for row in rows)
    palette = {"tested": "#1b9e77", "built_not_tested": "#d95f02",
               "projected": "#7570b3"}
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<text x="600" y="34" text-anchor="middle" font-size="22">'
        'Scheme-B radiator source branches: mass-derived area upper bound</text>',
        f'<line x1="{left}" y1="{top+chart_h}" x2="{left+chart_w}" '
        f'y2="{top+chart_h}" stroke="black"/>',
        f'<line x1="{left}" y1="{top}" x2="{left}" y2="{top+chart_h}" stroke="black"/>',
        '<text x="470" y="735" text-anchor="middle">kappa (kg/m2)</text>',
        '<text x="22" y="380" transform="rotate(-90 22 380)" '
        'text-anchor="middle">A_rad upper bound if TAC mass=0 (m2)</text>',
        '<text x="900" y="90" font-size="14">upper bound, not design area</text>',
    ]
    for row in rows:
        kappa = float(row["kappa_kg_m2"])
        area = float(row["A_rad_upper_if_TAC_zero_m2"])
        x = left + chart_w * kappa / kmax
        y = top + chart_h * (1.0 - area / amax)
        color = palette[row["technology_evidence_grade"]]
        label = escape(row["candidate_id"])
        parts.append(
            f'<g class="branch"><circle cx="{x:.2f}" cy="{y:.2f}" r="6" '
            f'fill="{color}"/><title>{label}</title></g>')
    for index, (label, color) in enumerate(palette.items()):
        y = 140 + index * 28
        parts.extend([
            f'<circle cx="910" cy="{y}" r="6" fill="{color}"/>',
            f'<text x="925" y="{y+5}" font-size="14">{escape(label)}</text>',
        ])
    parts.append('<g font-size="10" fill="#333">')
    for index, row in enumerate(rows):
        y = 250 + index * 24
        parts.append(f'<text x="880" y="{y}">{escape(row["candidate_id"])}</text>')
    parts.extend(['</g>', '</svg>'])
    output_svg.write_text("\n".join(parts) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate_csv", type=Path)
    parser.add_argument("output_svg", type=Path)
    args = parser.parse_args()
    render(args.candidate_csv, args.output_svg)
    print(args.output_svg)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 运行SVG测试确认通过**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_render_radiator_candidate_family.py
```

Expected: `Ran 2 tests`、`OK`。

- [ ] **Step 5: 生成并目视检查SVG**

Run:

```bash
run_dir="$(find tmp -maxdepth 1 -type d -name 'radiator_candidate_family_*' | sort | tail -n 1)"
mkdir -p "$run_dir/plots"
python3 tests/render_radiator_candidate_family.py \
  "$run_dir/candidate_family.csv" \
  "$run_dir/plots/mass_area_envelope.svg"
```

Expected: SVG存在，包含16个`class="branch"`元素；图标题明确写出面积是上界而非设计值。使用Codex文件查看器打开SVG，确认标签不溢出、图例可读、点位位于坐标区内。

- [ ] **Step 6: 提交SVG渲染器**

```bash
git add -- \
  tests/render_radiator_candidate_family.py \
  tests/test_render_radiator_candidate_family.py
git diff --cached --check
git commit -m "可视化散热器来源分支可行域"
```

### Task 5: 完整运行、反事实守卫与证据哈希

**Files:**
- Read: `tests/radiator_candidate_math.py`
- Read: `tests/audit_radiator_candidate_family.py`
- Read: `tests/render_radiator_candidate_family.py`
- Create at runtime: `tmp/radiator_candidate_family_<run>/input_hashes.json`

- [ ] **Step 1: 运行全部本阶段测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_audit_radiator_source_chain.py \
  tests/test_audit_nak_triplet_and_radiator_provenance.py \
  tests/test_radiator_candidate_math.py \
  tests/test_audit_radiator_candidate_family.py \
  tests/test_render_radiator_candidate_family.py
```

Expected: 16项测试全部通过，无警告。

- [ ] **Step 2: 建立新的、不可覆盖的运行目录并生成产物**

Run:

```bash
run_dir="$(mktemp -d tmp/radiator_candidate_family_20260829_XXXXXX)"
rmdir "$run_dir"
python3 tests/audit_radiator_candidate_family.py "$run_dir"
mkdir "$run_dir/plots"
python3 tests/render_radiator_candidate_family.py \
  "$run_dir/candidate_family.csv" \
  "$run_dir/plots/mass_area_envelope.svg"
```

Expected: 编排器报告16个来源分支、48个质量—能量包络行，且作者实现状态为`not_uniquely_identified`。

- [ ] **Step 3: 验证关键负结论没有被输出器改写**

Run:

```bash
python3 - "$run_dir" <<'PY'
import csv, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
with (root / "candidate_family.csv").open() as handle:
    candidates = list(csv.DictReader(handle))
with (root / "mass_energy_envelope.csv").open() as handle:
    envelope = list(csv.DictReader(handle))
with (root / "rejection_log.csv").open() as handle:
    rejected = list(csv.DictReader(handle))
ident = json.loads((root / "identifiability.json").read_text())
assert len(candidates) == 16
assert len(envelope) == 48
assert rejected[0]["candidate_id"] == "legacy_current"
assert rejected[0]["status"] == "rejected"
assert "5744 > 4650" in rejected[0]["reasons"]
assert ident["author_implementation_status"] == "not_uniquely_identified"
assert ident["paper_reproduced"] is False
assert ident["no_model_load_or_simulation"] is True
print("CANDIDATE_NEGATIVE_CLAIMS_PRESERVED")
PY
```

Expected: `CANDIDATE_NEGATIVE_CLAIMS_PRESERVED`。

- [ ] **Step 4: 记录输入、脚本和输出哈希**

Run:

```bash
python3 - "$run_dir" <<'PY'
import hashlib, json, pathlib, sys
repo = pathlib.Path.cwd()
out = pathlib.Path(sys.argv[1])
inputs = [
    repo / "tests/radiator_candidate_math.py",
    repo / "tests/audit_radiator_candidate_family.py",
    repo / "tests/render_radiator_candidate_family.py",
    repo / "data/provenance/radiator_source/juhasz/source.md",
    repo / "data/provenance/radiator_source/juhasz/published_missing_matrix.csv",
    repo / "sources/NASA-TM-2007-215003-Juhasz-2007.pdf",
    repo / "sources/NASA-TM-2008-215420-Juhasz-2008.pdf",
]
outputs = sorted(path for path in out.rglob("*") if path.is_file())
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
manifest = {
    "inputs": {str(p.relative_to(repo)): digest(p) for p in inputs},
    "outputs": {str(p.relative_to(out)): digest(p) for p in outputs},
    "no_model_load_or_simulation": True,
}
(out / "input_hashes.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print(out / "input_hashes.json")
PY
shasum -a 256 "$run_dir/identifiability.json" "$run_dir/input_hashes.json"
```

Expected: 两个SHA256值均被打印，`input_hashes.json`不包含正式模型行为修改记录。

- [ ] **Step 5: 再次验证受保护文件与正式基线模型哈希**

Run:

```bash
python3 - <<'PY'
from tests.audit_radiator_candidate_family import verify_protected
assert verify_protected() == 34
print("PROTECTED_34_UNCHANGED")
PY
shasum -a 256 tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx
```

Expected:

```text
PROTECTED_34_UNCHANGED
0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391  tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx
```

### Task 6: 报告结果并保留人工确认门

**Files:**
- Modify: `docs/steady53_curve_recheck_20260828.md` after the current §37
- Read: `tmp/radiator_candidate_family_<run>/identifiability.json`
- Read: `tmp/radiator_candidate_family_<run>/rejection_log.csv`
- Read: `tmp/radiator_candidate_family_<run>/mass_energy_envelope.csv`
- Read: `tmp/radiator_candidate_family_<run>/input_hashes.json`

- [ ] **Step 1: 在报告中追加固定结构的§38**

Append a section with exactly these subsections and evidence meanings:

```markdown
## 38. 2026-08-29 方案B散热器来源约束候选族

### 38.1 范围、输入哈希与禁止事项
记录本轮只读Python路径、运行目录、输入/输出SHA256、34个受保护文件结果；明确没有加载/仿真/修改SLX。

### 38.2 十六个[147]技术分支
列出材料、翅片密度、单/双面、kappa、成熟度和由4650 kg松弛上界得到的面积上界；明确面积上界不是设计面积。

### 38.3 NaK能量约束
列出论文直接端点和功率、项目6.95 kg/s、现行物性条件反推流量及各自证据状态；不选择“最接近项目值”的流量。

### 38.4 理想辐射必要条件
列出0 K理论下界、[120]的200 K异系统敏感性和当前项目225 K对照；明确三者均不等于论文已公开冷源温度。

### 38.5 动态时间尺度的组合可识别性
报告epsilon*A、UA、M*Cp和有效时间常数关系；图5.18(d)只作为观察约束，不作为材料参数来源。

### 38.6 当前参数组审判
记录5744 kg硬淘汰以及1113/9.755/0.9/900/6.95的来源门状态。

### 38.7 结论与下一人工确认门
只允许结论“条件可行分支/不可唯一识别”；不得声明论文曲线、表5.2或整机稳态通过。列出若进入临时SLX实验仍需批准的材料分支和工程假设。
```

Do not paste prose placeholders above literally. Populate every subsection from the generated files, using ✅/⚠️/❓/❌ evidence marks and exact values/hashes.

- [ ] **Step 2: 运行报告禁止词和格式检查**

Run:

```bash
rg -n "TBD|TODO|待补|paper_reproduced.?true|论文模型已恢复|稳态已复现" \
  docs/steady53_curve_recheck_20260828.md
git diff --check -- docs/steady53_curve_recheck_20260828.md
```

Expected: 不出现本节新增的占位符或完成误报；`git diff --check`退出码0。若旧章节含历史否定语境，逐行人工确认，不做无关改写。

- [ ] **Step 3: 提交候选族报告**

```bash
git add -- docs/steady53_curve_recheck_20260828.md
git diff --cached --check
git diff --cached --name-only
git commit -m "记录方案B散热器候选族约束结果"
```

Expected: 本提交只包含主诊断报告；`tmp/`产物不进入正式模型依赖。

### Task 7: 阶段终验与执行交接

**Files:**
- Verify: all files listed above
- Do not modify: `final_steady_24a.slx`, formal `.mat` files, property functions

- [ ] **Step 1: 运行本计划全套测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_audit_radiator_source_chain.py \
  tests/test_audit_nak_triplet_and_radiator_provenance.py \
  tests/test_radiator_candidate_math.py \
  tests/test_audit_radiator_candidate_family.py \
  tests/test_render_radiator_candidate_family.py
```

Expected: 16项测试全部通过，0失败、0错误、0警告。

- [ ] **Step 2: 检查仓库差异与禁止的正式模型变化**

Run:

```bash
git diff --check
git status --short
git diff --name-only 51e34d8..HEAD | sort
git diff --name-only 51e34d8..HEAD | rg '\.(slx|mat)$|HeXe_property_simulink\.m' && exit 1 || true
```

Expected: `git diff --check`通过；阶段提交列表中不存在SLX、MAT或正式物性函数。

- [ ] **Step 3: 核验阶段结论没有越过证据**

Run:

```bash
latest_run="$(find tmp -maxdepth 1 -type d -name 'radiator_candidate_family_20260829_*' | sort | tail -n 1)"
python3 - "$latest_run" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
data = json.loads((root / "identifiability.json").read_text())
assert data["paper_reproduced"] is False
assert data["author_implementation_status"] == "not_uniquely_identified"
assert data["no_model_load_or_simulation"] is True
print("EVIDENCE_BOUNDARY_FINAL_CHECK_PASS")
PY
```

Expected: `EVIDENCE_BOUNDARY_FINAL_CHECK_PASS`。

- [ ] **Step 4: 停在人工确认门**

报告以下事实，不进入临时SLX实验：

```text
- 16个来源分支是否全部满足必要条件；
- 哪些分支被质量/能量必要条件淘汰；
- epsilon*A、UA、M*Cp和NaK流量的可识别状态；
- 当前参数组的逐项失败原因；
- 运行目录与证据SHA256；
- 正式模型仍未修改；
- 下一步需要人工选择“单个来源最强分支”或“覆盖不可识别区间的代表分支组”。
```

不得在该人工确认前调用任何SLX补丁、MATLAB仿真或正式参数写入。
