# Task 8 Root-Cause Addendum 草案：500 s 名义整机稳态点偏移

**日期：** 2026-08-24  
**状态：** RED，未批准，停在 Root-Cause Checkpoint  
**正式模型：** `final_steady_24a.slx`  
**正式模型 SHA-256：** `5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d`

## 1. 人工批准门

本文档只是根因实验草案，**不授权任何正式模型或 MAT 修改**。在用户明确
批准本补遗前，不得修改：

- `final_steady_24a.slx` 中的透平、回热器、冷却器、反应堆或 TAC 方程/参数；
- `HeXe_property_simulink.m` 的物性关联式或系数；
- `turbine_table1.mat` / `turbine_table2.mat` 或任何其他查表；
- 初值、符号、效率、换热系数或验收容差。

批准后也只允许先执行第 6 节的只读计算和临时副本实验；实验结果必须再次提交
人工审核，才能考虑任何生产修改。

## 2. 准确失败测试

本轮使用完整测试名精确选择，并在运行前断言选中项数正好为 `1`：

```text
test_final_steady_acceptance/testNominalCoupledModelMatchesSection531By500Seconds
```

- ✅ 本轮实测：`0 Passed, 1 Failed, 0 Incomplete`。
- ✅ 阻塞仿真本身成功：`success=true`、`tFinal_s=500`、`errorId=""`、
  `warningIds=[]`。
- ✅ 验收判定为 RED，首个失败标识为 `turbine_outlet_T:target`。
- ✅ 最终不可变运行证据目录：
  `tmp/steady53/task8/run_1787577681355_c27e98941c2d4673b269b0d14f579ac5/`。
- ✅ `nominal_500_report.mat` SHA-256：
  `f6bbefaaa2b5aa9c4af9f6198d2e20cdece89f5dd1df5578b64e70ff7ec46cf9`。

## 3. RED 的完整口径

✅ 最后 `400–500 s` 的所有已记录输出和状态都满足既定的末窗波动/趋势门；
本轮没有任何 `:peak_to_peak`或`:trend` 输出失败，状态最大相对峰峰值为
`1.2866786960e-5`，最大相对趋势为 `1.2598533948e-5`。因此，当前现象是
**已收敛到错误的稳态工作点**，不是 `500 s` 时仍在明显漂移。

✅ 失败标识全集为：

```text
turbine_outlet_T:target
turbine_outlet_T:settling
compressor_inlet_T:target
compressor_inlet_T:settling
compressor_outlet_T:target
compressor_outlet_T:settling
recuperator_hot_outlet_T:target
recuperator_hot_outlet_T:settling
recuperator_cold_outlet_T:target
recuperator_cold_outlet_T:settling
cooler_cold_inlet_T:target
cooler_cold_inlet_T:settling
cooler_cold_outlet_T:target
cooler_cold_outlet_T:settling
reactor_power:target
reactor_power:settling
turbine_power:target
turbine_power:settling
compressor_power:target
compressor_power:settling
tac_electric_power:target
tac_electric_power:settling
mass:closure
```

✅ 全部 21 个目标的实际值、目标、相对误差、末窗峰峰值、趋势、永久进带时间和
通过标识在证据目录的 `metrics.csv` 中；`signal_window_audit.csv` 和
`state_window_audit.csv` 分别保存全部信号/状态的末窗数据。

✅ 审计结果：

- 8 个实际查表输入均在各自断点范围内；
- He-Xe 全时段范围 `397.6329219–1515.3874157 K`；
- 液态锂全时段范围 `1430.1015961–1587.6158057 K`；
- 物性 warning 为空；
- 质量闭合最大相对差为 `1.1454162022e-3`，超过已批准门限 `1e-6`。
  最大差发生在 `t=0`：透平质量流量为 `11.9837137735 kg/s`，其余四个
  He-Xe 回路观测点均为 `11.97 kg/s`；锂侧闭合差为 `0`。

## 4. 首个失败信号的真实路径、端口、单位与方程

### 4.1 信号路径

- ✅ 验收信号 `turbine_outlet_T` 来自 `final_steady_24a/TAC` 的 Outport 3。
- ✅ TAC 内部对应 `final_steady_24a/TAC/Turbine/T_out`，其 Outport 号为 `3`。
- ✅ `T_out` 由 `From20` 的 `T2` tag 驱动；`T2` 由
  `final_steady_24a/TAC/Turbine/MATLAB Function1` 的第 1 个输出进入 `Goto10`。
- ✅ 这些 Inport/Outport 的 Simulink `Unit` 属性保存为 `inherit`；按论文公式、
  物性函数接口和验收规格，`T1/T2/T2s` 的物理语义单位为 K，`P1/P2` 为 Pa，
  `cp1/cp2` 为 J/(kg·K)，`N` 为 rpm，`mdot` 为 kg/s，`γ/φ/π/η` 无量纲。

### 4.2 当前活动方程

✅ `final_steady_24a/TAC/Turbine/MATLAB Function`：

```matlab
T2s = T1 * pi^(-phi);
```

✅ `final_steady_24a/TAC/Turbine/Fcn`：

```matlab
phi = 1 - 1/gamma;
```

