function rebuild_hexe_compressor_lookup(output_mat)
% Rebuild the active compressor maps from the Xu Chi paper steady point.

if nargin == 0
    output_mat = fullfile(fileparts(mfilename('fullpath')), ...
        'hexe_compressor_lookup.mat');
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
    etaPeak = targetEta - 0.30 * (1 - s)^2 - ...
        0.02 * max(s - 1, 0)^2;
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
