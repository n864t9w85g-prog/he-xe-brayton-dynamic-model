# Steady53 H1a-S2 Scheme A Read-Only Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不修改或加载/仿真正式 SLX、不修改 `HeXe_property_simulink.m` 或任何正式 MAT 的前提下，仅在 `tests/`/`tmp/` 中用已批准的方案 A 恢复 H1a-S2 明示线性 `(T,P)` 路径积分与 Eq. (2.28) 求根，并判断原阻断点之后的离线计算能否继续。

**Architecture:** 保留现有 `analyze_task8_h1a_readonly.m` 的默认行为及正式 H1a 输出合同不变，只在其完整 `testOnly` 合同中增加一个默认关闭的 S2 物性注入缝。新增探索区 Scheme A 物性 evaluator，逐点复现已批准 H2a counterfactual；再由一个固定 wrapper 读取同一 Task 8 MAT、固定透平表和固定模型哈希，仅把 S2 路径中的 `phi=1-1/gamma` evaluator 替换为 Scheme A。`eta/cp1/cp2`、Eq. (2.30)、输入、根区间、积分容差、求根容差和目标值均保持原 H1a 合同，结果写入独立的 `h1a_s2_scheme_a/` 探索目录。这一收敛避免复制近千行 H1a 已审定逻辑，同时由原 H1a 17 项回归锁定默认行为。

**Tech Stack:** MATLAB R2025a function-based tests、`integral`、`fzero`、SHA-256、只读 MAT 加载、CSV/TXT 探索证据。

---

## 固定边界和完成条件

- 正式受保护文件的哈希必须保持：
  - `final_steady_24a.slx`: `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`
  - `HeXe_property_simulink.m`: `2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2`
  - `turbine_table2.mat`: `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33`
  - `nominal_500_report.mat`: `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`
  - H2a CSV/TXT: `6a8398b7a32685cb3d198a1fe39b3b9365cfdefe65143d5613c68ffdd44366f4` / `afd75b1b31cd0abdbdb2926b95ab987f260caa81a55fe2e901fdde4dafd72465`
- 原 `analyze_task8_h1a_readonly()` 必须继续以 `steady53:H1aInvalidProperty` 在固定异常点 fail closed，正式 `tmp/.../h1a/<runId>/` 必须仍不存在。
- Scheme A 只作用于 H1a-S2 的 `phi` 路径积分；S1、单点 baseline、`eta/cp1/cp2` 和 Eq. (2.30) 不变。
- 成功标准不是“接近论文”，而是：真实 `integral` 完成、`fzero` 收敛、残差绝对值 `<=1e-9 K`、求得的 S2 路径全部检测点满足 `cp>0`、`cv>0`、`gamma>1`、`0<phi<1`，且所有保护对象和已加载 block diagram 集合不变。
- 输出只能进入：
  `tmp/steady53/task8_root_cause/h1a_s2_scheme_a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/`。
- 结论固定保持 `authorizesRepair=false`、`formalModelPromotion=false`、`slxLoadedOrSimulated=false`、`h1bExecuted=false`。

### Task 1: Scheme A 离线物性 evaluator（TDD）

**Files:**
- Create: `tests/steady53/hexe_property_scheme_a_offline.m`
- Create: `tests/steady53/test_hexe_property_scheme_a_offline.m`

- [x] **Step 1: 写 RED 测试**

测试必须先调用尚不存在的：

```matlab
[cpMass, gamma, rho, audit] = ...
    hexe_property_scheme_a_offline(T_K, P_Pa);
```

并验证：

1. 固定异常点与批准 H2a 结果一致：
   `cpMolar=20.787832416605639`、`cvMolar=12.476129332826748`、
   `gamma=1.6662084739623075`、`rho` 与 H2a state 一致；
2. 对 H2a `fixedPressureSweep.counterfactual.stateTable` 和
   `h1aPathSweep.counterfactual.stateTable` 的全部坐标逐点比较
   `rho/cpMolar/cvMolar/gamma/dPdrho`；
3. `audit.C111/C112/C122` 及一、二阶导数精确为零，Xe 的
   `C222` 路径保留；
4. 非有限、非标量或 `T<=0/P<=0` 输入 fail closed；
5. 源文件不含 `HeXe_property_simulink(`、`load`、写文件 API 或任何模型 API。

