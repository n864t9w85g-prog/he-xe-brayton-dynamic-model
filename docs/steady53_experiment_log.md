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

## 2026-08-24 55090 rpm 正式基线晋升后的测试生命周期治理

- ✅ 覆盖口径纠正：提交 `1960aa1` 报告的 `41 Passed`只包含当时选定的规格、判定器、阻塞运行器和转速验收回归；它没有覆盖仍绑定修改前 SHA/`66100 rpm` 的旧 Task 5 套件，也没有覆盖仍会将 TAC DUT 从 `66100` 改为 `55090` 的旧 Task 6 工装。因此该 `41 Passed` 不再作为“当前全活动套件”证据。
- ✅ TDD RED：修复前精确运行三项生命周期回归，实际得到 `0 Passed, 3 Failed, 2 Incomplete`：Task 6 TAC 工装以 `steady53:UnexpectedSourceSpeed` 拒绝已晋升的 `55090 rpm` 源模型；当前生命周期函数以 `MATLAB:UndefinedFunction` 缺失；Task 5 归档文件未建立且旧文件仍位于活动目录。完整输出为 `tmp/steady53/lifecycle/task7_lifecycle_red.txt`，不提交。
- ✅ Task 5 历史归档：旧 `run_speed_hypothesis.m` 和 `test_run_speed_hypothesis.m` 原样移至 `docs/archive/steady53/task5/`，不再被标准 `runtests('tests/steady53')` 发现。`README.md` 明确旧 SHA 合同不可只替换为新 SHA，需复核时应在独立 worktree 检出 `a84b680`；未生成或提交旧 SLX 副本。
- ✅ Task 5 当前生命周期：活动函数 `steady53_speed_hypothesis_lifecycle` 只读核对正式模型和压气机表，返回 `lifecycle="historical_not_applicable"`、`hypothesisAlreadyApplied=true`、`legacyRunnerApplicable=false`、实际转速 `55090 rpm`、归一化转速 `1.0`，且模型运行前后哈希相同；不再用无说明的 `UnexpectedSourceHash` 代表当前状态。
- ✅ 历史 Task 5 证据未改写：不可变 run `run_1787565286804_7a02debf9af2499f80405c77e165ba9a` 的副本和结果哈希仍分别为 `d8964212142663a8fba86c9d5f64cbba93c362d6f9c5a8db0e07106d2a7261c2` 和 `ebd06be2e9b38f6a56d8fb08d15ca2c9b06bc0f455fe2914f299a06d33940ec4`；`speed55090_current.mat` 仍存在，本轮未发布新 marker 或覆盖旧 run。
- ✅ Task 6 晋升：`create_component_harness` 现要求 TAC 源转速已为 `55090±1 rpm`，不再对 DUT 调用 `set_param` 做转速修正；六个 DUT 均与当前正式部件具有零 DialogParameter 差异、零连线签名差异和空 `behavioralChanges`。
- ✅ Task 6 正式基线复验：标准全活动套件中生成的最终不可变矩阵 run 为 `matrix_1787572756810_d9cc97278ec04270add6a69ff420d68e`。六部件在 `500 s` 和 `14000 s` 两个完整矩阵中均为 `success=true`、`tFinal` 精确到达请求时间、`errorId=""`、`warningIds=[]`。
- ✅ 新矩阵证据 SHA-256：`component_matrix_500.mat=a685b33b6daed8bd1b1169702b1a23ca93d92a2a1f541402c113a7559d660b8d`、`component_matrix_500.txt=4bf20c0921fc97594582ccf436fce61b6934370e22b1efa84778d3af19aa3fa7`、`component_matrix_14000.mat=fd4c7775fb871d3500e9fc4f081d6ec2a9068af08268d5735202a7b89e18fd94`、`component_matrix_14000.txt=e933e35886c84c30e450bdc0ea581057e50b3f8b2638eece6f49e9b5a1db3330`、`matrix_manifest.mat=0d7a10327ac23f7081b25219e7e79e806a37ee1feb77e42422f474346493cdc4`。修复前最终矩阵 `matrix_1787570192430_d4f48aaee81d47ab82d1d36d56b767f7` 的五个已记录哈希仍全部匹配，未改写旧矩阵。
- ✅ 当前活动回归：标准 `runtests('tests/steady53')` 实测 `50 Passed, 0 Failed, 0 Incomplete`，涵盖 Task 6 完整矩阵、Task 5 当前生命周期、规格/判定器/运行器以及正式模型的转速与 `14000 s` 无求解器/物性错误可达性回归。Python 溯源回归为 `6 tests, OK`；本轮修改的四个活动 MATLAB 文件 `checkcode` 均为零问题。
- ✅ 交付边界：本节没有修改正式 SLX、任何 `.mat` 或物理参数；`final_steady_24a.slx` SHA-256 仍为 `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`，`archive/pre-restart-20260824^{commit}` 仍为 `8f625c268c35a95c18a626305c1aa6a79ae2ace7`。
- ❓ 结论边界：本节证明测试工具已与晋升后的 `55090 rpm` 正式基线对齐，并且活动套件能识别旧 Task 5 为历史已应用假设。虽然本轮活动可达性回归实测到正式整机 `tout(end)=14000 s`，但这仍不是论文表 5.2 终值、图 5.18–5.19 稳定时间、最终窗口漂移、守恒或查表裕度的 Task 8/9 验收结论。

