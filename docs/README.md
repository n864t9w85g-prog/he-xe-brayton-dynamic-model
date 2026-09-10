# 实验与文档索引

✅ 2026-09-07 核对路径并建立索引；本页不重新验证历史实验。返回 [项目入口](../README.md) · [当前状态与下一步](STATUS.md)。

## 先分清模型与运行身份

✅ [模型清单](model_inventory.tsv)记录本项目目录内 88 个 SLX 的相对路径、SHA-256、与根模型是否字节相同及证据角色。清单不包含本项目目录外的其他 Git 工作区。只有明确核对的模型标记具体角色，其余仅按位置登记为待核实；“同名”或“同哈希”都不证明运行依赖、初态、输入和求解设置相同。

| 类型 | 入口 | 状态或限制 |
|---|---|---|
| 当前根模型 | [final_steady_24a.slx](../final_steady_24a.slx) | ✅ 当前源文件；并非已验收交付物 |
| 当前 14000 秒证据 | [2026-09-02 结果目录](../.worktrees/rotating-map-candidate-a/tmp/final_steady_speed55090_formal_20260902/) | ✅ 原始 MAT、CSV、状态存在；使用冻结运行依赖 |
| 历史冻结快照与运行依赖 | [f8bcd83 说明](../data/provenance/baselines/f8bcd83/README.md)、[清单](../data/provenance/baselines/f8bcd83/baseline_manifest.csv)、[runtime](../data/provenance/baselines/f8bcd83/runtime/) | ✅ 来源材料与当前诊断依赖；历史 SLX 不等于当前源模型 |
| 固定协议短程对照 | [500/1000 秒探索目录](../tmp/fixed_protocol_prefix_20260906/) | ✅ 状态文件记录成功，供最新候选比较 |
| 最新反应堆候选 | [探索目录](../tmp/reactor_shared_heat_20260906/)、[报告](2026-09-06-reactor-shared-heat-candidate.md) | ✅ 单项 500 秒探索；未进入根模型 |
| 历史 NaK 候选 | [探索目录](../tmp/nak_enthalpy_ORtGWO/)、[旧规格](../tests/nak_enthalpy_candidate_plan_20260829.md) | ⚠️ 旧来源模型上的结果，移植前复核；不是当前候选已通过 |
| 历史 NaK 工装失败 | [首次目录](../tmp/nak_enthalpy_0dmtnO/) | ⚠️ 旧报告第 35.3 节记载仿真前重复连线失败；不是物理模型失败 |
| 其余历史模型 | [模型清单](model_inventory.tsv) | ⚠️ 本轮只核路径和哈希，未逐一审阅物理内容或决定去留 |

## 当前诊断主线

下表说明报告用途；报告里的数值与结论保留其原证据等级，不因列入索引而升级。

| 顺序/主题 | 报告 | 阅读用途 |
|---|---|---|
| 1. 对齐论文 | [14000 秒只读诊断](2026-09-05-steady14000-readonly-energy-diagnostic.md) | 基线身份、图 5.18/5.19、第一处内部失配 |
| 2. 上游 | [反应堆—IHX 瞬态收支](2026-09-06-reactor-ihx-transient-budget.md) | 区分内部差额、流体携热和储热 |
| 3. 下游 | [预冷器与散热器](2026-09-06-downstream-energy-budget.md) | NaK 和 He-Xe 各段热量口径 |
| 4. 总账 | [全链条汇总](2026-09-06-whole-chain-readonly-budget.md) | 末点余额分解；早期记录限制须结合后续报告 |
| 5. 记录纠正 | [流量对齐](2026-09-06-flow-alignment-diagnostic.md) | 后续证据解释旧报告中部分早期功率复算假差 |
| 6. 运行协议 | [StopTime 与采样耦合](2026-09-06-sampling-stop-time-coupling.md)、[固定协议对照](2026-09-06-fixed-protocol-prefix-check.md) | 避免把不同离散更新协议当作公平短长程比较 |
| 7. 反应堆局部候选 | [反应堆统一热量](2026-09-06-reactor-shared-heat-candidate.md) | 单项结果、剩余差额与交付限制 |
| 8. 当前 NaK 独立候选 | [固定协议 NaK 对照](2026-09-07-nak-fixed-protocol-candidate.md) | 旧证据复核、单项 500 秒结果及剩余约 17 kW 全链余额 |

| 9. 两个出口合并与剩余账项 | [合并对照与离线分解](2026-09-07-combined-outlets-budget.md) | 500 秒交互检查、约 97 W 净额中的正负抵消及证据边界 |

✅ [建模取舍 D01](DECISIONS.md)已获批并完成一次500秒未缩放Li物性对照；局部检查通过，论文偏差仍在，未晋升。

✅ [D02结果](DECISIONS.md)已完成：仅燃料温度反馈单参数整机对照，未晋升。

## 支撑报告与未决来源

| 主题 | 入口 |
|---|---|
| 反应堆参数出处 | [参数溯源](2026-09-06-reactor-parameter-provenance.md)、[热约束](2026-09-06-reactor-thermal-constraints.md) |
| 液锂与功率定义 | [物性来源及定义](2026-09-06-li-property-and-power-definitions.md)、[能量闭合范围](2026-09-06-reactor-energy-closure-scope.md) |
| 早期单项试探 | [系数局部检查](2026-09-06-reactor-coefficient-local-check.md)、[温度反馈局部检查](2026-09-06-reactor-feedback-local-check.md) |
| 压气机与透平原表 | [旋转机械根因审计](2026-09-02-rotating-machinery-map-rootcause.md)、[证据矩阵](2026-09-02-steady53-rootcause-evidence-matrix.md) |
| 指令修订记录 | [2026-09-06 修订说明](2026-09-06-instruction-revision.md)；实际执行以根目录正式规则为准 |

