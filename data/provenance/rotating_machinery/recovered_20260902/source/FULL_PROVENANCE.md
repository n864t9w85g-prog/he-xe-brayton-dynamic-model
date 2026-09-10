# Xu2022 Paper-Style Equivalent Lookup — 完整来源与生成说明

> 结论：本数据集不是徐驰论文作者的原始 Lookup Table。论文没有公开 breakpoints 和 table matrices。
> 本数据集是依据论文查表拓扑、论文公开稳态/动态工况、He-Xe 物性模型，以及同工质径流透平/离心压缩机文献曲线形状重建的“论文式等效查表数据”。

## 1. 最终四张表

- Compressor pressure ratio: PRc = f(mdot, N)
- Compressor efficiency: eta_c = f(mdot, N)
- Turbine mass flow: mdot_t = f(PRt, N)
- Turbine efficiency: eta_t = f(mdot_t, N)

最终 MAT:
`Xu2022_PaperStyle_Equivalent_Lookup.mat`

## 2. 一级来源：徐驰 2022 博士论文

论文第 5 章决定了最终查表的拓扑和主要绝对工况锚点。

### 2.1 查表拓扑

论文图 5.3/5.5 和公式 (5.8)-(5.11) 给出压缩机/透平性能曲线与质量流量、入口状态、转轴转速的关系。
在论文 Simulink 拓扑中，本数据集采用：

- PRc = f(mdot, N)
- eta_c = f(mdot, N)
- mdot_t = f(PRt, N)
- eta_t = f(mdot_t, N)

### 2.2 第 4 章方案 B（早期锚点，最终只保留为历史约束）

TOPSIS 方案 B：
- reactor outlet temperature: 1600 K
- cold-end temperature: 360 K
- max pressure: 1.55 MPa
- cycle pressure ratio: 2.37
- turbine efficiency: 0.87
- compressor efficiency: 0.85
- specific work: 93.56 kJ/kg
- system efficiency: 37.69%

早期阶段曾由 (2253-1233)/93.56 得到 10.9021 kg/s。
这个值后来被废弃，因为它把第 4 章比功和第 5 章部件功率混在一起。

### 2.3 第 5 章 Table 5.2（最终绝对设计锚点）

仿真稳态值：
- turbine Tin = 1522.96 K
- turbine Pin = 1.539 MPa
- turbine Tout = 1162.00 K
- turbine Pout = 0.676 MPa
- compressor Tin = 405.16 K
- compressor Pin = 0.658 MPa
- compressor Tout = 601.90 K
- compressor Pout = 1.551 MPa
- turbine power = 2252.2 kW
- compressor power = 1231.6 kW
- electric power = 1000.21 kWe

由此：
- PRc = 1.551/0.658 = 2.357142857
- PRt = 1.539/0.676 = 2.276627219

## 3. 二级来源：HeXe_property_simulink.m

组成：
- x_He = 0.7172
- x_Xe = 0.2828
- M_He = 4.0026e-3 kg/mol
- M_Xe = 131.293e-3 kg/mol

加权摩尔质量约 40.0003 g/mol。

物性程序用 Virial EOS 计算 cp、gamma 等。
在 Table 5.2 节点处得到：
- compressor cp_avg = 520.038257 J/(kg K)
- compressor gamma_avg = 1.666852416
- turbine cp_avg = 519.654386 J/(kg K)
- turbine gamma_avg = 1.666075065

利用论文部件功率能量关系反算流量：

compressor:
mdot_c = 1231600 / [520.038257*(601.90-405.16)]
       = 12.037650 kg/s

turbine:
mdot_t = 2252200 / [519.654386*(1522.96-1162.00)]
       = 12.006966 kg/s

采用两者均值：
mdot_design = 12.022308 kg/s

两种独立反算仅差约 0.255%。

利用同一 gamma 和等熵温度关系推导动态设计点效率：
- eta_c = 0.842737535
- eta_t = 0.845605188

注意：这两个效率是“由论文 T/P 节点 + 物性模型推导”，不是作者公开的原始 Lookup 单元格。

## 4. 三级来源：Gallo, El-Genk & Tournier 2007

文献：
B. M. Gallo, M. S. El-Genk, J.-M. Tournier,
“Compressor and Turbine Models of Brayton Units for Space Nuclear Power Systems,”
AIP Conference Proceedings 880, 472–482 (2007),
DOI 10.1063/1.2437488.

