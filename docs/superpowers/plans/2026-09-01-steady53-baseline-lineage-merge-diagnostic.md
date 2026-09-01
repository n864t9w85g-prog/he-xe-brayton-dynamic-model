# Steady53 Baseline Lineage Merge Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run one exploration-only 500 s candidate that keeps the frozen f8bcd83 model behavior but replaces its exact 40-state initial-condition vector with the repository-root model vector, then compare all four Figure 5.19 power panels.

**Architecture:** One MATLAB builder uses official Simulink APIs to create and audit the candidate without simulation. One MATLAB runner calls the existing isolated `run_steady53_case` exactly once and writes raw/CSV evidence. One Python analyzer reuses the fixed Figure 5.19 paper points and metrics without changing comparison rules.

**Tech Stack:** MATLAB/Simulink R2025a, Python 3 standard library, existing `tests/steady53` runtime, CSV/JSON/MAT, SHA-256.

---

## Fixed experiment contract

- Approved spec: `docs/superpowers/specs/2026-09-01-steady53-baseline-lineage-merge-diagnostic-design.md`.
- Root model SHA-256: `a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159`.
- Frozen model SHA-256: `0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`.
- Exact common Integrator count: 40.
- Only changed parameter: each common Integrator's `InitialCondition`.
- Candidate run count: one; duration: 500 s; no retry, scan, smoothing, fitting, time shift, 14000 s extension, or formal promotion.
- Runtime output root: `tmp/steady53_lineage_merge_20260901_A/`.

## File-responsibility map

| File | Responsibility |
|---|---|
| `tests/create_steady53_lineage_merge_candidate.m` | Create and API-audit the 40-state candidate; never simulate |
| `tests/test_create_steady53_lineage_merge_candidate.m` | Lock source hashes, exact state mapping, and zero-simulation behavior |
| `tests/run_steady53_lineage_merge_diagnostic.m` | Call `run_steady53_case` once and write raw/status/four curves |
| `tests/analyze_steady53_lineage_merge.py` | Compute fixed Figure 5.19 metrics, classification, and plot |
| `tests/test_analyze_steady53_lineage_merge.py` | Lock metric/classification behavior and reject malformed evidence |
| `tmp/steady53_lineage_merge_20260901_A/**` | Exploration-only candidate, raw evidence, metrics, and figure |

### Task 1: Build the exact 40-state candidate without simulation

**Files:**
- Create: `tests/create_steady53_lineage_merge_candidate.m`
- Create: `tests/test_create_steady53_lineage_merge_candidate.m`

- [ ] **Step 1: Write the failing MATLAB contract test**

The test creates a private `tmp/` directory, calls the builder, and requires:

```matlab
audit = create_steady53_lineage_merge_candidate(outputDir, repoRoot);
verifyEqual(testCase, string(audit.schema), ...
    "steady53_lineage_merge_candidate_v1");
verifyEqual(testCase, audit.state_count, 40);
verifyEqual(testCase, audit.changed_state_count, 40);
verifyEqual(testCase, unique(string({audit.changes.parameter})), ...
    "InitialCondition");
verifyEqual(testCase, string(audit.root_model_sha256), ...
    "a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159");
verifyEqual(testCase, string(audit.frozen_model_sha256), ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyTrue(testCase, audit.block_inventory_unchanged);
verifyTrue(testCase, audit.non_ic_dialog_parameters_unchanged);
verifyEqual(testCase, audit.simulation_call_count, 0);
verifyTrue(testCase, isfile(fullfile(outputDir, "candidate.slx")));
verifyTrue(testCase, isfile(fullfile(outputDir, "candidate_audit.json")));
```

The test also hashes the root model, frozen model, root MAT files, and both property functions before/after and requires byte identity.

- [ ] **Step 2: Run RED**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_steady53_lineage_merge_candidate.m'); assertSuccess(r)"
```

Expected: missing builder failure; no model simulation marker.

- [ ] **Step 3: Implement the minimal API builder**

Implement this public flow in `create_steady53_lineage_merge_candidate.m`:

```matlab
rootPath = fullfile(repoRoot, "final_steady_24a.slx");
frozenPath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
requireHash(rootPath, ROOT_SHA256);
requireHash(frozenPath, FROZEN_SHA256);

rootStates = readIntegratorInitialConditions(rootPath);
frozenBefore = readModelContract(frozenPath);
if numel(rootStates) ~= 40 || ...
        ~isequal(sort(string({rootStates.relative_path})), ...
                 sort(string({frozenBefore.states.relative_path})))
    error("lineagemerge:StateSetMismatch", ...
        "Root and frozen models must expose the same exact 40 Integrator paths.");