## 2026-08-24 物性警告 persistent latch 的诊断状态隔离

- ✅ 根因复现：`HeXe_property_simulink` 以 persistent `warned_lo_hexe/warned_hi_hexe` 抑制重复警告，`Lithium_property_simulink` 以 persistent `warned_lo/warned_hi` 做同样处理。在同一 MATLAB 会话中先将对应 warning 设为 `off` 并调用越界物性后，latch 已被置位；随后改成 `warning(error)` 不会重新发出警告。这是诊断告警状态泄漏，不是物性方程或钳位边界的变化。
- ✅ TDD RED：修复前运行 helper、runner、验收所有权和 Task 6 故障工装四项测试，实测 `0 Passed, 4 Failed, 1 Incomplete`。Task 6 的明确越界工装在四个已污染 latch 下均错误返回 `success=true` 且 `warningIds=[]`；`run_steady53_case` 的故障注入同样可被隐藏。完整证据为 `tmp/steady53/property_state/tdd_red.txt`，不提交。
- ✅ 最小状态治理：新 helper `reset_steady53_property_warning_state` 只执行 `clear("HeXe_property_simulink", "Lithium_property_simulink")`，把两个外部函数的一次性警告抑制 latch 恢复为“未初始化”。该 helper 不编辑物性文件，不改钳位上下限、关联式、模型参数或任何保存文件。
- ✅ runner 隔离：`run_steady53_case` 在每次隔离仿真的 `warning(error)` 之前先重置 latch；仿真完成或失败后，先关闭本调用所有的模型，再清回两个函数的未初始化诊断状态，最后恢复调用者的 warning 设置。runner 仍在所有副作用之前拒绝预加载模型。
- ✅ Task 6 隔离：矩阵在每个部件 `sim` 前重置 latch，并用 cleanup 在部件模型关闭后再清回未初始化状态。因此 IHX、回热器、预冷器、辐射器、反应堆和 TAC 不再共享上一个 case 的告警抑制 latch。
- ✅ 四 ID 污染/逆序回归：直接 helper 测试和逆序 runner 测试覆盖 `HeXe:T_lo`、`HeXe:T_hi`、`Lithium_property_simulink:TemperatureBelowRange`、`Lithium_property_simulink:TemperatureAboveRange`。每个已污染 latch 重置后均以原 warning ID 失败；runner 每个故障结果均满足 `success=false`、`errorId=<对应ID>`、`warningIds=<对应ID>` 且正式模型运行前后哈希不变。
- ✅ 真实工装故障注入：Task 6 在 TAC 的 He-Xe 输入常数和 IHX 的锂温度积分器初值上构造明确越界；对于每个已污染 ID，目标部件必须以正确 warning ID 失败，同一完整矩阵的其余五个部件仍必须运行成功。四种注入均通过该回归。
- ✅ 验收入口所有权：`test_final_steady_acceptance` 的 14000 s 运行已删除主动 `close_system`，统一通过 `run_final_steady_reachability` 委托 runner 执行。预加载正式模型并在内存把 `TAC/Constant` 改为 `55091`后，入口精确以 `steady53:ModelAlreadyLoaded` 拒绝，模型仍保持 loaded、`Dirty=on`、参数 `55091`，磁盘哈希不变；入口未关闭、保存或覆盖用户模型。
- ✅ 历史发现隔离：Task 5 归档测试再以 R100 重命名为 `docs/archive/steady53/task5/historical_run_speed_hypothesis_tests.m`，文件内容不变。仓库根目录递归 `TestSuite.fromFolder(...,'IncludingSubfolders',true)` 和标准活动发现均得到 `54` 项，其中旧 Task 5 测试为 `0`项。README 明确历史复核仍需在 `a84b680` 的原路径进行。
- ✅ 当前标准活动回归：`runtests('tests/steady53')` 实测 `54 Passed, 0 Failed, 0 Incomplete`，包含四 ID 污染/逆序回归、Task 6 完整六部件 `500 s/14000 s` 矩阵、正式整机 14000 s 可达性、所有权与环境恢复。Python 溯源回归仍为 `6 tests, OK`，八个本轮相关活动 MATLAB 文件 `checkcode` 均为零问题。
- ✅ 最终矩阵 run：`matrix_1787575403176_9e7f25628b6c410c9a48f090104d28e3`；六部件在 500 s 和 14000 s 均为 `success=true`、精确到达请求时间、`errorId=""`、`warningIds=[]`。证据 SHA-256 为：`component_matrix_500.mat=2c5172e823e7cdce7d5345f04b6273ac635b2d2e11b3649e08c3cb58675ceafd`、`component_matrix_500.txt=4bf20c0921fc97594582ccf436fce61b6934370e22b1efa84778d3af19aa3fa7`、`component_matrix_14000.mat=d73f5f23733de4c1de4a6020d821fc96cdfdb85522f2025d5d7eee2885bd06ff`、`component_matrix_14000.txt=e933e35886c84c30e450bdc0ea581057e50b3f8b2638eece6f49e9b5a1db3330`、`matrix_manifest.mat=fca507c9d15173ac86e5c910ed1aa5f6f5bbcc6d21acb1c3c80fc14ea199d2ae`。
- ✅ 独立证据口径：先前在新 MATLAB 进程的干净初始状态下得到的 500 s/14000 s 可达性和部件矩阵结果仍保留；该历史证据没有被改写。从本修复开始，运行器和 Task 6 矩阵还额外证明结果与同会话之前的物性告警 latch 历史无关。
- ✅ 交付边界：本节未修改 `final_steady_24a.slx`、He-Xe/锂物性文件、任何 `.mat`、钳位范围、物理方程或模型参数。正式模型 SHA-256 仍为 `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`，`archive/pre-restart-20260824^{commit}` 仍为 `8f625c268c35a95c18a626305c1aa6a79ae2ace7`。
- ❓ 结论边界：该修复只消除“告警抑制 persistent 状态导致诊断假阳性”。它不改物性模型或整机物理，也不将 14000 s 无错误可达性上升为论文表 5.2、图 5.18–5.19、最终窗口、守恒或查表裕度通过。

