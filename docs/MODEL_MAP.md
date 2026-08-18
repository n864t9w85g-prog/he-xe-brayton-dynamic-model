# 模型地图（首次只读审计）

审计日期：2026-08-18  
审计范围：当前仓库全部可见文件、`final_dynamic_24a.slx` 的只读 MATLAB/Simulink 检查、现有测试和论文 PDF。  
本文件只记录事实和待确认事项；本轮没有修改任何既有模型、代码、参数或交付文件。

## 1. 项目结构

仓库根目录没有 `specs/` 子目录；用户指定的四份规则文件实际位于根目录：`AGENTS.md`、`决策自律准则.md`、`交付边界约束_v4.md`、`验收标准_论文5.4.md`。这属于路径一致性风险，不能因此改变规则内容。

主要文件按用途分类如下：

| 类别 | 文件/目录 | 用途与状态 |
|---|---|---|
| 正式动态模型 | `final_dynamic_24a.slx` | 当前目标交付模型；本轮只读检查 |
| 相关模型/快照 | `final_steady_24a.slx`、`final_steady_24a.slx.r2024a`、`*.slxc`、`final_dynamic_24a.slx.original`、`*.bak` | 历史模型、编译缓存或备份；不是已确认的 Step 0 备份 |
| 运行入口 | `start.m`、`run_dynamic.m` | 加载 MAT/参数、设置 5.4 时序并运行动态模型 |
| 物性/参数 | `HeXe_property_simulink.m`、`Lithium_property_simulink.m`、`prop_material.m`、`sys_param_rad_fixed.m`、`paper54_constants.m`、`paper54_schedules.m` | 物性函数、辐射器参数、论文常数和时序 |
| 查表数据 | `hexe_compressor_lookup.mat`、`radiator_table.mat`、`turbine_table1.mat`、`turbine_table2.mat` | 压气机、辐射器、透平查表数据 |
| 压气机探索链 | `build_traceable_compressor_lookup.m`、`rebuild_hexe_compressor_lookup.m`、`activate_traceable_compressor_lookup.m`、`apply_compressor_corrected_coordinates.m`、`compressor_corrected_coordinates.m`、`tmx2269_*.m`、`output/compressor_map_rebuild/` | 候选表、坐标和来源审计；尚不能视为交付链 |
| 其他探索/求解 | `apply_paper52_generator_load.m`、`solve_paper52_operating_point.m`、`tests/audit_paper52_baseline.m` | 设计点、功率平衡和局部实验 |
| 测试 | `tests/` | MATLAB 单元/审计脚本和 Python 来源测试；探索区 |
| 中间产物 | `tmp/`、`output/`、`slprj/` | PDF 转换、图像、仿真输出、编译缓存；不应成为交付模型依赖 |
| 论文/来源 | `空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf`、`sources/*.pdf`、根目录锂物性/NASA PDF | 论文及查表来源 |

首次只读审计执行时未建立可用提交基线；当前仓库已有发布历史。当前审计分支为 `codex/publish-he-xe-brayton-model`，其审计前 HEAD 为 `fa90cfc`，并将在本阶段建立新的只读审计 baseline。`main` 保留已有发布基线，不在本阶段修改。

## 2. 正式模型顶层结构

只读 Simulink 检查显示 `system_root` 下共有 15 个顶层块。六个物理架构子系统为：

| 精确名称 | 层级 | 作用/论文对应 |
|---|---|---|
| `reactor` | 3.1 物理架构层 | 反应堆点堆动力学、燃料/冷却剂温度及反应性输入；对应论文 §5.2.1.1、式 (5.1)-(5.7) |
| `TAC` | 3.1 物理架构层 | 透平-发电-压缩一体机和转子动力学；对应论文 §5.2.1.5、式 (5.17)-(5.18) |
| `recuperator` | 3.1 物理架构层 | He-Xe 回热器两区集总参数换热；对应论文 §5.2.1.3、式 (5.12) |
| `IHX` | 3.1 物理架构层 | 锂/He-Xe 中间换热器两区集总参数换热；对应论文 §5.2.1.3、式 (5.13) |
| `precooler` | 3.1 物理架构层 | He-Xe/NaK 预冷器两区集总参数换热；对应论文 §5.2.1.3、式 (5.14) |
| `rediator` | 3.1 物理架构层 | 辐射散热器（模型拼写为 `rediator`）；对应论文 §5.2.1.4、式 (5.15)-(5.16) |

其余 9 个顶层块为数据/数值或记录块，归入 3.2 方程实现层或“未归类”：`Pload_fw`、`Goto`、`From`、`Constant`、`Unit Delay`、`Unit Delay1`、`Scope`、`Scope1`、`Scope2`。模型总规模的只读统计为：1297 blocks、47 SubSystem、40 Integrator、4 Assertion、8 Scope、10 To Workspace、12 Display、2 From Workspace、2 Unit Delay。

## 3. 主要信号流和耦合

### 3.1 热力学回路

- 锂回路：`reactor -> IHX -> reactor`。
- He-Xe 回路：`IHX -> TAC/Turbine -> recuperator -> precooler -> TAC/Compressor -> recuperator -> IHX`。
- NaK 散热回路：`precooler -> rediator -> precooler`，模型环境温度为 `T_env=225 K`。

### 3.2 外部输入和记录