end

if isfile(candidatePath) || isfolder(candidatePath)
    error("lineagemerge:CandidateExists", ...
        "Candidate path must not already exist; this run never overwrites evidence.");
end
copyfile(frozenPath, candidatePath);
load_system(candidatePath);
for index = 1:numel(rootStates)
    target = "candidate/" + rootStates(index).relative_path;
    set_param(target, "InitialCondition", rootStates(index).expression);
end
save_system("candidate", candidatePath);
close_system("candidate", 0);

candidateAfter = readModelContract(candidatePath);
changes = compareContracts(frozenBefore, candidateAfter);
if numel(changes) ~= 40 || ...
        any(string({changes.parameter}) ~= "InitialCondition")
    error("lineagemerge:NonICChange", ...
        "Candidate changed something other than the exact 40 initial conditions.");
end
```

`readModelContract` must use `find_system(..., "LookUnderMasks", "all", "FollowLinks", "on")`, record sorted relative block path/type and every dialog parameter, and close without saving. `compareContracts` normalizes only the root model name (`final_steady_24a` versus `candidate`); it must not ignore any other difference. Write `candidate_audit.json` with all 40 old/new expressions and fixed false promotion flags.

- [ ] **Step 4: Run GREEN and commit**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_steady53_lineage_merge_candidate.m'); assertSuccess(r)"
git add tests/create_steady53_lineage_merge_candidate.m \
  tests/test_create_steady53_lineage_merge_candidate.m
git commit -m "构建稳态谱系初值组合候选"
```

Expected: MATLAB test passes; zero simulation calls; formal hashes unchanged.

### Task 2: Run the candidate exactly once for 500 s

**Files:**
- Create: `tests/run_steady53_lineage_merge_diagnostic.m`
- Modify: `tests/test_create_steady53_lineage_merge_candidate.m`

- [ ] **Step 1: Add a failing runner-hook test**

Require a test hook that injects a fake `run_steady53_case` result and verifies the runner's one-call/data-shape contract without MATLAB integration:

```matlab
fake = syntheticRunResult();
status = run_steady53_lineage_merge_diagnostic( ...
    candidateDir, repoRoot, @(varargin) fake);
verifyEqual(testCase, status.run_steady53_case_call_count, 1);
verifyEqual(testCase, status.retry_count, 0);
verifyEqual(testCase, status.final_time_s, 500);
verifyTrue(testCase, status.raw_result_present);
verifyTrue(testCase, status.curves_present);
verifyEqual(testCase, readmatrix(status.curves_path, ...
    "NumHeaderLines", 1, "OutputType", "double"), ...
    expectedSixColumnCurves(fake), "AbsTol", 0);
```

The six columns are exactly `time_s,reactor_W,turbine_W,compressor_W,electrical_paper_eta_W,electrical_historical_eta_W`, with electrical definitions `0.98*(turbine-compressor)` and `0.96527*(turbine-compressor)`.

- [ ] **Step 2: Run RED**

Run the Task 1 MATLAB test command. Expected: missing runner failure and zero real simulation calls.

- [ ] **Step 3: Implement the runner**

Production mode must reject an existing `run/` directory, then execute exactly:

```matlab
runResult = run_steady53_case(candidatePath, 500, true);
callCount = 1;
```

Require `success=true`, `tFinal_s=500`, finite equal-length `t`, reactor, turbine, and compressor vectors. Save `raw_result.mat`, `curves.csv`, and `run_status.json` using new files only. Record `callCount=1`, `retry_count=0`, source/candidate hashes, error identity/report when unsuccessful, and keep all promotion flags false. Never call itself, loop, retry, or delete evidence after a failure.

- [ ] **Step 4: Run zero-simulation tests and commit**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "r=runtests('tests/test_create_steady53_lineage_merge_candidate.m'); assertSuccess(r)"
git add tests/run_steady53_lineage_merge_diagnostic.m \
  tests/test_create_steady53_lineage_merge_candidate.m
