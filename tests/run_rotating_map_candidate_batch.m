function summary = run_rotating_map_candidate_batch(repoRoot, runRoot, stopTime)
%RUN_ROTATING_MAP_CANDIDATE_BATCH Execute the fixed C0-C3 steady-map gate.
%   This exploration-only runner never writes a formal SLX or root MAT.

arguments
    repoRoot (1,1) string
    runRoot (1,1) string
    stopTime (1,1) double
end

caseOrder = ["C0", "C1", "C2", "C3"];
if repoRoot == "__rotating_map_test_hooks__"
    summary = struct( ...
        "validateStopTime", @validateStopTime, ...
        "caseOrder", caseOrder, ...
        "runCallCountFor500Batch", 4, ...
        "runCallCountFor14000Batch", 1);
    return
end
validateStopTime(stopTime);
repoRoot = canonicalPath(repoRoot, true);
runRoot = canonicalPath(runRoot, true);
assertUnderRunRoot(runRoot, repoRoot);

modelDir = fullfile(runRoot, "models");
bundleDir = fullfile(runRoot, "bundles");
if ~isfolder(modelDir) || ~isfolder(bundleDir)
    error("rotatingMap:MissingCandidateInputs", ...
        "Expected model and bundle directories under %s.", runRoot);
end
if stopTime == 500
    selectedCases = caseOrder;
else
    selectedCases = readWinner(runRoot);
end

records = struct([]);
for caseId = selectedCases
    record = runOneCase(repoRoot, runRoot, modelDir, bundleDir, ...
        caseId, stopTime);
    if isempty(records)
        records = record;
    else
        records(end + 1) = record; %#ok<AGROW>
    end
end
summary = struct( ...
    "schema", "rotating_map_candidate_batch_v1", ...
    "requested_stop_time_s", stopTime, ...
    "case_order", selectedCases, ...
    "run_call_count", numel(selectedCases), ...
    "records", records, ...
    "formal_promotion", false);
summaryPath = fullfile(runRoot, ...
    "batch_" + string(stopTime) + "s_summary.json");
writelines(jsonencode(summary, "PrettyPrint", true), summaryPath);
end

function validateStopTime(stopTime)
if ~isscalar(stopTime) || ~isfinite(stopTime) || ...
        ~any(stopTime == [500, 14000])
    error("rotatingMap:UnsupportedStopTime", ...
        "Only the approved 500 s and 14000 s gates are supported.");
end
end

function winner = readWinner(runRoot)
decisionPath = fullfile(runRoot, "gate2_decision.json");
if ~isfile(decisionPath)
    error("rotatingMap:MissingGate2Decision", ...
        "The 14000 s gate requires gate2_decision.json.");
end
decision = jsondecode(fileread(decisionPath));
if ~isfield(decision, "eligible_for_14000") || ...
        ~decision.eligible_for_14000 || ~isfield(decision, "winner") || ...
        isempty(decision.winner)
    error("rotatingMap:LongRunNotAuthorized", ...
        "Gate 2 did not authorize a 14000 s run.");
end
winner = string(decision.winner);
if ~any(winner == ["C1", "C2", "C3"])
    error("rotatingMap:InvalidGate2Winner", ...
        "Gate 2 winner is not one of C1-C3.");
end
end

function record = runOneCase(repoRoot, runRoot, modelDir, bundleDir, ...
        caseId, stopTime)
candidateModelPath = fullfile(modelDir, caseId + "_model.slx");
bundlePath = fullfile(bundleDir, caseId + "_lookup.mat");
if ~isfile(candidateModelPath) || ~isfile(bundlePath)
    error("rotatingMap:MissingCaseInput", ...
        "Missing model or bundle for %s.", caseId);
end
caseParent = fullfile(runRoot, "runs", caseId);
if ~isfolder(caseParent)
    mkdir(caseParent);
end
outputDir = fullfile(caseParent, string(stopTime) + "s");
resultPath = fullfile(outputDir, "result.mat");
statusPath = fullfile(outputDir, "run_status.json");
recoverSavedResult = false;
if isfolder(outputDir)
    if isfile(statusPath)
        error("rotatingMap:RunAlreadyExists", ...
            "Refusing to overwrite or rerun %s.", outputDir);
    end
    if ~isfile(resultPath)
        error("rotatingMap:IncompleteRunArtifact", ...
            "Existing run directory has no recoverable result.mat: %s.", ...
            outputDir);
    end
    recoverSavedResult = true;
