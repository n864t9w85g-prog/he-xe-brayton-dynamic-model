# 稳态基线谱系组合 500 s 诊断设计

**状态：** 用户已选择方案 A，待书面规格复核

**批准文本：** `A`
**目的：** 判断图 5.19 曲线丢失是否由“稳态工况修正”和“40 状态近稳态化”被同时引入同一冻结模型造成。

## 1. 已核实前提

✅ 仓库根 `final_steady_24a.slx` 的 SHA-256 为
`a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159`。

✅ 冻结模型
`data/provenance/baselines/f8bcd83/final_steady_24a.slx` 的 SHA-256 为
`0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`。

✅ Simulink 官方 API 比较得到：两者共有 53 项参数值差异，其中 40 项为同路径积分器的 `InitialCondition`；其余差异包括负荷、TAC 常量、换热参数、散热器参数表达式、模型停止时间和一个增益。根模型另有四个 TAC Goto/From 块。

✅ 根模型具有明显功率瞬态但工况参数与论文稳态点不一致；冻结模型的工况更接近论文稳态点，但 40 状态均在当前边界下接近稳态，500 s 功率曲线近乎平坦。

✅ 论文图 5.19 描述系统主要部件在稳态前的功率变化并称约 230 s 趋稳，但没有公开完整作者初始状态向量。

## 2. 唯一实验变量

候选以冻结模型为源，保持其全部方程、拓扑、查表、常量、边界和求解器配置不变，只进行一项向量替换：

> 将冻结模型中与根模型同路径的全部 40 个积分器 `InitialCondition`，逐项替换为根模型对应值。

该操作把“初值向量来源”视为一个完整实验变量。不得只挑选其中更接近论文的状态，也不得在运行后调整任何初值。

## 3. 实施边界

- 只在 `tmp/` 私有目录创建候选副本和结果。
- 使用 MATLAB/Simulink 官方 API 读取和设置参数；不修改 SLX/XML 底层文件。
- 正式根 SLX、正式 MAT、物性函数和冻结 provenance 字节保持不变。
- 候选必须验证 exact 40 路径一一对应，且除 40 个 `InitialCondition` 外没有参数或拓扑变化。
- 使用冻结 runtime 和现有 `run_steady53_case`，只运行一次 500 s。
- 不使用 A3 attempt 标识或 A3 one-shot runner；本实验是已批准的谱系诊断，不改写 A1/A2/A3 历史。
- 不扫描、不拟合、不平移时间、不平滑、不改变论文数字化点或比较容差。
- 运行结束后不自动延伸到 14,000 s，不晋升正式模型。

## 4. 输出与判据

必须保存：

1. 两个源模型 SHA-256；
2. 40 条旧/新初值记录；
3. 候选 SHA-256 和参数/拓扑差异审计；
4. 原始 500 s MAT 与四条功率 CSV；
5. 与固定 `paper_points.csv` 的四面板叠图；
6. 起点、终点、峰谷、峰谷时刻、方向序列、非平坦结果和 RMSE。

结论只允许分为：

- `lineage_initial_state_split_supported`：数值运行成功，且四面板方向/非平坦门整体明显优于冻结平坦基线；这只支持版本谱系是重要原因，不证明作者初值已识别。
- `lineage_initial_state_split_partially_supported`：仅部分面板恢复论文方向或明显瞬态。
- `lineage_initial_state_split_not_supported`：仍平坦或整体方向没有恢复。
- `numerical_or_contract_failure`：未完成 500 s 或唯一变量合同被破坏。

无论结果如何，`paper_reproduced`、`author_initial_state_identified` 和 `formal_promotion` 均保持 `false`，除非后续另有独立证据和正式批准。

## 5. 停止条件

一次 500 s 结果完成并发布对比后立即停止。报告实际数据，再决定是追查作者初值来源、定位剩余方程/参数差异，还是淘汰该谱系假设；不得自动生成第二候选。