## 2026-08-24 Task 8：500 s 名义整机论文稳态验收（RED）

- ✅ 精确选择完整测试名
  `test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds`，
  并在运行前断言只选中 `1` 项；最终实测为
  `0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真完成 `500 s`：`success=true`、`tFinal_s=500`、`errorId=""`、
  `warningIds=[]`；失败发生在论文终值/收敛/质量闭合判定，不是求解器失败。
- ✅ 结构化证据位于
  `tmp/steady53/task8/run_1787577681355_c27e98941c2d4673b269b0d14f579ac5/`，
  包含完整 `result/report/spec` MAT、21 指标 CSV、全信号末窗 CSV、全状态末窗 CSV、
  8 查表输入审计和失败列表。`nominal_500_report.mat` SHA-256 为
  `f6bbefaaa2b5aa9c4af9f6198d2e20cdece89f5dd1df5578b64e70ff7ec46cf9`。
- ✅ 当时自动覆盖的 21 个论文指标和 40 个积分状态在 `400–500 s` 的波动/趋势均通过；状态最大相对
  峰峰值为 `1.2866786960e-5`，最大相对趋势为 `1.2598533948e-5`。因此 RED 是
  “收敛到错误稳态工作点”，不是末窗仍明显漂移。
- ✅ 首个失败为 `turbine_outlet_T:target`；末窗均值 `1143.7357423 K`，
  论文目标 `1162 K`，相对误差 `1.571794984%`，永久进入 `±1%` 目标带的时间为
  `Inf`。其余失败指标与全部数值见证据目录 `metrics.csv`。
- ✅ 8 个实际查表输入均在断点内；He-Xe 全时段范围为
  `397.6329219–1515.3874157 K`，液态锂为 `1430.1015961–1587.6158057 K`，
  且物性 warning 为空。
- ✅ 质量闭合最大相对差 `1.1454162022e-3 > 1e-6`，发生于 `t=0`：
  透平侧 `11.9837137735 kg/s`，其余四个 He-Xe 观测点各为 `11.97 kg/s`；
  锂侧闭合差为 `0`。本轮不修改初值或忽略 `t=0`。
- ✅ 首个失败的真实路径为
  `TAC/Turbine/MATLAB Function1 -> Goto10(T2) -> From20(T2) -> T_out(port 3)`；
  活动方程为 `T2=T1-(neta*cp2*(T1-T2s))/cp1`，上游为
  `T2s=T1*pi^(-phi)` 与 `phi=1-1/gamma`。
- ✅ 本轮重新检查论文 PDF：第 38–39 页（印刷页 23–24）Eq. (2.28)/(2.30)
  分别使用过程平均 φ̅ 和过程平均定压比热；第 88 页（印刷页 73）表 4.9
  直接给出方案 B `eta_T=0.87`，本轮未沿用任何旧 dynamic 效率结论。
- ✅ 当前透平块使用入口单点 `phi=1-1/gamma` 和点 `1/2s` 单点 `cp`。末时刻数值为
  `gamma=1.6658243262`、`T2s=1089.6475181 K`、`cp1=519.6567811`、
  `cp2=519.6580662 J/(kg·K)`、查表 `eta=0.8728696088`；离线复算得
  `T2=1143.7357706 K`，与模型记录完全一致。
- ❓ 根因候选：模型单点 `phi/cp` 与论文 Eq. (2.28)/(2.30) 过程平均量之间
  存在语义差异，可能导致透平稳态点偏移；尚未证明是唯一或足量根因。
  当前值口径下反算目标温度所需 `eta≈0.8299417` 仅是❓反算值，不是论文值，
  明确禁止作为调参输入。
- ✅ Root-Cause Checkpoint 已激活：新增未批准草案
  `docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md`。本轮没有修改
  正式 SLX、任何 MAT、物理参数或验收门槛，Task 8 明确为“未通过/未完成”。
- ✅ 回归分支验证：从标准活动发现集中只排除新增 Task 8 RED，并断言剩余
  测试数正好为 `54`，实测 `54 Passed, 0 Failed, 0 Incomplete`；Python 溯源回归为
  `6 tests, OK`；`checkcode` 对修改后验收文件报告 `0` 项问题。

## 2026-08-24 Task 8 规格审查修正：全结果信号末窗门

- ✅ 口径精准纠正：上一节“全部记录输出和积分状态在 `400–500 s`
  的波动/趋势均通过”中，只有 21 个论文指标和 40 个积分状态当时进入自动门；
  37 个结果信号虽全部保存，但其中 16 个非指标信号当时只有数值摘要、没有
  自动 pass/fail。本节将该表述改为已核实的实际覆盖范围，不撤回旧运行的其他数值。
- ✅ TDD RED：新增的固定无量纲尺度、非指标质量流量漂移、结果信号覆盖闭合
  和 manifest `kind` 四项回归在实现前实测为 RED。其中质量流量用例从
  `12 kg/s` 在末窗线性漂移到 `12.024 kg/s`，旧判定器错误返回 `pass=true`。
- ✅ 最小测试工具修正：`steady53_signal_manifest` 现对每个结果信号明示
  `kind`；`evaluate_steady53` 对审计名集与 `result.signals` 的全等、唯一性、
  数据一致性、固定尺度和末窗动态 fail closed。常量标记只是元数据，不跳过计算。
- ✅ 固定尺度沿用已批准规格：温度 `1 K`、压力 `1 Pa`、质量流量
  `1 kg/s`、功率 `1 W`、转速 `1 rpm`、无量纲及其他量 `1`；没有按本轮数据拟合。
- ✅ 新单元/连线回归实测 `32 Passed, 0 Failed, 0 Incomplete`；其中非指标
  质量流量漂移现同时产生 `signal:peak_to_peak:diagnostic_mdot` 和
  `signal:trend:diagnostic_mdot`，无审计元数据的额外结果信号产生 `signal:coverage`。
- ✅ 新真实阻塞 `500 s` 运行 ID 为
  `run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f`，精确选中 1 项后实测
  `0 Passed, 1 Failed, 0 Incomplete`；仿真本身 `success=true`、`tFinal_s=500`、
  `errorId=""`、`warningIds=[]`。
- ✅ 新完整 MAT 位于
  `tmp/steady53/task8/run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f/nominal_500_report.mat`，
  SHA-256 为 `53c72290496d319c33ef65fed75252f5e14254ae3b1765b9e566626762dfb9ea`，
  未覆盖旧 run。小型自包含摘要提交到
  `docs/steady53_evidence/task8_red/run_1787580406638_f71f1d130d1a444194e4141bb4c46d5f/`。
- ✅ 新运行的 37/37 结果信号全部进入自动末窗门并通过。最大信号相对
  峰峰值为 `4.52720121965087e-5`，最大相对趋势为
  `4.48826962977559e-5`，均来自 `compressor_outlet_P`。8 个质量流量语义信号均使用
  `1 kg/s` 尺度；两个锂流量常量仍明确审计。
- ✅ 失败集与旧运行一致：首个失败仍为 `turbine_outlet_T:target`，且
  `mass:closure=1.145416202230606e-3 > 1e-6`。本轮没有改门槛、没有忽略
  `t=0`、没有改初值。
- ✅ 论文 PDF 第 35 页（印刷页 20）Eq. (2.27) 是普朗特数定义
  `Pr = cp*mu/lambda`，未定义透平 φ̅；第 38–39 页（印刷页 23–24）Eq. (2.28)–(2.31)
  的透平上下文重新复核后，Eq. (2.28) 仍没有定义 φ̅ 的唯一平均路径/算子；
  Eq. (2.30) 后的文本用 `∫cp(T)dT` 解释平均 cp̅。
- ✅ 直接核实：当前 `HeXe_property_simulink(T,P)` 中 `P_Pa` 经
  `P_RT -> rho_hat -> cp_mol` 路径进入 cp 计算，cp 同时使用温度与压力。
- ❓ 数值实现判断：若使用当前 `cp(T,P)` 执行论文积分，必须另行
  选择论文未给出的 `P(T)` 路径；本轮不代用户选择。
- ✅ Root-Cause Addendum 已收窄为完全只读的 H1a 灵敏度分解：只计算
  Eq. (2.28) 的 φ̅ 对 `T2s/T2` 的独立增量，端点算术平均和明示线性
  `(T,P)` 路径积分作为两个并列的“数值实现选择”，不代用户选物理路径。
  H1b 只能在 H1a 基线经人工选择并固定后作为单独增量；本轮不授权 H1b，
  不授权任何 `tmp` SLX 实验。
- ❓ Task 8 仍为 RED/未完成；本轮没有修改正式 SLX、MAT、物理方程、参数或
  验收门槛。
- ✅ 完整活动 MATLAB 回归只排除预期 RED 的 Task 8 精确测试，并断言排除项
  恰好为 1；实测 `56 Passed, 0 Failed, 0 Incomplete`，即原有 54 项加本轮新增
  2 项全部通过。
- ✅ Python 溯源回归在带 Pillow 的工作区 Homebrew Python 下实测
  `6 tests, OK`。系统 `/usr/bin/python3` 的首次调用因未安装 Pillow 无法导入
  `PIL`；这是解释器依赖缺失，不是测试断言失败，本轮未安装或改动依赖。
- ✅ `checkcode` 对本轮修改的 7 个 MATLAB 文件均报告 0 项；`git diff --check`
  无尾随空格或空白错误。
- ✅ 正式模型 SHA-256 仍为
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`；四个已跟踪 MAT 分别为
  `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579`、
  `3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304`、
  `10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d`、
  `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33`；
  `archive/pre-restart-20260824^{commit}` 仍为
  `8f625c268c35a95c18a626305c1aa6a79ae2ace7`。

