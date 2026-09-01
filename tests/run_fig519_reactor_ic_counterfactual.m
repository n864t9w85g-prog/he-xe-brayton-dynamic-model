function status = run_fig519_reactor_ic_counterfactual(runDir)
%RUN_FIG519_REACTOR_IC_COUNTERFACTUAL Execute the one approved 500 s run.
%   The existence of runDir/run is the durable one-shot marker.  This
%   function never retries, never saves a model, and preserves success or
%   failure evidence below the unique exploration directory.

arguments
    runDir {mustBeTextScalar}
end

repo = string(fileparts(fileparts(mfilename("fullpath"))));
if string(runDir) == "__fig519_test_write_exclusive__"
    status = testExclusiveTextCreation(repo);
    return
end
runDir = validateExistingRunDirectory(runDir, fullfile(repo, "tmp"));
candidatePath = fullfile(runDir, "candidate.slx");
auditPath = fullfile(runDir, "patch_audit.json");
sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
referencePath = fullfile(repo, "tmp", ...
    "fig519_initialization_20260831_A1", "raw_reference.mat");
if ~isfile(candidatePath) || ~isfile(auditPath)
    error("fig519cf:CandidateMissing", ...
        "Candidate and patch_audit.json must exist before the one-shot run.");
end
audit = jsondecode(fileread(auditPath));
validatePatchAuditIdentity(audit, candidatePath, sourcePath);
if sha256File(referencePath) ~= ...
        "185d59ca6e55647ad14fb5f23599bc85e6566f8da2ca6120f42a0ef8dedbb648"
    error("fig519cf:ReferenceHashMismatch", ...
        "The fixed Task 6 raw reference is missing or changed.");
end

runPath = fullfile(runDir, "run");
createDirectoryExclusive(runPath);
startedAt = isoTimestamp();
writeExclusiveText(fullfile(runPath, "experiment_started.json"), ...
    string(jsonencode(struct( ...
        "experiment_schema", "steady53_fig519_reactor_ic_one_shot_v1", ...
        "started_at_utc", startedAt, ...
        "approved_run_limit", 1, ...
        "run_steady53_case_call_count_at_start", 0, ...
        "rerun_forbidden", true), PrettyPrint=true)) + newline);

identityBefore = identitySnapshot(audit, sourcePath, candidatePath);
referenceLoaded = load(referencePath, "runResult");
if ~isfield(referenceLoaded, "runResult") || ...
        ~isstruct(referenceLoaded.runResult) || ...
        ~referenceLoaded.runResult.success || ...
        referenceLoaded.runResult.tFinal_s ~= 500
    error("fig519cf:ReferenceInvalid", ...
        "Fixed raw reference is not a successful 500 s runResult.");
end
referenceResult = referenceLoaded.runResult;
writeCurves(fullfile(runPath, "reference_curves.csv"), referenceResult);

runResult = emptyFailureResult();
runnerException = [];
try
    % This is the only executable call in the repository Task 7 runner.
    runResult = run_steady53_case(candidatePath, 500, true);
catch exception
    runnerException = exception;
    runResult.success = false;
    runResult.errorId = string(exception.identifier);
    runResult.errorReport = string(getReport( ...
        exception, "extended", "hyperlinks", "off"));
end

rawPath = fullfile(runPath, "raw_result.mat");
save(rawPath, "runResult", "-v7.3");
candidateCsv = fullfile(runPath, "candidate_curves.csv");
curvesWritten = false;
if isfield(runResult, "success") && runResult.success
    try
        writeCurves(candidateCsv, runResult);
        curvesWritten = true;
    catch exception
        if isempty(runnerException)
            runnerException = exception;
        else
            runnerException = addCause(runnerException, exception);
        end
    end
end

identityAfter = identitySnapshot(audit, sourcePath, candidatePath);
identityUnchanged = isequal(identityBefore, identityAfter);
if ~identityUnchanged && isempty(runnerException)
    runnerException = MException("fig519cf:IdentityChanged", ...
        "Source/candidate/runtime/protected identity changed during the run.");
