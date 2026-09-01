# A3 自包含 Capture 依赖闭包设计

**状态：** 已批准设计，待据此修订实施计划  
**批准文本：** `批准方案 A 依赖闭包设计`  
**适用范围：** A3 Task 2–5 的保护对象、formal 根状态、capture 快照和离线耐久证据  
**不适用范围：** 模型参数、物理方程、A3 候选温度偏移、论文判据、验收阈值和正式仿真授权

---

## 1. 问题与证据

✅ 固定恢复清单
`data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv`
共有 34 条逻辑记录，SHA-256 为
`33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64`。

✅ 其中 24 条记录当前解析到本仓库内，10 条解析到仓库外的历史
`不接入转子稳态模型_副本`。这些记录包含重复路径及同名不同哈希版本，不能通过简单去重或只复制当前活动文件保持原证据语义。

✅ 当前 Task 5 的 exact snapshot 清单没有包含恢复清单、34 条保护对象和正式根文件布局。候选生成器会在预检阶段读取保护清单；runner 又要求 exact formal 8 记录。按旧计划构建的 capture 会在正式模型调用前确定性失败。

✅ 当前正式仓库根状态不是“8 个文件都存在”，而是 exact 8 条记录：

| 根记录 | 当前状态 | SHA-256（存在时） |
|---|---|---|
| `final_steady_24a.slx` | 存在 | `a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159` |
| `final_dynamic_24a.slx` | 不存在 | 空字符串 |
| `HeXe_property_simulink.m` | 存在 | `2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2` |
| `Lithium_property_simulink.m` | 存在 | `f0c2aad44e8701212e924371fe027d7b3814a32cd5df3a32f8a0ccf09abb7f1c` |
| `hexe_compressor_lookup.mat` | 存在 | `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579` |
| `radiator_table.mat` | 存在 | `3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304` |
| `turbine_table1.mat` | 存在 | `10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d` |
| `turbine_table2.mat` | 存在 | `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33` |

因此，依赖闭包必须保存“存在/缺失状态”，不能把 provenance 中的旧
`final_dynamic_24a.slx` 复制到 capture 根并把它重新变成活动 formal 文件。

## 2. 设计选择

采用仓库内 portable immutable archive：把 34 条逻辑记录逐条归档为仓库相对路径对象，并用一个 portable manifest 绑定原恢复清单、逻辑行和归档字节。

不采用以下方案：

- 不在 Task 5 运行时继续读取外部 `_副本` 绝对路径；这不具备可移植性，也不是 self-contained capture。
- 不在 capture 内改写原恢复清单的绝对路径；原清单必须保持原字节作为历史证据。
- 不把 34 条记录压缩成当前活动文件的唯一集合；重复记录和同名不同哈希版本均属于原证据。
- 不把 provenance 中的旧 `final_dynamic_24a.slx` 恢复到 capture 根或正式仓库根。

## 3. 新增治理材料

在 `data/provenance/baselines/f8bcd83/` 下新增：

```text
portable_protected_manifest.json
formal_root_state.json
protected_objects/
  row_001/HeXe_property_simulink.m
  row_002/Lithium_property_simulink.m
  ...
  row_034/turbine_table2.mat
```

### 3.1 portable protected manifest

`portable_protected_manifest.json` 使用固定 schema
`steady53_protected_portable_manifest_v1`，至少包含：

```json
{
  "schema": "steady53_protected_portable_manifest_v1",
  "source_manifest": "data/provenance/baselines/f8bcd83/protected_manifest_recovery.csv",
  "source_manifest_sha256": "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64",
  "record_count": 34,
  "records": [
    {
      "record_index": 1,
      "source_original_path": "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型/HeXe_property_simulink.m",
      "source_resolved_path": "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型/HeXe_property_simulink.m",
      "source_resolution": "original_path_hash_match",
      "archive_repository_relative_path": "data/provenance/baselines/f8bcd83/protected_objects/row_001/HeXe_property_simulink.m",
      "sha256": "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2"
    }
  ]
}
```

路径规则：

- `source_original_path` 和 `source_resolved_path` 只能作为不可执行的 provenance 字符串保存。
- candidate generator、runner、analyzer 和 Task 5 prepare 禁止使用这两个绝对路径读取文件。
- 唯一允许的读取路径为
  `repoRoot / archive_repository_relative_path`。
- `record_index` 必须精确覆盖 `1..34`；archive 路径必须唯一，逻辑记录和归档文件必须一一对应。
- 相同字节、相同文件名或相同来源允许重复归档；不得据此合并逻辑记录。
- 每项必须是 no-follow 普通文件，完整祖先位于 `repoRoot` 内，实际 SHA 必须等于记录值。

### 3.2 formal root state

`formal_root_state.json` 使用固定 schema
`steady53_formal_root_state_v1`，记录上述 exact 8 名称、`exists` 状态，以及存在文件的 SHA-256。它同时记录观察基线提交
`aaeee0ceb9220e65686fdbbef6ab9b702c7135ff`。

路径规则：

