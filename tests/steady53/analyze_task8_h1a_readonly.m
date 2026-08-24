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
    "rootBracketLow_K", 100, ...
    "rootAbsResidualTolerance_K", 1e-9, ...
    "rootTolX_K", 1e-12, ...
    "rootMaxIterations", 1000, ...
    "rootMaxFunctionEvaluations", 5000, ...
    "s2IntegralRelTol", 1e-8, ...
    "s2IntegralAbsTol", 1e-10);
if inputs.T1_K <= settings.rootBracketLow_K
    error("steady53:H1aInvalidInput", ...
        "T1 must exceed the fixed 100 K root bracket lower bound.");
end
settings.rootBracketHigh_K = inputs.T1_K;

resetPropertyState();
[inputs.cp1_J_kgK, inputs.gamma1] = propertyCpGamma( ...
    inputs.T1_K, inputs.P1_Pa);
inputs.baselinePhi = 1 - 1 / inputs.gamma1;
inputs.baselineT2s_K = inputs.T1_K * ...
    inputs.expansionRatio^(-inputs.baselinePhi);
[inputs.cp2_J_kgK, inputs.gamma2s] = propertyCpGamma( ...
    inputs.baselineT2s_K, inputs.P2_Pa);
baselineT2_K = turbineOutletTemperature(inputs, ...
    inputs.baselineT2s_K);
baselineReproductionResidual_K = ...
    baselineT2_K - inputs.recordedT2_K;
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

resetPropertyState();
warning("error", "MATLAB:integral:MaxIntervalCountReached");
s2Function = @(candidateT2s) s2RootResidual( ...
    candidateT2s, inputs, settings);
try
    [s2T2s_K, s2RootResidual_K] = solveBracketedRoot( ...
        s2Function, settings);
catch exception
    if string(exception.identifier) == ...
            "MATLAB:integral:MaxIntervalCountReached"
        nonconvergence = MException( ...
            "steady53:H1aIntegrationNonconvergence", ...
            "S2 integral did not converge at the required [100 K,T1] fzero bracket. S1 local read-only result before block: phiBar=%.17g, T2s_K=%.17g, T2_K=%.17g, rootResidual_K=%.17g. No H1a output was published.", ...
            s1PhiBar, s1T2s_K, s1T2_K, s1RootResidual_K);
        nonconvergence = addCause(nonconvergence, exception);
        throw(nonconvergence);
    end
    rethrow(exception);
end
s2PhiBar = s2PhiAverage(s2T2s_K, inputs, settings);
s2T2_K = turbineOutletTemperature(inputs, s2T2s_K);

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
    turbineTableMat, turbineTableSha256, loadedBlockDiagramsBefore);
summaryText = makeSummaryText(config, inputMat, inputMatSha256, ...
    turbineTableMat, turbineTableSha256, modelPath, modelSha256, ...
    finalWindow_s, inputs, settings, sensitivity, ...
    baselineReproductionResidual_K, conclusion, ...
    loadedBlockDiagramsBefore);
writeOutputs(outputDir, csvPath, summaryPath, ...
    sensitivity, summaryText);
assertReadOnlyState(modelPath, modelSha256, ...
    turbineTableMat, turbineTableSha256, loadedBlockDiagramsBefore);
loadedBlockDiagramsAfter = loadedBlockDiagrams();

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
analysis.csvSha256 = sha256File(csvPath);
analysis.summarySha256 = sha256File(summaryPath);
analysis.finalWindow_s = finalWindow_s;
analysis.inputs = inputs;
analysis.settings = settings;
analysis.sensitivity = sensitivity;
analysis.baselineReproductionResidual_K = ...
    baselineReproductionResidual_K;
analysis.h1aNumericallySufficient = h1aNumericallySufficient;
analysis.conclusion = conclusion;
analysis.loadedBlockDiagramsBefore = loadedBlockDiagramsBefore;
analysis.loadedBlockDiagramsAfter = loadedBlockDiagramsAfter;
analysis.h1bExecuted = false;
analysis.modelModified = false;

restoreEnvironment(originalPath, originalWarnings);
clear environmentCleanup
analysis.pathRestored = strcmp(path, originalPath);
analysis.warningStateRestored = isequaln(warning, originalWarnings);
analysis.persistentStateAfter = "cleared_uninitialized";
if ~analysis.pathRestored || ~analysis.warningStateRestored
    error("steady53:H1aEnvironmentRestoreFailed", ...
        "Path or warning state was not restored.");
end
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
    "expectedModelSha256", "outputDir"];
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
        ~all(ismember(["metricName", "target"], ...
        string(report.metrics.Properties.VariableNames)))
    invalidInput("report.metrics is invalid.");
end
targetRow = string(report.metrics.metricName) == "turbine_outlet_T";
if nnz(targetRow) ~= 1 || ...
        ~validFiniteRealScalar(report.metrics.target(targetRow)) || ...
        report.metrics.target(targetRow) <= 0
    invalidInput("The turbine_outlet_T target is invalid.");
end

