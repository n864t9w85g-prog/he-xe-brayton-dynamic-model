# 2026-08-24 稳态新基线重启审计

## 口径与证据等级

- ✅ 归档 tag：`archive/pre-restart-20260824`。
- ✅ 快照提交：`8f625c268c35a95c18a626305c1aa6a79ae2ace7`；父提交：`4f8a0ebe707c5ef125ed449124aa8fc68899f917`；树对象：`8f2fb8d36eb00a654153eecee3b43f26a79d6b82`。
- ✅ 归档树共 `621` 个文件路径；分类总数 `621`，其中第1类 `10`、第2类 `41`、第3类 `570`。
- ✅ 分类口径固定为归档提交，不受本轮运行 MATLAB 后生成/更新的缓存影响。
- ❓ 第3类仅是待人工确认候选，不是删除结论。

## Step 0：归档与状态快照

- ✅ 创建归档前的活动分支：`codex/publish-he-xe-brayton-model`；当时 `HEAD` 为 `4f8a0ebe707c5ef125ed449124aa8fc68899f917`。
- ✅ 创建前工作树：`docs/MODEL_MAP.md`、`docs/PLAN.md`、`docs/STATUS.md` 已修改；`final_dynamic_24a.slx` 已删除；另有 README、实验文档、诊断脚本和 4 个参考/提取文件未跟踪。
- ✅ 归档提交通过独立临时 Git index 建立，纳入 tracked、untracked、ignored 文件；未切换分支，未改变活动 index/工作树。
- ✅ `final_dynamic_24a.slx` 不在快照树中，准确保存“活动文件已删除”的状态；其父提交仍保存该文件，父提交版本 SHA-256 为 `2bed798bcd3d32c15b7771907e8cd5452aa4171a0b87335af7c8769ed6987790`。

### 关键模型、入口与查表快照（归档树内容 SHA-256）

| 文件 | SHA-256 |
|---|---|
| `final_steady_24a.slx` | `08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a` |
| `run_dynamic.m` | `2db89acaa46c9c2bfbb490a028ef435a66ea85dbe5af4994c3f4e933d1486f5a` |
| `start.m` | `0de14c8d7e56e22871800f0c84f6eccd5b00e34ae7c20a3501752f45a09effec` |
| `hexe_compressor_lookup.mat` | `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579` |
| `radiator_table.mat` | `3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304` |
| `turbine_table1.mat` | `10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d` |
| `turbine_table2.mat` | `cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33` |
| `final_dynamic_24a.slx.original` | `a51a1705d37d838e9f1b3eb8fc7db0c47c05fad4162704299584683c25036f5b` |
| `final_dynamic_24a.slx.before_corrected_coordinates.bak` | `b8783103d96b00741edda860dc2a3c840df9d4d47979e1bbd7a5565bfffcbd8d` |
| `hexe_compressor_lookup.mat.bak` | `f46131b3376be296e917492e5ed913463bc9a9430d08bdcc8c3b252754eff068` |
| `hexe_compressor_lookup.mat.bak2` | `158f0e4a74f3db39b1b5dcc458c754619a4c257d7becb18461032328be1ab85c` |
| `hexe_compressor_lookup.mat.before_compressor_map_20260816.bak` | `41271905d715bd32069576573a154e07348706954421f09b2ef124a4ee7a1f7f` |
| `hexe_compressor_lookup.mat.before_traceable_map_20260818.bak` | `ab0fa69686d7fbb2d7815a1abf84939ad19506834d3de310c39883b7b3d57f3a` |
| `hexe_compressor_lookup.mat.pre_paper_shape.bak` | `41271905d715bd32069576573a154e07348706954421f09b2ef124a4ee7a1f7f` |
| `output/compressor_map_rebuild/hexe_compressor_lookup_candidate.mat` | `0b300e5f2f09c586aa65482d76ba30536aaad72e09bd4171bf163b0a9753859d` |
| `output/compressor_map_rebuild/hexe_compressor_lookup_smooth_candidate.mat` | `4beeb806edfce1995732d28cb355f731ddb23a8e930c0479be714dea46fba545` |
| `output/compressor_map_rebuild/t0_old_candidate.mat` | `8fccf83b2e39c681b7d23bc6f8ca91111e42411a9f941e74223566c1f16ad591` |
| `output/paper54_reproduction/hexe_compressor_lookup_candidate.mat` | `f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579` |

