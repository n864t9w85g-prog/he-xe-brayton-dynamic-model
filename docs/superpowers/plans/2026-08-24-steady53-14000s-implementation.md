# 第 5.3.1 节名义稳态 14000 s Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 以测试先行为前提，把 `final_steady_24a.slx` 建成在论文第 5.3.1 节名义工况下无物性钳位、无查表越界且可重复运行到 `14000 s` 的稳态基线。

**Architecture:** 先建立与 Simulink 模型解耦的论文目标和纯 MATLAB 判定器，再建立只位于 `tests/steady53/` 的模型运行器、信号清单和部件恒边界工装。当前 `66100 rpm` 转速接线先在探索副本做单变量实验，再用失败测试保护后最小修改正式模型；如果该修改不能使整机 `500 s` 通过，则计划在根因检查点暂停，依据部件测试的首个失败方程编写精确的后续修复计划，禁止继续猜参数。

**Tech Stack:** MATLAB R2025a、Simulink、MATLAB Unit Test（function-based tests）、Git、现有 `.slx`/`.mat`/物性函数。

---

## 实施前文件结构

计划创建或修改以下文件：

| 文件 | 职责 |
|---|---|
| `tests/steady53/steady53_spec.m` | 唯一的论文目标和已批准数值门槛结构体 |
| `tests/steady53/test_steady53_spec.m` | 目标值和门槛的单元测试 |
| `tests/steady53/evaluate_steady53.m` | 纯 MATLAB 终值、波动、漂移、收敛时间和域检查 |
| `tests/steady53/test_evaluate_steady53.m` | 使用合成数据验证判定器红/绿行为 |
| `tests/steady53/steady53_signal_manifest.m` | 当前模型关键输出的块路径和端口号 |
| `tests/steady53/run_steady53_case.m` | 在内存中记录信号、运行模型、捕获警告/错误并保证不保存诊断修改 |
| `tests/steady53/test_run_steady53_case.m` | 运行器和模型不落盘保证测试 |
| `tests/steady53/test_final_steady_acceptance.m` | 当前失败回归、转速/查表域、500 s 和 14000 s 验收测试 |
| `tests/steady53/run_speed_hypothesis.m` | 在 `tmp/steady53/` 副本执行 `66100→55090` 单变量实验 |
| `tests/steady53/steady53_component_boundaries.m` | 各部件恒边界输入及证据口径 |
| `tests/steady53/create_component_harness.m` | 从正式模型复制一个部件并接恒定边界的探索模型生成器 |
| `tests/steady53/test_component_harnesses.m` | 图 5.18 对应部件的 500 s/14000 s 有界性测试 |
| `run_steady53.m` | 最终用户可运行的名义稳态入口；不被模型反向引用 |
| `docs/steady53_experiment_log.md` | 假设、输入、模型哈希、结果和证据等级 |
| `docs/steady53_validation.md` | 最终两次 14000 s 验收报告 |
| `final_steady_24a.slx` | 仅在测试证明后最小修改实际转速源和最终 `StopTime` |

大体积时序文件写入 `tmp/steady53/`，不提交 Git。论文第 5.3.2 节参数扫描不在本计划内。

### Task 0: 建立隔离执行环境并固定基线

**Files:**
- Read: `AGENTS.md`
- Read: `决策自律准则.md`
- Read: `交付边界约束_v4.md`
- Read: `docs/superpowers/specs/2026-08-24-steady53-14000s-design.md`
- Verify: `final_steady_24a.slx`

- [ ] **Step 1: 使用 worktree 技能创建隔离工作树**

执行时先调用 `using-git-worktrees` 技能，基于提交
`a97b37c82ad479a0be3e68a3fc21d3c511493953` 创建 `codex/steady53-14000s`
隔离分支。不要复制当前工作树中未跟踪的文献，也不要带入已存在的
`final_dynamic_24a.slx` 删除状态。

- [ ] **Step 2: 复核正式规则和设计规格**

Run:

```bash
sed -n '1,260p' AGENTS.md
sed -n '1,240p' 决策自律准则.md
sed -n '1,320p' 交付边界约束_v4.md
sed -n '1,430p' docs/superpowers/specs/2026-08-24-steady53-14000s-design.md
```

Expected: 四个文件均完整可读，设计范围明确排除第 5.3.2 节。

- [ ] **Step 3: 固定基线哈希与存档标签**

Run:

```bash
test "$(shasum -a 256 final_steady_24a.slx | awk '{print $1}')" = \
  '08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a'
test "$(git rev-parse archive/pre-restart-20260824^{commit})" = \
  '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
git status --short
```

Expected: 两个 `test` 均退出 0；隔离工作树干净。

### Task 1: 用测试固定论文目标和项目门槛

**Files:**
- Create: `tests/steady53/test_steady53_spec.m`
- Create: `tests/steady53/steady53_spec.m`

- [ ] **Step 1: 写论文目标的失败测试**

Create `tests/steady53/test_steady53_spec.m`:

```matlab
function tests = test_steady53_spec
tests = functiontests(localfunctions);
end

function testPaperDirectTargets(testCase)
s = steady53_spec();
verifyEqual(testCase, s.stopTime_s, 14000);
verifyEqual(testCase, s.finalWindow_s, [13000 14000]);
verifyEqual(testCase, metricTarget(s, "rotor_speed"), 55090);
verifyEqual(testCase, metricTarget(s, "reactor_outlet_T"), 1600.00);
verifyEqual(testCase, metricTarget(s, "turbine_power"), 2252.2e3);
verifyEqual(testCase, metricTarget(s, "compressor_power"), 1231.6e3);
verifyEqual(testCase, metricTarget(s, "tac_electric_power"), 1000.21e3);
end

function testApprovedNumericalGates(testCase)
s = steady53_spec();
verifyEqual(testCase, s.outputRelTol, 0.01);
verifyEqual(testCase, s.windowPeakToPeakTol, 0.001);
verifyEqual(testCase, s.windowTrendTol, 0.0001);
verifyEqual(testCase, s.massClosureTol, 1e-6);
verifyEqual(testCase, s.property.HeXe_K, [100 2000]);
verifyEqual(testCase, s.property.Lithium_K, [453.7 1608]);
verifyEqual(testCase, s.requiredIndependentRuns, 2);
end

function value = metricTarget(s, name)
row = s.metrics(s.metrics.name == name, :);
assert(height(row) == 1);
value = row.target;
end
```

- [ ] **Step 2: 运行测试并确认因函数缺失而失败**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_steady53_spec.m'); assertSuccess(r)"
```

Expected: FAIL，原因包含 `steady53_spec` 未定义。

- [ ] **Step 3: 实现唯一目标结构**

Create `tests/steady53/steady53_spec.m`:

```matlab
function s = steady53_spec()
s.stopTime_s = 14000;
s.finalWindow_s = [13000 14000];
s.outputRelTol = 0.01;
s.windowPeakToPeakTol = 0.001;
s.windowTrendTol = 0.0001;
s.massClosureTol = 1e-6;
s.requiredIndependentRuns = 2;
s.property.HeXe_K = [100 2000];
s.property.Lithium_K = [453.7 1608];
s.scale.temperature_K = 1;
s.scale.pressure_Pa = 1;
s.scale.massFlow_kg_s = 1;
s.scale.power_W = 1;
s.scale.speed_rpm = 1;
s.scale.other = 1;

