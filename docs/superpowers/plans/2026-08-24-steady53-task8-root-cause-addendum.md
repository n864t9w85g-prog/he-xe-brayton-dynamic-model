# Task 8 Root-Cause Addendum 草案：500 s 名义整机稳态点偏移

**日期：** 2026-08-24
**状态：** RED，未批准，停在 Root-Cause Checkpoint
**正式模型：** `final_steady_24a.slx`
**正式模型 SHA-256：** `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`

## 1. 人工批准门

本文档只是一份根因定位草案，不授权任何正式或临时模型修改。本轮唯一待批准范围是
第 7 节的完全只读离线 H1a 分解。在用户明确批准前，不得：

- 修改 `final_steady_24a.slx`、任何 `tmp` SLX 副本或模型内存中的方程；
- 修改 `HeXe_property_simulink.m`、透平查表、任何 MAT、初值或效率；
- 同时改变 φ̅ 口径和 cp̅ 口径；
- 改变验收门槛，或忽略 `t=0` 质量闭合失败。

只读 H1a 结果必须先提交人工审核。如果后续需要临时模型实验，必须另写第二份补遗；
该补遗只能包含一项精确的单变量修改，并再次获得人工批准。

## 2. 准确失败测试与证据状态

精确测试名为：

```text
test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds
```

选择器在运行前断言恰好选中 1 项。

- ✅ 旧证据运行 `run_1787577681355_c27e98941c2d4673b269b0d14f579ac5` 实测
  `0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真本身成功：`success=true`、`tFinal_s=500`、`errorId=""`、
  `warningIds=[]`。
- ✅ 验收首个失败标识为 `turbine_outlet_T:target`。
- ✅ 旧不可变 MAT 证据 SHA-256 为
  `f6bbefaaa2b5aa9c4af9f6198d2e20cdece89f5dd1df5578b64e70ff7ec46cf9`。
- ✅ 规格审查后的新运行 ID 为
  `run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f`，实测仍为
  `0 Passed, 1 Failed, 0 Incomplete`，没有覆盖旧证据。
- ✅ 新完整 MAT 证据 SHA-256 为
  `53c72290496d319c33ef65fed75252f5e14254ae3b1765b9e566626762dfb9ea`。
- ✅ 归一化合同复审后的最新运行 ID 为
  `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`，实测仍为
  `0 Passed, 1 Failed, 0 Incomplete`；完整 MAT SHA-256 为
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`，未覆盖任何旧 run。
- ✅ 可信审计合同和排他证据发布实现后，另行生成验证 run
  `run_1787586447806_3d8eac4909284e1cb114e0911008dd2b`；其完整 MAT SHA-256 为
  `f0525396c7159eb6dff5e2f9bc3b2e0f54e66c0d3e94875ce43240a8042f0443`，并有
  `status=completed` 的 `manifest.json`。它不改变本补遗下述 H1a 已固定的输入 run。

## 3. RED 的自动覆盖口径

旧运行的自动验收只对 21 个论文指标和 40 个积分状态实施末窗波动/趋势门。它虽然保存
了全部 37 个结果信号的末窗数值，但其中 16 个非指标信号当时没有进入自动通过/失败判定。
因此，旧日志中“全部记录输出均自动通过”的表述不精确，现修正为：

- ✅ 旧运行自动覆盖：21 个指标 + 40 个状态；
- ✅ 新实现自动覆盖：37 个结果信号 + 21 个指标 + 40 个状态；
- ✅ 37 个结果信号中的 8 个质量流量语义信号全部使用固定尺度下限 `1 kg/s`，
  包括 7 个回路观测量及透平效率表的质量流量输入；
- ✅ 每个信号保存 `kind`、`scaleFloor`、`constant`、`peakToPeakRel`、
  `trendRel` 和 `signalPass`；标记为常量的信号仍完整计算，不跳过；
- ✅ 属于 21 个论文指标的信号行直接复用已计算的
  `metric.peakToPeakRel/trendRel/windowPass`，共同使用 `abs(target)` 归一化；
- ✅ 其余 16 个非指标信号使用
  `max(abs(windowMean), approved scaleFloor)` 归一化；
- ✅ 固定尺度下限按已批准规格使用：温度 `1 K`、压力 `1 Pa`、功率 `1 W`、
  转速 `1 rpm`、质量流量 `1 kg/s`、无量纲及其他量 `1`；
- ✅ 审计名集与 `result.signals` 名集不全等、重名、数据不一致或尺度不符合固定
  规格时均 fail closed。
- ✅ `steady53_spec.requiredLookupNames` 固定 8 个 lookup 名称；审计必须
  集合精确相等且每项恰好一次，空、缺失、重名或未知额外项均 fail closed。
- ✅ `steady53_spec.signalMetadata` 固定 37 行
  `name/kind/constant/scaleFloor` 可信合同；evaluator 逐名比对调用审计，
  并只用 spec 行进入报告与归一化，不依赖调用者自报。

✅ 最新报告实测 21/21 论文指标与 37/37 个结果信号的末窗波动/趋势门全部通过；
最大相对峰峰值为 `4.52673514492192e-5`，最大相对趋势为
`4.48780756304835e-5`，均来自
`compressor_outlet_P`。这只是本轮实测结果，不改变论文指标与质量闭合仍失败的结论。