作用：
- 提供 He-Xe 40 g/mol 工质下离心压缩机和径流透平的非设计性能曲线形状；
- 提供不同轴速和入口 Mach 下 PR/efficiency/flow 的相对趋势。

没有直接使用其绝对质量流量作为徐驰兆瓦级设备数据，因为该文硬件尺度不同。

第一版视觉数字化文件：
`HeXe40_Master_Digitized_v1.csv`

例如 40 krpm 的近似数字化点：

compressor:
flow kg/s = [0.097279, 0.118312, 0.139345, 0.160378, 0.181411, 0.202445, 0.223478]
PR        = [1.36, 1.43, 1.453111, 1.442, 1.37, 1.262, 1.10]
eta       = [0.740, 0.760, 0.770667, 0.765, 0.71675, 0.605, 0.400]

turbine:
flow kg/s = [0.220659, 0.239047, 0.257436, 0.275824, 0.294212, 0.312600, 0.330989]
PR        = [1.35, 1.404444, 1.464444, 1.545, 1.65, 1.855, 2.10]
eta       = [0.888, 0.901611, 0.907037, 0.909167, 0.904410, 0.892889, 0.875]

这些数值是从论文图中近似数字化得到，不是 Gallo 作者原始数组。

## 5. 四级来源：NASA Galvas 1973

Michael R. Galvas,
“FORTRAN Program for Predicting Off-Design Performance of Centrifugal Compressors,”
NASA TN D-7487, 1973.

作用仅为压缩机物理趋势/边界约束：
- 每条转速线工作范围位于 surge 与 choke 之间；
- 压比、效率随流量的合理变化趋势；
- 一维模型在 choke/surge 边界附近误差可能明显增大。

没有把 Galvas 的某张数值 map 直接缩放成徐驰 map。

更重要的是：徐驰论文参考文献 [162] 就是 Galvas D-7487，它是“离心压缩机”报告，不是透平原始数据源。因此徐驰论文对透平性能曲线的引用链本身存在缺口。

## 6. 辅助交叉检查来源（不直接提供最终数值）

### El-Genk, Tournier & Gallo 2010
“Dynamic Simulation of a Space Reactor System with Closed Brayton Cycle Loops,”
Journal of Propulsion and Power 26(3), 394–406,
DOI 10.2514/1.46262.

用途：
- 40 g/mol He-Xe；
- 检查径流透平、离心压缩机 map 的总体形状；
- 检查转速变化时 flow/PR 的方向趋势；
- 不直接使用其 UNM-BRU-1 数值，因为其功率等级和徐驰系统不同。

### Gallo & El-Genk 2009
“Brayton rotating units for space reactor power systems,”
Energy Conversion and Management 50(9), 2210–2232,
DOI 10.1016/j.enconman.2009.04.035.

用途：
- 40 g/mol He-Xe BRU 设计范围和径流透平/离心压缩机背景交叉检查；
- 不直接作为徐驰 lookup 原表。

## 7. 初版母曲线如何从“小型同工质曲线”变成“徐驰兆瓦级候选曲线”

初版使用 Gallo 2007 的“形状”，不使用其绝对尺度。

目标速度线最初设为：
- 0.4 Nd
- 0.6 Nd
- 0.8 Nd
- 1.0 Nd
其中 Nd = 55090 rpm。

压缩机初版：
- 保留每条 Gallo 曲线沿流量方向的归一化形状；
- 初始峰值压比假设：
  PR_peak(s) = 1 + (2.37-1)*s^2
- 初始峰值效率假设：
  eta_peak(s) = 0.85 - 0.10*(1-s)^1.2
- 这些公式是重建假设，不是徐驰论文公式。

透平初版：
- 保留 Gallo 径流透平 PR/eta 曲线形状；
- 用缩放系数使满速目标点落到当时的设计 PR/eta；
- 设计 line-coordinate 取 q≈0.90；
- q 只是内部重建坐标，不是徐驰论文变量。

## 8. Stage 7 最终绝对尺度重标定

发现 10.9021 kg/s 是跨章节混算后，最终中央 map 改用第 5 章动态证据。

旧值：
mdot_old = 10.90209491 kg/s

新值：
mdot_new = 12.02230808 kg/s