name = [ ...
    "reactor_inlet_T"; "reactor_outlet_T"; ...
    "turbine_inlet_T"; "turbine_inlet_P"; ...
    "turbine_outlet_T"; "turbine_outlet_P"; ...
    "compressor_inlet_T"; "compressor_inlet_P"; ...
    "compressor_outlet_T"; "compressor_outlet_P"; ...
    "recuperator_hot_outlet_T"; "recuperator_hot_outlet_P"; ...
    "recuperator_cold_outlet_T"; "recuperator_cold_outlet_P"; ...
    "cooler_cold_inlet_T"; "cooler_cold_outlet_T"; ...
    "reactor_power"; "turbine_power"; "compressor_power"; ...
    "tac_electric_power"; "rotor_speed"];

target = [ ...
    1443.27; 1600.00; 1522.96; 1.539e6; 1162.00; 0.676e6; ...
    405.16; 0.658e6; 601.90; 1.551e6; 663.63; 0.676e6; ...
    1100.91; 1.543e6; 360.10; 609.58; ...
    2664e3; 2252.2e3; 1231.6e3; 1000.21e3; 55090];

unit = [ ...
    repmat("K", 3, 1); "Pa"; "K"; "Pa"; "K"; "Pa"; "K"; "Pa"; ...
    "K"; "Pa"; "K"; "Pa"; "K"; "K"; ...
    "W"; "W"; "W"; "W"; "rpm"];

settleDeadline_s = [ ...
    75; NaN; 75; NaN; 300; NaN; 75; NaN; 300; NaN; ...
    180; NaN; 180; NaN; 180; 75; 300; 300; 300; 300; 0];

relTol = repmat(s.outputRelTol, numel(name), 1);
relTol(name == "rotor_speed") = 1 / 55090;
s.metrics = table(name, target, unit, relTol, settleDeadline_s);
s.speedAbsTol_rpm = 1;
end
```

- [ ] **Step 4: 运行目标测试**

Run the Task 1 Step 2 command again.

Expected: PASS，2 tests passed。

- [ ] **Step 5: 提交目标定义**

```bash
git add tests/steady53/steady53_spec.m tests/steady53/test_steady53_spec.m
git commit -m "test: encode section 5.3.1 steady targets"
```

### Task 2: 测试先行实现纯 MATLAB 稳态判定器

**Files:**
- Create: `tests/steady53/test_evaluate_steady53.m`
- Create: `tests/steady53/evaluate_steady53.m`

- [ ] **Step 1: 写合成稳定数据通过、漂移数据失败的测试**

Create `tests/steady53/test_evaluate_steady53.m`:

```matlab
function tests = test_evaluate_steady53
tests = functiontests(localfunctions);
end

function testStableSyntheticCasePasses(testCase)
s = steady53_spec();
t = (0:10:14000)';
signals = syntheticSignals(s, t, 0);
audit = cleanAudit();
report = evaluate_steady53(t, signals, audit, s);
verifyTrue(testCase, report.pass);
verifyEmpty(testCase, report.failures);
end

function testLongTermDriftFails(testCase)
s = steady53_spec();
t = (0:10:14000)';
signals = syntheticSignals(s, t, 0);
ix = t >= 13000;
signals.reactor_inlet_T(ix) = 1443.27 .* ...
    (1 + 0.002 .* (t(ix) - 13000) ./ 1000);
report = evaluate_steady53(t, signals, cleanAudit(), s);
verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(contains(report.failures, "reactor_inlet_T:peak_to_peak")));
end

function testWarningAndLookupExtrapolationFail(testCase)
s = steady53_spec();
t = (0:10:14000)';
signals = syntheticSignals(s, t, 0);
audit = cleanAudit();
audit.warningIds = "HeXe:T_hi";
audit.lookup(1) = struct("name", "compressor_speed", ...
    "inputMin", 1.0, "inputMax", 1.2, "bpMin", 0.9, "bpMax", 1.1);
report = evaluate_steady53(t, signals, audit, s);
verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(contains(report.failures, "warning:HeXe:T_hi")));
verifyTrue(testCase, any(contains(report.failures, "lookup:compressor_speed")));
end

function testInternalFluidStateOutsideDomainFails(testCase)
s = steady53_spec();
t = (0:10:14000)';
signals = syntheticSignals(s, t, 0);
audit = cleanAudit();
audit.states(1) = struct("path", "model/recuperator/T_hot", ...
    "fluid", "HeXe", "data", repmat(2200, size(t)));
report = evaluate_steady53(t, signals, audit, s);
verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(contains(report.failures, "state:HeXe_domain")));
end

function signals = syntheticSignals(s, t, fractionalOffset)
signals = struct();
for k = 1:height(s.metrics)
    signals.(s.metrics.name(k)) = repmat( ...
        s.metrics.target(k) .* (1 + fractionalOffset), size(t));
end
end

function audit = cleanAudit()
audit.warningIds = strings(0,1);
audit.lookup = struct("name", {}, "inputMin", {}, "inputMax", {}, ...
    "bpMin", {}, "bpMax", {});
audit.property = struct("HeXeMin_K", 100, "HeXeMax_K", 2000, ...
    "LithiumMin_K", 453.7, "LithiumMax_K", 1608);
audit.massClosureRel = 0;
audit.states = struct("path", {}, "fluid", {}, "data", {});
end
```

- [ ] **Step 2: 运行并确认函数缺失失败**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_evaluate_steady53.m'); assertSuccess(r)"
```

Expected: FAIL，原因包含 `evaluate_steady53` 未定义。

- [ ] **Step 3: 实现判定器**

Create `tests/steady53/evaluate_steady53.m`:

```matlab
function report = evaluate_steady53(t, signals, audit, s)
arguments
    t (:,1) double
    signals (1,1) struct
    audit (1,1) struct
    s (1,1) struct
end

failures = strings(0,1);
rows = table();
window = t >= s.finalWindow_s(1) & t <= s.finalWindow_s(2);
if ~any(window) || t(end) ~= s.stopTime_s
    failures(end+1) = "time:not_14000";
end

for k = 1:height(s.metrics)
    name = s.metrics.name(k);
    if ~isfield(signals, name)
        failures(end+1) = name + ":missing";
        continue
    end
    y = double(signals.(name)(:));
    if numel(y) ~= numel(t) || any(~isfinite(y)) || ~isreal(y)
        failures(end+1) = name + ":invalid";
        continue
    end
    target = s.metrics.target(k);
    finalValue = mean(y(window));
    relError = abs(finalValue - target) / abs(target);
    peakToPeak = (max(y(window)) - min(y(window))) / abs(target);
    p = polyfit(t(window) - t(find(window,1)), y(window), 1);
    trend = abs(p(1) * diff(s.finalWindow_s)) / abs(target);
    outside = abs(y - target) > abs(target) * s.metrics.relTol(k);
    lastOutside = find(outside, 1, "last");
    if isempty(lastOutside)
        settlingTime = t(1);
    elseif lastOutside == numel(t)
        settlingTime = Inf;
    else
        settlingTime = t(lastOutside + 1);
    end
    if relError > s.metrics.relTol(k)
        failures(end+1) = name + ":target";
    end
    if peakToPeak > s.windowPeakToPeakTol
        failures(end+1) = name + ":peak_to_peak";
    end
    if trend > s.windowTrendTol
        failures(end+1) = name + ":trend";
    end
    deadline = s.metrics.settleDeadline_s(k);
    if isfinite(deadline) && settlingTime > deadline
        failures(end+1) = name + ":settling";
    end
    rows = [rows; table(name, target, finalValue, relError, ...
        peakToPeak, trend, settlingTime)]; %#ok<AGROW>
end

for id = string(audit.warningIds(:))'
    failures(end+1) = "warning:" + id;
end
for k = 1:numel(audit.lookup)
    a = audit.lookup(k);
    if a.inputMin < a.bpMin || a.inputMax > a.bpMax
        failures(end+1) = "lookup:" + string(a.name);
    end
end
if audit.property.HeXeMin_K < s.property.HeXe_K(1) || ...
        audit.property.HeXeMax_K > s.property.HeXe_K(2)
    failures(end+1) = "property:HeXe";
end
if audit.property.LithiumMin_K < s.property.Lithium_K(1) || ...
        audit.property.LithiumMax_K > s.property.Lithium_K(2)
    failures(end+1) = "property:Lithium";
end
if audit.massClosureRel > s.massClosureTol
    failures(end+1) = "mass:closure";
end
for k = 1:numel(audit.states)
    state = audit.states(k);
    y = double(state.data(:));
    label = string(state.path);
    if any(~isfinite(y)) || ~isreal(y)
        failures(end+1) = "state:invalid:" + label;
        continue
    end
    isTemperature = contains(label, "/T_") || contains(label, "T_rad_");
    if isTemperature && any(y <= 0)
        failures(end+1) = "state:nonpositive:" + label;
    end
    if state.fluid == "HeXe" && ...
            (min(y) < s.property.HeXe_K(1) || max(y) > s.property.HeXe_K(2))
        failures(end+1) = "state:HeXe_domain:" + label;
    elseif state.fluid == "Lithium" && ...
            (min(y) < s.property.Lithium_K(1) || max(y) > s.property.Lithium_K(2))
        failures(end+1) = "state:Lithium_domain:" + label;
    end
end

report.pass = isempty(failures);
report.failures = unique(failures, "stable");
report.metrics = rows;
report.audit = audit;
end
```

