# 空间锂冷堆 He-Xe 布雷顿循环复现项目

✅ 目录入口更新：2026-09-07。本项目研究徐驰《空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析》。最终目标是第 5.4 节启动与变工况响应复现；当前工作聚焦图 5.18/5.19 的稳态及能量链诊断，**整机复现未完成**。

## 从这里开始

| 需要了解什么 | 入口 |
|---|---|
| 当前做到哪里、哪些结论仍有缺口、下一步 | [当前状态](docs/STATUS.md) |
| 基线、候选、失败记录和历史报告在哪里 | [实验与文档索引](docs/README.md) |
| 同名模型如何区分 | [模型路径与 SHA-256 清单](docs/model_inventory.tsv) |
| tmp 中各目录的规模和引用 | [实验目录清单](docs/experiment_inventory.tsv) |
| 主论文、NASA 与其他参考资料 | [文献统一入口](sources/README.md) |
| 如何备份、换目录恢复及检查证据 | [恢复与可移植性说明](docs/RECOVERY.md) |
| 自动化任务的执行边界 | [AGENTS.md](AGENTS.md) |

## 当前模型与运行入口

✅ 根目录当前模型为 [final_steady_24a.slx](final_steady_24a.slx)，SHA-256：

```text
31745b6487234b64938f9b61131910599db75a1b53e3d1099b8585d0b7b4e8aa
```

✅ 根目录目前没有 `final_dynamic_24a.slx` 或 `run_dynamic.m`。前者是最终交付目标名；历史目录里的同名文件不代表当前动态交付版本。旧 README 的 `run_dynamic` 快速开始和 8 月 18 日失败状态已不适合作为当前入口。

✅ 已有稳态诊断运行器为 [run_steady53_case.m](tests/steady53/run_steady53_case.m)。它接收模型绝对路径、仿真终止时间等参数，使用 [f8bcd83 冻结运行依赖](data/provenance/baselines/f8bcd83/runtime/)，不保存源模型。根目录 [start.m](start.m) 加载的是根目录查表；二者不能默认视为相同运行环境。

✅ 查看现有结果无需启动 MATLAB：

- [14000 秒运行状态](.worktrees/rotating-map-candidate-a/tmp/final_steady_speed55090_formal_20260902/run_status.json)
- [原始 MAT](.worktrees/rotating-map-candidate-a/tmp/final_steady_speed55090_formal_20260902/result.mat) 与 [导出信号 CSV](.worktrees/rotating-map-candidate-a/tmp/final_steady_speed55090_formal_20260902/signals.csv)
- [图 5.18/5.19 对齐诊断](docs/2026-09-05-steady14000-readonly-energy-diagnostic.md)

⚠️ 该 14000 秒运行是已有暖态诊断，不能当作第 5.4 节六阶段冷启动。其 CSV 存在多速率信号对齐限制；短程对照另用固定更新协议，详见当前状态页。这里提供代码和证据入口，不把未经本轮重跑的命令写成“一键复现通过”。

## 目录用途

| 位置 | 内容 | 使用说明 |
|---|---|---|
| 根目录 `.slx / .m / .mat` | 当前稳态模型及脚本、物性、查表 | 运行依赖还须按具体运行器核对 |
| 根目录规则文档 | 执行、物理边界与验收要求 | 当前状态页不能覆盖这些规则 |
| 根目录 PDF、提取文本 | 主论文及部分参考资料 | 暂保留路径，避免破坏出处链接 |
| [docs/](docs/README.md) | 状态入口、诊断报告、历史计划 | 按索引查找，不按文件新旧直接判定结论有效性 |
| [data/provenance/](data/provenance/) | 冻结基线、查表与其他来源材料 | 是证据与部分运行依赖，不是缓存 |
| [sources/](sources/) | NASA 参考报告 | 原版与 repaired 版保留来源区别 |
| [tests/](tests/) | 审计、测试、诊断与实验运行脚本 | 部分脚本会创建或运行探索模型，勿批量执行所有脚本 |
| [tools/](tools/) | 数字化及参考算法工具 | 不等于作者原查表生成程序 |
| [tmp/](tmp/) | 实验副本、原始输出、验证结果及缓存 | 混有重要证据，不能按目录名整体清空 |
| [.worktrees/](.worktrees/) | 本地 Git 工作区及运行结果 | 当前 14000 秒证据位于其中 |
| [output/](output/) | 文献提取等生成产物 | 归档前核对引用 |
| `slprj/`、`*.slxc` | Simulink 生成缓存 | 与原始结果分开识别 |

✅ `tmp/`、`output/`、`.worktrees/` 被 [.gitignore](.gitignore) 排除。当前本机有这些文件，不表示仅克隆 Git 仓库便能获得全部证据。搬动或清理前，先核对实验索引、脚本硬编码路径和工作区关系。

## 正式规则

- [决策自律准则](决策自律准则.md)：✅ 已核实、⚠️ 沿用未复验、❓ 推断或计算、❌ 无依据。
- [交付边界约束 v4](交付边界约束_v4.md)：探索区与交付区、允许的物理耦合、正式修改及批准边界。
- [论文第 5.4 节验收标准](验收标准_论文5.4.md)：目标值、未定容差及论文内部矛盾。

✅ 2026-09-07 已更新入口、模型与实验目录清单，并将 3,277 个生成缓存文件压缩备份后移出原位置，详见 [整理与恢复说明](docs/README.md)。模型、物性、查表、运行器与验收标准未改动。后续实验应先阅读 [当前状态](docs/STATUS.md)，沿用已有授权，涉及正式模型或物理假设的决定仍遵守上述规则。
