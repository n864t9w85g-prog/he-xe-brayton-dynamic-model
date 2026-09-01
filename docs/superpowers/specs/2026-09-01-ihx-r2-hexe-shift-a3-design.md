# IHX 第二区 He-Xe 热状态一致平移 A3 实验设计

## 1. 状态与权限边界

本文件固化用户已逐段批准的实验设计，但**不构成执行授权**。在书面规格经用户复核、实施计划另行批准、A3 单次正式运行再次获批之前，不得生成正式候选、调用 `sim`、修改正式模型或执行 500 s 仿真。

命名说明：用户选择的“方案 A1”是本设计中的锚点方案；`A3` 是继既有 A1/A2 正式尝试之后的时间序列 attempt 标识，二者不是同一编号体系。A3 的固定 `attempt_id` 为 `20260901_A3`。

本实验属于探索区单自由度反事实。它只回答：

> 在冻结的 `final_steady_24a` 基线上，以论文图 5.18(a) 起点约 1200 K 为视觉代理，对 IHX 第二区两个 He-Xe 热状态施加同一温度平移，是否足以使论文图 5.19 的四条功率曲线通过预声明的方向与非平坦门？

它不识别作者完整初态，不证明 1200 K 是作者精确初值，不复现论文，不授权 14000 s 延长，也不允许正式模型晋升。

## 2. 冻结证据与证据等级

### 2.1 模型与目标路径

✅ 冻结源模型为：

- `data/provenance/baselines/f8bcd83/final_steady_24a.slx`
- SHA-256：`0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`

✅ `data/provenance/steady53/fig5_19/initialization_audit.json` 记录目标状态及当前初值：

- `final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator`：`1245.8184669844006 K`
- `final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator`：`1393.6037139151003 K`

✅ 同一审计文件中的官方 API 影响图记录：这两个状态均有路径到 `TAC/Turbine` 输出 4 和 `TAC/WT_sw`；论文口径电功率是该透平路径与已验证压气机路径的离线组合。没有直接发电机信号。

### 2.2 1200 K 锚点

✅ 论文 PDF：

- `空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf`
- SHA-256：`983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a`
- 图 5.18(a)：PDF 第 105 页、印刷页 90

✅ 当前只读页面图像 `tmp/steady53_recheck_20260827/paper-105.png` 的 SHA-256 为 `da9e9a536d0dda98152fa694d942b393ca2f5f5d10b720dbd79692ac694cc95c`。实施前必须将该固定页面和来源说明发布到耐久溯源目录，不能让候选值只依赖 `tmp/`。

❓ 图 5.18(a) 中三个 IHX 温度在 `t≈0` 附近从约 1200 K 起升。`1200 K` 只能使用身份：

`figure_5_18a_t0_visual_proxy_not_author_initial_state`

该值是扫描图读代理，不是论文文字给出的精确作者初值；不得缩写为 `author_t0`、`paper_initial_condition` 或类似名称。

### 2.3 已有探索材料的边界

✅ `tests/run_ihx_initial_state_diagnostic.m` 和相关 `tmp/` 结果曾用“全部十个 IHX 热状态均为 1200 K”做过部件级诊断。该实验改变十个状态、使用部件 harness，不能替代本 A3 整机双状态单自由度实验，也不能作为 A3 成功证据。

## 3. 单自由度候选定义

### 3.1 唯一标量

候选只允许一个独立标量：

```text
anchor_K = 1200.0000000000000
delta_T_K = anchor_K - old_T_c2_out_K
          = -193.6037139151003
```

### 3.2 两个从属状态变化

同一 `delta_T_K` 同时作用于两个状态：

| 状态 | 修改前 / K | 修改后 / K |
|---|---:|---:|
| `IHX/IHX_region_2/T_c1_average_Integrator` | 1245.8184669844006 | 1052.2147530693003 |
| `IHX/IHX_region_2/T_c2_out_Integrator` | 1393.6037139151003 | 1200.0000000000000 |