end

if ~isempty(runnerException) || ~identityUnchanged
    experimentStatus = "runner_or_hash_gate_failed";
elseif ~runResult.success
    experimentStatus = "completed_model_failure";
elseif ~curvesWritten || runResult.tFinal_s ~= 500
    experimentStatus = "completed_incomplete_output";
else
    experimentStatus = "completed_success";
end
completedAt = isoTimestamp();

artifacts = artifactRecords(candidatePath, auditPath, ...
    rawPath, fullfile(runPath, "reference_curves.csv"), candidateCsv, ...
    curvesWritten);
status = struct( ...
    "run_schema", "steady53_fig519_reactor_ic_counterfactual_run_v1", ...
    "experiment_status", experimentStatus, ...
    "started_at_utc", startedAt, ...
    "completed_at_utc", completedAt, ...
    "run_steady53_case_call_count", 1, ...
    "retry_count", 0, ...
    "rerun_forbidden", true, ...
    "candidate_success", logical(runResult.success), ...
    "candidate_final_time_s", finiteOrNull(runResult.tFinal_s), ...
    "candidate_error_id", string(runResult.errorId), ...
    "candidate_error_report", string(runResult.errorReport), ...
    "runner_exception_id", exceptionId(runnerException), ...
    "runner_exception_report", exceptionReport(runnerException), ...
    "identity_unchanged", identityUnchanged, ...
    "identity_before", identityBefore, ...
    "identity_after", identityAfter, ...
    "artifacts", artifacts, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);
writeExclusiveText(fullfile(runPath, "run_status.json"), ...
    string(jsonencode(status, PrettyPrint=true)) + newline);
end

function runDir = validateExistingRunDirectory(runDir, tmpRoot)
runDir = string(runDir);
if ~startsWith(runDir, filesep) || ~isfolder(runDir)
    error("fig519cf:RunDirInvalid", ...
        "runDir must be an existing absolute directory.");
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalRun = canonicalPath(runDir);
if canonicalRun == canonicalTmp || ~startsWith(canonicalRun, canonicalTmp + filesep)
    error("fig519cf:RunDirOutsideTmp", "runDir must remain below tmp/.");
end
assertNoSymlinkAncestors(runDir, canonicalTmp);
runDir = canonicalRun;
end

function validatePatchAuditIdentity(audit, candidatePath, sourcePath)
expected = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
if string(audit.source_sha256) ~= expected || ...
        string(audit.source_sha256_after) ~= expected || ...
        string(audit.candidate_value_identity) ~= ...
            "figure_5_19_digitized_t10_proxy_not_author_t0" || ...
        audit.candidate_value_W ~= 3186507.937 || ...
        ~audit.source_hash_unchanged || audit.paper_reproduced || ...
        audit.author_initial_state_identified || audit.formal_promotion || ...
        string(audit.changed_blocks) ~= "reactor/Integrator6" || ...
        string(audit.changed_parameters) ~= "InitialCondition" || ...
        sha256File(sourcePath) ~= expected || ...
        sha256File(candidatePath) ~= string(audit.candidate_sha256)
    error("fig519cf:PatchAuditMismatch", ...
        "patch_audit.json does not satisfy the exact-one-change identity.");
end
states = audit.state_initial_conditions;
if numel(states) ~= 40 || nnz(~[states.unchanged]) ~= 1
    error("fig519cf:PatchStateMismatch", ...
        "Patch audit must contain exactly one changed IC among 40 states.");
end
changed = states(~[states.unchanged]);
if string(changed.path) ~= "reactor/Integrator6" || ...
        ~audit.solver_contract.unchanged || ...
        ~audit.semantic_snapshot.unchanged || ...
        numel(audit.runtime_dependencies) ~= 9 || ...
        numel(audit.mat_files) ~= 4 || numel(audit.property_files) ~= 2 || ...
        numel(audit.protected_files) ~= 34
    error("fig519cf:PatchContractIncomplete", ...
        "Patch audit exact-one-change contracts are incomplete.");