## Step 1：final_steady_24a.slx 新基线依赖集

- ✅ MATLAB `R2025a (25.1.0.2943329)` / Simulink `25.1` 中，从全新 batch 进程运行；随后又在只含下列依赖文件的系统临时目录中复验。
- ✅ 隔离复验执行 `restoredefaultpath`、`start.m`、`load_system`、diagram update，输出 `CLEAN_STAGE_DEPENDENCY_SET_UPDATE_PASS`。
- ✅ 模型 8 个回调均为空；无数据字典；模型工作区数据源为 Model File；活动配置是模型内嵌 `Simulink.ConfigSet`。
- ✅ `find_mdlrefs` 只返回模型自身；`libinfo` 返回 0 条，因此没有引用模型或外部 Simulink 库链接。
- ✅ `Simulink.findVars` 识别 15 个直接基础工作区变量。

| 文件 | 依赖层级与依据 |
|---|---|
| `HeXe_property_simulink.m` | 模型内 11 个 MATLAB Function 图表以 coder.extrinsic 直接调用。 |
| `Lithium_property_simulink.m` | IHX 两个 MATLAB Function 图表以 coder.extrinsic 直接调用。 |
| `final_steady_24a.slx` | 新基线核心模型；隔离目录中成功加载并完成 diagram update。 |
| `hexe_compressor_lookup.mat` | start.m 实际加载；向压气机两张二维表提供 speed_bp、m_ratio_bp、PR_table、ETAT_table。 |
| `paper54_constants.m` | start.m 实际调用；返回 paper54，但 final_steady_24a.slx 当前不引用该变量，属于入口链中的附带硬依赖。 |
| `radiator_table.mat` | start.m 实际加载；随后同名辐射器变量会被 sys_param_rad_fixed.m 覆盖，仍是当前入口的硬依赖。 |
| `start.m` | 当前初始化入口；无模型回调时必须由调用者运行，且它无条件加载 4 个 MAT、调用 2 个 M 文件。 |
| `sys_param_rad_fixed.m` | start.m 实际调用；提供模型直接引用的 A_rad、Cp_rad、M_rad、epsilon、h_h、theta。 |
| `turbine_table1.mat` | start.m 实际加载；提供 bp_er、bp_speed、table_mf。 |
| `turbine_table2.mat` | start.m 实际加载；提供 bp_mf、bp_speed、table_eff。 |

### 直接工作区变量映射

| 来源 | 模型实际引用变量 | 说明 |
|---|---|---|
| `hexe_compressor_lookup.mat` | `speed_bp`, `m_ratio_bp`, `PR_table`, `ETAT_table` | 压气机两张二维表。 |
| `turbine_table1.mat` | `bp_er`, `bp_speed`, `table_mf` | 透平质量流量表。 |
| `turbine_table2.mat` | `bp_mf`, `bp_speed`, `table_eff` | 透平效率表。 |
| `sys_param_rad_fixed.m` | `A_rad`, `Cp_rad`, `M_rad`, `epsilon`, `h_h`, `theta` | 辐射器常量。 |

### 依赖链中的非有效/被覆盖项

- ✅ `paper54_constants.m` 被 `start.m` 调用，但其结果变量 `paper54` 不在模型 15 个直接引用变量中。
- ✅ `radiator_table.mat` 先加载，随后 `sys_param_rad_fixed.m` 覆盖同名变量；`A_rad: 100→300`、`M_rad: 500→150`，其余 4 个模型引用值相同。
- ✅ `radiator_table.mat` 与 `paper54_constants.m` 当前仍是 `start.m` 的硬依赖；本轮未据此修改入口。