修改前后两状态差值都必须为 `147.7852469306997 K`。候选审计必须验证两个新值均由同一个 `delta_T_K` 算出，禁止把它们当成两个独立可调参数。

### 3.3 精确变更集

候选允许且只允许上述两个 `InitialCondition` 字段变化：

- 其余 38 个连续状态初值逐项不变；
- solver 参数、模型配置、拓扑、端口、信号线、mask、workspace、runtime 依赖逐项不变；
- 正式 SLX、正式 MAT、`HeXe_property_simulink.m`、`Lithium_property_simulink.m` 不变；
- 不增加控制器、校正反馈、限幅、滤波、时移、拟合效率或状态回注；
- 不直接修改 SLX/XML，候选生成只走 MATLAB/Simulink 官方 API。

若任何额外差异出现，候选生成失败，不能进入正式运行门。

## 4. 执行架构

### 4.1 零仿真预检

预检不得调用 `sim`，必须完成：

1. 验证冻结源模型、runtime、A1/A2 历史和 34 项保护身份；
2. 验证 A3 目标目录不存在；
3. 在临时目录通过官方 API 生成候选、更新模型图并关闭模型；
4. 证明精确变更集只有两个 IC，且二者共享一个 `delta_T_K`；
5. 验证 40 状态清单、37 项 solver 合同、拓扑指纹及依赖身份；
6. 验证 runner 只有一次阻塞式模型调用且没有重试路径；
7. 正常 Python 与 `python -O` 使用相同不可绕过的验证合同。

### 4.2 同期执行快照

正式命令之前必须把所有实际执行字节冻结到只读 capture，并建立 SHA-256 清单，至少包括：

- A3 预检/one-shot 执行器；
- 候选生成器；
- 顶层 runner；
- `run_steady53_case.m`；
- `steady53_signal_manifest.m`；
- `reset_steady53_property_warning_state.m`；
- 离线分析器；
- 精确命令文本、Git HEAD、tracked diff、untracked 路径清单；
- 来源页面、论文点、基线、signal contract 与初始化审计的身份。

正式命令必须从已捕获的脚本副本执行，不能只记录 live 工作树路径。这样 A3 不再依赖 A2 的 `post_hoc_git_inference` 式 helper 身份推断。

### 4.3 单次执行

获得用户明确的“A3 单次正式运行批准”后：

- 只允许一个 formal command invocation；
- `run_steady53_case` 调用次数最多且必须恰为 1，才能形成完成的科学结果；
- `retry_count = 0`；
- StopTime 固定为 `500 s`；
- Python one-shot 执行器记录 UTC、单调时钟、stdout、stderr、退出码和调用计数；
- 正式命令一旦发出就消耗该 attempt，即使在模型积分前失败也不得自动补跑。

## 5. 信号与科学判据

### 5.1 固定信号定义

四条功率定义继续使用已发布的 `data/provenance/steady53/fig5_19/signal_contract.json`：

- 反应堆功率：`P_sw`；
- 透平功率：`WT_sw`；
- 压气机功率：`Wc_sw`；
- 论文口径电功率：离线计算 `0.98 * (WT_sw - Wc_sw)`。

历史 `0.96527` 指标只可作为明确标注的历史诊断，不能替代论文口径。

### 5.2 数值与物理门

候选必须：

- 无模型错误、断言或物性越界；
- 精确到达 `500 s`；
- raw、四条功率曲线和两个目标状态全部有限；
- 时间向量严格递增并覆盖分析窗口；
- 运行前后候选、依赖和保护身份不变；
- 不依赖 `tests/` 或 `tmp/` 中未被 capture 的 live 执行字节。

### 5.3 四面板方向门

方向算法、论文点和扫描容差必须复用 A2 已锁定实现，不得为 A3 调参。要求：

| 面板 | 论文方向序列 |
|---|---|
| 反应堆 | `[fall]` |
| 透平 | `[rise]` |
| 压气机 | `[fall, rise]` |
| 论文口径电功率 | `[rise, fall]` |