- [ ] **Step 4: 运行判定器测试和目标测试**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53'); assertSuccess(r)"
```

Expected: PASS，Task 1–2 的 5 tests 全部通过。

- [ ] **Step 5: 提交判定器**

```bash
git add tests/steady53/evaluate_steady53.m tests/steady53/test_evaluate_steady53.m
git commit -m "test: add steady-state acceptance evaluator"
```

### Task 3: 测试先行建立模型运行器和信号清单

**Files:**
- Create: `tests/steady53/steady53_signal_manifest.m`
- Create: `tests/steady53/run_steady53_case.m`
- Create: `tests/steady53/test_run_steady53_case.m`

- [ ] **Step 1: 写清单可解析和模型不落盘测试**

Create `tests/steady53/test_run_steady53_case.m`:

```matlab
function tests = test_run_steady53_case
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
addpath(fullfile(root, "tests", "steady53"));
run(fullfile(root, "start.m"));
end

function testManifestResolvesCurrentModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));
m = steady53_signal_manifest("final_steady_24a");
for k = 1:numel(m)
    verifyNotEqual(testCase, getSimulinkBlockHandle(m(k).block), -1);
    ports = get_param(m(k).block, "PortHandles");
    verifyGreaterThanOrEqual(testCase, numel(ports.Outport), m(k).port);
end
clear c
end

function testShortRunDoesNotRewriteModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
before = sha256File(modelPath);
result = run_steady53_case(modelPath, 1, false);
after = sha256File(modelPath);
verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 1);
verifyEqual(testCase, after, before);
end

function h = sha256File(path)
[status, text] = system("shasum -a 256 " + quoted(path));
assert(status == 0);
parts = split(strtrim(text));
h = string(parts(1));
end

function q = quoted(path)
q = "'" + replace(string(path), "'", "'\\''") + "'";
end
```

- [ ] **Step 2: 运行并确认清单函数缺失失败**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_run_steady53_case.m'); assertSuccess(r)"
```

Expected: FAIL，首先报告 `steady53_signal_manifest` 未定义。

- [ ] **Step 3: 实现关键输出清单**

Create `tests/steady53/steady53_signal_manifest.m`:

```matlab
function m = steady53_signal_manifest(model)
arguments
    model (1,1) string
end
row = @(name, block, port, fluid) struct( ...
    "name", string(name), "block", model + "/" + string(block), ...
    "port", port, "fluid", string(fluid));
m = [ ...
    row("reactor_inlet_T", "IHX", 1, "HeXe"); ...
    row("turbine_inlet_P", "IHX", 2, "none"); ...
    row("turbine_inlet_T", "IHX", 3, "HeXe"); ...
    row("reactor_outlet_T", "reactor", 1, "Lithium"); ...
    row("turbine_outlet_P", "TAC", 1, "none"); ...
    row("turbine_outlet_T", "TAC", 3, "HeXe"); ...
    row("compressor_outlet_T", "TAC", 4, "HeXe"); ...
    row("compressor_outlet_P", "TAC", 6, "none"); ...
    row("recuperator_hot_outlet_T", "recuperator", 1, "HeXe"); ...
    row("recuperator_hot_outlet_P", "recuperator", 2, "none"); ...
    row("recuperator_cold_outlet_P", "recuperator", 4, "none"); ...
    row("recuperator_cold_outlet_T", "recuperator", 6, "HeXe"); ...
    row("compressor_inlet_P", "precooler", 2, "none"); ...
    row("compressor_inlet_T", "precooler", 3, "HeXe"); ...
    row("cooler_cold_outlet_T", "precooler", 4, "none"); ...
    row("cooler_cold_inlet_T", "rediator", 1, "none"); ...
    row("turbine_power", "TAC/Turbine", 4, "none"); ...
    row("compressor_power", "TAC/Compressor", 2, "none"); ...
    row("rotor_speed", "TAC/Constant", 1, "none"); ...
    row("turbine_expansion_ratio", "TAC/Compressor", 1, "none"); ...
    row("hexe_mdot_turbine", "TAC", 2, "none"); ...
    row("hexe_mdot_compressor", "TAC", 5, "none"); ...
    row("hexe_mdot_ihx", "IHX", 5, "none"); ...
    row("hexe_mdot_recup_hot", "recuperator", 3, "none"); ...
    row("hexe_mdot_recup_cold", "recuperator", 5, "none"); ...
    row("lithium_mdot_reactor", "reactor", 2, "none"); ...
    row("lithium_mdot_ihx", "IHX", 4, "none")];
end
```

- [ ] **Step 4: 实现运行器**

Create `tests/steady53/run_steady53_case.m`:

```matlab
function result = run_steady53_case(modelPath, stopTime_s, logSignals)
arguments
    modelPath {mustBeTextScalar}
    stopTime_s (1,1) double {mustBePositive}
    logSignals (1,1) logical = true
end

modelPath = string(modelPath);
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
run(fullfile(root, "start.m"));
[modelDir, model, ext] = fileparts(modelPath);
assert(ext == ".slx");
addpath(modelDir);
before = sha256File(modelPath);
load_system(modelPath);
cleanupModel = onCleanup(@() close_system(model, 0));

warnIds = ["HeXe:T_lo", "HeXe:T_hi", ...
    "Lithium_property_simulink:TemperatureBelowRange", ...
    "Lithium_property_simulink:TemperatureAboveRange"];
oldWarn = cell(size(warnIds));
for k = 1:numel(warnIds)
    oldWarn{k} = warning("query", warnIds(k));
    warning("error", warnIds(k));
end
cleanupWarnings = onCleanup(@() restoreWarnings(oldWarn));

manifest = steady53_signal_manifest(model);
stateBlocks = strings(0,1);
stateLogNames = strings(0,1);
if logSignals
    for k = 1:numel(manifest)
        ports = get_param(manifest(k).block, "PortHandles");
        set_param(ports.Outport(manifest(k).port), "DataLogging", "on", ...
            "DataLoggingNameMode", "Custom", ...
            "DataLoggingName", manifest(k).name);
    end
    stateBlocks = string(find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "BlockType", "Integrator"));
    stateLogNames = compose("steady53_state_%03d", 1:numel(stateBlocks))';
    for k = 1:numel(stateBlocks)
        ports = get_param(stateBlocks(k), "PortHandles");
        set_param(ports.Outport(1), "DataLogging", "on", ...
            "DataLoggingNameMode", "Custom", ...
            "DataLoggingName", stateLogNames(k));
    end
end

in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(stopTime_s, "%.17g"), ...
    "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", ...
    "SignalLoggingName", "logsout");

result = struct("success", false, "errorId", "", "errorReport", "", ...
    "tFinal_s", NaN, "t", [], "signals", struct(), ...
    "states", struct("path", {}, "fluid", {}, "data", {}), ...
    "warningIds", strings(0,1), "modelHashBefore", before, ...
    "modelHashAfter", "");
try
    out = sim(in);
    result.success = true;
    result.tFinal_s = out.tout(end);
    result.t = out.tout;
    if logSignals
        for k = 1:numel(manifest)
            ts = out.logsout.get(manifest(k).name).Values;
            result.signals.(manifest(k).name) = ...
                interp1(ts.Time, squeeze(ts.Data), out.tout, "linear", "extrap");
        end
        result.signals.reactor_power = workspaceSeries(out, "P_sw", out.tout);
        eta = 1000.21e3 / (2252.2e3 - 1231.6e3);
        result.signals.tac_electric_power = eta .* ...
            (result.signals.turbine_power - result.signals.compressor_power);
        for k = 1:numel(stateBlocks)
            ts = out.logsout.get(stateLogNames(k)).Values;
            result.states(k).path = stateBlocks(k);
            result.states(k).fluid = classifyStateFluid(stateBlocks(k));
            result.states(k).data = ...
                interp1(ts.Time, squeeze(ts.Data), out.tout, "linear", "extrap");
        end
    end
catch ME
    result.errorId = string(ME.identifier);
    result.errorReport = string(getReport(ME, "extended", "hyperlinks", "off"));
    if startsWith(result.errorId, "HeXe:") || ...
            startsWith(result.errorId, "Lithium_property_simulink:")
        result.warningIds = result.errorId;
    end
end
clear cleanupWarnings cleanupModel
result.modelHashAfter = sha256File(modelPath);
assert(result.modelHashAfter == result.modelHashBefore, ...
    "steady53:ModelWasRewritten", "Diagnostic run rewrote the model file.");
end

function y = workspaceSeries(out, name, targetTime)
v = out.get(name);
if isa(v, "timeseries")
    y = interp1(v.Time, squeeze(v.Data), targetTime, "linear", "extrap");
elseif isnumeric(v) && size(v,2) >= 2
    y = interp1(v(:,1), v(:,2), targetTime, "linear", "extrap");
else
    error("steady53:UnsupportedWorkspaceSeries", ...
        "Unsupported workspace format for %s.", name);
end
end

function restoreWarnings(oldWarn)
for k = 1:numel(oldWarn)
    warning(oldWarn{k}.state, oldWarn{k}.identifier);
end
end

function fluid = classifyStateFluid(path)
path = string(path);
if contains(path, "/IHX/") && contains(path, "/T_c")
    fluid = "HeXe";
elseif contains(path, "/IHX/") && contains(path, "/T_h")
    fluid = "Lithium";
elseif contains(path, "/recuperator/") && contains(path, "/T_")
    fluid = "HeXe";
elseif contains(path, "/precooler/") && contains(path, "/T_h")
    fluid = "HeXe";
else
    fluid = "none";
end
end

function h = sha256File(path)
[status, text] = system("shasum -a 256 " + quoted(path));
assert(status == 0);
parts = split(strtrim(text));
h = string(parts(1));
end

function q = quoted(path)
q = "'" + replace(string(path), "'", "'\\''") + "'";
end
```

- [ ] **Step 5: 运行运行器测试**

Run the Task 3 Step 2 command again.

Expected: PASS。当前模型完成 `1 s` 短运行；源模型哈希不变。当前长时失败由 Task 4
单独固定，运行器自身的长期行为测试不会在修复后继续期待生产模型失败。

- [ ] **Step 6: 运行现有全部测试**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53'); assertSuccess(r)"
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: MATLAB helper tests通过；现有 6 个 Python provenance tests通过。

- [ ] **Step 7: 提交运行器**

```bash
git add tests/steady53/steady53_signal_manifest.m \
  tests/steady53/run_steady53_case.m \
  tests/steady53/test_run_steady53_case.m
git commit -m "test: add isolated steady model runner"
```

### Task 4: 固化当前整机 RED 验收和转速定义域失败

**Files:**
- Create: `tests/steady53/test_final_steady_acceptance.m`

- [ ] **Step 1: 写当前应当失败的正式要求测试**

Create `tests/steady53/test_final_steady_acceptance.m`:

```matlab
function tests = test_final_steady_acceptance
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
addpath(fullfile(root, "tests", "steady53"));
run(fullfile(root, "start.m"));
end

function testActualComponentSpeedIsPaperNominal(testCase)
model = "final_steady_24a";
load_system(fullfile(testCase.TestData.root, model + ".slx"));
c = onCleanup(@() close_system(model, 0));
actual = str2double(get_param(model + "/TAC/Constant", "Value"));
verifyEqual(testCase, actual, 55090, "AbsTol", 1);
verifyGreaterThanOrEqual(testCase, actual / N_design, min(speed_bp));
verifyLessThanOrEqual(testCase, actual / N_design, max(speed_bp));
clear c
end

function testModelReaches14000WithoutPropertyOrSolverFailure(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
result = run_steady53_case(modelPath, 14000, false);
verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 14000);
verifyEmpty(testCase, result.warningIds);
end
```

- [ ] **Step 2: 运行 RED 测试并保存完整输出**

Run:

```bash
mkdir -p tmp/steady53
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_final_steady_acceptance.m'); disp(table(r)); assertSuccess(r)" \
  2>&1 | tee tmp/steady53/red_baseline.txt
```

Expected: 2 failures：实际转速为 `66100`，以及整机未到 `14000 s`。确认失败原因不是测试
语法、路径或初始化错误。

- [ ] **Step 3: 在实验日志记录 RED 基线**

Create `docs/steady53_experiment_log.md` with this exact initial entry:

```markdown
# 第 5.3.1 节稳态实验日志

## 2026-08-24 RED 基线

- ✅ 模型 SHA256：`08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a`
- ✅ 实际 TAC 部件转速源：`66100 rpm`
- ✅ 压气机归一化转速：`1.199854783`，活动表上限 `1.1`
- ✅ 14000 s 验收：未通过；当前模型在到达终点前触发物性/求解器失败
- 证据文件：`tmp/steady53/red_baseline.txt`（探索输出，不提交）
- 结论：两个正式要求测试均能捕获当前缺口，RED 阶段成立
```

- [ ] **Step 4: 提交 RED 测试与日志**

```bash
git add tests/steady53/test_final_steady_acceptance.m \
  docs/steady53_experiment_log.md
git commit -m "test: reproduce steady baseline failures"
```

### Task 5: 在探索副本检验 55090 rpm 单变量假设

**Files:**
- Create: `tests/steady53/run_speed_hypothesis.m`
- Modify: `docs/steady53_experiment_log.md`
- Create at runtime only: `tmp/steady53/final_steady_speed55090.slx`
- Create at runtime only: `tmp/steady53/speed55090_result.mat`

- [ ] **Step 1: 写探索函数的失败调用检查**

