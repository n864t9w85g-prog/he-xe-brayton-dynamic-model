# Steady53 H1b Cpbar Read-Only Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a strictly read-only H1b experiment that freezes the approved H1a-S2 Scheme A `phi/T2s` candidate, replaces only point `cp1/cp2` with formal-property path-integral `cpBar` values, and reports three explicit pressure-path sensitivities without selecting a formal path.

**Architecture:** Add one pure candidate solver and one independent fixed-evidence analyzer under `tests/steady53/`. The analyzer validates the approved H1a-S2/H2a evidence and all protected inputs, reproduces the point-`cp` baseline, calls the solver for `linearEndpointPressure`, `constantP1`, and `constantP2`, then atomically publishes a self-contained CSV/TXT pair under `tmp/`. Existing H1a/H2/H2a code and evidence remain unchanged.

**Tech Stack:** MATLAB R2025a function-based tests, `integral`, bracketed `fzero`, formal `HeXe_property_simulink(T,P)`, read-only MAT loading, SHA-256, Java NIO no-replace publication, CSV/TXT evidence, Git.

---

## Fixed scope and file map

Read `AGENTS.md`, all three formal root rules, the approved design
`docs/superpowers/specs/2026-08-26-steady53-h1b-cpbar-readonly-design.md`, the Task 8
root-cause addendum, and the current H1a-S2 analyzer/tests before editing.

Create only:

```text
tests/steady53/h1b_cpbar_candidate_readonly.m
tests/steady53/test_h1b_cpbar_candidate_readonly.m
tests/steady53/analyze_task8_h1b_cpbar_readonly.m
tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m
```

Generate only:

```text
tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/
  run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/
    h1b_cpbar_sensitivity.csv
    h1b_cpbar_summary.txt
```

Do not modify any SLX, MAT, PDF, formal property file, acceptance threshold, existing
H1a/H2/H2a implementation, or existing evidence. The two new implementation files must not
contain `load_system`, `open_system`, `sim`, `set_param`, `save_system`, or `bdclose` calls.

Public solver interface:

```matlab
result = h1b_cpbar_candidate_readonly( ...
    inputs, pathVariant, propertyFunction, numerics)
```

Required contracts:

```matlab
inputs = struct("T1_K", T1, "P1_Pa", P1, "P2_Pa", P2, ...
    "T2s_K", T2s, "eta", eta);
% pathVariant must equal exactly one of:
% "linearEndpointPressure", "constantP1", or "constantP2".
[cpMass_J_kgK, gamma, rho_kg_m3] = propertyFunction(T_K, P_Pa);
numerics = struct("integralFunction", @integral, ...
    "rootFunction", @fzero, "integralRelTol", 1e-8, ...
    "integralAbsTol_J_kgK", 1e-8, "rootTolX_K", 1e-12, ...
    "rootMaxIterations", 1000, ...
    "rootMaxFunctionEvaluations", 5000, ...
    "rootAbsResidualTolerance_K", 1e-9, ...
    "auditSampleCount", 1001);
```

The analyzer interface is:

```matlab
analysis = analyze_task8_h1b_cpbar_readonly()
analysis = analyze_task8_h1b_cpbar_readonly( ...
    struct("testOnly", true, "outputDir", absolutePath))
```

Tamper/failure tests may use a nested complete test-control struct; partial or unknown fields
must fail with `steady53:H1bInvalidOptions`.

---

### Task 1: Pure candidate solver RED tests

**Files:**
- Create: `tests/steady53/test_h1b_cpbar_candidate_readonly.m`
- Test target absent at RED: `tests/steady53/h1b_cpbar_candidate_readonly.m`

- [ ] **Step 1: Create a function-based test file with exactly ten tests**

Use these names:

```text
testConstantCpRecoversEtaEquation
testAnalyticCpMatchesAllPressurePaths
testAuditHas1001PhysicalPoints
testInvalidInputsAndVariantFailClosed
testNonphysicalPropertyFailsClosed
testPropertyWarningFailsClosed
testIntegralFailurePreservesCause
testNoBracketFailsClosed
testRootNonconvergenceFailsClosed
testWarningStateRestoredAfterFailure
```

