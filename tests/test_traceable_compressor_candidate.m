function test_traceable_compressor_candidate(candidatePath)
% Verify the candidate map before any active-MAT replacement.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
if nargin == 0
    candidatePath = fullfile(root, 'output', 'paper54_reproduction', ...
        'hexe_compressor_lookup_candidate.mat');
end
assert(isfile(candidatePath), ...
    'Traceable compressor candidate does not exist: %s', candidatePath);

S = load(candidatePath);
required = {'speed_bp', 'm_ratio_bp', 'PR_table', 'ETAT_table', ...
    'valid_flow_ratio_by_speed', 'coordinate_definition', 'provenance', ...
    'N_design', 'mdot_design', 'T_in_design', 'P_in_design', ...
    'T_out_design', 'P_out_design', 'Power_design'};
for k = 1:numel(required)
    assert(isfield(S, required{k}), ...
        'Candidate is missing required field %s.', required{k});
end

speed = S.speed_bp(:);
flow = S.m_ratio_bp(:).';
assert(all(isfinite(speed)) && all(diff(speed) > 0));
assert(all(isfinite(flow)) && all(diff(flow) > 0));
assert(abs(speed(1) - 0.9) < 10 * eps);
assert(abs(speed(end) - 1.10) < 10 * eps);
assert(any(abs(speed - 1.0) < 10 * eps));
assert(isequal(size(S.PR_table), [numel(speed), numel(flow)]));
assert(isequal(size(S.ETAT_table), size(S.PR_table)));
assert(all(isfinite(S.PR_table), 'all') && all(S.PR_table >= 1, 'all'));
assert(all(isfinite(S.ETAT_table), 'all') && ...
    all(S.ETAT_table > 0 & S.ETAT_table <= 1, 'all'));

bounds = S.valid_flow_ratio_by_speed;
assert(isequal(size(bounds), [numel(speed), 2]));
assert(all(flow >= max(bounds(:, 1)) - 1e-12));
assert(all(flow <= min(bounds(:, 2)) + 1e-12));
assert(strcmp(S.coordinate_definition.speed, ...
    '(N/N_design)/sqrt(T_in/T_design)'));
assert(strcmp(S.coordinate_definition.flow, ...
    ['(mdot/mdot_design)*sqrt(T_in/T_design)/' ...
     '(P_in/P_design)']));

C = paper54_constants();
X = tmx2269_similarity_transform();
pr = interp2(flow, speed, S.PR_table, 1, 1, 'linear');
eta = interp2(flow, speed, S.ETAT_table, 1, 1, 'linear');
assert(abs(pr - C.compressor.PR) < 1e-12, ...
    'Candidate does not preserve the Table 5.2 pressure ratio.');
assert(abs(eta - X.target.eta) < 1e-12, ...
    'Candidate does not preserve the property-consistent design efficiency.');

[cp1, gamma1] = HeXe_property_simulink( ...
    C.compressor.Tin_K, C.compressor.Pin_Pa);
T2s = C.compressor.Tin_K * pr^((gamma1 - 1) / gamma1);
cp2 = HeXe_property_simulink(T2s, C.compressor.Pout_Pa);
Tout = C.compressor.Tin_K + ...
    cp2 * (T2s - C.compressor.Tin_K) / (cp1 * eta);
power = S.mdot_design * cp1 * (Tout - C.compressor.Tin_K);
powerRoundoffBound = 0.005 * cp1 * ...
    (Tout - C.compressor.Tin_K);
assert(abs(Tout - C.compressor.Tout_K) < 1e-10);
assert(abs(C.compressor.Pin_Pa * pr - C.compressor.Pout_Pa) < 1e-8);
assert(abs(power - C.compressor.power_W) <= powerRoundoffBound, ...
    ['Candidate forced-point power differs by more than the documented ' ...
     '12.04 kg/s two-decimal rounding allowance.']);

assert(strcmp(S.provenance.source_report, 'NASA TM X-2269'));
assert(strcmp(S.provenance.source_working_fluid, 'argon'));
assert(strcmp(S.provenance.target_working_fluid, 'He-Xe'));
assert(strcmp(S.provenance.source_types{1}, 'measurement'));
assert(strcmp(S.provenance.source_types{2}, 'measurement'));
assert(all(strcmp(S.provenance.source_types(3:end), ...
    'similarity_prediction')));
assert(~contains(lower(jsonencode(S.provenance)), '5.4'));
assert_verified_file(root, S.provenance.source_pdf_file, ...
    S.provenance.source_pdf_sha256);
assert_verified_file(root, S.provenance.calibration_file, ...
    S.provenance.calibration_sha256);
assert_verified_file(root, S.provenance.raw_points_file, ...
    S.provenance.raw_points_sha256);
assert_verified_file(root, S.provenance.implementation_file, ...
    S.provenance.implementation_sha256);

assert_identifier(@() build_traceable_compressor_lookup( ...
    fullfile(root, 'hexe_compressor_lookup.mat')), ...
    'compressorMap:ActivePathForbidden');

fprintf('PASS traceable compressor candidate: %s\n', candidatePath);
end

function assert_verified_file(root, relativePath, expectedHash)
path = fullfile(root, char(string(relativePath)));
assert(isfile(path), 'Provenance file does not exist: %s', path);
actual = sha256_file(path);
assert(strcmpi(actual, char(string(expectedHash))), ...
    'Provenance hash mismatch for %s.', path);
end

function assert_identifier(callable, expectedIdentifier)
didFail = false;
try
    callable();
catch ME
    didFail = strcmp(ME.identifier, expectedIdentifier);
end
assert(didFail, 'Expected error identifier %s.', expectedIdentifier);
end

function digest = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = java.nio.file.Files.readAllBytes(java.io.File(path).toPath());
digest = lower(reshape(dec2hex( ...
    typecast(md.digest(bytes), 'uint8'), 2).', 1, []));
end