Run before creating the function:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); run_speed_hypothesis()"
```

Expected: FAIL，原因包含 `run_speed_hypothesis` 未定义。

- [ ] **Step 2: 实现只改探索副本的实验函数**

Create `tests/steady53/run_speed_hypothesis.m`:

```matlab
function summary = run_speed_hypothesis()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(root, "tests", "steady53"));
run(fullfile(root, "start.m"));
tmpDir = fullfile(root, "tmp", "steady53");
if ~isfolder(tmpDir), mkdir(tmpDir); end
source = fullfile(root, "final_steady_24a.slx");
copy = fullfile(tmpDir, "final_steady_speed55090.slx");
sourceHashBefore = sha256File(source);
copyfile(source, copy, "f");

model = "final_steady_speed55090";
load_system(copy);
set_param(model + "/TAC/Constant", "Value", "55090");
set_param(model, "StopTime", "500");
save_system(model, copy);
close_system(model, 0);

result = run_steady53_case(copy, 500, true);
summary = rmfield(result, ["t", "signals", "states"]);
summary.sourceHashBefore = sourceHashBefore;
summary.sourceHashAfter = sha256File(source);
summary.sourceUnchanged = summary.sourceHashAfter == sourceHashBefore;
summary.normalizedCompressorSpeed = 55090 / N_design;
summary.compressorSpeedInRange = ...
    summary.normalizedCompressorSpeed >= min(speed_bp) && ...
    summary.normalizedCompressorSpeed <= max(speed_bp);
save(fullfile(tmpDir, "speed55090_result.mat"), "result", "summary");
assert(summary.sourceUnchanged);
end

function h = sha256File(path)
[status, text] = system("shasum -a 256 '" + ...
    replace(string(path), "'", "'\\''") + "'");
assert(status == 0);
parts = split(strtrim(text));
h = string(parts(1));
end
```

- [ ] **Step 3: 运行单变量实验**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); s=run_speed_hypothesis(); disp(s)" \
  2>&1 | tee tmp/steady53/speed55090_console.txt
```

Expected invariants, independent of whether the coupled model passes:

- `sourceUnchanged = true`
- `normalizedCompressorSpeed = 1`
- `compressorSpeedInRange = true`
- 正式模型 SHA256 仍为原值

- [ ] **Step 4: 按固定决策表记录实验结果**

Append one of the following evidence records to `docs/steady53_experiment_log.md`:

```markdown
## 55090 rpm 单变量实验

- ✅ 正式模型未改写
- ✅ 探索副本实际部件转速为 55090 rpm
- ✅ 压气机归一化转速为 1.0，位于活动表内
- ✅/未通过 500 s 完成状态：按 `summary.success` 原样记录
- ✅ 若未完成：按 `summary.errorId` 和 `summary.errorReport` 原样记录
- ❓ 结论边界：该实验只验证转速接线对定义域和整机轨迹的影响，不把结果改善单独视为全部根因
```

Do not replace `✅/未通过` literally: select `✅` only when `summary.success=true`; otherwise write
`未通过（✅本轮已核实）` and include the exact error identifier.

- [ ] **Step 5: 提交探索函数和实验摘要**

```bash
git add tests/steady53/run_speed_hypothesis.m docs/steady53_experiment_log.md
git commit -m "test: evaluate nominal speed hypothesis"
```

Do not add `tmp/steady53/`.

### Task 6: 建立论文图 5.18 对应的部件恒边界工装

**Files:**
- Create: `tests/steady53/steady53_component_boundaries.m`
- Create: `tests/steady53/create_component_harness.m`
- Create: `tests/steady53/test_component_harnesses.m`

- [ ] **Step 1: 写边界值和工装生成失败测试**

Create `tests/steady53/test_component_harnesses.m`:

```matlab
function tests = test_component_harnesses
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
addpath(fullfile(root, "tests", "steady53"));
run(fullfile(root, "start.m"));
end

function testBoundaryValuesAreExplicit(testCase)
b = steady53_component_boundaries();
verifyEqual(testCase, b.IHX.inputs, [1600 4.572 11.97 1100.91 1.543e6]);
verifyEqual(testCase, b.recuperator.inputs, ...
    [11.97 1162 0.676e6 1.551e6 601.90 11.97]);
verifyEqual(testCase, b.precooler.inputs, ...
    [360.10 6.95 663.63 0.676e6 11.97]);
verifyEqual(testCase, b.rediator.inputs, [609.58 6.95]);
verifyEqual(testCase, b.reactor.inputs, 1443.27);
verifyEqual(testCase, b.TAC.inputs, ...
    [1.539e6 1522.96 405.16 0.658e6 11.97 1000e3]);
end

function testHarnessesCompile(testCase)
components = ["IHX", "recuperator", "precooler", "rediator", "reactor", "TAC"];
for component = components
    harness = create_component_harness(component);
    c = onCleanup(@() close_system(harness.model, 0));
    set_param(harness.model, "SimulationCommand", "update");
    verifyTrue(testCase, isfile(harness.path));
    clear c
end
end
```

- [ ] **Step 2: 运行并确认边界函数缺失失败**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_component_harnesses.m'); assertSuccess(r)"
```

Expected: FAIL，原因包含 `steady53_component_boundaries` 未定义。

- [ ] **Step 3: 实现明确的部件边界**

Create `tests/steady53/steady53_component_boundaries.m`:

```matlab
function b = steady53_component_boundaries()
item = @(inputs, inputNames, source) struct( ...
    "inputs", inputs, "inputNames", string(inputNames), "source", string(source));
b.IHX = item([1600 4.572 11.97 1100.91 1.543e6], ...
    ["T_hi" "mdot_Li" "mdot_HeXe" "T_ci" "P_ci"], ...
    "Table 5.2 temperatures/pressure; current baseline mass-flow ICs");
b.recuperator = item([11.97 1162 0.676e6 1.551e6 601.90 11.97], ...
    ["mdot_h_in" "T_h_in" "P_h" "P_c" "T_c_in" "mdot_c_in"], ...
    "Table 5.2 terminals; current baseline HeXe mass-flow IC");
b.precooler = item([360.10 6.95 663.63 0.676e6 11.97], ...
    ["T_c_in" "mdot_c_in" "T_h_in" "P_h" "mdot_h_in"], ...
    "Table 5.2 terminals; current baseline coolant/HeXe mass-flow ICs");
b.rediator = item([609.58 6.95], ["T_hi" "m_hi"], ...
    "Table 5.2 terminal; current baseline coolant mass-flow IC");
b.reactor = item(1443.27, "T_in", "Table 5.2 reactor inlet");
b.TAC = item([1.539e6 1522.96 405.16 0.658e6 11.97 1000e3], ...
    ["P_in_Turbine" "T_in_Turbine" "T_in_Compressor" ...
     "p_in_Compressor" "m_in_Compressor" "Pload"], ...
    "Table 5.2 terminals; current baseline HeXe mass-flow IC; section 5.3.1 load");
end
```

- [ ] **Step 4: 实现通用部件工装生成器**

Create `tests/steady53/create_component_harness.m`:

```matlab
function h = create_component_harness(component)
arguments
    component (1,1) string
end
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
run(fullfile(root, "start.m"));
tmpDir = fullfile(root, "tmp", "steady53", "components");
if ~isfolder(tmpDir), mkdir(tmpDir); end
sourceModel = "final_steady_24a";
load_system(fullfile(root, sourceModel + ".slx"));
cleanupSource = onCleanup(@() close_system(sourceModel, 0));
b = steady53_component_boundaries();
assert(isfield(b, component));
cfg = b.(component);

