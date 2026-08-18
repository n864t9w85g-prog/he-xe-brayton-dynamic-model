function outputPath = build_traceable_compressor_lookup(outputPath)
%BUILD_TRACEABLE_COMPRESSOR_LOOKUP Build a candidate from audited source data.

root = fileparts(mfilename('fullpath'));
allowedDir = fullfile(root, 'output', 'paper54_reproduction');
activePath = fullfile(root, 'hexe_compressor_lookup.mat');
if nargin == 0
    outputPath = fullfile(allowedDir, ...
        'hexe_compressor_lookup_candidate.mat');
end
outputPath = canonical_path(outputPath);
allowedDir = canonical_path(allowedDir);
activePath = canonical_path(activePath);

if strcmp(outputPath, activePath)
    error('compressorMap:ActivePathForbidden', ...
        'The candidate builder cannot overwrite the active compressor MAT.');
end
allowedPrefix = [allowedDir filesep];
if ~startsWith(outputPath, allowedPrefix)
    error('compressorMap:CandidatePathRequired', ...
        'Candidate output must be inside %s.', allowedDir);
end
if ~isfolder(allowedDir)
    mkdir(allowedDir);
end

transform = tmx2269_similarity_transform();
pointsPath = fullfile(root, 'data', 'provenance', 'compressor_map', ...
    'nasa_tmx2269', 'digitized_points.csv');
calibrationPath = fullfile(root, 'data', 'provenance', ...
    'compressor_map', 'nasa_tmx2269', 'calibration.json');
points = readtable(pointsPath, 'TextType', 'string');

speed = [0.9, 1.0, 1.01:0.01:1.10];
sourceDesignFlow = transform.source.published_design_conditions.flow_eq_kg_s;
prFlow = cell(numel(speed), 1);
prValue = cell(numel(speed), 1);
etaFlow = cell(numel(speed), 1);
etaValue = cell(numel(speed), 1);
sourceTypes = cell(numel(speed), 1);
validBounds = zeros(numel(speed), 2);

[flow100PR, value100PR] = measured_line( ...
    points, "pressure_ratio", 1.0);
[flow100Eta, value100Eta] = measured_line( ...
    points, "efficiency", 1.0);

for i = 1:numel(speed)
    s = speed(i);
    if s < 1
        [prFlow{i}, prValue{i}] = measured_line( ...
            points, "pressure_ratio", s);
        [etaFlow{i}, etaValue{i}] = measured_line( ...
            points, "efficiency", s);
        sourceTypes{i} = 'measurement';
    elseif s == 1
        prFlow{i} = flow100PR;
        prValue{i} = value100PR;
        etaFlow{i} = flow100Eta;
        etaValue{i} = value100Eta;
        sourceTypes{i} = 'measurement';
    else
        [prFlow{i}, prValue{i}, prMetadata] = ...
            tmx2269_predict_speed_line( ...
                flow100PR, value100PR, s, "pressure_ratio");
        [etaFlow{i}, etaValue{i}, etaMetadata] = ...
            tmx2269_predict_speed_line( ...
                flow100Eta, value100Eta, s, "efficiency");
        assert(strcmp(prMetadata.source_type, 'similarity_prediction'));
        assert(strcmp(etaMetadata.source_type, 'similarity_prediction'));
        sourceTypes{i} = 'similarity_prediction';
    end

    prFlow{i} = prFlow{i} / sourceDesignFlow;
    etaFlow{i} = etaFlow{i} / sourceDesignFlow;
    validBounds(i, :) = [ ...
        max(prFlow{i}(1), etaFlow{i}(1)), ...
        min(prFlow{i}(end), etaFlow{i}(end))];
    assert(validBounds(i, 1) < validBounds(i, 2), ...
        'No common PR/efficiency flow domain at speed ratio %.3f.', s);
end

commonLow = max(validBounds(:, 1));
commonHigh = min(validBounds(:, 2));
assert(commonLow < 1 && commonHigh > 1, ...
    'Source curves do not enclose the Table 5.2 design flow coordinate.');

flow = 1.0;
for i = 1:numel(speed)
    flow = [flow; in_domain(prFlow{i}, commonLow, commonHigh); ...
        in_domain(etaFlow{i}, commonLow, commonHigh)]; %#ok<AGROW>
end
flow = unique(sort(flow(:))).';

sourcePR = zeros(numel(speed), numel(flow));
sourceEta = zeros(size(sourcePR));
for i = 1:numel(speed)
    sourcePR(i, :) = interp1( ...
        prFlow{i}, prValue{i}, flow, 'linear');
    sourceEta(i, :) = interp1( ...
        etaFlow{i}, etaValue{i}, flow, 'linear');
end
assert(all(isfinite(sourcePR), 'all') && all(isfinite(sourceEta), 'all'));

aTarget = (transform.target.gamma_in - 1) / transform.target.gamma_in;
targetPR = (1 + transform.head_scale * ...
    (sourcePR.^aTarget - 1)).^(1 / aTarget);
targetEta = 1 - transform.loss_scale * (1 - sourceEta);

