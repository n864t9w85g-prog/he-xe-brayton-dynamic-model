# Task 8 500 s RED 证据摘要

- ✅ 运行 ID：`run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f`
- ✅ 精确测试：
  `test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds`
- ✅ 选择器断言恰好 `1` 项，实测 `0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真：`success=true`、`tFinal_s=500`、`errorId=""`、`warningIds=[]`。
- ✅ 正式模型 SHA-256：
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。
- ✅ 完整时序 MAT 保留在
  `tmp/steady53/task8/run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f/nominal_500_report.mat`，
  SHA-256 为
  `53c72290496d319c33ef65fed75252f5e14254ae3b1765b9e566626762dfb9ea`；该大文件不提交。

## 结果

- ✅ 首个失败仍为 `turbine_outlet_T:target`；完整失败集见
  `failures.txt`。
- ✅ 37/37 个结果信号均已进入自动末窗审计；每行保存
  `kind/scaleFloor/constant/peakToPeakRel/trendRel/signalPass`。
- ✅ 37 个信号本轮均通过末窗波动/趋势门。最大信号相对峰峰值为
  `4.52720121965087e-5`，最大相对趋势为 `4.48826962977559e-5`，均来自
  `compressor_outlet_P`。
- ✅ 8 个质量流量语义信号全部明确审计，尺度下限均为 `1 kg/s`；
  两个锂流量常量标记为 `constant=1`，仍计算并通过末窗门。
- ✅ 40 个积分状态的最大相对峰峰值为 `1.28667869603203e-5`，
  最大相对趋势为 `1.2598533947921e-5`。
- ✅ He-Xe 全时段范围 `397.632921931885–1515.38741571301 K`，锂为
  `1430.1015961066–1587.61580570996 K`；8 个查表输入全部在断点内。
- ✅ `mass:closure` 仍失败：`1.145416202230606e-3 > 1e-6`。本轮没有
  改门槛或忽略 `t=0`。
- ❓ Task 8 仍为 RED/未完成；本证据不支持修改任何正式物理方程。

## 受控文件

- `metrics.csv`：21 个论文指标的目标、实值、误差、收敛和通过标记。
- `failures.txt`：本轮完整失败标识集。
- `signal_window_audit.csv`：全部 37 个结果信号的 fail-closed 末窗审计。
- `state_window_audit.csv`：全部 40 个积分状态的末窗摘要。
- `lookup_audit.csv`：8 个查表输入的实际范围与断点范围。
- `summary.txt`：仿真、物性范围和质量闭合的小型机器可读摘要。
