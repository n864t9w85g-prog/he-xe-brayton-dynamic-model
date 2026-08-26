# Steady53 H1b 平均比热只读实验设计

## 1. 目标与人工授权

本设计实现一个严格离线、只读的 H1b 单变量实验：以已批准的
`H1a-S2 Scheme A` 结果作为待验证候选基线，只把当前 Eq. (2.30) 中的单点
`cp1/cp2` 处理替换为实际过程与理想过程的路径积分平均比热
`cpBarActual/cpBarIsentropic`，并计算该变化对透平出口温度 `T2` 的独立数值贡献。

用户于 2026-08-26 明确批准：

1. Scheme A 继续只作用于 H1a-S2 的 `phi` 路径；
2. H1b 的平均比热调用正式 `HeXe_property_simulink(T,P)`；
3. H1b 唯一新增变量是 `单点 cp1/cp2 -> 路径积分平均 cpBar`；
4. 并列计算线性端点压力、恒 `P1`、恒 `P2` 三条 `P(T)` 候选；
5. 不在三条候选中选择正式物理实现。

本设计不授权加载或仿真任何 SLX，不授权修改正式物性、SLX、MAT、PDF、效率、
初值、验收门槛或现有 H1a/H2/H2a 证据，也不授权把数值上更接近论文目标的候选
晋升为正式模型。

## 2. 证据等级与物理边界

- ✅ 仓库既有直接复核记录表明，论文 Eq. (2.30) 使用实际过程与理想过程的平均
  定压比热，并以 `integral cp(T)dT` 说明温差焓变。
- ✅ 当前活动透平方程用入口单点 `cp1` 和等熵出口单点 `cp2` 近似两个平均量。
- ✅ 当前正式物性接口实际为 `cp(T,P)`，压力进入 EOS 与热力状态计算。
- ❓ 论文没有规定当前 `cp(T,P)` 接口所需的 `P(T)` 路径；三条候选都是明示的
  数值敏感性选择，不是论文唯一规定的物理路径。
- ❌ 数值接近 `1162 K` 不能证明候选物理正确，不能授权正式修复。

## 3. 架构选择

采用独立、证据绑定的 H1b analyzer，不扩展已经审定的 H1a analyzer，也不在每次
H1b 运行前重新发布一套临时 H1a 证据。

新增四个探索区文件：

1. `tests/steady53/h1b_cpbar_candidate_readonly.m`
   - 纯数值求解一条压力路径候选；
   - 不读写文件，不调用模型 API；
   - 通过调用者提供的 property function 计算平均比热和路径审计。
2. `tests/steady53/test_h1b_cpbar_candidate_readonly.m`
   - 用解析合成物性验证积分、路径定义、Eq. (2.30) 分子/分母方向、求根与失败门。
3. `tests/steady53/analyze_task8_h1b_cpbar_readonly.m`
   - 固定验证 H1a-S2、H2a、MAT、SLX、正式物性、透平表和 helper 身份；
   - 复算并锁定 H1a 点比热候选基线；
   - 用正式物性调用三次纯求解器；
   - 原子发布自包含 H1b CSV/TXT。
4. `tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m`
   - 验证真实固定输入、完整证据、不可覆盖、环境恢复和只读边界。

现有 H1a/H2/H2a 实现和固定证据保持不变，只作为带哈希的输入依赖。

## 4. 固定 H1a-S2 候选基线

H1b 固定使用：

| quantity | fixed value |
|---|---:|
| `T1_K` | `1515.109678670083` |
| `P1_Pa` | `1538809.8025948156` |
| `P2_Pa` | `674556.26792509283` |
| `phiBar` | `0.39979002315209694` |
| `T2s_K` | `1089.5635709913104` |
| `eta` | `0.87286960881076081` |
| `H1a candidate T2_K` | `1143.6624955393854` |
| paper target `T2_K` | `1162` |

`T2s_K` 在 H1b 中不重新求解。Scheme A 不进入任何 H1b `cpBar` 积分；所有平均
比热均调用正式 `HeXe_property_simulink(T,P)`。

## 5. 平均比热数值定义

对任一实际或理想出口温度 `Tout_K`，定义无量纲路径参数：

```text
lambda in [0,1]
T(lambda; Tout) = T1 + lambda*(Tout - T1)
```

平均比热定义为：

```text
cpBar(Tout) = integral_0^1 cp(T(lambda;Tout), P(lambda)) dlambda
```

当 `Tout<T1` 时，它与下式严格等价：

```text
integral_Tout^T1 cp(T,P(T)) dT / (T1-Tout)
```

`lambda` 参数化是避免小温差下“小积分/小温差”数值退化的纯数值实现选择，不改变
平均比热的定义。

## 6. 三条压力路径候选

### 6.1 `linearEndpointPressure`

```text
P(lambda) = P1 + lambda*(P2-P1)
```

理想过程令 `Tout=T2s`，实际过程令 `Tout=T2`。这是唯一同时经过入口和出口压力
端点的候选，但仍不是论文已规定的唯一过程路径。

### 6.2 `constantP1`

```text
P(lambda) = P1
```

