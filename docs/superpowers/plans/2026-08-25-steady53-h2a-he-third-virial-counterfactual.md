# Steady 5.3 Task 8 H2a He Third-Virial Counterfactual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a strictly read-only H2a counterfactual that changes only the He pure third-Virial branch to zero, then compares baseline and counterfactual `cp/cv/gamma` at the fixed exception point, over the approved fixed-pressure neighborhood, and along the complete H1a linear path.

**Architecture:** Add a new analysis-only H2a function and tests without modifying the approved H2 analyzer or any formal asset. The H2a analyzer first reproduces the locked H2 baseline, then evaluates the approved counterfactual through the same EOS and thermodynamic identities. A separate fail-closed publisher writes two self-contained files through same-parent staging and a no-overwrite directory move.

**Tech Stack:** MATLAB R2025a, MATLAB Unit Test Framework, tables/structs, `roots`, `fzero`, SHA-256 through Java, Java NIO atomic directory publication, Git.

---

## Fixed Scope and Identities

The implementation must preserve these paths and hashes:

```text
runId = run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3
exceptionT_K = 992.38742737169468
exceptionP_Pa = 1007910.8613125964

formal model = 5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d
property source = 2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2
compressor MAT = f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579
radiator MAT = 3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304
turbine MAT 1 = 10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d
turbine MAT 2 = cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33
fixed input MAT = 4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b
thesis PDF = 983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a
archive peeled commit = 8f625c268c35a95c18a626305c1aa6a79ae2ace7
approved H2 CSV = b2998bdafd96cdd49d9fa4ff621dc586add229dd525a9d0d79a7c22fc71ee9d6
approved H2 TXT = 1fa29cebd816d891fecddfa8c54863d1f672f44a8793cb6e32cf3084241f9799
```

The only counterfactual assignment is:

```matlab
counterfactual.C111 = 0.0;
counterfactual.dC111_dT = 0.0;
counterfactual.d2C111_dT2 = 0.0;
counterfactual.C112 = 0.0;
counterfactual.C122 = 0.0;
counterfactual.dC112_dT = 0.0;
counterfactual.dC122_dT = 0.0;
counterfactual.d2C112_dT2 = 0.0;
counterfactual.d2C122_dT2 = 0.0;
counterfactual.C = x_Xe^3*baseline.C222;
counterfactual.dC_dT = x_Xe^3*baseline.dC222_dT;
counterfactual.d2C_dT2 = x_Xe^3*baseline.d2C222_dT2;
```

Do not run or load an SLX. Do not run the complete `tests/steady53` suite. Do not modify `HeXe_property_simulink.m`, the approved H2 analyzer/publisher/tests, either approved H2 output, any MAT/PDF, solver setting, acceptance criterion, H1a integrator, or formal model.

---

### Task 1: Lock the H2a Read-Only Contract

**Files:**

- Create: `tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m`
- Create: `tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m`

- [ ] **Step 1: Write the missing-analyzer and immutable-input tests**

Create a function-based test file whose setup adds only `tests/steady53` and records the protected hashes. The first contract test must require these fields:

```matlab
required = ["inputs" "sourceAudit" "approval" "baselineParity" ...
    "exceptionPoint" "fixedPressureSweep" "h1aPathSweep" ...
    "counterfactualVerdict"];
analysis = analyze_task8_h2a_he_third_virial_counterfactual();
for name = required
    verifyTrue(testCase, isfield(analysis, name), ...
        "Missing H2a field: " + name);
end
verifyEqual(testCase, analysis.approval.variant, ...
    "ignoreHePureThirdVirialBeforeCurrentMixingRule");
verifyFalse(testCase, analysis.approval.authorizesRepair);
verifyFalse(testCase, analysis.approval.loadsOrSimulatesSlx);
```

Add static source tests that reject model APIs and all writer APIs in the analyzer:

```matlab
source = fileread(fullfile(testCase.TestData.root, "tests", ...
    "steady53", "analyze_task8_h2a_he_third_virial_counterfactual.m"));
forbidden = ["set_param" "sim" "load_system" "save_system" ...
    "open_system" "bdclose" "writetable" "writecell" ...
    "writematrix" "fopen" "copyfile" "movefile"];
for token = forbidden
    verifyEmpty(testCase, regexp(source, ...
        "(?<![A-Za-z0-9_])" + token + "\\s*\\(", "once"));
end
```