lastValue = @(name) double(result.signals.(name)(end));
inputs = struct();
inputs.T1_K = lastValue("turbine_inlet_T");
inputs.P1_Pa = lastValue("turbine_inlet_P");
inputs.P2_Pa = lastValue("turbine_outlet_P");
inputs.recordedT2_K = lastValue("turbine_outlet_T");
inputs.expansionRatio = ...
    lastValue("turbine_lookup_expansion_ratio");
inputs.lookupMassFlow_kg_s = ...
    lastValue("turbine_lookup_mass_flow");
inputs.lookupSpeed_rpm = lastValue("turbine_lookup_speed_eff");
inputs.targetT2_K = double(report.metrics.target(targetRow));
inputs.tFinal_s = t(end);
if any(structfun(@(value) ~validFiniteRealScalar(value), inputs)) || ...
        inputs.T1_K <= 0 || inputs.P1_Pa <= 0 || inputs.P2_Pa <= 0 || ...
        inputs.recordedT2_K <= 0 || inputs.expansionRatio <= 0 || ...
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
        gamma == 0
    error("steady53:H1aInvalidProperty", ...
        "He-Xe property output is non-finite, complex, or nonphysical at T=%.17g K, P=%.17g Pa: cp=%.17g, gamma=%.17g.", ...
        T_K, P_Pa, cp, gamma);
end
end

function phi = phiAt(T_K, P_Pa)
[~, gamma] = propertyCpGamma(T_K, P_Pa);
phi = 1 - 1 / gamma;
if ~validFiniteRealScalar(phi)
    error("steady53:H1aInvalidProperty", ...
        "He-Xe phi is non-finite or complex.");
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
integrand = @(lambda) arrayfun(@(value) phiAt( ...
    inputs.T1_K + value * (candidateT2s_K - inputs.T1_K), ...
    inputs.P1_Pa + value * (inputs.P2_Pa - inputs.P1_Pa)), lambda);
phiBar = integral(integrand, 0, 1, ...
    "RelTol", settings.s2IntegralRelTol, ...
    "AbsTol", settings.s2IntegralAbsTol);
if ~validFiniteRealScalar(phiBar) || phiBar <= 0 || phiBar >= 1
    error("steady53:H1aIntegralFailed", ...
        "S2 phi integral did not produce a valid result.");
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
        "No sign-changing root bracket exists on [100 K,T1].");
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
description = [ ...
    "current inlet single-point phi"
    "endpoint arithmetic mean phi"
    "linear T-P path integral phi"];
output = table(method, phiBar, T2s_K, T2_K, ...
    deltaT2FromBaseline_K, targetT2_K, remainingError_K, ...
    relativeTargetError, rootResidual_K, ...
    explainedFractionOfBaselineGap, rootBracketLow_K, ...
    rootBracketHigh_K, rootAbsResidualTolerance_K, ...
    s2IntegralRelTol, s2IntegralAbsTol, ...
    numericalImplementationChoice, evidenceGrade, description);
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
        finalWindow_s, inputs, settings, sensitivity, ...
        baselineResidual_K, conclusion, loadedBefore)
loadedText = "(none)";
if ~isempty(loadedBefore)
    loadedText = strjoin(loadedBefore, ",");
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
    sprintf("finalWindow_s=[%.17g,%.17g]", finalWindow_s)
    sprintf("tFinal_s=%.17g", inputs.tFinal_s)
    sprintf("T1_K=%.17g", inputs.T1_K)
    sprintf("P1_Pa=%.17g", inputs.P1_Pa)
    sprintf("P2_Pa=%.17g", inputs.P2_Pa)
    sprintf("recordedT2_K=%.17g", inputs.recordedT2_K)
    sprintf("targetT2_K=%.17g", inputs.targetT2_K)
    sprintf("expansionRatio=%.17g", inputs.expansionRatio)
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
    "s2IntegralWarningPolicy=fail_closed"
    "lookupInterpolation=2-D linear with bp_mf as dimension 1 and bp_speed as dimension 2"
    "H1a-S1 and H1a-S2 are both paper-unspecified numerical implementation choices"
    "Neither candidate is selected as the correct physical path"
    "h1bExecuted=false"
    "modelModified=false"
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

function writeOutputs(outputDir, csvPath, summaryPath, ...
        sensitivity, summaryText)
[created, message] = mkdir(outputDir);
if ~created || ~isempty(message) && ~isfolder(outputDir)
    error("steady53:H1aOutputFailed", ...
        "Could not create output directory '%s': %s", ...
        outputDir, message);
end
writetable(sensitivity, csvPath);
[fileId, message] = fopen(summaryPath, "w", "n", "UTF-8");
if fileId < 0
    error("steady53:H1aOutputExists", ...
        "Could not exclusively create summary '%s': %s", ...
        summaryPath, message);
end
fileCleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", summaryText);
clear fileCleanup
end

function assertReadOnlyState(modelPath, modelHash, ...
        tablePath, tableHash, loadedBefore)
if sha256File(modelPath) ~= modelHash || ...
        sha256File(tablePath) ~= tableHash
    error("steady53:H1aProtectedFileChanged", ...
        "Formal model or turbine table hash changed.");
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