## 2026-08-24 Task 8 复审修正：论文 target 归一化合同

- ✅ 根因定位：21 个论文指标在 `metrics` 门中使用 `abs(target)` 归一化，
  但同名 `signalDynamics` 行曾使用 `max(abs(windowMean), scaleFloor)`，导致双门口径分叉。
- ✅ TDD RED 边界用例构造 `windowMean=0.9901*target`、
  `peakToPeak=0.000999*target`；修正前 5 个精确复审测试为
  `4 Passed, 1 Failed, 0 Incomplete`，失败行被旧分母计为
  `0.00100898899101109`。
- ✅ 最小修正：指标表新增明示 `windowPass`；37 行信号中的 21 个
  指标行直接复用已计算的 `peakToPeakRel/trendRel/windowPass`，因而精确复用
  `abs(target)` 口径；只有其余 16 行使用末窗均值与批准尺度下限的较大值。
- ✅ 新回归精确覆盖数据不一致、常量漂移、重名审计、非法（`NaN`）/未批准
  （`2`）的 `scaleFloor` 失败。`constant=true` 只是元数据，常量漂移仍同时产生
  `signal:peak_to_peak:*` 和 `signal:trend:*`。
- ✅ TDD GREEN：5/5 精确复审测试通过；`test_evaluate_steady53` 发现
  33 项并实测 `33 Passed, 0 Failed, 0 Incomplete`。