- [x] **Step 2: 运行测试，确认因函数不存在而 RED**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'r=runtests("tests/steady53/test_hexe_property_scheme_a_offline.m"); disp(r); assert(any([r.Failed]));'
```

- [x] **Step 3: 实现最小 evaluator**

从已通过 26/26 回归的
`analyze_task8_h2a_he_third_virial_counterfactual.m` 中复用同一组纯函数方程：
`hexeConstants`、`secondVirialTerms`、`thirdComponent`、Scheme A 的
`thirdVirialTerms`、`densityState` 和 `thermalState`。公开函数只接受两个
标量输入并返回 `cpMass/gamma/rho/audit`；`audit` 至少包含
`cpMolar/cvMolar/dPdrho/C111/C112/C122/C222` 及 C 项的一、二阶导数。
不得调用正式物性函数，也不得实现输运物性。

- [x] **Step 4: 运行 Task 1 测试并要求全绿**

- [x] **Step 5: 提交 Task 1**

```bash
git add tests/steady53/hexe_property_scheme_a_offline.m \
        tests/steady53/test_hexe_property_scheme_a_offline.m
git diff --cached --check
git commit -m "test: add offline Scheme A property evaluator"
```

### Task 2: 恢复 H1a-S2 的独立 analyzer（TDD）

**Files:**
- Modify: `tests/steady53/analyze_task8_h1a_readonly.m`
- Modify: `tests/steady53/test_analyze_task8_h1a_readonly.m`
- Create: `tests/steady53/analyze_task8_h1a_s2_scheme_a_readonly.m`
- Create: `tests/steady53/test_analyze_task8_h1a_s2_scheme_a_readonly.m`

- [x] **Step 1: 写 RED 测试**

测试调用专用 analyzer，并要求其：

```matlab
analysis = analyze_task8_h1a_s2_scheme_a_readonly(options);
```

返回以下可审计字段：

```matlab
analysis.scope.s2PhiVariant == "schemeA"
analysis.scope.etaCp1Cp2HeldFixed == true
analysis.s2.integrationCompleted == true
analysis.s2.rootConverged == true
abs(analysis.s2.rootResidual_K) <= 1e-9
analysis.s2.pathAudit.allPhysical == true
analysis.authorizesRepair == false
analysis.formalModelPromotion == false
analysis.slxLoadedOrSimulated == false
analysis.h1bExecuted == false
```

同时验证：

- 固定输入 run ID、输入 MAT/模型/物性函数/透平表/H2a 双文件哈希；
- 活动 `pi=turbine_lookup_expansion_ratio=2.2812178550028612`；
- 根区间 `[T1/pi,T1]=[664.1670261116656,1515.109678670083] K`；
- `integral` 的 `RelTol=1e-8`、`AbsTol=1e-10`，根残差门槛 `1e-9 K`；
- baseline 与 S1 数值必须与原 H1a 在其阻断前的结果相同；
- Scheme A 只进入 S2 `phi` integrand，`eta/cp1/cp2` 使用正式 baseline 值；
- resolved S2 路径用固定 1001 点复核并记录 `minCp/minCv/minGamma/minPhi`；
- 任何非物性点、积分 warning、无根括号、哈希漂移或输出碰撞均 fail closed；
- 不改变 path/warning state，不改变加载的 block diagram 集合；
- 不创建原正式 H1a 目录。

- [x] **Step 2: 运行测试，确认因 analyzer 不存在而 RED**

- [x] **Step 3: 实现最小 analyzer**

在现有 H1a analyzer 的完整 `testOnly` 选项中增加 S2 property function、variant、
source hash 和 H2a evidence hash；默认值仍为正式物性。固定 wrapper 只把 S2 的
`phiAt` 调用替换为 `hexe_property_scheme_a_offline`；baseline/S1 和
`cp1/cp2` 仍调用正式 `HeXe_property_simulink`。输出表方法名固定为
`baseline`、`S1`、`S2_schemeA_phiOnly`。

1001 点路径审计使用求得的 `T2s`：

```matlab
lambda = linspace(0, 1, 1001).';
T = T1 + lambda.*(T2s - T1);
P = P1 + lambda.*(P2 - P1);
```

逐点由 Scheme A evaluator 计算并检查域；不得把有限采样称为形式化全域证明。

- [x] **Step 4: 运行 Task 2 测试并要求全绿**

- [x] **Step 5: 提交 Task 2**

```bash
git add tests/steady53/analyze_task8_h1a_readonly.m \
        tests/steady53/test_analyze_task8_h1a_readonly.m \
        tests/steady53/analyze_task8_h1a_s2_scheme_a_readonly.m \
        tests/steady53/test_analyze_task8_h1a_s2_scheme_a_readonly.m