Add fail-closed test-only options for every protected hash and the exception point. Each mutation must expect a dedicated `steady53:H2a...Mismatch` identifier and must not create an H2a output directory.

- [ ] **Step 2: Run the exact RED test**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'r=runtests("tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m"); disp(r); assert(any([r.Failed]));'
```

Expected: failure because `analyze_task8_h2a_he_third_virial_counterfactual` does not exist. Record the exact pass/fail/incomplete counts and exact failure names in the experiment log before implementing.

- [ ] **Step 3: Implement the minimal read-only analyzer contract**

Create the analyzer with this public shape:

```matlab
function analysis = analyze_task8_h2a_he_third_virial_counterfactual(options)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = defaultConfig(root);
if nargin > 0
    config = applyTestOnlyOptions(config, options);
end
validateFixedInputs(config);
protectedBefore = protectedHashes(root);
h2 = analyze_task8_h2_hexe_property_readonly();
protectedAfter = protectedHashes(root);
if ~isequaln(protectedBefore, protectedAfter)
    error("steady53:H2aProtectedAssetChanged", ...
        "A protected asset changed during H2a analysis.");
end

analysis = struct( ...
    "inputs", fixedInputIdentity(config), ...
    "sourceAudit", sourceAudit(config, protectedBefore, protectedAfter), ...
    "approval", approvalContract(), ...
    "baselineParity", struct("status", "notComputedInTask1"), ...
    "exceptionPoint", struct("status", "notComputedInTask1"), ...
    "fixedPressureSweep", struct("status", "notComputedInTask1"), ...
    "h1aPathSweep", struct("status", "notComputedInTask1"), ...
    "counterfactualVerdict", struct("status", "notComputedInTask1"));
end
```

`protectedHashes` must include the eight formal/input files, the two approved H2 output files, and the archive peeled commit. H2a may call the H2 analyzer read-only but may not change it.

- [ ] **Step 4: Run GREEN and static checks**

Run the focused test. Then run:

```matlab
issues = checkcode( ...
    'tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m', ...
    '-id');
assert(isempty(issues));
```

Expected: all Task 1 tests pass; `checkcode` reports zero issues; protected hashes match before and after.

- [ ] **Step 5: Commit Task 1**

```bash
git add tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m \
        tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m
git diff --cached --check
git commit -m "test: lock approved H2a read-only contract"
```

---

### Task 2: Implement the Dual-Branch Point Evaluator and Baseline Parity

**Files:**

- Modify: `tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m`
- Modify: `tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m`

- [ ] **Step 1: Write RED tests for baseline parity and the single variable**

Add tests that assert the internal baseline reproduces the approved H2 exception-point data and that counterfactual changes only the third-Virial branch:

```matlab
h2 = analyze_task8_h2_hexe_property_readonly();
h2a = analyze_task8_h2a_he_third_virial_counterfactual();

verifyTrue(testCase, h2a.baselineParity.allSatisfied);
verifyEqual(testCase, h2a.exceptionPoint.baseline.cpMolar, ...
    h2.thermoIdentity.eq2_15.analyticCpMolar, "AbsTol", 1e-10);
verifyEqual(testCase, h2a.exceptionPoint.baseline.cvMolar, ...
    h2.thermoIdentity.eq2_17.analyticCvMolar, "AbsTol", 1e-10);
verifyEqual(testCase, h2a.exceptionPoint.baseline.gamma, ...
    h2.thermoIdentity.gamma.analytic, "AbsTol", 1e-13);

cf = h2a.exceptionPoint.counterfactual;
verifyEqual(testCase, [cf.C111 cf.C112 cf.C122], [0 0 0]);
verifyEqual(testCase, [cf.dC111_dT cf.dC112_dT cf.dC122_dT], [0 0 0]);
verifyEqual(testCase, ...
    [cf.d2C111_dT2 cf.d2C112_dT2 cf.d2C122_dT2], [0 0 0]);
verifyEqual(testCase, cf.C, cf.xXe^3*cf.C222, "AbsTol", 1e-30);
verifyEqual(testCase, cf.dC_dT, cf.xXe^3*cf.dC222_dT, ...
    "AbsTol", 1e-30);
verifyEqual(testCase, cf.d2C_dT2, cf.xXe^3*cf.d2C222_dT2, ...
    "AbsTol", 1e-30);