git commit -m "实现稳态谱系组合单次诊断"
```

Expected: fake-run tests pass and no real simulation marker appears.

### Task 3: Analyze against fixed Figure 5.19 evidence and execute

**Files:**
- Create: `tests/analyze_steady53_lineage_merge.py`
- Create: `tests/test_analyze_steady53_lineage_merge.py`
- Runtime only: `tmp/steady53_lineage_merge_20260901_A/**`

- [ ] **Step 1: Write failing pure-Python analysis tests**

Use synthetic curves to require the four fixed paper direction sequences and result enums:

```python
class LineageMergeAnalysisTests(unittest.TestCase):
    def test_all_four_directions_support_the_hypothesis(self):
        result = analyze_arrays(times, matching_curves, paper_points)
        self.assertEqual(
            result["result_enum"], "lineage_initial_state_split_supported"
        )
        self.assertFalse(result["paper_reproduced"])
        self.assertFalse(result["author_initial_state_identified"])
        self.assertFalse(result["formal_promotion"])

    def test_partial_and_failed_directions_are_not_promoted(self):
        self.assertEqual(
            analyze_arrays(times, partial_curves, paper_points)["result_enum"],
            "lineage_initial_state_split_partially_supported",
        )
        self.assertEqual(
            analyze_arrays(times, flat_curves, paper_points)["result_enum"],
            "lineage_initial_state_split_not_supported",
        )
```

Also reject wrong columns, nonfinite values, nonmonotonic time, final time other than 500, changed paper-point hash, missing audit, wrong model hashes, changed count other than 40, and call count other than one.

- [ ] **Step 2: Run RED**

```bash
python3 -m unittest -v tests.test_analyze_steady53_lineage_merge
python3 -O -m unittest -v tests.test_analyze_steady53_lineage_merge
```

Expected: missing analyzer failure in both modes.

- [ ] **Step 3: Implement the offline analyzer**

Reuse the existing audited Figure 5.19 machinery from `tests/analyze_fig519_ihx_r2_hexe_shift.py` and `tests/fig519_ihx_r2_hexe_contract.py`: import `direction_sequence`, `PAPER_POINTS_SHA256`, `PAPER_DIRECTIONS`, and `NONFLAT_THRESHOLDS_W`; do not copy or change their values. The new analyzer may expose a small public wrapper for reading the fixed paper CSV, but it must verify the imported SHA-256 before parsing. Produce `analysis.json`, `comparison.csv`, and `figure5_19_lineage_merge.png`. Report for each panel: start/end, peak/valley and times, peak-to-peak, direction sequence, nonflat result, RMSE, max absolute error, and baseline-to-candidate RMSE change.

Classify mechanically:

```python
passed = sum(direction_ok[name] and nonflat_ok[name] for name in PANEL_NAMES)
if passed == 4:
    result_enum = "lineage_initial_state_split_supported"
elif passed > 0:
    result_enum = "lineage_initial_state_split_partially_supported"
else:
    result_enum = "lineage_initial_state_split_not_supported"
```

Keep all three promotion flags false regardless of RMSE.

- [ ] **Step 4: Run GREEN**

Run both Python commands from Step 2. Expected: all pass under normal and optimized Python.

- [ ] **Step 5: Create the candidate and execute one 500 s run**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  "repoRoot=string(pwd); addpath(fullfile(repoRoot,'tests'),fullfile(repoRoot,'tests','steady53')); runDir=fullfile(repoRoot,'tmp','steady53_lineage_merge_20260901_A'); create_steady53_lineage_merge_candidate(runDir,repoRoot); run_steady53_lineage_merge_diagnostic(runDir,repoRoot)"
python3 tests/analyze_steady53_lineage_merge.py \
  --run-dir tmp/steady53_lineage_merge_20260901_A
```

Expected: one `run_steady53_case` call, final time 500 s, analysis artifacts produced, and no formal-file changes.

- [ ] **Step 6: Verify and commit code plus truthful result summary**

```bash
python3 -m unittest -v tests.test_analyze_steady53_lineage_merge
python3 -O -m unittest -v tests.test_analyze_steady53_lineage_merge
git diff --check
git diff --name-only -- \
  final_steady_24a.slx final_dynamic_24a.slx '*.mat' \
  HeXe_property_simulink.m Lithium_property_simulink.m
git add tests/create_steady53_lineage_merge_candidate.m \
  tests/test_create_steady53_lineage_merge_candidate.m \
  tests/run_steady53_lineage_merge_diagnostic.m \
  tests/analyze_steady53_lineage_merge.py \
  tests/test_analyze_steady53_lineage_merge.py
git commit -m "分析稳态谱系初值组合诊断"
```

Expected: tests pass, formal diff is empty, and the report states the actual enum without claiming paper reproduction.
