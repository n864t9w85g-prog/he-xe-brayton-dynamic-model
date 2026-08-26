function analysis = analyze_task8_h1a_readonly(options)
%ANALYZE_TASK8_H1A_READONLY Offline Eq. 2.28 phi-bar sensitivity audit.
%   This exploration-only function reads one immutable Task 8 evidence MAT,
%   recomputes the active turbine baseline, and reports both approved H1a
%   numerical candidates. It never loads, simulates, edits, or saves a model.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = defaultConfig(root);
if nargin > 0
    config = applyTestOnlyOptions(config, options);
end

inputMat = requireAbsolutePath(config.inputMat, "inputMat");
turbineTableMat = requireAbsolutePath( ...
    config.turbineTableMat, "turbineTableMat");
modelPath = requireAbsolutePath(config.modelPath, "modelPath");
outputDir = requireAbsolutePath(config.outputDir, "outputDir");
validateRunId(config.runId);
validateExpectedHash(config.expectedInputSha256, ...
    "expectedInputSha256");
validateExpectedHash(config.expectedTurbineTableSha256, ...
    "expectedTurbineTableSha256");
validateExpectedHash(config.expectedModelSha256, ...
    "expectedModelSha256");
if ~isa(config.integralFunction, "function_handle")
    error("steady53:H1aInvalidOptions", ...
        "integralFunction must be a function handle.");
end
if ~isa(config.outputFailureHook, "function_handle")
    error("steady53:H1aInvalidOptions", ...
        "outputFailureHook must be a function handle.");
end
validateS2PropertyContract(config);

% The fixed input hash is the first content gate. No output directory or
% result file is created before this check succeeds.
inputMatSha256 = sha256File(inputMat);
if inputMatSha256 ~= lower(string(config.expectedInputSha256))
    error("steady53:H1aInputHashMismatch", ...
        "Input MAT hash mismatch for '%s'.", inputMat);
end

turbineTableSha256 = sha256File(turbineTableMat);
if turbineTableSha256 ~= lower(string( ...
        config.expectedTurbineTableSha256))
    error("steady53:H1aTurbineTableHashMismatch", ...
        "Turbine table hash mismatch for '%s'.", turbineTableMat);
end
modelSha256 = sha256File(modelPath);
if modelSha256 ~= lower(string(config.expectedModelSha256))
    error("steady53:H1aModelHashMismatch", ...
        "Formal model hash mismatch for '%s'.", modelPath);
end
formalPropertyPath = requireAbsolutePath( ...
    config.formalPropertyPath, "formalPropertyPath");
formalPropertySha256 = sha256File(formalPropertyPath);
if formalPropertySha256 ~= lower(string( ...
        config.expectedFormalPropertySha256))
    error("steady53:H1aFormalPropertyHashMismatch", ...
        "Formal property source hash mismatch for '%s'.", ...
        formalPropertyPath);
end
s2PropertySourcePath = requireAbsolutePath( ...
    config.s2PropertySourcePath, "s2PropertySourcePath");
s2PropertySourceSha256 = sha256File(s2PropertySourcePath);
if s2PropertySourceSha256 ~= lower(string( ...
        config.expectedS2PropertySourceSha256))
    error("steady53:H1aS2PropertyHashMismatch", ...
        "S2 property source hash mismatch for '%s'.", ...
        s2PropertySourcePath);
end
[s2EvidencePaths, s2EvidenceHashes] = ...
    validateS2Evidence(config);

csvPath = fullfile(outputDir, "h1a_sensitivity.csv");
summaryPath = fullfile(outputDir, "h1a_summary.txt");
if isfolder(outputDir) || isfile(outputDir) || ...
        isfile(csvPath) || isfile(summaryPath)
    error("steady53:H1aOutputExists", ...
        "H1a output target already exists: '%s'.", outputDir);
end

originalPath = path;
originalWarnings = warning;
loadedBlockDiagramsBefore = loadedBlockDiagrams();
environmentCleanup = onCleanup(@() restoreEnvironment( ...
    originalPath, originalWarnings));
addpath(root);
warning("error", "HeXe:T_lo");
warning("error", "HeXe:T_hi");

payload = load(inputMat, "result", "report", "spec");
[inputs, finalWindow_s] = validateAndExtractPayload(payload, ...
    config.expectedModelSha256);

tablePayload = load(turbineTableMat, ...
    "bp_mf", "bp_speed", "table_eff");
validateTurbineTable(tablePayload);
inputs.eta = interpolateCurrentTurbineEfficiency(tablePayload, ...
    inputs.lookupMassFlow_kg_s, inputs.lookupSpeed_rpm);

settings = struct( ...
    "rootAbsResidualTolerance_K", 1e-9, ...
    "rootTolX_K", 1e-12, ...
    "rootMaxIterations", 1000, ...
    "rootMaxFunctionEvaluations", 5000, ...
    "s2IntegralRelTol", 1e-8, ...
    "s2IntegralAbsTol", 1e-10, ...
    "integralFunction", config.integralFunction, ...
    "s2PropertyFunction", config.s2PropertyFunction, ...
    "s2PropertyVariant", string(config.s2PropertyVariant));

resetPropertyState();
[inputs.cp1_J_kgK, inputs.gamma1] = propertyCpGamma( ...
    inputs.T1_K, inputs.P1_Pa);
inputs.baselinePhi = 1 - 1 / inputs.gamma1;
validatePhi(inputs.baselinePhi, inputs.T1_K, ...
    inputs.P1_Pa, inputs.gamma1);
settings.rootBracketLow_K = ...
    inputs.T1_K / inputs.expansionRatio;
settings.rootBracketHigh_K = inputs.T1_K;
if ~validFiniteRealScalar(settings.rootBracketLow_K) || ...
        settings.rootBracketLow_K <= 0 || ...
        settings.rootBracketLow_K >= settings.rootBracketHigh_K
    error("steady53:H1aInvalidInput", ...
        "The Eq. 2.28 root bracket [T1/pi,T1] is invalid.");
end
% Validate the property/phi domain at both derived bracket endpoints before
% either candidate root solve. S2 validates every interior quadrature point.
phiAt(settings.rootBracketLow_K, inputs.P2_Pa);
phiAt(settings.rootBracketHigh_K, inputs.P2_Pa);
resetPropertyState();
inputs.baselineT2s_K = inputs.T1_K * ...
    inputs.expansionRatio^(-inputs.baselinePhi);
[inputs.cp2_J_kgK, inputs.gamma2s] = propertyCpGamma( ...
    inputs.baselineT2s_K, inputs.P2_Pa);
baselineT2_K = turbineOutletTemperature(inputs, ...
    inputs.baselineT2s_K);
baselineReproductionResidual_K = ...
    baselineT2_K - inputs.recordedTerminalT2_K;
if abs(baselineReproductionResidual_K) > 1e-9
    error("steady53:H1aBaselineMismatch", ...
        "The immutable evidence does not reproduce the active single-point turbine equation within 1e-9 K.");
end

resetPropertyState();
s1Function = @(candidateT2s) s1RootResidual( ...
    candidateT2s, inputs);