必须四条全部匹配，不能只凭直接受影响的透平/电功率两条判“未被证伪”。

### 5.4 四面板非平坦门

沿用“候选峰峰值大于等于原基线噪声峰峰值的 10 倍”：

| 曲线 | 固定阈值 / W |
|---|---:|
| 反应堆 | 0.5141158541664481 |
| 透平 | 1.609319536946714 |
| 压气机 | 2.2659989586099982 |
| 论文口径电功率 | 3.7926344096194953 |

四条必须全部通过。RMSE、起末误差、峰谷值和峰谷时刻只作预声明报告量，不设置事后“最佳候选”或拟合阈值。

## 6. 结论状态机

科学结论只能是：

1. `ihx_r2_hexe_shift_alone_falsified`
   - 数值门通过，但至少一个方向门或非平坦门失败。
2. `ihx_r2_hexe_shift_alone_not_falsified_but_not_validated`
   - 数值门、四方向门和四非平坦门全部通过；仍没有独立作者初态证据。
3. `numerical_or_physical_gate_failed`
   - 数值门未通过；另记录 `pre_simulation_infrastructure`、`compile`、`property_domain`、`model_runtime`、`incomplete_output` 等实际子类。

任何分支都必须保持：

```text
paper_reproduced = false
author_initial_state_identified = false
formal_promotion = false
```

不得以 RMSE 改善、局部方向改善或成功运行作为模型正确性的充分证据。

## 7. 证据发布与历史

### 7.1 耐久证据

新的耐久目录建议为：

`data/provenance/steady53/fig5_19/ihx_r2_hexe_shift_A3/`

必须保存：

- 图 5.18(a) 固定来源页面与 provenance；
- 候选补丁审计；
- 同期执行字节与 SHA-256 清单；
- 命令、stdout、stderr、退出码、计数和时间记录；
- 实际生成的 raw MAT、reference/candidate CSV；若正式尝试在生成它们之前失败，必须明确记录缺失原因，禁止伪造占位 raw 或曲线；
- 离线分析 JSON 和机器可读结论。

候选 SLX 可留在探索区，但耐久补丁审计必须足以证明精确变更集。耐久目录不得包含可被正式模型运行时引用的补丁或控制逻辑。

### 7.2 追加历史

现有 `reactor_ic_counterfactual.json` 继续作为 A1/A2 反应堆初值档案，不改写其科学内容。A3 应建立跨状态族的 `initial_state_counterfactual_history.json`：

- 引用 A1/A2 canonical summary SHA；
- 追加 A3 attempt 和结论；
- 使用 manifest-last、可恢复、verify-only 不写入的事务；
- 不覆盖 A1/A2 工件或把旧失败改写成成功。

## 8. 测试与验收

实施必须采用 TDD，至少覆盖：

- 1200 K 锚点身份和精确十进制计算；
- 单一 `delta_T_K` 推导两个 IC；
- 仅两个 IC 变化、其余 38 状态不变；
- solver、拓扑、runtime、MAT、property、34 项保护不变；
- 正常与 `python -O` 合同等价；
- 无仿真 candidate API 临时生成；
- capture 覆盖全部实际执行依赖且正式命令只从 capture 调用；
- exact-once、无重试、失败即停；
- 三种枚举机械判定及三项晋升标志恒为 false；
- raw 和 manifest 哈希、append-only 历史、崩溃恢复与 verify-only 无写入；
- 完整现有 101 项 Python 回归、相关 MATLAB 无仿真测试、34/34 保护门、`git diff --check` 与正式文件零差异。

## 9. 明确停止条件

本设计只包含一个锚点、一个标量和一次 500 s 运行。禁止自动执行：

- 第二个温度锚点；
- 参数包络或批量扫描；
- 独立调整两个目标状态；
- 14000 s 延长；
- 正式模型修改或候选晋升。

若 A3 未被证伪，也必须先寻找独立初态来源并取得新批准。若 A3 被证伪，则回到已测影响图选择下一个状态族，重新走书面规格批准流程。
