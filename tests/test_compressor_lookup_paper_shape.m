function test_compressor_lookup_paper_shape(mat_path)
% Historical diagnostic-shape test only; not a paper-provenance acceptance.

if nargin == 0
    root = fileparts(fileparts(mfilename('fullpath')));
    mat_path = fullfile(root, 'hexe_compressor_lookup.mat');
end

S = load(mat_path, 'speed_bp', 'm_ratio_bp', 'PR_table', 'ETAT_table', ...
    'T_in_design', 'T_out_design', 'Power_design', 'mdot_design', ...
    'cp_hexe', 'gamma_hexe');
speed = S.speed_bp(:);
flow = S.m_ratio_bp(:).';
assert(isequal(size(S.PR_table), [numel(speed), numel(flow)]));
assert(isequal(size(S.ETAT_table), size(S.PR_table)));

targetPR = 1.551 / 0.658;
targetEta = (targetPR^((S.gamma_hexe - 1) / S.gamma_hexe) - 1) / ...
    (S.T_out_design / S.T_in_design - 1);
pr = interp2(flow, speed, S.PR_table, 1, 1, 'linear');
eta = interp2(flow, speed, S.ETAT_table, 1, 1, 'linear');
assert(abs(pr - targetPR) < 1e-6, ...
    'Paper pressure-ratio anchor is incorrect.');
assert(abs(eta - targetEta) < 1e-6, ...
    'Paper efficiency anchor is incorrect.');

predictedTout = S.T_in_design * (1 + ...
    (pr^((S.gamma_hexe - 1) / S.gamma_hexe) - 1) / eta);
predictedPower = S.mdot_design * S.cp_hexe * ...
    (predictedTout - S.T_in_design);
assert(abs(predictedTout - S.T_out_design) < 1e-6, ...
    'Design outlet temperature is inconsistent.');
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
    assert(all(diff(prLine(1:prPeak)) > 0) && ...
        all(diff(prLine(prPeak:end)) < 0), ...
        'PR line at N/Ndesign=%.3f is not a smooth one-peak curve.', speed(i));
    assert(all(diff(etaLine(1:etaPeak)) > 0) && ...
        all(diff(etaLine(etaPeak:end)) < 0), ...
        'Efficiency line at N/Ndesign=%.3f is not a smooth one-peak curve.', speed(i));
    assert(flow(etaPeak) >= previousPeakFlow, ...
        'Efficiency peak flow does not move right as speed increases.');
    previousPeakFlow = flow(etaPeak);
end

fprintf('PASS paper anchors and Fig. 5.3 curve-family shape: %s\n', mat_path);
end
