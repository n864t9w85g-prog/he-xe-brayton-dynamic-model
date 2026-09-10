# Pressure algebraic-closure candidate implementation plan

> For agentic workers: use executing-plans, inline in this session. Tasks use checkbox tracking. The user-approved exploration location is tests/tmp; do not create a new worktree or change the active checkout.

**Goal:** Test the numerical pressure-closure candidate described in report §32.5 without changing the official model, tables, properties, thermal states or acceptance criteria.

**Architecture:** Read the immutable f8bcd83 snapshot. Run an exact-byte reference copy, then make a distinct candidate with official APIs. Replace only the pressure feed to recuperator input 4 with the algebraic solution of the existing loop. Keep the original pressure delay and its initial value as a disconnected-output witness; leave the flow delay active and unchanged.

**Tech stack:** MATLAB R2025a/Simulink API, existing signal manifest, raw Dataset logs, independent Python arithmetic/XML read-only verification.

## Approved design and safeguards

- Design reviewed in `docs/steady53_curve_recheck_20260828.md` §32.5; user then said “继续”. No new physics or calibration is authorized.
- Input snapshot SHA256: `0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391`.
- Protected manifest: `tmp/tp7d213f64_7fad_4bfa_b722_0771b21d9640/protected_after.csv`, 34 files. Check before/after each stage.
- Retain the Step0 archive and all failed evidence. No deletes, formal saves, source-runner changes or candidate promotion.
- Output folder: `tmp/pressure_closure_4FKFZS`.
- Numerical gate, not a thesis acceptance threshold: pressure loop residual below `1e-5 Pa` at the original pressure-signal timestamps, all logged data finite, complete blocking simulation, no property-domain warning.
- Do not equate pressure closure with paper curve reproduction.

## Task 1 — Reference and failing regression

- [x] Create `tests/run_pressure_closure_case.m`: mode `reference` copies only the snapshot SLX to `pressure_reference.slx`, loads the snapshot start script, logs the existing manifest plus the two original delay outputs, and saves raw logs/CSV. All cache/output paths stay below the run folder.
- [x] Compile with StopTime 500 and 14000 and read `CompiledSampleTime` for both delays, compressor lookup, and pressure outputs. Restore the requested stop time before simulation. Never assume auto resolves the same in the two cases.

```matlab
set_param(model,'StopTime',num2str(stopTime));
feval(char(model),[],[],[],'compile');
pressureTs=get_param(model+"/Unit Delay",'CompiledSampleTime');
flowTs=get_param(model+"/Unit Delay1",'CompiledSampleTime');
feval(char(model),[],[],[],'term');
out=sim(model,'CaptureErrors','on','ReturnWorkspaceOutputs','on');
assert(isempty(out.ErrorMessage)&&out.tout(end)==stopTime);
```

- [x] Run:
  `/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); run_pressure_closure_case('tmp/pressure_closure_4FKFZS','reference',500);"`
- [x] Create and run `tests/check_pressure_closure_run.py .../reference_500 --require-closed`. Expected RED: the fresh reference run has nonzero loop residual, not a file/import error.

```python
residual = compressor_outlet_P - (recuperator_cold_outlet_P + 8000)
assert max(abs(x) for x in residual) < 1e-5
```

Match pressure samples by their actual logged timestamps; do not linearly interpolate a delay output and call it a continuous pressure trajectory. Also compare the fresh 500 s pressure samples to the prior saved run.

## Task 2 — Minimal official-API candidate

- [x] Create `tests/patch_pressure_algebraic_candidate.m` only after the reference regression fails for the intended reason. It may operate only on `pressure_candidate` below the named tmp folder.
- [x] Assert all pressure-loss and map-input constants/wiring against the prior audit. Add a TAC Outport 7 carrying the existing Compressor output 1 (r). Add one root Fcn implementing the existing pressure equation:

```matlab
% H=12000, L=18000; h=.005158+.002579, l=.011605.
% q=(a*H+r*L)/(a-1), a=(1+r*l)/(1-h).
expr='((1+u(1)*0.011605)*12000+u(1)*18000*(1-0.007737))/(u(1)*0.011605+0.007737)';
add_block('simulink/Ports & Subsystems/Out1',model+"/TAC/PressureRatioDiagnostic",'Port','7');
add_line(model+"/TAC",'Compressor/1','PressureRatioDiagnostic/1');
add_block('simulink/User-Defined Functions/Fcn',model+"/PressureAlgebraicCandidate",'Expr',expr);
add_line(model,'TAC/7','PressureAlgebraicCandidate/1');
delete_line(model,'Unit Delay/1','recuperator/4');
add_line(model,'PressureAlgebraicCandidate/1','recuperator/4');
```

- [x] Compare full inventories: all old block dialog parameters, charts, solver settings and initial conditions identical; exactly two added blocks, three added edges and one removed edge. The original pressure delay input stays connected, output only observed. No new state, gain feedback, pressure target or property replacement.
- [x] Save only candidate, reopen, verify inventory again, compile. Stop on an unexpected structural difference.

## Task 3 — Candidate runs and stop conditions

- [x] Run candidate 500 s. Verify pressure residual below gate, unchanged map/flow recursion, states finite, no warning promoted to an error.
- [x] If it succeeds, run candidate 14000 s and the reference 14000 s with identical logging/configuration. Each run retains raw pressure logs, output MAT, timing and errors. Long duration is a warm steady validation, not the thesis cold-start experiment.
- [x] On property or simulation failure: retain evidence and stop adding changes. Do not adjust initial values, solver tolerances, table coordinates or physics to force success.

## Task 4 — Independent checks and report

- [x] Run the Python check against raw pressure timestamps, replay the original delay recurrence and independently calculate candidate q*. Verify all source/model/script hashes and all 34 protected files.
- [x] Compare candidate/reference at 500/14000 s for pressures, flows, temperatures, powers; disclose changes relative to Table 5.2 without promoting a calibrated metric to independent validation.
- [x] Append report §33 with exact paths, compiled times, numerical pass/fail, structural change set and unresolved limitations. Keep candidates in tmp; no commit or promotion of a formal model.
