# Xu Chi Paper Section 5.4 Dynamic Reproduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `final_dynamic_24a.slx` reproduce the paper Table 5.2 steady baseline and the Section 5.4 speed, load, and reactivity cases without unsourced model numbers.

**Architecture:** Establish provenance tests before changing the model. Correct the electrical-to-shaft load boundary, build and validate a candidate compressor map from NASA measurements plus a bounded no-free-parameter similarity extension, apply it only through an audited gate, obtain a coupled steady operating point using only paper constraints, and only then run the Section 5.4 acceptance cases.

**Tech Stack:** MATLAB R2025a, Simulink, Simulink Control Design operating-point tools, MAT-file lookup tables, Poppler-rendered thesis figures.

---

## File structure

- Create `paper54_constants.m`: paper literals and formulas only.
- Create `tests/test_paper52_power_balance.m`: Table 5.2 and rotor-equation regression.
- Create `apply_paper52_generator_load.m`: idempotent audited edit of the rotor subsystem.
- Modify `start.m`: load traceable constants into the model workspace.
- Modify `final_dynamic_24a.slx`: add electrical-load to shaft-load conversion.
- Create `tests/audit_paper52_baseline.m`: coupled baseline boundary and residual audit.
- Create `solve_paper52_operating_point.m`: steady-state search and residual report.
- Create `paper52_operating_point.mat`: verified initial operating point only after the audit passes.
- Create `data/provenance/compressor_map/`: source images, calibration, digitized points, and metadata.
- Create `tmx2269_predict_speed_line.m`: pure bounded similarity-law speed-line prediction.
- Create `tests/test_tmx2269_speed_extension.m`: identity, leave-one-out, provenance, and upper-bound tests.
- Create `build_traceable_compressor_lookup.m`: deterministic candidate-only MAT builder.
- Create `output/paper54_reproduction/hexe_compressor_lookup_candidate.mat`: candidate output that never implicitly replaces the active map.
- Create `tests/test_compressor_map_provenance.m`: reject synthetic or untraceable active maps.
- Modify `hexe_compressor_lookup.mat`: only after the candidate passes every source, range, Table 5.2, and model-update gate.
- Create `paper54_schedules.m`: exact paper schedules.
- Create `tests/test_paper54_schedules.m`: schedule regression.
- Create `run_paper54_cases.m`: baseline and three Section 5.4 cases.
- Create `tests/test_paper54_acceptance.m`: end-state and domain acceptance.
- Modify `run_dynamic.m`, `验收标准_论文5.4.md`, and `图5_34_对比分析_14000s.md`: remove stale claims while retaining historical failure evidence.

## Current checkpoint and corrected execution order

Tasks 1 and 2 are complete. The first diagnostic measurement in Task 3 exists,
but its active compressor map is still the rejected `3.0-paper-shape` surrogate.
Therefore execute the remaining work in this order: **Task 5, Task 3 rerun,
Task 4, Tasks 6--8**. A coupled operating point obtained before Task 5 passes
would only validate the synthetic map and is not an acceptable paper baseline.

### Task 1: Freeze paper literals with a failing test

**Files:**

- Create: `tests/test_paper54_constants.m`
- Create: `paper54_constants.m`
- Create: `tests/test_paper52_power_balance.m`

- [ ] **Step 1: Write the failing constants test**

```matlab
function test_paper54_constants()
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
C = paper54_constants();
assert(abs(C.compressor.PR - 1.551/0.658) < 10*eps(C.compressor.PR));
expectedEta = 1000.21/(2252.2-1231.6);
assert(abs(C.generator.eta_calculated - expectedEta) < ...
    10*eps(C.generator.eta_calculated));
residual = C.turbine.power_W - C.compressor.power_W - ...
    C.generator.shaft_power_W;
assert(abs(residual) < 1e-6);
end
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_paper54_constants"
```

Expected: failure because `paper54_constants` is undefined.

- [ ] **Step 3: Write `paper54_constants.m`**

Define a function returning a struct. Store thesis literals separately from calculated consequences:

```matlab
function C = paper54_constants()
C.source = 'Xu Chi thesis, Table 5.2, Eqs. (5.17)-(5.18), Sec. 5.4';
C.N_rpm = 55090;
C.compressor.Tin_K = 405.16;
C.compressor.Pin_Pa = 0.658e6;
C.compressor.Tout_K = 601.90;
C.compressor.Pout_Pa = 1.551e6;
C.compressor.power_W = 1231.6e3;
C.turbine.power_W = 2252.2e3;
C.generator.electric_power_W = 1000.21e3;
C.compressor.PR = C.compressor.Pout_Pa / C.compressor.Pin_Pa;
C.generator.eta_calculated = C.generator.electric_power_W / ...
    (C.turbine.power_W - C.compressor.power_W);
C.generator.shaft_power_W = C.generator.electric_power_W / ...
    C.generator.eta_calculated;
C.rotor.inertia_kg_m2 = 0.5;
end
```

