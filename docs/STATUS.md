# 项目状态（首次只读审计）

审计日期：2026-08-18。状态结论不是交付验收结论；项目未完成，本轮审计后停止开发。

## 1. Baseline

### 环境和入口

- MATLAB：`25.1.0.2943329 (R2025a)`；Simulink：`25.1`。
- 入口：`run_dynamic.m`；其第 11 行执行 `start.m`，第 25-27 行加载负荷/反应性时序，第 40-41 行将 StopTime 设为 14000 s 并调用 `sim(mdl)`。
- 求解器：`ode15s`，variable-step；`RelTol=1e-3`、`AbsTol=1e-6`，MaxStep/MinStep 为 auto；模型 callbacks 为空。

### 实跑结果

✅ 模型可加载并完成编译；编译报告发现 1 个跨 `Turbine -> recuperator -> precooler -> Compressor` 的代数环。  
⚠️ 运行约在 `t=4.43696 s` 提前终止，错误 ID 为 `Simulink:blocks:AssertionAssert`，失败块为 `final_dynamic_24a/TAC/Compressor/Corrected_Coordinates/FlowBelowMaximum_Assertion`。该 Assertion 报告修正流量超过活动表上界 `m_ratio_bp(end)=1.05358561168551`。  
⚠️ 编译/运行同时出现 `final_dynamic_24a/TAC/Turbine/Product3` 除零警告。因仿真提前终止，不能确认完整轨迹是否含 NaN/Inf。  
✅ 失败后模型保持 `Dirty=off`；本轮没有禁用断言、改变求解器或修改模型配置。

因此准确 baseline 表述是：

> 当前 `run_dynamic.m` 入口 baseline 无法运行到 14000 s，在 4.43696 s 因压气机修正流量上界断言失败。

这不是论文单独验收场景的成功/失败判定，因为该入口同时施加负荷和反应性 schedule，且没有实现论文 5.4.1 的六阶段冷启动调度。

## 2. 当前运行状态与论文启动状态的差异

当前活动模型积分器已含热态初值：堆功率约 `3135923.945487 W`、燃料温度约 `1742.645982 K`、六组先驱核浓度及换热器/辐射器热态；转子初值为 `55090 rpm`。历史 `.slx.original` 则有反应堆积分器 `225 K` 冷态和转子 `64500 rpm` 等不同值。

❌ 因此当前活动模型不能直接宣称复现论文 §5.4.1 的 `1 W / 225 K / 0 rpm` 冷启动。`run_dynamic.m` 也没有论文要求的六阶段锂流量和 TAC 启动判据调度。

## 3. 局部验证结果

✅ MATLAB 局部测试新鲜运行 `8/8 PASS`：

- `test_paper54_constants`
- `test_paper54_schedules`
- `test_paper52_power_balance`
- `test_traceable_activation_gate`
- `test_compressor_corrected_coordinates_model`
- `test_compressor_map_provenance`
- `test_tmx2269_similarity`
- `test_tmx2269_speed_extension`

✅ Python 现有测试用标准库运行 `6/6 PASS`（`python3 -m unittest discover -s tests -p 'test_*.py' -v`）。  
⚠️ `pytest` 未安装；没有安装新依赖。上述测试只覆盖来源审计、候选压气机表、常数/时序和局部功率平衡，不覆盖整机动态成功。

## 4. 压气机工作假设复核

| 检查项 | 当前活动文件 | 历史备份/论文对照 | 结论 |
|---|---|---|---|
| `N_design` | `55090` | `hexe_compressor_lookup.mat.bak` 为 `18732.4558377844` | ✅ 历史“曾为 18732 且不覆盖 55090”已验证；❌ 不能说当前仍为 18732 |
| 速度断点 | `0.9:0.01:1.1` 倍 `55090`，即约 `49581-60599 rpm` | 历史备份约 `5619.7-21542.3 rpm` | ✅ 当前断点覆盖 55090；历史断点不覆盖 |
| 设计 PR | `2.35714285714286` | 论文表 5.2：`1.551/0.658=2.357142857` | ✅ 与表 5.2 一致 |
| 表版本 | `4.0-nasa-tmx2269-candidate` | 元数据 `candidate_status='not active until all gates pass'` | ❓ 门禁声明与 `start.m` 无条件加载的实际状态矛盾 |

结论：`AGENTS.md` 中“当前活动表仍为 PR=2.357、N_design=18732、断点不覆盖 55090”这一组合不成立。可验证的是历史备份问题；当前整机越界是否由表造成，仍需探索区实验，不能称唯一根因。

## 5. 证据和风险分级

- ✅ 已核实：模型顶层结构、MATLAB/Simulink 版本、求解器、baseline 失败时间/块/错误、当前活动表速度域、表 5.2 PR、局部测试结果、无直接 `tests/`/`tmp/` 入口引用。
- ⚠️ 历史未复验：更早审计记录、`.original`/`.bak` 产生过程、旧动态结果文件；它们只能作为历史证据。
- ❓ 推断：压气机修正流量越界与动态偏差的因果关系、Unit Delay 的必要性、两区离散是否足够、`alphac` 是否为论文允许机制。
- ❌ 当前证据不支持：已完成论文 5.4 全部工况、当前 baseline 可运行到 14000 s、PR 必须约为 1.92、压气机表已被证明是唯一根因。

## 6. 当前最关键风险

1. 模型在 4.43696 s 失败，无法产生完整验收轨迹。
2. 当前入口不是冷启动六阶段场景，初值和输入调度与 §5.4.1 不同。
3. 压气机候选表的“未激活”元数据与实际加载冲突，且修正流量超出上界。
4. `alphac`、Unit Delay、Assertion/Scope/Display 的正式边界和出处尚未逐块确认。
5. Git 无 commit，且未找到正式命名的 Step 0 时间戳备份。

## 7. 审计边界

本轮未修改任何 `.slx`、`.m`、`.py`、`.mat`、规则、验收标准或现有输出。仅允许新增本目录下的 `docs/MODEL_MAP.md`、`docs/STATUS.md`、`docs/PLAN.md`。