```

Add invariance tests for `B`, constants, EOS form, Newton initial value, clamp rule, tolerances, and input coordinates. Add a negative test-only mutation that changes one non-C quantity and requires `steady53:H2aSingleVariableViolation`.

- [ ] **Step 2: Run RED**

Run the focused analyzer test. Expected: new tests fail because Task 1 has only placeholders. Record exact counts and failure names.

- [ ] **Step 3: Implement a parameterized pure evaluator**

Use an internal enum-like string restricted to two values:

```matlab
function state = evaluatePoint(T_K, P_Pa, variant)
arguments
    T_K (1,1) double {mustBeFinite,mustBePositive}
    P_Pa (1,1) double {mustBeFinite,mustBePositive}
    variant (1,1) string {mustBeMember(variant, ...
        ["baseline","ignoreHePureThirdVirial"])}
end

coeff = evaluateCommonCoefficients(T_K);
if variant == "baseline"
    coeff = applyBaselineThirdVirial(coeff, T_K);
else
    coeff = applyIgnoredHeThirdVirial(coeff, T_K);
end
density = solveDensityExactlyAsBaseline(T_K, P_Pa, coeff);
thermal = evaluateCpCvGammaExactlyAsBaseline(T_K, coeff, density);
state = mergePointEvidence(T_K, P_Pa, variant, coeff, density, thermal);
end
```

Do not evaluate counterfactual derivatives with `C'/C`; assign the approved zero components directly, then compute mixture derivatives from Xe only. Keep the baseline derivative formula unchanged.

Return all cubic roots, scaled residuals, stability slopes, Newton iterations, raw/clamped roots, `cp/cv/gamma`, and the full contribution decomposition.

- [ ] **Step 4: Implement and enforce baseline parity**

Build a parity table with fields:

```text
name
h2Value
h2aBaselineValue
absoluteError
tolerance
pass
```

Include all quantities named in design section 5. Require all rows to pass before evaluating or returning counterfactual results:

```matlab
if ~all(parity.pass)
    error("steady53:H2aBaselineParityMismatch", ...
        "The H2a baseline does not reproduce approved H2 evidence.");
end
```

- [ ] **Step 5: Run GREEN and commit Task 2**

Run the analyzer tests twice in fresh MATLAB processes. Recheck protected hashes and `checkcode`, then commit:

```bash
git add tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m \
        tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m
git diff --cached --check
git commit -m "test: evaluate approved H2a point counterfactual"
```

---

### Task 3: Evaluate the Fixed-Pressure Domain and Complete H1a Path

**Files:**

- Modify: `tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m`
- Modify: `tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m`

- [ ] **Step 1: Write RED tests for both domains without assuming improvement**

Tests must require both branch names, exact ranges, complete quantities, finite coordinates, and explicit zero-boundary results. They must not assert that counterfactual `cp/cv/gamma` are positive.

```matlab
analysis = analyze_task8_h2a_he_third_virial_counterfactual();
for field = ["fixedPressureSweep" "h1aPathSweep"]
    sweep = analysis.(field);
    verifyEqual(testCase, sweep.status, "completed");
    verifyEqual(testCase, sort(sweep.branchNames), ...
        sort(["baseline" "counterfactual"]));
    verifyEqual(testCase, sweep.quantitiesSearched, ...
        ["cp=0"; "cv=0"; "gamma=1"; "dP/drho=0"]);
    for branchName = sweep.branchNames
        branch = sweep.(branchName);
        verifyTrue(testCase, all(isfinite(branch.stateTable.T_K)));
        verifyTrue(testCase, all(isfinite(branch.stateTable.P_Pa)));
        verifyTrue(testCase, branch.allCoordinatesAccountedFor);
    end
end
```

Add a test that confirms the counterfactual branch has no C111 fractional-power discontinuity:

```matlab
verifyEqual(testCase, ...
    analysis.fixedPressureSweep.counterfactual.c111Treatment, ...
    "identicallyZeroBeforeCurrentMixingRule");
verifyFalse(testCase, ...
    analysis.fixedPressureSweep.counterfactual.hasC111ZeroDerivativeDiscontinuity);
```

Add result-neutral tests: a synthetic internally valid analysis with nonphysical counterfactual values must still satisfy result completeness, while missing states or silently skipped coordinates must fail.

- [ ] **Step 2: Run RED**

Expected: failures because both sweep fields remain placeholders. Record exact counts and names.

- [ ] **Step 3: Implement generic adaptive scanning**

