# 2026-09-01 稳态基线谱系组合 500 s 诊断结果

**状态：** 探索区单次实验已完成；不晋升正式模型  
**批准方案：** A（冻结 f8bcd83 方程/工况参数 + 根模型完整 40 状态初值向量）  
**原始证据目录：** `tmp/steady53_lineage_merge_20260901_A/`

## 1. 合同与执行事实

- ✅ 根模型 SHA-256：`a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159`。
- ✅ 冻结模型 SHA-256：`0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`。
- ✅ 候选模型 SHA-256：`5e540941d24d7488e0ef8420b3c6d1435b898dae681ddbfeacdd6abf13cf2ab2`。
- ✅ 40 个共同积分器均逐项采用根模型初值；其中 39 项发生数值变化，`TAC/rotor/N_rpm_Integrator` 在两版中原本均为 `55090`，因此 1 项不变。
- ✅ 根模型 `Unit Delay1` 不属于上述 40 状态向量，候选保持冻结模型值。
- ✅ 块清单、信号连线、非初值对话框参数及求解器参数审计均未变化。
- ✅ `run_steady53_case` 调用计数为 1，重试计数为 0；运行成功到达 500 s。
- ✅ `paper_reproduced=false`、`author_initial_state_identified=false`、`formal_promotion=false`。

以上事实来自同目录的 `candidate_audit.json`、`run/run_status.json` 和 `analysis.json`。

## 2. 图 5.19 四面板结果

| 面板 | 候选方向序列 | 论文固定方向 | 非平坦 | 候选 RMSE (kW) | 冻结基线 RMSE (kW) | RMSE 变化 (kW) |
|---|---|---|---:|---:|---:|---:|
| 反应堆功率 | `rise, fall` | `fall` | 是 | 189.448 | 237.551 | -48.103 |
| 涡轮功率 | 空序列（固定容差下无有效方向段） | `rise` | 是 | 64.661 | 63.964 | +0.697 |
| 压气机功率 | `rise, fall` | `fall, rise` | 是 | 345.401 | 29.450 | +315.952 |
| TAC 电功率（论文效率口径） | `fall, rise` | `rise, fall` | 是 | 298.542 | 34.544 | +263.998 |

✅ 四个面板的峰峰值均超过预先冻结的非平坦阈值，但方向匹配数为 0/4。机械分类为：

`lineage_initial_state_split_not_supported`

## 3. 可讲述结论与边界

- ✅ 该候选不是“仍然平坦”；完整根模型初值向量确实激发了明显瞬态。
- ✅ 这些瞬态没有恢复论文图 5.19 的方向结构，尤其压气机与 TAC 电功率方向恰好相反，并且 RMSE 明显恶化。
- ❓ 因此可以否定“只需把根模型 40 状态初值搬到冻结工况模型，就能解释论文曲线”的单因假设；不能据此判定剩余根因究竟是作者未公开初值、边界/参数谱系、方程实现还是多项共同作用。
- ✅ 本实验没有修改正式 `final_steady_24a.slx`、正式 MAT、物性函数或冻结 provenance；运行后 SHA-256 与运行前记录一致。
- ✅ 本结果不是论文复现，也不是正式模型修复，不触发第二候选、参数扫描或 14000 s 延伸。

## 4. 原始证据 SHA-256

| 文件 | SHA-256 |
|---|---|
| `candidate_audit.json` | `771a5476d5fa85e118df51bf99d5f81a94119286c3c9799e6f61951b62f79034` |
| `run/raw_result.mat` | `fb47a9f32ce54da0dbb3b76a629238dd52378d98892403a7e4dd3847b1b9209a` |
| `run/curves.csv` | `6c90777458b58f5acd196d8095d7131068b0f33f95b6f39dd58b296352692394` |
| `run/run_status.json` | `989f065abb71830e2d0c7e093eb2ec0698f83eccb35894971bfe82eb3cc00664` |
| `analysis.json` | `c706d8dd113eb06c0d4f1f80c59384c3c977fd139123a6e1d83e0aed8fb26ca3` |
| `comparison.csv` | `926e2c02d618e976f28fb75f7449a4017efcc0deb9ffc1e2901730f80bac6fcb` |
| `figure5_19_lineage_merge.png` | `07ba5a48afafee60f4625831cfcebc8484d59d5a93a93cd7d55e2f291a8a4918` |
