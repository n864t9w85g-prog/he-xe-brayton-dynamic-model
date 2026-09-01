function status = run_fig519_ihx_r2_hexe_shift(runDir, repoRoot)
%RUN_FIG519_IHX_R2_HEXE_SHIFT Execute the consumed A3 500 s attempt once.
%   This exploration-only runner validates the A3 two-state/one-delta
%   candidate, claims a unique run directory, invokes the blocking steady53
%   case exactly once, and records only artifacts that actually exist.

arguments
    runDir {mustBeTextScalar}
    repoRoot {mustBeTextScalar}
end

if string(runDir) == "__a3_test_hooks__"
    hookRoot = validateRepoRoot(repoRoot);
    status = struct( ...
        "testExclusiveTextCreation", @() testExclusiveTextCreation(hookRoot), ...
        "testExclusiveDirectoryCreation", ...
            @() testExclusiveDirectoryCreation(hookRoot));
    return
end

repoRoot = validateRepoRoot(repoRoot);
runDir = validateExistingRunDirectory(runDir, fullfile(repoRoot, "tmp"));
[~, runName] = fileparts(runDir);
if string(runName) ~= "fig519_ihx_r2_hexe_20260901_A3"
    error("fig519a3run:RunNameMismatch", ...
        "The A3 run directory must use the frozen attempt name.");
end

candidatePath = fullfile(runDir, "candidate.slx");
auditPath = fullfile(runDir, "patch_audit.json");
sourcePath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
assertRegularFile(candidatePath, "candidate model");
assertRegularFile(auditPath, "candidate patch audit");
assertRegularFile(sourcePath, "captured immutable source model");
audit = jsondecode(fileread(auditPath));
validatePatchAuditIdentity(audit, candidatePath, sourcePath, repoRoot);
referenceSeries(repoRoot);

runPath = fullfile(runDir, "run");
createDirectoryExclusive(runPath);
runIdentity = pathIdentity(runPath, "directory");
candidateIdentity = pathIdentity(candidatePath, "file");
auditIdentity = pathIdentity(auditPath, "file");
startedAt = isoTimestamp();
startRecord = struct( ...
    "experiment_schema", "steady53_fig519_ihx_r2_hexe_shift_started_v1", ...
    "attempt_id", "20260901_A3", ...
    "started_at_utc", startedAt, ...
    "approved_run_limit", 1, ...
    "run_steady53_case_call_count_at_start", 0, ...
    "retry_count", 0, ...
    "rerun_forbidden", true);
assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
    candidatePath, auditIdentity, auditPath);
writeExclusiveText(fullfile(runPath, "experiment_started.json"), ...
    string(jsonencode(startRecord, PrettyPrint=true)) + newline);

identityBefore = identitySnapshot(audit, sourcePath, candidatePath, repoRoot);
runResult = emptyFailureResult();
runnerException = [];
rawWritten = false;
candidateCurvesWritten = false;
referenceCurvesWritten = false;

disp("BEGIN_A3_500")
try
    runResult = run_steady53_case(candidatePath, 500, true);
catch exception
    runnerException = exception;
    runResult.success = false;
    runResult.errorId = string(exception.identifier);
    runResult.errorReport = string(getReport( ...
        exception, "extended", "hyperlinks", "off"));
end

rawPath = fullfile(runPath, "raw_result.mat");
candidateCsv = fullfile(runPath, "candidate_curves.csv");
referenceCsv = fullfile(runPath, "reference_curves.csv");
try
    assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
        candidatePath, auditIdentity, auditPath);
    saveRawExclusive(rawPath, runResult, runPath);
    rawWritten = true;
catch exception
    runnerException = appendException(runnerException, exception);
end

if logicalField(runResult, "success")
    try
        writePowerAndStateCurves(candidateCsv, runResult);
        candidateCurvesWritten = true;
    catch exception
        runnerException = appendException(runnerException, exception);
    end
end
try
    writeReferenceCurves(referenceCsv, repoRoot);
    referenceCurvesWritten = true;
catch exception
    runnerException = appendException(runnerException, exception);
end

