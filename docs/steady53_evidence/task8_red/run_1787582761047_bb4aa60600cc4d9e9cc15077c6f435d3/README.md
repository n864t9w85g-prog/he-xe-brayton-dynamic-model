# Task 8 500 s RED 证据摘要（target 归一化合同修正后）

- ✅ 运行 ID：`run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`
- ✅ 精确测试：
  `test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds`
- ✅ 选择器断言恰好 `1` 项，实测 `0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真：`success=true`、`tFinal_s=500`、`errorId=""`、`warningIds=[]`。
- ✅ 正式模型 SHA-256：
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。
- ✅ 完整时序 MAT 保留在
  `tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat`，
  SHA-256 为
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`；该大文件不提交。

## 判定口径

- ✅ 37 行 `signalDynamics` 全部进入自动末窗门。
- ✅ 其中属于 `s.metrics` 的 21 行直接复用论文指标已计算的
  `peakToPeakRel/trendRel/windowPass`，并且以 `abs(target)` 为归一化分母。
- ✅ 其余 16 行使用
  `max(abs(windowMean), approved scaleFloor)`，未按本轮数据拟合尺度。
- ✅ `constant` 只是元数据；常量行仍完整计算并执行峰峰值和趋势门。

## 结果

- ✅ 首个失败仍为 `turbine_outlet_T:target`；完整失败集见
  `failures.txt`。
- ✅ 21/21 论文指标通过末窗波动/趋势门；37/37 个结果信号亦全部通过。
- ✅ 最大信号相对峰峰值为 `4.52673514492192e-5`，最大相对趋势为
  `4.48780756304835e-5`，均来自 `compressor_outlet_P`。
- ✅ 8 个质量流量语义信号全部明确审计，尺度下限均为 `1 kg/s`。
- ✅ 40 个积分状态的末窗审计保持通过。
- ✅ He-Xe 全时段范围为 `397.632921931885–1515.38741571301 K`，锂为
  `1430.1015961066–1587.61580570996 K`；8 个查表输入全部在断点内。
- ✅ `mass:closure` 仍失败：`1.145416202230606e-3 > 1e-6`；未改门槛、
  未忽略 `t=0`。
- ❓ Task 8 仍为 RED/未完成；本证据不授权修改任何正式或临时模型。

## 受控文件

- `metrics.csv`：21 个论文指标的目标、实值、误差、末窗通过和总体通过标记。
- `failures.txt`：本轮完整失败标识集。
- `signal_window_audit.csv`：全部 37 个结果信号的 fail-closed 末窗审计。
- `state_window_audit.csv`：全部 40 个积分状态的末窗摘要。
- `lookup_audit.csv`：8 个查表输入的实际范围与断点范围。
- `summary.txt`：仿真、物性范围和质量闭合的小型机器可读摘要。