压比缩放：
PRc_new = 1 + k_c*(PRc_old-1)
k_c = (2.357142857-1)/(2.37-1)
    = 0.990615224

PRt_new = 1 + k_t*(PRt_old-1)
k_t = (2.276627219-1)/(2.298507463-1)
    = 0.983149697

效率缩放：
eta_c,new = 0.991455924 * eta_c,old
eta_t,new = 0.971959986 * eta_t,old

流量坐标修正：
- 在 40% 速度线保持原 Stage-III 附近尺度；
- 从 40% 到 100% 线性增加修正；
- 满速时总修正量为 12.02230808 - 10.90209491 kg/s。

因此最终中央 map 的绝对尺度主要由 Xu Chapter 5 决定，曲线的非设计“形状骨架”主要来自 Gallo 2007。

## 9. 论文公开动态工况对速度范围的约束

Xu Chapter 5 直接给出：
- Stage III: 40% full speed = 22036 rpm，He-Xe flow ≈ 10.02 kg/s
- Stage IV: full speed = 55090 rpm
- 950 kW load disturbance steady speed = 59655 rpm
- 1000 kW = 55090 rpm
- 1050 kW = 50610 rpm

因此只做到 55090 rpm 不足以覆盖论文动态运行范围。

## 10. 100%–110% 转速数据从哪里来

55090 rpm 以上没有原作者 map。

为了覆盖论文 59655 rpm 工况，Stage 9 增加 TEST-ONLY 外推：

对每个相同 line-coordinate q，使用 90% 到 100% 的局部变化趋势线性外推到 110%。

质量流量：
m(N) = m100 + a*(m100-m90)

压比：
PR(N)-1 = (PR100-1) + a*[(PR100-1)-(PR90-1)]

效率：
eta(N) = eta100 + a*(eta100-eta90)

其中：
a = (N-N100)/(N100-N90)

效率最终限制在 0.20–0.95。

这部分是明确的数值外推，不是论文原始数据。

## 11. 最终矩形 Lookup Table 如何生成

最终轴：

- N_bp: 281 points, 22036 to 60599 rpm, step 137.725 rpm
- mC_bp: 512 points, 6.80 to 17.02 kg/s, step 0.02 kg/s
- PRt_bp: 346 points, 1.030 to 2.755, step 0.005
- mT_bp: 374 points, 5.50 to 12.96 kg/s, step 0.02 kg/s

从母速度线做一维线性插值形成矩形表：

- PRc_tbl(N, mdot)
- etac_tbl(N, mdot)
- mT_tbl(N, PRt)
- etat_tbl(N, mdot)

透平质量流量表是通过每条速度线上单调 PR-flow 曲线反插得到。

## 12. 哪些东西“来自论文”，哪些“不是”

### 直接或高可信来源于 Xu 论文
- 查表模块拓扑
- 55090 rpm 满速
- 22036 rpm / ~10.02 kg/s Stage III
- Table 5.2 T/P/power
- 950/1000/1050 kW 对应 59655/55090/50610 rpm
- 由 Table 5.2 直接得到的 PRc、PRt

### 由论文 + He-Xe 物性推导
- 12.022308 kg/s 满功率流量
- 0.8427375 compressor design efficiency
- 0.8456052 turbine design efficiency

### 来自外部同工质文献的形状信息
- 非设计压缩机曲线形状
- 非设计径流透平曲线形状
- 不同转速下的相对趋势

### 完全属于本次重建算法
- Gallo 图像数字化后的离散点
- 从小 BRU 到 Xu MW 机器的缩放
- 40%–100% 中间速度线插值
- 100%–110% 外推
- 最终矩形网格的点数/步长
- 所有未被论文公开数据直接约束的 lookup 单元格

## 13. 最终结论

正确名称是：

`Xu2022 paper-style equivalent reconstructed lookup data`

不能称为：

`Xu2022 original lookup data`

因为没有任何来源证明最终矩阵里的每个单元格与作者原始 .mat/.slx 数据相同。

它的目标是：
1. 查表关系与论文一致；
2. 工质与论文一致；
3. 设计/稳态/启动/负载范围尽可能受论文公开数据约束；
4. 非设计曲线形状使用同工质径流透平/离心压缩机文献做物理约束；
5. 所有无原始数据支撑的部分明确标注为 reconstructed / extrapolated。
