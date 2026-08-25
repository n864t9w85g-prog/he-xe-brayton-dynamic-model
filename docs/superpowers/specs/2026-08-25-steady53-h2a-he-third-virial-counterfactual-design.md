# Steady 5.3 Task 8 H2a：忽略 He 三阶 Virial 项的只读反事实实验设计

**日期：** 2026-08-25

**状态：** 已获人工批准的设计，待书面规格复审

**实验区域：** `tests/` 与 `tmp/`，不得进入正式模型
**固定输入 run：** `run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3`

## 1. 目标

在不修改 `HeXe_property_simulink.m`、任何 SLX/MAT/PDF、求解器、验收标准或
正式物理参数的前提下，执行一个严格单变量的离线反事实实验：按原始来源对 He
三阶 Virial 系数采用“忽略”处理，重新计算固定异常点、固定压力局部温度域以及
H1a 明示线性 `(T,P)` 路径上的 `cp/cv/gamma` 与必要的 EOS 诊断量。

本实验只回答：

> 在其他公式、输入和根策略全部保持不变时，忽略 He 三阶 Virial 项会怎样改变
> 当前异常点及两条指定路径上的热力学性质？

本实验不判断该反事实是否应晋升为正式物性模型，也不继续执行 H1a 积分或整机仿真。

## 2. 人工批准的唯一变量

### 2.1 baseline 分支

baseline 必须保持当前论文/正式物性函数的三阶 Virial 口径：

```text
C111 = 当前 He 三阶关联式
C112 = cbrt(C111^2*C222)
C122 = cbrt(C111*C222^2)
C    = xHe^3*C111
     + 3*xHe^2*xXe*C112
     + 3*xHe*xXe^2*C122
     + xXe^3*C222
```

`cbrt` 表示带符号的实数三次根。baseline 的一、二阶温度导数必须与当前 H2
审定公式一致。

### 2.2 counterfactual 分支

唯一反事实开关固定为：

```text
C111          = 0
dC111/dT      = 0
d2C111/dT2    = 0
```

继续严格沿用 baseline 的混合规则后，计算后果固定为：

```text
C112          = 0
C122          = 0
dC112/dT      = 0
dC122/dT      = 0
d2C112/dT2    = 0
d2C122/dT2    = 0

C             = xXe^3*C222
dC/dT         = xXe^3*dC222/dT
d2C/dT2       = xXe^3*d2C222/dT2
```

`C112/C122` 的变化是上述单一开关经当前混合规则产生的计算后果，不是第二个
独立调节变量。

### 2.3 必须固定不变的量

两分支必须逐项共用：

- `B11/B22/B12/B` 及其一、二阶导数；
- He/Xe 摩尔分数、摩尔质量、临界参数和气体常数；
- 三阶 Virial EOS 形式；
- 全三次根求解、实根筛选、稳定性判断和生产 Newton 初值/迭代/夹取策略；
- 理想气体 `cp/cv` 项；
- 论文 Eq. (2.15)–(2.17) 的 `cp/cv/gamma` 公式；
- 固定异常点、固定压力、H1a 路径端点及所有数值容差；
- 所有输入文件与保护资产哈希。

不得加入裁剪、拟合、插值补丁、理想气体替代、其他混合规则或第二个物性修正。

### 2.4 原始来源身份

方案 A 的来源证据固定为：

```text
Tournier, El-Genk and Gallo
Best Estimates of Binary Gas Mixtures Properties for Closed Brayton Cycle Space Applications
AIAA 2006-4154
DOI: 10.2514/6.2006-4154
https://www.researchgate.net/publication/268572975_Best_Estimates_of_Binary_Gas_Mixtures_Properties_for_Closed_Brayton_Cycle_Space_Applications
```

作者公开全文将其 Eq. (11) 的三阶 Virial 拟合明示用于 Ne/Ar/Kr，并说明 He
三阶 Virial 系数可忽略。该来源只支持把方案 A 作为已批准的反事实输入；它不自动
证明方案 A 是当前论文混合物模型的唯一正确替代。

## 3. 实现架构

采用独立 H2a 双分支分析器，不修改已审定 H2 分析器或 H2 正式证据。

### 3.1 H2a 分析器

计划新增：

```text
tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m
```

职责：

1. fail closed 核对固定输入和全部保护哈希；
2. 只读调用现有 H2 分析器取得已审定 baseline 证据；
3. 用 H2a 内部的双分支 evaluator 独立重算 baseline；
4. baseline 与 H2 证据一致后才允许计算 counterfactual；
5. 在三个指定域内并列计算两分支；
6. 返回内存结构，不写任何文件。

