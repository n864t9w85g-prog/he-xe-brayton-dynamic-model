# Rotating Map Controlled Candidate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine, with traceable C0–C3 experiments, whether the recovered paper-style compressor/turbine lookup candidate materially improves `final_steady_24a.slx` against Xu Chapter 5 steady-state evidence without changing the formal model.

**Architecture:** Preserve the recovered sources under provenance, audit all maps offline, convert candidate axes into the exact coordinates already consumed by the model, and apply table-variable changes only to API-created temporary copies. Run the fixed 500 s gate for C0–C3; run one 14000 s case only if the written gate selects it.

**Tech Stack:** MATLAB R2025a, Simulink official API, MATLAB unit tests, existing `tests/steady53/run_steady53_case.m`, JSON/CSV artifacts, Git and SHA256.

---

## File structure

- Create `data/provenance/rotating_machinery/recovered_20260902/README.md`: evidence classification and limitations.
- Create `data/provenance/rotating_machinery/recovered_20260902/manifest.json`: hashes and immutable source metadata.
- Copy binary sources into `data/provenance/rotating_machinery/recovered_20260902/source/`: the recovered turbine archive/document and the two recovered lookup packages.
- Create `tests/test_rotating_map_recovery_manifest.py`: verifies every preserved source byte-for-byte.
- Create `tests/audit_rotating_map_candidates.m`: produces the Gate 1 numerical audit and plots.
- Create `tests/test_audit_rotating_map_candidates.m`: unit tests the audit contract and hard failures.
- Create `tests/build_rotating_map_candidate_bundles.m`: produces C0–C3 runtime bundles under `tmp/` without altering surfaces.
- Create `tests/test_build_rotating_map_candidate_bundles.m`: proves orientation, unit conversion, and design-point invariance.
- Create `tests/create_rotating_map_candidate_models.m`: copies the steady model and applies only lookup-variable expressions through Simulink API.
- Create `tests/test_create_rotating_map_candidate_models.m`: checks hashes, changed block parameters, and protected settings.
- Create `tests/run_rotating_map_candidate_batch.m`: runs C0–C3 at 500 s and the selected winner at 14000 s.
- Create `tests/test_run_rotating_map_candidate_batch.m`: tests stop-time and gate logic with injected run results.
- Create `tests/analyze_rotating_map_candidate_batch.py`: calculates Table 5.2 error metrics and emits the selection decision.
- Create `tests/test_analyze_rotating_map_candidate_batch.py`: tests the 20% median-error rule and no-regression rule.
- Create `docs/steady53_candidate_comparison.md`: final evidence-backed result; do not create it until real outputs exist.

### Task 1: Preserve recovered evidence

**Files:**
- Create: `data/provenance/rotating_machinery/recovered_20260902/README.md`
- Create: `data/provenance/rotating_machinery/recovered_20260902/manifest.json`
- Create: `data/provenance/rotating_machinery/recovered_20260902/source/*`
- Test: `tests/test_rotating_map_recovery_manifest.py`

- [ ] **Step 1: Write the failing manifest test**

```python
import hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROV = ROOT / "data/provenance/rotating_machinery/recovered_20260902"

def test_recovered_sources_match_manifest():
    manifest = json.loads((PROV / "manifest.json").read_text())
    assert manifest["schema"] == "rotating_map_recovery_v1"
    assert len(manifest["files"]) == 5
    for item in manifest["files"]:
        path = PROV / item["repository_path"]
        assert path.is_file()
        assert path.stat().st_size == item["size_bytes"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"]
        assert item["evidence_level"] in {"warning", "negative"}
        assert item["author_original"] is False
```

- [ ] **Step 2: Run the test and confirm the missing-manifest failure**

Run: `python3 -m pytest tests/test_rotating_map_recovery_manifest.py -q`

Expected: FAIL because `manifest.json` does not exist.

- [ ] **Step 3: Preserve the five immutable sources**

Create `source/` and copy these files without transforming them:

```text
透平机程序.7z
透平建模思路(1).docx
HeXe40_Xu2022_v2_stage9.zip
Xu2022_PaperStyle_Equivalent_Lookup.mat
FULL_PROVENANCE.md
```

