# 论文 §5.3 稳态与图 5.19 初始化根因阶段报告

本报告只汇总截至 2026-09-01 已固化的证据。它不是论文复现完成声明，也不授权新的参数扫描、第二个反事实或正式模型修改。证据标记遵循仓库根目录 `决策自律准则.md`：✅ 本轮可复算/可定位，⚠️ 已有证据但存在明确限制，❓ 仅为本阶段反事实或下一步假设，❌ 当前未知或尚未满足。

## 状态总表

<!-- FIG519_STATUS_BEGIN -->
```json
{
  "figure_5_18d_reproduced": false,
  "figure_5_19_reproduced": false,
  "section_5_3_reproduced": false,
  "section_5_4_reproduced": false,
  "formal_model_modified": false,
  "formal_promotion": false,
  "paper_reproduced": false,
  "author_initial_state_identified": false,
  "result_enum": "reactor_ic_alone_falsified",
  "next_single_state_family": "IHX_region_2_HeXe_turbine_inlet_thermal_states",
  "next_decision_gate": "written_specification_approval_required",
  "selected_best_candidate": false,
  "automatic_envelope_expansion": false,
  "time_shifted": false,
  "smoothed": false,
  "fitted_electrical_efficiency": false,
  "digitized_t10_claimed_as_author_t0": false
}
```
<!-- FIG519_STATUS_END -->

✅ 固定状态：`paper_reproduced = false`、`author_initial_state_identified = false`、`formal_promotion = false`。图 5.18(d)、图 5.19、§5.3 和 §5.4 均未通过完整复现门。

✅ 正式模型零修改：本阶段只产生探索区候选、测试和溯源文档；A2 的保护文件审计记录正式 SLX、MAT、物性与运行依赖的前后哈希不变。候选 SLX 未晋升，正式稳态/动态模型未接入探索区文件。

## 本阶段完成并固化的对象

✅ `data/provenance/baselines/f8bcd83/` 固化了基线模型与运行依赖；当前基线模型 SHA256 为 `0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`。

✅ `data/provenance/steady53/fig5_18d/` 固化了图 5.18(d) 的 12 个论文点、2 个初值 MAT、96 行离线筛选、12 个代表包（11 个具备候选清单）以及 500 s/14000 s 结果。其机器状态为 `current_equation_family_status = incompatible_with_both_digitized_curves`、`a1_identifiability = multiple_conditionally_feasible_packages`：3 个代表包通过 500 s 且进入 14000 s，但这不能唯一识别作者实现，也没有正式晋升。

✅ `data/provenance/steady53/fig5_19/` 固化了论文页、60 个数字化点、覆盖图、数字化规则、14000 s 原基线功率对比、信号定义、40 状态初始化审计，以及 A1/A2 单变量反事实历史摘要。

✅ 已有运行记录的精确计数为：A1 正式命令 1 次、`run_steady53_case` 0 次、重试 0 次；A2 正式命令 1 次、`run_steady53_case` 1 次、重试 0 次。合计正式命令 2 次、科学运行调用 1 次、重试 0 次。A2 是本阶段唯一完成的候选 500 s 运行；没有第二个反事实。

## 图 5.19 论文曲线的观测层

✅ 图 5.19 来自论文 PDF 第 106 页（印刷页 91）的固定扫描页。每个 panel 使用同一组 15 个固定时刻（10–495 s），合计 60 点。算法在 `x-1:x+1` 三列以灰度 `<120` 找墨迹，组成连续 y 像素组，从 495 s 反向按最近连续组中心追踪；等距时选更上方中心，并拒绝坐标轴边框、空列及超过 80 px 的跳跃。

✅ 预先声明的扫描容差为：时间 ±3 s；panel a/b/c/d 的功率容差分别为 25/6/3/8 kW。`paper_points.csv`、`provenance.json` 和 `digitization_overlay.png` 给出可复算记录。

⚠️ 早期曲线接近竖直，分辨率受扫描限制。身份 `figure_5_19_digitized_t10_proxy_not_author_t0` 的含义严格是“t=10 s 数字化代理点”，不是作者给出的 t=0 初值。

## 当前模型的功率定义与初始化

✅ Simulink 官方 API 已确认：反应堆功率 `P_sw` 直接来自 `final_steady_24a/reactor/Integrator6`；透平功率来自 `final_steady_24a/TAC/Turbine` 输出 4；压气机功率来自 `final_steady_24a/TAC/Compressor` 输出 2；负荷由 `final_steady_24a/Constant14` 经 TAC 输入 6 / `Pload` 施加，值为 1,000,210 W。

✅ 未发现直接发电机功率信号。论文口径电功率仅作离线派生 `0.98*(WT_sw-Wc_sw)`；0.98 来自论文口径，不是本阶段拟合效率。历史 `0.96527*(WT_sw-Wc_sw)` 指标未被接受为图 5.19 正式定义。

✅ 初始化审计记录 40 个连续状态。代表性路径包括：`reactor/Integrator6`（2,660,960.914 W）、`TAC/rotor/N_rpm_Integrator`（55,090 rpm）、`IHX/IHX_region_1/T_c1_average_Integrator`（1458.240 K）、`recuperator/MannRegion_1/T_c1_average_Integrator`（973.100 K）和 `rediator/T_rad_Integrator`（416.608 K）。40 个状态按 `abs(first_sample_slope)/max(abs(t0),1) <= 1e-6 /s` 的诊断规则均属近零斜率；这是数值观测，不是作者初态证明。

