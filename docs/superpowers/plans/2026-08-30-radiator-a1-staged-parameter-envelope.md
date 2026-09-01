# 散热器 A1 分阶段参数包实验 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改正式模型、正式 `.mat` 或物性函数的前提下，生成并审计 96 行来源约束散热器静态包络，确定最多 12 个固定代表候选，并对其执行严格门控的 `500 s → 14000 s` 临时整机实验。

**Architecture:** Python 标准库负责不可变来源合同、条件稳态求解、代表包确定、独立能量复算和最终汇总；MATLAB/Simulink 官方 API 只负责从固定快照生成独立临时 SLX、应用白名单补丁并阻塞式仿真。候选模型只保存一次，`500 s` 与 `14000 s` 通过 `Simulink.SimulationInput` 改变停止时间，模型文件 SHA256 必须相同；失败行、失败候选和不可识别性全部保留。

**Tech Stack:** Python 3.14 标准库（`dataclasses`、`csv`、`json`、`hashlib`、`math`、`unittest`、`pathlib`）、MATLAB/Simulink R2025a、Stateflow API、Git；不使用网络运行时依赖，不直接写 SLX/XML，不修改正式文件。

---

## 执行前合同

批准规格：

```text
docs/superpowers/specs/2026-08-30-radiator-a1-staged-parameter-envelope-design.md
commit 97000d6a44e201517891f83b2d302a984bde1231
```

不可变模型基线：

```text
tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx
SHA256 0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391
```

执行开始时必须先使用 `superpowers:using-git-worktrees` 检查是否适合隔离工作树。若独立 worktree 无法读取当前仓库中受保护的 `tmp/` 证据快照，不复制或伪造快照；应保持当前工作目录执行，并使用本计划的显式暂存清单保护现有 63 个未跟踪文件。

本计划不接触以下现有未跟踪文件；它们只可作为只读历史参考：

```text
tests/patch_nak_enthalpy_candidate.m
tests/run_nak_enthalpy_candidate.m
tests/check_nak_enthalpy_candidate.py
tests/verify_nak_enthalpy_structure.py
tests/compare_nak_enthalpy_candidate.py
```

## 文件职责与变更边界

| 文件 | 操作 | 单一职责 |
|---|---|---|
| `tests/radiator_a1_contract.py` | Create | 固定来源、参数轴、代表角色、补丁白名单和哈希合同 |
| `tests/test_radiator_a1_contract.py` | Create | 来源合同、角色值、受保护文件和禁止晋升测试 |
| `tests/radiator_a1_math.py` | Create | 96 行条件稳态求根、质量/能量/辐射/换热必要条件 |
| `tests/test_radiator_a1_math.py` | Create | 96 行数量、唯一性、方程残差、物理根和淘汰顺序测试 |
| `tests/build_radiator_a1_screen.py` | Create | 生成离线 96 行、代表矩阵、逐候选参数清单和来源合同 |
| `tests/test_build_radiator_a1_screen.py` | Create | 12 个固定角色、无补位、确定性和文件模式测试 |
| `tests/radiator_a1_model_inventory.m` | Create | MATLAB API 只读模型结构/参数/连接/配置清单 |
| `tests/patch_radiator_a1_candidate.m` | Create | 断言保护下替换 `rediator/Tho` 并写入唯一批准参数包 |
| `tests/test_patch_radiator_a1_candidate.m` | Create | 临时副本补丁、重开、编译和白名单差异测试 |
| `tests/prepare_radiator_a1_candidates.m` | Create | 从同一快照独立创建所有离线合格候选 SLX |
| `tests/run_radiator_a1_candidate.m` | Create | 单候选阻塞式运行、日志导出、异常捕获和哈希检查 |
| `tests/run_radiator_a1_batch.m` | Create | 顺序执行全部 500 s 或推进后的 14000 s 候选 |
| `tests/test_run_radiator_a1_candidate.m` | Create | 完成时间、失败状态和停止时间不落盘的合同测试 |
| `tests/analyze_radiator_a1_run.py` | Create | 独立复算能量、有限性、末窗增长、论文差异和推进门 |
| `tests/test_analyze_radiator_a1_run.py` | Create | 能量阈值、非有限量、增长窗口和输入/目标隔离测试 |
| `tests/summarize_radiator_a1.py` | Create | 批次汇总、来源优先排序、推进清单和最终报告 |
| `tests/test_summarize_radiator_a1.py` | Create | 多候选非唯一性、零候选停止、禁止扩包络和禁止完成声明测试 |
| `docs/radiator_A1_results_20260830.md` | Create at final task | 人工可读实验结果、限制、候选状态和下一审批门 |
| `tmp/radiator_A1_20260830_A1/` | Runtime only | 本次执行唯一的大体积数据、SLX 候选、CSV/JSON、缓存和失败证据目录 |

明确不修改：

```text
final_steady_24a.slx
final_dynamic_24a.slx
HeXe_property_simulink.m
Lithium_property_simulink.m
*.mat
验收标准_论文5.4.md
```

### Task 1: 建立不可变 A1 来源与参数合同

**Files:**
- Create: `tests/radiator_a1_contract.py`
- Create: `tests/test_radiator_a1_contract.py`
- Read: `data/provenance/radiator_source/juhasz/SHA256SUMS.txt`
- Read: `tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv`

- [ ] **Step 1: 写入失败测试，锁定四个分支、六个参数轴和三个代表角色**

Create `tests/test_radiator_a1_contract.py`:

```python
import unittest

from tests import radiator_a1_contract as contract


class RadiatorA1ContractTests(unittest.TestCase):
    def test_fixed_axes_make_exactly_96_static_rows(self):
        self.assertEqual(len(contract.BRANCHES), 4)
        self.assertEqual(len(contract.FLOWS), 2)
        self.assertEqual(len(contract.EMISSIVITIES), 2)
        self.assertEqual(len(contract.SINKS), 2)
        self.assertEqual(len(contract.H_ANCHORS), 3)
        self.assertEqual(
            len(contract.BRANCHES) * len(contract.FLOWS)
            * len(contract.EMISSIVITIES) * len(contract.SINKS)
            * len(contract.H_ANCHORS),
            96,
        )

    def test_representative_roles_are_exact_and_not_a_search(self):
        roles = {role.role_id: role for role in contract.ROLES}
        self.assertEqual(set(roles), {
            "legacy_transfer", "conservative_source", "optimistic_source"
        })
        self.assertEqual(roles["legacy_transfer"].as_tuple(),
                         (6.95, 0.90, 225.0, 9.755, 900.0))
        self.assertEqual(roles["conservative_source"].as_tuple(),
                         (7.134146337, 0.85, 225.0, 200.0, 1000.0))
        self.assertEqual(roles["optimistic_source"].as_tuple(),
                         (6.95, 0.90, 200.0, 600.0, 777.0))

    def test_contract_hashes_and_protected_files_are_current(self):
        evidence = contract.verify_source_contract()
        self.assertEqual(evidence["baseline_sha256"], contract.BASELINE_SHA256)
        self.assertEqual(evidence["protected_count"], 34)
        self.assertFalse(evidence["paper_reproduced"])
        self.assertFalse(evidence["formal_promotion"])

    def test_patch_whitelist_is_exact(self):
        self.assertEqual(set(contract.PATCH_BLOCKS), {
            "Constant", "rediator/Tho", "rediator/T_env",
            "rediator/Subsystem/Constant", "rediator/Subsystem/Constant2",
            "rediator/Subsystem/Constant3", "rediator/Subsystem/Constant4",
            "rediator/Subsystem/Constant5",
        })


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试，确认模块尚不存在**

Run:

```bash
python3 -m unittest -v tests/test_radiator_a1_contract.py
```

Expected: `ImportError`，指出无法导入 `radiator_a1_contract`。

- [ ] **Step 3: 实现固定合同及哈希守卫**

Create `tests/radiator_a1_contract.py`:

```python
"""Immutable source and parameter contract for the exploration-only A1 run."""
from __future__ import annotations