## 4. 首个失败信号的路径、端口、单位与活动方程

- ✅ `turbine_outlet_T` 来自 `final_steady_24a/TAC` 的 Outport 3。
- ✅ TAC 内部为 `TAC/Turbine/T_out` Outport 3，由 `From20(T2)` 驱动；
  `T2` 由 `TAC/Turbine/MATLAB Function1` 第 1 输出经 `Goto10(T2)` 传递。
- ✅ Simulink 端口 `Unit` 保存为 `inherit`；按论文方程、物性函数接口和验收
  规格，`T1/T2/T2s` 为 K，`P1/P2` 为 Pa，`cp1/cp2` 为 J/(kg·K)，
  `N` 为 rpm，`mdot` 为 kg/s，`γ/φ/π/η` 无量纲。

当前活动方程为：

```matlab
phi = 1 - 1/gamma;
T2s = T1 * pi^(-phi);
T2 = T1 - (neta*cp2*(T1-T2s))/cp1;
```

其中 `phi` 是由入口单点 `gamma(T1,P1)` 计算的单点量；`cp1` 和 `cp2`
分别是入口点 1 与等熵出口点 2s 的单点物性。

## 5. 论文 Eq. (2.27)–(2.31) 上下文的本轮直接复核

- ✅ PDF 第 35 页（印刷页 20）§ 2.2.2.5 中的 Eq. (2.27) 定义 He-Xe
  普朗特数 `Pr = cp*mu/lambda`；它不是压气机过程方程，也没有定义透平
  φ̅₁₋₂的平均算子或热力路径。
- ✅ PDF 第 38–39 页（印刷页 23–24）中的 Eq. (2.28)–(2.31) 已按
  透平上下文复核。
- ✅ Eq. (2.28) 用 φ̅₁₋₂ 计算等熵出口温度，Eq. (2.29) 定义透平膨胀比；
  论文只说 φ̅₁₋₂ 是进出口过程平均量且与比热容有关，没有给出精确平均算子、热力
  路径、压力路径、求积方法或迭代收敛容差。
- ✅ Eq. (2.30) 将透平效率写为实际过程 1–2 和理想过程 1–2s 的平均 cp̅ 之比；
  随后段落用 ∫cp(T)dT 解释温度变化的焓差与平均 cp̅。
- ✅ Eq. (2.31) 用实际过程平均 cp̅₁₋₂(T1−T2) 计算透平功。
- ✅ 直接核实：论文 Eq. (2.30) 后的文本将物性写为 cp(T)；当前
  `HeXe_property_simulink(T,P)` 的活动实现中，`P_Pa` 经
  `P_RT -> rho_hat -> cp_mol` 路径进入 cp 计算，因而 cp 同时使用温度与压力。
- ❓ 数值实现判断：若用当前 `cp(T,P)` 物性函数执行论文的
  `∫cp(T)dT`，必须另行选择 `P(T)` 路径；论文未给出该路径，本草案不代用户选择。

因此，本草案不代用户选择物理路径，也不把任何数值平均候选写成论文已定义的唯一实现。

## 6. 当前数值复算与可证伪候选

✅ 用旧运行最终时刻输入对当前块方程离线复算：

| 量 | 当前值 |
|---|---:|
| `T1` | `1515.109678670083 K` |
| `P1` | `1538809.802594816 Pa` |
| `P2` | `674556.267925093 Pa` |
| `pi` | `2.281217855002861` |
| `gamma(T1,P1)` | `1.665824326170285` |
| `phi(T1,P1)` | `0.399696604083703` |
| `T2s` | `1089.647518112211 K` |
| `cp1(T1,P1)` | `519.656781110474 J/(kg·K)` |
| `cp2(T2s,P2)` | `519.658066226693 J/(kg·K)` |
| `eta` 查表值 | `0.872869608810761` |
| 方程复算 `T2` | `1143.735770611176 K` |
| 仿真记录 `T2` | `1143.735770611176 K` |

✅ 上表证明记录信号与当前活动透平方程一致，不是端口选错或单位换算造成
`18.264 K` 差值。

- ✅ 只把查表效率 `0.8728696` 换成论文表 4.9 的 `0.87`，其他当前量不变时，
  离线计算仅使 `T2` 从 `1143.736 K` 变为 `1144.957 K`。
- ❓ 在继续沿用当前单点口径的假设下，反算目标 `1162 K` 所需
  `eta≈0.8299417`。它是反算值，不是论文值，禁止用作调参输入。

**H1a（❓）：** 当前用入口单点 `phi(T1,P1)` 代替 Eq. (2.28) 的 φ̅₁₋₂，
可能独立改变 `T2s`，并在保持当前 Eq. (2.30) 单点 `cp1/cp2` 处理不变时改变
`T2`。它尚未证明是唯一或足量根因。

**H1b（❓，本轮不执行）：** 只有在 H1a 口径经人工选择并固定为新基线后，才能将
Eq. (2.30) 实际过程和理想过程的平均 cp̅ 作为增量变量单独计算。本草案不授权 H1b，
也不授权将 H1a/H1b 合并试验。