end
end

function snapshot = identitySnapshot(audit, sourcePath, candidatePath)
runtime = recalcRecords(audit.runtime_dependencies);
protected = recalcRecords(audit.protected_files);
snapshot = struct( ...
    "source_sha256", sha256File(sourcePath), ...
    "candidate_sha256", sha256File(candidatePath), ...
    "runtime_dependencies", runtime, ...
    "mat_files", runtime(endsWith(string({runtime.name}), ".mat")), ...
    "property_files", runtime(ismember(string({runtime.name}), ...
        ["HeXe_property_simulink.m", "Lithium_property_simulink.m"])), ...
    "protected_files", protected);
end

function output = recalcRecords(records)
output = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "sha256", ""), numel(records), 1);
for index = 1:numel(records)
    filePath = string(records(index).absolute_path);
    if ~isfile(filePath)
        error("fig519cf:IdentityFileMissing", ...
            "Identity file is missing: %s", filePath);
    end
    assertNoSymlinkAncestors(filePath, fileparts(filePath));
    output(index) = struct("name", string(records(index).name), ...
        "repository_relative_path", ...
            string(records(index).repository_relative_path), ...
        "absolute_path", canonicalPath(filePath), ...
        "sha256", sha256File(filePath));
    if output(index).sha256 ~= string(records(index).before_sha256) || ...
            output(index).sha256 ~= string(records(index).after_sha256)
        error("fig519cf:IdentityContractMismatch", ...
            "Identity file differs from patch audit: %s", filePath);
    end
end
end

function writeCurves(filePath, result)
requiredSignals = ["reactor_power", "turbine_power", "compressor_power"];
if ~isfield(result, "t") || ~isfield(result, "signals") || ...
        ~all(isfield(result.signals, requiredSignals))
    error("fig519cf:RunSignalsMissing", ...
        "runResult does not contain the three contracted power signals.");
end
time = double(result.t(:));
reactor = double(result.signals.reactor_power(:));
turbine = double(result.signals.turbine_power(:));
compressor = double(result.signals.compressor_power(:));
if numel(time) < 2 || numel(reactor) ~= numel(time) || ...
        numel(turbine) ~= numel(time) || numel(compressor) ~= numel(time) || ...
        any(~isfinite([time; reactor; turbine; compressor])) || ...
        any(diff(time) <= 0)
    error("fig519cf:RunSignalsInvalid", ...
        "Power curves must be finite and share a strictly increasing time vector.");
end
if isfile(filePath) || isfolder(filePath) || java.nio.file.Files.isSymbolicLink( ...
        java.nio.file.Paths.get(char(filePath), javaArray("java.lang.String", 0)))
    error("fig519cf:OutputExists", "Refusing to overwrite '%s'.", filePath);