[s1T2s_K, s1RootResidual_K] = solveBracketedRoot( ...
    s1Function, settings);
s1PhiBar = s1PhiAverage(s1T2s_K, inputs);
s1T2_K = turbineOutletTemperature(inputs, s1T2s_K);
settings.s1PhiBar = s1PhiBar;
settings.s1T2s_K = s1T2s_K;
settings.s1T2_K = s1T2_K;
settings.s1RootResidual_K = s1RootResidual_K;

resetPropertyState();
s2Function = @(candidateT2s) s2RootResidual( ...
    candidateT2s, inputs, settings);
[s2T2s_K, s2RootResidual_K] = solveBracketedRoot( ...
    s2Function, settings);
s2PhiBar = s2PhiAverage(s2T2s_K, inputs, settings);
s2T2_K = turbineOutletTemperature(inputs, s2T2s_K);
s2PathAudit = auditResolvedS2Path(s2T2s_K, inputs, settings);

baselineRootResidual_K = inputs.baselineT2s_K - ...
    inputs.T1_K * inputs.expansionRatio^(-inputs.baselinePhi);
sensitivity = makeSensitivityTable(inputs, settings, ...
    [inputs.baselinePhi; s1PhiBar; s2PhiBar], ...
    [inputs.baselineT2s_K; s1T2s_K; s2T2s_K], ...
    [baselineT2_K; s1T2_K; s2T2_K], ...
    [baselineRootResidual_K; s1RootResidual_K; s2RootResidual_K]);

baselineGap_K = inputs.targetT2_K - baselineT2_K;
candidateDelta_K = sensitivity.deltaT2FromBaseline_K(2:3);
sameDirection = sign(candidateDelta_K) == sign(baselineGap_K);
h1aNumericallySufficient = any(sameDirection & ...
    abs(candidateDelta_K) >= abs(baselineGap_K));
conclusion = h1aConclusion(h1aNumericallySufficient, ...
    baselineGap_K, sensitivity);

assertReadOnlyState(modelPath, modelSha256, ...
    turbineTableMat, turbineTableSha256, formalPropertyPath, ...
    formalPropertySha256, s2PropertySourcePath, ...
    s2PropertySourceSha256, s2EvidencePaths, s2EvidenceHashes, ...
    loadedBlockDiagramsBefore);
summaryText = makeSummaryText(config, inputMat, inputMatSha256, ...
    turbineTableMat, turbineTableSha256, modelPath, modelSha256, ...
    formalPropertyPath, formalPropertySha256, ...
    s2PropertySourcePath, s2PropertySourceSha256, ...
    s2EvidencePaths, s2EvidenceHashes, finalWindow_s, inputs, ...
    settings, sensitivity, s2PathAudit, ...
    baselineReproductionResidual_K, conclusion, ...
    loadedBlockDiagramsBefore);
assertReadOnlyState(modelPath, modelSha256, ...
    turbineTableMat, turbineTableSha256, formalPropertyPath, ...
    formalPropertySha256, s2PropertySourcePath, ...
    s2PropertySourceSha256, s2EvidencePaths, s2EvidenceHashes, ...
    loadedBlockDiagramsBefore);
loadedBlockDiagramsAfter = loadedBlockDiagrams();

restoreEnvironment(originalPath, originalWarnings);
clear environmentCleanup
pathRestored = strcmp(path, originalPath);
warningStateRestored = isequaln(warning, originalWarnings);
if ~pathRestored || ~warningStateRestored
    error("steady53:H1aEnvironmentRestoreFailed", ...
        "Path or warning state was not restored.");
end

% Publication is deliberately the final fallible external-state action.
% All model/hash/environment checks have completed before this transaction.
[csvSha256, summarySha256] = writeOutputs(outputDir, ...
    sensitivity, summaryText, config.outputFailureHook);

analysis = struct();
analysis.runId = string(config.runId);
analysis.inputMat = inputMat;
analysis.inputMatSha256 = inputMatSha256;
analysis.turbineTableMat = turbineTableMat;
analysis.turbineTableSha256 = turbineTableSha256;
analysis.modelPath = modelPath;
analysis.modelSha256 = modelSha256;
analysis.outputDir = outputDir;
analysis.csvPath = string(csvPath);
analysis.summaryPath = string(summaryPath);
analysis.csvSha256 = csvSha256;
analysis.summarySha256 = summarySha256;
analysis.finalWindow_s = finalWindow_s;
analysis.inputs = inputs;
analysis.settings = settings;
analysis.sensitivity = sensitivity;
analysis.baselineReproductionResidual_K = ...
    baselineReproductionResidual_K;
analysis.h1aNumericallySufficient = h1aNumericallySufficient;
analysis.conclusion = conclusion;
analysis.scope = struct("s2PhiVariant", ...
    string(config.s2PropertyVariant), ...
    "s2PhiScope", "only H1a-S2 phi integrand", ...
    "etaCp1Cp2HeldFixed", true);
analysis.s2 = struct("integrationCompleted", true, ...
    "rootConverged", true, "phiBar", s2PhiBar, ...
    "T2s_K", s2T2s_K, "T2_K", s2T2_K, ...
    "rootResidual_K", s2RootResidual_K, ...
    "pathAudit", s2PathAudit);
analysis.s2PropertySourcePath = s2PropertySourcePath;
analysis.s2PropertySourceSha256 = s2PropertySourceSha256;
analysis.formalPropertyPath = formalPropertyPath;
analysis.formalPropertySha256 = formalPropertySha256;
analysis.s2EvidencePaths = s2EvidencePaths;
analysis.s2EvidenceHashes = s2EvidenceHashes;
analysis.loadedBlockDiagramsBefore = loadedBlockDiagramsBefore;
analysis.loadedBlockDiagramsAfter = loadedBlockDiagramsAfter;
analysis.h1bExecuted = false;
analysis.modelModified = false;
analysis.authorizesRepair = false;
analysis.formalModelPromotion = false;
analysis.slxLoadedOrSimulated = false;
analysis.pathRestored = pathRestored;
analysis.warningStateRestored = warningStateRestored;
analysis.persistentStateAfter = "cleared_uninitialized";
end

function config = defaultConfig(root)
runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
config = struct();
config.testOnly = false;
config.runId = runId;
config.inputMat = string(fullfile(root, "tmp", "steady53", "task8", ...
    runId, "nominal_500_report.mat"));
config.expectedInputSha256 = ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b";
config.turbineTableMat = string(fullfile(root, "turbine_table2.mat"));
config.expectedTurbineTableSha256 = ...
    "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33";
config.modelPath = string(fullfile(root, "final_steady_24a.slx"));
config.expectedModelSha256 = ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d";
config.outputDir = string(fullfile(root, "tmp", "steady53", ...
    "task8_root_cause", "h1a", runId));
config.integralFunction = @integral;
config.outputFailureHook = @noOutputFailure;
config.formalPropertyPath = string(fullfile(root, ...
    "HeXe_property_simulink.m"));