try
    identityAfter = identitySnapshot(audit, sourcePath, candidatePath, repoRoot);
    identityUnchanged = isequal(identityBefore, identityAfter);
    if ~identityUnchanged
        runnerException = appendException(runnerException, MException( ...
            "fig519a3run:IdentityChanged", ...
            "Candidate, source, runtime, protected, or formal identity changed."));
    end
catch exception
    identityAfter = struct();
    identityUnchanged = false;
    runnerException = appendException(runnerException, exception);
end

if ~isempty(runnerException) || ~identityUnchanged
    experimentStatus = "runner_or_hash_gate_failed";
elseif ~logicalField(runResult, "success")
    experimentStatus = "completed_model_failure";
elseif ~rawWritten || ~candidateCurvesWritten || ...
        ~referenceCurvesWritten || finiteOrNull(runResult.tFinal_s) ~= 500
    experimentStatus = "completed_incomplete_output";
else
    experimentStatus = "completed_success";
end

status = struct( ...
    "run_schema", "steady53_fig519_ihx_r2_hexe_shift_run_v1", ...
    "attempt_id", "20260901_A3", ...
    "candidate_value_identity", ...
        "figure_5_18a_t0_visual_proxy_not_author_initial_state", ...
    "experiment_status", experimentStatus, ...
    "started_at_utc", startedAt, ...
    "completed_at_utc", isoTimestamp(), ...
    "run_steady53_case_call_count", 1, ...
    "retry_count", 0, ...
    "rerun_forbidden", true, ...
    "candidate_success", logicalField(runResult, "success"), ...
    "candidate_final_time_s", finiteOrNull(fieldOr(runResult, "tFinal_s", NaN)), ...
    "candidate_error_id", string(fieldOr(runResult, "errorId", "")), ...
    "candidate_error_report", string(fieldOr(runResult, "errorReport", "")), ...
    "runner_exception_id", exceptionId(runnerException), ...
    "runner_exception_report", exceptionReport(runnerException), ...
    "identity_unchanged", identityUnchanged, ...
    "identity_before", identityBefore, ...
    "identity_after", identityAfter, ...
    "artifacts", artifactRecords(runDir, candidatePath, auditPath, ...
        rawPath, candidateCsv, referenceCsv), ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);
assertSameIdentity(runIdentity, runPath, "run directory");
writeExclusiveText(fullfile(runPath, "run_status.json"), ...
    string(jsonencode(status, PrettyPrint=true)) + newline);
end

function validatePatchAuditIdentity(audit, candidatePath, sourcePath, repoRoot)
expectedSource = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
requiredText = struct( ...
    "patch_schema", "steady53_fig519_ihx_r2_hexe_shift_candidate_v1", ...
    "attempt_id", "20260901_A3", ...
    "candidate_value_identity", ...
        "figure_5_18a_t0_visual_proxy_not_author_initial_state");
names = string(fieldnames(requiredText));
for index = 1:numel(names)
    name = names(index);
    if ~isfield(audit, name) || string(audit.(name)) ~= requiredText.(name)
        error("fig519a3run:PatchAuditMismatch", ...
            "The patch audit field %s does not match A3.", name);
    end
end
if string(audit.source_sha256) ~= expectedSource || ...
        string(audit.source_sha256_after) ~= expectedSource || ...
        string(audit.source_model_sha256) ~= expectedSource || ...
        ~logical(audit.source_hash_unchanged) || ...
        sha256File(sourcePath) ~= expectedSource || ...
        sha256File(candidatePath) ~= string(audit.candidate_sha256)
    error("fig519a3run:PatchHashMismatch", ...
        "Source or candidate hash does not match the A3 patch audit.");
end
if audit.paper_reproduced || audit.author_initial_state_identified || ...
        audit.formal_promotion || audit.changed_state_count ~= 2 || ...
        audit.unchanged_state_count ~= 38 || audit.state_count ~= 40 || ...
        audit.solver_parameter_count ~= 37 || ...
        audit.update_diagram_count ~= 1
    error("fig519a3run:PatchContractMismatch", ...
        "Patch count, update, or promotion contracts do not match A3.");