C = paper54_constants();
S.speed_bp = speed;
S.m_ratio_bp = flow;
S.PR_table = targetPR;
S.ETAT_table = targetEta;
S.valid_flow_ratio_by_speed = validBounds;
S.common_valid_flow_ratio = [commonLow, commonHigh];
S.valid_mask = uint8(ones(size(targetPR)));
S.surge_m_ratio = validBounds(:, 1).';
S.choke_m_ratio = validBounds(:, 2).';

S.N_design = transform.target.N_design_rpm;
S.mdot_design = transform.target.mdot_model_kg_s;
S.T_in_design = transform.target.T_design_K;
S.P_in_design = transform.target.P_design_Pa;
S.T_out_design = C.compressor.Tout_K;
S.P_out_design = C.compressor.Pout_Pa;
S.Power_design = C.compressor.power_W;
S.PR_design = C.compressor.PR;
S.eta_design = transform.target.eta;
S.cp_hexe = transform.target.cp_in_J_kgK;
S.gamma_hexe = transform.target.gamma_in;

S.P_out_table = S.P_in_design * S.PR_table;
S.T_out_table = zeros(size(S.PR_table));
S.Power_table = zeros(size(S.PR_table));
for i = 1:size(S.PR_table, 1)
    for j = 1:size(S.PR_table, 2)
        pr = S.PR_table(i, j);
        eta = S.ETAT_table(i, j);
        T2s = S.T_in_design * pr^((S.gamma_hexe - 1) / S.gamma_hexe);
        cp2 = HeXe_property_simulink(T2s, S.P_in_design * pr);
        Tout = S.T_in_design + cp2 * (T2s - S.T_in_design) / ...
            (S.cp_hexe * eta);
        S.T_out_table(i, j) = Tout;
        S.Power_table(i, j) = S.mdot_design * flow(j) * ...
            S.cp_hexe * (Tout - S.T_in_design);
    end
end

S.coordinate_definition.speed = ...
    '(N/N_design)/sqrt(T_in/T_design)';
S.coordinate_definition.flow = ...
    ['(mdot/mdot_design)*sqrt(T_in/T_design)/' ...
     '(P_in/P_design)'];
S.coordinate_definition.outside_domain = ...
    'reject and log; endpoint clipping is not valid model data';

S.version = '4.0-nasa-tmx2269-candidate';
S.description = [ ...
    'Candidate He-Xe compressor map from digitized NASA TM X-2269 ' ...
    'measurements and bounded similarity predictions.'];
S.reference = [ ...
    'NASA TM X-2269 source measurements; Xu Chi Table 5.2 target ' ...
    'design transform.'];
S.simulink_usage = [ ...
    'Rows are corrected speed ratio; columns are corrected mass-flow ' ...
    'ratio. Candidate status requires external activation gate.'];

S.provenance.source_report = transform.source.report;
S.provenance.source_working_fluid = transform.source.working_fluid;
S.provenance.target_working_fluid = 'He-Xe';
S.provenance.source_pdf_file = ...
    'sources/NASA-TM-X-2269-Ball-Tysl-Weigel-1971.pdf';
S.provenance.source_pdf_sha256 = transform.source.pdf_sha256;
S.provenance.calibration_file = ...
    'data/provenance/compressor_map/nasa_tmx2269/calibration.json';
S.provenance.calibration_sha256 = sha256_file(calibrationPath);
S.provenance.raw_points_file = transform.source.points_file;
S.provenance.raw_points_sha256 = transform.source.points_sha256;
S.provenance.implementation_file = ...
    'build_traceable_compressor_lookup.m';
S.provenance.implementation_sha256 = ...
    sha256_file(fullfile(root, S.provenance.implementation_file));
S.provenance.source_types = sourceTypes;
S.provenance.calibration_inputs = ...
    'NASA TM X-2269 measurements and Xu Chi Table 5.2 only';
S.provenance.speed_prediction_function = ...
    transform.domain.speed_prediction_function;
S.provenance.speed_prediction_upper_bound = ...
    transform.domain.speed_prediction_upper_bound;
S.provenance.speed_prediction_formula = ...
    transform.provenance.speed_prediction;
S.provenance.source_to_target_head_formula = ...
    transform.provenance.head_transform;
S.provenance.source_to_target_efficiency_formula = ...
    transform.provenance.efficiency_transform;
S.provenance.interpolation = ...
    'linear between digitized points inside the common measured domain';
S.provenance.candidate_status = 'not active until all gates pass';

save(outputPath, '-struct', 'S', '-v7');
fprintf('WROTE traceable compressor candidate: %s\n', outputPath);
end

function values = in_domain(values, lowerBound, upperBound)
values = values(values >= lowerBound & values <= upperBound);
end

function [flow, value] = measured_line(points, quantity, speedRatio)
mask = points.quantity == quantity & ...
    abs(points.speed_ratio - speedRatio) < 10 * eps(speedRatio);
flow = points.flow_eq_kg_s(mask);
value = points.value(mask);
[flow, order] = sort(flow);
value = value(order);
assert(~isempty(flow), ...
    'Missing measured %s line at speed ratio %.3f.', quantity, speedRatio);
end

function path = canonical_path(path)
path = char(java.io.File(char(string(path))).getCanonicalPath());
end

function digest = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = java.nio.file.Files.readAllBytes(java.io.File(path).toPath());
digest = lower(reshape(dec2hex( ...
    typecast(md.digest(bytes), 'uint8'), 2).', 1, []));
end