Use their verified source hashes:

```text
透平机程序.7z                                d0460bcbdb004dcdb447c37c5cf59e230511d1591af7d51e939f944545c35a98
透平建模思路(1).docx                         0589e0f16107bdcd10f263b986aaea9607118ea31786b2daa580c0329c749f3b
HeXe40_Xu2022_v2_stage9.zip                  eaf3c5d88a5b5ca15d1877dfcffee57c81d11c19159e6645dcf1e03ac44b0468
Xu2022_PaperStyle_Equivalent_Lookup.mat      f482a6a7388986727e09dd8b01b7614e1274952777c0b105f29827b96550eda6
FULL_PROVENANCE.md                           83d3823f0b2db307a11e5a55b0d1459d43e9cdd439578594ebe88fab1a6eed76
```

`manifest.json` must record `original_path`, `repository_path`, `size_bytes`, `mtime_local`, `sha256`, `role`, `evidence_level`, `author_original=false`, and `limitations` for every entry.

- [ ] **Step 4: Add the evidence classification README**

State explicitly:

```text
✅ Recovery identity is proven by SHA256.
⚠️ The D-8063 package is a NASA-geometry substitute calibrated with PD/XK and contains a wrong 4.572 kg/s design-flow assertion.
⚠️ The paper-style package is a Gallo-shape/Xu-anchor reconstruction with a test-only 100%-110% extrapolation.
❌ None of these files is Xu's author-original lookup matrix.
```

- [ ] **Step 5: Run the manifest test**

Run: `python3 -m pytest tests/test_rotating_map_recovery_manifest.py -q`

Expected: `1 passed`.

- [ ] **Step 6: Commit only the provenance package and its test**

```bash
git add data/provenance/rotating_machinery/recovered_20260902 tests/test_rotating_map_recovery_manifest.py
git commit -m "data: preserve recovered rotating-map evidence"
```

### Task 2: Implement the Gate 1 offline audit

**Files:**
- Create: `tests/audit_rotating_map_candidates.m`
- Test: `tests/test_audit_rotating_map_candidates.m`

- [ ] **Step 1: Write the failing MATLAB unit test**

The test must call:

```matlab
out = audit_rotating_map_candidates(repoRoot, outputDir);
verifyEqual(testCase, string(out.schema), "rotating_map_offline_audit_v1");
verifyTrue(testCase, out.current.compressor.pr_all_rows_strictly_decreasing);
verifyTrue(testCase, out.candidate.compressor.design_has_interior_pr_peak);
verifyLessThanOrEqual(testCase, out.candidate.design.max_relative_error, 0.05);
verifyTrue(testCase, out.candidate.domain.covers_all_required_speeds);
verifyTrue(testCase, isfile(fullfile(outputDir,"offline_map_audit.json")));
verifyTrue(testCase, isfile(fullfile(outputDir,"offline_map_summary.csv")));
verifyTrue(testCase, isfile(fullfile(outputDir,"offline_map_comparison.png")));
```

Add a synthetic invalid MAT fixture and require identifier `rotatingMap:InvalidCandidate` for NaN, wrong orientation, or efficiency outside `[0,1]`.

- [ ] **Step 2: Run the unit test and verify it fails**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); r=runtests('tests/test_audit_rotating_map_candidates.m'); assertSuccess(r)"
```

Expected: FAIL because `audit_rotating_map_candidates` is undefined.

- [ ] **Step 3: Implement the audit function**

Use fixed thesis-derived targets:

```matlab
target.N_rpm = 55090;
target.mdot_kg_s = 12.02230808;
target.PRc = 1.551/0.658;
target.PRt = 1.539/0.676;
target.etaC = 0.842737535;
target.etaT = 0.845605188;
target.required_speed_rpm = [22036 50610 55090 57844.5 59655];
```

Load current `hexe_compressor_lookup.mat`, `turbine_table1.mat`, `turbine_table2.mat` and the preserved `Xu2022_PaperStyle_Equivalent_Lookup.mat`. Validate exact field names and dimensions. Interpolate design values with `interp2`; calculate relative errors, finite/range checks, speed coverage, and interior-peak indices. Do not alter or smooth any source array.

Create one comparison figure with four tiles: compressor PR, compressor efficiency, turbine flow, turbine efficiency. Plot current and candidate design-speed lines in common physical coordinates and mark the Table 5.2 target.

- [ ] **Step 4: Run the audit unit test**

Run the Task 2 Step 2 command.

Expected: all tests PASS and `ROTATING_MAP_GATE1=PASS` appears once.

- [ ] **Step 5: Run the real Gate 1 audit**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); audit_rotating_map_candidates(pwd,fullfile(pwd,'tmp','rotating_map_candidate_A_20260902','gate1'))"
```