## Step 2：三类文件清单

完整逐文件清单见 `docs/restart_file_classification_20260824.tsv`；第3类的逐文件人工确认表见 `docs/restart_class3_candidates_20260824.md`。

### 第 1 类：新基线依赖集（10）

| 文件 | 判定理由 |
|---|---|
| `HeXe_property_simulink.m` | 模型内 11 个 MATLAB Function 图表以 coder.extrinsic 直接调用。 |
| `Lithium_property_simulink.m` | IHX 两个 MATLAB Function 图表以 coder.extrinsic 直接调用。 |
| `final_steady_24a.slx` | 新基线核心模型；隔离目录中成功加载并完成 diagram update。 |
| `hexe_compressor_lookup.mat` | start.m 实际加载；向压气机两张二维表提供 speed_bp、m_ratio_bp、PR_table、ETAT_table。 |
| `paper54_constants.m` | start.m 实际调用；返回 paper54，但 final_steady_24a.slx 当前不引用该变量，属于入口链中的附带硬依赖。 |
| `radiator_table.mat` | start.m 实际加载；随后同名辐射器变量会被 sys_param_rad_fixed.m 覆盖，仍是当前入口的硬依赖。 |
| `start.m` | 当前初始化入口；无模型回调时必须由调用者运行，且它无条件加载 4 个 MAT、调用 2 个 M 文件。 |
| `sys_param_rad_fixed.m` | start.m 实际调用；提供模型直接引用的 A_rad、Cp_rad、M_rad、epsilon、h_h、theta。 |
| `turbine_table1.mat` | start.m 实际加载；提供 bp_er、bp_speed、table_mf。 |
| `turbine_table2.mat` | start.m 实际加载；提供 bp_mf、bp_speed、table_eff。 |

### 第 2 类：治理与溯源材料（41）

| 文件 | 判定理由 |
|---|---|
| `.gitignore` | 仓库治理/卫生规则；默认保留。 |
| `AGENTS.md` | 用户明确指定的持久治理规则；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/calibration.json` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/digitized_points.csv` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/overlay_efficiency.png` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/overlay_pressure_ratio.png` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/source_page_14.png` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tmx2269/source_page_15.png` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/SHA256SUMS.txt` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/original/README.md` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/original/compressor_program.py` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/original/fortran_transcription.f` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/original/sample_input.json` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/original/test_compressor_program.py` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/nasa_tn_d7487/target_input_audit.csv` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `data/provenance/compressor_map/source.md` | 用户明确指定的 data/provenance/ 数字化、校准、叠图、原始程序或 SHA256 溯源材料；默认保留。 |
| `output/nasa_compressor_pdf/NASA-CR-182263-repaired.pdf` | NASA 报告的修复版；属于可读性/溯源辅助，默认保留。 |
| `output/nasa_compressor_pdf/NASA-CR-182263.pdf` | NASA 原始参考报告；虽位于 output/，仍是源证据，默认保留。 |
| `output/nasa_compressor_pdf/NASA-CR-182263.txt` | NASA 报告文字提取件；属于可检索溯源材料。 |
| `sources/NASA-CR-72533-AiResearch-1967.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TM-X-2129-Ball-Tysl-Weigel-1970.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TM-X-2269-Ball-Tysl-Weigel-1971-repaired.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TM-X-2269-Ball-Tysl-Weigel-1971.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TN-D-5761-Ball-Heidelberg-Weigel-1970-repaired.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TN-D-5761-Ball-Heidelberg-Weigel-1970.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TN-D-6640-Weigel-Ball-1972-repaired.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TN-D-6640-Weigel-Ball-1972.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `sources/NASA-TN-D-7487-Galvas-1973.pdf` | 用户明确指定的 sources/ 下 NASA 原始/修复参考报告；默认保留。 |
| `tests/test_nasa_d7487_input_audit.py` | 直接验证 NASA D-7487 输入审计材料的溯源测试。 |
| `tests/test_nasa_tmx2269_digitization.py` | 直接验证 NASA TM-X-2269 数字化材料的溯源测试。 |
| `tests/test_nasa_tn_d7487_program.py` | 直接验证 NASA TN-D-7487 程序转录的溯源测试。 |
| `tools/build_tmx2269_digitization.py` | 生成/核验 NASA TM-X-2269 数字化数据的溯源工具。 |
| `tools/nasa_tn_d7487/compressor_program.py` | NASA TN-D-7487 压气机程序的可执行溯源实现。 |
| `交付边界约束_v4.md` | 用户明确指定的正式交付边界；默认保留。 |
| `决策自律准则.md` | 用户明确指定的正式治理规则；默认保留。 |
| `压气机几何自洽说明_论文级.md` | 记录 55090 rpm 几何修正的独立物理论证；本次重启决定明确要求保留该结论。 |
| `徐驰论文_extracted.txt` | 论文文字提取件；原始论文 PDF 当前未出现在归档树中，因此作为现有论文溯源材料默认保留。 |
| `桑迪亚报告.pdf` | 外部原始参考报告；属于后续物理模型重建的源证据。 |
| `桑迪亚报告_extracted.txt` | 桑迪亚报告文字提取件；属于源证据的可检索副本。 |
| `透平程序 (Turbine Program).pdf` | 透平程序原始参考报告；属于后续透平模型重建的源证据。 |
| `验收标准_论文5.4.md` | 用户明确指定的正式验收标准；默认保留。 |