Use the same H2 local fixed-pressure range and H1a path endpoints. For each branch and path:

1. evaluate a fixed coarse grid;
2. add adaptive coordinates around every non-finite point or sign transition;
3. split all pole/discontinuity brackets before root solving;
4. refine ordinary roots with `fzero` and record bracket/residual/one-sided values;
5. classify `gamma` poles at `cv=0` separately from `gamma=1` roots;
6. record zero roots as an explicit searched-and-not-found result;
7. calculate continuous intervals where `cp<=0`, `cv<=0`, or `gamma<=1`;
8. record extrema with `coordinate/T/P/value`;
9. record stable positive real root count at every adaptive state.

Do not hard-code the H2a counterfactual boundary counts. Use this result schema:

```matlab
branch = struct( ...
    "name", variant, ...
    "status", "completed", ...
    "stateTable", stateTable, ...
    "boundaries", boundaryTable, ...
    "boundaryCountByQuantity", countTable, ...
    "nonphysicalIntervals", intervalTable, ...
    "extrema", extremaTable, ...
    "invalidStates", invalidStateTable, ...
    "allCoordinatesAccountedFor", true);
```

Each top-level sweep must wrap those branch structures consistently:

```matlab
sweep = struct( ...
    "status", "completed", ...
    "quantitiesSearched", quantities, ...
    "branchNames", ["baseline" "counterfactual"], ...
    "baseline", baselineBranch, ...
    "counterfactual", counterfactualBranch);
```

The baseline branch must reproduce the four approved H2 `cp/cv` boundaries within the same tolerances. The counterfactual branch is accepted whether its counts are zero or nonzero, provided every search and state is accounted for.

- [ ] **Step 4: Run GREEN, inspect numerical results, and commit Task 3**

Run focused tests and print a compact diagnostic table for human inspection. Do not create formal H2a output yet. Recheck analyzer `checkcode`, protected hashes, and that the approved H2 files are byte-identical. Commit:

```bash
git add tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m \
        tests/steady53/analyze_task8_h2a_he_third_virial_counterfactual.m
git diff --cached --check
git commit -m "test: map approved H2a property domains"
```

---

### Task 4: Publish Self-Contained H2a Evidence

**Files:**

- Create: `tests/steady53/test_publish_task8_h2a_evidence.m`
- Create: `tests/steady53/publish_task8_h2a_evidence.m`
- Create after all tests pass: `tmp/steady53/task8_root_cause/h2a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2a_counterfactual_diagnostics.csv`
- Create after all tests pass: `tmp/steady53/task8_root_cause/h2a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2a_summary.txt`

- [ ] **Step 1: Write publisher RED tests**

Require exact output names and a complete self-contained payload. Add independent single-mutation cases for:

- missing baseline parity row;
- baseline parity false;
- wrong variant name;
- nonzero `C111`, `C112`, or `C122` in counterfactual;
- changed common B/EOS/root-strategy identity;
- missing path quantity search;
- empty or incomplete state tables;
- unaccounted non-finite state;
- wrong protected hash or archive commit;
- `authorizesRepair=true`;
- existing target directory;
- target race with sentinel;
- controlled failure after CSV but before summary.

Each case must start from a real valid analysis and mutate exactly one field. Expect `steady53:H2aInvalidEvidence` before staging for evidence failures, and dedicated no-overwrite/publication errors for filesystem cases.

- [ ] **Step 2: Run publisher RED**

Expected: failure because the publisher does not exist. Record exact counts.

- [ ] **Step 3: Implement fail-closed evidence validation**

Validate all identities, baseline parity, the exact Scheme A values, path coverage, evidence grades, and result-neutral status before creating staging. In particular, do not write logic equivalent to:

```matlab
assert(counterfactual.cpMolar > 0)
assert(counterfactual.cvMolar > 0)
assert(counterfactual.gamma > 1)
```

Those are report fields, not publication gates.

- [ ] **Step 4: Implement transactional publication**

Follow the already-tested H2 publication pattern:

```matlab
staging = createUniqueSameParentStaging(outputDir);
cleanup = onCleanup(@() cleanupOwnedStaging(staging));
writeCsvIntoStaging(staging, analysis);
writeSummaryIntoStaging(staging, analysis);
verifyExpectedFilesAndHashes(staging);
moveDirectoryWithoutReplacement(staging, outputDir);
verifyExpectedFilesAndHashes(outputDir);
clear cleanup
```