分析器不得包含 `set_param`、`sim`、`load_system`、`save_system`、
`open_system`、`bdclose` 或文件写入 API。

### 3.2 独立发布器

计划新增：

```text
tests/steady53/publish_task8_h2a_evidence.m
```

职责：

- 只接受完整、哈希匹配且 baseline parity 通过的 H2a analysis；
- 结果是否改善不得作为发布前提；
- 在目标同父目录建立唯一 staging；
- staging 中完整写入、关闭、重读并计算哈希；
- 使用一次无覆盖目录级移动发布；
- 目标已存在、竞态碰撞、字段缺失或哈希不一致时拒绝并清理本次 staging；
- 不得覆盖任何既有 H2/H2a 证据。

固定正式输出目录计划为：

```text
tmp/steady53/task8_root_cause/h2a/
  run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/
```

固定文件名：

```text
h2a_counterfactual_diagnostics.csv
h2a_summary.txt
```

## 4. 固定输入与保护合同

### 4.1 固定状态

```text
exceptionT_K = 992.38742737169468
exceptionP_Pa = 1007910.8613125964

T1_K = 1515.109678670083
P1_Pa = 1538809.802594816
expansionRatio = 2.2812178550028612
Tlow_K = T1_K/expansionRatio
P2_Pa = 674556.267925093
```

H1a 明示路径为：

```text
T(lambda) = T1 + lambda*(Tlow - T1)
P(lambda) = P1 + lambda*(P2 - P1)
lambda in [0,1]
```

### 4.2 固定哈希

```text
final_steady_24a.slx
5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d

HeXe_property_simulink.m
2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2

hexe_compressor_lookup.mat
f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579

radiator_table.mat
3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304

turbine_table1.mat
10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d

turbine_table2.mat
cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33

固定 H1a 输入 MAT
4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b

论文 PDF
983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a

archive/pre-restart-20260824 peeled commit
8f625c268c35a95c18a626305c1aa6a79ae2ace7
```

分析器必须在计算前后核对保护资产，发布器必须再次验证 analysis 中的身份字段。

## 5. baseline 一致性门

H2a 不得用自己新写的公式直接证明自己。内部 baseline 分支必须与当前 H2 已审定
证据进行独立 parity：

### 5.1 固定异常点 parity

至少比较：

- `B11/B22/B12/B`；
- `C111/C222/C112/C122/C`；
- `dB/dT`、`d2B/dT2`、`dC/dT`、`d2C/dT2`；
- 全部 EOS 实根、稳定正实根数量、生产 Newton 终值和夹取状态；
- `rho/cp_molar/cv_molar/cp_mass/gamma`；
- `cp/cv` 贡献分解。

### 5.2 路径 parity

至少比较当前 H2 已审定边界：

```text
C111=0: 992.38240920882117 K

fixed pressure cp=0: 992.3980970081318 K
fixed pressure cv=0: 992.40367034763892 K

H1a path cp=0:
lambda=0.61427357048046893

H1a path cv=0:
lambda=0.61426702062376992
```

H2a baseline 任一 parity 超过固定容差时，analysis 必须失败，counterfactual 和正式
输出均不得产生。

## 6. 三个计算域

### 6.1 固定异常点

baseline 与 counterfactual 并列输出：

- `C111/C222/C112/C122/C` 及一、二阶温度导数；
- 全三次 EOS 根、每根残差和 `dP/drho`；
- 生产 Newton 根、夹取前后状态；
- `rho`；
- `cp_molar/cv_molar/cp_mass/cv_mass/gamma`；
- `cp/cv` 的理想项、B 项、C 项和密度导数项；
- counterfactual 相对 baseline 的绝对和相对变化。

### 6.2 固定压力局部温度域

固定：

```text
P = 1007910.8613125964 Pa
T in [C111ZeroT-0.1, C111ZeroT+0.1] K
```

即约 `992.282409208821–992.482409208821 K`。

baseline 与 counterfactual 使用相同粗网格和自适应策略，检查：

- `cp=0`；
- `cv=0`；
- `gamma=1`；
- `dP/drho=0`；
- 非有限或复数状态；
- 稳定正实密度根数量；
- 每个根的括号、残差和两侧符号；
- baseline 的 `C111=0` 导数不连续是否在 counterfactual 中消失。

粗网格只允许用于发现候选括号，不得用图形或网格最近点代替根求解。

### 6.3 完整 H1a 明示路径

在 `lambda in [0,1]` 上对两分支并列计算：