### 第 2 类缺口

- ❌ 归档树中没有找到徐驰论文原始 PDF；现存的是 `徐驰论文_extracted.txt` 以及 `tmp/pdfs/` 下的页图/OCR 派生件。原始 PDF 缺口不能用派生件冒充。

### 第 3 类：待人工确认候选（570）

| 共同判定理由 | 文件数 |
|---|---:|
| 论文页图/OCR 临时提取件；不被模型加载。注意归档树中缺少论文原始 PDF，删除前必须先确认这些派生件已由保留的文字提取或补回的 PDF 覆盖。 | 124 |
| 旧 final_dynamic 的解包 XML/媒体副本；可由归档模型对象重新生成，不参与新稳态加载。 | 104 |
| final_steady_24a.slx 的解包副本；可从活动 SLX 重新生成，模型运行不引用这些 XML/媒体文件。 | 102 |
| Simulink 自动生成的 slprj/JIT/Stateflow/varcache 文件；可再生且不属于模型源依赖。 | 75 |
| 参考报告的临时页面/OCR/版面提取；对应原始 PDF 或正式溯源材料已保留，模型不引用。 | 62 |
| 旧压气机审计/候选生成物；不是活动查表，也未被 final_steady 依赖链加载。 | 17 |
| NASA 报告的临时页图/版面提取；原始或修复 PDF/文字源已列入第 2 类，模型不引用本派生文件。 | 11 |
| 操作系统生成的 .DS_Store 元数据；既不参与模型加载，也不承载治理/溯源内容。 | 11 |
| 旧 5.4 动态仿真或表 5.2 审计输出；建立在重启前模型状态上，不能作为新基线事实。 | 9 |
| 旧压气机候选构建/激活/修正链；隔离依赖追踪未加载，后续只能基于新基线和保留的独立物理论证重建。 | 7 |
| 验证旧压气机候选、修正坐标、相似变换或激活门禁的测试；不参与新稳态基线加载，候选链须重验。 | 7 |
| 历史压气机查表备份；活动表与独立几何/来源材料已分别列入第 1/2 类，本备份仅由归档 tag 保存历史。 | 5 |
| 旧会话代理记忆；不是正式治理文档，也不参与稳态基线加载，且内容形成于重启前。 | 4 |
| 旧 final_dynamic 模型备份或编译缓存；不在新稳态依赖链内，且旧动态具体改动不再默认可信。 | 4 |
| 重启前针对旧压气机候选链或旧动态复现的计划/设计稿；不参与稳态模型加载，结论须重验。 | 4 |
| Python 自动生成的 __pycache__/pyc；可再生且不承载源代码或溯源结论。 | 4 |
| 验证旧表 5.2 平衡/求解链的测试；不参与新稳态基线加载，旧结果不再默认可信。 | 3 |
| 验证旧 5.4 常量/调度或 dynamic 诊断的测试；不参与新稳态基线加载。 | 3 |
| 重启前的模型地图/计划/状态，包含旧 dynamic 假设；不参与新稳态基线加载，不能继续作为当前事实。 | 3 |
| 旧 final_dynamic 运行入口或 5.4 调度文件；不参与 final_steady 加载，旧动态参数不得迁回。 | 2 |
| 旧 final_dynamic 边界诊断的临时模型/结果；只证明重启前故障现象，不是新基线依赖。 | 2 |
| 旧表 5.2 负载/稳态求解或残差审计链；不参与 final_steady 的当前加载，且旧耦合结论需重新验证。 | 2 |
| 图 5.34 旧全耦合对比分析；用户已明确其前提过时，不能继续作为当前事实。 | 1 |
| 记录旧 final_dynamic 压气机边界失败实验；对新稳态基线不构成运行依赖，历史已由归档 tag 保留。 | 1 |
| 仓库说明仍围绕旧 dynamic 运行链和审计状态；不参与新稳态基线加载，需按新计划另行重写。 | 1 |
| final_steady 的版本转换备份；活动基线是 final_steady_24a.slx，本文件不被加载或引用。 | 1 |
| 模型静态追踪与 MATLAB Function 脚本均未引用；当前模型使用 HeXe/Lithium 外部函数及内嵌 NaK 关联式。 | 1 |