理想与实际积分均使用入口压力。该候选不满足出口压力端点，只用于量化压力路径
敏感性。

### 6.3 `constantP2`

```text
P(lambda) = P2
```

理想与实际积分均使用出口压力。该候选不满足入口压力端点，也只用于数值敏感性。

三个候选必须并列计算、并列报告，禁止只发布更接近论文目标的一条。

## 7. Eq. (2.30) 隐式求根

每条路径 `j` 先用固定 `T2s` 计算：

```text
cpBarIsentropic_j = cpBar_j(T2s)
```

实际平均比热依赖未知出口温度：

```text
cpBarActual_j(T2) = cpBar_j(T2)
```

求解残差：

```text
R_j(T2) = T2 - [T1 - eta*(cpBarIsentropic_j/cpBarActual_j(T2))*(T1-T2s)]
```

根区间固定为：

```text
T2 in [T2s,T1]
```

论文目标 `1162 K` 不得进入根区间、初值、容差或收敛方向。

数值设置固定为：

| setting | value |
|---|---:|
| integral `RelTol` | `1e-8` |
| integral `AbsTol` | `1e-8 J/(kg K)` |
| fzero `TolX` | `1e-12 K` |
| root maximum iterations | `1000` |
| root maximum function evaluations | `5000` |
| accepted absolute root residual | `<=1e-9 K` |

积分 warning 一律提升为 error。根区间没有符号变化、积分或求根不收敛、根越界或
残差超限均 fail closed。

## 8. 物性域与有限路径审计

每个正式 property call 必须返回有限实数，并满足：

```text
cp > 0
gamma > 1
cv = cp/gamma > 0
rho > 0
```

求根后，对三条实际路径和三条理想路径分别作固定 1001 点审计，记录：

- `min/max cp`；
- `min/max cv`；
- `min/max gamma`；
- `min/max rho`；
- `sampleCount=1001`；
- `allPhysical`；
- `formalGlobalProof=false`。

1001 点审计只能标为有限数值证据，不能称为全路径形式化证明。

## 9. 固定依赖与哈希门

默认 analyzer 必须绑定：

| artifact | SHA-256 / identity |
|---|---|
| run ID | `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3` |
| H1a-S2 CSV | `7e1ed139d14cbb1977a9f19d870c822243205414321a00c0f597717f5616f622` |
| H1a-S2 TXT | `26248e95f42acbb70701193fa75af429b60659b9975277837331b8cd2803efd2` |
| input MAT | `4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b` |
| `final_steady_24a.slx` | `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d` |
| formal property | `2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2` |
| `turbine_table2.mat` | `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33` |
| Scheme A helper | `5820e957b90b1affce777c1774aee6cc685f40430310408fb00f303846f606d0` |
| H2a CSV | `6a8398b7a32685cb3d198a1fe39b3b9365cfdefe65143d5613c68ffdd44366f4` |
| H2a TXT | `afd75b1b31cd0abdbdb2926b95ab987f260caa81a55fe2e901fdde4dafd72465` |
| archive peeled commit | `8f625c268c35a95c18a626305c1aa6a79ae2ace7` |

所有哈希必须在创建输出目录前验证。任一漂移都不得生成正式 H1b 输出。

## 10. H1a 候选一致性门

H1a CSV 必须恰好包含一行 `S2_schemeA_phiOnly`，并验证：

- 固定 `phiBar/T2s/T2`；
- `s2PhiVariant=schemeA`；
- `s2PhiScope=only H1a-S2 phi integrand`；
- `schemeADefinition=ignoreHePureThirdVirialBeforeCurrentMixingRule`；
- `etaCp1Cp2HeldFixed=true`；
- `slxLoadedOrSimulated=false`；
- `authorizesRepair=false`；
- `formalModelPromotion=false`；
- 记录的路径与哈希和本次实际依赖一致。

analyzer 随后从固定 MAT 和透平表重新取得 `T1/P1/P2/eta`，用正式物性复算点比热
基线：

```text
T2_point = T1 - eta*cp(T2s,P2)/cp(T1,P1)*(T1-T2s)
```

它必须在 `1e-9 K` 内复现 H1a CSV 的 `T2`，否则禁止进入 H1b。

## 11. 输出与原子发布

固定输出目录为：

```text
tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/
run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/
```

目录只允许包含：

- `h1b_cpbar_sensitivity.csv`；
- `h1b_cpbar_summary.txt`。

CSV 必须恰好四行：

1. `H1a_S2_schemeA_pointCp_baseline`；
2. `H1b_linearEndpointPressure`；
3. `H1b_constantP1`；
4. `H1b_constantP2`。

CSV 每行重复完整运行身份、依赖哈希、单变量范围、状态边界和适用的路径审计，使
CSV 能脱离 TXT 单独审计。TXT 记录数学定义、压力路径、容差、全部数值结果、有限
路径审计、证据等级和结论边界。

发布使用同文件系统 staging。两个文件均完整写入、重新解析、验证内容并预计算哈希
后，才排他发布固定目录。目标目录存在时拒绝覆盖；不得删除、替换或合并旧证据。

