# 第5.3.1节稳态实验日志

## 2026-08-24 RED基线

- ✅ 本轮运行前后 `final_steady_24a.slx` SHA-256 均为 `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`，源模型哈希未变。
- ✅ 从已加载但不保存的模型块 `final_steady_24a/TAC/Constant` 读得实际 TAC 部件转速为 `66100 rpm`；论文第 5.3.1 节本轮验收目标为 `55090±1 rpm`，当前不通过。
- ✅ 局部读取 `hexe_compressor_lookup.mat` 得 `N_design=55090 rpm`、`speed_bp=[0.9, 1.1]`。本轮计算归一化转速为 `66100/55090=1.19985478308223`，高于表上限 `1.1`，当前不通过。
- ✅ 使用 `run_steady53_case`、`StopTime=14000 s`、不保存模型的阻塞式仿真结果：`success=false`、`tFinal_s=NaN`、`errorId=Simulink:Solver:Error`、`warningIds=[]`。`warningIds` 是运行器预筛选的物性警告 ID，本轮未记录到此类 ID。
- ✅ 错误报告精确文本记录“求解器在时间 `3628.4188021688287` 处遇到错误”；底层关键错误为 `Nonlinear iteration is not converging with step size reduced to hmin (1.28907E-11) at time 3628.42.`。✅ `3628.4188021688287 s` 只来自本轮错误文本，不是 `result.tFinal_s`；后者为 `NaN`，不据此编造终止轨迹数值。
- ✅ 单独验收测试结果为 `0 Passed, 2 Failed, 0 Incomplete`：一项捕获转速/查表边界缺口，一项捕获 14000 s 可达性缺口。
- ✅ 完整临时证据保存在 `tmp/steady53/red_baseline.txt`；该文件属于探索区运行输出，不提交。
- ❓ RED 测试只证明当前模型存在上述两类验收缺口；尚不能据此将任一单一部件或参数判定为唯一根因。

## 2026-08-24 55090 rpm 单变量实验

- ✅ TDD RED：创建函数前，在新 MATLAB 进程执行 `addpath('tests/steady53'); run_speed_hypothesis()`，以“函数或变量 `run_speed_hypothesis` 无法识别”失败；完整输出为 `tmp/steady53/speed55090_red.txt`。
- ✅ 正式模型未改写：实验前后 `final_steady_24a.slx` SHA-256 均为 `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`。
- ✅ 探索副本唯一的物理语义改动是 `final_steady_speed55090/TAC/Constant` 的 `Value` 从 `66100` 改为 `55090 rpm`；`StopTime` 从源模型保存值 `800 s` 改为本轮实验时长 `500 s`，后者是实验配置，不改变物理方程。正式模型和 `.mat` 查表均未保存或改写。
- ✅ 局部读取 `hexe_compressor_lookup.mat` 得 `N_design=55090 rpm`、`speed_bp=[0.9, 1.1]`；本轮实际部件转速为 `55090 rpm`，归一化压气机转速为 `55090/55090=1.0`，位于活动表定义域内。
- ✅ 500 s 完成状态：`summary.success=true`、`summary.tFinal_s=500`、`summary.errorId=""`、`summary.errorReport=""`、`summary.warningIds=[]`。这表示本轮探索副本完成了 500 s 阻塞仿真；不据此宣称已达到论文第 5.3.1 节的稳态数值、末窗稳定性或 14000 s 长期运行要求。
- ✅ 最终独立复跑生成的探索副本 SHA-256 为 `e7e91ec22df3e31d1341d8cefde8f0926a8f54719d435b00354d5f73618b973f`。当前完整结果为 `tmp/steady53/speed55090_result.mat`，首次完整运行控制台为 `tmp/steady53/speed55090_console.txt`，最终独立复跑控制台为 `tmp/steady53/speed55090_repeat_console.txt`；这些文件均为探索区证据，不提交。
- ✅ 新 MATLAB 进程独立复跑再次得到 `success=true`、`tFinal_s=500`，并逐项核实函数返回后 MATLAB path、Simulink 文件生成配置、既有 base 变量以及模型加载状态均已恢复；正式模型和探索模型均未保持加载。
- ❓ 结论边界：相较当前正式基线，55090 rpm 单变量副本消除了压气机归一化转速超出活动速度断点的问题，并在本轮完成 500 s；该结果仅支持继续定位转速接线对定义域和整机轨迹的影响，不能把“改善”单独视为全部根因，也不证明其他部件、方程或初值没有问题。
