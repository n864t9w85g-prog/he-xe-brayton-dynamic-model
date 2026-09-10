# 本地恢复与可移植性

返回 [项目入口](../README.md) · [当前状态](STATUS.md) · [材料索引](README.md)。

## 包含什么

恢复包位于 [output/maintenance/project_recovery_20260907/](../output/maintenance/project_recovery_20260907/)。它是本地恢复材料，未上传外部服务，不能代替异地备份。

- project.zip：打包时本项目目录内的当前文件，包括 Git 未跟踪及忽略的 tmp、output、内部 .worktrees 证据。保留相对路径，不只保留“看起来成功”的实验。
- history.bundle：Git 的可达分支和标签历史；不改变当前提交、分支或未提交工作。
- manifest.json：每个文件的路径、大小、SHA-256、模式、时间和打包时 HEAD。文件清单以它为准。
- before_document_edits.zip：本轮修改前的 README 与 docs 原文，保留历史报告的原始字节版本。
- restore_project.py：独立恢复工具，内容与项目中的 project_bundle.py 相同。
- verification.json：实际恢复检查的范围和结果。只证明文件恢复及所列核查，不表示新仿真通过。

Git 管理目录 .git 和恢复包自身不递归放入 project.zip；Git 可达历史由 bundle 单独保留。恢复工具会将整个恢复包复制到新目录的相同相对位置，便于文档继续找到清单和验证记录。

## 当前电脑与新位置如何使用

在项目根目录运行，先核对整个包，再恢复到一个**不存在的新目录**：

```sh
python3 tools/maintenance/project_bundle.py verify --package output/maintenance/project_recovery_20260907
python3 tools/maintenance/project_bundle.py restore --package output/maintenance/project_recovery_20260907 --destination ../HeXe-restored
```

若只带走恢复包，可在包所在目录运行：

```sh
python3 restore_project.py restore --package . --destination ../HeXe-restored
```

恢复需要 Python 标准库和 Git；不会启动 MATLAB，也不执行压缩包内的模型脚本。工具拒绝已有目标目录，逐项验证内容后才恢复。恢复出的根仓库分支为 codex/recovered-workspace，索引对应快照记录的 HEAD；未提交文件仍保留为未提交内容。

进入恢复后的项目目录，可执行可移植的只读核查：

```sh
python3 tools/maintenance/audit_project.py
```

它检查文档导航、84 个模型哈希、当前三份输入/保护清单及四份已保存运行状态。历史清单中的绝对路径按各自明确记录的源根目录映射到恢复根目录，原 JSON 不重写；它不重新计算候选的热量残差，也不冒充 MATLAB 复验。

## 保留的历史身份与范围界限

- 内部 .worktrees 以证据目录恢复，里面的模型与原始结果仍在原相对位置；其 .git 指针不恢复，不冒充已注册的工作区。
- 项目目录之外的三个 Git 工作区，其可达提交包含在 bundle 中，未提交工作文件不在本包范围。工具不移动或重建用户的其他任务。
- tests/trace_ihx_h_calibration.py 是历史溯源脚本，依赖项目外的旧 Codex 会话和另一个“_副本”目录。保留原脚本和已保存溯源结果；它不是当前运行入口，未把外部私有会话或旧人工授权复制进包。
- 旧 JSON、CSV、日志中的绝对路径是历史证据。新审计工具提供明确的路径映射，不改写来源哈希或旧实验原始结果。其他历史脚本若自行要求旧绝对路径，仍须按其所属实验复核，不能批量运行来“验收”恢复包。
- MATLAB、系统 Python 及项目外安装的库不由此包安装。包内原有 pydeps 文件保留，但依赖二进制能否跨系统运行需单独验证；本包保证文件恢复，不承诺跨操作系统数值重现。

## 本轮文件管理的完成范围

全部实验条目已有留存决定，文献已有统一入口及字节版本清单，历史报告已有时点说明，当前导航使用相对路径，原始证据按原路径打包。缓存已有单独可恢复备份。没有继续迁移历史脚本依赖的目录，也不再以目录美观为由重做物理实验。

这完成本轮文件管理范围；论文原始参数、曲线失配及正式模型验收仍按 STATUS.md 处理。最新实际核验结果以恢复包 verification.json 为准。
