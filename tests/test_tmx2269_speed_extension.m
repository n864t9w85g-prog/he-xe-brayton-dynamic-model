function test_tmx2269_speed_extension()
% Verify the bounded speed-line similarity rule against independent data.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
pointsFile = fullfile(root, 'data', 'provenance', 'compressor_map', ...
    'nasa_tmx2269', 'digitized_points.csv');
points = readtable(pointsFile, 'TextType', 'string');

[flow100PR, value100PR] = measured_line( ...
    points, "pressure_ratio", 1.0);
[flow100Eta, value100Eta] = measured_line( ...
    points, "efficiency", 1.0);

test_identity(flow100PR, value100PR);
test_upper_extension(flow100PR, value100PR, ...
    flow100Eta, value100Eta);
test_bounds(flow100PR, value100PR);
test_leave_one_out(points, flow100PR, value100PR, ...
    "pressure_ratio", 0.0228671267225498, 0.0322228459018734);
test_leave_one_out(points, flow100Eta, value100Eta, ...
    "efficiency", 0.00441873824420987, 0.00565366047760163);

fprintf('PASS TM X-2269 bounded speed extension and 90%% leave-one-out.\n');
end

function test_identity(flow100, value100)
[flowOut, valueOut, metadata] = tmx2269_predict_speed_line( ...
    flow100, value100, 1.0, "pressure_ratio");
assert(isequal(flowOut, flow100), ...
    'The 100%% line flow coordinates must remain byte-for-byte unchanged.');
assert(isequal(valueOut, value100), ...
    'The 100%% measured values must remain byte-for-byte unchanged.');
assert(strcmp(metadata.source_type, 'measurement'));
assert(metadata.model_use_approved);
assert(~contains(lower(metadata.calibration_source), '5.4'));
end

function test_upper_extension(flowPR, valuePR, flowEta, valueEta)
a = 2 / 5;
[flowOut, prOut, metadataPR] = tmx2269_predict_speed_line( ...
    flowPR, valuePR, 1.10, "pressure_ratio");
expectedPR = (1 + 1.10^2 * (valuePR.^a - 1)).^(1 / a);
assert(max(abs(flowOut - 1.10 * flowPR)) < 1e-12);
assert(max(abs(prOut - expectedPR)) < 1e-12);
assert(strcmp(metadataPR.source_type, 'similarity_prediction'));
assert(metadataPR.model_use_approved);

[flowOut, etaOut, metadataEta] = tmx2269_predict_speed_line( ...
    flowEta, valueEta, 1.10, "efficiency");
assert(max(abs(flowOut - 1.10 * flowEta)) < 1e-12);
assert(isequal(etaOut, valueEta), ...
    'Efficiency must remain unchanged under the selected similarity rule.');
assert(strcmp(metadataEta.source_type, 'similarity_prediction'));
assert(metadataEta.model_use_approved);
assert(~contains(lower(metadataEta.calibration_source), '5.4'));
end

function test_bounds(flow100, value100)
assert_identifier(@() tmx2269_predict_speed_line( ...
    flow100, value100, 1.1000001, "pressure_ratio"), ...
    'tmx2269:SpeedOutsideAuditedDomain');
assert_identifier(@() tmx2269_predict_speed_line( ...
    flow100, value100, 0.8999999, "pressure_ratio"), ...
    'tmx2269:SpeedOutsideAuditedDomain');
assert_identifier(@() tmx2269_predict_speed_line( ...
    flow100, value100, 1.05, "temperature"), ...
    'tmx2269:UnsupportedQuantity');
end

function test_leave_one_out(points, flow100, value100, quantity, ...
    expectedMAE, expectedMax)
[flow90, value90] = measured_line(points, quantity, 0.9);
indices = 3:5;
flowCoefficient = flow90(indices) / 0.9;
baseValues = interp1(flow100, value100, flowCoefficient, 'linear');
[predictedFlow, predictedValues, metadata] = ...
    tmx2269_predict_speed_line( ...
        flowCoefficient, baseValues, 0.9, quantity);
errors = predictedValues - value90(indices);

assert(max(abs(predictedFlow - flow90(indices))) < 1e-12);
assert(abs(mean(abs(errors)) - expectedMAE) < 1e-12, ...
    '%s leave-one-out MAE changed.', quantity);
assert(abs(max(abs(errors)) - expectedMax) < 1e-12, ...
    '%s leave-one-out maximum error changed.', quantity);
assert(strcmp(metadata.source_type, 'validation_prediction'));
assert(~metadata.model_use_approved, ...
    'The 90%% leave-one-out prediction must not enter the model map.');
assert(~contains(lower(metadata.calibration_source), '5.4'));
end

function [flow, value] = measured_line(points, quantity, speedRatio)
mask = points.quantity == quantity & ...
    abs(points.speed_ratio - speedRatio) < 10 * eps(speedRatio);
flow = points.flow_eq_kg_s(mask);
value = points.value(mask);
[flow, order] = sort(flow);
value = value(order);
assert(numel(flow) >= 5, ...
    'The measured %s %.0f%% line has too few points.', ...
    quantity, 100 * speedRatio);
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