The common fixture is:

```matlab
function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"), "-begin");
testCase.TestData.inputs = struct("T1_K", 1500, "P1_Pa", 1.5e6, ...
    "P2_Pa", 0.7e6, "T2s_K", 1100, "eta", 0.87);
testCase.TestData.numerics = fixedNumerics();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function numerics = fixedNumerics()
numerics = struct("integralFunction", @integral, ...
    "rootFunction", @fzero, "integralRelTol", 1e-8, ...
    "integralAbsTol_J_kgK", 1e-8, "rootTolX_K", 1e-12, ...
    "rootMaxIterations", 1000, ...
    "rootMaxFunctionEvaluations", 5000, ...
    "rootAbsResidualTolerance_K", 1e-9, "auditSampleCount", 1001);
end
```

- [ ] **Step 2: Test the Eq. (2.30) ratio direction with constant `cp`**

```matlab
function testConstantCpRecoversEtaEquation(testCase)
for variant = ["linearEndpointPressure" "constantP1" "constantP2"]
    result = h1b_cpbar_candidate_readonly(testCase.TestData.inputs, ...
        variant, @constantProperty, testCase.TestData.numerics);
    inputs = testCase.TestData.inputs;
    expected = inputs.T1_K-inputs.eta*(inputs.T1_K-inputs.T2s_K);
    verifyEqual(testCase, result.T2_K, expected, "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarIsentropic_J_kgK, 520, ...
        "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarActual_J_kgK, 520, ...
        "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarRatio, 1, "AbsTol", 1e-12);
end
end

function [cp, gamma, rho] = constantProperty(~, ~)
cp = 520; gamma = 1.65; rho = 4;
end
```

- [ ] **Step 3: Test all three averages against an independent analytic property**

Use `cp(T,P)=480+0.02*T+1e-6*P`, `gamma=1.65`, and `rho=P/(287*T)`. For each
variant, compare the returned ideal average at `T2s` and actual average at the returned `T2`
against:

```matlab
meanT = (inputs.T1_K + Tout_K)/2;
switch variant
    case "linearEndpointPressure"
        meanP = (inputs.P1_Pa + inputs.P2_Pa)/2;
    case "constantP1"
        meanP = inputs.P1_Pa;
    case "constantP2"
        meanP = inputs.P2_Pa;
end
expectedCpBar = 480 + 0.02*meanT + 1e-6*meanP;
```

Require `AbsTol=1e-8 J/(kg K)` and independently reconstruct the Eq. (2.30) residual.

- [ ] **Step 4: Test both returned audits**

For `idealPathAudit` and `actualPathAudit`, require `sampleCount=1001`, positive
`minCp/minCv/minRho`, `minGamma>1`, `allPhysical=true`, and
`formalGlobalProof=false`.

- [ ] **Step 5: Add exact fail-closed tests**

Require these IDs:

```text
invalid input                         steady53:H1bInvalidInput
unknown path                         steady53:H1bInvalidPathVariant
cp<=0/gamma<=1/rho<=0                steady53:H1bInvalidProperty
property warning converted to error  steady53:H1bPropertyWarning
integral exception                   steady53:H1bIntegrationFailed
no sign-changing bracket             steady53:H1bNoBracket
root exitflag<=0                      steady53:H1bRootFailed
```

For no-bracket coverage, inject a closure integral returning `100`, `1`, `1` on its first
three calls. For root failure, inject a root function returning the bracket midpoint with
`exitflag=0`. Verify the integration/property wrapper preserves the original exception as a
cause and the full warning state is equal before/after every failure.