Expected: either an explicit hard-failure identifier or complete JSON/CSV/PNG outputs. Do not proceed on hard failure.

- [ ] **Step 6: Commit the tested audit code**

```bash
git add tests/audit_rotating_map_candidates.m tests/test_audit_rotating_map_candidates.m
git commit -m "test: audit rotating-map candidate evidence"
```

### Task 3: Build invariant candidate bundles

**Files:**
- Create: `tests/build_rotating_map_candidate_bundles.m`
- Test: `tests/test_build_rotating_map_candidate_bundles.m`

- [ ] **Step 1: Write the failing bundle test**

Require four directories `C0`–`C3`, each with `compressor.mat`, `turbine1.mat`, `turbine2.mat`, and one shared `candidate_mapping.json`. Assert:

```matlab
verifyEqual(testCase, C1.speed_bp, candidate.N_bp/55090, "AbsTol", 1e-12);
verifyEqual(testCase, C1.m_ratio_bp, candidate.mC_bp/12.04, "AbsTol", 1e-12);
verifyEqual(testCase, C1.PR_table, candidate.PRc_tbl);
verifyEqual(testCase, C1.eta_table, candidate.etac_tbl);
verifyEqual(testCase, C2.bp_er, candidate.PRt_bp);
verifyEqual(testCase, C2.bp_speed, candidate.N_bp);
verifyEqual(testCase, C2.table_mf, candidate.mT_tbl.');
verifyEqual(testCase, C2.bp_mf, candidate.mT_bp);
verifyEqual(testCase, C2.table_eff, candidate.etat_tbl.');
```

Also interpolate each original and converted table at three interior points and require absolute residual `<1e-12`.

- [ ] **Step 2: Verify the missing-function failure**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); r=runtests('tests/test_build_rotating_map_candidate_bundles.m'); assertSuccess(r)"
```

Expected: FAIL because the builder is undefined.

- [ ] **Step 3: Implement C0–C3 bundle creation**

Use these exact mappings:

```text
Candidate compressor:
  speed_bp   = N_bp / 55090
  m_ratio_bp = mC_bp / 12.04
  PR_table   = PRc_tbl
  eta_table  = etac_tbl

Candidate turbine flow:
  bp_er      = PRt_bp
  bp_speed   = N_bp
  table_mf   = transpose(mT_tbl)

Candidate turbine efficiency:
  bp_mf      = mT_bp
  bp_speed   = N_bp
  table_eff  = transpose(etat_tbl)
```

C0 uses current tables; C1 changes only compressor; C2 changes only both turbine tables; C3 changes all three. Record source hashes, array hashes, conversions, dimensions, and case membership in `candidate_mapping.json`.

- [ ] **Step 4: Run the bundle test and real builder**

Run the Task 3 Step 2 command, then:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); build_rotating_map_candidate_bundles(pwd,fullfile(pwd,'tmp','rotating_map_candidate_A_20260902','bundles'))"
```

Expected: tests PASS; four bundles and one mapping JSON exist.

- [ ] **Step 5: Commit the tested builder**

```bash
git add tests/build_rotating_map_candidate_bundles.m tests/test_build_rotating_map_candidate_bundles.m
git commit -m "test: build invariant rotating-map bundles"
```

### Task 4: Create API-only temporary model cases

**Files:**
- Create: `tests/create_rotating_map_candidate_models.m`
- Test: `tests/test_create_rotating_map_candidate_models.m`

- [ ] **Step 1: Write the failing API-structure test**

The test must verify:

```matlab
models = create_rotating_map_candidate_models(repoRoot, runRoot);
verifyEqual(testCase, sort(string(fieldnames(models))), ["C0";"C1";"C2";"C3"]);
verifyEqual(testCase, hashFile(fullfile(repoRoot,"final_steady_24a.slx")), sourceHashBefore);
verifyEqual(testCase, protectedSolverTuple(models.C1), protectedSolverTuple(models.C0));
verifyEqual(testCase, changedLookupKinds(models.C1,models.C0), "compressor");
verifyEqual(testCase, changedLookupKinds(models.C2,models.C0), "turbine");
verifyEqual(testCase, changedLookupKinds(models.C3,models.C0), "compressor+turbine");
```

The test must also read the implementation source and reject `unzip`, XML writes, or direct archive editing.

- [ ] **Step 2: Verify the missing-function failure**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); r=runtests('tests/test_create_rotating_map_candidate_models.m'); assertSuccess(r)"
```

Expected: FAIL because the creator is undefined.

- [ ] **Step 3: Implement the temporary-copy creator**

For each case, copy `final_steady_24a.slx` to its own `tmp/.../C?/model/` directory, load the copy with `load_system`, and use `set_param` only on the three lookup blocks' table/breakpoint expressions so they refer to case-local variable names. Preserve solver, initial states, callbacks, topology, line handles, all non-lookup block parameters, and the source model hash. Save only the temporary copy.

Write `model_patch_manifest.json` with source/candidate hashes and an exact before/after parameter diff.

- [ ] **Step 4: Run the structure test**

Run the Task 4 Step 2 command.

Expected: all tests PASS and source SLX hash unchanged.

- [ ] **Step 5: Commit the tested model creator**

```bash
git add tests/create_rotating_map_candidate_models.m tests/test_create_rotating_map_candidate_models.m
git commit -m "test: create API-only rotating-map model cases"
```

### Task 5: Implement and execute the fixed 500 s gate

**Files:**
- Create: `tests/run_rotating_map_candidate_batch.m`
- Create: `tests/analyze_rotating_map_candidate_batch.py`
- Test: `tests/test_run_rotating_map_candidate_batch.m`
- Test: `tests/test_analyze_rotating_map_candidate_batch.py`

- [ ] **Step 1: Write failing tests for run limits and selection**

MATLAB runner tests must require:

```matlab
verifyWarningFree(testCase,@() hooks.validateStopTime(500));
verifyWarningFree(testCase,@() hooks.validateStopTime(14000));
verifyError(testCase,@() hooks.validateStopTime(501),"rotatingMap:UnsupportedStopTime");
verifyEqual(testCase,hooks.caseOrder,["C0" "C1" "C2" "C3"]);
verifyEqual(testCase,hooks.runCallCountFor500Batch,4);
```

Python analyzer tests must construct synthetic C0/C1 results and verify that a candidate is selected only when median normalized Table 5.2 error falls by at least 20%, no formerly passing key signal exceeds 5%, the run reaches the requested stop time, and lookup assertions remain clear.

- [ ] **Step 2: Run both tests and verify they fail**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); r=runtests('tests/test_run_rotating_map_candidate_batch.m'); assertSuccess(r)"
python3 -m pytest tests/test_analyze_rotating_map_candidate_batch.py -q
```

Expected: FAIL because the runner/analyzer do not exist.

- [ ] **Step 3: Implement the runner**

Reuse `tests/steady53/run_steady53_case.m`. Before each run, add only the case-local model, bundle, and steady53 helper directories to the path; load case-local variables; reset property-warning state; and invoke exactly once:

```matlab
result = run_steady53_case(candidateModelPath, stopTime, true);
```

Persist `run_status.json`, the returned MAT result, signal CSVs, MATLAB log, lookup-domain audit, elapsed time, stop reason, and final valid time. A failed case must not abort the remaining 500 s cases.

- [ ] **Step 4: Implement the analyzer**

Use the fixed Table 5.2 signals already exposed by `run_steady53_case`. For each case, calculate normalized absolute error, median error, ±5% pass/fail, final valid time, and assertion status. Emit `gate2_decision.json` with `eligible_for_14000`, `winner`, and per-rule evidence.

- [ ] **Step 5: Run the unit tests**

