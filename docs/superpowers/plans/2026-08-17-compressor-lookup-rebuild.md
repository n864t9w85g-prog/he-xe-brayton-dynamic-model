# Compressor Lookup Rebuild Implementation Plan

> **Superseded diagnostic plan.** This plan produced the rejected
> `3.0-paper-shape` Gaussian surrogate. Xu Chi Figures 5.3 and 5.4 are model
> diagrams, not compressor performance maps. Do not execute this plan for paper
> reproduction; use `2026-08-17-paper54-dynamic-reproduction.md` Task 5.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the active compressor pressure-ratio and efficiency lookup surfaces so their curve families follow Xu Chi's Figure 5.3 and their design point reproduces the thesis steady state.

**Architecture:** Preserve the two existing normalized inputs and the `speed_bp × m_ratio_bp` orientation. Add one MATLAB test that rejects the current flat/kinked tables and verifies the paper design point, then add one reproducible MATLAB rebuild function that replaces only the lookup arrays and related MAT metadata.

**Tech Stack:** MATLAB R2025a, Simulink, MAT-file lookup data.

---

## File structure

- Create: `tests/test_compressor_lookup_paper_shape.m` — paper-anchor and curve-shape regression test.
- Create: `rebuild_hexe_compressor_lookup.m` — deterministic generator and MAT-file updater.
- Modify: `hexe_compressor_lookup.mat` — active compressor lookup values and metadata.
- Create: `output/compressor_map_rebuild/paper_shape_map.png` — visual verification artifact only.

The workspace is not a Git repository, so no commit task can be performed.

### Task 1: Add a regression test for the paper-style map

**Files:**

- Create: `tests/test_compressor_lookup_paper_shape.m`
- Test: `tests/test_compressor_lookup_paper_shape.m`

- [ ] **Step 1: Write the failing test**

```matlab
function test_compressor_lookup_paper_shape(mat_path)
if nargin == 0
    root = fileparts(fileparts(mfilename('fullpath')));
    mat_path = fullfile(root, 'hexe_compressor_lookup.mat');
end

S = load(mat_path, 'speed_bp', 'm_ratio_bp', 'PR_table', 'ETAT_table', ...
    'T_in_design', 'P_in_design', 'T_out_design', 'P_out_design', ...
    'Power_design', 'mdot_design', 'cp_hexe', 'gamma_hexe');
speed = S.speed_bp(:);
flow = S.m_ratio_bp(:).';
assert(isequal(size(S.PR_table), [numel(speed), numel(flow)]));
assert(isequal(size(S.ETAT_table), size(S.PR_table)));

targetPR = 1.551 / 0.658;
targetEta = (targetPR^((S.gamma_hexe - 1) / S.gamma_hexe) - 1) / ...
    (S.T_out_design / S.T_in_design - 1);
pr = interp2(flow, speed, S.PR_table, 1, 1, 'linear');
eta = interp2(flow, speed, S.ETAT_table, 1, 1, 'linear');
assert(abs(pr - targetPR) < 1e-6, 'Paper pressure-ratio anchor is incorrect.');
assert(abs(eta - targetEta) < 1e-6, 'Paper efficiency anchor is incorrect.');

predictedTout = S.T_in_design * (1 + ...
    (pr^((S.gamma_hexe - 1) / S.gamma_hexe) - 1) / eta);
predictedPower = S.mdot_design * S.cp_hexe * (predictedTout - S.T_in_design);
assert(abs(predictedTout - S.T_out_design) < 1e-6, 'Design outlet temperature is inconsistent.');
assert(abs(predictedPower - S.Power_design) / S.Power_design < 5e-3, ...
    'Design compressor power is inconsistent.');

previousPeakFlow = -inf;
for i = 1:numel(speed)
    prLine = S.PR_table(i, :);
    etaLine = S.ETAT_table(i, :);
    [~, prPeak] = max(prLine);
    [~, etaPeak] = max(etaLine);
    assert(prPeak > 1 && prPeak < numel(flow), ...
        'PR line at N/Ndesign=%.3f has no interior peak.', speed(i));
    assert(etaPeak > 1 && etaPeak < numel(flow), ...
        'Efficiency line at N/Ndesign=%.3f has no interior peak.', speed(i));
    assert(all(diff(prLine(1:prPeak)) > 0) && all(diff(prLine(prPeak:end)) < 0), ...
        'PR line at N/Ndesign=%.3f is not a smooth one-peak curve.', speed(i));
    assert(all(diff(etaLine(1:etaPeak)) > 0) && all(diff(etaLine(etaPeak:end)) < 0), ...
        'Efficiency line at N/Ndesign=%.3f is not a smooth one-peak curve.', speed(i));
    assert(flow(etaPeak) >= previousPeakFlow, ...
        'Efficiency peak flow does not move right as speed increases.');
    previousPeakFlow = flow(etaPeak);
end
fprintf('PASS paper anchors and Fig. 5.3 curve-family shape: %s\\n', mat_path);
end
```

