# He-Xe Brayton Dynamic Model — 空间锂冷堆 He-Xe 布雷顿循环动态模型复现

本仓库的目标是在 MATLAB/Simulink 中复现徐驰博士学位论文《空间锂冷堆He-Xe布雷顿
循环发电系统优化设计与运行特性分析》第 5.4 节"动态运行特性分析"的仿真结果，
包括：

- **§5.4.1 启动瞬态**：六阶段冷启动过程，总时长 14000 s，初始堆功率 1 W、
  初始温度 225 K。
- **§5.4.2 变工况响应**：稳定运行点附近的 ±5% 转速扰动、TAC 负荷扰动、
  反应性扰动，三类工况分别验证。

最终交付目标是一个干净的 Simulink 模型 `final_dynamic_24a.slx`：只包含论文本身
描述的物理部件与物理耦合，不包含任何为了让曲线对上论文而额外加装的控制器、
校正反馈或拟合补丁。数值与曲线的允许误差以 `验收标准_论文5.4.md` 为准。

> 本项目的执行方式高度依赖三份治理文档（见下文"项目治理与规则文档"），它们
> 规定了证据分级标注、可做/不可做的修改边界，以及探索区与交付区的划分。在对
> 模型或代码做任何非平凡改动之前，请先读这三份文档。

---

## 仓库状态说明

本仓库当前有两个相关分支：

- `main`：仅包含 `.gitignore`，尚无实质内容。
- `codex/publish-he-xe-brayton-model`：包含本 README 描述的全部模型、脚本、
  数据溯源材料与文档，是目前实际的工作分支。

在合并到 `main`之前，克隆/拉取本仓库时请确认所在分支，否则会得到一个几乎
为空的工作区。

---

## 当前进度（截至 2026-08-18 只读审计）

**项目尚未完成，验收标准全部未通过。** 最近一次只读审计的结论：

- `run_dynamic.m` 入口目前**无法完整运行到 14000 s**：仿真在 `t ≈ 4.437 s`
  因压气机修正流量（corrected flow）超出当前查表上界而触发
  `Simulink:blocks:AssertionAssert`，失败块为
  `TAC/Compressor/Corrected_Coordinates/FlowBelowMaximum_Assertion`。
- 当前入口脚本的初值是热态工况（堆功率约 3.14 MW、燃料温度约 1743 K、
  转子 55090 rpm），**尚未实现论文 §5.4.1 要求的 `1 W / 225 K / 0 rpm` 六阶段
  冷启动调度**。
- 压气机候选查表的设计转速已从历史值 18732 rpm 修正为与论文单轴设计点一致的
  55090 rpm，速度断点也已覆盖该转速，但该查表元数据标记为
  `candidate_status='not active until all gates pass'`，与 `start.m` 无条件
  加载它的实际行为存在矛盾，这一点尚未澄清。
- MATLAB 本地测试 `8/8 PASS`，Python 本地测试 `6/6 PASS`，但这些测试仅覆盖
  常数/时序/来源审计/局部功率平衡等局部环节，**不覆盖整机动态仿真是否成功**。

详见 `docs/STATUS.md`（现状审计）、`docs/MODEL_MAP.md`（模型结构盘点）与
`docs/PLAN.md`（后续分阶段计划）。三者均标注为"只读审计"，本轮未修改任何
`.slx` / `.m` / `.py` / `.mat` 文件或验收标准。

---

## 项目治理与规则文档

本项目对"结论必须有证据支撑"要求很高，所有实质性修改都必须遵循以下规则文件
（均位于仓库根目录）：

| 文件 | 作用 |
|---|---|
| `AGENTS.md` | 项目背景、核心目标、执行原则、探索区/交付区划分、完成定义（Done Criteria）；任何自动化代理开始任务前必读。 |
| `决策自律准则.md` | 三条铁律（不臆测、不偏执、不走极端）与证据分级标注体系 `✅ 已核实 / ⚠️ 未复验 / ❓ 推断 / ❌ 证据不支持`，全仓库结论必须统一使用这套标注。 |
| `交付边界约束_v4.md` | 模型结构黑名单、探索区与交付区的操作细则、信号记录规则、修改—验证协议的正式依据。 |
| `验收标准_论文5.4.md` | 逐图（论文图 5.23–5.34）整理的数值与曲线验收阈值，是判断某一工况"通过/未通过"的唯一正式依据。 |

如果规则文档之间或与 `AGENTS.md` 冲突，以更具体、更新的正式规则文档为准。

---

## 环境要求

- MATLAB `R2025a`（`25.1.0.2943329`）
- Simulink `25.1`
- Python 3（用于 `tests/` 下的来源审计脚本，标准库即可；未强制要求 `pytest`）

---

## 快速开始

```matlab
% 在 MATLAB 中，将工作目录切到仓库根目录后运行：
run_dynamic
```

`run_dynamic.m` 会依次：

1. 调用 `start.m` 加载压气机/辐射器/涡轮查表（`.mat`）并初始化物性参数；
2. 通过 `paper54_schedules()` 设置论文 §5.4 的负荷（`Pload_sched`）与反应性
   （`rho_sched`）时序；
3. 将 TAC 转子初值设为论文设计转速 `55090 rpm`；
4. 设置 `StopTime` 并调用 `sim('final_dynamic_24a')`；
5. 绘制转速、堆功率、燃料温度曲线。

如上文"当前进度"所述，**该入口目前会在约 4.4 s 处因压气机断言失败而提前
终止**，这是已知且已记录在案的问题，不是使用方法错误。

### 运行测试