- capture 根只复制 `exists=true` 的 7 个 formal 文件。
- capture 根必须不存在 `final_dynamic_24a.slx`。
- provenance 子目录中的
  `data/provenance/baselines/f8bcd83/final_dynamic_24a.slx`
  仍可作为历史证据存在，但不得被解析成 formal 根文件或活动模型。
- candidate、runner 和 analyzer 必须按 `formal_root_state.json` 验证 exact 8 记录，而不是通过 `dir("*.mat")` 动态决定集合。

## 4. 统一路径解析合同

Task 2–5 共用以下语义；实现可以分语言，但行为必须一致：

1. `repoRoot` 是调用者明确传入并完成 no-follow 绑定的根。
2. 所有运行时、保护对象、formal 根、数据组和 executable 都从仓库相对路径解析。
3. 禁止绝对路径、`..`、空组件、symlink 祖先、symlink 终点和逃逸 `repoRoot` 的 canonical path。
4. 每个读取阶段前后复核普通文件类型、fileKey/dev/inode 和 SHA；正式调用门仍按已批准的“有限替换”威胁边界执行。
5. portable manifest、formal state 和原恢复清单本身都进入 immutable `SHA256SUMS`。
6. 任何缺失、额外、重复、哈希不符、存在状态不符或路径逃逸，都必须在模型调用前失败。

## 5. Task 5 exact snapshot 闭包

Task 5 的 immutable snapshot 是以下集合的去重并集；每个普通文件在
`SHA256SUMS` 中恰好出现一次，并按 POSIX 相对路径排序：

1. 原计划 exact 9 executables。
2. 原计划 9 data groups 的全部普通文件。
3. `protected_manifest_recovery.csv`。
4. `portable_protected_manifest.json`。
5. `formal_root_state.json`。
6. `protected_objects/row_001..row_034` 的 34 个归档对象。
7. formal 根状态中 `exists=true` 的 7 个文件，复制到 capture `repo_snapshot/` 根。

`repo_snapshot/tmp/` 仍是唯一可写例外：目录模式 `0700`、初始为空、不进入 immutable manifest。所有 immutable 普通文件模式 `0400`，immutable 目录模式 `0500`。

Snapshot 还必须保留以下不变量：

- capture 根的 `final_dynamic_24a.slx` 不存在；
- provenance 内的历史 `final_dynamic_24a.slx` 不得加入 MATLAB path 或 formal 根解析；
- MATLAB path 只能使用 captured `tests/`、`tests/steady53/` 和 runner 已固定的 captured runtime 位置；
- command 只能调用 captured executor，cwd 必须是 captured `repo_snapshot`。

## 6. 零仿真闭包验证

实施必须增加一个真实 captured-root 测试，不得再用 live ROOT 合成 audit 代替：

1. 构造与 Task 5 相同的 exact snapshot。
2. 在 captured cwd 中调用 captured candidate generator，输出到
   `repo_snapshot/tmp/fig519_ihx_r2_hexe_20260901_A3_preflight`。
3. 只允许一次 `SimulationCommand="update"`；禁止 runner、`run_steady53_case`、`sim`、`start` 和正式 A3 目录。
4. 断言 protected=34、formal records=8、formal existing=7、runtime=9、states=40、solver=37、两个目标状态使用共同 delta。
5. 断言 candidate、runner 和 analyzer 都只报告 capture-local 路径。
6. 预检后重新计算全部 immutable SHA，必须逐项不变。

以下任一情况必须 RED：

- portable manifest、formal state、原恢复清单或任一归档对象缺失；
- 34 条逻辑记录被合并、重复索引或路径重复；
- capture 根意外出现 `final_dynamic_24a.slx`；
- 7 个应存在 formal 文件任一缺失或哈希变化；
- protected/runtime/formal 集合缺失、额外或重复；
- 任何路径解析回 live 仓库、外部 `_副本` 或 symlink；
- 预检产生正式运行 claim、runner marker、raw/curve 文件或仿真调用。

## 7. Task 4 耐久证据兼容性

Analyzer 的完整 snapshot allowlist 必须接受第 5 节闭包，归档所有列入
`SHA256SUMS` 的 immutable 字节，并在 `verify_only` 中逐项重算。

同时统一 `SHA256SUMS` 语法：

- UTF-8 文本；
- 每行依次为 64 位小写十六进制 SHA-256、两个 ASCII 空格和一个非空 POSIX 相对路径；
- 禁止空行、重复路径、绝对路径、反斜杠、`..` 和未声明路径；
- publish 和 verify 使用同一个 parser，入口即拒绝非法清单，不能在提交后才发现语法不一致。

## 8. 变更边界与人工门

本设计只允许修改 provenance/capture 治理材料、探索区实现、测试和实施计划。

禁止：

- 修改正式 SLX、正式 MAT 或物性函数；
- 恢复旧 `final_dynamic_24a.slx` 为活动根文件；
- 改变 A3 共同温度偏移、论文方向、非平坦阈值或结论状态机；
- 运行正式 A3 runner 或 500 s 仿真；
- 越过 Task 5 READY 后的独立授权语句
  `批准 A3 单次正式运行`。

依赖闭包完成后必须重新通过 Task 2–4 的规格与质量审查，随后才可实现 Task 5 并到达 `READY_NO_SIMULATION`。
