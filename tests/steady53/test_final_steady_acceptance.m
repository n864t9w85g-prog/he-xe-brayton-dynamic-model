function tests = test_final_steady_acceptance
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
testCase.TestData.testFolder = fullfile(root, "tests", "steady53");
testCase.TestData.originalPath = path;
if bdIsLoaded("final_steady_24a")
    error("steady53:TestModelAlreadyLoaded", ...
        "Acceptance tests require final_steady_24a to be initially unloaded.");
end
addpath(testCase.TestData.testFolder);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testActualComponentSpeedIsPaperNominal(testCase)
model = "final_steady_24a";
modelPath = fullfile(testCase.TestData.root, model + ".slx");
wasLoaded = bdIsLoaded(model);
cleanup = onCleanup(@() closeTestOwnedModel(model, wasLoaded));
load_system(modelPath);

actual = str2double(get_param(model + "/TAC/Constant", "Value"));
compressorMap = load(fullfile(testCase.TestData.root, ...
    "hexe_compressor_lookup.mat"), "N_design", "speed_bp");
normalized = actual / compressorMap.N_design;

fprintf(1, ['TAC actual speed: %.15g rpm\n' ...
    'Compressor N_design: %.15g rpm\n' ...
    'Normalized compressor speed: %.15g\n' ...
    'Compressor speed breakpoint range: [%.15g, %.15g]\n'], ...
    actual, compressorMap.N_design, normalized, ...
    min(compressorMap.speed_bp), max(compressorMap.speed_bp));

verifyEqual(testCase, actual, 55090, "AbsTol", 1);
verifyGreaterThanOrEqual(testCase, normalized, ...
    min(compressorMap.speed_bp));
verifyLessThanOrEqual(testCase, normalized, ...
    max(compressorMap.speed_bp));
end

function testModelReaches14000WithoutPropertyOrSolverFailure(testCase)
model = "final_steady_24a";
modelPath = fullfile(testCase.TestData.root, model + ".slx");
result = run_final_steady_reachability(modelPath, 14000, false);

fprintf(1, ['14000 s run success: %d\n' ...
    'tFinal_s: %.17g\n' ...
    'errorId: %s\n' ...
    'warningIds: %s\n' ...
    'errorReport follows:\n%s\n'], ...
    result.success, result.tFinal_s, result.errorId, ...
    strjoin(result.warningIds, ", "), result.errorReport);

verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 14000, "AbsTol", 1e-9);
verifyEmpty(testCase, result.warningIds);
end

function testNominalCoupledModelMatchesSection531By500Seconds(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
result = run_steady53_case(modelPath, 500, true);
verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 500);

s = steady53_spec();
s.stopTime_s = 500;
s.finalWindow_s = [400 500];
audit = auditForRun(testCase.TestData.root, result, s);
report = evaluate_steady53(result.t, result.signals, audit, s);
evidenceRoot = fullfile(testCase.TestData.root, "tmp", "steady53", "task8");
stage = create_task8_evidence_stage( ...
    evidenceRoot, makeTask8RunId(), result, report, s);
published = publish_task8_evidence(stage);
fprintf(1, "Task 8 structured evidence: %s\n", published.rawMatPath);
fprintf(1, "Task 8 evidence manifest: %s\n", published.manifestPath);
fprintf(1, "Task 8 failures:\n%s\n", strjoin(report.failures, newline));
verifyTrue(testCase, report.pass, strjoin(report.failures, newline));
end

function audit = auditForRun(root, result, spec)
audit.warningIds = result.warningIds;
audit.lookup = lookupAudit(root, result.signals);
audit.property = propertyAudit(result);
audit.massClosureRel = massClosure(result.signals);
audit.states = result.states;
audit.signalDynamics = signalDynamicsAudit(result.signals, spec);
end

function entries = signalDynamicsAudit(signals, spec)
metadata = spec.signalMetadata;
count = height(metadata);
entries = repmat(struct( ...
    "name", "", ...
    "data", [], ...
    "kind", "", ...
    "scaleFloor", NaN, ...
    "constant", false), count, 1);
for index = 1:count
    entries(index) = dynamicsEntry( ...
        metadata.name(index), signals, metadata.kind(index), ...
        metadata.constant(index), metadata.scaleFloor(index));
end
end

