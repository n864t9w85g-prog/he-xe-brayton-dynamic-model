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

## 2026-08-24 探索证据链发布治理

- ✅ 质量审查 RED：在旧工具上先新增“哈希不匹配必须先于产物创建失败”的受控 options 测试，实际因旧函数不接受 options 而以 `MATLAB:TooManyInputs` 失败；证据为 `tmp/steady53/task5_review_red.txt`。该 RED 针对证据工具，不构成新的物理结果。
- ✅ 每次实验现写入唯一的 `tmp/steady53/runs/<runId>/`，完整保留该次副本、结果或外层工具失败记录；固定兼容文件不再直接无条件覆盖。
- ✅ 第二轮质量复审撤回此前“legacy 严格采纳”和“copy/result/marker 三文件原子发布”的表述：summary 自报字段即使与伪造副本哈希同步，也不能证明所有权；三个文件的依次移动也不是一个原子事务。
- ✅ `speed55090_current.mat` 现为 schema v2 的唯一 current 权威。工具先完整验证不可变 run 的 copy/result 哈希、路径边界及 result/summary 元数据，再以同目录暂存文件加一次 `movefile` 原子替换 marker；这一次 marker 移动是唯一的 current 切换点。
- ✅ markerless 状态下，只要任一固定 copy/result 存在，一律以 `steady53:UnownedExplorationArtifact` 拒绝，绝不根据 summary 自报字段接管或覆盖；新增反例在副本额外修改 `Constant14` 并同步伪造哈希后仍必须被拒绝。
- ✅ 固定 `final_steady_speed55090.slx` 与 `speed55090_result.mat` 只是可重建兼容缓存，不参与 marker 权威判定。有效 marker 指向的不可变 run 通过验证后，固定缓存缺失或哈希不同会从该 run 通过暂存加移动自动恢复；返回字段 `cacheRebuilt` 明确记录本次是否恢复。
- ✅ marker 的 `schemaVersion/runId/runDirectory/runCopyPath/runResultPath/sourceHash/copyHash/resultHash/status/completedAt` 均与不可变 result/summary 交叉验证；同时核实 run 目录必须直接位于本工具 `tmpRoot/runs` 下、目录 basename 等于 `runId`、两个文件名和父目录精确匹配。分别篡改 `status`、`completedAt`、`runDirectory`、`runId`、`runCopyPath`、`runResultPath` 均以 `steady53:MarkerMismatch` 拒绝。
- ✅ 发布中断测试覆盖 `before_marker_move`、`after_marker_move_before_cache`、`after_current_copy_move`：marker 移动前中断时旧 current 保持有效；marker 移动后缓存尚未更新或只更新 copy 时，新 marker 仍有效，下一次只读校验会修复缓存，且不永久阻塞后续运行。
- ✅ 外层 `after_save` 与 `before_runner` 受控异常均保留原错误 ID，在各自唯一 run 目录保存 `failure.mat` 和 `errorReport.txt`；并核实 path、pwd、warning、Simulink file-generation、base workspace 和模型加载状态均恢复，随后重新计算正式源模型哈希。
- ✅ 第二轮工具测试结果为 `9 Passed, 0 Failed, 0 Incomplete`；连同 Task1–3 helper 为 `49 Passed, 0 Failed, 0 Incomplete`。逐块 DialogParameters/连线签名语义审计仍只发现 `TAC/Constant::Value`，另有明确的实验配置 `StopTime` 差异。Task4 两项正式验收继续单列为预期 RED，不计入工具绿灯。
- ✅ 原 schema v1 的三个固定兼容文件已可恢复地移入 `tmp/steady53/archive/schema_v1_20260824_round2/`，原不可变 run 未改动；没有执行 markerless 自动接管。随后无参数 500 s 新运行直接生成 schema v2 current。
- ✅ schema v2 无参数 500 s 复跑仍为 `success=true`、`tFinal_s=500`、`warningIds=[]`；正式源模型 SHA-256 仍为 `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`。
- ✅ 当前 schema v2 marker 指向 `run_1787565286804_7a02debf9af2499f80405c77e165ba9a`，状态 `completed`，副本 SHA-256 为 `d8964212142663a8fba86c9d5f64cbba93c362d6f9c5a8db0e07106d2a7261c2`，结果 SHA-256 为 `ebd06be2e9b38f6a56d8fb08d15ca2c9b06bc0f455fe2914f299a06d33940ec4`；marker 校验返回 `cacheRebuilt=false`。控制台证据为 `tmp/steady53/speed55090_schema_v2_console.txt`，不提交。
- ❓ 证据边界：本节改进的是异常安全、运行身份和证据发布协议；除再次复核同一 500 s 完成事实外，不把工具重构升级为新的物理证据，不扩大此前关于 55090 rpm 单变量的结论范围。
