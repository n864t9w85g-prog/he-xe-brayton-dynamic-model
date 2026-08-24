# Task 8 500 s RED 证据摘要（可信审计合同与排他发布）

- ✅ 运行 ID：`run_1787586447806_3d8eac4909284e1cb114e0911008dd2b`
- ✅ 精确测试：
  `test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds`
- ✅ 选择器断言恰好 1 项；实测 `0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真：`success=true`、`tFinal_s=500`、`errorId=""`、`warningIds=[]`。
- ✅ 正式模型 SHA-256：
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。
- ✅ 完整时序 MAT 保留在
  `tmp/steady53/task8/run_1787586447806_3d8eac4909284e1cb114e0911008dd2b/nominal_500_report.mat`，
  SHA-256 为
  `f0525396c7159eb6dff5e2f9bc3b2e0f54e66c0d3e94875ce43240a8042f0443`；该大文件不提交。

## 审计合同

- ✅ lookup 审计与 `steady53_spec.requiredLookupNames` 的 8 个名称集合
  精确相等，每项恰好一次。
- ✅ 37 行结果信号审计逐名与 `steady53_spec.signalMetadata` 的
  `name/kind/constant/scaleFloor` 可信合同一致；调用者自报不能改变判定元数据。
- ✅ 21 个论文指标行使用 `abs(target)` 归一化；其余 16 行使用
  `max(abs(windowMean), approved scaleFloor)`。
- ✅ `constant` 只是元数据，不跳过峰峰值或趋势门。

## 排他发布合同

- ✅ 所有原始和小型证据先写入同文件系统 staging。
- ✅ `manifest.json` 在所有文件写完并计算 SHA-256 后才生成。
- ✅ 发布通过排他目标目录和硬链接执行；manifest 最后发布。
- ✅ manifest 记录 `runId/sourceModelHash/rawMatHash/smallFileHashes/status/createdAt`；
  本轮 `status=completed`。
- ✅ 碰撞或中断不会在目标目录生成 completed manifest，也不会覆盖旧 run。

## 结果

- ✅ 完整失败集仍为 23 项；首个为 `turbine_outlet_T:target`，最后为
  `mass:closure`。
- ✅ 21/21 论文指标末窗门和 37/37 结果信号末窗门全部通过。
- ✅ 40 个积分状态的末窗审计通过；8 个 lookup 输入均在断点内。
- ✅ `massClosureRel=1.145416202230606e-3 > 1e-6`；未忽略 `t=0`，
  未修改阈值或初值。
- ❓ Task 8 仍为 RED/未完成；本证据不授权修改正式或临时模型。

## 受控文件

- `manifest.json`：发布状态、模型/MAT 哈希和全部小文件哈希。
- `metrics.csv`：21 个论文指标的结果。
- `failures.txt`：完整失败标识集。
- `signal_window_audit.csv`：37 个结果信号的末窗审计。
- `state_window_audit.csv`：40 个积分状态的末窗摘要。
- `lookup_audit.csv`：8 个查表输入范围。
- `summary.txt`：仿真、物性和质量闭合摘要。