- [ ] **Step 4: Run the constants test and verify GREEN**

Run the command from Step 2 again. Expected: no assertion failure.

- [ ] **Step 5: Write the failing model power-boundary test**

The test must verify the calculation and require the model conversion block:

```matlab
function test_paper52_power_balance()
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
mdl = 'final_dynamic_24a';
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_system(mdl, 0));
gainPath = [mdl '/TAC/rotor/Generator_Electrical_to_Shaft'];
assert(getSimulinkBlockHandle(gainPath) > 0, ...
    'Missing explicit electrical-to-shaft generator load conversion.');
assert(strcmp(get_param(gainPath, 'Gain'), '1/paper54.generator.eta_calculated'));
end
```

- [ ] **Step 6: Run the model test and verify RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_paper52_power_balance"
```

Expected: failure `Missing explicit electrical-to-shaft generator load conversion.`

### Task 2: Correct the generator load boundary

**Files:**

- Create: `apply_paper52_generator_load.m`
- Modify: `start.m`
- Modify: `final_dynamic_24a.slx`
- Test: `tests/test_paper52_power_balance.m`

- [ ] **Step 1: Add traceable constants to `start.m`**

Append this line after the existing data loads:

```matlab
paper54 = paper54_constants();
```

- [ ] **Step 2: Implement the idempotent model edit**

`apply_paper52_generator_load.m` must load the model, add a Gain block named
`Generator_Electrical_to_Shaft` with gain
`1/paper54.generator.eta_calculated`, remove only the direct `Pload -> Sum`
line, reconnect `Pload -> Gain -> Sum`, update the diagram, and save the model.
It must refuse to overwrite an existing block with a different type or expression.

- [ ] **Step 3: Apply the edit and run the regression**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "apply_paper52_generator_load; addpath('tests'); test_paper52_power_balance"
```

Expected: `test_paper52_power_balance` completes without assertion failure.

- [ ] **Step 4: Record the model hash and block parameters**

Run `shasum -a 256 final_dynamic_24a.slx` and export the rotor block paths,
types, gains, sums, and integrator initial condition to
`output/paper54_reproduction/rotor_after_generator_conversion.txt`.

### Task 3: Measure the coupled baseline after the single power-boundary fix

**Files:**

- Create: `tests/audit_paper52_baseline.m`
- Create: `output/paper54_reproduction/baseline_after_generator_conversion.mat`

- [ ] **Step 1: Add a baseline audit without pass/fail relaxation**

Run `start`, assign constant `1000.21e3 W` electrical load and zero reactivity,
set the rotor initial condition to `55090 rpm`, simulate `500 s`, and save:

- initial/final/min/max rotor speed;
- compressor `Tin`, `Pin`, mass flow, `Tout`, `Pout`, and power;
- turbine power and instantaneous shaft-power residual;
- every property clamp or lookup-domain violation.

The audit test must fail unless final speed differs from `55090 rpm` by no more
than the resolution later obtained from the paper graph, all states are finite,
and there are no clamps or lookup-domain violations.

- [ ] **Step 2: Run the audit and preserve the expected failure**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); audit_paper52_baseline"
```

Expected at this stage: a quantified failure identifying the first component
boundary that prevents the Table 5.2 state. Do not modify another component
until this output exists.

### Task 4: Obtain a coupled paper-constrained steady operating point

**Files:**

- Create: `solve_paper52_operating_point.m`
- Create: `output/paper54_reproduction/paper52_steady_residuals.mat`
- Create only after passing: `paper52_operating_point.mat`
- Modify only when a sourced mismatch is identified: `final_dynamic_24a.slx`

- [ ] **Step 1: Inventory every continuous state and its derivative**

Use `operspec('final_dynamic_24a')` and `findop` reports to export state block
paths, initial values, steady-state flags, calculated derivatives, and bounds.
Fix `N_rpm=55090`, electrical load `1000.21e3 W`, and reactivity `0`.

- [ ] **Step 2: Constrain published component boundaries**

Add operating-point output constraints only for quantities directly published
in Table 5.2. Do not constrain unpublished internal temperatures or tune
unpublished coefficients.

- [ ] **Step 3: Run the steady-state search and classify residuals**

If `findop` converges, rerun a short simulation from the candidate state and
verify it remains stationary. If it does not converge, rank residuals by
normalized magnitude and trace the largest residual backward through the exact
active equations. Modify a parameter only when its source contradicts the
paper, then rerun this same step.

- [ ] **Step 4: Save the operating point only after verification**

`paper52_operating_point.mat` must contain the operating point, source-model
SHA-256, paper constraint struct, residual report, MATLAB release, and creation
date. The file must not be created for a nonconverged candidate.

### Task 5: Replace the synthetic compressor map with traceable data

**Files:**

- Modify: `data/provenance/compressor_map/source.md`
- Read: `data/provenance/compressor_map/nasa_tmx2269/digitized_points.csv`
- Read: `data/provenance/compressor_map/nasa_tmx2269/calibration.json`
- Create: `tmx2269_predict_speed_line.m`
- Create: `tests/test_tmx2269_speed_extension.m`
- Create: `build_traceable_compressor_lookup.m`
- Modify: `tests/test_compressor_map_provenance.m`
- Create: `output/paper54_reproduction/hexe_compressor_lookup_candidate.mat`
- Modify only after all gates pass: `hexe_compressor_lookup.mat`

- [ ] **Step 1: Write the failing bounded-speed-extension test**

The test must load the existing TM X-2269 points and require a function with this
interface:

```matlab
[flowOut, valueOut, metadata] = tmx2269_predict_speed_line( ...
    flow100, value100, targetSpeedRatio, quantity)
