function test_tmx2269_similarity()
% Verify the source-map transform without using Section 5.4 endpoints.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
C = paper54_constants();
S = tmx2269_similarity_transform();

assert(strcmp(S.source.report, 'NASA TM X-2269'));
assert(strcmp(S.source.working_fluid, 'argon'));
assert(abs(S.source.measured_design.flow_eq_kg_s - 0.69) < eps);
assert(abs(S.source.measured_design.PR - 2.28) <= 0.02);
assert(abs(S.source.measured_design.eta - 0.80) <= 0.005);

assert(abs(S.target.PR - C.compressor.PR) < 10 * eps(C.compressor.PR));
[cp1, gamma1] = HeXe_property_simulink( ...
    C.compressor.Tin_K, C.compressor.Pin_Pa);
T2s = C.compressor.Tin_K * C.compressor.PR^((gamma1 - 1) / gamma1);
cp2 = HeXe_property_simulink(T2s, C.compressor.Pout_Pa);
expectedEta = cp2 * (T2s - C.compressor.Tin_K) / ...
    (cp1 * (C.compressor.Tout_K - C.compressor.Tin_K));
assert(abs(S.target.eta - expectedEta) < 1e-12);

a = (gamma1 - 1) / gamma1;
transformedPR = (1 + S.head_scale * ...
    (S.source.measured_design.PR^a - 1))^(1 / a);
transformedEta = 1 - S.loss_scale * ...
    (1 - S.source.measured_design.eta);
assert(abs(transformedPR - C.compressor.PR) < 1e-12);
assert(abs(transformedEta - expectedEta) < 1e-12);

[speedRatio, flowRatio] = compressor_corrected_coordinates( ...
    C.N_rpm, S.target.mdot_model_kg_s, ...
    C.compressor.Tin_K, C.compressor.Pin_Pa, S.target);
assert(abs(speedRatio - 1) < 10 * eps);
assert(abs(flowRatio - 1) < 10 * eps);

[speedHot, flowHighPressure] = compressor_corrected_coordinates( ...
    C.N_rpm, S.target.mdot_model_kg_s, ...
    4 * C.compressor.Tin_K, 2 * C.compressor.Pin_Pa, S.target);
assert(abs(speedHot - 0.5) < 10 * eps);
assert(abs(flowHighPressure - 1.0) < 10 * eps);

assert(isequal(S.source.speed_ratio_domain, [0.5 1.0]));
paperMaximumRatio = 59655 / C.N_rpm;
assert(paperMaximumRatio > S.source.speed_ratio_domain(2));
assert(S.domain.paper54_requires_speed_extrapolation);
assert(S.domain.speed_extrapolation_approved);
assert(S.domain.speed_prediction_upper_bound == 1.10);
assert(strcmp(S.domain.speed_prediction_function, ...
    'tmx2269_predict_speed_line'));
assert(strcmp(S.domain.speed_prediction_source_type, ...
    'similarity_prediction'));
assert(~contains(lower(S.domain.speed_prediction_calibration_source), ...
    '5.4'));
assert(~contains(lower(S.provenance.calibration_inputs), '5.4'));
end
