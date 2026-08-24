# Task 5 55090 rpm 单变量实验归档

`historical_run_speed_hypothesis_tests.m` 保留正式基线晋升前的测试源码；
其非 `test` 前缀名称用于防止仓库递归测试发现把这 9 项旧基线测试计入当前绿灯。
本目录保留正式基线晋升前的 Task 5 实验工具和测试源码，不属于
`tests/steady53` 当前活动验收套件。

## 生命周期状态

- 历史源模型 SHA-256：
  `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`。
- 历史假设：只把 TAC 部件边界转速从 `66100 rpm` 改为 `55090 rpm`，
  在探索副本中验证压气机归一化转速和 500 s 可达性。
- 该假设已由正式提交 `1960aa1` 应用到 `final_steady_24a.slx`。
- 因此旧 runner 的“源模型必须为旧 SHA”合同已不适用于当前基线；
  不得通过只替换硬编码 SHA 把它伪装成新基线实验。

## 证据保留

本次归档不删除、不覆盖现有
`tmp/steady53/runs/<runId>/`、`speed55090_current.mat` 和相关日志。这些仍是
历史实验证据，但不是当前正式模型的验收绿灯。

## 手动复核历史实验

归档文件保留了原始根目录相对路径假设，不应直接从本目录执行。
需要复核时，应在独立 Git worktree 检出最终 Task 5 提交 `a84b680`，
从当时的 `tests/steady53/` 路径手动运行。不要把旧 SLX 副本写入或
覆盖当前正式基线。

当前基线的机器可读状态由
`tests/steady53/steady53_speed_hypothesis_lifecycle.m` 报告，应为
`historical_not_applicable` 且 `hypothesisAlreadyApplied=true`。
