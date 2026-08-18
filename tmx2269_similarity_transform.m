function S = tmx2269_similarity_transform()
%TMX2269_SIMILARITY_TRANSFORM Audited source and Table 5.2 scaling terms.
%
% This function does not extrapolate or build a compressor map. It keeps
% source measurements, Table 5.2 design calibration, and map-domain status
% separate so later builders cannot describe calculated points as NASA data.

root = fileparts(mfilename('fullpath'));
provenanceDir = fullfile(root, 'data', 'provenance', ...
    'compressor_map', 'nasa_tmx2269');
calibrationFile = fullfile(provenanceDir, 'calibration.json');
pointsFile = fullfile(provenanceDir, 'digitized_points.csv');
calibration = jsondecode(fileread(calibrationFile));
points = readtable(pointsFile, 'TextType', 'string');

S.source.report = calibration.source_report;
S.source.working_fluid = calibration.working_fluid;
S.source.pdf_sha256 = calibration.source_pdf_sha256;
S.source.points_file = relative_path(root, pointsFile);
S.source.points_sha256 = sha256_file(pointsFile);
S.source.speed_ratio_domain = [0.5 1.0];
S.source.molar_mass_kg_mol = 39.948e-3;
S.source.gamma_ideal = 5 / 3;

designFlow = calibration.published_design_conditions.flow_eq_kg_s;
S.source.measured_design.flow_eq_kg_s = designFlow;
S.source.measured_design.PR = interpolate_line( ...
    points, "pressure_ratio", 1.0, designFlow);
S.source.measured_design.eta = interpolate_line( ...
    points, "efficiency", 1.0, designFlow);
S.source.published_design_conditions = ...
    calibration.published_design_conditions;
S.source.predicted_design_markers = ...
    calibration.predicted_design_markers;

C = paper54_constants();
[cp1, gamma1] = HeXe_property_simulink( ...
    C.compressor.Tin_K, C.compressor.Pin_Pa);
T2s = C.compressor.Tin_K * C.compressor.PR^((gamma1 - 1) / gamma1);
cp2 = HeXe_property_simulink(T2s, C.compressor.Pout_Pa);
targetEta = cp2 * (T2s - C.compressor.Tin_K) / ...
    (cp1 * (C.compressor.Tout_K - C.compressor.Tin_K));

S.target.N_design_rpm = C.N_rpm;
S.target.mdot_model_kg_s = 12.04;
S.target.T_design_K = C.compressor.Tin_K;
S.target.P_design_Pa = C.compressor.Pin_Pa;
S.target.PR = C.compressor.PR;
S.target.eta = targetEta;
S.target.cp_in_J_kgK = cp1;
S.target.gamma_in = gamma1;
S.target.T_isentropic_K = T2s;
S.target.cp_isentropic_J_kgK = cp2;
S.target.mdot_category = 'existing model parameter';
S.target.mdot_paper_check = ...
    'Figure 5.25 shows an approximately 12 kg/s full-power plateau.';

exponent = (gamma1 - 1) / gamma1;
S.head_scale = (C.compressor.PR^exponent - 1) / ...
    (S.source.measured_design.PR^exponent - 1);
S.loss_scale = (1 - targetEta) / ...
    (1 - S.source.measured_design.eta);

S.domain.paper54_maximum_speed_ratio = 59655 / C.N_rpm;
S.domain.paper54_requires_speed_extrapolation = ...
    S.domain.paper54_maximum_speed_ratio > S.source.speed_ratio_domain(2);
S.domain.speed_extrapolation_approved = true;
S.domain.speed_prediction_lower_bound = 1.0;
S.domain.speed_prediction_upper_bound = 1.10;
S.domain.speed_prediction_function = 'tmx2269_predict_speed_line';
S.domain.speed_prediction_source_type = 'similarity_prediction';
S.domain.speed_prediction_calibration_source = [ ...
    'NASA TM X-2269 measured 100% speed line and similarity law only'];
S.provenance.calibration_inputs = ...
    'NASA TM X-2269 measured curves and Xu Chi Table 5.2 only';
S.provenance.head_transform = ...
    'PR_target=(1+head_scale*(PR_source^a-1))^(1/a)';
S.provenance.efficiency_transform = ...
    'eta_target=1-loss_scale*(1-eta_source)';
S.provenance.corrected_speed = ...
    '(N/N_design)/sqrt(T_in/T_design)';
S.provenance.corrected_flow = ...
    '(mdot/mdot_design)*sqrt(T_in/T_design)/(P_in/P_design)';
S.provenance.speed_prediction = [ ...
    'flow_s=s*flow_100; ' ...
    'PR_s=(1+s^2*(PR_100^(2/5)-1))^(5/2); eta_s=eta_100'];
end

function value = interpolate_line(points, quantity, speed, flow)
mask = points.quantity == quantity & ...
    abs(points.speed_ratio - speed) < 10 * eps(speed);
x = points.flow_eq_kg_s(mask);
y = points.value(mask);
[x, order] = sort(x);
y = y(order);
assert(flow >= x(1) && flow <= x(end), ...
    'Design flow lies outside the digitized source line.');
value = interp1(x, y, flow, 'linear');
end

function path = relative_path(root, absolutePath)
prefix = [root filesep];
assert(startsWith(absolutePath, prefix));
path = strrep(extractAfter(absolutePath, strlength(prefix)), filesep, '/');
end

function digest = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = java.nio.file.Files.readAllBytes(java.io.File(path).toPath());
digest = lower(reshape(dec2hex( ...
    typecast(md.digest(bytes), 'uint8'), 2).', 1, []));
end