## 12. 数值充分性

对每条 H1b 候选 `j`：

```text
deltaT2_j = T2_j - T2_H1a
remainingError_j = targetT2 - T2_j
explainedFraction_j = deltaT2_j/(targetT2-T2_H1a)
```

仅当：

```text
sign(deltaT2_j) == sign(targetT2-T2_H1a)
and abs(deltaT2_j) >= abs(targetT2-T2_H1a)
```

才标记 `h1bNumericallySufficient=true`。该标记只描述数值幅度和方向，不证明压力
路径或平均比热实现物理正确。`explainedFraction` 不裁剪，允许为负或大于 1。

## 13. Fail-closed 合同

以下任一情况都禁止正式发布：

- 任一固定依赖或证据哈希漂移；
- H1a CSV 缺行、重行、未知额外方法、字段缺失或固定值不一致；
- 输入 MAT 必要时序缺失、长度不一致、末值非有限或身份不一致；
- 透平表维度/断点/查询值不合法，或 `eta` 复算不一致；
- H1a 点比热基线不能在 `1e-9 K` 内复现；
- 正式物性返回非有限、复数或非物理解；
- 任一积分 warning/异常/不收敛；
- 任一候选无符号变化根、求根不收敛、根越界或残差超限；
- 任一实际/理想 resolved path 的 1001 点审计失败；
- path、warning state、正式物性 persistent state 或 loaded block diagrams 未恢复；
- 任一受保护文件调用前后哈希变化；
- 输出目录已经存在；
- staging 缺少任一文件、文件为空或重新解析失败。

若任一候选失败，报告具体候选和失败点，H1b 保持未完成；不得只发布另外两条较好
结果。

## 14. TDD 设计

### 14.1 纯求解器

测试先调用尚不存在的 `h1b_cpbar_candidate_readonly` 并确认 RED。随后用解析物性：

```text
cp(T,P) = a + b*T + c*P
```

验证：

```text
linear:    cpBar = a + b*(T1+Tout)/2 + c*(P1+P2)/2
constantP1 cpBar = a + b*(T1+Tout)/2 + c*P1
constantP2 cpBar = a + b*(T1+Tout)/2 + c*P2
```

用恒定 `cp` 验证退化根：

```text
T2 = T1 - eta*(T1-T2s)
```

这项测试独立锁定 Eq. (2.30) 的 `cpBarIsentropic/cpBarActual` 方向。

失败测试覆盖未知路径、非法输入、非物性 property 输出、property/integral warning、
无根括号、求根失败、根超界、残差超限和 1001 点审计失败。

### 14.2 固定 analyzer

测试先调用尚不存在的 `analyze_task8_h1b_cpbar_readonly` 并确认 RED。随后验证：

- 所有固定身份和哈希；
- H1a-S2 行和点比热复算；
- 恰好 baseline 加三条 H1b 候选；
- 三条压力路径集合精确相等且无重复；
- H1b property variant 为 `formalHeXeProperty`；
- Scheme A 仍只作用于 H1a `phi`；
- 三条积分/求根和六条 1001 点审计；
- 输出 CSV/TXT 各自自包含；
- 输出碰撞和 staging 故障不产生半成品；
- 异常路径也恢复环境和只读状态。

## 15. 状态边界

成功发布时必须记录：

```text
h1aCandidateBaselineSelectedForExperiment=true
h1aCandidateBaselinePromotedToFormalModel=false
h1bExecuted=true
h1bPressurePathSelectedAsFormal=false
modelModified=false
formalPropertyModified=false
slxLoadedOrSimulated=false
authorizesRepair=false
formalModelPromotion=false
task8Passed=false
steady14000AcceptancePassed=false
```

`h1bExecuted=true` 只表示离线 H1b 数值实验完成。

## 16. 完成条件与最终验证

本批准范围只有在以下条件全部满足时完成：

1. H1a-S2 固定证据身份与点比热基线通过；
2. 三条候选均完成真实正式物性积分和隐式求根；
3. 三条根残差均 `<=1e-9 K`；
4. 六条 resolved path 均通过 1001 点有限物性审计；
5. CSV/TXT 各自自包含且二次运行拒绝覆盖；
6. 正式资产和既有证据哈希不变；
7. 没有加载或仿真 SLX；
8. 新 H1b 测试、既有 H1a/H2/H2a 聚焦回归和扩展后的 no-SLX 回归通过；
9. 完整 `tests/steady53` 只做 discovery，不运行 SLX 测试；
10. 新增 MATLAB 文件 `checkcode` 为零；
11. 禁止模型 API 扫描、`git diff --check` 和独立质量复审通过；
12. 工作树干净，变更形成独立可回滚提交。

最终报告必须分别标记：

- ✅ 三条 H1b 候选是否完成和准确数值；
- ⚠️ 1001 点审计只是有限数值证据；
- ❓ 每条候选是否数值上足以解释偏差；
- ❌ 不选择正式压力路径；
- ❌ 不授权修改正式 Eq. (2.30) 或物性；
- ❌ 不宣称 Task 8、14000 秒稳态或论文第 5.3 节验收通过。