- `T/P/rho/cp/cv/gamma/dPdrho`；
- 每个量的最小值、最大值及对应 `lambda/T/P`；
- `cp<=0`、`cv<=0`、`gamma<=1` 的连续区间；
- `cp=0/cv=0/gamma=1/dPdrho=0` 的全部根；
- 非有限/复数状态和稳定正实根数量；
- H1a 原异常坐标的 baseline/counterfactual 前后对比。

不得在本任务中把路径物性结果送入 `phi` 积分、`T2s/T2` 或任何整机模型。

## 7. 结果与证据分级

H2a 不设置“counterfactual 必须改善”或“必须恢复正比热”的验收门。

- ✅ baseline parity：当前代码与已审定 H2 证据的一致性；
- ✅ counterfactual 数值：批准的方案 A 下可复现的计算后果；
- ⚠️ counterfactual 物理解释：原始来源提示支持的探索性建模候选，尚未完成
  独立数据验证或整机验证；
- ❌ 正式模型正确性/晋升：本任务不支持、不授权；
- ❓ H1a 与 14000 s 稳态：本任务结束时仍保持未判定/未完成。

如果 counterfactual 仍出现负比热、`gamma<=1`、非有限量、无稳定正实根或其他
非物理状态，必须如实记录，不得增加第二个修改来改善结果。

## 8. 输出合同

CSV/TXT 必须自包含，至少记录：

- 实验状态和 `authorizesRepair=false`；
- 固定 run、状态点、路径公式和全部保护哈希；
- 原始来源 DOI/URL 与方案 A 的精确定义；
- baseline parity 字段与容差；
- 两分支异常点全量结果和差值；
- 两分支两条路径的搜索量、范围、边界计数、根、残差及物理域区间；
- baseline 的 C111 奇点与 counterfactual 的消失/保留判定；
- H1a-S2、Task 8 和 14000 s 状态仍未完成；
- 不得包含拟合参数、裁剪建议或自动晋升判断。

发布器不得把 `cp>0/cv>0/gamma>1` 作为发布前置条件；这些是实验结果，不是
结果筛选条件。发布前置条件仅包括身份、完整性、数值可追溯性和 baseline parity。

## 9. 测试策略

严格执行 RED→GREEN：

1. 固定哈希、禁止模型 API、禁止写入的分析器合同测试；
2. 方案 A 单变量测试，逐项证明 B/EOS/根策略等不变；
3. baseline 对当前 H2 的异常点与边界 parity 测试；
4. counterfactual 的 `C111/C112/C122` 和导数精确为零测试；
5. EOS、`cp/cv/gamma` 与贡献闭合测试；
6. 固定压力和 H1a 路径的自适应根/区间测试；
7. 不以结果改善为前提的反例测试；
8. 发布器缺字段、错哈希、空表、竞态、既有目标和中途失败测试；
9. CSV/TXT 自包含字段和磁盘哈希测试；
10. 只运行静态核实不会加载 SLX 的离线子集；完整 `tests/steady53` 只发现、不执行。

## 10. 完成条件

H2a 只有在以下条件全部满足时才可标记为只读实验完成：

1. 方案 A 是唯一反事实变量；
2. H2a baseline 完整通过 H2 parity；
3. 固定异常点、固定压力局部域和完整 H1a 路径均完成并发布；
4. 所有边界、非物理区和无根结果均可追溯；
5. counterfactual 无论改善与否均如实报告；
6. 聚焦测试与无 SLX 离线回归通过；
7. 分析器无写入和模型 API，发布器无模型 API；
8. 正式 SLX、物性函数、MAT、PDF 和归档 tag 哈希保持不变；
9. H2 既有分析器和固定 H2 输出未修改；
10. 输出明确不授权正式修复或晋升。

## 11. 停止条件

出现以下任一情况立即停止并返回人工审核：

- 需要修改 `HeXe_property_simulink.m`、H2 既有证据、任何 SLX/MAT/PDF；
- baseline 不能复现已审定 H2；
- 需要选择新的交互三阶系数、混合规则、裁剪值或第二个物性改动；
- 需要执行 H1a `phi` 积分、`T2s/T2` 或整机仿真；
- 需要根据“更接近论文”筛选或隐藏反事实结果；
- 任何保护哈希或归档标签发生变化。

## 12. 后续人工门

H2a 完成后只向用户提交结果和证据。是否：

- 承认方案 A 为值得进一步验证的物理候选；
- 批准只读恢复 H1a-S2 积分；
- 在探索模型中试验物性变化；
- 修改正式物性函数；

均属于新的人工批准事项，不由本设计自动授权。