✅ 原基线在 0–500 s 几乎平坦：反应堆、透平、压气机和论文口径电功率峰峰值分别仅约 0.0514、0.1609、0.2266、0.3793 W。模型没有根 Inport，根层固定边界包括 `Constant=6.95` 到预冷器和 `Constant14=1000.21e3` 到 TAC 负荷；状态本身已放在当前固定边界下的近稳态附近。因此，当前模型会从“已稳态化状态”开始，而不会自然产生论文图 5.19 的明显冷启动过渡。

✅ 原 14000 s 基线相对论文 15 点的 RMSE 为：反应堆 237.55100653524295 kW、透平 63.9636463094873 kW、压气机 29.449898542545878 kW、论文口径电功率 34.54364589385944 kW。能跑通 14000 s 不等于复现了论文稳态运行特性。

⚠️ 初始残差中可直接计算的反应堆首区间功率斜率为 -0.0333715 W/s，轴系功率算术量 `WT(t0)-Wc(t0)-Pload` 为 35,934.179 W；IHX、回热器、预冷器和散热器的完整能量残差因缺少直接焓流/储能导数信号而不可观测。不能把已计算项外推成整机初态闭合已证明。

## A1 与 A2 单变量反事实

⚠️ A1 在仿真调用前因 R2025a 不支持所用 `fopen(...,"x",...)` 权限模式而失败。它只证明“正式尝试在预仿真基础设施处失败”：原尝试 runner 的 SHA 被记录，但其精确旧字节没有独立归档，原始 batch stdout/stderr 未归档；错误标识来自随后无模型复现。因此 A1 不是数值或模型物理结果。

❓ A2 只改变候选副本 `reactor/Integrator6.InitialCondition` 为 3,186,507.937 W；数值取自上述 t=10 s 代理点。该循环使用论文观测构造反事实，所以结论只能回答：“仅改变反应堆功率状态，能否解释四条功率曲线？”不能据此识别作者初值。

✅ A2 唯一 500 s 运行成功完成数值门，但四个 panel 的方向序列均不匹配：候选按预声明容差得到的方向序列均为空，而论文 a/b/c/d 分别为 `[fall]`、`[rise]`、`[fall,rise]`、`[rise,fall]`。

✅ 非平坦门也未全部通过：反应堆、透平和论文口径电功率超过各自原基线噪声的 10 倍，压气机（`compressor`）仅 1.417730409 W 峰峰值，低于 2.265998959 W 门限。A2 对论文点的 RMSE 为：反应堆 237.6560876219371 kW、透平 63.97522843651207 kW、压气机 29.450068481857393 kW、论文口径电功率 34.55500454745297 kW。

❓ 因此实际枚举为 `reactor_ic_alone_falsified`：在这个候选值、这个固定基线、预声明方向/非平坦规则和 500 s 窗口内，“反应堆功率初值单独解释四条曲线”被反证。它不证明反应堆功率初值与作者一致，也不排除其他初态、边界施加或方程实现差异。

⚠️ A2 执行前固化了 runner 与候选生成器字节；但三个运行 helper 及 `prepare_fig519_reactor_ic_a2.py` 的执行时精确字节没有全部同步捕获。现有佐证等级是 `post_hoc_git_inference`，其明确限制为 `cannot exclude execution-time uncommitted modifications that were later reverted`。这不改写原始 MAT/CSV，也不足以把执行证据升级为完全自包含复现包。

⚠️ A1/A2 候选、原始 MAT、CSV、stdout/stderr 和命令捕获通过 `manifest.csv` 的外部定位器指向 `tmp/`。外部 `tmp/` 定位器不是耐久存储；删除或清理 `tmp/` 后，耐久 JSON 仍保留摘要和哈希，但外部原始字节将不可由仓库提交恢复。

## 本阶段完整门禁

✅ 2026-09-01 新运行的八组 Python 合同共 101 项全部通过；runtime、图 5.18(d)、图 5.19 数字化、原基线与 A2 摘要的 5 个只读验证命令全部返回固定通过标识。

✅ 计划引用的保护清单仍存在，并由正式解析器得到 `ROWS=34; RESOLVED=34; UNRESOLVED=0`。MATLAB R2025a 的 `test_prepare_radiator_a1_candidates` 与 `test_audit_fig519_initialization` 为 2 passed、0 failed、0 incomplete。

✅ `git diff --check` 无空白错误；对 `final_steady_24a.slx`、`final_dynamic_24a.slx`、根目录正式 `*.mat`、`HeXe_property_simulink.m`、`Lithium_property_simulink.m` 的差异检查为空。README 同步只更新文档身份；`source_page_106.png`、`paper_points.csv`、`provenance.json` 和 `digitization_overlay.png` 的固定 SHA256 均保持不变。

## 尚未知与下一决策门

❌ 论文没有给出完整作者初始状态向量；当前不知道 40 个连续状态中哪些与作者 t=0 一致，也不知道作者是否通过 operating point、预运行、外部边界调度或其他未披露初始化流程施加初态。

❌ IHX、回热器、预冷器、散热器在作者起始时刻的完整能量闭合与边界施加顺序尚未识别；当前也没有直接发电机功率信号可证明论文电功率在模型内的精确实现位置。

❓ 根据已测 API 影响图，在 `reactor_ic_alone_falsified` 分支下，下一个只能被识别为单一状态族的是 `IHX_region_2_HeXe_turbine_inlet_thermal_states`：`IHX_region_2/T_c1_average_Integrator` 与 `T_c2_out_Integrator` 有到透平组件及 `WT_sw` 的官方 API 路径，并同时进入离线电功率组成。这里仅识别候选状态族，不选择数值、不生成候选、不执行实验。

下一步必须先提交该单一状态族的书面实验规格，说明变量边界、独立来源、预声明方向/非平坦门、一次性运行规则和失败归档，然后请求人工批准。未获书面规格批准前，停止在此决策门；不自动扩展包络，不开展第二个反事实。