- [ ] **Step 6: Run RED and require the missing solver to be the cause**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'r=runtests("tests/steady53/test_h1b_cpbar_candidate_readonly.m"); fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assert(numel(r)==10 && any([r.Failed]));'
```

Expected: `TOTAL=10`, with undefined `h1b_cpbar_candidate_readonly` failures.

---

### Task 2: Pure candidate solver minimal GREEN

**Files:**
- Create: `tests/steady53/h1b_cpbar_candidate_readonly.m`
- Test: `tests/steady53/test_h1b_cpbar_candidate_readonly.m`

- [ ] **Step 1: Implement exact validation**

Require scalar structs with exact field sets; finite positive `T/P`; `0<T2s<T1`;
`0<eta<1`; valid function handles; positive tolerances; positive integer iteration limits; and
`auditSampleCount==1001`. Do not ignore unknown fields.

- [ ] **Step 2: Implement the path and formal property state contracts**

```matlab
function [T_K, P_Pa] = pathPoint(lambda, Tout_K, inputs, variant)
T_K = inputs.T1_K + lambda*(Tout_K-inputs.T1_K);
switch variant
    case "linearEndpointPressure"
        P_Pa = inputs.P1_Pa + lambda*(inputs.P2_Pa-inputs.P1_Pa);
    case "constantP1"
        P_Pa = inputs.P1_Pa;
    case "constantP2"
        P_Pa = inputs.P2_Pa;
    otherwise
        error("steady53:H1bInvalidPathVariant", "Unknown path variant.");
end
end
```

`propertyState` must scope `warning("error","all")` around exactly one property call,
restore the complete warning state with `onCleanup`, preserve the warning exception as a cause,
calculate `cv=cp/gamma`, and enforce finite real `cp>0`, `gamma>1`, `cv>0`, `rho>0`.

- [ ] **Step 3: Implement the average and implicit residual exactly**

```matlab
cpBar(Tout) = integral_0^1 cp(T1+lambda*(Tout-T1),P(lambda)) dlambda
R(T2) = T2 - (T1-eta*(cpBarIsentropic/cpBarActual(T2))*(T1-T2s))
```

Call the injected integral with `RelTol`, `AbsTol`, and `ArrayValued=true`. Wrap any integral
failure as `steady53:H1bIntegrationFailed` with its cause.

- [ ] **Step 4: Implement bracketed root and audits**

Evaluate both endpoints `[T2s,T1]`, require a sign change, and call the injected root function
with `TolX=1e-12`, `MaxIter=1000`, and `MaxFunEvals=5000`. Require `exitflag>0`, root inside
the closed bracket, and absolute residual `<=1e-9 K`.

Audit `linspace(0,1,1001).'` for the fixed ideal root and resolved actual root. Return:

```text
pathVariant cpBarIsentropic_J_kgK cpBarActual_J_kgK cpBarRatio
T2_K rootResidual_K rootBracket_K integrationCompleted rootConverged
idealPathAudit actualPathAudit numerics
```

Each audit contains sample count, min/max `cp/cv/gamma/rho`, `allPhysical`,
`formalGlobalProof=false`, and
`classification="finite1001PointAuditNotFormalGlobalProof"`.

- [ ] **Step 5: Run all ten tests GREEN and static checks**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'r=runtests("tests/steady53/test_h1b_cpbar_candidate_readonly.m"); fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assertSuccess(r); files=["tests/steady53/h1b_cpbar_candidate_readonly.m","tests/steady53/test_h1b_cpbar_candidate_readonly.m"]; for f=files, issues=checkcode(f,"-id"); assert(isempty(issues)); end'
```

Expected: `PASS=10 FAIL=0 INCOMPLETE=0 TOTAL=10`; both `checkcode` counts are zero.

- [ ] **Step 6: Commit the pure solver**

```bash
git diff --check
git add tests/steady53/h1b_cpbar_candidate_readonly.m \
        tests/steady53/test_h1b_cpbar_candidate_readonly.m