end
file = fopen(filePath, "w", "n", "UTF-8");
if file < 0
    error("fig519cf:WriteFailed", "Could not create '%s'.", filePath);
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "time_s,reactor_W,turbine_W,compressor_W\n");
fprintf(file, "%.17g,%.17g,%.17g,%.17g\n", ...
    [time, reactor, turbine, compressor].');
end

function records = artifactRecords(candidatePath, auditPath, ...
        rawPath, referenceCsv, candidateCsv, curvesWritten)
paths = [string(candidatePath); string(auditPath); string(rawPath); ...
    string(referenceCsv)];
identities = ["candidate_slx"; "patch_audit"; "raw_result"; ...
    "reference_curves"];
if curvesWritten
    paths(end + 1, 1) = string(candidateCsv);
    identities(end + 1, 1) = "candidate_curves";
end
repo = string(fileparts(fileparts(mfilename("fullpath"))));
records = repmat(struct("identity", "", ...
    "repository_relative_path", "", "absolute_path", "", ...
    "sha256", "", "bytes", 0, "storage", ...
    "external_tmp_not_copied"), numel(paths), 1);
for index = 1:numel(paths)
    info = dir(paths(index));
    records(index) = struct("identity", identities(index), ...
        "repository_relative_path", relativeToRepo(paths(index), repo), ...
        "absolute_path", canonicalPath(paths(index)), ...
        "sha256", sha256File(paths(index)), "bytes", info.bytes, ...
        "storage", "external_tmp_not_copied");
end
end

function result = emptyFailureResult()
result = struct("success", false, "errorId", "", "errorReport", "", ...
    "tFinal_s", NaN, "t", [], "signals", struct(), "states", struct([]));
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

function assertNoSymlinkAncestors(pathValue, stopAt)
probe = string(pathValue);
stopAt = canonicalPath(stopAt);
while strlength(probe) >= strlength(stopAt)
    javaPath = java.nio.file.Paths.get(char(probe), ...
        javaArray("java.lang.String", 0));
    if java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:SymlinkForbidden", "Symlinked path: %s", probe);
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
error("fig519cf:PathNotAnchored", "Path is not anchored below its root.");
end

function relative = relativeToRepo(pathValue, repo)
canonical = canonicalPath(pathValue);
repo = canonicalPath(repo);
if ~startsWith(canonical, repo + filesep)
    error("fig519cf:PathOutsideRepo", "Artifact path is outside repository.");
end
relative = replace(extractAfter(canonical, strlength(repo + filesep)), ...
    filesep, "/");
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end

function writeExclusiveText(filePath, text)
javaPath = java.nio.file.Paths.get(char(filePath), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createFile(javaPath, attributes);
catch exception
    if isfile(filePath) || isfolder(filePath) || ...
            java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:OutputExists", ...
            "Refusing to overwrite '%s'.", filePath);
    end
    rethrow(exception)
end
file = fopen(filePath, "w", "n", "UTF-8");
if file < 0
    error("fig519cf:WriteFailed", "Could not create '%s'.", filePath);
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s", text);
end

function status = testExclusiveTextCreation(repo)
% Non-simulation R2025a compatibility probe for the one-shot file helper.
testDir = string(tempname(fullfile(repo, "tmp")));
mkdir(testDir);
cleanup = onCleanup(@() rmdir(testDir, "s")); %#ok<NASGU>
filePath = fullfile(testDir, "exclusive.txt");
writeExclusiveText(filePath, "first");
if string(fileread(filePath)) ~= "first"
    error("fig519cf:ExclusiveWriteTestFailed", ...
        "Exclusive-write test content mismatch.");
end
try
    writeExclusiveText(filePath, "second");
    error("fig519cf:ExclusiveWriteTestFailed", ...
        "Exclusive-write helper overwrote an existing file.");
catch exception
    if string(exception.identifier) ~= "fig519cf:OutputExists"
        rethrow(exception)
    end
end
claimPath = fullfile(testDir, "one_shot_claim");
createDirectoryExclusive(claimPath);
try
    createDirectoryExclusive(claimPath);
    error("fig519cf:ExclusiveWriteTestFailed", ...
        "One-shot directory claim was acquired twice.");
catch exception
    if string(exception.identifier) ~= "fig519cf:ExperimentAlreadyStarted"
        rethrow(exception)
    end
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "overwrite_rejected", true, "second_directory_claim_rejected", true);
disp("FIG519_EXCLUSIVE_WRITE_TEST=PASS")
end

function createDirectoryExclusive(directoryPath)
javaPath = java.nio.file.Paths.get(char(directoryPath), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createDirectory(javaPath, attributes);
catch exception
    if isfolder(directoryPath) || isfile(directoryPath) || ...
            java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:ExperimentAlreadyStarted", ...
            "The one-shot directory already exists: '%s'.", directoryPath);
    end
    rethrow(exception)
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("fig519cf:HashFailed", "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\''") + "'";
end