- ✅ 新真实阻塞 500 s 运行 ID 为
  `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`；精确选中 1 项，实测
  `0 Passed, 1 Failed, 0 Incomplete`，仿真本身 `success=true`、`tFinal_s=500`、
  `errorId=""`、`warningIds=[]`。
- ✅ 新完整 MAT SHA-256 为
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`，位于该新 run
  的 `tmp` 目录，未覆盖旧证据；小型受控摘要位于
  `docs/steady53_evidence/task8_red/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/`。
- ✅ 新报告的 21/21 指标末窗门和 37/37 结果信号末窗门全部通过。
  最大相对峰峰值为 `4.52673514492192e-5`，最大相对趋势为
  `4.48780756304835e-5`，均来自 `compressor_outlet_P`。
- ✅ 失败集仍为 23 项，首个为 `turbine_outlet_T:target`，最后为
  `mass:closure`；`1.145416202230606e-3 > 1e-6`，没有忽略 `t=0`或改阈值。
- ✅ 标准发现集共 62 项，断言且排除恰好 1 个预期 Task 8 RED 后，活动集
  实测 `61 Passed, 0 Failed, 0 Incomplete`。Python 溯源回归为 `6 tests, OK`；
  `checkcode` 对 7 个相关 MATLAB 文件均为 0 项。
- ✅ 证据等级已拆开：论文 `cp(T)` 与当前函数 `cp(T,P)` 是直接核实的
  ✅ 事实；因此需要另选 `P(T)` 则是论文未定义的 ❓ 数值实现判断。
- ❓ Task 8 仍为 RED/未完成；本轮没有修改正式 SLX、MAT、物理方程、
  参数、初值或验收门槛。

## 2026-08-25 Task 8 质量复审修正：可信合同与不可变证据发布

- ✅ `steady53_spec` 现固定 8 个必需查表审计名；evaluator 要求调用审计与该集合
  精确相等且每项恰好一次。空集合、缺项、重项和未知额外项均 fail closed，
  对应 4 类回归已由 RED 转为 GREEN。
- ✅ `steady53_spec` 现固定 37 行可信信号元数据合同，逐名规定
  `name/kind/constant/scaleFloor`，包括派生量 `reactor_power` 和
  `tac_electric_power`。evaluator 不再信任调用者自报元数据；`kind`、
  `constant`、合法但未批准的 `scaleFloor=2`、非法 `scaleFloor=NaN` 及未知信号
  的篡改回归均 fail closed。
- ✅ `steady53_signal_manifest` 的 35 行加两个派生量与上述 37 行规格合同进行
  全表一致性回归；规格自身另以硬编码期望表验证名称唯一、类型集合、常量标记和
  正有限尺度下限，避免可信合同退化为调用者自报。
- ✅ Task 8 证据写入已拆为 staging 与排他发布两个可测 helper：同文件系统 staging
  先写完整 MAT 和 6 个小文件、逐个计算 SHA-256，最后生成含 `runId`、源模型
  hash、原始 MAT hash、小文件 hash、`status=completed`、`createdAt` 的 manifest；
  发布时 manifest 最后出现。受控 runId 碰撞、目标文件碰撞、发布中断和旧证据
  hash 不变 4 项回归均通过；碰撞精确报 `steady53:EvidenceAlreadyExists`，中断不会
  产生 completed 目标或 current 假象。
- ✅ 采用新 helper 的真实阻塞 `500 s` 运行 ID 为
  `run_1787586447806_3d8eac4909284e1cb114e0911008dd2b`；精确选中 1 项并实测
  `0 Passed, 1 Failed, 0 Incomplete`。仿真本身 `success=true`、`tFinal_s=500`、
  `errorId=""`、`warningIds=[]`；失败仍为 23 项，首个为
  `turbine_outlet_T:target`，最后为 `mass:closure`。
- ✅ 新完整 MAT 位于
  `tmp/steady53/task8/run_1787586447806_3d8eac4909284e1cb114e0911008dd2b/nominal_500_report.mat`，
  SHA-256 为 `f0525396c7159eb6dff5e2f9bc3b2e0f54e66c0d3e94875ce43240a8042f0443`；
  manifest 的源模型 SHA-256 为
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`。
  小型自包含证据位于
  `docs/steady53_evidence/task8_red/run_1787586447806_3d8eac4909284e1cb114e0911008dd2b/`，
  与临时运行目录逐文件一致；两个既有受控 run 未被覆盖或改写。