function entry = dynamicsEntry(name, signals, kind, constant, scaleFloor)
entry = struct( ...
    "name", string(name), ...
    "data", signals.(string(name))(:), ...
    "kind", string(kind), ...
    "scaleFloor", double(scaleFloor), ...
    "constant", logical(constant));
end

function audit = lookupAudit(root, signals)
compressor = load(fullfile(root, "hexe_compressor_lookup.mat"), ...
    "speed_bp", "m_ratio_bp");
turbineFlow = load(fullfile(root, "turbine_table1.mat"), ...
    "bp_speed", "bp_er");
turbineEfficiency = load(fullfile(root, "turbine_table2.mat"), ...
    "bp_speed", "bp_mf");

audit = struct("name", {}, "inputMin", {}, "inputMax", {}, ...
    "bpMin", {}, "bpMax", {});
audit(end + 1) = margin("compressor_efficiency_speed", ...
    signals.compressor_lookup_speed_eff, compressor.speed_bp);
audit(end + 1) = margin("compressor_efficiency_flow", ...
    signals.compressor_lookup_flow_eff, compressor.m_ratio_bp);
audit(end + 1) = margin("compressor_pressure_ratio_speed", ...
    signals.compressor_lookup_speed_pr, compressor.speed_bp);
audit(end + 1) = margin("compressor_pressure_ratio_flow", ...
    signals.compressor_lookup_flow_pr, compressor.m_ratio_bp);
audit(end + 1) = margin("turbine_flow_expansion_ratio", ...
    signals.turbine_lookup_expansion_ratio, turbineFlow.bp_er);
audit(end + 1) = margin("turbine_flow_speed", ...
    signals.turbine_lookup_speed_flow, turbineFlow.bp_speed);
audit(end + 1) = margin("turbine_efficiency_mass_flow", ...
    signals.turbine_lookup_mass_flow, turbineEfficiency.bp_mf);
audit(end + 1) = margin("turbine_efficiency_speed", ...
    signals.turbine_lookup_speed_eff, turbineEfficiency.bp_speed);
end

function audit = margin(name, values, breakpoints)
audit = struct( ...
    "name", string(name), ...
    "inputMin", min(values), ...
    "inputMax", max(values), ...
    "bpMin", min(breakpoints), ...
    "bpMax", max(breakpoints));
end

function property = propertyAudit(result)
names = [ ...
    "turbine_inlet_T"
    "turbine_outlet_T"
    "compressor_inlet_T"
    "compressor_outlet_T"
    "recuperator_hot_outlet_T"
    "recuperator_cold_outlet_T"
    ];
hexe = zeros(0, 1);
for name = names.'
    hexe = [hexe; result.signals.(name)(:)]; %#ok<AGROW>
end
lithium = [result.signals.reactor_outlet_T(:); ...
    result.signals.reactor_inlet_T(:)];
for index = 1:numel(result.states)
    if result.states(index).fluid == "HeXe"
        hexe = [hexe; result.states(index).data(:)]; %#ok<AGROW>
    elseif result.states(index).fluid == "Lithium"
        lithium = [lithium; result.states(index).data(:)]; %#ok<AGROW>
    end
end
property = struct( ...
    "HeXeMin_K", min(hexe), ...
    "HeXeMax_K", max(hexe), ...
    "LithiumMin_K", min(lithium), ...
    "LithiumMax_K", max(lithium));
end

function value = massClosure(signals)
hexeNames = [ ...
    "hexe_mdot_turbine"
    "hexe_mdot_compressor"
    "hexe_mdot_ihx"
    "hexe_mdot_recup_hot"
    "hexe_mdot_recup_cold"
    ];
lithiumNames = ["lithium_mdot_reactor"; "lithium_mdot_ihx"];
value = max(groupClosure(signals, hexeNames), ...
    groupClosure(signals, lithiumNames));
end

function value = groupClosure(signals, names)
data = zeros(numel(signals.(names(1))), numel(names));
for index = 1:numel(names)
    data(:, index) = signals.(names(index))(:);
end
denominator = max(abs(mean(data, 2)), 1);
value = max((max(data, [], 2) - min(data, [], 2)) ./ denominator);
end

function runId = makeTask8RunId()
milliseconds = string(floor(posixtime(datetime("now", ...
    "TimeZone", "UTC")) * 1000));
uuid = replace(string(char(java.util.UUID.randomUUID())), "-", "");
runId = "run_" + milliseconds + "_" + uuid;
end

function closeTestOwnedModel(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