```matlab
% MATLAB 单元/审计测试（tests/ 目录下的 test_*.m）
runtests('tests')
```

```bash
# Python 来源审计测试
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

---

## 仓库结构

```
.
├── AGENTS.md                      # 代理任务规则入口
├── 决策自律准则.md                  # 证据分级与三条铁律
├── 交付边界约束_v4.md               # 模型结构与修改边界
├── 验收标准_论文5.4.md              # 数值/曲线验收阈值
│
├── start.m                        # 加载查表数据、初始化参数
├── run_dynamic.m                  # 动态仿真主入口
├── paper54_constants.m            # 论文常数
├── paper54_schedules.m            # 论文 §5.4 负荷/反应性时序
├── sys_param_rad_fixed.m          # 辐射器参数
├── HeXe_property_simulink.m       # He-Xe 工质物性函数
├── Lithium_property_simulink.m    # 锂工质物性函数
├── prop_material.m                # 材料物性函数
│
├── final_dynamic_24a.slx          # 当前目标交付的动态模型
├── final_steady_24a.slx           # 对应的稳态模型
├── hexe_compressor_lookup.mat     # 压气机查表（候选表）
├── radiator_table.mat             # 辐射器查表
├── turbine_table1.mat/2.mat       # 涡轮查表
│
├── build_traceable_compressor_lookup.m   # 压气机查表溯源链
├── rebuild_hexe_compressor_lookup.m
├── activate_traceable_compressor_lookup.m
├── apply_compressor_corrected_coordinates.m
├── compressor_corrected_coordinates.m
├── tmx2269_predict_speed_line.m
├── tmx2269_similarity_transform.m
│
├── solve_paper52_operating_point.m       # 论文 §5.2 设计点/功率平衡求解
├── apply_paper52_generator_load.m
│
├── data/provenance/compressor_map/       # 压气机查表数据溯源（数字化点、标定、SHA-256）
├── sources/                              # NASA 参考报告 PDF（压气机、性能相关）
├── tools/nasa_tn_d7487/                  # NASA TN D-7487 算法的可运行 Python 复现
│
├── tests/                         # 探索区：MATLAB/Python 单元与审计测试
│
└── docs/
    ├── MODEL_MAP.md                # 模型结构、信号流、论文-实现对应关系
    ├── STATUS.md                   # 当前进度与阻塞点（只读审计）
    ├── PLAN.md                     # 分阶段后续计划
    └── superpowers/                # 具体子任务的计划与设计文档
```

---

## 数据溯源

压气机变工况模型的来源经过专门审计，记录在 `data/provenance/compressor_map/`：

- 离心压气机变工况算法采用 Michael R. Galvas, *FORTRAN Program for Predicting
  Off-Design Performance of Centrifugal Compressors*, NASA TN D-7487, 1973
  （论文参考文献 [162]）。仓库中同时保留原始提供的 FORTRAN/Python 实现快照
  （`data/provenance/compressor_map/nasa_tn_d7487/original/`）与仓库内可运行的
  独立复现（`tools/nasa_tn_d7487/compressor_program.py`），并用 SHA-256 校验和
  区分两者，避免"修正实现"覆盖"原始证据快照"。
- 压气机几何与设计工况的自洽性核对见 `压气机几何自洽说明_论文级.md`：论文
  1 MWe 单轴方案的设计转速为 55090 rpm，据此修正了查表中曾经错误的
  `N_design = 18732 rpm`。
- `图5_34_对比分析_14000s.md` 记录了针对论文图 5.34（变反应性工况）的一次
  14000 s 动态仿真与论文曲线的对比分析。

`sources/` 目录下另有若干与压气机/涡轮性能相关的 NASA 技术报告 PDF，作为
建模依据的原始出处保存。

---

## 已知风险与待确认事项

摘自 `docs/MODEL_MAP.md` 的可疑项清单，供后续工作参考：

1. 正式模型含 4 个 Assertion、多个 Scope、12 个 Display，哪些属于正式交付
   输出、哪些只是调试用途，需要逐块判定。
2. 主回路中两个 `Unit Delay`（分别位于压缩机出口压力、TAC 质量流量到
   recuperator 的路径上）的数值依据和动态副作用尚未确认。
3. 反应堆模型中的冷却剂反应性系数 `alphac = -8.35e-6` 目前找不到明确的论文
   对应公式，已列为需要人工确认的事项。
4. 压气机候选查表的"未激活"元数据（`candidate_status`）与 `start.m` 实际
   无条件加载该表的行为不一致。
5. `radiator_table.mat` 中混有多余的 `out`（`Simulink.SimulationOutput`）和
   `ans` 字段，且变量名 `version` 可能遮蔽 MATLAB 内置函数 `version()`，
   存在工作区污染风险。
6. 尚未找到符合正式命名规则的 Step 0 时间戳备份
   （`final_dynamic_24a_backup_YYYYMMDD_HHMMSS.slx`）；现有的 `.original` /
   `.bak` 文件能否替代，尚未确认。

以上事项按 `AGENTS.md` 第 10 节，均属于"不能被自动化代理擅自决定"的人工确认门。

---

## 后续计划

按 `docs/PLAN.md`，下一阶段的两项优先工作是：

1. 在探索区（`tests/`、`tmp/`）复现并定位 4.437 s 处的压气机修正流量越界，
   区分是查表域问题、上游热力状态问题，还是代数环/初始化问题。
2. 在无负荷/无反应性扰动条件下，建立与论文表 5.2 对应的单一设计点稳态基线。

在此之前不建议直接进行动态曲线拟合，或修改验收标准以让结果"看起来更接近论文"。