- ✅ Root-Cause Addendum 的 H1a 只读分析仍精确绑定人工指定输入 run
  `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3` 及 MAT SHA-256
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`；
  草案明确拟读取字段、拟用只读脚本、输出路径及输出必须记录输入 MAT hash。
  本轮不创建或运行该待批准脚本，也不授权临时 SLX 修改。
- ✅ 完整 MATLAB 发现集共 76 项，断言且排除恰好 1 个预期 Task 8 RED 后，
  活动集实测 `75 Passed, 0 Failed, 0 Incomplete`。带 Pillow 的 Homebrew Python
  实测 `6 tests, OK`；系统 `/usr/bin/python3` 仍因缺少 Pillow 不能导入该测试，
  未安装或改动依赖。
- ✅ `checkcode` 对本轮 9 个相关 MATLAB 文件均报告 0 项；`git diff --check`
  已执行且无空白错误。Task 8 仍为 RED/未完成；本轮没有修改正式 SLX、MAT、
  物理方程、参数、初值或验收门槛。

## 2026-08-25 Task 8 发布器复审：固定 payload 合同

- ✅ 根因确认：`c06602e` 的发布器虽然校验了 manifest 中已列出的 hash，发布循环却
  仍由调用者可改写的 `stage.payloadFiles` 决定；同时没有要求 manifest 的小文件
  名称集合完整且唯一。因此删除 payload 声明、删除/重复小文件 hash 或改变
  `rawMatFile` 后仍可能发布 completed manifest。
- ✅ TDD RED：8 个新增合同回归在修复前全部实测失败，覆盖删除/添加
  `stage.payloadFiles` 项、删除/重复/加入未知 manifest 小文件 hash、篡改
  `rawMatFile`、将 `stage.rawMatPath` 指向内容相同的其他文件，以及目标 payload
  在发布 manifest 前被篡改。
- ✅ 最小修复：必需集合固定为 `nominal_500_report.mat` 加 6 个小文件；
  `stage.payloadFiles` 只作为必须精确匹配的兼容性声明，不再决定发布循环。
  manifest 必须精确列出固定 raw MAT 名称与 6 个唯一小文件名，发布列表仅由已验证
  manifest 派生；`stage.rawMatPath` 必须精确等于 `stageDir/nominal_500_report.mat`。
- ✅ manifest 发布前再次核对目标目录恰有 7 个 payload，且每项实际 SHA-256 与
  已验证 manifest 一致。碰撞、中断或二次核对失败时，目标目录即使保留也没有
  `manifest.json`，测试明确将其判定为 `incomplete`。
- ✅ 聚焦 evidence 测试实测 `12 Passed, 0 Failed, 0 Incomplete`。完整 MATLAB
  发现集为 84 项，精确排除 1 个既定 Task 8 RED 后，活动集实测
  `83 Passed, 0 Failed, 0 Incomplete`，即上轮 75 项加 8 个新增合同回归全部通过。
  Python 溯源回归为 `6 tests, OK`；两个相关 MATLAB 文件 `checkcode` 均为 0 项。
- ✅ 本轮没有重新生成或覆盖 500 s 证据；全部三个受控 evidence 目录相对
  `c06602e` 无差异，当前原始 MAT SHA-256 仍为
  `f0525396c7159eb6dff5e2f9bc3b2e0f54e66c0d3e94875ce43240a8042f0443`。
  正式 SLX、4 个 MAT 和归档 tag hash 均不变。Task 8 仍为 RED/未完成。

## 2026-08-25 Task 8 发布器复审：manifest 来源身份合同

- ✅ 根因确认：`72d8e40` 已固定 payload 名称和 hash，但发布器仍未强制
  `schemaVersion/sourceModelHash/createdAt`，也没有从 raw MAT 读取
  `result.modelHashBefore/modelHashAfter`；调用者还可把已验证 manifest 发布到与
  run ID 不一致的 `stage.targetDir`。
- ✅ TDD RED：10 个新增回归在修复前全部实测失败，覆盖 schemaVersion 缺失/错误、
  sourceModelHash 缺失/非法/与 raw MAT 不符、raw MAT 内 before/after 不一致、
  createdAt 缺失/非法/非 UTC，以及 target 目录与 manifest run ID 不一致；所有用例
  都要求不得产生目标 `manifest.json` 或 completed 状态。
- ✅ 最小修复：发布前强制 `schemaVersion==1`；`sourceModelHash` 必须是 64 位
  十六进制，并与 raw MAT 内 `result.modelHashBefore`、`result.modelHashAfter` 三方
  相等，同时要求 before==after。raw MAT 的 SHA-256 先通过 manifest 校验，再读取
  其中的 `result`，不采用 stage 中自报的模型 hash。
- ✅ `createdAt` 必须存在、非空，并严格符合含毫秒和尾随 `Z` 的 UTC 格式
  `yyyy-MM-ddTHH:mm:ss.SSSZ`，且能被 UTC datetime 实际解析。
- ✅ manifest run ID 必须为安全的 `run_*` 标识，并与 `stage.runId`、
  `.staging_<runId>` 目录名以及同父目录下的目标 `<runId>` 路径全部一致；
  manifest 路径也必须精确为 `stageDir/manifest.json`。
- ✅ 聚焦 evidence 测试实测 `22 Passed, 0 Failed, 0 Incomplete`。完整 MATLAB
  发现集为 94 项，精确排除 1 个既定 Task 8 RED 后，活动集实测
  `93 Passed, 0 Failed, 0 Incomplete`，即上轮 83 项加 10 个新增来源身份回归全部通过。
  Python 溯源回归为 `6 tests, OK`；两个相关 MATLAB 文件 `checkcode` 均为 0 项。
- ✅ 使用当前真实 500 s MAT 和既有 manifest 在系统临时目录完成一次发布合同
  兼容验证，结果 `CURRENT_EVIDENCE_PUBLISH_COMPAT=PASS`；临时目录随后删除，未生成或
  覆盖任何受控 run。三个 evidence 目录、正式 SLX、4 个 MAT 与归档 tag 均不变。
  Task 8 仍为 RED/未完成。

## 2026-08-25 Task 8A/H1a：Eq. (2.28) 只读分析被 S2 积分不收敛阻断

- ✅ 范围与 TDD RED：本轮只创建
  `tests/steady53/analyze_task8_h1a_readonly.m` 及对应测试，不加载或仿真任何 SLX，
  不修改任何 SLX、MAT、物性方程、模型参数、初值或验收阈值。函数缺失测试先实测
  `0 Passed, 1 Failed, 0 Incomplete`，随后完整合同测试在函数缺失时实测
  `0 Passed, 14 Failed, 14 Incomplete`；RED 证据位于
  `tmp/steady53/task8_root_cause/h1a_tdd/`，不提交。
- ✅ 固定输入身份门：默认输入仍精确绑定
  `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat`，
  SHA-256 为
  `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`；
  输入哈希不符、所需字段缺失、`t` 非严格递增、`finalWindow_s` 非法、输出碰撞、
  物性越界和无根括号均在产生结果文件前 fail closed。输入 MAT 的活动读取语句仅为
  `load(inputMat,"result","report","spec")`。
- ✅ 当前单点基线复算在进入 S2 前通过 `1e-9 K` 门：末时刻
  `T1=1515.109678670083 K`、`P1=1538809.8025948156 Pa`、
  `P2=674556.26792509283 Pa`、记录 `T2=1143.7357706111763 K`；
  `eta=0.87286960881076081` 由当前二维线性查表复算，`cp1=519.65678111047418`、
  `cp2=519.65806622669288 J/(kg K)`，基线方程复算残差为 `0 K`。
- ❓ H1a-S1 的只读局部结果在 S2 阻断前已收敛：
  `phiBar=0.39978932815006674`、`T2s=1089.5641955018075 K`、
  `T2=1143.6630406569668 K`、相对单点基线增量
  `-0.0727299542095352 K`、求根残差
  `1.5916157281026244e-12 K`。S1 是论文未指定的数值实现候选；该局部结果不能单独
  完成 H1a，也不构成物理正确性证据。
- ✅ 严格阻断事实：S2 使用批准的线性 `(T,P)` 路径、
  `integral(...,RelTol=1e-8,AbsTol=1e-10)` 和固定 `fzero` 区间
  `[100 K,T1]` 时，在下界评估触发精确 warning ID
  `MATLAB:integral:MaxIntervalCountReached`，报告误差近似范围为 `2.0e-05`。
  当前入口将该 warning 升为 error，并以
  `steady53:H1aIntegrationNonconvergence` 包装、保留原 cause 后 fail closed；默认
  执行证据为 `tmp/steady53/task8_root_cause/h1a_tdd/default_fail_closed.txt`。
- ❌ 一次早期实现曾压制并缓存上述 100 K 端点 warning；这违反“不收敛 fail
  closed”，其 S2 数值已经作废，禁止用于接受、拒绝或量化 H1a。该次两个原文件未被
  删除，而是完整移入
  `tmp/steady53/task8_root_cause/h1a/invalid_attempt_max_interval_20260825T014358CST/`；
  原 `h1a_sensitivity.csv` SHA-256 为
  `c3d05ed2fb24b435e9ac23c8ad7e830ffcf4c13ef33c0504a5ff41977296c280`，
  原 `h1a_summary.txt` SHA-256 为
  `8d76fa024fc0fe3728a9454c397f50253e97b45f1807969f73ff34ba22b3a962`，
  自描述 `INVALID_ATTEMPT.txt` SHA-256 为
  `e4c3fd413fe7f547ec93ba9a3ca683d0787e72c8e2ce9b0931f8394ee8910ffd`。
- ✅ 纠正后的默认执行没有创建正式固定输出目录
  `tmp/steady53/task8_root_cause/h1a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/`，
  因而没有有效的 `h1a_sensitivity.csv` 或 `h1a_summary.txt` 可交付。
  未改变根区间、未扫描子区间、未分段积分、未改变 `MaxIntervalCount`、未换算法。
- ❓ 结论边界：完整 H1a 为 **BLOCKED/未完成**。S2 没有有效结果，因此不能根据
  作废的早期 S2 数值声称 H1a 已被证伪，也不能判断 H1a 是否足以解释
  `18.264229388823651 K` 的末时刻差值。H1b 未执行，模型未修改。
- ✅ 允许范围内的最终验证：MATLAB 活动发现集共 `106` 项，精确发现且断言既定
  Task 8 RED
  `test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds`
  恰好 `1` 项；只运行经静态核实不触及 SLX 的 spec/evaluator/evidence/H1a 离线子集，
  实测 `79 Passed, 0 Failed, 0 Incomplete`。完整活动 SLX 回归有意未运行，因为本次
  人工批准范围明确禁止 load/sim SLX；本条不是“其余 105 项全绿”的声明。
- ✅ `/opt/homebrew/bin/python3` 溯源回归实测 `6 tests, OK`；`checkcode` 对两个
  新增 MATLAB 文件均为 `0` 项，静态扫描未发现 `set_param/load_system/sim/save_system`，
  `git diff --check` 通过。
- ✅ 保护状态复核：`final_steady_24a.slx` SHA-256 仍为
  `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`；
  四个 MAT SHA-256 仍依次为
  `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579`、
  `3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304`、
  `10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d`、
  `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33`；
  `archive/pre-restart-20260824^{commit}` 仍为
  `8f625c268c35a95c18a626305c1aa6a79ae2ace7`。