else
    createExclusiveDirectory(outputDir);
end

oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(modelDir, bundleDir, fullfile(repoRoot, "tests", "steady53"));
bundle = load(bundlePath);
variableSnapshot = captureBundleVariables(bundle);
variableCleanup = onCleanup(@() restoreBundleVariables(variableSnapshot)); %#ok<NASGU>
assignBundleVariables(bundle);

if recoverSavedResult
    saved = load(resultPath, "result");
    result = saved.result;
    if string(result.modelHashBefore) ~= sha256File(candidateModelPath) || ...
            (result.success && abs(result.tFinal_s - stopTime) > 1e-6)
        error("rotatingMap:SavedResultContractMismatch", ...
            "Saved result cannot be attributed to this model and gate.");
    end
    elapsed = -1;
else
    diaryPath = fullfile(outputDir, "matlab.log");
    diary(diaryPath);
    diaryCleanup = onCleanup(@() diary("off")); %#ok<NASGU>
    started = tic;
    try
        result = run_steady53_case(candidateModelPath, stopTime, true);
    catch exception
        result = runnerFailure(exception, sha256File(candidateModelPath));
    end
    elapsed = toc(started);
    diary("off");
    clear diaryCleanup
    save(resultPath, "result", "-v7.3");
end
[allFinite, signalNames] = writeSignals(result, outputDir);
lookupAudit = writeLookupAudit(result, bundle, outputDir);
lookupClear = lookupAssertionClear(result) && ...
    (isempty(lookupAudit) || all(lookupAudit.within_domain));
if result.success
    stopReason = "completed";
elseif strlength(result.errorId) > 0
    stopReason = result.errorId;
else
    stopReason = "failed_without_identifier";
end
status = struct( ...
    "schema", "rotating_map_run_status_v1", ...
    "case_id", caseId, ...
    "requested_stop_time_s", stopTime, ...
    "success", logical(result.success), ...
    "final_valid_time_s", result.tFinal_s, ...
    "stop_reason", stopReason, ...
    "error_id", string(result.errorId), ...
    "warning_ids", string(result.warningIds), ...
    "lookup_assertion_clear", lookupClear, ...
    "all_logged_values_finite", allFinite, ...
    "logged_signal_count", numel(signalNames), ...
    "elapsed_wall_time_s", elapsed, ...
    "elapsed_wall_time_available", ~recoverSavedResult, ...
    "recovered_from_saved_result", recoverSavedResult, ...
    "model_repository_path", relativePath(candidateModelPath, repoRoot), ...
    "model_sha256", sha256File(candidateModelPath), ...
    "bundle_repository_path", relativePath(bundlePath, repoRoot), ...
    "bundle_sha256", sha256File(bundlePath), ...
    "formal_promotion", false);
writelines(jsonencode(status, "PrettyPrint", true), statusPath);
record = status;
end

function result = runnerFailure(exception, modelHash)
result = struct( ...
    "success", false, ...
    "errorId", string(exception.identifier), ...
    "errorReport", string(getReport(exception, "extended", ...
        "hyperlinks", "off")), ...
    "tFinal_s", NaN, ...
    "t", [], ...
    "signals", struct(), ...
    "states", struct([]), ...
    "warningIds", strings(0, 1), ...
    "modelHashBefore", modelHash, ...
    "modelHashAfter", modelHash, ...
    "fileGenRoot", "");
end

function [allFinite, names] = writeSignals(result, outputDir)
names = string(fieldnames(result.signals));
allFinite = result.success && ~isempty(result.t) && ...
    all(isfinite(result.t));
if isempty(names) || isempty(result.t)
    return
end
signalTable = table(result.t(:), 'VariableNames', {'time_s'});
for name = names.'
    values = result.signals.(name);
    values = values(:);
    allFinite = allFinite && numel(values) == height(signalTable) && ...
        all(isfinite(values));
    signalTable.(name) = values;
end
writetable(signalTable, fullfile(outputDir, "signals.csv"));
end

function audit = writeLookupAudit(result, bundle, outputDir)
mapping = [ ...
    "compressor_lookup_speed_eff", "compressor_speed_bp"; ...
    "compressor_lookup_flow_eff", "compressor_flow_bp"; ...
    "compressor_lookup_speed_pr", "compressor_speed_bp"; ...
    "compressor_lookup_flow_pr", "compressor_flow_bp"; ...
    "turbine_lookup_expansion_ratio", "turbine_er_bp"; ...
    "turbine_lookup_speed_flow", "turbine_speed_bp"; ...
    "turbine_lookup_mass_flow", "turbine_mf_bp"; ...
    "turbine_lookup_speed_eff", "turbine_speed_bp"];
