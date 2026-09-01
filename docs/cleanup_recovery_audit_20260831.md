# 2026-08-31 误清理恢复验收记录

## 1. 结论

- ✅ 误清理造成的关键 A1 基线缺失已经完成字节级恢复与 Git 固化。
- ✅ 清理前保护清单 34 行全部可由原路径或完全相同 SHA256 的耐久基线解析，未发现内容哈希不匹配。
- ✅ A1 运行时合同已从易失 `tmp/` 快照迁移到 Git 跟踪的 `data/provenance/baselines/f8bcd83/`。
- ✅ 中断的 Task 3 测试合同已经保存，其对应实现已按失败测试重新构建并通过离线测试。
- ⚠️ 本恢复只恢复文件身份和离线工装，不证明稳态、动态或论文曲线已经复现。

固定状态：

```text
paper_reproduced = false
formal_promotion = false
```

## 2. 来源与模型身份

✅ 恢复来源：

```text
/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型_副本
commit f8bcd833e816eb681982b7dd04364e4b856948e3
```

✅ 恢复文件：

| 文件 | 字节数 | SHA256 | 身份 |
|---|---:|---|---|
| `data/provenance/baselines/f8bcd83/final_steady_24a.slx` | 617390 | `0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391` | A1 唯一稳态权威源 |
| `data/provenance/baselines/f8bcd83/final_dynamic_24a.slx` | 660489 | `2bed798bcd3d32c15b7771907e8cd5452aa4171a0b87335af7c8769ed6987790` | 仅历史恢复证据 |

两份 SLX 均以不透明 Git blob 导出，没有加载、解包、仿真或编辑。恢复动态文件不恢复旧动态参数结论的可信状态。

## 3. 保护清单审计

✅ 事故前清单：

```text
tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv
SHA256 496e4bbbbe5786bbb21b63d3c320dcfdf3c741935736624ed2912ab81afc9a0a
```

✅ 审计结果：

```text
rows = 34
resolved = 34
original_path_hash_match = 31
durable_hash_equivalent = 3
unresolved = 0
hash_mismatch = 0
```

3 个原路径缺失项为：

1. 当前仓库旧 `tmp/source_f8bcd83/final_steady_24a.slx`；
2. 副本仓库工作树 `final_steady_24a.slx`；
3. 副本仓库工作树 `final_dynamic_24a.slx`。

它们分别由耐久基线中的完全相同 SHA256 内容解析。逐行结果保存在：

```text
data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv
```

旧 `protected_after.csv` 未被修改。A1 合同仍验证其文件哈希、CSV 表头、34 行数量、绝对路径格式、路径唯一性和哈希格式，但不再要求另一工作区的绝对路径在每次运行时存在。

## 4. 中断 Task 3 恢复

✅ 中断测试工作树 blob：

```text
e47b25b0fa1d1c9e45d4d7251a3f5094cdff31b2
```

✅ 测试先以单独提交 `7bf076b` 保存，随后旧实现的真实红灯结果为：

```text
34 tests
24 failures
4 errors
```

主要缺口：

- 来源行身份检查不完整；
- 代理热容派生量的溢出、非有限值和非正值没有统一机器原因；
- 单位、方程、来源和生成器哈希未闭合到代表参数包；
- JSON/CSV 未在写盘前全部完成严格序列化；
- 中途写入失败会留下部分目录；
- 未计划输出未统一阻断；
- `formal_promotion=false` 未覆盖选择文件。

⚠️ 保留测试自身存在一处明确矛盾：前段仍要求旧 12 项单位表，后段要求覆盖全部物理数值字段的 19 项单位表。依据后段逐字段闭合测试和批准规格，仅将前段同步为同一 19 项表；没有删除测试或降低门槛。修正提交为 `dd0da01`。

⚠️ 未提交的原加固实现没有从工作树、stash、可达提交或已检查的悬空 Python blob 中找到。本轮实现是根据保存的失败测试和批准规格重新构建，不冒充原未提交实现的字节恢复。

## 5. 验证结果

✅ 联合离线测试命令：

```text
python3 -m unittest -v \
  tests.test_recover_cleanup_baselines \
  tests.test_audit_cleanup_protected_manifest \
  tests.test_radiator_a1_contract \
  tests.test_radiator_a1_math \
  tests.test_build_radiator_a1_screen
```

结果：

```text
68 tests
0 failures
0 errors
```

✅ 构建器在普通与 `python3 -O` 模式下分别通过 34/34 测试。

✅ 全新离线恢复门：

```text
tmp/radiator_A1_recovery_gate_20260831
RADIATOR_A1_OFFLINE_SCREEN_PASS; ROWS=96; NO_MODEL_LOAD
```

生成结果：

```text
offline rows = 96
fixed representative roles = 12
eligible_for_slx = 11
baseline SHA256 = 0532e9dd...a5a391
```

11 个合格代表是既有固定包络的结果；未对被拒绝角色补位，也未扩大包络。

✅ 正式文件非改动检查：

```text
git diff --name-only -- final_steady_24a.slx final_dynamic_24a.slx '*.mat' HeXe_property_simulink.m
```

结果为空。恢复阶段未启动 MATLAB，未加载或仿真 SLX。

## 6. Git 恢复提交

| 提交 | 内容 |
|---|---|
| `7bf076b` | 保存中断 A1 加固测试 |
| `cb5d08b` | 实现精确 blob 恢复工具 |
| `f20d152` | 固化两份 A1 模型基线 |
| `314a733` | 加固恢复说明格式门 |
| `954dc94` | 发布 34 行保护清单恢复审计 |
| `fea41f6` | 迁移 A1 不可变基线合同 |
| `dd0da01` | 修正测试单位合同矛盾 |
| `a9708c8` | 加固来源身份与代理量闭合 |
| `00b98ee` | 恢复原子证据发布实现 |

## 7. 剩余不确定性

- ❓ 本轮结束前仍有 64 个事故前遗留的未跟踪文件。由于清理前没有覆盖全部未跟踪文件的完整清单，无法证明是否还有未登记的一次性诊断产物丢失。
- ✅ 当前 Git 跟踪删除数为 0，跟踪修改数为 0；上述未跟踪文件没有被删除、覆盖或纳入本轮提交。
- ⚠️ 本报告不评价这些遗留未跟踪诊断脚本的科学有效性；后续仍按原文件分类和治理规则处理。

## 8. 后续入口

恢复门通过后，继续执行：

```text
docs/superpowers/plans/2026-08-30-radiator-a1-staged-parameter-envelope.md
Task 4: 用官方 API 建立断言保护的候选补丁
```

唯一路径替换：

```text
旧权威源：tmp/steady53_curves_20260828/source_f8bcd83/final_steady_24a.slx
新权威源：data/provenance/baselines/f8bcd83/final_steady_24a.slx
```

SHA256 不变。其余已批准规则不变：官方 MATLAB/Simulink API、独立临时候选、正式模型不修改、固定角色不补位、先 `500 s` 后 `14000 s`、不按论文曲线接近程度自动晋升。