from dataclasses import dataclass
import csv
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx"
BASELINE_SHA256 = "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
PROTECTED = ROOT / "tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv"
SOURCE_HASHES = {
    ROOT / "sources/NASA-TM-2007-215003-Juhasz-2007.pdf":
        "2f1a8b19be7deea95a43e6d30468e234e48e9955eed1dc5005b0efa3119fd732",
    ROOT / "sources/NASA-TM-2008-215420-Juhasz-2008.pdf":
        "eb332a4e13d75406c47f72d698f11e10708d1f230041aecdda591a86fae7e10f",
    ROOT / "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf":
        "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a",
}
CURVE_EVIDENCE_HASHES = {
    ROOT / "tmp/steady53_curves_20260828/radiator_scan_points.csv":
        "6aed804bf1ac57832055dab34483bdcb25567a5b902e5b3c6b85cb7129e8849b",
    ROOT / "tmp/steady53_curves_20260828/radiator_scan_provenance.json":
        "fe35a863731ff5394095f5d268a988cb45120a1382db9fd53bc0599e8f98e0cd",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


@dataclass(frozen=True)
class Branch:
    branch_id: str
    kappa_kg_m2: float
    maturity: str


@dataclass(frozen=True)
class NamedValue:
    case_id: str
    value: float
    unit: str
    evidence: str


@dataclass(frozen=True)
class Role:
    role_id: str
    flow_kg_s: float
    epsilon: float
    sink_K: float
    h_W_m2K: float
    cp_proxy_J_kgK: float

    def as_tuple(self) -> tuple[float, float, float, float, float]:
        return (self.flow_kg_s, self.epsilon, self.sink_K,
                self.h_W_m2K, self.cp_proxy_J_kgK)


BRANCHES = (
    Branch("T300_fd1p45_one", 4.22, "tested"),
    Branch("T300_fd1p45_two", 2.11, "tested"),
    Branch("P95_WG_fd1p45_two", 1.57, "built_not_tested"),
    Branch("APG_fd1p00_two", 0.92, "projected"),
)
FLOWS = (
    NamedValue("project_flow", 6.95, "kg/s", "project_boundary"),
    NamedValue("energy_closure_flow", 7.134146337, "kg/s", "conditional"),
)
EMISSIVITIES = (
    NamedValue("NASA_surface_0p85", 0.85, "1", "other_system_anchor"),
    NamedValue("NASA_surface_0p90", 0.90, "1", "other_system_anchor"),
)
SINKS = (
    NamedValue("NASA_120_example", 200.0, "K", "other_system_anchor"),
    NamedValue("legacy_project", 225.0, "K", "project_boundary"),
)
H_ANCHORS = (
    NamedValue("legacy_inverse", 9.755, "W/(m^2*K)", "conditional_inverse"),
    NamedValue("NASA_120_low", 200.0, "W/(m^2*K)", "other_system_anchor"),
    NamedValue("NASA_120_high", 600.0, "W/(m^2*K)", "other_system_anchor"),
)
ROLES = (
    Role("legacy_transfer", 6.95, 0.90, 225.0, 9.755, 900.0),
    Role("conservative_source", 7.134146337, 0.85, 225.0, 200.0, 1000.0),
    Role("optimistic_source", 6.95, 0.90, 200.0, 600.0, 777.0),
)
PATCH_BLOCKS = {
    "Constant": "Value",
    "rediator/Tho": "replace_with_integral_enthalpy_function",
    "rediator/T_env": "Value",
    "rediator/Subsystem/Constant": "Value",
    "rediator/Subsystem/Constant2": "Value",
    "rediator/Subsystem/Constant3": "Value",
    "rediator/Subsystem/Constant4": "Value",
    "rediator/Subsystem/Constant5": "Value",
}


def verify_source_contract() -> dict:
    assert BASELINE.is_file() and sha256(BASELINE) == BASELINE_SHA256
    for path, expected in SOURCE_HASHES.items():
        assert path.is_file() and sha256(path) == expected, path
    for path, expected in CURVE_EVIDENCE_HASHES.items():
        assert path.is_file() and sha256(path) == expected, path
    with PROTECTED.open() as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 34
    for row in rows:
        path = Path(row["paths"])
        assert path.is_file() and sha256(path) == row["hashes"], path
    return {
        "baseline_path": str(BASELINE),
        "baseline_sha256": BASELINE_SHA256,
        "source_hashes": {str(p.relative_to(ROOT)): h for p, h in SOURCE_HASHES.items()},
        "curve_evidence_hashes": {
            str(p.relative_to(ROOT)): h for p, h in CURVE_EVIDENCE_HASHES.items()
        },
        "protected_manifest": str(PROTECTED),
        "protected_count": len(rows),
        "paper_reproduced": False,
        "formal_promotion": False,
    }
```

- [ ] **Step 4: 运行合同测试确认通过**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_a1_contract.py
```

Expected: `Ran 4 tests`、`OK`。

- [ ] **Step 5: 暂存并提交合同文件**

```bash
git add -- tests/radiator_a1_contract.py tests/test_radiator_a1_contract.py
git diff --cached --check
git diff --cached --name-only
git commit -m "锁定散热器A1来源与参数合同"
```

Expected: 暂存区只包含上述两个文件。

### Task 2: 用 TDD 实现 96 行条件稳态求解器

**Files:**
- Create: `tests/radiator_a1_math.py`
- Create: `tests/test_radiator_a1_math.py`
- Read: `tests/radiator_candidate_math.py`

- [ ] **Step 1: 写入 96 行、物理根和方程残差失败测试**

Create `tests/test_radiator_a1_math.py`:

```python
import math
import unittest

from tests import radiator_a1_math as a1math


class RadiatorA1MathTests(unittest.TestCase):
    def test_generate_exactly_96_unique_rows_deterministically(self):
        first = a1math.generate_static_rows()
        second = a1math.generate_static_rows()
        self.assertEqual(len(first), 96)
        self.assertEqual(len({row.row_id for row in first}), 96)
        self.assertEqual(first, second)

    def test_each_non_rejected_row_closes_all_three_equations(self):
        for row in a1math.generate_static_rows():
            if row.condition_status == "rejected":
                continue
            self.assertGreater(row.Twall_K, row.T_sink_K)
            self.assertLess(row.Twall_K, a1math.T_MEAN_K)
            self.assertGreater(row.A_rad_m2, 0.0)
            self.assertGreater(row.UA_W_K, 0.0)
            self.assertLess(abs(row.exchange_residual_W), 1e-6)
            self.assertLess(abs(row.radiation_residual_W), 1e-6)

    def test_mass_gate_uses_4650_as_upper_bound_only(self):
        rows = a1math.generate_static_rows()
        rejected = [row for row in rows if "mass_above_4650_kg" in row.rejection_reasons]
        self.assertTrue(rejected)
        self.assertTrue(all(row.M_rad_kg > 4650.0 for row in rejected))
        self.assertTrue(all(row.condition_status == "rejected" for row in rejected))

    def test_flow_energy_identities_are_preserved(self):
        rows = a1math.generate_static_rows()
        q_project = {round(row.Q_NaK_W, 6) for row in rows
                     if row.flow_case == "project_flow"}
        q_closure = {row.Q_NaK_W for row in rows
                     if row.flow_case == "energy_closure_flow"}
        self.assertEqual(q_project, {round(1_580_132.9924937415, 6)})
        self.assertEqual(len(q_closure), 1)
        self.assertTrue(math.isclose(next(iter(q_closure)), 1_622_000.0,
                                     rel_tol=0.0, abs_tol=1e-3))

    def test_invalid_root_is_recorded_not_hidden(self):
        result = a1math.solve_static_case(
            branch_id="synthetic", kappa_kg_m2=1.0,
            flow_case="synthetic", m_dot_kg_s=6.95,
            epsilon_case="bad", epsilon=0.0,
            sink_case="bad", sink_K=225.0,
            h_case="bad", h_W_m2K=200.0,
            evidence_status_per_input="test",
        )
        self.assertEqual(result.condition_status, "rejected")
        self.assertIn("epsilon_out_of_range", result.rejection_reasons)
        self.assertTrue(math.isnan(result.Twall_K))


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试，确认模块缺失**

Run:

```bash
python3 -m unittest -v tests/test_radiator_a1_math.py
```

Expected: `ImportError`。

- [ ] **Step 3: 实现解析消元后的物理根求解和固定淘汰顺序**

Create `tests/radiator_a1_math.py`:

```python
"""Pure A1 conditional steady solver; no files, model APIs, or fitting."""
from __future__ import annotations

from dataclasses import dataclass
import itertools
import math

from tests import radiator_a1_contract as contract
from tests import radiator_candidate_math as base_math


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
    return (base_math.nak_enthalpy_J_kg(T_IN_K)
            - base_math.nak_enthalpy_J_kg(T_OUT_K))


def _wall_root(epsilon: float, sink_K: float, h_W_m2K: float) -> float:
    def residual(wall_K: float) -> float:
        return (h_W_m2K * (T_MEAN_K - wall_K)
                - epsilon * SIGMA * (wall_K**4 - sink_K**4))

    lo = math.nextafter(sink_K, math.inf)
    hi = math.nextafter(T_MEAN_K, -math.inf)
    f_lo, f_hi = residual(lo), residual(hi)
    if not (f_lo > 0.0 and f_hi < 0.0):
        raise ValueError("no_physical_wall_root")
    for _ in range(100):
        mid = 0.5 * (lo + hi)
        if residual(mid) > 0.0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def solve_static_case(*, branch_id: str, kappa_kg_m2: float,
                      flow_case: str, m_dot_kg_s: float,
                      epsilon_case: str, epsilon: float,
                      sink_case: str, sink_K: float,
                      h_case: str, h_W_m2K: float,
                      evidence_status_per_input: str,
                      technology_maturity: str = "test") -> StaticRow:
    row_id = "__".join((branch_id, flow_case, epsilon_case, sink_case, h_case))
    reasons: list[str] = []
    if not (0.0 < epsilon <= 1.0):
        reasons.append("epsilon_out_of_range")
    if not all(math.isfinite(v) and v > 0.0 for v in
               (kappa_kg_m2, m_dot_kg_s, h_W_m2K, sink_K)):
        reasons.append("nonpositive_or_nonfinite_input")
    if not (sink_K < T_OUT_K):
        reasons.append("sink_not_below_cold_endpoint")
    if reasons:
        nan = math.nan
        return StaticRow(row_id, branch_id, kappa_kg_m2, technology_maturity,
                         flow_case, m_dot_kg_s, epsilon_case, epsilon,
                         sink_case, sink_K, h_case, h_W_m2K,
                         nan, nan, nan, nan, nan, nan, nan, nan, nan,
                         "rejected", evidence_status_per_input, tuple(reasons))
    q_W = m_dot_kg_s * _enthalpy_rise_J_kg()
    try:
        wall_K = _wall_root(epsilon, sink_K, h_W_m2K)
    except ValueError:
        nan = math.nan
        return StaticRow(row_id, branch_id, kappa_kg_m2, technology_maturity,
                         flow_case, m_dot_kg_s, epsilon_case, epsilon,
                         sink_case, sink_K, h_case, h_W_m2K,
                         q_W, nan, nan, nan, nan, nan, nan, nan, nan,
                         "rejected", evidence_status_per_input,
                         ("no_physical_wall_root",))
    area = q_W / (h_W_m2K * (T_MEAN_K - wall_K))
    ua = h_W_m2K * area
    mass = kappa_kg_m2 * area
    exchange = h_W_m2K * area * (T_MEAN_K - wall_K)
    radiation = epsilon * SIGMA * area * (wall_K**4 - sink_K**4)
    exchange_residual = exchange - q_W
    radiation_residual = radiation - q_W
    if not all(math.isfinite(v) and v > 0.0 for v in (area, ua, mass)):
        reasons.append("nonpositive_or_nonfinite_derived_quantity")
    if mass > MASS_UPPER_KG:
        reasons.append("mass_above_4650_kg")
    if radiation + 1e-6 < q_W:
        reasons.append("insufficient_radiation_capacity")
    status = "rejected" if reasons else "not_rejected_under_necessary_conditions"
    return StaticRow(
        row_id, branch_id, kappa_kg_m2, technology_maturity,
        flow_case, m_dot_kg_s, epsilon_case, epsilon,
        sink_case, sink_K, h_case, h_W_m2K,
        q_W, wall_K, area, area, ua, mass, MASS_UPPER_KG - mass,
        exchange_residual, radiation_residual, status,
        evidence_status_per_input, tuple(reasons),
    )


def generate_static_rows() -> list[StaticRow]:
    rows = []
    for branch, flow, epsilon, sink, h_anchor in itertools.product(
            contract.BRANCHES, contract.FLOWS, contract.EMISSIVITIES,
            contract.SINKS, contract.H_ANCHORS):
        evidence = "|".join((branch.maturity, flow.evidence,
                             epsilon.evidence, sink.evidence, h_anchor.evidence))
        rows.append(solve_static_case(
            branch_id=branch.branch_id,
            kappa_kg_m2=branch.kappa_kg_m2,
            technology_maturity=branch.maturity,
            flow_case=flow.case_id,
            m_dot_kg_s=flow.value,
            epsilon_case=epsilon.case_id,
            epsilon=epsilon.value,
            sink_case=sink.case_id,
            sink_K=sink.value,
            h_case=h_anchor.case_id,
            h_W_m2K=h_anchor.value,
            evidence_status_per_input=evidence,
        ))
    return rows
```

- [ ] **Step 4: 运行纯数学测试并检查精确数量**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_a1_contract.py \
  tests/test_radiator_a1_math.py
```

Expected: `Ran 9 tests`、`OK`。

- [ ] **Step 5: 提交纯数学求解器**

```bash
git add -- tests/radiator_a1_math.py tests/test_radiator_a1_math.py
git diff --cached --check
git commit -m "实现散热器A1九十六行条件求解"
```

### Task 3: 用 TDD 生成离线证据和最多十二个固定代表包

**Files:**
- Create: `tests/build_radiator_a1_screen.py`
- Create: `tests/test_build_radiator_a1_screen.py`

- [ ] **Step 1: 写入输出模式、确定性、无补位和代理热容失败测试**

Create `tests/test_build_radiator_a1_screen.py`:

```python
import csv
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tests import build_radiator_a1_screen as builder


ROOT = Path(__file__).resolve().parents[1]


def digest_tree(path: Path) -> dict[str, str]:
    return {str(p.relative_to(path)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(path.rglob("*")) if p.is_file()}


class BuildRadiatorA1ScreenTests(unittest.TestCase):
    def test_output_has_96_rows_and_at_most_12_fixed_representatives(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            out = Path(folder)
            builder.write_screen(out)
            with (out / "offline_screen/offline_96.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            with (out / "representatives/representative_matrix.csv").open() as handle:
                reps = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 96)
            self.assertEqual(len(reps), 12)
            self.assertEqual(len({row["candidate_id"] for row in reps}), 12)
            self.assertEqual({row["role_id"] for row in reps}, {
                "legacy_transfer", "conservative_source", "optimistic_source"
            })

    def test_proxy_capacity_and_timescale_are_not_author_properties(self):
        package = builder.build_screen()
        for rep in package["representatives"]:
            self.assertIn(rep["cp_proxy_J_kgK"], (777.0, 900.0, 1000.0))
            self.assertEqual(rep["cp_identity"], "sensitivity_proxy")
            if rep["eligible_for_slx"]:
                self.assertGreater(rep["C_eff_proxy_J_K"], 0.0)
                self.assertGreater(rep["tau_predicted_s"], 0.0)

    def test_rejected_fixed_role_is_not_replaced(self):
        package = builder.build_screen(force_reject_candidate="APG_fd1p00_two__optimistic_source")
        reps = package["representatives"]
        self.assertEqual(len(reps), 12)
        target = next(row for row in reps
                      if row["candidate_id"] == "APG_fd1p00_two__optimistic_source")
        self.assertFalse(target["eligible_for_slx"])
        self.assertIn("test_forced_rejection", target["rejection_reasons"])
        self.assertEqual(sum(row["eligible_for_slx"] for row in reps),
                         sum(row["eligible_for_slx"] for row in builder.build_screen()["representatives"]) - 1)

    def test_outputs_are_byte_deterministic(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as first, \
             tempfile.TemporaryDirectory(dir=ROOT / "tmp") as second:
            builder.write_screen(Path(first))
            builder.write_screen(Path(second))
            self.assertEqual(digest_tree(Path(first)), digest_tree(Path(second)))

    def test_every_eligible_candidate_has_one_manifest(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            out = Path(folder)
            builder.write_screen(out)
            selection = json.loads((out / "representatives/selection.json").read_text())
            manifests = list((out / "representatives").glob("*/parameter_manifest.json"))
            self.assertEqual(len(manifests), selection["eligible_count"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认编排器缺失**

Run:

```bash
python3 -m unittest -v tests/test_build_radiator_a1_screen.py
```

Expected: `ImportError`。

- [ ] **Step 3: 实现代表角色匹配、代理热容和确定性文件输出**

Create `tests/build_radiator_a1_screen.py` with these exact public functions and fields:

```python
"""Write the deterministic offline A1 package below an existing run root."""
from __future__ import annotations

from dataclasses import asdict
import csv
import hashlib
import json
import math
from pathlib import Path

from tests import radiator_a1_contract as contract
from tests import radiator_a1_math as a1math


ROOT = Path(__file__).resolve().parents[1]


def _same(left: float, right: float) -> bool:
    return math.isclose(left, right, rel_tol=0.0, abs_tol=1e-9)


def _static_for_role(rows, branch_id, role):
    matches = [row for row in rows
               if row.branch_id == branch_id
               and _same(row.m_dot_NaK_kg_s, role.flow_kg_s)
               and _same(row.epsilon, role.epsilon)
               and _same(row.T_sink_K, role.sink_K)
               and _same(row.h_W_m2K, role.h_W_m2K)]
    if len(matches) != 1:
        raise AssertionError((branch_id, role.role_id, len(matches)))
    return matches[0]


def build_screen(force_reject_candidate: str | None = None) -> dict:
    source = contract.verify_source_contract()
    rows = a1math.generate_static_rows()
    representatives = []
    for branch in contract.BRANCHES:
        for role in contract.ROLES:
            row = _static_for_role(rows, branch.branch_id, role)
            candidate_id = f"{branch.branch_id}__{role.role_id}"
            reasons = list(row.rejection_reasons)
            if candidate_id == force_reject_candidate:
                reasons.append("test_forced_rejection")
            capacity = row.M_rad_kg * role.cp_proxy_J_kgK
            g_rad = 4.0 * a1math.SIGMA * row.epsilon * row.A_rad_m2 * row.Twall_K**3
            g_effective = row.UA_W_K + g_rad
            tau = capacity / g_effective if capacity > 0.0 and g_effective > 0.0 else math.nan
            eligible = (row.condition_status != "rejected" and not reasons
                        and all(math.isfinite(v) and v > 0.0
                                for v in (capacity, g_effective, tau)))
            representatives.append({
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
                "C_eff_proxy_J_K": capacity,
                "G_effective_W_K": g_effective,
                "tau_predicted_s": tau,
                "timescale_relation": (
                    "within_120_150_s" if 120.0 <= tau <= 150.0
                    else "below_120_s" if tau < 120.0 else "above_150_s"
                ),
                "eligible_for_slx": eligible,
                "rejection_reasons": reasons,
                "paper_reproduced": False,
                "formal_promotion": False,
            })
    return {
        "source_contract": source,
        "unit_contract": {
            "m_dot_NaK_kg_s": "kg/s", "epsilon": "1", "T_sink_K": "K",
            "h_W_m2K": "W/(m^2*K)", "Q_NaK_W": "W", "Twall_K": "K",
            "A_exchange_m2": "m^2", "A_rad_m2": "m^2", "UA_W_K": "W/K",
            "M_rad_kg": "kg", "C_eff_proxy_J_K": "J/K",
            "tau_predicted_s": "s",
        },
        "offline_rows": [asdict(row) for row in rows],
        "representatives": representatives,
        "paper_reproduced": False,
        "formal_promotion": False,
    }


def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        raise ValueError(f"refuse empty CSV: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = []
    for row in rows:
        normalized.append({key: json.dumps(value, ensure_ascii=False)
                           if isinstance(value, (list, tuple, dict, bool)) else value
                           for key, value in row.items()})
    with path.open("x", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(normalized[0]))
        writer.writeheader()
        writer.writerows(normalized)


def _write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2,
                               sort_keys=True, allow_nan=False) + "\n")