config.expectedFormalPropertySha256 = ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2";
config.s2PropertyFunction = @HeXe_property_simulink;
config.s2PropertyVariant = "baseline";
config.s2PropertySourcePath = string(fullfile(root, ...
    "HeXe_property_simulink.m"));
config.expectedS2PropertySourceSha256 = ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2";
config.s2EvidenceCsvPath = "";
config.expectedS2EvidenceCsvSha256 = "";
config.s2EvidenceTxtPath = "";
config.expectedS2EvidenceTxtSha256 = "";
end

function config = applyTestOnlyOptions(config, options)
if ~isstruct(options) || ~isscalar(options) || ...
        ~isfield(options, "testOnly") || ...
        ~isequal(options.testOnly, true)
    error("steady53:H1aInvalidOptions", ...
        "Non-default options require explicit testOnly=true.");
end

allowed = ["testOnly", "runId", "inputMat", ...
    "expectedInputSha256", "turbineTableMat", ...
    "expectedTurbineTableSha256", "modelPath", ...
    "expectedModelSha256", "outputDir", "integralFunction", ...
    "outputFailureHook", "formalPropertyPath", ...
    "expectedFormalPropertySha256", "s2PropertyFunction", ...
    "s2PropertyVariant", "s2PropertySourcePath", ...
    "expectedS2PropertySourceSha256", "s2EvidenceCsvPath", ...
    "expectedS2EvidenceCsvSha256", "s2EvidenceTxtPath", ...
    "expectedS2EvidenceTxtSha256"];
actual = string(fieldnames(options));
if any(~ismember(actual, allowed))
    error("steady53:H1aInvalidOptions", ...
        "Unknown test-only option.");
end
required = allowed;
if ~all(ismember(required, actual))
    error("steady53:H1aInvalidOptions", ...
        "Test-only options must state the complete override contract.");
end
for index = 1:numel(actual)
    config.(actual(index)) = options.(actual(index));
end
end

function validateS2PropertyContract(config)
if ~isa(config.s2PropertyFunction, "function_handle") || ...
        ~isscalar(string(config.s2PropertyVariant)) || ...
        ~ismember(string(config.s2PropertyVariant), ...
        ["baseline" "schemeA"])
    error("steady53:H1aInvalidOptions", ...
        "The S2 property evaluator contract is invalid.");
end
validateExpectedHash(config.expectedS2PropertySourceSha256, ...
    "expectedS2PropertySourceSha256");
if string(config.s2PropertyVariant) == "baseline"
    if string(config.s2EvidenceCsvPath) ~= "" || ...
            string(config.expectedS2EvidenceCsvSha256) ~= "" || ...
            string(config.s2EvidenceTxtPath) ~= "" || ...
            string(config.expectedS2EvidenceTxtSha256) ~= ""
        error("steady53:H1aInvalidOptions", ...
            "Baseline S2 must not claim counterfactual evidence.");
    end
    return
end
requireAbsolutePath(config.s2EvidenceCsvPath, "s2EvidenceCsvPath");
requireAbsolutePath(config.s2EvidenceTxtPath, "s2EvidenceTxtPath");
validateExpectedHash(config.expectedS2EvidenceCsvSha256, ...
    "expectedS2EvidenceCsvSha256");
validateExpectedHash(config.expectedS2EvidenceTxtSha256, ...
    "expectedS2EvidenceTxtSha256");
end

function [paths, hashes] = validateS2Evidence(config)
if string(config.s2PropertyVariant) == "baseline"
    paths = strings(0, 1);
    hashes = strings(0, 1);
    return
end
paths = [string(config.s2EvidenceCsvPath); ...
    string(config.s2EvidenceTxtPath)];
expected = lower([string(config.expectedS2EvidenceCsvSha256); ...
    string(config.expectedS2EvidenceTxtSha256)]);
hashes = strings(2, 1);
for index = 1:2
    hashes(index) = sha256File(paths(index));
end
if ~isequal(hashes, expected)
    error("steady53:H1aS2EvidenceHashMismatch", ...
        "Approved H2a evidence hash mismatch.");
end
end

function pathValue = requireAbsolutePath(value, label)
if ~(isstring(value) || ischar(value)) || ...
        ~isscalar(string(value)) || ismissing(string(value)) || ...
        strlength(string(value)) == 0 || ...
        ~startsWith(string(value), filesep)
    error("steady53:H1aInvalidOptions", ...
        "%s must be an absolute path.", label);
end
pathValue = string(value);
end

function validateRunId(value)
if ~(isstring(value) || ischar(value)) || ...
        ~isscalar(string(value)) || isempty(regexp(char(string(value)), ...
        '^run_[A-Za-z0-9_]+$', 'once'))
    error("steady53:H1aInvalidOptions", "Invalid runId.");
end
end

function validateExpectedHash(value, label)
if ~(isstring(value) || ischar(value)) || ...
        ~isscalar(string(value)) || isempty(regexp(char(string(value)), ...
        '^[0-9a-fA-F]{64}$', 'once'))
    error("steady53:H1aInvalidOptions", ...
        "%s must be a SHA-256 string.", label);
end
end

function [inputs, finalWindow_s] = validateAndExtractPayload( ...
        payload, expectedModelSha256)
if ~isstruct(payload) || ~all(isfield(payload, ...
        ["result", "report", "spec"])) || ...
        ~isstruct(payload.result) || ~isscalar(payload.result) || ...
        ~isstruct(payload.report) || ~isscalar(payload.report) || ...
        ~isstruct(payload.spec) || ~isscalar(payload.spec)
    invalidInput("Missing result, report, or spec payload.");
end
result = payload.result;
report = payload.report;
spec = payload.spec;
requiredResult = ["t", "signals", "modelHashBefore", ...
    "modelHashAfter"];
if ~all(isfield(result, requiredResult)) || ...
        ~isstruct(result.signals) || ~isscalar(result.signals)
    invalidInput("Missing required result fields.");
end

t = result.t;
if ~isnumeric(t) || ~isvector(t) || numel(t) < 2 || ...
        ~isreal(t) || any(~isfinite(t), "all") || ...
        any(diff(double(t(:))) <= 0)
    invalidInput("result.t must be finite, real, and strictly increasing.");
end
t = double(t(:));
if ~isfield(spec, "finalWindow_s") || ...
        ~isnumeric(spec.finalWindow_s) || ...
        numel(spec.finalWindow_s) ~= 2 || ...
        ~isreal(spec.finalWindow_s) || ...
        any(~isfinite(spec.finalWindow_s), "all")
    invalidInput("spec.finalWindow_s is invalid.");
