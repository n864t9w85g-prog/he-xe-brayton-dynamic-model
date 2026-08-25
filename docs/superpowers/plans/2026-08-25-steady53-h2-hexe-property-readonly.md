# Steady 5.3 Task 8 H2 He-Xe 物性只读取证实施计划

> **执行要求：** 按 `subagent-driven-development` 的逐任务审查节奏执行；每一项先写失败测试，再写最小只读分析实现。任何发现都先按 `systematic-debugging` 追到公式或数值中间量，不在本计划内修复正式物性函数。

**目标：** 在不加载或仿真任何 SLX、不修改 `HeXe_property_simulink.m`、MAT、求解器或验收门槛的前提下，确定 H1a-S2 在 `(T,P)=(992.38742737169468 K, 1007910.8613125964 Pa)` 出现 `cp<0`、`gamma<1` 的直接数值来源，并区分“当前实现错误”“密度根选择错误”“论文 Eq. (2.7)–(2.17) 关联式自身在该点产生非物理解”三种假设。

**证据边界：** 论文原文 PDF 第 33–35 PDF 页（印刷页 18–20）用于核对 Eq. (2.7)–(2.17)；当前活动函数只读调用及源代码哈希用于证明实现状态；独立有限差分、三次方程全根和热力学恒等式用于交叉验证。所有结论使用 `✅/⚠️/❓/❌` 证据等级。在线文献只可补充原始关联式适用域或系数出处，不可替代论文和当前代码的直接证据。

**固定输入：**

- H1a 输入 run：`run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`；
- H1a 输入 MAT SHA-256：`4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b`；
- 异常点：`T=992.38742737169468 K`、`P=1007910.8613125964 Pa`；
- H1a 根区间低端路径：`T1=1515.109678670083 K`、`P1=1538809.802594816 Pa`、`Tlow=T1/pi`、`P2=674556.267925093 Pa`，其中活动 `pi=2.2812178550028612`；
- 正式模型 SHA-256：`5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`；
- 论文 PDF SHA-256：`983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a`。

---

## Task 1：建立 H2 只读合同与 RED 测试

**文件：**

- 新建：`tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m`
- 新建：`tests/steady53/analyze_task8_h2_hexe_property_readonly.m`

**Step 1：编写固定输入、禁止副作用和输出结构测试**

测试必须断言：

- 分析器拒绝错误的异常点、输入 MAT 哈希、模型哈希、属性函数哈希或论文 PDF 哈希；
- 源文件不得包含 `set_param`、`sim(`、`save_system`、`load_system`、`bdclose` 或写入 SLX/MAT 的路径；
- 输出至少包含 `inputs`、`sourceAudit`、`coefficients`、`derivatives`、`densityRoots`、`thermoIdentity`、`domainSweep`、`hypothesisVerdicts`；
- 测试只读比较受保护资产执行前后的 SHA-256。

**Step 2：运行精确 RED 测试**

```matlab
runtests('tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m')
```

预期：因分析器不存在或合同字段缺失而失败；记录精确失败名。

**Step 3：实现最小合同骨架**

只允许读取固定 MAT、论文 PDF 元数据和当前属性函数；不发布任何结论文件，直到 Task 2–4 全部通过。

**Step 4：运行合同测试并提交**

```bash
git add tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m tests/steady53/analyze_task8_h2_hexe_property_readonly.m
git commit -m "test: lock Task 8 H2 read-only property audit"
```

---

## Task 2：逐项复算 Virial 系数、导数与密度根

**文件：**

- 修改：`tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m`
- 修改：`tests/steady53/analyze_task8_h2_hexe_property_readonly.m`

**Step 1：为论文公式映射和中间量写 RED 测试**

测试要求：

- 明确映射 Eq. (2.7)–(2.17) 到当前函数行号和诊断字段；
- 保存 `B11/B22/B12/B`、`C111/C222/C112/C122/C`；
- 保存一、二阶解析导数及不少于三组步长的中心有限差分/Richardson 估计；
- 保存三次 EOS 的全部根、实根筛选、每个根的残差、`dP/drho` 符号、生产 Newton 迭代终值、迭代残差和 `max(rho_hat,0.9*P_RT)` 是否改变结果；
- 当前函数最终 `cp/gamma/rho` 与诊断复算必须在严格容差内一致，否则 fail closed。

**Step 2：实现纯诊断复算**

将当前活动公式逐项复算到结构体，但不复用函数内部未暴露的中间量。有限差分只对基础 `B(T)`、`C(T)` 及常压焓函数做独立检查，不拿相同解析式自证。

**Step 3：运行聚焦测试**

```matlab
runtests('tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m')
```

预期：所有系数、导数、根和生产输出一致性合同通过。

**Step 4：提交**

```bash
git add tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m tests/steady53/analyze_task8_h2_hexe_property_readonly.m
git commit -m "test: trace Task 8 H2 virial intermediates"
```

---

## Task 3：用独立热力学恒等式定位非物理来源

**文件：**

- 修改：`tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m`
- 修改：`tests/steady53/analyze_task8_h2_hexe_property_readonly.m`