**H2（❓）：** 如果分离的 H1a/H1b 仍不能解释偏差，再逐项核对
`HeXe_property_simulink` 与论文 Eq. (2.8)–(2.17) 及其原始系数。本轮不执行 H2。

## 7. 待批准的唯一只读 H1a 计划

输入严格固定为：

- run ID：`run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`；
- 输入 MAT：
  `tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat`；
- 输入 MAT SHA-256：
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`。

若 H1a 获得人工批准，待创建的唯一只读脚本路径固定为
`tests/steady53/analyze_task8_h1a_readonly.m`；在批准前不创建、不执行该脚本。
它必须只用 `load(inputMat,"result","report","spec")` 读取：

- `result.t`；
- `result.signals.turbine_inlet_T`、`result.signals.turbine_inlet_P`；
- `result.signals.turbine_outlet_P`、`result.signals.turbine_outlet_T`；
- `result.signals.turbine_lookup_mass_flow`、
  `result.signals.turbine_lookup_speed_eff`；
- `result.signals.turbine_expansion_ratio`；
- `report.metrics` 中的 `turbine_outlet_T` 目标和当前误差；
- `spec.finalWindow_s`。

末时刻 `T1/P1/P2/T2` 从上述时序字段取值；`gamma/cp1/cp2` 只读调用
`HeXe_property_simulink`复算。固定的当前 `eta` 由上述两个 lookup 输入与
`turbine_table2.mat` 中的 `bp_mf/bp_speed/table_eff` 按当前查表方式只读复算；
输出还必须记录该 lookup MAT 的 SHA-256。

若获批执行，输出路径固定为：

- `tmp/steady53/task8_root_cause/h1a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1a_sensitivity.csv`；
- `tmp/steady53/task8_root_cause/h1a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1a_summary.txt`。

`h1a_summary.txt` 必须记录输入 run ID、输入 MAT 精确路径和
`inputMatSha256=4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`；
若执行时哈希不等则 fail closed，不产生 H1a 结果。

本轮只计算 φ̅ 对 Eq. (2.28) `T2s` 及在当前 Eq. (2.30) 处理下
`T2` 的独立贡献。
`eta/cp1/cp2`、查表、MAT、模型、初值和其他部件全部固定。

由于论文未定义 φ̅ 的唯一平均路径，只读报告必须并列、不代用户选择下列“数值实现选择”
敏感性候选：

1. **H1a-S1：端点算术平均**
   `φ̅=[φ(T1,P1)+φ(T2s,P2)]/2`，与 `T2s=T1*pi^(−φ̅)` 联立求根。
2. **H1a-S2：明示线性 (T,P) 路径的数值积分敏感性**
   令 `T(λ)=T1+λ(T2s−T1)`、`P(λ)=P1+λ(P2−P1)`，
   `φ̅=∫₀¹φ(T(λ),P(λ))dλ`，再与 Eq. (2.28) 联立求根。

S1/S2 都只是论文未指定的数值实现选择，不是已证实的物理路径。两者必须分开列出
`φ̅/T2s/T2` 和相对当前口径的增量，不得只报告更接近论文的一项。

为保证只读数值可复现，候选工作表的数值设置固定为：

- 外层 `T2s` 求根区间 `[100 K,T1]`，要求残差绝对值 `≤1e-9 K`；
- S2 的 `λ∈[0,1]` 积分使用 `RelTol=1e-8`、`AbsTol=1e-10`；
- 物性越界、求根无括号区间或不收敛均 fail closed；
- 只生成离线表格/文本，不调用 `set_param`，不保存或仿真任何 SLX。

H1a 只读结果审核后，用户才决定是否选择其中一个数值实现，进入第二份补遗的单变量
临时 H1a 实验，或停止 H1。

## 8. H1b 后续分解边界（本轮不授权）

如果后续人工固定了 H1a 基线，H1b 只允许计算 Eq. (2.30) 实际过程/理想过程平均 cp̅
相对该固定基线的增量。由于当前物性接口是 `cp(T,P)`，H1b 必须在新的人工审核门前
分开列出论文的 ∫cp(T)dT 形式与各个明示 P(T) 数值候选，不得自行选定路径，不得与 H1a
同时实验。

## 9. `mass:closure` 独立分支

✅ 旧运行最大质量闭合相对差为 `1.1454162022e-3 > 1e-6`，发生于 `t=0`：
透平质量流量 `11.9837137735 kg/s`，其余四个 He-Xe 回路观测点各为
`11.97 kg/s`；锂侧闭合差为 `0`。

本分支继续保留且与 H1 分开。后续只读追踪 `TAC/Turbine/mdot` 与其他四个 He-Xe
质量流量端口的初始方程和执行顺序；不修改门槛、不忽略 `t=0`、不为通过验收直接
改初值。

## 10. 停止条件

如果只读 H1a 需要代用户选择物理路径，或任何后续工作需要修改正式/临时 SLX、MAT、
物性系数、效率、初值或验收门槛，立即停止并返回人工审核。