end
finalWindow_s = double(spec.finalWindow_s(:).');
if finalWindow_s(1) >= finalWindow_s(2) || ...
        finalWindow_s(1) < t(1) || finalWindow_s(2) > t(end) || ...
        nnz(t >= finalWindow_s(1) & t <= finalWindow_s(2)) < 2
    invalidInput("spec.finalWindow_s is outside valid result.t coverage.");
end

requiredSignals = [ ...
    "turbine_inlet_T"
    "turbine_inlet_P"
    "turbine_outlet_P"
    "turbine_outlet_T"
    "turbine_lookup_expansion_ratio"
    "turbine_lookup_mass_flow"
    "turbine_lookup_speed_eff"];
% User-approved field contract (2026-08-25): the active Eq. 2.28 pi input is
% turbine_lookup_expansion_ratio. The separately recorded
% turbine_expansion_ratio=2.3620239539147176 comes from Compressor r and is
% not the active turbine Eq. 2.28 expansion ratio.
if ~all(isfield(result.signals, requiredSignals))
    invalidInput("A required turbine signal is missing.");
end
for index = 1:numel(requiredSignals)
    values = result.signals.(requiredSignals(index));
    if ~isnumeric(values) || ~isvector(values) || ...
            numel(values) ~= numel(t) || ~isreal(values) || ...
            any(~isfinite(values), "all")
        invalidInput("A required turbine signal is invalid.");
    end
end

if ~validHashScalar(result.modelHashBefore) || ...
        ~validHashScalar(result.modelHashAfter) || ...
        lower(string(result.modelHashBefore)) ~= ...
            lower(string(result.modelHashAfter)) || ...
        lower(string(result.modelHashAfter)) ~= ...
            lower(string(expectedModelSha256))
    invalidInput("Result model hash identity is invalid.");
end

if ~isfield(report, "metrics") || ~istable(report.metrics) || ...
        ~all(ismember(["metricName", "target", "meanValue", ...
        "relativeError"], ...
        string(report.metrics.Properties.VariableNames)))
    invalidInput("report.metrics is invalid.");
end
targetRow = string(report.metrics.metricName) == "turbine_outlet_T";
if nnz(targetRow) ~= 1 || ...
        ~validFiniteRealScalar(report.metrics.target(targetRow)) || ...
        report.metrics.target(targetRow) <= 0 || ...
        ~validFiniteRealScalar(report.metrics.meanValue(targetRow)) || ...
        report.metrics.meanValue(targetRow) <= 0 || ...
        ~validFiniteRealScalar(report.metrics.relativeError(targetRow)) || ...
        report.metrics.relativeError(targetRow) < 0
    invalidInput("The turbine_outlet_T target is invalid.");
end

lastValue = @(name) double(result.signals.(name)(end));
inputs = struct();
inputs.T1_K = lastValue("turbine_inlet_T");
inputs.P1_Pa = lastValue("turbine_inlet_P");
inputs.P2_Pa = lastValue("turbine_outlet_P");
inputs.recordedTerminalT2_K = lastValue("turbine_outlet_T");
inputs.expansionRatio = ...
    lastValue("turbine_lookup_expansion_ratio");
inputs.lookupMassFlow_kg_s = ...
    lastValue("turbine_lookup_mass_flow");
inputs.lookupSpeed_rpm = lastValue("turbine_lookup_speed_eff");
inputs.targetT2_K = double(report.metrics.target(targetRow));
inputs.reportMetricMeanT2_K = ...
    double(report.metrics.meanValue(targetRow));
inputs.reportMetricMeanError_K = ...
    inputs.targetT2_K - inputs.reportMetricMeanT2_K;
inputs.reportMetricRelativeError = ...
    double(report.metrics.relativeError(targetRow));
inputs.recordedTerminalError_K = ...
    inputs.targetT2_K - inputs.recordedTerminalT2_K;
inputs.recordedTerminalRelativeError = ...
    abs(inputs.recordedTerminalError_K) / abs(inputs.targetT2_K);
inputs.tFinal_s = t(end);
if any(structfun(@(value) ~validFiniteRealScalar(value), inputs)) || ...
        inputs.T1_K <= 0 || inputs.P1_Pa <= 0 || inputs.P2_Pa <= 0 || ...
        inputs.recordedTerminalT2_K <= 0 || inputs.expansionRatio <= 1 || ...
        inputs.lookupMassFlow_kg_s <= 0 || inputs.lookupSpeed_rpm <= 0
    invalidInput("A terminal turbine input is outside its valid domain.");
end
pressureRatio = inputs.P1_Pa / inputs.P2_Pa;
if abs(pressureRatio - inputs.expansionRatio) > ...
        1e-12 * max(1, abs(pressureRatio))
    invalidInput("Recorded pressure ratio does not match the active pi input.");
end
end

function validateTurbineTable(tablePayload)
required = ["bp_mf", "bp_speed", "table_eff"];
if ~isstruct(tablePayload) || ~all(isfield(tablePayload, required))
    error("steady53:H1aInvalidTurbineTable", ...
        "Missing turbine efficiency table fields.");
end
bp_mf = tablePayload.bp_mf;
bp_speed = tablePayload.bp_speed;
table_eff = tablePayload.table_eff;
if ~validBreakpoint(bp_mf) || ~validBreakpoint(bp_speed) || ...
        ~isnumeric(table_eff) || ~isreal(table_eff) || ...
        any(~isfinite(table_eff), "all") || ...
        ~isequal(size(table_eff), [numel(bp_mf), numel(bp_speed)])
    error("steady53:H1aInvalidTurbineTable", ...
        "Turbine efficiency table contract is invalid.");
end
end

function valid = validBreakpoint(value)
valid = isnumeric(value) && isvector(value) && numel(value) >= 2 && ...
    isreal(value) && all(isfinite(value), "all") && ...
    all(diff(double(value(:))) > 0);
end

function eta = interpolateCurrentTurbineEfficiency(tablePayload, mf, speed)
bp_mf = double(tablePayload.bp_mf(:));
bp_speed = double(tablePayload.bp_speed(:));
if mf < bp_mf(1) || mf > bp_mf(end) || ...
        speed < bp_speed(1) || speed > bp_speed(end)
    error("steady53:H1aLookupOutOfRange", ...
        "Turbine efficiency lookup input is outside its table.");
end
eta = interpn(bp_mf, bp_speed, double(tablePayload.table_eff), ...
    mf, speed, "linear");
if ~validFiniteRealScalar(eta) || eta <= 0 || eta > 1
    error("steady53:H1aInvalidTurbineTable", ...
        "Interpolated turbine efficiency is invalid.");
end
end

function [cp, gamma] = propertyCpGamma(T_K, P_Pa)
[cp, gamma] = HeXe_property_simulink(T_K, P_Pa);
if ~validFiniteRealScalar(cp) || ~validFiniteRealScalar(gamma) || ...
        cp <= 0 || gamma <= 1
    error("steady53:H1aInvalidProperty", ...
        "He-Xe property output is non-finite, complex, or nonphysical at T=%.17g K, P=%.17g Pa: cp=%.17g, gamma=%.17g.", ...
        T_K, P_Pa, cp, gamma);
end
end

function phi = phiAt(T_K, P_Pa)
[~, gamma] = propertyCpGamma(T_K, P_Pa);
phi = 1 - 1 / gamma;
validatePhi(phi, T_K, P_Pa, gamma);
end

function validatePhi(phi, T_K, P_Pa, gamma)
if ~validFiniteRealScalar(phi) || phi <= 0 || phi >= 1
    error("steady53:H1aInvalidProperty", ...
        "He-Xe phi is outside the required finite real interval (0,1) at T=%.17g K, P=%.17g Pa: gamma=%.17g, phi=%.17g.", ...
        T_K, P_Pa, gamma, phi);
end
end

function residual = s1RootResidual(candidateT2s_K, inputs)
phiBar = s1PhiAverage(candidateT2s_K, inputs);
residual = candidateT2s_K - ...
    inputs.T1_K * inputs.expansionRatio^(-phiBar);
validateResidual(residual);
end

function phiBar = s1PhiAverage(candidateT2s_K, inputs)
phiBar = (phiAt(inputs.T1_K, inputs.P1_Pa) + ...
    phiAt(candidateT2s_K, inputs.P2_Pa)) / 2;
end

function residual = s2RootResidual(candidateT2s_K, inputs, settings)
phiBar = s2PhiAverage(candidateT2s_K, inputs, settings);
residual = candidateT2s_K - ...
    inputs.T1_K * inputs.expansionRatio^(-phiBar);
validateResidual(residual);
end

function phiBar = s2PhiAverage(candidateT2s_K, inputs, settings)
integrand = @(lambda) arrayfun(@(value) s2PhiAt( ...
    inputs.T1_K + value * (candidateT2s_K - inputs.T1_K), ...
    inputs.P1_Pa + value * (inputs.P2_Pa - inputs.P1_Pa), ...
    settings), lambda);
phiBar = callIntegralFailClosed(settings.integralFunction, ...
    integrand, settings, inputs);
if ~validFiniteRealScalar(phiBar) || phiBar <= 0 || phiBar >= 1
    error("steady53:H1aIntegralFailed", ...
        "S2 phi integral did not produce a valid result.");
end
end

function phi = s2PhiAt(T_K, P_Pa, settings)
[cp, gamma] = settings.s2PropertyFunction(T_K, P_Pa);
if ~validFiniteRealScalar(cp) || ~validFiniteRealScalar(gamma) || ...
        cp <= 0 || gamma <= 1
    error("steady53:H1aInvalidProperty", ...
        "S2 %s property output is non-finite, complex, or nonphysical at T=%.17g K, P=%.17g Pa: cp=%.17g, gamma=%.17g.", ...
        settings.s2PropertyVariant, T_K, P_Pa, cp, gamma);
end
phi = 1 - 1/gamma;
validatePhi(phi, T_K, P_Pa, gamma);
end

function audit = auditResolvedS2Path(T2s_K, inputs, settings)
sampleCount = 1001;
coordinate = linspace(0, 1, sampleCount).';
cpMass = zeros(sampleCount, 1);
cvMass = zeros(sampleCount, 1);
gamma = zeros(sampleCount, 1);
phi = zeros(sampleCount, 1);
for index = 1:sampleCount
    T_K = inputs.T1_K + coordinate(index)*(T2s_K - inputs.T1_K);
    P_Pa = inputs.P1_Pa + ...
        coordinate(index)*(inputs.P2_Pa - inputs.P1_Pa);
    if settings.s2PropertyVariant == "schemeA"
        [cpMass(index), gamma(index), ~, propertyAudit] = ...
            settings.s2PropertyFunction(T_K, P_Pa);
        cvMass(index) = propertyAudit.cvMass;
    else
        [cpMass(index), gamma(index)] = ...
            settings.s2PropertyFunction(T_K, P_Pa);
        cvMass(index) = cpMass(index)/gamma(index);
    end
    phi(index) = 1 - 1/gamma(index);
end
allPhysical = all(isfinite(cpMass)) && all(isreal(cpMass)) && ...
    all(cpMass > 0) && all(isfinite(cvMass)) && all(isreal(cvMass)) && ...
    all(cvMass > 0) && all(isfinite(gamma)) && all(isreal(gamma)) && ...
    all(gamma > 1) && all(isfinite(phi)) && all(isreal(phi)) && ...
    all(phi > 0 & phi < 1);
if ~allPhysical
    error("steady53:H1aInvalidProperty", ...
        "The resolved S2 path failed its finite physical-domain audit.");
end
audit = struct("sampleCount", sampleCount, ...
    "minCpMass_J_kgK", min(cpMass), ...
    "minCvMass_J_kgK", min(cvMass), ...
    "minGamma", min(gamma), "maxGamma", max(gamma), ...
    "minPhi", min(phi), "maxPhi", max(phi), ...
    "allPhysical", allPhysical, "formalGlobalProof", false, ...
    "classification", "finite1001PointAuditNotFormalGlobalProof");
end

function value = callIntegralFailClosed(integralFunction, ...
        integrand, settings, inputs)
warningIds = integralWarningIdentifiers();
savedStates = repmat(warning("query", warningIds(1)), ...
    numel(warningIds), 1);
for index = 1:numel(warningIds)
    savedStates(index) = warning("query", warningIds(index));
end
warningCleanup = onCleanup(@() restoreWarningStates(savedStates));
for index = 1:numel(warningIds)
    warning("error", warningIds(index));
end
try
    value = integralFunction(integrand, 0, 1, ...
        "RelTol", settings.s2IntegralRelTol, ...
        "AbsTol", settings.s2IntegralAbsTol);
catch exception
    if startsWith(string(exception.identifier), "MATLAB:integral:")
        nonconvergence = MException( ...
            "steady53:H1aIntegrationNonconvergence", ...
            "S2 integral raised %s at the required [T1/pi,T1] fzero bracket. S1 local read-only result before block: phiBar=%.17g, T2s_K=%.17g, T2_K=%.17g, rootResidual_K=%.17g. reportMetricMeanT2_K=%.17g, reportMetricRelativeError=%.17g; recordedTerminalT2_K=%.17g, recordedTerminalRelativeError=%.17g. Expansion-ratio field contract approved 2026-08-25: turbine_lookup_expansion_ratio is the active Eq. 2.28 pi input. No H1a output was published.", ...
            string(exception.identifier), settings.s1PhiBar, ...
            settings.s1T2s_K, settings.s1T2_K, ...
            settings.s1RootResidual_K, inputs.reportMetricMeanT2_K, ...
            inputs.reportMetricRelativeError, ...
            inputs.recordedTerminalT2_K, ...
            inputs.recordedTerminalRelativeError);
        nonconvergence = addCause(nonconvergence, exception);
        throw(nonconvergence);
    end
    rethrow(exception);
end
clear warningCleanup
end

function identifiers = integralWarningIdentifiers()
% Complete set of warning() identifiers called by R2025a integralCalc.m.
% MATLAB does not support warning-ID wildcards for state changes, so this
% verified current-release set is promoted locally and restored afterward.
identifiers = [ ...
    "MATLAB:integral:MaxIntervalCountReached"
    "MATLAB:integral:MinStepSize"
    "MATLAB:integral:NonFiniteValue"];
end

function restoreWarningStates(savedStates)
for index = 1:numel(savedStates)
    warning(savedStates(index));
end
end

function [root, residual] = solveBracketedRoot(functionHandle, settings)
lowerBound = settings.rootBracketLow_K;
upperBound = settings.rootBracketHigh_K;
lowerResidual = functionHandle(lowerBound);
upperResidual = functionHandle(upperBound);
validateResidual(lowerResidual);
validateResidual(upperResidual);
if lowerResidual == 0
    root = lowerBound;
    exitflag = 1;
elseif upperResidual == 0
    root = upperBound;
    exitflag = 1;
elseif sign(lowerResidual) == sign(upperResidual)
    error("steady53:H1aNoBracket", ...
        "No sign-changing root bracket exists on [T1/pi,T1].");
else
    solverOptions = optimset("Display", "off", ...
        "TolX", settings.rootTolX_K, ...
        "MaxIter", settings.rootMaxIterations, ...
        "MaxFunEvals", settings.rootMaxFunctionEvaluations);
    [root, ~, exitflag] = fzero(functionHandle, ...
        [lowerBound, upperBound], solverOptions);
end
residual = functionHandle(root);
if exitflag <= 0 || ~validFiniteRealScalar(root) || ...
        root < lowerBound || root > upperBound || ...
        ~validFiniteRealScalar(residual) || ...
        abs(residual) > settings.rootAbsResidualTolerance_K
    error("steady53:H1aRootFailed", ...
        "Root solve did not converge to the required absolute residual.");
end
end

function validateResidual(value)
if ~validFiniteRealScalar(value)
    error("steady53:H1aRootFailed", ...
        "Root residual is non-finite or complex.");
end
end

function T2_K = turbineOutletTemperature(inputs, T2s_K)
T2_K = inputs.T1_K - ...
    inputs.eta * inputs.cp2_J_kgK * ...
    (inputs.T1_K - T2s_K) / inputs.cp1_J_kgK;
if ~validFiniteRealScalar(T2_K) || T2_K <= 0
    error("steady53:H1aInvalidResult", ...
        "Calculated turbine outlet temperature is invalid.");
end
end

function output = makeSensitivityTable(inputs, settings, ...
        phiBar, T2s_K, T2_K, rootResidual_K)
method = ["baseline"; "S1"; "S2"];
if settings.s2PropertyVariant == "schemeA"
    method(3) = "S2_schemeA_phiOnly";
end
deltaT2FromBaseline_K = T2_K - T2_K(1);
targetT2_K = repmat(inputs.targetT2_K, 3, 1);
remainingError_K = targetT2_K - T2_K;
relativeTargetError = abs(remainingError_K) ./ abs(targetT2_K);
baselineGap_K = inputs.targetT2_K - T2_K(1);
explainedFractionOfBaselineGap = ...
    deltaT2FromBaseline_K / baselineGap_K;
rootBracketLow_K = repmat(settings.rootBracketLow_K, 3, 1);
rootBracketHigh_K = repmat(settings.rootBracketHigh_K, 3, 1);
rootAbsResidualTolerance_K = repmat( ...
    settings.rootAbsResidualTolerance_K, 3, 1);
s2IntegralRelTol = repmat(settings.s2IntegralRelTol, 3, 1);
s2IntegralAbsTol = repmat(settings.s2IntegralAbsTol, 3, 1);
numericalImplementationChoice = [false; true; true];
evidenceGrade = ["✅"; "❓"; "❓"];
reportMetricMeanT2_K = repmat(inputs.reportMetricMeanT2_K, 3, 1);
reportMetricMeanError_K = repmat( ...
    inputs.reportMetricMeanError_K, 3, 1);
reportMetricRelativeError = repmat( ...
    inputs.reportMetricRelativeError, 3, 1);
recordedTerminalT2_K = repmat(inputs.recordedTerminalT2_K, 3, 1);
recordedTerminalError_K = repmat( ...
    inputs.recordedTerminalError_K, 3, 1);
recordedTerminalRelativeError = repmat( ...
    inputs.recordedTerminalRelativeError, 3, 1);
description = [ ...
    "current inlet single-point phi"
    "endpoint arithmetic mean phi"
    "linear T-P path integral phi"];
if settings.s2PropertyVariant == "schemeA"
    description(3) = ...
        "linear T-P path integral phi with Scheme A only";
end
output = table(method, phiBar, T2s_K, T2_K, ...
    deltaT2FromBaseline_K, targetT2_K, remainingError_K, ...
    relativeTargetError, rootResidual_K, ...
    explainedFractionOfBaselineGap, rootBracketLow_K, ...
    rootBracketHigh_K, rootAbsResidualTolerance_K, ...
    s2IntegralRelTol, s2IntegralAbsTol, ...
    numericalImplementationChoice, evidenceGrade, ...
    reportMetricMeanT2_K, reportMetricMeanError_K, ...
    reportMetricRelativeError, recordedTerminalT2_K, ...
    recordedTerminalError_K, recordedTerminalRelativeError, ...
    description);
end

function conclusion = h1aConclusion(numericallySufficient, ...
        baselineGap_K, sensitivity)
if numericallySufficient
    resultWord = "yes";
else
    resultWord = "no";
end
conclusion = sprintf("h1aNumericallySufficient=%s; terminalBaselineGap_K=%.17g; S1RemainingError_K=%.17g; S2RemainingError_K=%.17g. This numerical sensitivity result is not evidence that either paper-unspecified implementation is physically correct.", ...
    resultWord, baselineGap_K, sensitivity.remainingError_K(2), ...
    sensitivity.remainingError_K(3));
conclusion = string(conclusion);
end

function text = makeSummaryText(config, inputMat, inputHash, ...
        turbineTableMat, turbineTableHash, modelPath, modelHash, ...
        formalPropertyPath, formalPropertyHash, ...
        s2PropertySourcePath, s2PropertySourceHash, ...
        s2EvidencePaths, s2EvidenceHashes, finalWindow_s, inputs, ...
        settings, sensitivity, s2PathAudit, ...
        baselineResidual_K, conclusion, loadedBefore)
loadedText = "(none)";
if ~isempty(loadedBefore)
    loadedText = strjoin(loadedBefore, ",");
end
evidenceLines = strings(0, 1);
if settings.s2PropertyVariant == "schemeA"
    evidenceLines = [ ...
        "s2ApprovedH2aCsv=" + s2EvidencePaths(1)
        "s2ApprovedH2aCsvSha256=" + s2EvidenceHashes(1)
        "s2ApprovedH2aTxt=" + s2EvidencePaths(2)
        "s2ApprovedH2aTxtSha256=" + s2EvidenceHashes(2)];
end
lines = [ ...
    "Task 8 H1a read-only Eq. 2.28 phi-bar sensitivity"
    "runId=" + string(config.runId)
    "inputMat=" + inputMat
    "inputMatSha256=" + inputHash
    "turbineTableMat=" + turbineTableMat
    "turbineTableSha256=" + turbineTableHash
    "formalModel=" + modelPath
    "modelSha256=" + modelHash
    "formalProperty=" + formalPropertyPath
    "formalPropertySha256=" + formalPropertyHash
    "s2PhiVariant=" + settings.s2PropertyVariant
    "s2PhiScope=only H1a-S2 phi integrand"
    "s2PropertySource=" + s2PropertySourcePath
    "s2PropertySourceSha256=" + s2PropertySourceHash
    evidenceLines
    sprintf("finalWindow_s=[%.17g,%.17g]", finalWindow_s)
    sprintf("tFinal_s=%.17g", inputs.tFinal_s)
    sprintf("T1_K=%.17g", inputs.T1_K)
    sprintf("P1_Pa=%.17g", inputs.P1_Pa)
    sprintf("P2_Pa=%.17g", inputs.P2_Pa)
    sprintf("targetT2_K=%.17g", inputs.targetT2_K)
    sprintf("reportMetricMeanT2_K=%.17g", ...
        inputs.reportMetricMeanT2_K)
    sprintf("reportMetricMeanError_K=%.17g", ...
        inputs.reportMetricMeanError_K)
    sprintf("reportMetricRelativeError=%.17g", ...
        inputs.reportMetricRelativeError)
    sprintf("recordedTerminalT2_K=%.17g", ...
        inputs.recordedTerminalT2_K)
    sprintf("recordedTerminalError_K=%.17g", ...
        inputs.recordedTerminalError_K)
    sprintf("recordedTerminalRelativeError=%.17g", ...
        inputs.recordedTerminalRelativeError)
    sprintf("expansionRatio=%.17g", inputs.expansionRatio)
    "expansionRatioSourceSignal=turbine_lookup_expansion_ratio"
    "expansionRatioFieldContractApprovedOn=2026-08-25"
    "expansionRatioFieldContractStatus=approved"
    "inactiveCompressorRatioSignal=turbine_expansion_ratio"
    "inactiveCompressorRatioValue=2.3620239539147176"
    "inactiveCompressorRatioRole=Compressor r; not the active Eq. 2.28 pi input"
    sprintf("lookupMassFlow_kg_s=%.17g", inputs.lookupMassFlow_kg_s)
    sprintf("lookupSpeed_rpm=%.17g", inputs.lookupSpeed_rpm)
    sprintf("eta=%.17g", inputs.eta)
    sprintf("gamma1=%.17g", inputs.gamma1)
    sprintf("baselinePhi=%.17g", inputs.baselinePhi)
    sprintf("cp1_J_kgK=%.17g", inputs.cp1_J_kgK)
    sprintf("cp2_J_kgK=%.17g", inputs.cp2_J_kgK)
    sprintf("gamma2s=%.17g", inputs.gamma2s)
    sprintf("baselineT2s_K=%.17g", inputs.baselineT2s_K)
    sprintf("baselineReproductionResidual_K=%.17g", baselineResidual_K)
    sprintf("rootBracket_K=[%.17g,%.17g]", ...
        settings.rootBracketLow_K, settings.rootBracketHigh_K)
    sprintf("rootAbsResidualTolerance_K=%.17g", ...
        settings.rootAbsResidualTolerance_K)
    sprintf("rootTolX_K=%.17g", settings.rootTolX_K)
    sprintf("rootMaxIterations=%d", settings.rootMaxIterations)
    sprintf("rootMaxFunctionEvaluations=%d", ...
        settings.rootMaxFunctionEvaluations)
    sprintf("s2IntegralRelTol=%.17g", settings.s2IntegralRelTol)
    sprintf("s2IntegralAbsTol=%.17g", settings.s2IntegralAbsTol)
    "s2IntegrationCompleted=true"
    "s2RootConverged=true"
    sprintf("s2PathAuditSampleCount=%d", s2PathAudit.sampleCount)
    sprintf("s2PathAuditMinCpMass_J_kgK=%.17g", ...
        s2PathAudit.minCpMass_J_kgK)
    sprintf("s2PathAuditMinCvMass_J_kgK=%.17g", ...
        s2PathAudit.minCvMass_J_kgK)
    sprintf("s2PathAuditMinGamma=%.17g", s2PathAudit.minGamma)
    sprintf("s2PathAuditMaxGamma=%.17g", s2PathAudit.maxGamma)
    sprintf("s2PathAuditMinPhi=%.17g", s2PathAudit.minPhi)
    sprintf("s2PathAuditMaxPhi=%.17g", s2PathAudit.maxPhi)
    "s2PathAuditAllPhysical=true"
    "s2PathAuditFormalGlobalProof=false"
    "etaCp1Cp2HeldFixed=true"
    "s2IntegralWarningPolicy=all R2025a integralCalc MATLAB:integral:* warning calls fail_closed with original cause preserved"
    "lookupInterpolation=2-D linear with bp_mf as dimension 1 and bp_speed as dimension 2"
    "H1a-S1 and H1a-S2 are both paper-unspecified numerical implementation choices"
    "Neither candidate is selected as the correct physical path"
    "h1bExecuted=false"
    "modelModified=false"
    "authorizesRepair=false"
    "formalModelPromotion=false"
    "slxLoadedOrSimulated=false"
    "loadedBlockDiagramsBefore=" + loadedText
    "result.baseline=" + rowSummary(sensitivity(1, :))
    "result.S1=" + rowSummary(sensitivity(2, :))
    "result.S2=" + rowSummary(sensitivity(3, :))
    "conclusion=" + conclusion
    "Boundary: numerical proximity to the paper target is not correctness evidence."];
text = strjoin(lines, newline) + newline;
end

function output = rowSummary(row)
output = string(sprintf("phiBar=%.17g,T2s_K=%.17g,T2_K=%.17g,deltaT2FromBaseline_K=%.17g,remainingError_K=%.17g,relativeTargetError=%.17g,rootResidual_K=%.17g", ...
    row.phiBar, row.T2s_K, row.T2_K, ...
    row.deltaT2FromBaseline_K, row.remainingError_K, ...
    row.relativeTargetError, row.rootResidual_K));
end

function [csvHash, summaryHash] = writeOutputs(outputDir, ...
        sensitivity, summaryText, outputFailureHook)
[outputParent, outputName, outputExtension] = fileparts(outputDir);
outputParent = string(outputParent);
outputLeaf = string(outputName) + string(outputExtension);
if ~isfolder(outputParent) || strlength(outputLeaf) == 0
    error("steady53:H1aOutputFailed", ...
        "The H1a output parent must already exist.");
end
if isfolder(outputDir) || isfile(outputDir)
    error("steady53:H1aOutputExists", ...
        "H1a output target already exists: '%s'.", outputDir);
end

stagingPrefix = "." + outputLeaf + ".staging_";
[~, uniqueLeaf] = fileparts(tempname(outputParent));
stagingDir = fullfile(outputParent, stagingPrefix + string(uniqueLeaf));
if isfolder(stagingDir) || isfile(stagingDir)
    error("steady53:H1aOutputFailed", ...
        "The unique H1a staging path unexpectedly exists.");
end
[created, message, messageId] = mkdir(stagingDir);
if ~created || strlength(string(messageId)) > 0 || ~isfolder(stagingDir)
    error("steady53:H1aOutputFailed", ...
        "Could not create unique H1a staging directory '%s': %s", ...
        stagingDir, message);
end
stagingCleanup = onCleanup(@() cleanupStagingDirectory( ...
    stagingDir, outputParent, stagingPrefix));

stagedCsvPath = fullfile(stagingDir, "h1a_sensitivity.csv");
stagedSummaryPath = fullfile(stagingDir, "h1a_summary.txt");
writetable(sensitivity, stagedCsvPath);
outputFailureHook("afterCsvBeforeSummary", stagingDir);

% The staging directory is uniquely created and empty, so ordinary create
% semantics are sufficient here. The former native-machine-format token
% "n" was never an exclusive-create flag and is intentionally not used.
[fileId, message] = fopen(stagedSummaryPath, "w", "native", "UTF-8");
if fileId < 0
    error("steady53:H1aOutputFailed", ...
        "Could not create staged summary '%s': %s", ...
        stagedSummaryPath, message);
end
try
    fprintf(fileId, "%s", summaryText);
catch exception
    fclose(fileId);
    rethrow(exception);
end
closeStatus = fclose(fileId);
if closeStatus ~= 0
    error("steady53:H1aOutputFailed", ...
        "Could not close staged summary '%s'.", stagedSummaryPath);
end

validateReadableOutput(stagedCsvPath);
validateReadableOutput(stagedSummaryPath);
csvHash = sha256File(stagedCsvPath);
summaryHash = sha256File(stagedSummaryPath);

% Recheck, then permit a test-only race fixture immediately before the
% single directory-level no-replace move. Correctness cannot rely on this
% precheck because another owner may create the target after it returns.
if isfolder(outputDir) || isfile(outputDir)
    error("steady53:H1aOutputExists", ...
        "H1a output target appeared before publication: '%s'.", ...
        outputDir);
end
outputFailureHook("beforePublish", stagingDir);
moveDirectoryNoReplace(stagingDir, outputDir);
try
    if ~isfolder(outputDir) || ...
            ~isfile(fullfile(outputDir, "h1a_sensitivity.csv")) || ...
            ~isfile(fullfile(outputDir, "h1a_summary.txt"))
        error("steady53:H1aOutputFailed", ...
            "Published H1a output directory is incomplete.");
    end
    publishedCsvHash = sha256File(fullfile(outputDir, ...
        "h1a_sensitivity.csv"));
    publishedSummaryHash = sha256File(fullfile(outputDir, ...
        "h1a_summary.txt"));
    if publishedCsvHash ~= csvHash || ...
            publishedSummaryHash ~= summaryHash
        error("steady53:H1aOutputFailed", ...
            "Published H1a output hashes differ from staged hashes.");
    end
catch exception
    cleanupPublishedDirectory(outputDir, outputParent, outputLeaf);
    rethrow(exception);
end
clear stagingCleanup
end

function validateReadableOutput(filePath)
[fileId, message] = fopen(filePath, "r");
if fileId < 0
    error("steady53:H1aOutputFailed", ...
        "Staged output is not readable '%s': %s", filePath, message);
end
closeStatus = fclose(fileId);
if closeStatus ~= 0
    error("steady53:H1aOutputFailed", ...
        "Could not close staged output '%s' after validation.", filePath);
end
end

function moveDirectoryNoReplace(stagingDir, outputDir)
sourcePath = javaObject("java.io.File", char(stagingDir)).toPath();
targetPath = javaObject("java.io.File", char(outputDir)).toPath();
noReplaceOptions = javaArray("java.nio.file.CopyOption", 0);
try
    javaMethod("move", "java.nio.file.Files", ...
        sourcePath, targetPath, noReplaceOptions);
catch exception
    if isfolder(outputDir) || isfile(outputDir)
        collision = MException("steady53:H1aOutputExists", ...
            "H1a output publication refused to overwrite '%s'.", ...
            outputDir);
        collision = addCause(collision, exception);
        throw(collision);
    end
    publicationFailure = MException("steady53:H1aOutputFailed", ...
        "Could not publish staged H1a output directory.");
    publicationFailure = addCause(publicationFailure, exception);
    throw(publicationFailure);
end
end

function cleanupStagingDirectory(stagingDir, expectedParent, ...
        expectedPrefix)
if ~isfolder(stagingDir)
    return
end
[actualParent, actualName, actualExtension] = fileparts(stagingDir);
actualLeaf = string(actualName) + string(actualExtension);
if string(actualParent) ~= string(expectedParent) || ...
        ~startsWith(actualLeaf, string(expectedPrefix)) || ...
        strlength(actualLeaf) <= strlength(string(expectedPrefix))
    return
end
rmdir(stagingDir, "s");
end

function cleanupPublishedDirectory(outputDir, expectedParent, expectedLeaf)
if ~isfolder(outputDir)
    return
end
[actualParent, actualName, actualExtension] = fileparts(outputDir);
actualLeaf = string(actualName) + string(actualExtension);
if string(actualParent) ~= string(expectedParent) || ...
        actualLeaf ~= string(expectedLeaf)
    return
end
rmdir(outputDir, "s");
end

function noOutputFailure(varargin)
end

function assertReadOnlyState(modelPath, modelHash, ...
        tablePath, tableHash, formalPropertyPath, formalPropertyHash, ...
        s2PropertyPath, s2PropertyHash, ...
        s2EvidencePaths, s2EvidenceHashes, loadedBefore)
if sha256File(modelPath) ~= modelHash || ...
        sha256File(tablePath) ~= tableHash || ...
        sha256File(formalPropertyPath) ~= formalPropertyHash || ...
        sha256File(s2PropertyPath) ~= s2PropertyHash
    error("steady53:H1aProtectedFileChanged", ...
        "A protected H1a input hash changed.");
end
for index = 1:numel(s2EvidencePaths)
    if sha256File(s2EvidencePaths(index)) ~= s2EvidenceHashes(index)
        error("steady53:H1aProtectedFileChanged", ...
            "Approved H2a evidence changed during H1a.");
    end
end
if ~isequal(loadedBlockDiagrams(), loadedBefore)
    error("steady53:H1aLoadedModelsChanged", ...
        "Loaded block-diagram set changed during H1a.");
end
end

function diagrams = loadedBlockDiagrams()
diagrams = sort(string(find_system("type", "block_diagram")));
diagrams = diagrams(:);
end

function restoreEnvironment(originalPath, originalWarnings)
path(originalPath);
warning(originalWarnings);
resetPropertyState();
end

function resetPropertyState()
clear("HeXe_property_simulink");
clear("hexe_property_scheme_a_offline");
end

function valid = validFiniteRealScalar(value)
valid = isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value);
end

function valid = validHashScalar(value)
valid = (isstring(value) || ischar(value)) && ...
    isscalar(string(value)) && ~isempty(regexp(char(string(value)), ...
    '^[0-9a-fA-F]{64}$', 'once'));
end

function invalidInput(message)
error("steady53:H1aInvalidInput", "%s", message);
end

function hash = sha256File(filePath)
if ~isfile(filePath)
    error("steady53:HashFailed", "File does not exist: '%s'.", filePath);
end
[commandStatus, output] = system( ...
    "shasum -a 256 " + shellQuote(filePath));
if commandStatus ~= 0
    error("steady53:HashFailed", ...
        "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = lower(string(parts(1)));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