逐文件路径和逐文件理由：`docs/restart_class3_candidates_20260824.md`。

## Step 3：确认门

- ❓ 本轮没有删除、移动或恢复任何仓库文件。
- ❓ 第3类等待人工逐项或按组确认；确认前不进入删除，也不进入从稳态基线重建动态模型的 Step 4。
- ❓ 后续若获确认，删除提交信息应写明：`依据 2026-08-24 的重启决策，参考 docs/restart_class3_candidates_20260824.md`，并可同时引用本审计文档。

## 审阅后的补充与执行记录

- ✅ 用户在 2026-08-24 补入徐驰论文原始 PDF：`空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf`。文件为 PDF 1.6、141 页，SHA-256 为 `983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a`。
- ✅ 同轮补入的压气机程序、锂物性、兆瓦级闭式布雷顿循环和 Inconel 617 PDF 均位于原 621 文件归档口径之外，作为新增溯源文献保留，不属于第3类删除目标。
- ✅ 用户完成清单审阅后明确回复“批准”，授权删除 `docs/restart_file_classification_20260824.tsv` 中 `category=3` 的全部 570 个精确路径。
- ✅ 实际删除严格按 TSV 精确路径执行：32 个受 Git 跟踪文件、538 个未跟踪或被忽略文件；另清理 43 个因此变空的目录。
- ✅ 本次删除不使用通配符；第1类、第2类、三份重启审计清单和新增文献均不在删除集合中。
- ✅ `final_dynamic_24a.slx` 在 Step 0 前已经处于工作树删除状态，且不在 570 个获批目标中；因此本次清理提交明确不暂存该项既有删除。
- ✅ 全部 570 个已删除文件仍可从归档 tag `archive/pre-restart-20260824`（快照提交 `8f625c268c35a95c18a626305c1aa6a79ae2ace7`）恢复。