git diff --cached --check
git commit -m "test: restore H1a-S2 with Scheme A offline"
```

### Task 3: 固定探索证据发布与原阻断对照

**Files:**
- Modify: `tests/steady53/test_analyze_task8_h1a_s2_scheme_a_readonly.m`
- Generate: `tmp/steady53/task8_root_cause/h1a_s2_scheme_a/<runId>/h1a_sensitivity.csv`
- Generate: `tmp/steady53/task8_root_cause/h1a_s2_scheme_a/<runId>/h1a_summary.txt`

- [x] **Step 1: 写发布合同 RED 测试**

要求固定目录只含两个非空、自包含文件，TXT/CSV 均记录单变量范围、固定哈希、
baseline/S1/S2 数值、积分/求根设置、1001 点路径审计、未加载 SLX 和四个否定门。
已有目标目录必须拒绝覆盖。

- [x] **Step 2: 运行 RED 并确认缺少发布字段/文件**

- [x] **Step 3: 补足原子发布并执行真实固定输入实验**

先再次执行原 `analyze_task8_h1a_readonly()` 并确认固定
`steady53:H1aInvalidProperty`；随后执行 Scheme A analyzer。发布前后分别哈希全部保护对象，
并确认原 H1a 正式目录仍不存在。

- [x] **Step 4: 运行 H1a/H2a 聚焦回归**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'files=["tests/steady53/test_analyze_task8_h1a_readonly.m","tests/steady53/test_hexe_property_scheme_a_offline.m","tests/steady53/test_analyze_task8_h1a_s2_scheme_a_readonly.m","tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m","tests/steady53/test_publish_task8_h2a_evidence.m"]; r=runtests(files); fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assert(all([r.Passed]));'
```

- [x] **Step 5: 提交固定探索证据**

仅添加固定目录中的两个证据文件，不提交临时 staging 或 MATLAB 缓存。

固定 CSV/TXT SHA-256 分别为
`7e1ed139d14cbb1977a9f19d870c822243205414321a00c0f597717f5616f622` 和
`26248e95f42acbb70701193fa75af429b60659b9975277837331b8cd2803efd2`；
独立质量审查后，CSV 已补齐可独立解释结果所需的身份、哈希、单变量范围、
1001 点路径审计和否定门元数据；聚焦回归结果为
`52 Passed, 0 Failed, 0 Incomplete`。

### Task 4: 结论记录与最终只读验证

**Files:**
- Modify: `docs/steady53_experiment_log.md`
- Modify: `docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md`
- Modify: this plan

- [x] **Step 1: 记录准确数值与证据等级**

必须分别报告：

- ✅ 原 baseline 阻断可复现；
- ✅ Scheme A H1a-S2 是否完成积分和求根；
- ✅/❓ 相对 baseline 的 `phiBar/T2s/T2` 数值变化；
- ⚠️ 1001 点审计只是有限数值证据；
- ❌ 不授权正式物性修复或晋升；
- ❓ Task 8、14000 秒稳态和论文 5.3 分析仍未完成。

- [x] **Step 2: 最终静态核验**

对三个实现文件和三个对应测试文件运行 `checkcode`；扫描禁止模型 API；运行
`git diff --check`；复核受保护哈希、H2a 哈希和 archive tag。

- [x] **Step 3: 运行完整的批准离线回归子集**

不执行 SLX 测试；明确报告测试数量。完整 `tests/steady53` 只 discovery，不声称全套通过。

最终结果：10 文件 no-SLX 离线回归 `149 Passed, 0 Failed,
0 Incomplete`；完整目录仅 discovery `176` 项。6 个相关 MATLAB 文件
`checkcode` 均为 0。

- [x] **Step 4: 文档提交**

```bash
git add docs/steady53_experiment_log.md \
        docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md \
        docs/superpowers/plans/2026-08-26-steady53-h1a-s2-scheme-a-readonly.md
git diff --cached --check
git commit -m "docs: record H1a-S2 Scheme A recovery"
```

## 停止门

以下任一情况立即停止，不进入 SLX：

- Scheme A helper 不能逐点复现 H2a counterfactual；
- 原 H1a 阻断不能复现；
- 真实 `integral` 仍 warning/fail，或 `fzero` 无括号/不收敛；
- resolved S2 路径出现 `cp<=0/cv<=0/gamma<=1/phi∉(0,1)`；
- 需要改变 `eta/cp1/cp2`、Eq. (2.30)、输入 MAT、透平表、根区间或容差；
- 任何正式 SLX/MAT/物性函数或 H2/H2a 证据发生哈希变化。

即使全部通过，也只允许结论：`H1a-S2 Scheme A offline recovery = COMPLETE`；不得自动进入正式物性修改或 14000 秒 SLX 仿真。