✅ `gamma` 来自 `HeXe_Properties (point 1)` 对
`HeXe_property_simulink(T_in,P_in)` 第 2 输出的单点调用。

✅ `final_steady_24a/TAC/Turbine/MATLAB Function1`：

```matlab
T2 = T1 - (neta*cp2*(T1-T2s))/cp1;
```

✅ `cp1` 和 `cp2` 分别来自入口点 `1` 和等熵出口点 `2s` 的
`HeXe_property_simulink` 单点 `cp` 输出。

### 4.3 论文方程的本轮直接复核

- ✅ 论文 PDF 第 38 页（印刷页 23）Eq. (2.28) 使用透平进出口的**平均绝热系数**
  `φ̅_1-2`，且 `π=p1/p2`。
- ✅ 论文 PDF 第 39 页（印刷页 24）Eq. (2.30) 使用实际过程 `1-2` 与理想过程
  `1-2s'` 的**平均定压比热**；Eq. (2.31) 使用 `cp̅_1-2(T1-T2)` 计算透平功。
- ✅ 论文 PDF 第 88 页（印刷页 73）表 4.9 直接给出 TOPSIS 方案 B 的
  `η_T=0.87`。
- ✅ 论文 PDF 第 104 页（印刷页 89）表 5.2 直接给出仿真的透平出口温度
  `1162.00 K` 与透平功率 `2252.2 kW`。

## 5. 本轮数值复算与可证伪候选

✅ 用最终时刻输入对当前块方程离线复算：

| 量 | 当前值 |
|---|---:|
| `T1` | `1515.109678670083 K` |
| `P1` | `1538809.802594816 Pa` |
| `P2` | `674556.267925093 Pa` |
| `pi` | `2.281217855002861` |
| `gamma(point 1)` | `1.665824326170285` |
| `phi(point 1)` | `0.399696604083703` |
| `T2s` | `1089.647518112211 K` |
| `cp1(point 1)` | `519.656781110474 J/(kg·K)` |
| `cp2(point 2s)` | `519.658066226693 J/(kg·K)` |
| `eta` 查表值 | `0.872869608810761` |
| 方程复算 `T2` | `1143.735770611176 K` |
| 仿真记录 `T2` | `1143.735770611176 K` |

✅ 这证明信号记录与当前透平块方程完全一致，不是端口选错或单位换算造成的
`18.264 K` 差值。

- ✅ 把查表效率从 `0.8728696` 单独换成论文表 4.9 的 `0.87`，其他当前
  量不变时，离线计算仅使 `T2` 从 `1143.736 K` 变为 `1144.957 K`。
- ❓ 在继续沿用当前单点 `gamma/cp` 口径的假设下，反算得到目标 `1162 K`
  所需 `eta≈0.8299417`。该数是反算值，不是论文值，不能用于调参。

**根因候选 H1（❓）：** 当前透平实现把入口/出口单点 `gamma/cp` 直接放入 Eq. (2.28)、
Eq. (2.30)，而论文明确要求过程平均量。这个语义差异可能使等熵出口温度和实际
出口温度偏移。它是可证伪候选，尚未证明是唯一或足量根因。

**根因候选 H2（❓）：** 如果按论文平均量复算仍不能解释偏差，则需逐项核对
`HeXe_property_simulink` 在当前 `T/P` 下的 `gamma/cp` 与论文 Eq. (2.8)–(2.17) 及原始系数。
本轮不将物性函数注释中的出处声明等同于数学实现已全部复核。

## 6. 待批准的最小实验计划

1. **只读方程工作表**  
   使用本轮 `500 s` 时序输入，离线计算并对比：
   - 当前单点 `gamma/cp` 公式；
   - 论文 Eq. (2.28)/(2.30) 的过程平均量公式。
   平均量的数值积分路径和压力路径必须在实验前明示，结果按“数值实现选择”标注，
   不写回模型。

2. **临时副本单变量实验 H1**  
   仅在 `tmp/steady53/` 的唯一命名副本中，用论文的过程平均 `gamma/cp` 口径替代透平两个
   MATLAB Function 的单点口径。保持 `eta` 查表、所有 MAT、压损、初值和其他部件不变。
   先运行 TAC 恒边界，再运行整机 `500 s`；同时对比 `T2/T2s/WT`、物性域、查表域和
   全部 Task 8 指标。

3. **只读物性溯源 H2（仅在 H1 被证伪时）**  
   逐项比对 `HeXe_property_simulink.m` 与论文 Eq. (2.8)–(2.17)及其引用的原始关联式，先生成
   `T/P -> cp,gamma` 只读对照表，不修改函数。

4. **质量闭合分支单独保留**  
   `mass:closure` 的最大差只出现在 `t=0` 初始代数工作点。先只读追踪
   `TAC/Turbine/mdot` 与其他四个 He-Xe 质量流量端口的初始方程/执行顺序，不允许
   为通过门限直接改初值或忽略 `t=0`。

## 7. 停止条件

任一实验如需更改正式 SLX/MAT、物性系数、效率表、初值、验收门槛，或如果单变量
实验不能证伪/支持 H1，立即停止并返回人工审核；不允许叠加第二个猜测式参数修改。
