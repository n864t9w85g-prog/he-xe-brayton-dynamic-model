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

## 2026-08-24 第 5.3.1 节部件恒边界隔离工装

- ✅ TDD RED：创建实现前，边界测试以 `MATLAB:UndefinedFunction` 报告 `steady53_component_boundaries` 未定义，工装测试同样报告 `create_component_harness` 未定义。证据保存于 `tmp/steady53/components/task6_tdd_red.txt`，不提交。
- ✅ 每次工装生成使用唯一运行目录和唯一模型名；拒绝预加载的正式源模型，不关闭非本调用所有的用户模型。六个工装的实际 Inport 名称和端口号均与边界合同一致，且 update/compile 通过。
- ✅ 语义差异审计：`IHX`/`recuperator`/`precooler`/`rediator`/`reactor` 的 DUT 内部无 DialogParameter 或连线差异；`TAC` 的唯一行为差异为探索副本内 `DUT/Constant.Value: 66100 -> 55090 rpm`。这一改动未保存回正式模型。
- ✅ 正式 `final_steady_24a.slx` 试验前后 SHA-256 均为 `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`。本任务未保存正式 `.slx` 或 `.mat`。

### 边界合同与出处

| 部件 | 输入向量（按实际 Inport 端口号） | 出处与证据等级 |
|---|---|---|
| `IHX` | `[1600, 4.572, 11.97, 1100.91, 1.543e6]` | 温度/压力：论文表 5.2 直接值 ✅；`4.572` 锂流量和 `11.97` He-Xe 流量：批准的项目工装边界 ❓，不冒充论文直接值 |
| `recuperator` | `[11.97, 1162, 0.676e6, 1.551e6, 601.90, 11.97]` | 温度/压力：论文表 5.2 直接值 ✅；两侧 `11.97` 流量：批准的项目工装边界 ❓ |
| `precooler` | `[360.10, 6.95, 663.63, 0.676e6, 11.97]` | 温度/压力：论文表 5.2 直接值 ✅；`6.95`/`11.97` 流量：批准的项目工装边界 ❓ |
| `rediator` | `[609.58, 6.95]` | 温度：论文表 5.2 直接值 ✅；冷却剂流量：批准的项目工装边界 ❓ |
| `reactor` | `[1443.27]` | 论文表 5.2 反应堆入口温度直接值 ✅ |
| `TAC` | `[1.539e6, 1522.96, 405.16, 0.658e6, 11.97, 1000e3]` | 温度/压力：论文表 5.2 直接值 ✅；`11.97` 流量与 `1000e3 W` 名义负载：第 5.3.1 节本轮批准的项目工装边界 ❓，负载不冒充实测发电功率 |

### 真实运行矩阵

| component | 500 s | 14000 s | `tFinal` / error | 物性 warning |
|---|---:|---:|---|---|
| `IHX` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |
| `recuperator` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |
| `precooler` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |
| `rediator` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |
| `reactor` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |
| `TAC` | PASS ✅ | PASS ✅ | `500` / `14000` s；无 error ID | 无 |

- ✅ 上表来自两个完整六部件矩阵；每个成功项均核对 `tout(end)` 精确达到请求时间、所有 To Workspace 输出为有限实数，且 `HeXe:T_lo` / `HeXe:T_hi` / 锂物性上下限四类 warning 均被提升为 error 而未触发。所有权修复后的最终验证运行 ID 为 `matrix_1787570192430_d4f48aaee81d47ab82d1d36d56b767f7`，500 s 和 14000 s 四个机器可读文件及 manifest 共同位于 `tmp/steady53/components/matrix_runs/matrix_1787570192430_d4f48aaee81d47ab82d1d36d56b767f7/`，不提交。
- ✅ 矩阵证据发布已取消固定可覆盖路径。每次测试会话先生成唯一 `matrix_runs/<runId>/`；`.mat` 和 `.txt` 均先写唯一 stage，再通过同文件系统排他硬链接发布，目标存在即以 `steady53:MatrixEvidenceAlreadyExists` 失败。连续两次合成矩阵发布回归已核对 runDir 不同，且第一次的四个文件和 manifest 哈希保持不变。
- ✅ 最终验证运行的不可变证据哈希：`component_matrix_500.mat=7c61e43b61bfb62f3e8d19cd74fab5beea1d7a21093798664453d7b022ed5ce4`，`component_matrix_500.txt=4bf20c0921fc97594582ccf436fce61b6934370e22b1efa84778d3af19aa3fa7`，`component_matrix_14000.mat=cbf3a8ffff09d0e9c608f8b70603bd2d7824f216d99b9d75194b682e83405610`，`component_matrix_14000.txt=e933e35886c84c30e450bdc0ea581057e50b3f8b2638eece6f49e9b5a1db3330`，`matrix_manifest.mat=375b772bed496a999f7f9ae876ecc8d178f11a87ddf80bde465ad8ac3ddeaae6`。
- ✅ 质量审查所有权回归：测试启动前已加载模型集合在 `setupOnce` 第一批记录，工装模型另行显式登记所有权；`teardownOnce` 仅关闭“不在启动前集合中且由本套件显式登记”的模型，不再依赖 `s53_*` 前缀。实际预加载回归在边界测试及 suite teardown 后保留正式模型 `Dirty=on, StopTime=801` 和用户 `s53_user_*` 模型 `Dirty=on, Value=42`；两者均未保存。
- ✅ `teardownOnce` 的已有模型关闭、base workspace、path、pwd、warning、Simulink file-generation 和套件临时目录恢复现分步 best-effort 执行；任一步失败不会阻断后续步骤，最后才以 `steady53:ComponentHarnessTeardownFailed` 聚合报告。
- ❓ 结论边界：恒边界下六个隔离部件均能完成 14000 s，因此本轮未由 Task 6 触发 Root-Cause Checkpoint。这不证明整机闭环已通过，不证明部件在整机互联边界下不会失稳，也不将“隔离运行通过”上升为任一具体根因结论。