- [ ] **Step 2: Run the test and confirm it fails on the current data**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_compressor_lookup_paper_shape('hexe_compressor_lookup.mat')"
```

Expected: failure stating that at least one PR or efficiency speed line has no interior peak or is not a smooth one-peak curve.

### Task 2: Build and apply the smooth paper-anchored lookup surfaces

**Files:**

- Create: `rebuild_hexe_compressor_lookup.m`
- Modify: `hexe_compressor_lookup.mat`
- Test: `tests/test_compressor_lookup_paper_shape.m`

- [ ] **Step 1: Write the rebuild function**

```matlab
function rebuild_hexe_compressor_lookup(output_mat)
if nargin == 0
    output_mat = fullfile(fileparts(mfilename('fullpath')), 'hexe_compressor_lookup.mat');
end

if isfile(output_mat)
    backup_mat = [output_mat '.pre_paper_shape.bak'];
    if ~isfile(backup_mat)
        copyfile(output_mat, backup_mat);
    end
end
S = load(output_mat);

speed = S.speed_bp(:);
flow = S.m_ratio_bp(:).';
targetPR = 1.551 / 0.658;
targetEta = (targetPR^((S.gamma_hexe - 1) / S.gamma_hexe) - 1) / ...
    (601.90 / 405.16 - 1);
PR = zeros(numel(speed), numel(flow));
ETA = zeros(size(PR));

for i = 1:numel(speed)
    s = speed(i);
    [~, peakIndex] = min(abs(flow - (0.25 + 0.75 * s)));
    peakFlow = flow(peakIndex);
    prBase = 1 + 0.02 * s^2;
    prPeak = 1 + (targetPR - 1) * s^2;
    prWidth = 0.20 + 0.30 * s;
    prShape = exp(-((flow - peakFlow) / prWidth).^2);
    PR(i, :) = prBase + (prPeak - prBase) * prShape;

    etaFloor = 0.18 + 0.08 * s;
    etaPeak = targetEta - 0.30 * (1 - s)^2 - 0.02 * max(s - 1, 0)^2;
    etaWidth = 0.23 + 0.20 * s;
    etaShape = exp(-((flow - peakFlow) / etaWidth).^2);
    ETA(i, :) = etaFloor + (etaPeak - etaFloor) * etaShape;
end

S.PR_table = PR;
S.ETAT_table = ETA;
S.N_design = 55090;
S.mdot_design = 12.04;
S.T_in_design = 405.16;
S.P_in_design = 658000;
S.PR_design = targetPR;
S.eta_design = targetEta;
S.T_out_design = 601.90;
S.P_out_design = 1551000;
S.Power_design = 1231600;
S.reference = ['Xu Chi (2022), Fig. 5.3, Table 5.2, and Sec. 5.3.1; ' ...
    'off-design lines are smooth paper-shape surrogates.'];
S.description = ['He-Xe compressor map v3.0. Two normalized lookup surfaces ' ...
    'anchored to Xu Chi thesis steady-state compressor data.'];
S.version = '3.0-paper-shape';
S.date = datestr(now, 'yyyy-mm-dd');
save(output_mat, '-struct', 'S');
end
```

- [ ] **Step 2: Run the rebuild function**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "rebuild_hexe_compressor_lookup('hexe_compressor_lookup.mat')"
```

Expected: `hexe_compressor_lookup.mat.pre_paper_shape.bak` is created once and the active MAT file is updated.

- [ ] **Step 3: Run the regression test and confirm it passes**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_compressor_lookup_paper_shape('hexe_compressor_lookup.mat')"
```

Expected: `PASS paper anchors and Fig. 5.3 curve-family shape`.

### Task 3: Verify the active Simulink module and visual curve family

**Files:**

- Modify: `hexe_compressor_lookup.mat`
- Create: `output/compressor_map_rebuild/paper_shape_map.png`
- Test: `tests/test_compressor_lookup_paper_shape.m`

- [ ] **Step 1: Check the two active Lookup Table bindings and update the model**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "start; load_system('final_steady_24a'); assert(strcmp(get_param('final_steady_24a/TAC/Compressor/2-D Lookup Table3','Table'),'PR_table')); assert(strcmp(get_param('final_steady_24a/TAC/Compressor/2-D Lookup Table1','Table'),'ETAT_table')); set_param('final_steady_24a','SimulationCommand','update'); close_system('final_steady_24a',0); disp('PASS active compressor Lookup Table bindings and model update')"
```

Expected: `PASS active compressor Lookup Table bindings and model update` with no model-update error.

- [ ] **Step 2: Render the two speed-line families for visual inspection**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "S=load('hexe_compressor_lookup.mat'); f=figure('Visible','off','Position',[100 100 1200 500]); tiledlayout(1,2); nexttile; plot(S.m_ratio_bp,S.PR_table','LineWidth',1.5); grid on; xlabel('m/m_{design}'); ylabel('Pressure ratio'); title('Compressor pressure-ratio curves'); nexttile; plot(S.m_ratio_bp,S.ETAT_table','LineWidth',1.5); grid on; xlabel('m/m_{design}'); ylabel('Isentropic efficiency'); title('Compressor efficiency curves'); exportgraphics(f,'output/compressor_map_rebuild/paper_shape_map.png','Resolution',180); close(f)"
```

Expected: each subplot shows smooth, non-flat speed-line families; the PR curves rise and fall, while efficiency curves are single arches.

- [ ] **Step 3: Run the final regression test after the model check**

Run:

```bash
/Applications/MATLAB_R2025a.app/bin/matlab -batch "addpath('tests'); test_compressor_lookup_paper_shape('hexe_compressor_lookup.mat')"
```

Expected: `PASS paper anchors and Fig. 5.3 curve-family shape`.
