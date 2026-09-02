# 稳态根模型与冻结证据模型的行为差异

`baseline_lineage_behavior_diff.csv` 是只读谱系证据，不是修改指令，也不表示任一模型已经通过论文验收。

## 对象

- 根模型：`final_steady_24a.slx`
  - SHA-256：`a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159`
- 冻结证据模型：`data/provenance/baselines/f8bcd83/final_steady_24a.slx`
  - SHA-256：`0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`

## 口径

- `53` 行 `dialog_parameter/solver_parameter` 与既有 Simulink 官方 API 审计数量一致：
  - `40` 行初值差异（39 个 Integrator + 1 个 Unit Delay）；
  - `12` 行其他块参数差异；
  - `1` 行模型 `StopTime` 差异。
- 另列根模型独有的 `4` 个 TAC Goto/From 块；它们是结构差异，不计入上述 53 个值差异。
- CSV 本次由 SLX 只读解包生成：从 `system_root` 递归解析 subsystem 引用，按相对块路径比较非布局块参数，并单独读取 `configSet0.xml` 的 `StopTime`。没有写入、加载、编译或仿真 SLX。
- 布局/显示元数据不进入清单；不能据此声称两个 SLX 除清单外字节相同。
- 既有官方 API 数量证据见 `docs/superpowers/specs/2026-09-01-steady53-baseline-lineage-merge-diagnostic-design.md`；科学解释见 `docs/2026-09-02-steady53-rootcause-evidence-matrix.md`。

## 固定结论边界

```text
paper_reproduced = false
formal_promotion = false
```