model = "steady53_component_" + component;
path = fullfile(tmpDir, model + ".slx");
if bdIsLoaded(model), close_system(model, 0); end
new_system(model);
add_block(sourceModel + "/" + component, model + "/DUT", ...
    "Position", [300 100 520 360]);
if component == "TAC"
    assert(strcmp(get_param(model + "/DUT/Constant", "Value"), "66100"));
    set_param(model + "/DUT/Constant", "Value", "55090");
end

inports = find_system(model + "/DUT", "SearchDepth", 1, "BlockType", "Inport");
[~, order] = sort(cellfun(@(p) str2double(get_param(p, "Port")), inports));
inports = inports(order);
assert(numel(inports) == numel(cfg.inputs));
for k = 1:numel(inports)
    block = model + "/Input_" + k;
    add_block("simulink/Sources/Constant", block, ...
        "Value", num2str(cfg.inputs(k), "%.17g"), ...
        "Position", [40 30+45*k 140 50+45*k]);
    add_line(model, "Input_" + k + "/1", "DUT/" + k, "autorouting", "on");
end

outports = find_system(model + "/DUT", "SearchDepth", 1, "BlockType", "Outport");
[~, order] = sort(cellfun(@(p) str2double(get_param(p, "Port")), outports));
outports = outports(order);
for k = 1:numel(outports)
    block = model + "/Output_" + k;
    add_block("simulink/Sinks/To Workspace", block, ...
        "VariableName", "y_" + k, "SaveFormat", "Timeseries", ...
        "Position", [650 30+45*k 760 50+45*k]);
    add_line(model, "DUT/" + k, "Output_" + k + "/1", "autorouting", "on");
end
set_param(model, "Solver", "ode15s", "RelTol", "1e-3", ...
    "StopTime", "500", "ReturnWorkspaceOutputs", "on");
save_system(model, path);
close_system(model, 0);
load_system(path);
clear cleanupSource
h = struct("model", model, "path", string(path), "component", component);
end
```

- [ ] **Step 5: 运行部件工装生成测试**

Run the Task 6 Step 2 command again.

Expected: PASS；六个探索工装均能更新/编译，正式模型哈希不变。

- [ ] **Step 6: 增加 500 s 有界性测试并观察真实失败矩阵**

Append to `tests/steady53/test_component_harnesses.m`:

```matlab
function testHarnessesRunBoundedFor500Seconds(testCase)
components = ["IHX", "recuperator", "precooler", "rediator", "reactor", "TAC"];
for component = components
    h = create_component_harness(component);
    out = sim(h.model, "StopTime", "500", "ReturnWorkspaceOutputs", "on");
    verifyEqual(testCase, out.tout(end), 500, "Component: " + component);
    vars = who(out);
    outputVars = vars(startsWith(vars, "y_"));
    for k = 1:numel(outputVars)
        ts = out.get(outputVars{k});
        verifyTrue(testCase, all(isfinite(ts.Data(:))), ...
            component + ":" + outputVars{k});
        verifyTrue(testCase, isreal(ts.Data), component + ":" + outputVars{k});
    end
    close_system(h.model, 0);
end
end
```

Run the Task 6 Step 2 command again.

Expected: 测试输出形成明确的部件通过/失败矩阵。若某个工装失败，记录第一个失败部件、
时间、错误标识和物性警告；不要修改正式模型。

- [ ] **Step 7: 增加并运行部件 14000 s 长时有界性测试**

Append to `tests/steady53/test_component_harnesses.m`:

```matlab
function testHarnessesRunBoundedFor14000Seconds(testCase)
ids = ["HeXe:T_lo" "HeXe:T_hi" ...
    "Lithium_property_simulink:TemperatureBelowRange" ...
    "Lithium_property_simulink:TemperatureAboveRange"];
old = cell(size(ids));
for k = 1:numel(ids)
    old{k} = warning("query", ids(k));
    warning("error", ids(k));
end
c = onCleanup(@() restoreWarningStates(old));
components = ["IHX", "recuperator", "precooler", "rediator", "reactor", "TAC"];
for component = components
    h = create_component_harness(component);
    out = sim(h.model, "StopTime", "14000", "ReturnWorkspaceOutputs", "on");
    verifyEqual(testCase, out.tout(end), 14000, "Component: " + component);
    vars = who(out);
    outputVars = vars(startsWith(vars, "y_"));
    for k = 1:numel(outputVars)
        ts = out.get(outputVars{k});
        verifyTrue(testCase, all(isfinite(ts.Data(:))), ...
            component + ":" + outputVars{k});
        verifyTrue(testCase, isreal(ts.Data), component + ":" + outputVars{k});
    end
    close_system(h.model, 0);
end
clear c
end

function restoreWarningStates(old)
for k = 1:numel(old)
    warning(old{k}.state, old{k}.identifier);
end
end
```

Run the Task 6 Step 2 command again.

Expected: every component reaches `14000 s` with finite real outputs and no property-domain warning. Any failure
activates the Root-Cause Checkpoint before a formal model change beyond the independently proven speed fix.

- [ ] **Step 8: 提交工装代码和失败矩阵摘要**

在 `docs/steady53_experiment_log.md` 追加每个部件的 `500 s` 结果，然后：

```bash
git add tests/steady53/steady53_component_boundaries.m \
  tests/steady53/create_component_harness.m \
  tests/steady53/test_component_harnesses.m \
  docs/steady53_experiment_log.md
git commit -m "test: isolate section 5.3.1 component dynamics"
```

### Task 7: 将已证明的 55090 rpm 工作点修正应用到正式模型

**Files:**
- Modify: `final_steady_24a.slx`
- Test: `tests/steady53/test_final_steady_acceptance.m`
- Modify: `docs/steady53_experiment_log.md`

此任务只修复已经由 Task 4 RED 测试和 Task 5 定义域实验共同证明的转速工作点错误。
它不宣称同时修复换热器失稳。

- [ ] **Step 1: 重新确认转速测试仍为 RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_final_steady_acceptance.m', 'Name','testActualComponentSpeedIsPaperNominal'); assertSuccess(r)"
```

Expected: FAIL，实际值 `66100`，期望 `55090 ± 1`。

- [ ] **Step 2: 对正式模型做单一最小修改**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "mdl='final_steady_24a'; load_system(mdl); assert(strcmp(get_param([mdl '/TAC/Constant'],'Value'),'66100')); set_param([mdl '/TAC/Constant'],'Value','55090'); save_system(mdl); close_system(mdl,0);"
```

This modifies only `final_steady_24a/TAC/Constant.Value`.

- [ ] **Step 3: 验证转速测试由红变绿**

Run the Task 7 Step 1 command again.

Expected: PASS；归一化压气机转速为 `1.0` 且位于 `0.9–1.1`。

- [ ] **Step 4: 验证 SLX 只包含预期语义变化**

Run:

```bash
git status --short -- final_steady_24a.slx
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "run('start.m'); mdl='final_steady_24a'; load_system(mdl); fprintf('N=%s Stop=%s Solver=%s RelTol=%s\\n',get_param([mdl '/TAC/Constant'],'Value'),get_param(mdl,'StopTime'),get_param(mdl,'Solver'),get_param(mdl,'RelTol')); close_system(mdl,0);"
```

Expected: `N=55090`；`Stop=800`、`Solver=ode15s`、`RelTol=1e-3` 仍未改变。

- [ ] **Step 5: 运行 500 s 整机检查**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=run_steady53_case('final_steady_24a.slx',500,true); disp(rmfield(r,{'t','signals'})); assert(r.success); assert(r.tFinal_s==500);"
```

Expected branch:

- If PASS: proceed to Step 6 and Task 8.
- If FAIL: do not add another production change. Revert neither by destructive command nor by stacking a guess;
  record the exact failure, leave the single speed correction as an isolated commit candidate, and go to the
  Root-Cause Checkpoint after Task 7.

- [ ] **Step 6: 提交独立转速修正**

Append the actual 500 s result to `docs/steady53_experiment_log.md`, then:

```bash
git add final_steady_24a.slx docs/steady53_experiment_log.md
git commit -m "fix: align steady TAC component speed with section 5.3.1"
```

#### Root-Cause Checkpoint（仅在 500 s 未通过时）

如果 Task 7 Step 5 未通过：

1. 从 Task 6 的部件矩阵选择第一个失败部件；
2. 记录该部件第一个越界状态、输入边界、错误时间和调用的物性函数；
3. 对照论文相应方程逐项核对热流方向、温差符号、质量/热容乘积和端口顺序；
4. 创建一个只针对该首个错误的失败回归测试；
5. 在 `docs/superpowers/plans/` 新增带确切块路径、方程和最小修改代码的计划补遗；
6. 请求人工批准补遗后再继续。

该检查点是有意的安全门，不允许在根因未知时提前写“调换符号”“修改换热系数”或
“调整初值”的泛化修复。

### Task 8: 500 s 名义整机及论文图 5.18–5.19 验收

**Files:**
- Modify: `tests/steady53/test_final_steady_acceptance.m`
- Modify: `docs/steady53_experiment_log.md`

只在 Task 7 的 500 s 运行成功，或根因补遗已批准并执行后进入本任务。

- [ ] **Step 1: 写 500 s 论文终值/收敛时间测试**

Append to `tests/steady53/test_final_steady_acceptance.m`:

```matlab
function testNominalCoupledModelMatchesSection531By500Seconds(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
result = run_steady53_case(modelPath, 500, true);
verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 500);
s = steady53_spec();
s.stopTime_s = 500;
s.finalWindow_s = [400 500];
audit = auditForRun(result);
report = evaluate_steady53(result.t, result.signals, audit, s);
verifyTrue(testCase, report.pass, strjoin(report.failures, newline));
end

function audit = auditForRun(result)
audit.warningIds = result.warningIds;
audit.lookup = lookupAudit(result.signals);
audit.property = propertyAudit(result);
audit.massClosureRel = massClosure(result.signals);
audit.states = result.states;
end

function a = lookupAudit(x)
run("start.m");
a = struct("name", {}, "inputMin", {}, "inputMax", {}, ...
    "bpMin", {}, "bpMax", {});
a(end+1) = margin("compressor_speed", x.rotor_speed ./ N_design, speed_bp);
a(end+1) = margin("compressor_mass_ratio", ...
    x.hexe_mdot_compressor ./ 12.04, m_ratio_bp);
a(end+1) = margin("turbine_speed_flow_table", x.rotor_speed, bp_speed);
a(end+1) = margin("turbine_expansion_ratio", ...
    x.turbine_expansion_ratio, bp_er);
a(end+1) = margin("turbine_mass_flow_efficiency_table", ...
    x.hexe_mdot_turbine, bp_mf);
end

function a = margin(name, y, bp)
a = struct("name", string(name), "inputMin", min(y), "inputMax", max(y), ...
    "bpMin", min(bp), "bpMax", max(bp));
end

function p = propertyAudit(result)
names = ["turbine_inlet_T" "turbine_outlet_T" "compressor_inlet_T" ...
    "compressor_outlet_T" "recuperator_hot_outlet_T" ...
    "recuperator_cold_outlet_T"];
hexe = zeros(0,1);
for n = names, hexe = [hexe; result.signals.(n)(:)]; end %#ok<AGROW>
lithium = result.signals.reactor_outlet_T(:);
for k = 1:numel(result.states)
    if result.states(k).fluid == "HeXe"
        hexe = [hexe; result.states(k).data(:)]; %#ok<AGROW>
    elseif result.states(k).fluid == "Lithium"
        lithium = [lithium; result.states(k).data(:)]; %#ok<AGROW>
    end
end
p = struct("HeXeMin_K", min(hexe), "HeXeMax_K", max(hexe), ...
    "LithiumMin_K", min(lithium), "LithiumMax_K", max(lithium));
end

function value = massClosure(x)
hexeNames = ["hexe_mdot_turbine" "hexe_mdot_compressor" ...
    "hexe_mdot_ihx" "hexe_mdot_recup_hot" "hexe_mdot_recup_cold"];
liNames = ["lithium_mdot_reactor" "lithium_mdot_ihx"];
value = max(groupClosure(x, hexeNames), groupClosure(x, liNames));
end

function value = groupClosure(x, names)
y = zeros(numel(x.(names(1))), numel(names));
for k = 1:numel(names), y(:,k) = x.(names(k))(:); end
denominator = max(abs(mean(y, 2)), 1);
value = max((max(y, [], 2) - min(y, [], 2)) ./ denominator);
end
```

- [ ] **Step 2: 运行并确认当前是否 RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_final_steady_acceptance.m', 'Name','testNominalCoupledModelMatchesSection531By500Seconds'); assertSuccess(r)"
```

Expected before all proven fixes: FAIL with exact target/settling/domain identifiers. Do not alter tolerances.

- [ ] **Step 3: 只应用根因补遗中已批准的最小修改**

If Step 2 fails after the speed correction, stop here and follow the Root-Cause Checkpoint. The exact production
change must be in an approved addendum containing the failing test, exact block path, equation evidence and
single modification. This plan deliberately contains no speculative heat-exchanger parameter change.

- [ ] **Step 4: 重跑全部 500 s 与部件测试**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53'); assertSuccess(r)"
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: 全部 MATLAB 500 s/辅助测试和 6 个 Python provenance tests通过，无 warning。

- [ ] **Step 5: 提交 500 s 验收证据**

```bash
git add tests/steady53/test_final_steady_acceptance.m \
  docs/steady53_experiment_log.md
git commit -m "test: verify section 5.3.1 nominal settling"
```

### Task 9: 保存 14000 s 配置并执行两次独立正式验收

**Files:**
- Modify: `final_steady_24a.slx`
- Create: `run_steady53.m`
- Modify: `tests/steady53/test_final_steady_acceptance.m`
- Create: `docs/steady53_validation.md`
- Runtime only: `tmp/steady53/formal_run_1.mat`
- Runtime only: `tmp/steady53/formal_run_2.mat`

- [ ] **Step 1: 写默认 StopTime 和正式入口的失败测试**

Append to `tests/steady53/test_final_steady_acceptance.m`:

```matlab
function testModelDefaultStopTimeIs14000(testCase)
model = "final_steady_24a";
load_system(fullfile(testCase.TestData.root, model + ".slx"));
c = onCleanup(@() close_system(model, 0));
verifyEqual(testCase, str2double(get_param(model, "StopTime")), 14000);
clear c
end

function testFormalEntryPointExists(testCase)
verifyTrue(testCase, isfile(fullfile(testCase.TestData.root, "run_steady53.m")));
end
```

Run these two tests and verify they FAIL because the model still stores `800` and the entry point is absent.

- [ ] **Step 2: 保存正式 StopTime=14000**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "mdl='final_steady_24a'; load_system(mdl); assert(strcmp(get_param(mdl,'StopTime'),'800')); set_param(mdl,'StopTime','14000'); save_system(mdl); close_system(mdl,0);"
```

- [ ] **Step 3: 创建正式运行入口**

Create `run_steady53.m`:

```matlab
function out = run_steady53()
%RUN_STEADY53 Run the approved Section 5.3.1 nominal steady case.
root = fileparts(mfilename("fullpath"));
run(fullfile(root, "start.m"));
model = "final_steady_24a";
load_system(fullfile(root, model + ".slx"));
c = onCleanup(@() close_system(model, 0));
assert(str2double(get_param(model, "StopTime")) == 14000, ...
    "steady53:UnexpectedStopTime", "The formal model StopTime must be 14000 s.");
out = sim(model, "ReturnWorkspaceOutputs", "on");
assert(out.tout(end) == 14000, "steady53:IncompleteRun", ...
    "The nominal steady run did not reach 14000 s.");
clear c
end
```

- [ ] **Step 4: 验证默认配置和入口测试变绿**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53/test_final_steady_acceptance.m', 'Name',{'testModelDefaultStopTimeIs14000','testFormalEntryPointExists'}); assertSuccess(r)"
```

Expected: 2 tests passed。

- [ ] **Step 5: 在第一个全新 MATLAB 进程执行正式带记录验收**

Run:

```bash
mkdir -p tmp/steady53
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=run_steady53_case('final_steady_24a.slx',14000,true); assert(r.success,r.errorReport); save('tmp/steady53/formal_run_1.mat','r','-v7.3');" \
  2>&1 | tee tmp/steady53/formal_run_1.txt
```

Expected: exit 0、`tFinal_s=14000`、无物性 warning。

- [ ] **Step 6: 在第二个全新 MATLAB 进程独立复跑**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=run_steady53_case('final_steady_24a.slx',14000,true); assert(r.success,r.errorReport); save('tmp/steady53/formal_run_2.mat','r','-v7.3');" \
  2>&1 | tee tmp/steady53/formal_run_2.txt
```

Expected: exit 0、`tFinal_s=14000`、无物性 warning。

- [ ] **Step 7: 写两次运行的比较测试**

Append to `tests/steady53/test_final_steady_acceptance.m`:

```matlab
function testTwoIndependentFormalRunsMeetAllGates(testCase)
files = ["formal_run_1.mat" "formal_run_2.mat"];
reports = cell(1,2);
s = steady53_spec();
for k = 1:2
    data = load(fullfile(testCase.TestData.root, "tmp", "steady53", files(k)), "r");
    audit = auditForRun(data.r);
    reports{k} = evaluate_steady53(data.r.t, data.r.signals, audit, s);
    verifyTrue(testCase, reports{k}.pass, strjoin(reports{k}.failures, newline));
end
joined = innerjoin(reports{1}.metrics, reports{2}.metrics, "Keys", "name", ...
    "LeftVariables", ["name" "target" "finalValue"], ...
    "RightVariables", "finalValue");
[found, specIndex] = ismember(joined.name, s.metrics.name);
assert(all(found));
allowed = 0.1 .* s.metrics.relTol(specIndex) .* abs(joined.target);
verifyLessThanOrEqual(testCase, ...
    abs(joined.finalValue_left - joined.finalValue_right), allowed);
end
```

- [ ] **Step 8: 运行完整正式测试套件**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "addpath('tests/steady53'); r=runtests('tests/steady53'); assertSuccess(r)"
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: 0 failures、0 errors、无物性钳位 warning；Python 6/6 passed。

- [ ] **Step 9: 生成正式验证报告**

Create `docs/steady53_validation.md` with these populated sections, using actual values from the two MAT files:

```markdown
# 第 5.3.1 节名义稳态 14000 s 验证

## 可复现环境
- Git commit
- 模型 SHA256
- 10 项直接依赖及 SHA256
- MATLAB/Simulink 版本
- 求解器、容差、StopTime

## 两次独立运行
- 起止时间
- 成功/失败
- warning IDs
- 运行墙钟时间
- 两次终值最大差异

## 论文表 5.2 / 图 5.18–5.19 对比
- 每个可观测量的论文值、运行 1、运行 2、相对误差
- 每个温度/功率的进入 ±1% 带时间
- 不可观测量及原因

## 长期稳态
- 13000–14000 s 峰峰值
- 1000 s 线性趋势
- 质量闭合
- 功率关系

## 物性和查表域
- He-Xe / Li 全时段极值
- 每个查表维度的输入极值、断点和最小裕度

## 证据分级和结论边界
- ✅ 当前直接验证
- ❓ 算术派生或项目数值门槛
- 未执行第 5.3.2 节参数扫描
```

Do not leave headings without actual values. If a field is structurally unobservable, write the exact missing
port/state and do not fabricate a number.

- [ ] **Step 10: 提交正式模型、入口、测试和报告**

```bash
git add final_steady_24a.slx run_steady53.m \
  tests/steady53/test_final_steady_acceptance.m \
  docs/steady53_validation.md docs/steady53_experiment_log.md
git commit -m "feat: validate section 5.3.1 steady model for 14000 seconds"
```

### Task 10: 完成前独立审计

**Files:**
- Verify: `final_steady_24a.slx`
- Verify: all created test and report files
- Verify: `archive/pre-restart-20260824`

- [ ] **Step 1: 运行完成前验证技能**

调用 `verification-before-completion` 技能，明确每项完成声明对应的命令。

- [ ] **Step 2: 新进程执行用户入口**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "out=run_steady53(); fprintf('FINAL_T=%.17g\\n',out.tout(end));"
```

Expected: exit 0 and `FINAL_T=14000`，无物性钳位 warning。

- [ ] **Step 3: 检查正式模型依赖和探索区隔离**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "run('start.m'); [files,products]=matlab.codetools.requiredFilesAndProducts('final_steady_24a.slx'); files=string(files(:)); disp(files); assert(~any(contains(files,filesep+'tests'+filesep))); assert(~any(contains(files,filesep+'tmp'+filesep))); save('tmp/steady53/final_dependencies.mat','files','products');"
```

Expected: exit 0；依赖清单不含 `tests/` 或 `tmp/`。将结果与
`docs/restart_baseline_audit_20260824.md` 的十文件基线逐项比较；任何新增正式依赖必须在
最终报告列出确切路径、用途和证据等级。

- [ ] **Step 4: 检查 Git 范围和存档**

Run:

```bash
git diff --check archive/pre-restart-20260824..HEAD
git status --short
git log --oneline --decorate -12
git rev-parse archive/pre-restart-20260824^{commit}
shasum -a 256 final_steady_24a.slx
```

Expected: no whitespace errors；无意外未提交文件；存档仍解析到
`8f625c268c35a95c18a626305c1aa6a79ae2ace7`。

- [ ] **Step 5: 逐条核对设计完成定义**

Read `docs/superpowers/specs/2026-08-24-steady53-14000s-design.md` section 14 and map every bullet to a test
result or report row. Any unmet item must be reported as incomplete; do not weaken the specification.

- [ ] **Step 6: 使用开发分支收尾技能交付**

调用 `finishing-a-development-branch` 技能，向用户提供合并、保留分支或其他适用的集成选项。

## 计划执行的停止规则

以下任一条件出现时，停止正式模型修改并返回根因检查点：

1. `55090 rpm` 单变量修正后整机仍不能完成 `500 s`；
2. 任一部件恒边界工装出现物性越界或求解器失败；
3. 三个独立根因假设均未解决首个失败；
4. 需要修改论文物理机制、增加反馈/控制器或拟合参数；
5. 需要放宽已批准的 `1%` 论文误差、`0.1%` 窗口波动或 `0.01%` 长期漂移门槛；
6. 正式模型需要依赖 `tests/` 或 `tmp/` 才能运行；
7. 两次独立 `14000 s` 结果不满足重复性要求。

停止时保留所有失败证据，写明支持与反对证据，并请求人工判断；不得用未批准的下一项
修改覆盖前一项失败。