- `Pload_fw -> Goto/From -> TAC/Pload`：`run_dynamic.m` 将 `Pload_sched` 写入 base workspace；这是开环负荷输入，不是控制器。
- `rho_fw -> reactor/Goto20(A3) -> From40 -> Sum10`：反应性时序进入堆芯反应性求和点。
- TAC 转子状态由 `TAC/rotor/N_rpm_Integrator` 积分。`run_dynamic.m` 设置其初值为 `55090 rpm`，并明确注释这只是初值，不是已证明的耦合稳态。
- 主要 To Workspace 信号包括 `N_log`、`P_log`、`Tf_log`；`V10_Tw_*`、`V10_T_rad` 等内部换热/辐射量是否属于正式验收输出，待确认。

### 3.3 物理反馈

- 转子动力学：`P_t - P_c - Pload/eta_generator` 进入 `900/(pi^2*0.5)` 系数，再除以转速并积分；结构对应论文式 (5.17)-(5.18)，不能仅因存在反馈路径而判定为外挂控制器。
- 反应堆：模型含六组 `beta/lambda`、`alphaf=-6.4e-6` 燃料温度反馈和 `rho_fw`。模型还有 `alphac=-8.35e-6` 冷却剂反应性项主动进入 `Sum10`；本轮已核对论文段落没有找到该项的明确对应式，列为“待确认的新增物理机制”，不得擅自删除或保留。

### 3.4 未归类的数值块

- 顶层 `Constant=6.95` 送入 `precooler` 冷侧质量流量。
- `Unit Delay` 位于 TAC 压缩机出口压力至 recuperator 的主回路，初值 `1.551e6`。
- `Unit Delay1` 位于 TAC 质量流量至 recuperator 的主回路，初值 `11.97`。
- 两个 Unit Delay 的 `SampleTime=-1`。它们不是只读记录块，可能用于打断代数环或数值初始化；论文出处及其对动态行为的影响尚未确认。

## 4. 论文到实现的对应关系

| 论文内容 | 当前实现 | 证据等级 |
|---|---|---|
| §5.2.1.1 点堆、六组缓发中子、燃料温度负反馈、式 (5.4) | `reactor` 内六组 `beta/lambda`、`alphaf`、`rho_fw` | ✅ 已核对 PDF 第 78 页及模型参数 |
| §5.2.1.5 TAC 功率平衡与转子方程 | `TAC/rotor` 功率差、惯量系数、转速积分 | ✅ PDF 第 87 页式 (5.17)-(5.18) 与模型结构相符 |
| 表 5.2 压气机入口/出口设计状态 | `PR=1.551/0.658=2.357142857`；当前活动表设计 PR 相同 | ✅ PDF 第 89 页和 MAT 检查 |
| §5.2.1.3 IHX/recuperator/precooler PCHE 集总方程 | 三个子系统各含 2 个 region | ⚠️ 方程对应已确认；两区离散数目的论文明示出处待确认 |
| §5.2.1.4 辐射散热器 | `rediator` 与 `T_env=225 K` | ✅ 章节/式对应已核对 |
| 论文启动六阶段调度 | `run_dynamic.m` 只加载负荷和反应性 schedule，未实现六阶段锂流量/TAC 启动调度 | ✅ 脚本和验收标准对照 |
| 冷却剂反应性系数 `alphac` | `reactor` 中存在，但本轮未找到明确论文式 | ❓ 待人工确认 |

## 5. 交付链与探索链

当前能从入口静态追踪到的直接/间接运行依赖并集为：

`final_dynamic_24a.slx`、`start.m`、`paper54_constants.m`、`paper54_schedules.m`、`sys_param_rad_fixed.m`、`hexe_compressor_lookup.mat`、`radiator_table.mat`、`turbine_table1.mat`、`turbine_table2.mat`、`HeXe_property_simulink.m`、`Lithium_property_simulink.m`。

没有发现活动模型或入口脚本直接引用 `tests/`、`tmp/`、`apply_*`、`fix_*` 或 `patch_*`。静态依赖器对 MATLAB `load()` 字段和 Stateflow extrinsic 函数可能漏报，因此该结论是多种只读方法的并集，不是形式化依赖证明。

`apply_*`、`build_*`、候选 MAT、PDF 图像和历史结果均属于探索/审计链；它们不可因实验结果改善而自动进入正式交付链。

## 6. 可疑项清单

1. 正式模型包含 4 个 Assertion、多个 Scope、12 个 Display；其中部分可能只是模型验证/内部诊断块。需结合连接方向和最终输出要求逐块判定。
2. 两个主回路 Unit Delay 的数值依据和动态副作用待确认。
3. `alphac` 的论文出处未确认，触发人工确认门。
4. 当前活动压气机 MAT 的元数据为 `version='4.0-nasa-tmx2269-candidate'`、`candidate_status='not active until all gates pass'`，但 `start.m` 无条件加载该文件，门禁状态和实际活动状态不一致。
5. `radiator_table.mat` 含多余 `out`（`Simulink.SimulationOutput`）和 `ans` 字段；`start.m` 无选择地加载全部字段，且 MAT 中变量 `version` 可能遮蔽 MATLAB `version()`，存在工作区污染风险。
6. 未找到符合正式 Step 0 命名规则的 `final_dynamic_24a_backup_YYYYMMDD_HHMMSS.slx`；现有 `.original`/`.bak` 是否可替代，无法确认。