Run the Task 5 Step 2 commands.

Expected: all tests PASS.

- [ ] **Step 6: Execute C0–C3 exactly once at 500 s**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests','tests/steady53'); run_rotating_map_candidate_batch(pwd,fullfile(pwd,'tmp','rotating_map_candidate_A_20260902'),500)"
python3 tests/analyze_rotating_map_candidate_batch.py --run-root tmp/rotating_map_candidate_A_20260902 --stop-time 500
```

Expected: four run-status records and one deterministic Gate 2 decision. Do not rerun a completed case merely to improve its outcome.

- [ ] **Step 7: Commit only reusable code and small test fixtures**

```bash
git add tests/run_rotating_map_candidate_batch.m tests/test_run_rotating_map_candidate_batch.m tests/analyze_rotating_map_candidate_batch.py tests/test_analyze_rotating_map_candidate_batch.py
git commit -m "test: gate rotating-map candidates at 500 seconds"
```

### Task 6: Enforce the 14000 s gate and write the evidence report

**Files:**
- Create: `docs/steady53_candidate_comparison.md`
- Modify: `docs/2026-09-02-rotating-machinery-map-rootcause.md`

- [ ] **Step 1: Read `gate2_decision.json` without overriding it**

If `eligible_for_14000=false`, skip directly to Step 4 and report all candidate failures. Do not create another candidate.

- [ ] **Step 2: Run exactly one eligible winner at 14000 s**

Run only when Gate 2 names one winner:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests','tests/steady53'); run_rotating_map_candidate_batch(pwd,fullfile(pwd,'tmp','rotating_map_candidate_A_20260902'),14000)"
python3 tests/analyze_rotating_map_candidate_batch.py --run-root tmp/rotating_map_candidate_A_20260902 --stop-time 14000
```

Expected: one 14000 s result for the selected case; no other case is run.

- [ ] **Step 3: Verify the long-run evidence**

Require final time 14000 s, finite signals, no lookup assertion, unchanged source SLX/MAT hashes, all available Table 5.2 comparisons, and the Chapter 5.3 steady-curve metrics. Record failures without modifying the gate.

- [ ] **Step 4: Write the comparison report**

The report must contain:

```text
- C0–C3 exact source identities and changed variables
- Gate 1 and Gate 2 results
- 14000 s result, or the explicit reason it was forbidden
- Table 5.2 per-signal error and ±5% result
- current/candidate/paper curve-shape comparison
- ✅/⚠️/❓/❌ evidence labels
- one of the three conclusion phrases allowed by the design spec
- explicit statement that no author-original lookup was recovered
```

- [ ] **Step 5: Run final verification**

Run:

```bash
python3 -m pytest tests/test_rotating_map_recovery_manifest.py tests/test_analyze_rotating_map_candidate_batch.py -q
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); r=runtests({'tests/test_audit_rotating_map_candidates.m','tests/test_build_rotating_map_candidate_bundles.m','tests/test_create_rotating_map_candidate_models.m','tests/test_run_rotating_map_candidate_batch.m'}); assertSuccess(r)"
git diff --check
git status --short
```

Expected: all new tests PASS; `git diff --check` is empty; formal `final_steady_24a.slx`, `final_dynamic_24a.slx`, root `.mat`, and `HeXe_property_simulink.m` hashes are unchanged.

- [ ] **Step 6: Commit the result report**

```bash
git add docs/steady53_candidate_comparison.md docs/2026-09-02-rotating-machinery-map-rootcause.md
git commit -m "docs: report rotating-map candidate gate results"
```

## Plan self-review

- Spec coverage: Gate 0 is Task 1; Gate 1 is Task 2; axis-only mapping is Task 3; API-only temporary copies are Task 4; C0–C3 500 s runs and the 20% rule are Task 5; one gated 14000 s run and final evidence language are Task 6.
- Scope: compressor and turbine remain in one plan because C1/C2 isolate them and C3 tests their required coupled closure; no other physical subsystem is changed.
- Type consistency: C0–C3 names, bundle field names, output filenames, and gate flags are identical across all tasks.
- No implementation step permits parameter fitting, surface smoothing, extra cases, formal-model writes, or automatic promotion.