audit = table('Size', [0, 9], ...
    'VariableTypes', ["string", repmat("double", 1, 7), "logical"], ...
    'VariableNames', ["signal_name", "observed_min", "observed_max", ...
        "domain_min", "domain_max", "below_domain_count", ...
        "above_domain_count", "nonfinite_count", "within_domain"]);
if ~result.success || isempty(fieldnames(result.signals))
    writetable(audit, fullfile(outputDir, "lookup_domain_audit.csv"));
    return
end
for index = 1:size(mapping, 1)
    signalName = mapping(index, 1);
    axisName = mapping(index, 2);
    values = double(result.signals.(signalName)(:));
    axis = double(bundle.(axisName)(:));
    lower = min(axis);
    upper = max(axis);
    finiteValues = values(isfinite(values));
    if isempty(finiteValues)
        observedMin = NaN;
        observedMax = NaN;
    else
        observedMin = min(finiteValues);
        observedMax = max(finiteValues);
    end
    below = sum(values < lower);
    above = sum(values > upper);
    nonfinite = sum(~isfinite(values));
    within = below == 0 && above == 0 && nonfinite == 0;
    audit(end + 1, :) = {signalName, observedMin, observedMax, ... %#ok<AGROW>
        lower, upper, below, above, nonfinite, within};
end
writetable(audit, fullfile(outputDir, "lookup_domain_audit.csv"));
writelines(jsonencode(table2struct(audit), "PrettyPrint", true), ...
    fullfile(outputDir, "lookup_domain_audit.json"));
end

function clear = lookupAssertionClear(result)
parts = [string(result.errorId); string(result.errorReport); ...
    string(result.warningIds(:))];
text = lower(join(parts, newline));
markers = ["lookup", "assert", "extrapolat", "out of range", ...
    "out-of-range", "outside the table"];
clear = ~any(contains(text, markers));
end

function snapshot = captureBundleVariables(bundle)
names = string(fieldnames(bundle));
snapshot = repmat(struct("name", "", "existed", false, "value", []), ...
    numel(names), 1);
for index = 1:numel(names)
    name = names(index);
    existed = evalin("base", "exist('" + name + "','var') == 1");
    snapshot(index).name = name;
    snapshot(index).existed = existed;
    if existed
        snapshot(index).value = evalin("base", name);
    end
end
end

function assignBundleVariables(bundle)
names = string(fieldnames(bundle));
for name = names.'
    assignin("base", name, bundle.(name));
end
end

function restoreBundleVariables(snapshot)
for index = 1:numel(snapshot)
    name = snapshot(index).name;
    if snapshot(index).existed
        assignin("base", name, snapshot(index).value);
    else
        evalin("base", "clear('" + name + "')");
    end
end
end

function createExclusiveDirectory(pathValue)
parent = fileparts(pathValue);
if ~isfolder(parent)
    mkdir(parent);
end
pathObject = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createDirectory(pathObject, attributes);
catch exception
    if isfile(pathValue) || isfolder(pathValue)
        error("rotatingMap:RunAlreadyExists", ...
            "Refusing to overwrite or rerun %s.", pathValue);
    end
    rethrow(exception)
end
end

function assertUnderRunRoot(runRoot, repoRoot)
tmpRoot = canonicalPath(fullfile(repoRoot, "tmp"), true);
if ~startsWith(runRoot, tmpRoot + filesep)
    error("rotatingMap:RunRootOutsideTmp", ...
        "Run output must remain under repository tmp.");
end
end

function value = relativePath(pathValue, repoRoot)
pathValue = canonicalPath(pathValue, true);
if ~startsWith(pathValue, repoRoot + filesep)
    error("rotatingMap:PathOutsideRepository", ...
        "Path escaped the repository root: %s", pathValue);
end
value = extractAfter(pathValue, strlength(repoRoot) + 1);
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

function value = canonicalPath(pathValue, mustExist)
file = java.io.File(char(pathValue));
if mustExist && ~file.exists()
    error("rotatingMap:MissingInput", ...
        "Required input does not exist: %s", pathValue);
end
value = string(file.getCanonicalPath());
end