end
if abs(audit.anchor_K - 1200.0000000000000) > 1e-12 || ...
        abs(audit.delta_T_K - (-193.6037139151003)) > 1e-12 || ...
        abs(audit.old_gap_K - 147.7852469306997) > 1e-12 || ...
        abs(audit.new_gap_K - audit.old_gap_K) > 1e-12
    error("fig519a3run:SharedDeltaMismatch", ...
        "The common-delta and preserved-gap contract does not match A3.");
end
validateChangedStates(audit.changed_states);
validateStateInventory(audit.state_initial_conditions);
if ~audit.solver_contract.unchanged || ...
        audit.solver_contract.parameter_count ~= 37 || ...
        ~audit.semantic_snapshot.unchanged || ~audit.model_workspace.unchanged || ...
        numel(audit.runtime_dependencies) ~= 9 || ...
        numel(audit.protected_files) ~= 34
    error("fig519a3run:PatchInventoryIncomplete", ...
        "Patch solver, semantic, workspace, runtime, or protected audit is incomplete.");
end
validateUnchangedRecords(audit.runtime_dependencies, repoRoot, ...
    "runtime dependency");
validateUnchangedRecords(audit.protected_files, repoRoot, "protected file");
validateFormalRecords(audit.formal_files, repoRoot);
end

function validateChangedStates(changed)
if numel(changed) ~= 2
    error("fig519a3run:ChangedStateShape", ...
        "Exactly two dependent state changes are required.");