⚠️ 早期单项试探、历史“下一步”和未晋升候选均保留为记录，不能直接作为当前实施结论。新报告只修正明确对应的旧主张，不整篇推翻历史记录。

## 历史报告与计划

| 内容 | 入口 | 查阅提示 |
|---|---|---|
| 长篇部件与整机实验日志 | [steady53_curve_recheck_20260828.md](steady53_curve_recheck_20260828.md) | 第 34 节预冷器、35 节 NaK 候选、36–38 节 NaK/散热器来源；先核其来源模型 |
| 早期稳态验证与候选比较 | [验证](steady_validation_20260824.md)、[候选比较](steady53_candidate_comparison.md) | 历史配置，不能替代当前 14000 秒证据 |
| 图 5.19 进展与合并 | [进展](steady53_fig519_progress_20260831.md)、[合并结果](2026-09-01-steady53-lineage-merge-result.md) | 历史链路演进 |
| 散热器 A1 | [结果](radiator_A1_results_20260830.md) | 单项候选记录 |
| 重启与清理溯源 | [基线审计](restart_baseline_audit_20260824.md)、[候选分类](restart_class3_candidates_20260824.md)、[文件分类](restart_file_classification_20260824.tsv)、[清理恢复审计](cleanup_recovery_audit_20260831.md) | 搬动或删除材料前查阅，不能当作新的删除授权 |
| 旧设计与实施计划 | [superpowers/](superpowers/) | 计划状态须与 STATUS.md 和实际产物核对 |

## 整理边界与后续维护

✅ 本轮保留实验和文献原路径，并将已核对的生成缓存压缩备份后从原位置移除，具体结果见下节。后续已完成全部 155 个条目的材料类型和留存决定登记，文献从 [统一入口](../sources/README.md)查找，完整本地快照按 [恢复说明](RECOVERY.md)使用。以下材料不按“临时”或“失败”字样直接删除：

- 原始运行结果、模型副本、输入身份、独立验证结果与来源 PDF。
- 冻结 runtime、备份及工作区；[旧 NaK 运行器](../tests/run_nak_enthalpy_candidate.m)还硬编码引用其他 tmp 子目录。
- 状态失败的实验目录：失败记录可能用于区分脚本问题与物理问题。

✅ 本次归档决定是：当前及历史证据按原路径收进完整快照；测试工装样本单独标识并保留；空目录记录身份；可再生缓存按下节收起。原版与 repaired PDF、同哈希 SLX 不因表面重复删除。各条目的材料类型来自现有文件，保存状态与科学结论分开，不把目录整理扩大成逐个物理候选的重新验收。

## 2026-09-07 缓存整理与实验目录盘点

✅ [实验目录清单](experiment_inventory.tsv)覆盖 tmp 下 155 个非隐藏一级条目，列出缓存清理后的文件数、字节数、模型数、材料类型、留存决定、已保存状态及初次扫描的文本引用位置。其中 87 个条目在初次 docs/tests/tools/data 扫描中有名称匹配；该匹配是保守查找线索，未匹配不代表没有动态路径、二进制引用或外部任务引用，不能作为删除许可。

✅ 对根目录、tests、tools 与部分 tmp 中的标准生成缓存完成可恢复清理：3,277 个文件，原始总量 18,429,593 字节，压缩包 13,020,282 字节。保留 manifest 和恢复工具，因此实际净节省小于两者之差。主要收益是减少散落文件，不是大幅释放磁盘空间。

✅ 清理范围为 slprj、__pycache__、.pytest_cache、SLXC 与 Finder 元数据；候选均不受 Git 跟踪，操作前未发现运行中的 MATLAB。冻结 data、sources、.worktrees、source_f8bcd83 快照、pydeps 与恢复的透平程序包均排除。没有以 MAT 后缀整体删除数据，移除的 MAT 均位于生成缓存目录内。

✅ [备份与清理清单](../output/maintenance/cache_cleanup_20260907/manifest.json)、[缓存压缩包](../output/maintenance/cache_cleanup_20260907/cache_backup.zip)、[恢复脚本](../output/maintenance/cache_cleanup_20260907/restore_cache.py)保存在 output/maintenance。删除前逐项核对压缩内容的 SHA-256，并在独立临时目录实际恢复全部文件后核对哈希；重复恢复不会覆盖不同内容。备份位于 Git 忽略目录，不能随 output 一起清空。

在项目根目录运行下列命令可只校验备份；加 --restore 才恢复原路径。目标已有不同内容时会停止，防止覆盖后来新生成的缓存。

```sh
python3 output/maintenance/cache_cleanup_20260907/restore_cache.py
python3 output/maintenance/cache_cleanup_20260907/restore_cache.py --restore
```

✅ 模型、物性、查表、原始实验结果、规则与文献保持原路径和内容。历史报告仍有脚本硬编码引用，例如 tests/digitize_fig519.py 引用图 5.19 进度报告，tests/summarize_radiator_a1.py 输出散热器 A1 报告；未迁移这些文件。阶段报告已统一增加时点说明，98 处绑定本机的文档导航改为相对链接。详细恢复范围见 [恢复说明](RECOVERY.md)；这些整理不构成模型验收通过结论。

## 文件整理后的新增实验

✅ 2026-09-07 新增 [NaK 固定协议候选](2026-09-07-nak-fixed-protocol-candidate.md)，当前 tmp 清单增至 156 项、模型清单增至 85 项。前述 155 项与完整恢复包是文件整理完成时的快照，不随新实验改写旧归档。新增证据及更新的导航文件另存 [增量资料目录](../output/maintenance/nak_fixed_protocol_20260907/)。