**Step 1：写恒等式 RED 测试**

测试要求同时计算并比较：

1. 论文 Eq. (2.15) 的解析 `cp`；
2. 由论文对应残余焓 `h(T,P)` 在固定压力下做多步长中心有限差分得到的 `cp=(dh/dT)_P`；
3. 论文 Eq. (2.17) 的解析 `cv`；
4. EOS 恒等式
   `cp-cv = T*(dP/dT)_rho*(-drho/dT)_P/rho_hat^2`；
5. `gamma=cp/cv`。

分析器必须把一致性与物理域分开：公式数值互相一致不等于 `cp>0`、`cv>0`、`gamma>1`。

**Step 2：实现恒等式诊断和贡献分解**

把 `cp`、`cv` 分解为理想项、B 项、C 项、密度导数项；再把 C 项细分到 `C111/C222/C112/C122` 的一、二阶导数贡献，以找出负值的直接主导项。

**Step 3：运行测试并提交**

```bash
git add tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m tests/steady53/analyze_task8_h2_hexe_property_readonly.m
git commit -m "test: cross-check Task 8 H2 thermodynamic identities"
```

---

## Task 4：绘制局部失效域并给出三假设判决

**文件：**

- 修改：`tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m`
- 修改：`tests/steady53/analyze_task8_h2_hexe_property_readonly.m`
- 新建：`tests/steady53/test_publish_task8_h2_evidence.m`
- 新建：`tests/steady53/publish_task8_h2_evidence.m`
- 修改：`docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md`
- 修改：`docs/steady53_experiment_log.md`
- 新建（仅测试通过后发布）：`tmp/steady53/task8_root_cause/h2/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2_property_diagnostics.csv`
- 新建（仅测试通过后发布）：`tmp/steady53/task8_root_cause/h2/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2_summary.txt`

**Step 1：写局部扫掠 RED 测试**

沿 H1a 根区间低端的明示线性 `(T,P)` 路径，自适应加密所有 `cp=0`、`cv=0`、`gamma=1`、`dP/drho=0` 或导数不连续邻域；同时在异常点固定压力上做局部温度扫掠。要求输出边界括号和根残差，不得只给粗网格图形判断。

**Step 2：实现 fail-closed 判决**

- 若解析导数与独立差分不一致：`implementation_error` 得到支持，其他判决保持未定；
- 若生产 Newton 根不是满足稳定性/残差条件的唯一气相实根：`density_root_error` 得到支持；
- 若系数、导数、根及热力学恒等式全部一致，而物理域仍失败：仅可判为“当前论文关联式的直接实现确实在该点给出非物理解”；是否属于关联式适用域外，须由原始文献适用域证据另行定级；
- 任何证据不足都输出 `❓`，不得用“更接近论文目标”替代根因证据。

**Step 3：用独立发布器发布只读诊断结果并更新补遗**

报告记录全部输入哈希、公式页码、当前函数行号、精确异常区间、贡献分解和三假设判决。不得包含修复参数、裁剪值或替代物性实现。
分析器继续保持无写文件能力；单独的发布器只接受完整通过 fail-closed 合同的分析结构，先在同一父目录的唯一 staging 目录写入两个固定文件，再用一次目录级移动发布到精确固定输出目录。目标目录已存在、分析未完成、哈希不一致或判决字段不全时必须拒绝且不得覆盖。

**Step 4：完整验证**

```matlab
runtests('tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m')
runtests('tests/steady53/test_publish_task8_h2_evidence.m')
checkcode('tests/steady53/analyze_task8_h2_hexe_property_readonly.m','-id')
checkcode('tests/steady53/publish_task8_h2_evidence.m','-id')
```

获批范围禁止加载或仿真 SLX，因此不得执行整个 `tests/steady53` 目录；只执行已静态核实不触及 SLX 的 spec/evaluator/evidence/H1a/H2 离线子集，并只发现、不执行完整目录。再次核对受保护资产 SHA-256、归档 tag、固定输入 MAT、`git diff --check` 与 `git status --short`。

**Step 5：提交只读取证**

```bash
git add tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m tests/steady53/analyze_task8_h2_hexe_property_readonly.m tests/steady53/test_publish_task8_h2_evidence.m tests/steady53/publish_task8_h2_evidence.m docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md docs/superpowers/plans/2026-08-25-steady53-h2-hexe-property-readonly.md docs/steady53_experiment_log.md
git add -f tmp/steady53/task8_root_cause/h2/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3
git commit -m "test: record approved H2 He-Xe property root cause"
```

---

## 停止条件

发生下列任一情况立即停止并返回人工审核：

- 需要修改 `HeXe_property_simulink.m`、SLX、MAT、初值、效率或求解设置；
- 需要选择新的物性关联式、拟合系数、裁剪范围或密度根策略；
- 原始文献对适用域/符号存在冲突且本地证据不能消解；
- 分析器不能同时复现生产输出并通过独立恒等式检查；
- 任何正式模型或数据哈希发生变化。