git diff --cached --check
git commit -m "test: add read-only H1b cpbar solver"
```

---

### Task 3: Fixed-evidence analyzer RED tests

**Files:**
- Create: `tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m`
- Test target absent at RED: `tests/steady53/analyze_task8_h1b_cpbar_readonly.m`

- [ ] **Step 1: Create a function-based test file with exactly twelve tests**

Use these names:

```text
testRealFormalPropertyComputesAllThreeCandidates
testBaselineIdentityAndSingleVariableScope
testOutputIsIndependentlySelfContained
testH1aHashMismatchPrecedesOutputCreation
testMalformedH1aEvidenceFailsClosed
testH1aPointBaselineMismatchFailsClosed
testProtectedDependencyHashMismatchFailsClosed
testExistingOutputRefusesOverwrite
testTransactionalPublicationLeavesNoHalfOutput
testUnknownOrPartialOverrideFailsClosed
testEnvironmentAndLoadedDiagramsArePreserved
testAnalyzerContainsNoModelApis
```

`setupOnce` must save the original path and complete warning state, add only root and
`tests/steady53`, create one owned `tempname` root, and record loaded block diagrams and all
protected hashes. `teardownOnce` restores path/warnings and removes only that exact owned root;
it must not close any model.

- [ ] **Step 2: Add the real fixed-input computation contract**

```matlab
function testRealFormalPropertyComputesAllThreeCandidates(testCase)
outputDir = fullfile(testCase.TestData.tempRoot, "real_h1b");
analysis = analyze_task8_h1b_cpbar_readonly( ...
    struct("testOnly", true, "outputDir", string(outputDir)));