end
expectedPaths = [ ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"];
expectedOld = [1245.8184669844006; 1393.6037139151003];
expectedNew = [1052.2147530693003; 1200.0000000000000];
[actualPaths, order] = sort(string({changed.path}).');
[expectedPaths, expectedOrder] = sort(expectedPaths);
if ~isequal(actualPaths, expectedPaths)
    error("fig519a3run:ChangedStatePathMismatch", ...
        "The changed state paths do not match A3.");
end
changed = changed(order);
expectedOld = expectedOld(expectedOrder);
expectedNew = expectedNew(expectedOrder);
for index = 1:2
    if abs(changed(index).old_initial_condition_K - expectedOld(index)) > 1e-12 || ...
            abs(changed(index).new_initial_condition_K - expectedNew(index)) > 1e-12 || ...
            abs(changed(index).delta_T_K - (-193.6037139151003)) > 1e-12
        error("fig519a3run:ChangedStateValueMismatch", ...
            "A changed state does not share the frozen A3 delta.");
    end
end
end

function validateStateInventory(states)
if numel(states) ~= 40 || sum([states.unchanged]) ~= 38
    error("fig519a3run:StateInventoryMismatch", ...
        "The audit must preserve exactly 38 of 40 state ICs.");
end
changed = states(~[states.unchanged]);
paths = sort(string({changed.source_path}).');
expected = sort([ ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"]);
if ~isequal(paths, expected)
    error("fig519a3run:StateInventoryPathMismatch", ...
        "The two changed inventory paths do not match A3.");
end
end

function snapshot = identitySnapshot(audit, sourcePath, candidatePath, repoRoot)
snapshot = struct( ...
    "source_sha256", sha256File(sourcePath), ...
    "candidate_sha256", sha256File(candidatePath), ...
    "runtime_dependencies", recalcRecords(audit.runtime_dependencies, repoRoot), ...
    "protected_files", recalcRecords(audit.protected_files, repoRoot), ...
    "formal_files", recalcFormalRecords(audit.formal_files, repoRoot), ...
    "reference_curves", referenceIdentities(repoRoot));
end

function validateUnchangedRecords(records, repoRoot, label)
actual = recalcRecords(records, repoRoot);
for index = 1:numel(records)
    if ~logical(records(index).unchanged) || ...
            string(records(index).before_sha256) ~= actual(index).sha256 || ...
            string(records(index).after_sha256) ~= actual(index).sha256
        error("fig519a3run:IdentityContractMismatch", ...
            "%s differs from the candidate audit: %s", ...
            label, actual(index).repository_relative_path);
    end
end
end

function output = recalcRecords(records, repoRoot)
output = repmat(struct("repository_relative_path", "", "sha256", ""), ...
    numel(records), 1);
for index = 1:numel(records)
    relative = string(records(index).repository_relative_path);
    filePath = resolveCapturedPath(repoRoot, relative);
    assertRegularFile(filePath, "captured identity dependency");
    output(index) = struct("repository_relative_path", relative, ...
        "sha256", sha256File(filePath));
end
end

function validateFormalRecords(records, repoRoot)
actual = recalcFormalRecords(records, repoRoot);
for index = 1:numel(records)
    if ~logical(records(index).unchanged) || ...
            logical(records(index).exists_before) ~= actual(index).exists || ...
            logical(records(index).exists_after) ~= actual(index).exists || ...
            string(records(index).before_sha256) ~= actual(index).sha256 || ...
            string(records(index).after_sha256) ~= actual(index).sha256
        error("fig519a3run:FormalIdentityMismatch", ...
            "A formal root identity differs from the candidate audit.");
    end
end
end

function output = recalcFormalRecords(records, repoRoot)
output = repmat(struct("repository_relative_path", "", ...
    "exists", false, "sha256", ""), numel(records), 1);
for index = 1:numel(records)
    relative = string(records(index).repository_relative_path);
    filePath = resolveCapturedPath(repoRoot, relative);
    exists = isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath);
    hash = "";
    if exists
        assertRegularFile(filePath, "captured formal root file");
        hash = sha256File(filePath);
    end
    output(index) = struct("repository_relative_path", relative, ...
        "exists", exists, "sha256", hash);
end
end

function filePath = resolveCapturedPath(repoRoot, relative)
relative = replace(string(relative), "/", filesep);
if strlength(relative) == 0 || startsWith(relative, filesep) || ...
        any(split(relative, filesep) == "..")
    error("fig519a3run:CapturedPathInvalid", ...
        "Every executed dependency must use a captured repository-relative path.");
end
filePath = fullfile(repoRoot, relative);
if ~isContainedLexically(filePath, repoRoot)
    error("fig519a3run:CapturedPathOutsideRepo", ...
        "Captured dependency escaped repoRoot.");
end
end

function writePowerAndStateCurves(filePath, result)
[time, reactor, turbine, compressor] = powerSeries(result);
average = stateSeries(result, ...
    "IHX/IHX_region_2/T_c1_average_Integrator", time);
outlet = stateSeries(result, ...
    "IHX/IHX_region_2/T_c2_out_Integrator", time);
content = "time_s,reactor_W,turbine_W,compressor_W,ihx_r2_average_K,ihx_r2_outlet_K\n" + ...
    string(sprintf("%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n", ...
        [time, reactor, turbine, compressor, average, outlet].'));
writeExclusiveText(filePath, content);
end

function writeReferenceCurves(filePath, repoRoot)
[time, reactor, turbine, compressor] = referenceSeries(repoRoot);
content = "time_s,reactor_W,turbine_W,compressor_W\n" + ...
    string(sprintf("%.17g,%.17g,%.17g,%.17g\n", ...
        [time, reactor, turbine, compressor].'));
writeExclusiveText(filePath, content);
end

function [time, reactor, turbine, compressor] = referenceSeries(repoRoot)
baselineDir = fullfile(repoRoot, "data", "provenance", "steady53", ...
    "fig5_19", "model_baseline");
names = ["baseline_P_sw.csv"; "baseline_WT_sw.csv"; "baseline_Wc_sw.csv"];
hashes = [ ...
    "288a9b031d31f8168517ea30d06f712d72c4d1dc31fd911f0a266aaa3023999f"; ...
    "28b852e9b997af51a860905e53da096821ddfbdd310857d16e9df0761ca2ab23"; ...
    "f44a9bca2c006780f287e4f3a7199f63d26348cc18ad261d4ad89570b0e9ad5c"];
series = cell(3, 1);
for index = 1:3
    filePath = fullfile(baselineDir, names(index));
    assertRegularFile(filePath, "captured model-baseline curve");
    if sha256File(filePath) ~= hashes(index)
        error("fig519a3run:ReferenceHashMismatch", ...
            "A fixed model-baseline curve is missing or changed: %s", names(index));
    end
    series{index} = readmatrix(filePath);
    if size(series{index}, 2) ~= 2
        error("fig519a3run:ReferenceShapeMismatch", ...
            "A fixed model-baseline curve must have two columns.");
    end
end
time = double(series{1}(:, 1));
reactor = double(series{1}(:, 2));
turbine = double(series{2}(:, 2));
compressor = double(series{3}(:, 2));
if ~isequal(time, double(series{2}(:, 1)), double(series{3}(:, 1)))
    error("fig519a3run:ReferenceTimeMismatch", ...
        "The three fixed model-baseline curves do not share one time vector.");
end
validateAlignedFinite(time, reactor, turbine, compressor);
end

function records = referenceIdentities(repoRoot)
baselineDir = fullfile(repoRoot, "data", "provenance", "steady53", ...
    "fig5_19", "model_baseline");
names = ["baseline_P_sw.csv"; "baseline_WT_sw.csv"; "baseline_Wc_sw.csv"];
records = repmat(struct("name", "", "sha256", ""), 3, 1);
for index = 1:3
    filePath = fullfile(baselineDir, names(index));
    records(index) = struct("name", names(index), "sha256", sha256File(filePath));
end
end

function [time, reactor, turbine, compressor] = powerSeries(result)
required = ["reactor_power", "turbine_power", "compressor_power"];
if ~isfield(result, "t") || ~isfield(result, "signals") || ...
        ~all(isfield(result.signals, required))
    error("fig519a3run:RunSignalsMissing", ...
        "runResult lacks one or more contracted power signals.");
end
time = double(result.t(:));
reactor = double(result.signals.reactor_power(:));
turbine = double(result.signals.turbine_power(:));
compressor = double(result.signals.compressor_power(:));
validateAlignedFinite(time, reactor, turbine, compressor);
end

function values = stateSeries(result, suffix, time)
if ~isfield(result, "states") || ~isstruct(result.states)
    error("fig519a3run:RunStatesMissing", ...
        "runResult lacks the contracted IHX state inventory.");
end
matches = endsWith(string({result.states.path}).', suffix);
if nnz(matches) ~= 1
    error("fig519a3run:RunStatePathMismatch", ...
        "Expected exactly one state ending in %s.", suffix);
end
values = double(result.states(matches).data(:));
if numel(values) ~= numel(time) || any(~isfinite(values))
    error("fig519a3run:RunStateInvalid", ...
        "IHX state data must be finite and aligned to runResult.t.");
end
end

function validateAlignedFinite(time, reactor, turbine, compressor)
if numel(time) < 2 || numel(reactor) ~= numel(time) || ...
        numel(turbine) ~= numel(time) || ...
        numel(compressor) ~= numel(time) || ...
        any(~isfinite([time; reactor; turbine; compressor])) || ...
        any(diff(time) <= 0)
    error("fig519a3run:RunSignalsInvalid", ...
        "Power curves must be finite and share a strictly increasing time vector.");
end
end

function saveRawExclusive(rawPath, runResult, runPath)
stagingDir = fullfile(runPath, ".raw_" + string(java.util.UUID.randomUUID()));
createDirectoryExclusive(stagingDir);
stagingIdentity = pathIdentity(stagingDir, "directory");
cleanup = onCleanup(@() cleanupEmptyRawStaging(stagingDir, stagingIdentity));
stagingPath = fullfile(stagingDir, "raw_result.mat");
save(stagingPath, "runResult", "-v7.3");
assertRegularFile(stagingPath, "staged raw result");
moveFileExclusive(stagingPath, rawPath);
clear cleanup
cleanupEmptyRawStaging(stagingDir, stagingIdentity);
end

function cleanupEmptyRawStaging(stagingDir, expectedIdentity)
if ~isfolder(stagingDir) || isSymbolicLink(stagingDir)
    return
end
try
    assertSameIdentity(expectedIdentity, stagingDir, "raw staging directory");
    listing = dir(stagingDir);
    names = string({listing.name});
    if ~any(~ismember(names, [".", ".."]))
        rmdir(stagingDir);
    end
catch
    % Preserve unexpected or replaced paths as evidence; never recurse.
end
end

function moveFileExclusive(sourcePath, destinationPath)
options = javaArray("java.nio.file.CopyOption", 1);
options(1) = java.nio.file.StandardCopyOption.ATOMIC_MOVE;
try
    java.nio.file.Files.move(nioPath(sourcePath), nioPath(destinationPath), options);
catch exception
    if isfile(destinationPath) || isfolder(destinationPath) || ...
            isSymbolicLink(destinationPath)
        error("fig519a3run:OutputExists", ...
            "Refusing to overwrite '%s'.", destinationPath);
    end
    rethrow(exception)
end
end

function records = artifactRecords(runDir, candidatePath, auditPath, ...
        rawPath, candidateCsv, referenceCsv)
paths = [string(candidatePath); string(auditPath); string(rawPath); ...
    string(candidateCsv); string(referenceCsv)];
identities = ["candidate_slx"; "patch_audit"; "raw_result"; ...
    "candidate_curves"; "reference_curves"];
present = false(size(paths));
for index = 1:numel(paths)
    present(index) = isfile(paths(index)) && ~isSymbolicLink(paths(index));
end
paths = paths(present);
identities = identities(present);
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
records = repmat(struct("identity", "", ...
    "repository_relative_path", "", "absolute_path", "", ...
    "sha256", "", "bytes", 0, "storage", "external_tmp_not_copied"), ...
    numel(paths), 1);
for index = 1:numel(paths)
    assertRegularFile(paths(index), "actual run artifact");
    info = dir(paths(index));
    records(index) = struct("identity", identities(index), ...
        "repository_relative_path", relativeIfWithinRepo(paths(index), repoRoot), ...
        "absolute_path", canonicalPath(paths(index)), ...
        "sha256", sha256File(paths(index)), "bytes", info.bytes, ...
        "storage", "external_tmp_not_copied");
end
if ~isContainedLexically(runDir, fileparts(runDir))
    error("fig519a3run:RunContainmentLost", "Run containment changed.");
end
end

function result = emptyFailureResult()
result = struct("success", false, "errorId", "", "errorReport", "", ...
    "tFinal_s", NaN, "t", [], "signals", struct(), "states", struct([]));
end

function output = appendException(existing, added)
if isempty(existing)
    output = added;
else
    output = addCause(existing, added);
end
end

function value = fieldOr(item, name, fallback)
if isstruct(item) && isfield(item, name)
    value = item.(name);
else
    value = fallback;
end
end

function value = logicalField(item, name)
value = false;
if isstruct(item) && isfield(item, name) && ...
        islogical(item.(name)) && isscalar(item.(name))
    value = item.(name);
end
end

function value = finiteOrNull(value)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    value = [];
end
end

function value = exceptionId(exception)
if isempty(exception)
    value = "";
else
    value = string(exception.identifier);
end
end

function value = exceptionReport(exception)
if isempty(exception)
    value = "";
else
    value = string(getReport(exception, "extended", "hyperlinks", "off"));
end
end

function timestamp = isoTimestamp()
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function repoRoot = validateRepoRoot(repoRoot)
repoRoot = canonicalPath(repoRoot);
detected = string(fileparts(fileparts(mfilename("fullpath"))));
if repoRoot ~= canonicalPath(detected)
    error("fig519a3run:RepoRootMismatch", ...
        "repoRoot must contain this captured runner.");
end
assertNoSymlinkAncestors(repoRoot, repoRoot);
end

function runDir = validateExistingRunDirectory(runDir, tmpRoot)
runDir = string(runDir);
if ~startsWith(runDir, filesep)
    error("fig519a3run:RunDirMustBeAbsolute", "runDir must be absolute.");
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalRun = canonicalPath(runDir);
if canonicalRun == canonicalTmp || ...
        ~startsWith(canonicalRun, canonicalTmp + filesep)
    error("fig519a3run:RunDirOutsideTmp", ...
        "runDir must remain below captured repoRoot/tmp.");
end
assertNoSymlinkAncestors(runDir, canonicalTmp);
assertRealDirectory(runDir, "A3 candidate directory");
runDir = canonicalRun;
end

function assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
        candidatePath, auditIdentity, auditPath)
assertSameIdentity(runIdentity, runPath, "run directory");
assertSameIdentity(candidateIdentity, candidatePath, "candidate model");
assertSameIdentity(auditIdentity, auditPath, "patch audit");
end

function assertNoSymlinkAncestors(pathValue, stopAt)
probe = string(java.io.File(string(pathValue)).getAbsolutePath());
stopAt = canonicalPath(stopAt);
while true
    if isSymbolicLink(probe)
        error("fig519a3run:SymlinkForbidden", "Symlinked path: %s", probe);
    end
    if canonicalPath(probe) == stopAt
        return
    end
    parent = string(fileparts(probe));
    if parent == probe
        break
    end
    probe = parent;
end
error("fig519a3run:PathNotAnchored", ...
    "Path is not anchored below its required root.");
end

function assertRegularFile(pathValue, label)
if isSymbolicLink(pathValue) || ~isfile(pathValue) || ...
        ~java.nio.file.Files.isRegularFile(nioPath(pathValue), ...
            javaArray("java.nio.file.LinkOption", 0))
    error("fig519a3run:RegularFileRequired", ...
        "%s must be a non-symlink regular file: %s", label, pathValue);
end
end

function assertRealDirectory(pathValue, label)
if isSymbolicLink(pathValue) || ~isfolder(pathValue) || ...
        ~java.nio.file.Files.isDirectory(nioPath(pathValue), ...
            javaArray("java.nio.file.LinkOption", 0))
    error("fig519a3run:RealDirectoryRequired", ...
        "%s must be a non-symlink directory: %s", label, pathValue);
end
end

function identity = pathIdentity(pathValue, kind)
if kind == "file"
    assertRegularFile(pathValue, "identity target");
else
    assertRealDirectory(pathValue, "identity target");
end
attributes = java.nio.file.Files.readAttributes(nioPath(pathValue), ...
    "basic:fileKey,isRegularFile,isDirectory,isSymbolicLink", ...
    javaArray("java.nio.file.LinkOption", 0));
identity = struct("absolute_path", lexicalAbsolute(pathValue), ...
    "file_key", string(attributes.get("fileKey")), "kind", string(kind));
if strlength(identity.file_key) == 0 || identity.file_key == "null"
    error("fig519a3run:FileKeyUnavailable", ...
        "Filesystem identity is unavailable for %s.", pathValue);
end
end

function assertSameIdentity(expected, pathValue, label)
actual = pathIdentity(pathValue, expected.kind);
if actual.absolute_path ~= expected.absolute_path || ...
        actual.file_key ~= expected.file_key
    error("fig519a3run:PathIdentityChanged", ...
        "%s identity changed: %s", label, pathValue);
end
end

function createDirectoryExclusive(directoryPath)
try
    permissions = java.nio.file.attribute.PosixFilePermissions.fromString("rwx------");
    attributes = javaArray("java.nio.file.attribute.FileAttribute", 1);
    attributes(1) = java.nio.file.attribute.PosixFilePermissions.asFileAttribute(permissions);
catch
    attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
end
try
    java.nio.file.Files.createDirectory(nioPath(directoryPath), attributes);
catch exception
    if isfile(directoryPath) || isfolder(directoryPath) || isSymbolicLink(directoryPath)
        error("fig519a3run:ExperimentAlreadyStarted", ...
            "The one-shot directory already exists: '%s'.", directoryPath);
    end
    rethrow(exception)
end
end

function writeExclusiveText(filePath, content)
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
try
    channel = java.nio.file.Files.newByteChannel(nioPath(filePath), options);
catch exception
    if isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath)
        error("fig519a3run:OutputExists", ...
            "Refusing to overwrite '%s'.", filePath);
    end
    rethrow(exception)
end
cleanup = onCleanup(@() closeChannel(channel));
bytes = unicode2native(char(string(content)), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(typecast(uint8(bytes), "int8"));
while buffer.hasRemaining()
    channel.write(buffer);
end
channel.force(true);
channel.close();
clear cleanup
end

function closeChannel(channel)
try
    if ~isempty(channel) && channel.isOpen()
        channel.close();
    end
catch
end
end

function hash = sha256File(filePath)
assertRegularFile(filePath, "SHA-256 input");
digest = java.security.MessageDigest.getInstance("SHA-256");
stream = java.nio.file.Files.newInputStream(nioPath(filePath), ...
    javaArray("java.nio.file.OpenOption", 0));
cleanup = onCleanup(@() stream.close());
buffer = zeros(1, 65536, "int8");
count = stream.read(buffer, 0, numel(buffer));
while count >= 0
    if count > 0
        digest.update(buffer(1:count));
    end
    count = stream.read(buffer, 0, numel(buffer));
end
bytes = typecast(digest.digest(), "uint8");
hash = lower(join(string(dec2hex(bytes, 2)).', ""));
end

function value = isSymbolicLink(pathValue)
value = java.nio.file.Files.isSymbolicLink(nioPath(pathValue));
end

function value = isContainedLexically(pathValue, root)
path = nioPath(pathValue).toAbsolutePath().normalize();
base = nioPath(root).toAbsolutePath().normalize();
value = path.startsWith(base) && ~path.equals(base);
end

function output = lexicalAbsolute(pathValue)
output = string(nioPath(pathValue).toAbsolutePath().normalize().toString());
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end

function output = relativeIfWithinRepo(pathValue, repoRoot)
absolute = lexicalAbsolute(pathValue);
root = lexicalAbsolute(repoRoot);
if absolute.startsWith(root + filesep)
    output = replace(extractAfter(absolute, strlength(root + filesep)), ...
        filesep, "/");
else
    output = "";
end
end

function pathValue = nioPath(pathValue)
pathValue = java.nio.file.Paths.get(char(string(pathValue)), ...
    javaArray("java.lang.String", 0));
end

function status = testExclusiveTextCreation(repoRoot)
sandbox = createHookSandbox(repoRoot);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
filePath = fullfile(sandbox.path, "exclusive.txt");
writeExclusiveText(filePath, "first");
if string(fileread(filePath)) ~= "first"
    error("fig519a3run:HookContentMismatch", ...
        "Exclusive text helper wrote unexpected content.");
end
rejected = false;
try
    writeExclusiveText(filePath, "second");
catch exception
    if string(exception.identifier) ~= "fig519a3run:OutputExists"
        rethrow(exception)
    end
    rejected = true;
end
if ~rejected
    error("fig519a3run:HookOverwriteAccepted", ...
        "Exclusive text helper accepted an overwrite.");
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "overwrite_rejected", true);
end

function status = testExclusiveDirectoryCreation(repoRoot)
sandbox = createHookSandbox(repoRoot);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
claimPath = fullfile(sandbox.path, "claim");
createDirectoryExclusive(claimPath);
rejected = false;
try
    createDirectoryExclusive(claimPath);
catch exception
    if string(exception.identifier) ~= "fig519a3run:ExperimentAlreadyStarted"
        rethrow(exception)
    end
    rejected = true;
end
if ~rejected
    error("fig519a3run:HookSecondClaimAccepted", ...
        "Exclusive directory helper accepted a second claim.");
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "second_claim_rejected", true);
end

function sandbox = createHookSandbox(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
assertRealDirectory(tmpRoot, "repository tmp directory");
sandboxPath = fullfile(tmpRoot, ...
    ".fig519a3_runner_hook_" + string(java.util.UUID.randomUUID()));
createDirectoryExclusive(sandboxPath);
sandbox = struct("path", sandboxPath, ...
    "identity", pathIdentity(sandboxPath, "directory"));
end

function cleanupHookSandbox(sandbox)
if ~isfolder(sandbox.path) || isSymbolicLink(sandbox.path)
    return
end
try
    assertSameIdentity(sandbox.identity, sandbox.path, "hook sandbox");
    listing = dir(sandbox.path);
    names = string({listing.name});
    children = names(~ismember(names, [".", ".."]));
    for index = 1:numel(children)
        child = fullfile(sandbox.path, children(index));
        if isSymbolicLink(child) || isfolder(child)
            if isfolder(child) && ~isSymbolicLink(child)
                childListing = dir(child);
                childNames = string({childListing.name});
                if ~any(~ismember(childNames, [".", ".."]))
                    rmdir(child);
                end
            end
        elseif isfile(child)
            delete(child);
        end
    end
    listing = dir(sandbox.path);
    names = string({listing.name});
    if ~any(~ismember(names, [".", ".."]))
        rmdir(sandbox.path);
    end
catch
    % Retain untrusted or replaced test paths; never delete recursively.
end
end