The publisher may write only under an explicit test-only directory during tests or the one fixed H2a directory during formal publication.

- [ ] **Step 5: Run GREEN and publish the fixed evidence once**

Run analyzer and publisher tests. Only after GREEN, invoke:

```matlab
analysis = analyze_task8_h2a_he_third_virial_counterfactual();
publication = publish_task8_h2a_evidence(analysis);
disp(publication)
```

Verify the fixed directory contains exactly two files, no staging remains, and returned hashes match `shasum -a 256`.

- [ ] **Step 6: Commit Task 4**

```bash
git add tests/steady53/test_publish_task8_h2a_evidence.m \
        tests/steady53/publish_task8_h2a_evidence.m
git add -f tmp/steady53/task8_root_cause/h2a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3
git diff --cached --check
git commit -m "test: publish approved H2a counterfactual evidence"
```

---

### Task 5: Record Results and Perform Final Read-Only Verification

**Files:**

- Modify: `docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md`
- Modify: `docs/steady53_experiment_log.md`
- Modify only if implementation reveals a specification correction: `docs/superpowers/specs/2026-08-25-steady53-h2a-he-third-virial-counterfactual-design.md`

- [ ] **Step 1: Add the H2a result record**

Record:

- artificial change and unchanged quantities;
- baseline parity results;
- fixed-point baseline/counterfactual values and deltas;
- both path ranges, boundary counts, roots, intervals, extrema, and invalid states;
- whether the C111 derivative discontinuity disappears;
- CSV/TXT hashes;
- RED/GREEN counts;
- evidence grades `✅/⚠️/❌/❓`;
- explicit statements that H1a-S2, Task 8, and 14000 s remain unexecuted/uncompleted;
- `authorizesRepair=false`.

- [ ] **Step 2: Run the focused H2a verification in a fresh MATLAB process**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'files=["tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m","tests/steady53/test_publish_task8_h2a_evidence.m"]; r=runtests(files); fprintf("H2A_PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assert(~any([r.Failed]) && ~any([r.Incomplete]));'
```

- [ ] **Step 3: Run the approved no-SLX offline regression subset**

Include the existing spec/evaluator/evidence/H1a/H2 tests plus the two H2a tests. Do not run the whole directory. Record exact pass/fail/incomplete counts.

- [ ] **Step 4: Discover the full directory without executing it**

```matlab
allTests = testsuite("tests/steady53");
fprintf("STEADY53_DISCOVERED_ONLY=%d\n", numel(allTests));
```

Confirm both H2a test files are represented. This is discovery evidence, not a full-suite pass claim.

- [ ] **Step 5: Run static and asset verification**

Run `checkcode` on the four H2a MATLAB files. Search the analyzer/publisher for forbidden model APIs. Run:

```bash
git diff --check
git status --short
git rev-parse 'archive/pre-restart-20260824^{commit}'
shasum -a 256 final_steady_24a.slx HeXe_property_simulink.m \
  hexe_compressor_lookup.mat radiator_table.mat \
  turbine_table1.mat turbine_table2.mat \
  tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat \
  tmp/steady53/task8_root_cause/h2/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2_property_diagnostics.csv \
  tmp/steady53/task8_root_cause/h2/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h2_summary.txt
```

Also hash the thesis PDF by its approved absolute path. Every protected hash must match the fixed list at the top of this plan.

- [ ] **Step 6: Commit the result record**

```bash
git add docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md \
        docs/steady53_experiment_log.md \
        docs/superpowers/specs/2026-08-25-steady53-h2a-he-third-virial-counterfactual-design.md
git diff --cached --check
git commit -m "docs: record approved H2a counterfactual result"
```

If the design file did not change, omit it from `git add` rather than creating a no-op edit.

---

## Final Status Language

Only use the following status distinctions after fresh verification:

```text
H2a read-only counterfactual: COMPLETE or NOT COMPLETE
H2a baseline parity: PASS or FAIL
counterfactual physical-domain result: REPORTED, never promoted automatically
H1a-S2 integration: NOT EXECUTED
Task 8 steady acceptance: RED / NOT COMPLETED
14000 s steady run: NOT EXECUTED / NOT COMPLETED
formal property repair: NOT AUTHORIZED
```

Do not describe a physically improved H2a result as proof that Scheme A is the correct formal model. A favorable result is only evidence that the approved hypothesis deserves the next human review gate.