## 2026-08-24 正式稳态模型 TAC 设计转速最小修正

- ✅ 修改前备份与状态门：`final_steady_24a.slx` SHA-256 为 `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`；`archive/pre-restart-20260824^{commit}` 仍解析为 `8f625c268c35a95c18a626305c1aa6a79ae2ace7`；修改前工作树无已跟踪变更。完整快照输出位于 `tmp/steady53/task7_prechange_snapshot.txt`，不提交。
- ✅ 真实 RED：在新 MATLAB 进程中精确选中且断言只有一个 `testActualComponentSpeedIsPaperNominal` 测试，读得实际值 `66100 rpm`、期望值 `55090±1 rpm`，以绝对差 `11010 rpm` 失败；同时归一化转速 `1.199854783082229` 超过活动表上限 `1.1`。证据位于 `tmp/steady53/task7_speed_red.txt`，不提交。
- ✅ 测试选择器口径修正：计划文档里仅传短 `Name` 的 `runtests` 命令在本 MATLAB R2025a 环境实际选中 `0` 项，不能作为 RED/GREEN 证据。本轮改用完整测试名 `test_final_steady_acceptance/testActualComponentSpeedIsPaperNominal`，并在运行前断言 `numel(suite)==1`。
- ✅ 正式模型单一修改：只将 `final_steady_24a/TAC/Constant.Value` 从 `66100` 改为 `55090 rpm`。未修改任何 `.mat` 查表，未增加模块、连线、控制器、校正反馈或拟合参数。修改后模型 SHA-256 为 `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。
- ✅ GREEN：同一个精确选中的转速测试在新 MATLAB 进程中返回 `1 Passed, 0 Failed, 0 Incomplete`；实际转速和 `N_design` 均为 `55090 rpm`，归一化转速为 `1.0`，位于 `speed_bp=[0.9,1.1]` 内。证据位于 `tmp/steady53/task7_speed_green.txt`，不提交。
- ✅ 保存前后 SLX 语义对比覆盖 `1233` 个块和 `1097` 条连线：块集合、块类型、DialogParameter 模式和连线端口签名相同，唯一 DialogParameter 差异为 `/TAC/Constant::Value`。模型 `StopTime=800`、`Solver=ode15s`、`RelTol=1e-3` 修改前后不变。机器可读摘要位于 `tmp/steady53/task7_semantic_audit.txt`，不提交。
- ✅ 正式整机 500 s 阻塞运行：`run_steady53_case` 在内存中把四类 He-Xe/锂物性警告提升为 error，并使用阻塞式 `sim(SimulationInput)`。本轮实测 `success=true`、`tFinal_s=500`、`errorId=""`、`warningIds=[]`；运行前后模型 SHA-256 均为 `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。控制台与时序证据分别位于 `tmp/steady53/task7_whole_system_500_console.txt` 和 `tmp/steady53/task7_whole_system_500.mat`，不提交。
- ✅ 回归与交付边界检查：稳态规格、验收判定器、阻塞运行器及精确选中的转速验收共 `41 Passed, 0 Failed, 0 Incomplete`；`checkcode` 对 `test_final_steady_acceptance.m` 和 `run_steady53_case.m` 均为 `0` 项；非 `tmp/` 的全部 `.mat` SHA-256 清单修改前后无差异；archive tag 的标签对象和解析 commit 均未变。
- ❓ 结论边界：本轮证明正式模型在已批准的单一转速修正后可阻塞运行到 `500 s`，并且压气机归一化转速回到活动表定义域。这不证明整机已达到论文稳态数值，不证明图 5.18–5.19 稳定时间通过，不证明最终窗口/守恒/查表裕度通过，也不证明 `14000 s` 可达。