```

It must assert all of the following independently:

```matlab
% 100% identity: no interpolation and no value change.
[f1, pr1, m1] = tmx2269_predict_speed_line( ...
    f100, pr100, 1.0, "pressure_ratio");
assert(isequal(f1, f100));
assert(isequal(pr1, pr100));
assert(strcmp(m1.source_type, 'measurement'));

% 110% is allowed and is explicitly prediction, not measurement.
[f110, ~, m110] = tmx2269_predict_speed_line( ...
    f100, pr100, 1.10, "pressure_ratio");
assert(max(abs(f110 - 1.10*f100)) < 1e-12);
assert(strcmp(m110.source_type, 'similarity_prediction'));
assert(~contains(lower(m110.calibration_source), '5.4'));

% Any value above the audited 10% extension must fail.
didFail = false;
try
    tmx2269_predict_speed_line( ...
        f100, pr100, 1.1000001, "pressure_ratio");
catch ME
    didFail = strcmp(ME.identifier, ...
        'tmx2269:SpeedOutsideAuditedDomain');
end
assert(didFail);
```

For leave-one-out validation, sort the 90% measured line, use points 3--5,
calculate `phi=flow90/0.9`, linearly interpolate the 100% measured line at
`phi`, predict to 90%, and pin these fresh-source results:

```text
PR MAE 0.0228671267225498, max 0.0322228459018734
eta MAE 0.00441873824420987, max 0.00565366047760163
```

- [ ] **Step 2: Run the extension test and verify RED**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_tmx2269_speed_extension"
```

Expected: failure because `tmx2269_predict_speed_line` is undefined.

- [ ] **Step 3: Implement the minimal pure prediction function**

For `s=1`, return the exact input points and `source_type='measurement'`. For
`1<s<=1.10`, use `a=2/5`, `flowOut=s*flow100`,
`PRout=(1+s^2*(PR100.^a-1)).^(1/a)`, or unchanged efficiency, and mark
`source_type='similarity_prediction'`. Permit `s=0.9` only for the leave-one-out
test and mark it `source_type='validation_prediction'` plus
`model_use_approved=false`; the candidate builder must never write that line.
The function must reject unsupported quantities, nonfinite inputs, `s<0.9`,
and `s>1.10` with stable identifiers.

- [ ] **Step 4: Run the extension test and verify GREEN**

Run the command from Step 2. Expected: all identity, leave-one-out, provenance,
and bound assertions pass.

- [ ] **Step 5: Keep D-7487 input gaps explicit**

Run the 28-field audit before every candidate build. If any of the current 13
D-7487 target-geometry fields remains blank, the builder must not invoke D-7487
for the target compressor. The supplied air example remains a transcription
test only. The selected candidate source is TM X-2269 measured data, with
Table 5.2 used only for the documented He-Xe design-point transform.

- [ ] **Step 6: Reverify the source curves and hashes**

Rerun `tools/build_tmx2269_digitization.py` and the Python provenance tests.
Require both source-page hashes, all six speed lines for pressure ratio and
efficiency, and visual marker displacement no greater than two pixels. Do not
smooth or add points beyond interpolation between digitized measurements.

- [ ] **Step 7: Write a candidate-only builder and failing candidate test**

The builder must refuse `hexe_compressor_lookup.mat` as its output path. It may
write only a caller-supplied candidate path under
`output/paper54_reproduction/`. It must read only the TM X-2269 provenance
files, `tmx2269_similarity_transform`, and Table 5.2 constants; construct the
audited 90%--110% corrected-speed domain; write explicit valid-flow bounds per
speed line; and include source hashes, interpolation method, point categories,
formulas, and the `1.10` upper bound in structured metadata.