def write_screen(output: Path) -> None:
    output = output.resolve()
    if not output.is_relative_to(ROOT / "tmp"):
        raise ValueError("output must be below tmp/")
    package = build_screen()
    offline = output / "offline_screen"
    reps_dir = output / "representatives"
    _write_json(output / "source_contract/source_contract.json",
                package["source_contract"])
    _write_json(output / "source_contract/unit_contract.json",
                package["unit_contract"])
    _write_csv(offline / "offline_96.csv", package["offline_rows"])
    rejected = [row for row in package["offline_rows"]
                if row["condition_status"] == "rejected"]
    _write_csv(offline / "offline_rejection_log.csv",
               rejected or [{"status": "none_rejected"}])
    _write_csv(reps_dir / "representative_matrix.csv",
               package["representatives"])
    eligible = [row for row in package["representatives"]
                if row["eligible_for_slx"]]
    _write_json(reps_dir / "selection.json", {
        "eligible_candidate_ids": [row["candidate_id"] for row in eligible],
        "eligible_count": len(eligible),
        "fixed_role_count": len(package["representatives"]),
        "replacement_allowed": False,
        "paper_reproduced": False,
    })
    for row in eligible:
        _write_json(reps_dir / row["candidate_id"] / "parameter_manifest.json", row)
    hashes = {str(path.relative_to(output)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(output.rglob("*")) if path.is_file()}
    _write_json(output / "source_contract/output_hashes.json", hashes)


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write_screen(args.output)
    print("RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 运行屏选测试并修正任何真实数值误差**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_a1_contract.py \
  tests/test_radiator_a1_math.py \
  tests/test_build_radiator_a1_screen.py
```

Expected: `Ran 14 tests`、`OK`。如果浮点基准差异只来自最后几位，必须回到当前 NaK 多项式复算并更新测试中的派生显示值；不得修改批准输入来让测试通过。

- [ ] **Step 5: 提交离线编排器**

```bash
git add -- \
  tests/build_radiator_a1_screen.py \
  tests/test_build_radiator_a1_screen.py
git diff --cached --check
git commit -m "生成散热器A1固定代表参数包"
```

### Task 4: 用官方 API 建立断言保护的候选补丁

**Files:**
- Create: `tests/radiator_a1_model_inventory.m`
- Create: `tests/patch_radiator_a1_candidate.m`
- Create: `tests/test_patch_radiator_a1_candidate.m`
- Read only: `tests/patch_nak_enthalpy_candidate.m`

- [ ] **Step 1: 写入只读模型清单函数**

Create `tests/radiator_a1_model_inventory.m`:

```matlab
function data = radiator_a1_model_inventory(model)
%RADIATOR_A1_MODEL_INVENTORY Deterministic API inventory for A1 audits.
model = string(model);
paths = sort(string(find_system(model, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'off', 'Type', 'Block')));
relative = extractAfter(paths, strlength(model));
types = strings(size(paths));
keys = strings(0, 1);
values = strings(0, 1);
edges = strings(0, 1);
for k = 1:numel(paths)
    block = paths(k);
    types(k) = string(get_param(block, 'BlockType'));
    parameters = get_param(block, 'DialogParameters');
    if ~isempty(parameters)
        names = sort(string(fieldnames(parameters)));
        for j = 1:numel(names)
            keys(end+1, 1) = relative(k) + "|" + names(j); %#ok<AGROW>
            values(end+1, 1) = string(jsonencode(get_param(block, names(j)))); %#ok<AGROW>
        end
    end
    handles = get_param(block, 'PortHandles');
    for j = 1:numel(handles.Inport)
        line = get_param(handles.Inport(j), 'Line');
        if line < 0, continue; end
        source = get_param(line, 'SrcPortHandle');
        if source < 0, continue; end
        edges(end+1, 1) = extractAfter(string(get_param(source, 'Parent')), ...
            strlength(model)) + "#" + get_param(source, 'PortNumber') + ...
            "->" + relative(k) + "#" + j; %#ok<AGROW>
    end
end
settings = struct();
for key = ["Solver", "SolverType", "StartTime", "StopTime", "RelTol", ...
        "AbsTol", "MaxStep", "LoadInitialState", "InitialState", ...
        "AlgebraicLoopSolver"]
    settings.(key) = get_param(model, key);
end
root = sfroot;
allCharts = root.find('-isa', 'Stateflow.EMChart');
charts = struct('path', {}, 'script', {});
for k = 1:numel(allCharts)
    if startsWith(string(allCharts(k).Path), model + "/")
        charts(end+1) = struct( ...
            'path', extractAfter(string(allCharts(k).Path), strlength(model)), ...
            'script', string(allCharts(k).Script)); %#ok<AGROW>
    end
end
if ~isempty(charts)
    [~, order] = sort(string({charts.path}));
    charts = charts(order);
end
[sortedKeys, order] = sort(keys);
data = struct( ...
    'blocks', struct('relative', cellstr(relative), 'type', cellstr(types)), ...
    'edges', cellstr(sort(edges)), ...
    'parameters', struct('key', cellstr(sortedKeys), ...
                         'value', cellstr(values(order))), ...
    'settings', settings, ...
    'charts', {charts});
end
```

- [ ] **Step 2: 写入补丁失败测试**

Create `tests/test_patch_radiator_a1_candidate.m`:

```matlab
function tests = test_patch_radiator_a1_candidate
tests = functiontests(localfunctions);
end

function testPatchIsLimitedAndReopens(testCase)
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(tempname(fullfile(repo, 'tmp')));
mkdir(runRoot);
cleanupRoot = onCleanup(@() removeOwnedTemp(runRoot)); %#ok<NASGU>
command = "cd '" + replace(repo, "'", "'\''") + ...
    "' && python3 tests/build_radiator_a1_screen.py '" + ...
    replace(runRoot, "'", "'\''") + "'";
[status, output] = system(command);
verifyEqual(testCase, status, 0, output);
selection = jsondecode(fileread(fullfile(runRoot, ...
    'representatives', 'selection.json')));
verifyGreaterThan(testCase, numel(selection.eligible_candidate_ids), 0);
candidateId = string(selection.eligible_candidate_ids{1});
manifest = fullfile(runRoot, 'representatives', candidateId, ...
    'parameter_manifest.json');
candidateDir = fullfile(runRoot, 'candidate_test');
mkdir(candidateDir);
source = fullfile(repo, 'tmp', 'steady53_curves_20260828', ...
    'source_f8bcd83', 'final_steady_24a.slx');
candidateFile = fullfile(candidateDir, 'candidate.slx');
copyfile(source, candidateFile);
load_system(candidateFile);
cleanupModel = onCleanup(@() closeCandidate()); %#ok<NASGU>
audit = patch_radiator_a1_candidate("candidate", manifest, candidateDir);
verifyEqual(testCase, audit.source_sha256, ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyEqual(testCase, audit.changed_parameter_paths, [ ...
    "Constant"; "rediator/Subsystem/Constant"; ...
    "rediator/Subsystem/Constant2"; "rediator/Subsystem/Constant3"; ...
    "rediator/Subsystem/Constant4"; "rediator/Subsystem/Constant5"; ...
    "rediator/T_env"; "rediator/Tho"]);
verifyTrue(testCase, isfile(fullfile(candidateDir, 'patch_manifest.json')));
verifyTrue(testCase, isfile(fullfile(candidateDir, 'structural_diff.json')));
verifyNotEqual(testCase, audit.candidate_sha256, audit.source_sha256);

    function closeCandidate()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function removeOwnedTemp(pathValue)
if bdIsLoaded('candidate'), close_system('candidate', 0); end
if isfolder(pathValue), rmdir(pathValue, 's'); end
end
```

- [ ] **Step 3: 运行 MATLAB 测试，确认补丁函数缺失**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); r=run(testsuite('tests/test_patch_radiator_a1_candidate.m')); assertSuccess(r)"
```

Expected: FAIL，指出 `patch_radiator_a1_candidate` 未定义。

- [ ] **Step 4: 实现路径、原值、结构和配置断言保护的 API 补丁**

Create `tests/patch_radiator_a1_candidate.m`:

```matlab
function audit = patch_radiator_a1_candidate(model, manifestPath, outputDir)
%PATCH_RADIATOR_A1_CANDIDATE Exploration-only official-API patch.
model = string(model);
manifestPath = string(manifestPath);
outputDir = string(outputDir);
repo = string(fileparts(fileparts(mfilename('fullpath'))));
file = string(get_param(model, 'FileName'));
assert(startsWith(file, fullfile(repo, 'tmp') + filesep));
assert(startsWith(manifestPath, fullfile(repo, 'tmp') + filesep));
assert(startsWith(outputDir, fullfile(repo, 'tmp') + filesep));
sourceHash = hashFile(file);
assert(sourceHash == "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
manifest = jsondecode(fileread(manifestPath));
assert(manifest.eligible_for_slx);
assert(~manifest.paper_reproduced && ~manifest.formal_promotion);

expected = {
    model + "/Constant", 'Constant', 'Value', '6.95';
    model + "/rediator/T_env", 'Constant', 'Value', '225';
    model + "/rediator/Subsystem/Constant", 'Constant', 'Value', 'epsilon';
    model + "/rediator/Subsystem/Constant2", 'Constant', 'Value', '1113';
    model + "/rediator/Subsystem/Constant3", 'Constant', 'Value', '5744';
    model + "/rediator/Subsystem/Constant4", 'Constant', 'Value', 'Cp_rad';
    model + "/rediator/Subsystem/Constant5", 'Constant', 'Value', '9.755'};
for k = 1:size(expected, 1)
    assert(strcmp(get_param(expected{k,1}, 'BlockType'), expected{k,2}));
    assert(strcmp(get_param(expected{k,1}, expected{k,3}), expected{k,4}));
end
tho = model + "/rediator/Tho";
assert(strcmp(get_param(tho, 'BlockType'), 'Fcn'));
assert(strcmp(get_param(tho, 'Expr'), '((u(2)-0.8)*u(3)+u(1))/(u(2)+0.2)'));

before = radiator_a1_model_inventory(model);
position = get_param(tho, 'Position');
orientation = get_param(tho, 'Orientation');
delete_block(tho);
add_block('simulink/User-Defined Functions/MATLAB Function', tho, ...
    'Position', position, 'Orientation', orientation);
chart = sfroot.find('-isa', 'Stateflow.EMChart', 'Path', tho);
assert(numel(chart) == 1);
chart.Script = integralScript();
ensureLine(model + "/rediator", 'Mux4/1', 'Tho/1');
ensureLine(model + "/rediator", 'Tho/1', 'Mux2/6');
ensureLine(model + "/rediator", 'Tho/1', 'T_ho/1');

set_param(model + "/Constant", 'Value', number(manifest.m_dot_NaK_kg_s));
set_param(model + "/rediator/T_env", 'Value', number(manifest.T_sink_K));
set_param(model + "/rediator/Subsystem/Constant", 'Value', number(manifest.epsilon));
set_param(model + "/rediator/Subsystem/Constant2", 'Value', number(manifest.A_rad_m2));
set_param(model + "/rediator/Subsystem/Constant3", 'Value', number(manifest.M_rad_kg));
set_param(model + "/rediator/Subsystem/Constant4", 'Value', number(manifest.cp_proxy_J_kgK));
set_param(model + "/rediator/Subsystem/Constant5", 'Value', number(manifest.h_W_m2K));
set_param(model, 'SimulationCommand', 'update');
after = radiator_a1_model_inventory(model);
assert(isequal(before.settings, after.settings));
assertOnlyWhitelisted(before, after);

save_system(model, file);
close_system(model, 0);
load_system(file);
reopened = radiator_a1_model_inventory(model);
assert(isequal(after, reopened), 'Saved inventory changed on reopen');
candidateHash = hashFile(file);
changed = ["Constant"; "rediator/Subsystem/Constant"; ...
    "rediator/Subsystem/Constant2"; "rediator/Subsystem/Constant3"; ...
    "rediator/Subsystem/Constant4"; "rediator/Subsystem/Constant5"; ...
    "rediator/T_env"; "rediator/Tho"];
audit = struct( ...
    'candidate_id', string(manifest.candidate_id), ...
    'source_sha256', sourceHash, ...
    'candidate_sha256', candidateHash, ...
    'manifest_sha256', hashFile(manifestPath), ...
    'patch_sha256', hashFile(string(mfilename('fullpath')) + ".m"), ...
    'changed_parameter_paths', changed, ...
    'official_api_only', true, ...
    'paper_reproduced', false, ...
    'formal_promotion', false);
writeJSON(fullfile(outputDir, 'patch_manifest.json'), audit);
writeJSON(fullfile(outputDir, 'structural_diff.json'), ...
    struct('before', before, 'after', after, 'whitelist_pass', true));
end

function assertOnlyWhitelisted(before, after)
allowed = ["/Constant|Value"; "/rediator/T_env|Value"; ...
    "/rediator/Subsystem/Constant|Value"; ...
    "/rediator/Subsystem/Constant2|Value"; ...
    "/rediator/Subsystem/Constant3|Value"; ...
    "/rediator/Subsystem/Constant4|Value"; ...
    "/rediator/Subsystem/Constant5|Value"];
beforeKeys = string({before.parameters.key});
beforeValues = string({before.parameters.value});
afterKeys = string({after.parameters.key});
afterValues = string({after.parameters.value});
allKeys = union(beforeKeys, afterKeys);
for key = reshape(allKeys, 1, [])
    if startsWith(key, "/rediator/Tho|") || startsWith(key, "/rediator/Tho/")
        continue
    end
    beforeIndex = find(beforeKeys == key);
    afterIndex = find(afterKeys == key);
    assert(isscalar(beforeIndex) && isscalar(afterIndex));
    if beforeValues(beforeIndex) ~= afterValues(afterIndex)
        assert(any(key == allowed), "Unexpected parameter change: " + key);
    end
end
beforeBlocks = string({before.blocks.relative});
afterBlocks = string({after.blocks.relative});
assert(isequal(beforeBlocks(~startsWith(beforeBlocks, "/rediator/Tho")), ...
               afterBlocks(~startsWith(afterBlocks, "/rediator/Tho"))));
beforeEdges = string(before.edges);
afterEdges = string(after.edges);
assert(isequal(beforeEdges(~contains(beforeEdges, "/rediator/Tho")), ...
               afterEdges(~contains(afterEdges, "/rediator/Tho"))));
end

function text = integralScript()
lines = [
    "function Tout = nak_enthalpy_outlet(u)"
    "%#codegen"
    "% Exploration-only analytic integral of the existing NaK cp(T)."
    "Twall=u(1); r=u(2); Tin=u(3);"
    "cpin=1000*(1.061-3.694e-4*Tin+4.615e-8*Tin^2+1.509e-10*Tin^3);"
    "assert(isfinite(Twall)&&isfinite(r)&&isfinite(Tin)&&cpin>0&&r>0);"
    "lo=260.5; hi=Tin; assert(hi>lo&&Twall<Tin);"
    "hTin=1000*(1.061*Tin-3.694e-4*Tin^2/2+4.615e-8*Tin^3/3+1.509e-10*Tin^4/4);"
    "hLo=1000*(1.061*lo-3.694e-4*lo^2/2+4.615e-8*lo^3/3+1.509e-10*lo^4/4);"
    "fLo=(r/cpin)*(hTin-hLo)-(0.8*Tin+0.2*lo-Twall);"
    "fHi=-(Tin-Twall); assert(fLo>=0&&fHi<=0);"
    "for k=1:60"
    " mid=0.5*(lo+hi);"
    " hMid=1000*(1.061*mid-3.694e-4*mid^2/2+4.615e-8*mid^3/3+1.509e-10*mid^4/4);"
    " fMid=(r/cpin)*(hTin-hMid)-(0.8*Tin+0.2*mid-Twall);"
    " if fMid>=0, lo=mid; else, hi=mid; end"
    "end"
    "Tout=0.5*(lo+hi);"
    "end"];
text = strjoin(lines, newline);
end

function ensureLine(system, source, destination)
destinationBlock = extractBefore(string(destination), "/");
destinationPort = str2double(extractAfter(string(destination), "/"));
handles = get_param(system + "/" + destinationBlock, 'PortHandles');
line = get_param(handles.Inport(destinationPort), 'Line');
if line < 0
    add_line(system, source, destination, 'autorouting', 'on');
else
    sourceHandle = get_param(line, 'SrcPortHandle');
    assert(string(get_param(sourceHandle, 'Parent')) == ...
        system + "/" + extractBefore(string(source), "/"));
end
end

function value = number(input)
value = char(string(num2str(double(input), '%.17g')));
end

function value = hashFile(path)
[status, output] = system("shasum -a 256 '" + ...
    replace(string(path), "'", "'\''") + "'");
assert(status == 0);
parts = split(strtrim(string(output)));
value = parts(1);
end

function writeJSON(path, value)
assert(~isfile(path));
file = fopen(path, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
```

- [ ] **Step 5: 运行补丁测试并确认重新打开/编译/白名单检查通过**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); r=run(testsuite('tests/test_patch_radiator_a1_candidate.m')); assertSuccess(r)"
```

Expected: `testPatchIsLimitedAndReopens` PASS；输出不得包含仿真开始标记。

- [ ] **Step 6: 提交 API 补丁和结构清单**

```bash
git add -- \
  tests/radiator_a1_model_inventory.m \
  tests/patch_radiator_a1_candidate.m \
  tests/test_patch_radiator_a1_candidate.m
git diff --cached --check
git commit -m "实现散热器A1候选API白名单补丁"
```

### Task 5: 建立候选准备器和阻塞式仿真运行器

**Files:**
- Create: `tests/prepare_radiator_a1_candidates.m`
- Create: `tests/run_radiator_a1_candidate.m`
- Create: `tests/run_radiator_a1_batch.m`
- Create: `tests/test_run_radiator_a1_candidate.m`
- Read: `tmp/steady53_curves_20260828/source_f8bcd83/tests/steady53/steady53_signal_manifest.m`
- Read: `tmp/steady53_curves_20260828/source_f8bcd83/tests/steady53/reset_steady53_property_warning_state.m`

- [ ] **Step 1: 写入运行完成、非有限量和哈希失败测试**

Create `tests/test_run_radiator_a1_candidate.m`:

```matlab
function tests = test_run_radiator_a1_candidate
tests = functiontests(localfunctions);
end

function testCompletionGateRequiresExactStopAndFiniteData(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyTrue(testCase, hooks.completionGate([0; 250; 500], "", [1; 2; 3], 500));
verifyFalse(testCase, hooks.completionGate([0; 499.9], "", [1; 2], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "solver failed", [1; 2], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "", [1; Inf], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "", [1; 2+1i], 500));
end

function testStageContractAllowsOnly500And14000(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyWarningFree(testCase, @() hooks.validateStopTime(500));
verifyWarningFree(testCase, @() hooks.validateStopTime(14000));
verifyError(testCase, @() hooks.validateStopTime(501), ...
    'radiatorA1:UnsupportedStopTime');
end

function testLongStageMustReferenceSameCandidateHash(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyTrue(testCase, hooks.sameCandidateHash("abc", "abc"));
verifyFalse(testCase, hooks.sameCandidateHash("abc", "def"));
end
```

- [ ] **Step 2: 运行测试确认运行器缺失**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); r=run(testsuite('tests/test_run_radiator_a1_candidate.m')); assertSuccess(r)"
```

Expected: FAIL，指出 `run_radiator_a1_candidate` 未定义。

- [ ] **Step 3: 实现每个候选从源快照独立生成的准备器**

Create `tests/prepare_radiator_a1_candidates.m`:

```matlab
function summary = prepare_radiator_a1_candidates(runRoot)
%PREPARE_RADIATOR_A1_CANDIDATES Copy, patch, reopen and compile each candidate.
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
source = fullfile(repo, 'tmp', 'steady53_curves_20260828', ...
    'source_f8bcd83', 'final_steady_24a.slx');
assert(hashFile(source) == "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
selection = jsondecode(fileread(fullfile(runRoot, ...
    'representatives', 'selection.json')));
ids = string(selection.eligible_candidate_ids);
summary = struct('candidate_id', {}, 'prepared', {}, 'error', {}, ...
    'candidate_file', {}, 'candidate_sha256', {});
for k = 1:numel(ids)
    id = ids(k);
    destination = fullfile(runRoot, 'candidates_500s', id);
    mkdir(destination);
    candidateFile = fullfile(destination, 'candidate.slx');
    manifest = fullfile(runRoot, 'representatives', id, ...
        'parameter_manifest.json');
    row = struct('candidate_id', id, 'prepared', false, 'error', "", ...
        'candidate_file', candidateFile, 'candidate_sha256', "");
    oldConfig = Simulink.fileGenControl('getConfig');
    cleanupConfig = onCleanup(@() Simulink.fileGenControl('set', ...
        'CacheFolder', oldConfig.CacheFolder, ...
        'CodeGenFolder', oldConfig.CodeGenFolder, 'createDir', true)); %#ok<NASGU>
    Simulink.fileGenControl('set', ...
        'CacheFolder', fullfile(destination, 'cache'), ...
        'CodeGenFolder', fullfile(destination, 'codegen'), 'createDir', true);
    try
        copyfile(source, candidateFile);
        assert(hashFile(candidateFile) == hashFile(source));
        load_system(candidateFile);
        cleanupModel = onCleanup(@() closeOwnedModel()); %#ok<NASGU>
        audit = patch_radiator_a1_candidate("candidate", manifest, destination);
        set_param('candidate', 'SimulationCommand', 'update');
        close_system('candidate', 0);
        load_system(candidateFile);
        set_param('candidate', 'SimulationCommand', 'update');
        close_system('candidate', 0);
        row.prepared = true;
        row.candidate_sha256 = audit.candidate_sha256;
    catch exception
        row.error = string(getReport(exception, 'extended', 'hyperlinks', 'off'));
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
    writeJSON(fullfile(destination, 'preparation_status.json'), row);
    summary(end+1) = row; %#ok<AGROW>
end
writeJSON(fullfile(runRoot, 'final_audit', 'preparation_summary.json'), summary);

    function closeOwnedModel()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function value = hashFile(path)
[status, output] = system("shasum -a 256 '" + replace(string(path), "'", "'\''") + "'");
assert(status == 0); parts = split(strtrim(string(output))); value = parts(1);
end

function writeJSON(path, value)
folder = fileparts(path); if ~isfolder(folder), mkdir(folder); end
assert(~isfile(path)); file = fopen(path, 'w'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
```

- [ ] **Step 4: 实现单候选运行器；停止时间只进入 SimulationInput**

Create `tests/run_radiator_a1_candidate.m`:

```matlab
function status = run_radiator_a1_candidate(runRoot, candidateId, outputDir, stopTime)
%RUN_RADIATOR_A1_CANDIDATE Blocking run; catches and records every failure.
if string(runRoot) == "__test_hooks__"
    status = struct('completionGate', @completionGate, ...
        'validateStopTime', @validateStopTime, ...
        'sameCandidateHash', @(a,b) string(a) == string(b));
    return
end
validateStopTime(stopTime);
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot); candidateId = string(candidateId);
outputDir = string(outputDir);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
assert(startsWith(outputDir, runRoot + filesep));
assert(~isfolder(outputDir)); mkdir(outputDir);
candidateFile = fullfile(runRoot, 'candidates_500s', candidateId, 'candidate.slx');
manifestPath = fullfile(runRoot, 'representatives', candidateId, ...
    'parameter_manifest.json');
assert(isfile(candidateFile) && isfile(manifestPath));
candidateHash = hashFile(candidateFile);
preparation = jsondecode(fileread(fullfile(runRoot, 'candidates_500s', ...
    candidateId, 'preparation_status.json')));
assert(preparation.prepared && string(preparation.candidate_sha256) == candidateHash);
protected = readtable(fullfile(repo, 'tmp', ...
    'tp7d213f64_7fad_4bfa_b722_0771b21d9640', 'protected_after.csv'), ...
    TextType='string');
checkProtected(protected);

status = struct('candidate_id', candidateId, 'requested_stop_time_s', stopTime, ...
    'actual_final_time_s', [], 'success', false, 'error_id', "", ...
    'error_message', "", 'candidate_file', candidateFile, ...
    'candidate_sha256_before', candidateHash, 'candidate_sha256_after', "", ...
    'all_logged_values_finite_real', false, 'protected_hashes_unchanged', false, ...
    'paper_reproduced', false, 'formal_promotion', false);
oldPath = path; cleanupPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
sourceDir = fullfile(repo, 'tmp', 'steady53_curves_20260828', 'source_f8bcd83');
addpath(sourceDir, fullfile(sourceDir, 'tests', 'steady53'), fullfile(repo, 'tests'));
oldConfig = Simulink.fileGenControl('getConfig');
cleanupConfig = onCleanup(@() Simulink.fileGenControl('set', ...
    'CacheFolder', oldConfig.CacheFolder, 'CodeGenFolder', oldConfig.CodeGenFolder, ...
    'createDir', true)); %#ok<NASGU>
Simulink.fileGenControl('set', 'CacheFolder', fullfile(outputDir, 'cache'), ...
    'CodeGenFolder', fullfile(outputDir, 'codegen'), 'createDir', true);
oldWarnings = warning; cleanupWarnings = onCleanup(@() warning(oldWarnings)); %#ok<NASGU>
try
    evalin('base', "run('" + replace(fullfile(sourceDir, 'start.m'), "'", "''") + "')");
    reset_steady53_property_warning_state();
    for id = ["HeXe:T_lo", "HeXe:T_hi", ...
            "Lithium_property_simulink:TemperatureBelowRange", ...
            "Lithium_property_simulink:TemperatureAboveRange"]
        warning('error', id);
    end
    load_system(candidateFile);
    cleanupModel = onCleanup(@() closeOwnedModel()); %#ok<NASGU>
    [manifest, states] = steady53_signal_manifest("candidate");
    for k = 1:numel(manifest)
        logPort(manifest(k).block, manifest(k).port, manifest(k).name);
    end
    for k = 1:numel(states)
        logPort(states(k).path, 1, "state_" + compose('%03d', k));
    end
    input = Simulink.SimulationInput('candidate');
    input = input.setModelParameter( ...
        'StopTime', num2str(stopTime, '%.17g'), ...
        'ReturnWorkspaceOutputs', 'on', ...
        'SignalLogging', 'on', 'SignalLoggingName', 'logsout');
    timer = tic;
    output = sim(input);
    elapsed = toc(timer);
    save(fullfile(outputDir, 'raw_output.mat'), 'output', 'manifest', ...
        'states', 'elapsed', '-v7.3');
    exportLogs(output, outputDir);
    status.actual_final_time_s = output.tout(end);
    status.all_logged_values_finite_real = logsAreFiniteReal(output.logsout);
    status.success = completionGate(output.tout, "", ...
        flattenLogs(output.logsout), stopTime);
catch exception
    status.error_id = string(exception.identifier);
    status.error_message = string(getReport(exception, 'extended', 'hyperlinks', 'off'));
end
if bdIsLoaded('candidate'), close_system('candidate', 0); end
status.candidate_sha256_after = hashFile(candidateFile);
status.protected_hashes_unchanged = checkProtected(protected);
status.success = status.success ...
    && status.candidate_sha256_before == status.candidate_sha256_after ...
    && status.protected_hashes_unchanged;
writeJSON(fullfile(outputDir, 'simulation_status.json'), status);
writeJSON(fullfile(outputDir, 'hashes.json'), struct( ...
    'candidate_sha256', status.candidate_sha256_after, ...
    'manifest_sha256', hashFile(manifestPath), ...
    'runner_sha256', hashFile(string(mfilename('fullpath')) + ".m")));

    function closeOwnedModel()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function validateStopTime(value)
if ~any(value == [500 14000])
    error('radiatorA1:UnsupportedStopTime', 'Only 500 or 14000 s is approved.');
end
end

function passed = completionGate(time, errorText, values, requested)
passed = ~isempty(time) && time(end) == requested && strlength(string(errorText)) == 0 ...
    && all(isfinite(values), 'all') && isreal(values);
end

function logPort(block, port, name)
handles = get_param(block, 'PortHandles');
set_param(handles.Outport(port), 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', name);
end

function exportLogs(output, destination)
for k = 1:output.logsout.numElements
    element = output.logsout.getElement(k);
    series = element.Values;
    data = reshape(series.Data, numel(series.Time), []);
    if size(data, 2) == 1
        writetable(table(series.Time(:), data, ...
            'VariableNames', {'time_s','value'}), ...
            fullfile(destination, element.Name + ".csv"));
    end
end
for name = ["P_sw", "WT_sw", "Wc_sw"]
    try
        series = output.get(name);
        writetable(table(series.Time(:), series.Data(:), ...
            'VariableNames', {'time_s','value'}), ...
            fullfile(destination, name + ".csv"));
    catch
    end
end
end

function values = flattenLogs(logs)
values = [];
for k = 1:logs.numElements
    values = [values; logs.getElement(k).Values.Data(:)]; %#ok<AGROW>
end
end

function result = logsAreFiniteReal(logs)
values = flattenLogs(logs);
result = ~isempty(values) && all(isfinite(values)) && isreal(values);
end

function unchanged = checkProtected(tableValue)
unchanged = true;
for k = 1:height(tableValue)
    unchanged = unchanged && hashFile(tableValue.paths(k)) == tableValue.hashes(k);
end
assert(unchanged, 'Protected file changed');
end

function value = hashFile(path)
[status, output] = system("shasum -a 256 '" + replace(string(path), "'", "'\''") + "'");
assert(status == 0); parts = split(strtrim(string(output))); value = parts(1);
end

function writeJSON(path, value)
assert(~isfile(path)); file = fopen(path, 'w'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
```

- [ ] **Step 5: 实现不因单个候选失败而中止整个矩阵的批处理器**

Create `tests/run_radiator_a1_batch.m`:

```matlab
function summary = run_radiator_a1_batch(runRoot, stopTime)
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
if stopTime == 500
    source = jsondecode(fileread(fullfile(runRoot, ...
        'representatives', 'selection.json')));
    ids = string(source.eligible_candidate_ids);
    stage = 'candidates_500s';
elseif stopTime == 14000
    source = jsondecode(fileread(fullfile(runRoot, ...
        'comparisons', 'advance_14000.json')));
    ids = string(source.candidate_ids);
    stage = 'candidates_14000s';
else
    error('radiatorA1:UnsupportedStopTime', 'Only 500 or 14000 s is approved.');
end
summary = struct('candidate_id', {}, 'success', {}, 'output_dir', {});
for k = 1:numel(ids)
    output = fullfile(runRoot, stage, ids(k), 'run');
    try
        status = run_radiator_a1_candidate(runRoot, ids(k), output, stopTime);
    catch exception
        status = struct('success', false, ...
            'error_message', string(getReport(exception, 'extended', 'hyperlinks', 'off')));
        if ~isfolder(output), mkdir(output); end
        writeJSON(fullfile(output, 'batch_failure.json'), status);
    end
    summary(end+1) = struct('candidate_id', ids(k), ...
        'success', logical(status.success), 'output_dir', output); %#ok<AGROW>
end
writeJSON(fullfile(runRoot, 'final_audit', ...
    "batch_" + stopTime + "_summary.json"), summary);
end

function writeJSON(path, value)
folder = fileparts(path); if ~isfolder(folder), mkdir(folder); end
assert(~isfile(path)); file = fopen(path, 'w'); assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
```

- [ ] **Step 6: 运行纯门控测试**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); r=run(testsuite('tests/test_run_radiator_a1_candidate.m')); assertSuccess(r)"
```

Expected: `3 Passed`。本步骤不加载或仿真 SLX。

- [ ] **Step 7: 提交候选准备和运行工装**

```bash
git add -- \
  tests/prepare_radiator_a1_candidates.m \
  tests/run_radiator_a1_candidate.m \
  tests/run_radiator_a1_batch.m \
  tests/test_run_radiator_a1_candidate.m
git diff --cached --check
git commit -m "实现散热器A1阻塞式候选运行器"
```

### Task 6: 独立复算能量、末窗增长和论文差异

**Files:**
- Create: `tests/analyze_radiator_a1_run.py`
- Create: `tests/test_analyze_radiator_a1_run.py`

- [ ] **Step 1: 写入独立能量门、非有限量和持续增长失败测试**

Create `tests/test_analyze_radiator_a1_run.py`:

```python
import math
import unittest

from tests import analyze_radiator_a1_run as analyze


class AnalyzeRadiatorA1RunTests(unittest.TestCase):
    def test_energy_gate_uses_approved_thresholds(self):
        self.assertTrue(analyze.energy_gate(0.999, 999.999, True))
        self.assertFalse(analyze.energy_gate(1.0, 999.0, True))
        self.assertFalse(analyze.energy_gate(0.5, 1000.0, True))
        self.assertFalse(analyze.energy_gate(0.5, 500.0, False))

    def test_persistent_growth_needs_five_consecutive_increasing_ranges(self):
        growing = []
        for amplitude in (1, 2, 4, 8, 16):
            growing.extend([0.0, float(amplitude)])
        self.assertTrue(analyze.persistent_growth(growing))
        bounded = [0.0, 2.0, 0.0, 2.1, 0.0, 1.9, 0.0, 2.0, 0.0, 2.0]
        self.assertFalse(analyze.persistent_growth(bounded))

    def test_finite_real_rejects_nonfinite_and_complex(self):
        self.assertTrue(analyze.all_finite_real([1.0, 2.0]))
        self.assertFalse(analyze.all_finite_real([1.0, math.inf]))
        self.assertFalse(analyze.all_finite_real([1.0, complex(2.0, 1.0)]))

    def test_paper_target_is_not_reused_as_input_credit(self):
        comparison = analyze.paper_comparison({
            "cooler_cold_inlet_T": 360.10,
            "cooler_cold_outlet_T": 609.58,
            "reactor_inlet_T": 1443.27,
        })
        self.assertEqual(comparison["cooler_cold_inlet_T"]["independent_validation"], False)
        self.assertEqual(comparison["cooler_cold_outlet_T"]["independent_validation"], False)
        self.assertEqual(comparison["reactor_inlet_T"]["independent_validation"], True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认分析器缺失**

Run:

```bash
python3 -m unittest -v tests/test_analyze_radiator_a1_run.py
```

Expected: `ImportError`。

- [ ] **Step 3: 实现不依赖候选内部残差信号的独立分析器**

Create `tests/analyze_radiator_a1_run.py`:

```python
#!/usr/bin/env python3
"""Independent A1 run gates; reads CSV/JSON only and never loads an SLX."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from tests import radiator_candidate_math as base_math


ROOT = Path(__file__).resolve().parents[1]
PAPER_TARGETS = {
    "reactor_inlet_T": (1443.27, True, "thesis_table_5_2"),
    "reactor_outlet_T": (1600.00, True, "thesis_table_5_2"),
    "turbine_inlet_T": (1522.96, True, "thesis_table_5_2"),
    "turbine_outlet_T": (1162.00, True, "thesis_table_5_2"),
    "compressor_inlet_T": (405.16, True, "thesis_table_5_2"),
    "compressor_outlet_T": (601.90, True, "thesis_table_5_2"),
    "recuperator_hot_outlet_T": (663.63, True, "thesis_table_5_2"),
    "recuperator_cold_outlet_T": (1100.91, True, "thesis_table_5_2"),
    "cooler_cold_inlet_T": (360.10, False, "used_in_candidate_conditioning"),
    "cooler_cold_outlet_T": (609.58, False, "used_in_candidate_conditioning"),
    "P_sw": (2_664_000.0, True, "thesis_table_5_2_or_section_5_3_1"),
    "WT_sw": (2_252_200.0, True, "thesis_table_5_2"),
    "Wc_sw": (1_231_600.0, True, "thesis_table_5_2"),
}
RADIATOR_SCAN = ROOT / "tmp/steady53_curves_20260828/radiator_scan_points.csv"


def all_finite_real(values) -> bool:
    return all(not isinstance(value, complex) and math.isfinite(float(value))
               for value in values)


def persistent_growth(values) -> bool:
    values = [float(value) for value in values]
    if len(values) < 10 or not all_finite_real(values):
        return False
    bins = [values[round(i * len(values) / 5):round((i + 1) * len(values) / 5)]
            for i in range(5)]
    ranges = [max(chunk) - min(chunk) for chunk in bins if chunk]
    scale = max(1.0, max(abs(value) for value in values))
    return (len(ranges) == 5 and ranges[-1] > 1e-6 * scale
            and all(right > 1.05 * left
                    for left, right in zip(ranges, ranges[1:])))


def energy_gate(enthalpy_convection_residual_W: float,
                loop_residual_W: float, signs_consistent: bool) -> bool:
    return (abs(enthalpy_convection_residual_W) < 1.0
            and abs(loop_residual_W) < 1000.0
            and signs_consistent)


def read_series(path: Path) -> tuple[list[float], list[float]]:
    with path.open() as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError(f"empty series: {path}")
    time = [float(row["time_s"]) for row in rows]
    values = [float(row["value"]) for row in rows]
    if not all_finite_real(time + values):
        raise ValueError(f"nonfinite series: {path}")
    if any(right < left for left, right in zip(time, time[1:])):
        raise ValueError(f"nonmonotone time: {path}")
    return time, values


def paper_comparison(final_values: dict[str, float]) -> dict:
    result = {}
    for name, value in final_values.items():
        if name not in PAPER_TARGETS:
            continue
        target, independent, source = PAPER_TARGETS[name]
        result[name] = {
            "value": value,
            "paper_target": target,
            "relative_error": (value - target) / target,
            "independent_validation": independent,
            "target_source": source,
        }
    return result


def interpolate(time: list[float], values: list[float], target: float) -> float:
    if not (time[0] <= target <= time[-1]):
        raise ValueError("target is outside recorded time")
    for index in range(1, len(time)):
        if time[index] >= target:
            left_t, right_t = time[index - 1], time[index]
            if right_t == left_t:
                return values[index]
            weight = (target - left_t) / (right_t - left_t)
            return values[index - 1] + weight * (values[index] - values[index - 1])
    return values[-1]


def curve_comparison(series: dict[str, tuple[list[float], list[float]]]) -> dict:
    with RADIATOR_SCAN.open() as handle:
        points = list(csv.DictReader(handle))
    times = [float(row["time_s"]) for row in points]
    observed_wall = [float(row["wall_K"]) for row in points]
    observed_outlet = [float(row["outlet_K"]) for row in points]
    wall = [interpolate(*series["state_040"], target) for target in times]
    outlet = [interpolate(*series["cooler_cold_inlet_T"], target) for target in times]
    rmse = lambda left, right: math.sqrt(sum((a-b)**2 for a,b in zip(left,right))/len(left))
    return {
        "figure_5_18d_radiator_wall_rmse_K": rmse(wall, observed_wall),
        "figure_5_18d_radiator_outlet_rmse_K": rmse(outlet, observed_outlet),
        "scan_reading_allowance_K": 3.0,
        "scan_reading_allowance_s": 2.0,
        "comparison_identity": "comparison_only_due_to_whole_system_context_and_prior_conditioning",
        "independent_validation": False,
    }


def trajectory_metrics(time: list[float], values: list[float]) -> dict:
    final = values[-1]
    band = 0.01 * max(abs(final), 1.0)
    last_outside = max((index for index, value in enumerate(values)
                        if abs(value - final) > band), default=-1)
    settling = 0.0 if last_outside < 0 else (
        time[last_outside + 1] if last_outside + 1 < len(time) else None)
    return {"initial": values[0], "final": final, "minimum": min(values),
            "maximum": max(values), "settling_time_1pct_s": settling,
            "direction": "rise" if final > values[0] else
                         "fall" if final < values[0] else "flat"}


def analyze_run(run_root: Path, candidate_id: str, stop_time: int) -> dict:
    run_root = run_root.resolve()
    if not run_root.is_relative_to(ROOT / "tmp"):
        raise ValueError("run root must be below tmp/")
    stage = "candidates_500s" if stop_time == 500 else "candidates_14000s"
    run_dir = run_root / stage / candidate_id / "run"
    status = json.loads((run_dir / "simulation_status.json").read_text())
    manifest = json.loads((run_root / "representatives" / candidate_id
                           / "parameter_manifest.json").read_text())
    result = {
        "candidate_id": candidate_id,
        "stop_time_s": stop_time,
        "simulation_success": bool(status["success"]),
        "actual_final_time_s": status.get("actual_final_time_s"),
        "energy_gate_pass": False,
        "growth_gate_pass": False,
        "simulation_gate_pass": False,
        "rejection_reasons": [],
        "paper_reproduced": False,
        "formal_promotion": False,
    }
    if not status["success"] or status.get("actual_final_time_s") != stop_time:
        result["rejection_reasons"].append("simulation_incomplete_or_failed")
        return result
    names = [
        "cooler_cold_outlet_T", "cooler_cold_inlet_T", "state_040",
        "state_012", "state_016", "state_017", "state_021",
    ]
    series = {name: read_series(run_dir / f"{name}.csv") for name in names}
    if any(time[-1] != stop_time for time, _ in series.values()):
        result["rejection_reasons"].append("logged_series_does_not_reach_stop")
        return result
    tin = series["cooler_cold_outlet_T"][1][-1]
    tout = series["cooler_cold_inlet_T"][1][-1]
    wall = series["state_040"][1][-1]
    m_dot = float(manifest["m_dot_NaK_kg_s"])
    h = float(manifest["h_W_m2K"])
    area = float(manifest["A_exchange_m2"])
    epsilon = float(manifest["epsilon"])
    sink = float(manifest["T_sink_K"])
    q_enthalpy = m_dot * (base_math.nak_enthalpy_J_kg(tin)
                          - base_math.nak_enthalpy_J_kg(tout))
    q_convection = h * area * (0.8 * tin + 0.2 * tout - wall)
    q_radiation = epsilon * 5.67e-8 * area * (wall**4 - sink**4)
    q_precooler = 0.0
    for cold_name, wall_name in (("state_012", "state_016"),
                                 ("state_017", "state_021")):
        cold = series[cold_name][1][-1]
        region_wall = series[wall_name][1][-1]
        q_precooler += 94550.0 * 12.256 * (region_wall - cold)
    enthalpy_convection = q_enthalpy - q_convection
    loop_residual = q_precooler - q_enthalpy
    signs = (q_enthalpy > 0.0 and q_convection > 0.0 and q_radiation > 0.0)
    result["energy"] = {
        "q_enthalpy_W": q_enthalpy,
        "q_convection_W": q_convection,
        "q_radiation_W": q_radiation,
        "q_precooler_W": q_precooler,
        "enthalpy_minus_convection_W": enthalpy_convection,
        "precooler_minus_enthalpy_W": loop_residual,
        "signs_consistent": signs,
        "precooler_constants_source": "read-only source snapshot inventory",
    }
    result["energy_gate_pass"] = energy_gate(enthalpy_convection, loop_residual, signs)
    growing = {name: persistent_growth(values[-max(10, len(values)//5):])
               for name, (_, values) in series.items()}
    result["persistent_growth"] = growing
    result["growth_gate_pass"] = not any(growing.values())
    if not result["energy_gate_pass"]:
        result["rejection_reasons"].append("energy_gate_failed")
    if not result["growth_gate_pass"]:
        result["rejection_reasons"].append("persistent_end_window_growth")
    final_values = {}
    for name in PAPER_TARGETS:
        path = run_dir / f"{name}.csv"
        if path.is_file():
            final_values[name] = read_series(path)[1][-1]
    result["paper_comparison"] = paper_comparison(final_values)
    result["curve_comparison"] = curve_comparison(series)
    result["curve_comparison"]["figure_5_19_power_shape"] = {
        name: trajectory_metrics(*read_series(run_dir / f"{name}.csv"))
        for name in ("P_sw", "WT_sw", "Wc_sw")
        if (run_dir / f"{name}.csv").is_file()
    }
    result["simulation_gate_pass"] = (
        result["simulation_success"] and result["energy_gate_pass"]
        and result["growth_gate_pass"]
        and bool(status["protected_hashes_unchanged"])
        and status["candidate_sha256_before"] == status["candidate_sha256_after"]
    )
    return result


def write_analysis(run_root: Path, candidate_id: str, stop_time: int) -> dict:
    result = analyze_run(run_root, candidate_id, stop_time)
    stage = "candidates_500s" if stop_time == 500 else "candidates_14000s"
    run_dir = run_root / stage / candidate_id / "run"
    (run_dir / "energy_balance.json").write_text(json.dumps(
        {k: result[k] for k in result if k not in ("paper_comparison",)},
        ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    (run_dir / "paper_comparison.json").write_text(json.dumps(
        result.get("paper_comparison", {}), ensure_ascii=False,
        indent=2, sort_keys=True) + "\n")
    (run_dir / "gate.json").write_text(json.dumps(
        result, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root", type=Path)
    parser.add_argument("candidate_id")
    parser.add_argument("stop_time", type=int, choices=(500, 14000))
    args = parser.parse_args()
    result = write_analysis(args.run_root.resolve(), args.candidate_id, args.stop_time)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 运行分析器测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_analyze_radiator_a1_run.py
```

Expected: `Ran 4 tests`、`OK`。

- [ ] **Step 5: 提交独立分析器**

```bash
git add -- tests/analyze_radiator_a1_run.py tests/test_analyze_radiator_a1_run.py
git diff --cached --check
git commit -m "实现散热器A1独立能量与推进门"
```

### Task 7: 用 TDD 实现批次推进、来源排序和最终报告

**Files:**
- Create: `tests/summarize_radiator_a1.py`
- Create: `tests/test_summarize_radiator_a1.py`

- [ ] **Step 1: 写入零候选、多候选非唯一性和禁止越界声明测试**

Create `tests/test_summarize_radiator_a1.py`:

```python
import unittest

from tests import summarize_radiator_a1 as summary


class SummarizeRadiatorA1Tests(unittest.TestCase):
    def test_zero_pass_does_not_expand_envelope(self):
        result = summary.summarize_records([], 500)
        self.assertEqual(result["advance_candidate_ids"], [])
        self.assertFalse(result["expand_envelope"])
        self.assertFalse(result["paper_reproduced"])

    def test_multiple_passes_preserve_nonuniqueness(self):
        records = [
            {"candidate_id": "projected", "simulation_gate_pass": True,
             "technology_maturity": "projected", "paper_error": 0.001},
            {"candidate_id": "tested", "simulation_gate_pass": True,
             "technology_maturity": "tested", "paper_error": 0.05},
        ]
        result = summary.summarize_records(records, 14000)
        self.assertEqual(result["ranked_candidate_ids"], ["tested", "projected"])
        self.assertEqual(result["identifiability"], "multiple_conditionally_feasible_packages")
        self.assertIsNone(result["selected_best_candidate"])

    def test_failed_candidate_never_advances(self):
        records = [
            {"candidate_id": "pass", "simulation_gate_pass": True,
             "technology_maturity": "tested", "paper_error": 0.2},
            {"candidate_id": "fail", "simulation_gate_pass": False,
             "technology_maturity": "tested", "paper_error": 0.0},
        ]
        result = summary.summarize_records(records, 500)
        self.assertEqual(result["advance_candidate_ids"], ["pass"])

    def test_report_language_cannot_claim_reproduction(self):
        report = summary.render_report(summary.summarize_records([], 14000))
        self.assertNotIn("paper_reproduced=true", report)
        self.assertIn("未晋升正式模型", report)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行测试确认汇总器缺失**

Run:

```bash
python3 -m unittest -v tests/test_summarize_radiator_a1.py
```

Expected: `ImportError`。

- [ ] **Step 3: 实现来源等级优先、无自动最佳候选的汇总器**

Create `tests/summarize_radiator_a1.py`:

```python
#!/usr/bin/env python3
"""Summarize A1 gates without fitting, replacement, or formal promotion."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

from tests import analyze_radiator_a1_run as analyze


ROOT = Path(__file__).resolve().parents[1]
MATURITY_RANK = {"tested": 0, "built_not_tested": 1, "projected": 2,
                 "sensitivity_only": 3}


def _metric(value) -> float:
    return float("inf") if value is None else abs(float(value))


def summarize_records(records: list[dict], stage: int) -> dict:
    passed = [row for row in records if row.get("simulation_gate_pass")]
    ranked = sorted(passed, key=lambda row: (
        MATURITY_RANK.get(row.get("technology_maturity"), 99),
        _metric(row.get("energy_residual")),
        _metric(row.get("paper_error")),
        row["candidate_id"],
    ))
    return {
        "stage_s": stage,
        "record_count": len(records),
        "passed_count": len(passed),
        "advance_candidate_ids": [row["candidate_id"] for row in passed]
            if stage == 500 else [],
        "ranked_candidate_ids": [row["candidate_id"] for row in ranked],
        "selected_best_candidate": None,
        "identifiability": (
            "no_feasible_candidate_in_approved_envelope" if not passed
            else "one_conditionally_feasible_package" if len(passed) == 1
            else "multiple_conditionally_feasible_packages"
        ),
        "expand_envelope": False,
        "paper_reproduced": False,
        "formal_promotion": False,
    }


def _records(run_root: Path, stage: int) -> list[dict]:
    matrix = run_root / "representatives/representative_matrix.csv"
    with matrix.open() as handle:
        representatives = {row["candidate_id"]: row for row in csv.DictReader(handle)}
    selection = json.loads((run_root / "representatives/selection.json").read_text())
    ids = selection["eligible_candidate_ids"] if stage == 500 else json.loads(
        (run_root / "comparisons/advance_14000.json").read_text())["candidate_ids"]
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
                gate = {"candidate_id": candidate_id, "simulation_gate_pass": False,
                        "rejection_reasons": [
                            "analysis_failed: " + type(exception).__name__ + ": " + str(exception)
                        ]}
        rep = representatives[candidate_id]
        errors = [abs(value["relative_error"])
                  for value in gate.get("paper_comparison", {}).values()
                  if value["independent_validation"]]
        energy = gate.get("energy", {})
        rows.append({
            **gate,
            "technology_maturity": rep["technology_maturity"],
            "paper_error": max(errors) if errors else None,
            "energy_residual": abs(float(energy["precooler_minus_enthalpy_W"]))
                if "precooler_minus_enthalpy_W" in energy else None,
        })
    return rows


def render_report(summary: dict, records: list[dict] | None = None) -> str:
    records = records or []
    candidate_lines = []
    for row in records:
        candidate_lines.extend([
            f"### `{row['candidate_id']}`",
            "",
            f"- 数值完整性/推进门：`{row.get('simulation_gate_pass', False)}`",
            f"- 能量门：`{row.get('energy_gate_pass', False)}`；"
            f"整环残差 `{row.get('energy_residual')}` W",
            f"- 论文独立指标最大相对误差：`{row.get('paper_error')}`",
            f"- 来源成熟度：`{row.get('technology_maturity')}`",
            f"- 失败原因：`{row.get('rejection_reasons', [])}`",
            "",
        ])
    candidates = "\n".join(candidate_lines) or "- 无进入本阶段的候选"
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

{chr(10).join('- `' + value + '`' for value in summary['ranked_candidate_ids']) or '- 无'}

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
        (comparisons / "advance_14000.json").write_text(json.dumps({
            "candidate_ids": summary["advance_candidate_ids"],
            "source_stage": 500,
            "replacement_allowed": False,
            "expand_envelope": False,
        }, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    payload = {"summary": summary, "records": records}
    (final / f"summary_{stage}.json").write_text(json.dumps(
        payload, ensure_ascii=False, indent=2, sort_keys=True,
        allow_nan=False) + "\n")
    if stage == 14000:
        (final / "report.md").write_text(render_report(summary, records))
    return summary


def publish_report(run_root: Path, destination: Path) -> None:
    expected = ROOT / "docs/radiator_A1_results_20260830.md"
    if destination.resolve() != expected.resolve() or destination.exists():
        raise ValueError("destination must be the new approved A1 report path")
    payload = json.loads((run_root / "final_audit/summary_14000.json").read_text())
    destination.write_text(render_report(payload["summary"], payload["records"]))


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
```

- [ ] **Step 4: 运行汇总器测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_summarize_radiator_a1.py
```

Expected: `Ran 4 tests`、`OK`。

- [ ] **Step 5: 提交汇总器**

```bash
git add -- tests/summarize_radiator_a1.py tests/test_summarize_radiator_a1.py
git diff --cached --check
git commit -m "汇总散热器A1来源排序与非唯一性"
```

### Task 8: 建立完整自动合同并生成一次全新离线运行目录

**Files:**
- Create: `tests/test_radiator_a1_end_to_end_contract.py`
- Runtime create: `tmp/radiator_A1_20260830_A1/`

- [ ] **Step 1: 写入规格 20 项自动合同的整体验证测试**

Create `tests/test_radiator_a1_end_to_end_contract.py`:

```python
import csv
import json
from pathlib import Path
import tempfile
import unittest

from tests import build_radiator_a1_screen as builder
from tests import radiator_a1_contract as contract


ROOT = Path(__file__).resolve().parents[1]


class RadiatorA1EndToEndContractTests(unittest.TestCase):
    def test_offline_schema_has_units_sources_unique_ids_and_no_replacement(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "tmp") as folder:
            output = Path(folder)
            builder.write_screen(output)
            units = json.loads((output / "source_contract/unit_contract.json").read_text())
            self.assertTrue(units)
            self.assertTrue(all(units.values()))
            with (output / "offline_screen/offline_96.csv").open() as handle:
                rows = list(csv.DictReader(handle))
            self.assertEqual(len(rows), 96)
            self.assertEqual(len({row["row_id"] for row in rows}), 96)
            self.assertTrue(all(row["evidence_status_per_input"] for row in rows))
            selection = json.loads((output / "representatives/selection.json").read_text())
            self.assertFalse(selection["replacement_allowed"])
            self.assertFalse(selection["paper_reproduced"])

    def test_protected_contract_covers_formal_model_mat_and_properties(self):
        evidence = contract.verify_source_contract()
        self.assertEqual(evidence["protected_count"], 34)
        with contract.PROTECTED.open() as handle:
            paths = {Path(row["paths"]).name for row in csv.DictReader(handle)}
        self.assertIn("final_steady_24a.slx", paths)
        self.assertIn("HeXe_property_simulink.m", paths)
        self.assertIn("Lithium_property_simulink.m", paths)
        self.assertTrue(any(name.endswith(".mat") for name in paths))

    def test_python_execution_path_cannot_load_or_write_slx(self):
        paths = [
            ROOT / "tests/radiator_a1_contract.py",
            ROOT / "tests/radiator_a1_math.py",
            ROOT / "tests/build_radiator_a1_screen.py",
            ROOT / "tests/analyze_radiator_a1_run.py",
            ROOT / "tests/summarize_radiator_a1.py",
        ]
        combined = "\n".join(path.read_text() for path in paths)
        for forbidden in ("load_system", "save_system", "matlab.engine",
                          "ZipFile", "writestr("):
            self.assertNotIn(forbidden, combined)

    def test_matlab_write_path_uses_official_api_and_runtime_stop_time(self):
        patch = (ROOT / "tests/patch_radiator_a1_candidate.m").read_text()
        runner = (ROOT / "tests/run_radiator_a1_candidate.m").read_text()
        self.assertIn("set_param", patch)
        self.assertIn("save_system", patch)
        self.assertIn("Simulink.SimulationInput", runner)
        self.assertIn("setModelParameter", runner)
        self.assertNotIn("save_system", runner)
        self.assertNotIn("unzip", patch + runner)

    def test_no_runtime_code_can_promote_or_expand(self):
        paths = [ROOT / "tests/build_radiator_a1_screen.py",
                 ROOT / "tests/analyze_radiator_a1_run.py",
                 ROOT / "tests/summarize_radiator_a1.py"]
        combined = "\n".join(path.read_text() for path in paths)
        self.assertIn('"paper_reproduced": False', combined)
        self.assertIn('"formal_promotion": False', combined)
        self.assertIn('"expand_envelope": False', combined)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: 运行全部 Python 自动测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_candidate_math.py \
  tests/test_audit_radiator_candidate_family.py \
  tests/test_radiator_a1_contract.py \
  tests/test_radiator_a1_math.py \
  tests/test_build_radiator_a1_screen.py \
  tests/test_analyze_radiator_a1_run.py \
  tests/test_summarize_radiator_a1.py \
  tests/test_radiator_a1_end_to_end_contract.py
```

Expected: 所有测试 `OK`，零 failure、零 error、零 `ResourceWarning`。

- [ ] **Step 3: 运行 MATLAB 结构补丁和纯门控测试；仍不仿真**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); s=testsuite({'tests/test_patch_radiator_a1_candidate.m','tests/test_run_radiator_a1_candidate.m'}); r=run(s); assertSuccess(r)"
```

Expected: 全部 PASS。补丁测试只处理自己创建并清理的 `tmp` 副本，不执行 `sim`。

- [ ] **Step 4: 提交端到端合同测试**

```bash
git add -- tests/test_radiator_a1_end_to_end_contract.py
git diff --cached --check
git commit -m "覆盖散热器A1端到端合同"
```

- [ ] **Step 5: 创建唯一运行根并执行 96 行离线筛选**

Run:

```bash
run_root="$PWD/tmp/radiator_A1_20260830_A1"
test ! -e "$run_root"
mkdir "$run_root"
python3 tests/build_radiator_a1_screen.py "$run_root"
```

Expected:

```text
RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD
```

- [ ] **Step 6: 机器复核 96 行、12 个固定角色和实际合格数量**

Run:

```bash
python3 -c "import csv,json,pathlib; r=pathlib.Path('tmp/radiator_A1_20260830_A1'); rows=list(csv.DictReader((r/'offline_screen/offline_96.csv').open())); reps=list(csv.DictReader((r/'representatives/representative_matrix.csv').open())); s=json.loads((r/'representatives/selection.json').read_text()); assert len(rows)==96 and len({x['row_id'] for x in rows})==96; assert len(reps)==12 and len({x['candidate_id'] for x in reps})==12; assert 0<=s['eligible_count']<=12 and not s['replacement_allowed']; print({'rows':len(rows),'fixed_roles':len(reps),'eligible':s['eligible_count']})"
```

Expected: 打印 `rows: 96`、`fixed_roles: 12` 和 `0–12` 的实际 `eligible`。不得因合格数不足 12 修改输入。

- [ ] **Step 7: 生成、重开并编译所有离线合格候选；仍不仿真**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); s=prepare_radiator_a1_candidates(fullfile(pwd,'tmp','radiator_A1_20260830_A1')); assert(all([s.prepared] | strlength([s.error])>0))"
```

Expected: 每个合格候选都有 `preparation_status.json`。准备失败者保留错误，不修改其他参数重试。

- [ ] **Step 8: 人工检查候选补丁白名单后进入仿真**

Run:

```bash
python3 -c "import json,pathlib; r=pathlib.Path('tmp/radiator_A1_20260830_A1/candidates_500s'); rows=[]; [rows.append(json.loads((p/'preparation_status.json').read_text())) for p in sorted(r.iterdir())]; assert all(x['prepared'] or x['error'] for x in rows); assert all(not x['prepared'] or len(json.loads((pathlib.Path(x['candidate_file']).parent/'patch_manifest.json').read_text())['changed_parameter_paths'])==8 for x in rows); print({'prepared':sum(x['prepared'] for x in rows),'failed':sum(not x['prepared'] for x in rows)})"
```

Expected: 每个成功候选恰有 8 个白名单变化路径；任何额外差异都必须停止，不能开始 500 s。

### Task 9: 对所有已准备候选执行 500 s 阻塞式筛查

**Files:**
- Runtime modify only: `tmp/radiator_A1_20260830_A1/candidates_500s/*/run/`
- Runtime create: `tmp/radiator_A1_20260830_A1/comparisons/advance_14000.json`

- [ ] **Step 1: 顺序运行全部离线合格候选 500 s**

Run in a PTY-capable shell and poll without restarting MATLAB:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); run_radiator_a1_batch(fullfile(pwd,'tmp','radiator_A1_20260830_A1'),500)"
```

Expected: 命令最终返回；单个候选失败被写入其运行目录，不中断其余候选。执行期间每 60 秒以内向用户报告已完成数和当前候选，不宣称通过。

- [ ] **Step 2: 独立复算全部 500 s 结果并生成推进清单**

Run:

```bash
python3 tests/summarize_radiator_a1.py \
  tmp/radiator_A1_20260830_A1 500
```

Expected: 为每个候选生成或读取 `gate.json`；生成 `comparisons/advance_14000.json`。推进清单只包含 `simulation_gate_pass=true` 的候选。

- [ ] **Step 3: 核验短算例数量闭合和失败证据完整**

Run:

```bash
python3 -c "import json,pathlib; r=pathlib.Path('tmp/radiator_A1_20260830_A1'); s=json.loads((r/'representatives/selection.json').read_text()); b=json.loads((r/'final_audit/batch_500_summary.json').read_text()); f=json.loads((r/'final_audit/summary_500.json').read_text()); a=json.loads((r/'comparisons/advance_14000.json').read_text()); assert len(b)==s['eligible_count']; assert f['summary']['record_count']==s['eligible_count']; assert set(a['candidate_ids'])==set(f['summary']['advance_candidate_ids']); assert not a['expand_envelope']; print({'eligible':s['eligible_count'],'passed_500':len(a['candidate_ids'])})"
```

Expected: 合格、运行、分析和推进数量闭合。零通过是合法结果。

- [ ] **Step 4: 处理共同工装错误或真实候选失败**

如果多个候选因同一个日志拼写、输出路径或分析器异常失败：

1. 把该问题分类为共同工装错误；
2. 为错误写失败测试；
3. 修复共同工装；
4. 删除的只能是本轮工装错误生成的精确 `run/` 子目录，必须先保存错误报告；
5. 对全部受影响候选从头重跑，不能只补跑有利候选；
6. 形成独立提交 `修复散热器A1共同运行工装`。

如果失败来自模型、断言、能量门、物性域或持续增长，则不修改候选，保留失败并继续汇总。

### Task 10: 仅对推进清单中的同一候选执行 14000 s

**Files:**
- Runtime create: `tmp/radiator_A1_20260830_A1/candidates_14000s/*/run/`
- Runtime create: `tmp/radiator_A1_20260830_A1/final_audit/summary_14000.json`

- [ ] **Step 1: 在运行前核验推进候选的模型哈希未变化**

Run:

```bash
python3 -c "import json,hashlib,pathlib; r=pathlib.Path('tmp/radiator_A1_20260830_A1'); ids=json.loads((r/'comparisons/advance_14000.json').read_text())['candidate_ids']; assert all(hashlib.sha256((r/'candidates_500s'/i/'candidate.slx').read_bytes()).hexdigest()==json.loads((r/'candidates_500s'/i/'preparation_status.json').read_text())['candidate_sha256'] for i in ids); print({'advance_count':len(ids),'same_candidate_hash':True})"
```

Expected: `same_candidate_hash: True`。若推进数为零，跳过 MATLAB 长算例命令，直接执行 Step 3 的零候选汇总。

- [ ] **Step 2: 顺序运行推进候选 14000 s**

Run only when `advance_count > 0`:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); run_radiator_a1_batch(fullfile(pwd,'tmp','radiator_A1_20260830_A1'),14000)"
```

Expected: 只运行 `advance_14000.json` 中的候选；每个模型文件仍位于其实际候选 ID 对应的 `candidates_500s/候选ID/candidate.slx`，长算例目录不包含另一份 SLX。

- [ ] **Step 3: 独立分析并汇总 14000 s 结果**

Run:

```bash
python3 tests/summarize_radiator_a1.py \
  tmp/radiator_A1_20260830_A1 14000
```

Expected: 生成 `final_audit/summary_14000.json` 和 `final_audit/report.md`。多个通过者保留非唯一性；零通过者报告批准包络内无可行候选。

- [ ] **Step 4: 核验长短运行引用同一候选 SHA256**

Run:

```bash
python3 -c "import json,pathlib; r=pathlib.Path('tmp/radiator_A1_20260830_A1'); ids=json.loads((r/'comparisons/advance_14000.json').read_text())['candidate_ids']; assert all(json.loads((r/'candidates_500s'/i/'run/simulation_status.json').read_text())['candidate_sha256_after']==json.loads((r/'candidates_14000s'/i/'run/simulation_status.json').read_text())['candidate_sha256_after'] for i in ids if (r/'candidates_14000s'/i/'run/simulation_status.json').is_file()); print({'checked_candidates':len(ids)})"
```

Expected: 所有实际长算例均与短算例使用同一 SHA256；不得出现第二候选模型。

### Task 11: 发布可审计报告并执行最终边界核验

**Files:**
- Create: `docs/radiator_A1_results_20260830.md`
- Read: `tmp/radiator_A1_20260830_A1/final_audit/summary_500.json`
- Read: `tmp/radiator_A1_20260830_A1/final_audit/summary_14000.json`
- Read: `tmp/radiator_A1_20260830_A1/final_audit/report.md`

- [ ] **Step 1: 从机器汇总发布固定边界的项目报告**

Run:

```bash
python3 tests/summarize_radiator_a1.py \
  tmp/radiator_A1_20260830_A1 14000 \
  --publish docs/radiator_A1_results_20260830.md
```

Expected: 新建 `docs/radiator_A1_results_20260830.md`；若文件已存在则拒绝覆盖。

- [ ] **Step 2: 检查报告没有越权完成声明**

Run:

```bash
! rg -n 'paper_reproduced=true|论文模型已完整复现|徐驰原散热器参数已恢复|正式稳态模型已修复' \
  docs/radiator_A1_results_20260830.md \
  tmp/radiator_A1_20260830_A1/final_audit/report.md
rg -n '未晋升正式模型|不宣称第 5\.3\.1 节或第 5\.4 节已经复现' \
  docs/radiator_A1_results_20260830.md
```

Expected: 第一条命令无匹配且返回成功；第二条找到两项边界声明。

- [ ] **Step 3: 重新运行所有自动测试**

Run:

```bash
python3 -W error::ResourceWarning -m unittest -v \
  tests/test_radiator_candidate_math.py \
  tests/test_audit_radiator_candidate_family.py \
  tests/test_radiator_a1_contract.py \
  tests/test_radiator_a1_math.py \
  tests/test_build_radiator_a1_screen.py \
  tests/test_analyze_radiator_a1_run.py \
  tests/test_summarize_radiator_a1.py \
  tests/test_radiator_a1_end_to_end_contract.py
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests'); s=testsuite({'tests/test_patch_radiator_a1_candidate.m','tests/test_run_radiator_a1_candidate.m'}); r=run(s); assertSuccess(r)"
```

Expected: Python 全部 `OK`；MATLAB 全部 PASS。

- [ ] **Step 4: 核验正式和受保护文件哈希仍一致**

Run:

```bash
python3 -c "from tests.radiator_a1_contract import verify_source_contract; r=verify_source_contract(); assert r['protected_count']==34 and not r['paper_reproduced']; print('PROTECTED_34_UNCHANGED')"
shasum -a 256 \
  tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx
```

Expected:

```text
PROTECTED_34_UNCHANGED
0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391
```

- [ ] **Step 5: 暂存时只包含 A1 代码、测试和结果报告**

Run:

```bash
git add -- \
  tests/radiator_a1_contract.py \
  tests/test_radiator_a1_contract.py \
  tests/radiator_a1_math.py \
  tests/test_radiator_a1_math.py \
  tests/build_radiator_a1_screen.py \
  tests/test_build_radiator_a1_screen.py \
  tests/radiator_a1_model_inventory.m \
  tests/patch_radiator_a1_candidate.m \
  tests/test_patch_radiator_a1_candidate.m \
  tests/prepare_radiator_a1_candidates.m \
  tests/run_radiator_a1_candidate.m \
  tests/run_radiator_a1_batch.m \
  tests/test_run_radiator_a1_candidate.m \
  tests/analyze_radiator_a1_run.py \
  tests/test_analyze_radiator_a1_run.py \
  tests/summarize_radiator_a1.py \
  tests/test_summarize_radiator_a1.py \
  tests/test_radiator_a1_end_to_end_contract.py \
  docs/radiator_A1_results_20260830.md
git diff --cached --check
git diff --cached --name-only
```

Expected: 不包含任何 SLX、MAT、物性函数、现有未跟踪诊断文件或 `tmp/` 输出。由于前面任务采用频繁提交，正常情况下本步骤只剩结果报告；若代码已提交，`git add` 不会重复产生差异。

- [ ] **Step 6: 提交最终 A1 结果报告**

```bash
git commit -m "记录散热器A1分阶段候选结果"
```

- [ ] **Step 7: 提交后最终核验**

Run:

```bash
git diff --check HEAD^
git show --stat --name-status --oneline HEAD
git status --short --branch
```

Expected: 最新提交不含正式模型或正式数据文件；现有未跟踪历史文件仍保持未跟踪且未被删除。

## 规格 20 项测试与任务映射

| 规格测试 | 实施任务 |
|---|---|
| 1. 参数包络边界 | Task 1、2 |
| 2. 96 行数量和唯一 ID | Task 2、8 |
| 3. 单位与来源字段非空 | Task 3、8 |
| 4. 12 个代表包确定性 | Task 3 |
| 5. 代表包无重复 | Task 3、8 |
| 6. 硬淘汰规则 | Task 2 |
| 7. 候选补丁白名单 | Task 4、8 |
| 8. 不可变基线哈希 | Task 1、11 |
| 9. 正式模型未变 | Task 1、5、11 |
| 10. 正式 MAT 未变 | Task 1、5、11 |
| 11. 正式物性函数未变 | Task 1、5、11 |
| 12. 500 s 推进门 | Task 5、6、9 |
| 13. 14000 s 推进门 | Task 5、7、10 |
| 14. 实际终止时间 | Task 5、6 |
| 15. 非有限/复数检测 | Task 5、6 |
| 16. 能量闭合独立复算 | Task 6 |
| 17. 论文目标与输入隔离 | Task 6 |
| 18. 来源等级优先排序 | Task 7 |
| 19. 零候选不扩大包络 | Task 7、9、10 |
| 20. 禁止 `paper_reproduced=true` | Task 1、3、6、7、8、11 |

## Wolfram 第二实现验证门

本计划的 96 行求根、焓积分、辐射平衡和残差计算默认由项目 Python/MATLAB 两条独立路径复算，不自动调用 Wolfram。只有出现以下任一情况才允许新增 Wolfram 核验任务：

- 条件方程出现多根或物理根唯一性存疑；
- Python 与 MATLAB 的积分/求根结果超出已定义数值容差；
- 某一数值将直接决定正式模型是否修改；
- 某一结果将进入关键研究结论而现有两个实现不能充分交叉验证。

调用前必须固定输入、单位、假设和预期输出；调用后保存查询、输出和与项目实现的差值。Wolfram 只能是独立计算验证，不能升级为论文来源，也不能用来扩大参数包络或替代人工晋升门。

## 停止条件

执行过程中遇到以下任一情况必须停止当前阶段并保留证据：

- 不可变基线或 34 个受保护文件任一哈希变化；
- 补丁路径、SID、原值或结构白名单不一致；
- 需要改变求解器、容差、初值、物性、其他部件或断言才能继续；
- 离线合格候选不足 12 个而有人试图补位；
- 500 s 失败候选被加入 14000 s 清单；
- 长短算例候选 SHA256 不一致；
- 分析或报告把条件反推值升级为论文直接值；
- 有人要求按论文曲线误差自动选择或扩大候选包络。

停止并不等于项目失败。报告应明确区分共同工装错误、候选物理/数值失败、来源不可识别和正式授权不足。