verifyEqual(testCase, analysis.runId, ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
verifyEqual(testCase, sort(string({analysis.candidates.pathVariant})), ...
    sort(["linearEndpointPressure" "constantP1" "constantP2"]));
verifyEqual(testCase, analysis.inputs.T2s_K, ...
    1089.5635709913104, "AbsTol", 1e-12);
verifyEqual(testCase, analysis.inputs.eta, ...
    0.87286960881076081, "AbsTol", 1e-15);
verifyLessThanOrEqual(testCase, ...
    abs(analysis.h1aPointCpReproductionResidual_K), 1e-9);
for candidate = analysis.candidates
    verifyTrue(testCase, candidate.integrationCompleted);
    verifyTrue(testCase, candidate.rootConverged);
    verifyLessThanOrEqual(testCase, abs(candidate.rootResidual_K), 1e-9);
    verifyTrue(testCase, candidate.actualPathAudit.allPhysical);
    verifyTrue(testCase, candidate.idealPathAudit.allPhysical);
end
verifyTrue(testCase, analysis.h1bExecuted);
verifyFalse(testCase, analysis.h1bPressurePathSelectedAsFormal);
verifyFalse(testCase, analysis.authorizesRepair);
verifyFalse(testCase, analysis.formalModelPromotion);
verifyFalse(testCase, analysis.slxLoadedOrSimulated);
end
```

- [ ] **Step 3: Add baseline identity and single-variable scope assertions**

Require exact H1a CSV/TXT hashes, H2a hashes, formal property/model/table/MAT/helper hashes,
and:

```matlab
analysis.scope.h1aPhiPropertyVariant == "schemeA"
analysis.scope.h1bCpbarPropertyVariant == "formalHeXeProperty"
analysis.scope.T2sHeldFixed == true
analysis.scope.etaHeldFixed == true
analysis.scope.onlyPointCpReplacedByPathCpbar == true
analysis.h1aCandidateBaselineSelectedForExperiment == true
analysis.h1aCandidateBaselinePromotedToFormalModel == false
```

Require fixed `phiBar=0.39979002315209694`, `T2s=1089.5635709913104 K`, and
`H1a T2=1143.6624955393854 K`.

- [ ] **Step 4: Add the self-contained output contract**

Require exactly two regular files, CSV `height==4`, and exact method set:

```text
H1a_S2_schemeA_pointCp_baseline
H1b_linearEndpointPressure
H1b_constantP1
H1b_constantP2
```

Every CSV row repeats all paths/hashes, the approved single-variable scope, and all status
boundaries. Three H1b rows contain finite `cpBarIsentropic`, `cpBarActual`, `cpBarRatio`, `T2`,
`deltaT2`, `remainingError`, `explainedFraction`, numerical-sufficiency fields, and both audits.
The baseline row records point `cp1/cp2s`, marks `pathIntegralApplicable=false`, and uses missing
values only for explicitly H1b-path-only columns. Independently verify all corresponding keys in
TXT.

- [ ] **Step 5: Add exact fail-closed tests**

Use copied, test-owned inputs and a complete nested `testControl` override. Never mutate an
original. Require:

```text
H1a CSV/TXT hash mismatch       steady53:H1bH1aEvidenceHashMismatch
malformed/duplicate H1a rows    steady53:H1bInvalidH1aEvidence
point baseline mismatch         steady53:H1bBaselineMismatch
other protected hash mismatch   steady53:H1bProtectedHashMismatch
existing output                 steady53:H1bOutputExists
staging hook failure             steady53:H1bOutputFailed
partial/unknown override         steady53:H1bInvalidOptions
```

For every pre-publication failure, require the requested output directory not to exist. For
transactional failures after CSV and before publish, require no fixed output and no owned staging
residue. Verify exact path/warning equality and loaded-diagram/protected-hash equality on success
and failure.

- [ ] **Step 6: Add the static API boundary test**

Scan both new implementation sources with:

```matlab
pattern = ['(?<![A-Za-z0-9_])' ...
    '(load_system|open_system|sim|set_param|save_system|bdclose)\s*\('];
```

Require no matches. Require the analyzer source to contain `HeXe_property_simulink`,
`h1b_cpbar_candidate_readonly`, all three path names, and all fixed evidence hashes.

- [ ] **Step 7: Run RED and require the missing analyzer to be the cause**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'r=runtests("tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m"); fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assert(numel(r)==12 && any([r.Failed]));'
```

Expected: `TOTAL=12`, with undefined `analyze_task8_h1b_cpbar_readonly` failures.

---

### Task 4: Fixed-evidence analyzer minimal GREEN

**Files:**
- Create: `tests/steady53/analyze_task8_h1b_cpbar_readonly.m`
- Test: `tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m`

- [ ] **Step 1: Implement fixed configuration and strict override parsing**

`defaultConfig(root)` contains the approved run ID, exact paths and hashes, path variants,
formal property handle, fixed numerics, fixed output directory, and a no-op output failure hook.
The ordinary test-only convenience override allows exactly `testOnly/outputDir`. A nested complete
`testControl` must state every path, expected hash, function handle, archive identity, numerics,
output directory, and hook; reject partial/unknown fields.

- [ ] **Step 2: Hash all identities before output creation**

Hash H1a CSV/TXT first and use `steady53:H1bH1aEvidenceHashMismatch` for either mismatch. Hash
the MAT, model, formal property, turbine table, Scheme A helper, and H2a CSV/TXT and use
`steady53:H1bProtectedHashMismatch` for other drift. Resolve
`archive/pre-restart-20260824^{}` and require
`8f625c268c35a95c18a626305c1aa6a79ae2ace7`. No `mkdir` occurs in this step.

- [ ] **Step 3: Parse and validate the complete H1a evidence**

Read H1a CSV using `TextType="string"` and preserved variable names. Require `height==3`, exact
method set, exactly one `S2_schemeA_phiOnly`, all identity columns, fixed `phiBar/T2s/T2`, exact
Scheme A definition/scope, `etaCp1Cp2HeldFixed=true`, and every negative gate. Verify recorded
paths and hashes against actual dependencies. Throw `steady53:H1bInvalidH1aEvidence` on any
contract mismatch.

- [ ] **Step 4: Validate MAT/table payload and reproduce the point-`cp` baseline**

Load only:

```matlab
payload = load(config.inputMat, "result", "report", "spec");
tablePayload = load(config.turbineTableMat, ...
    "bp_mf", "bp_speed", "table_eff");
```

Validate `result.t`, `spec.finalWindow_s`, payload model hashes, and last values of
`turbine_inlet_T`, `turbine_inlet_P`, `turbine_outlet_P`,
`turbine_lookup_mass_flow`, and `turbine_lookup_speed_eff`. Read the
`turbine_outlet_T` target from `report.metrics`.

Recompute `eta` with the existing `interpn` dimension order:

```matlab
bp_mf = double(tablePayload.bp_mf(:));
bp_speed = double(tablePayload.bp_speed(:));
eta = interpn(bp_mf, bp_speed, double(tablePayload.table_eff), ...
    massFlow, speed_rpm, "linear");
```

Require the query inside both breakpoint ranges and `0<eta<1`. Clear the formal property to the
canonical uninitialized state immediately before and after the property calls. Recompute:

```matlab
[cp1, gamma1, rho1] = config.propertyFunction(T1_K, P1_Pa);
[cp2s, gamma2s, rho2s] = config.propertyFunction(T2s_K, P2_Pa);
T2point = T1_K-eta*(cp2s/cp1)*(T1_K-T2s_K);
```

Require physical property outputs and absolute reproduction residual `<=1e-9 K`; otherwise
throw `steady53:H1bBaselineMismatch`.

- [ ] **Step 5: Solve three candidates in approved order and calculate sensitivities**

```matlab
solverInputs = struct("T1_K", T1_K, "P1_Pa", P1_Pa, ...
    "P2_Pa", P2_Pa, "T2s_K", T2s_K, "eta", eta);
for index = 1:3
    candidates(index) = h1b_cpbar_candidate_readonly( ...
        solverInputs, config.pathVariants(index), ...
        config.propertyFunction, config.numerics);
    candidates(index).deltaT2FromH1a_K = candidates(index).T2_K-h1aT2_K;
    candidates(index).remainingTargetError_K = targetT2_K-candidates(index).T2_K;
    candidates(index).explainedFractionOfH1aGap = ...
        candidates(index).deltaT2FromH1a_K/(targetT2_K-h1aT2_K);
    candidates(index).targetDirectionMatched = ...
        sign(candidates(index).deltaT2FromH1a_K) == sign(targetT2_K-h1aT2_K);
    candidates(index).h1bNumericallySufficient = ...
        candidates(index).targetDirectionMatched && ...
        abs(candidates(index).deltaT2FromH1a_K) >= abs(targetT2_K-h1aT2_K);
end
```

Do not sort by target error and do not select a preferred result.

- [ ] **Step 6: Build the four-row table and analysis status**

Return inputs, H1a baseline, point-`cp` reproduction, all candidates, table, dependency paths and
hashes, before/after loaded diagrams, restored path/warnings, and canonical cleared property state.
Set exactly:

```text
h1aCandidateBaselineSelectedForExperiment=true
h1aCandidateBaselinePromotedToFormalModel=false
h1bExecuted=true
h1bPressurePathSelectedAsFormal=false
modelModified=false
formalPropertyModified=false
slxLoadedOrSimulated=false
authorizesRepair=false
formalModelPromotion=false
task8Passed=false
steady14000AcceptancePassed=false
```

- [ ] **Step 7: Implement two-file transactional publication**

Adapt the directory-level no-replace pattern already audited in
`analyze_task8_h1a_readonly.m`, using H1b-specific filenames and IDs. The exact order is:

1. after every identity, numerical, environment, and read-only gate passes, create the exact
   approved H1b output parent if absent; reject a non-directory at that path;
2. reject an existing fixed run target;
3. create a unique same-parent owned staging directory;
4. write CSV and invoke `outputFailureHook("afterCsvBeforeSummary", stagingDir)`;
5. write/close UTF-8 TXT;
6. parse both staged files and verify row/key contracts;
7. hash both files;
8. recheck target and invoke `outputFailureHook("beforePublish", stagingDir)`;
9. Java NIO directory move with no replace;
10. verify published hashes equal staged hashes;
11. clean only paths whose exact parent and owned prefix/leaf match.

Use `steady53:H1bOutputExists` for collision and `steady53:H1bOutputFailed` for publication
failure. Print floating values with `%.17g`.

- [ ] **Step 8: Run all new tests GREEN and commit**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'files=["tests/steady53/test_h1b_cpbar_candidate_readonly.m","tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m"]; r=runtests(files); fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n",sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r)); assertSuccess(r); files2=["tests/steady53/analyze_task8_h1b_cpbar_readonly.m","tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m"]; for f=files2, issues=checkcode(f,"-id"); assert(isempty(issues)); end'
```

Expected: `PASS=22 FAIL=0 INCOMPLETE=0 TOTAL=22`; both new analyzer files have zero
`checkcode` issues.

```bash
git diff --check
git add tests/steady53/analyze_task8_h1b_cpbar_readonly.m \
        tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m
git diff --cached --check
git commit -m "test: analyze H1b cpbar paths read only"
```

---

### Task 5: Publish the fixed H1b evidence

**Files:**
- Generate: `tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1b_cpbar_sensitivity.csv`
- Generate: `tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1b_cpbar_summary.txt`
- Test if a publication omission is exposed: `tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m`

- [ ] **Step 1: Verify target absence and every protected hash**

Use read-only `test ! -e`, `shasum -a 256`, and
`git rev-parse 'archive/pre-restart-20260824^{}'`. If the target exists, stop without deleting
it. Compare every value with the approved design before running MATLAB.

- [ ] **Step 2: Run the default fixed analyzer once**

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch \
  'addpath("tests/steady53"); a=analyze_task8_h1b_cpbar_readonly(); fprintf("CSV_SHA256=%s\nTXT_SHA256=%s\n",a.csvSha256,a.summarySha256); for c=a.candidates, fprintf("%s cpBarS=%.17g cpBarA=%.17g ratio=%.17g T2=%.17g delta=%.17g remaining=%.17g sufficient=%s\n",c.pathVariant,c.cpBarIsentropic_J_kgK,c.cpBarActual_J_kgK,c.cpBarRatio,c.T2_K,c.deltaT2FromH1a_K,c.remainingTargetError_K,string(c.h1bNumericallySufficient)); end'
```

Record exact stdout and hashes; do not round stored evidence.

- [ ] **Step 3: Verify self-containment independently**

Require exactly two regular files. Parse CSV independently with `readtable` and TXT with
`fileread`. Require CSV `height==4`, exact method/path sets, all dependency identities, all six
audits, all sensitivity fields, and all status boundaries. Require TXT to contain the same
identities, equations, path definitions, numerical settings, results, audit limits, and negative
gates.

- [ ] **Step 4: Verify no-overwrite behavior**

Hash both outputs, run the default analyzer again, require `steady53:H1bOutputExists`, and require
both post-attempt hashes equal the pre-attempt hashes.

- [ ] **Step 5: Run focused regressions**

Run the new 22 tests. Then run the existing five-file H1a/H2a 52-test subset plus both new H1b
test files. Expected focused result:

```text
PASS=74 FAIL=0 INCOMPLETE=0 TOTAL=74
```

- [ ] **Step 6: Commit exactly two evidence files**

`tmp/` is ignored, so use `git add -f` only for the exact two approved files:

```bash
git add -f \
  tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1b_cpbar_sensitivity.csv \
  tmp/steady53/task8_root_cause/h1b_cpbar_from_h1a_s2_scheme_a/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/h1b_cpbar_summary.txt
git diff --cached --check
git commit -m "test: publish read-only H1b cpbar evidence"
```

Do not add caches, staging directories, invalid attempts, or any other `tmp/` path.

---

### Task 6: Document, verify, and review

**Files:**
- Modify: `docs/steady53_experiment_log.md`
- Modify: `docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md`
- Modify: `docs/superpowers/plans/2026-08-26-steady53-h1b-cpbar-readonly.md`

- [ ] **Step 1: Record exact results with evidence grades**

Record:

- ✅ fixed identities and H1a point-`cp` baseline reproduction;
- ✅ each candidate's `cpBarIsentropic/cpBarActual/ratio/T2/rootResidual`;
- ✅ each delta, remaining error, explained fraction, direction, and numerical sufficiency;
- ⚠️ six 1001-point audits are finite numerical evidence only;
- ❓ pressure-path physical interpretation remains unresolved;
- ❌ no formal path selected and no repair/promotion authorized;
- ❌ Task 8, 14000-second steady acceptance, and paper Section 5.3 remain incomplete.

Record exact H1b CSV/TXT hashes and fresh test counts.

- [ ] **Step 2: Run static checks and forbidden API scans**

Run `checkcode` on all four new MATLAB files and require zero issues. Run:

```bash
rg -n '\b(load_system|open_system|sim|set_param|save_system|bdclose)\s*\(' \
  tests/steady53/h1b_cpbar_candidate_readonly.m \
  tests/steady53/analyze_task8_h1b_cpbar_readonly.m
```

Expected: no matches. Also run `git diff --check`.

- [ ] **Step 3: Run the expanded no-SLX suite**

Run the previous ten-file 149-test list plus both new H1b test files:

```matlab
files = [ ...
"tests/steady53/test_evaluate_steady53.m"
"tests/steady53/test_steady53_spec.m"
"tests/steady53/test_task8_evidence.m"
"tests/steady53/test_analyze_task8_h1a_readonly.m"
"tests/steady53/test_analyze_task8_h1a_s2_scheme_a_readonly.m"
"tests/steady53/test_hexe_property_scheme_a_offline.m"
"tests/steady53/test_analyze_task8_h2_hexe_property_readonly.m"
"tests/steady53/test_publish_task8_h2_evidence.m"
"tests/steady53/test_analyze_task8_h2a_he_third_virial_counterfactual.m"
"tests/steady53/test_publish_task8_h2a_evidence.m"
"tests/steady53/test_h1b_cpbar_candidate_readonly.m"
"tests/steady53/test_analyze_task8_h1b_cpbar_readonly.m"];
r = runtests(files);
fprintf("PASS=%d FAIL=%d INCOMPLETE=%d TOTAL=%d\n", ...
    sum([r.Passed]),sum([r.Failed]),sum([r.Incomplete]),numel(r));
assertSuccess(r);
```

Expected: `PASS=171 FAIL=0 INCOMPLETE=0 TOTAL=171`.

- [ ] **Step 4: Discover but do not run the complete suite**

```matlab
suite = testsuite("tests/steady53");
fprintf("DISCOVERY_TOTAL=%d\n",numel(suite));
assert(numel(suite)==198);
```

Expected: `176 existing + 22 new = 198`. Do not call `run(suite)`.

- [ ] **Step 5: Verify every protected identity**

Require:

```text
final_steady_24a.slx
5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d
HeXe_property_simulink.m
2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2
turbine_table2.mat
cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33
nominal_500_report.mat
4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b
hexe_property_scheme_a_offline.m
5820e957b90b1affce777c1774aee6cc685f40430310408fb00f303846f606d0
H1a-S2 CSV
7e1ed139d14cbb1977a9f19d870c822243205414321a00c0f597717f5616f622
H1a-S2 TXT
26248e95f42acbb70701193fa75af429b60659b9975277837331b8cd2803efd2
H2a CSV
6a8398b7a32685cb3d198a1fe39b3b9365cfdefe65143d5613c68ffdd44366f4
H2a TXT
afd75b1b31cd0abdbdb2926b95ab987f260caa81a55fe2e901fdde4dafd72465
archive/pre-restart-20260824^{}
8f625c268c35a95c18a626305c1aa6a79ae2ace7
```

Also require new H1b evidence hashes to equal the values printed and documented in Task 5.

- [ ] **Step 6: Obtain an independent scope/evidence review**

The review must verify:

1. Scheme A is used only as fixed H1a `phi/T2s` evidence;
2. every H1b average uses the formal property function;
3. Eq. (2.30) uses `cpBarIsentropic/cpBarActual`, not its inverse;
4. exactly three candidates are present and none selected as formal;
5. CSV and TXT are independently self-contained;
6. no formal asset or prior evidence changed;
7. no SLX was loaded or simulated;
8. test counts and hashes are fresh.

Resolve all Critical and Important findings. Record any accepted Minor limitation explicitly.

- [ ] **Step 7: Commit documentation and verify clean status**

```bash
git add docs/steady53_experiment_log.md \
        docs/superpowers/plans/2026-08-24-steady53-task8-root-cause-addendum.md \
        docs/superpowers/plans/2026-08-26-steady53-h1b-cpbar-readonly.md
git diff --cached --check
git commit -m "docs: record read-only H1b cpbar result"
git status --porcelain=v1
```

Expected final status output: empty.

## Stop conditions

Stop for human review if implementation would require changing Scheme A beyond H1a `phi`, using
Scheme A for H1b `cpBar`, adding/removing/selecting a pressure path, changing `T2s`, `eta`, inputs,
target, tolerances or audit count, modifying/simulating SLX, modifying formal property/MAT,
changing acceptance thresholds, publishing only a subset after another candidate fails, or
treating numerical closeness as physical correctness.