Before implementing the builder, extend `test_compressor_map_provenance` so it
fails on a missing candidate and still rejects the current activity map's
`surrogate`, `Gaussian`, and `paper-shape` metadata.

- [ ] **Step 8: Build and verify the candidate without touching the active map**

Record the active MAT hash before the build, build the candidate, and confirm
the active hash is unchanged. Candidate tests must verify corrected-coordinate
semantics, finite arrays, strict breakpoints, explicit valid-flow bounds,
Table 5.2 `PR`, `Tout`, and compressor power, and absence of Section 5.4 in all
calibration-source fields.

- [ ] **Step 9: Apply only after the joint gate passes**

Create a timestamped SHA-256 backup of the active MAT, copy the verified
candidate into place through a separate audited command, update both steady and
dynamic model diagrams, rerun the full map test suite, and confirm the saved SLX
hash is unchanged by diagram updates. If any gate fails, keep the active MAT
unchanged and return to the first failing boundary.

### Task 6: Encode the exact Section 5.4 schedules

**Files:**

- Create: `paper54_schedules.m`
- Create: `tests/test_paper54_schedules.m`
- Modify: `run_dynamic.m`

- [ ] **Step 1: Write failing schedule tests**

Require load transitions at `500`, `1500`, and `2500 s`; require reactivity
transitions at `500`, `2000`, `3500`, and `5000 s`; require left- and
right-continuous samples around every discontinuity.

- [ ] **Step 2: Implement the schedules from the thesis literals**

Use duplicate time-adjacent samples only to express steps for From Workspace.
The offset must use MATLAB `eps(time)` or a timeseries discontinuity mechanism,
not an invented physical delay such as `0.001 s`.

- [ ] **Step 3: Remove stale script claims**

Delete the `PR=1.92` claim, label `Pload_sched` as electrical output power, and
replace the erroneous `1000 s` recovery with `1500 s`.

- [ ] **Step 4: Run the schedule regression**

Expected: all transition times and values match the Section 5.4 constants.

### Task 7: Run and verify all Section 5.4 cases

**Files:**

- Create: `run_paper54_cases.m`
- Create: `tests/test_paper54_acceptance.m`
- Create: `output/paper54_reproduction/*.mat`

- [ ] **Step 1: Run the no-disturbance baseline from the verified operating point**

Require stable speed, finite states, zero property clamps, and zero lookup-domain
violations for the complete comparison duration.

- [ ] **Step 2: Run the +5% and -5% speed perturbations**

Require return to `55090 rpm` and compare the TAC power extrema with the values
digitized from Figures 5.27 and 5.28.

- [ ] **Step 3: Run the load case**

At each plateau, compare the steady speed with `55090`, `59655`, `55090`, and
`50610 rpm`. Derive numeric tolerances from the graph pixel scale and save the
calculation, rather than choosing a convenient percentage.

- [ ] **Step 4: Run the reactivity case**

Compare the steady speeds with `55090`, `56000`, `54300`, `55090`, and
`57790 rpm`, using the same graph-resolution rule. Verify reactor power and TAC
power directions and timing against Figures 5.32 to 5.34.

- [ ] **Step 5: Run the full regression suite**

Run all MATLAB tests in a fresh process. Any failed case returns the work to the
first failing component boundary; it must not be hidden by changing tolerances.

### Task 8: Correct documentation and produce the provenance audit

**Files:**

- Modify: `验收标准_论文5.4.md`
- Modify: `图5_34_对比分析_14000s.md`
- Create: `output/paper54_reproduction/复现结果与数据来源审计.md`

- [ ] **Step 1: Correct false historical conclusions**

Mark the old `PR=1.92` and “compressor table is the only root cause” statements
as superseded. Preserve their original run evidence and explain why the
conclusions changed.

- [ ] **Step 2: Generate a value-by-value provenance table**

For every active paper-reproduction parameter, list value, unit, category,
paper page/figure/table or calculation, active file, active block, and test.

- [ ] **Step 3: Record final hashes and test outputs**

Record hashes for the final SLX/MAT/scripts, MATLAB release, solver settings,
simulation completion times, acceptance errors, and any residual limitation.
Do not write “reproduced” unless every Task 7 test passes.

## Execution choice

The user explicitly requested continuous execution and did not request delegated
agents. Execute inline in this session with `executing-plans`, preserving a
checkpoint after each task. This directory is not a Git repository, so replace
commit checkpoints with SHA-256 manifests and never overwrite the existing
backup artifacts.
