function status = run_steady53_lineage_merge_diagnostic( ...
        runDir, repoRoot, injectedRunner)
%RUN_STEADY53_LINEAGE_MERGE_DIAGNOSTIC Execute the approved case once.
%   Production mode invokes run_steady53_case exactly once for 500 s. The
%   optional injected runner exists only so the zero-simulation contract can
%   be tested before the single approved production invocation is consumed.

arguments
    runDir {mustBeTextScalar}
    repoRoot {mustBeTextScalar}
    injectedRunner = []
end

repoRoot = canonicalPath(repoRoot);
runDir = validateRunDirectory(runDir, repoRoot);
candidatePath = fullfile(runDir, "candidate.slx");
auditPath = fullfile(runDir, "candidate_audit.json");
validateCandidateAudit(candidatePath, auditPath);
candidateHashBefore = sha256File(candidatePath);

runPath = fullfile(runDir, "run");
createDirectoryExclusive(runPath);
startedAt = isoTimestamp();
writeExclusiveText(fullfile(runPath, "experiment_started.json"), ...
    string(jsonencode(struct( ...
        "schema", "steady53_lineage_merge_started_v1", ...
        "started_at_utc", startedAt, ...
        "approved_run_limit", 1, ...
        "run_steady53_case_call_count_at_start", 0, ...
        "retry_count", 0, ...
        "rerun_forbidden", true), PrettyPrint=true)) + newline);

callCount = 0;
callReturned = false;
runResult = struct();
runnerException = [];
try
    if isempty(injectedRunner)
        runResult = run_steady53_case(candidatePath, 500, true);
    else
        if ~isa(injectedRunner, "function_handle")
            error("lineagemerge:InvalidTestRunner", ...
                "The injected runner must be a function handle.");
        end
        runResult = injectedRunner(candidatePath, 500, true);
    end
    callCount = 1;
    callReturned = true;
catch exception
    callCount = 1;
    runnerException = exception;
end

rawPath = fullfile(runPath, "raw_result.mat");
curvesPath = fullfile(runPath, "curves.csv");
rawPresent = false;
curvesPresent = false;
if callReturned
    save(rawPath, "runResult", "-v7.3");
    rawPresent = isfile(rawPath);
    try
        curves = validateAndBuildCurves(runResult);
        writetable(curves, curvesPath);
        curvesPresent = isfile(curvesPath);
    catch exception
        runnerException = appendException(runnerException, exception);
    end
end

candidateHashAfter = sha256File(candidatePath);
if candidateHashAfter ~= candidateHashBefore
    runnerException = appendException(runnerException, MException( ...
        "lineagemerge:CandidateChanged", ...
        "The diagnostic invocation changed the candidate model bytes."));
end

[experimentStatus, errorId, errorReport] = classifyRun( ...
    runResult, callReturned, runnerException, curvesPresent);
finalTime = [];
if callReturned && isfield(runResult, "tFinal_s") && ...
        isscalar(runResult.tFinal_s) && isfinite(runResult.tFinal_s)
    finalTime = double(runResult.tFinal_s);
end
status = struct( ...
    "schema", "steady53_lineage_merge_run_status_v1", ...
    "experiment_status", experimentStatus, ...
    "started_at_utc", startedAt, ...
    "completed_at_utc", isoTimestamp(), ...
    "run_steady53_case_call_count", callCount, ...
    "retry_count", 0, ...
    "rerun_forbidden", true, ...
    "requested_stop_time_s", 500, ...
    "final_time_s", finalTime, ...
    "call_returned", callReturned, ...
    "raw_result_present", rawPresent, ...
    "curves_present", curvesPresent, ...
    "raw_result_path", string(rawPath), ...
    "curves_path", string(curvesPath), ...
    "candidate_model_sha256_before", candidateHashBefore, ...
    "candidate_model_sha256_after", candidateHashAfter, ...
    "error_id", errorId, ...
    "error_report", errorReport, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);
statusPath = fullfile(runPath, "run_status.json");
writeExclusiveText(statusPath, ...
    string(jsonencode(status, PrettyPrint=true)) + newline);
status.run_status_path = string(statusPath);
end

function runDir = validateRunDirectory(runDir, repoRoot)
runDir = canonicalPath(runDir);
tmpRoot = canonicalPath(fullfile(repoRoot, "tmp"));
relative = extractAfter(runDir, strlength(tmpRoot) + 1);
if ~isfolder(runDir) || ~startsWith(runDir, tmpRoot + filesep) || ...
        strlength(relative) == 0 || contains(relative, filesep)
    error("lineagemerge:RunBoundary", ...
        "Run directory must be an existing direct child of repository tmp.");
end
end

function validateCandidateAudit(candidatePath, auditPath)
if ~isfile(candidatePath) || ~isfile(auditPath)
    error("lineagemerge:CandidateEvidenceMissing", ...
        "Candidate model or audit is missing.");
end
audit = jsondecode(fileread(auditPath));
expectedFrozen = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
expectedRoot = ...
    "a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159";
required = isfield(audit, "schema") && ...
    string(audit.schema) == "steady53_lineage_merge_candidate_v1" && ...
    isfield(audit, "frozen_model_sha256") && ...
    string(audit.frozen_model_sha256) == expectedFrozen && ...
    isfield(audit, "root_model_sha256") && ...
    string(audit.root_model_sha256) == expectedRoot && ...
    isfield(audit, "candidate_model_sha256") && ...
    string(audit.candidate_model_sha256) == sha256File(candidatePath) && ...
    isfield(audit, "assigned_state_count") && audit.assigned_state_count == 40 && ...
    isfield(audit, "changed_state_count") && audit.changed_state_count == 39 && ...
    isfield(audit, "unchanged_state_count") && audit.unchanged_state_count == 1 && ...
    isfield(audit, "block_inventory_unchanged") && ...
        logical(audit.block_inventory_unchanged) && ...
    isfield(audit, "topology_unchanged") && logical(audit.topology_unchanged) && ...
    isfield(audit, "non_ic_dialog_parameters_unchanged") && ...
        logical(audit.non_ic_dialog_parameters_unchanged) && ...
    isfield(audit, "solver_parameters_unchanged") && ...
        logical(audit.solver_parameters_unchanged) && ...
    isfield(audit, "simulation_call_count") && audit.simulation_call_count == 0 && ...
    isfield(audit, "paper_reproduced") && ~logical(audit.paper_reproduced) && ...
    isfield(audit, "author_initial_state_identified") && ...
        ~logical(audit.author_initial_state_identified) && ...
    isfield(audit, "formal_promotion") && ~logical(audit.formal_promotion);
if ~required
    error("lineagemerge:CandidateAuditMismatch", ...
        "Candidate audit does not match the approved 40-assignment contract.");
end
end

function curves = validateAndBuildCurves(runResult)
if ~isstruct(runResult) || ~isfield(runResult, "success") || ...
        ~isequal(runResult.success, true) || ~isfield(runResult, "tFinal_s") || ...
        ~isscalar(runResult.tFinal_s) || runResult.tFinal_s ~= 500 || ...
        ~isfield(runResult, "t") || ~isfield(runResult, "signals")
    error("lineagemerge:RunDidNotComplete", ...
        "The single diagnostic call did not complete at 500 s.");
end
requiredSignals = ["reactor_power", "turbine_power", "compressor_power"];
if ~all(isfield(runResult.signals, requiredSignals))
    error("lineagemerge:RunSignalsMissing", ...
        "The single diagnostic result lacks required power signals.");
end
time = double(runResult.t(:));
reactor = double(runResult.signals.reactor_power(:));
turbine = double(runResult.signals.turbine_power(:));
compressor = double(runResult.signals.compressor_power(:));
if numel(time) < 2 || numel(reactor) ~= numel(time) || ...
        numel(turbine) ~= numel(time) || numel(compressor) ~= numel(time) || ...
        any(~isfinite([time; reactor; turbine; compressor])) || ...
        time(1) ~= 0 || any(diff(time) <= 0) || time(end) ~= 500
    error("lineagemerge:RunSignalsInvalid", ...
        "Power signals must be finite and aligned on a 0-to-500 s time axis.");
end
electricalPaper = 0.98 .* (turbine - compressor);
electricalHistorical = 0.96527 .* (turbine - compressor);
curves = table(time, reactor, turbine, compressor, electricalPaper, ...
    electricalHistorical, 'VariableNames', {'time_s', 'reactor_W', ...
        'turbine_W', 'compressor_W', 'electrical_paper_eta_W', ...
        'electrical_historical_eta_W'});
end

function [status, errorId, errorReport] = classifyRun( ...
        runResult, callReturned, runnerException, curvesPresent)
errorId = "";
errorReport = "";
if ~isempty(runnerException)
    status = "numerical_or_contract_failure";
    errorId = string(runnerException.identifier);
    errorReport = string(getReport( ...
        runnerException, "extended", "hyperlinks", "off"));
elseif ~callReturned
    status = "numerical_or_contract_failure";
elseif ~isfield(runResult, "success") || ~isequal(runResult.success, true)
    status = "completed_model_failure";
    if isfield(runResult, "errorId")
        errorId = string(runResult.errorId);
    end
    if isfield(runResult, "errorReport")
        errorReport = string(runResult.errorReport);
    end
elseif ~curvesPresent
    status = "numerical_or_contract_failure";
else
    status = "completed_success";
end
end

function combined = appendException(existing, added)
if isempty(existing)
    combined = added;
else
    combined = addCause(existing, added);
end
end

function createDirectoryExclusive(pathValue)
pathObject = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
try
    java.nio.file.Files.createDirectory(pathObject, ...
        javaArray("java.nio.file.attribute.FileAttribute", 0));
catch exception
    if isfile(pathValue) || isfolder(pathValue)
        error("lineagemerge:RunExists", ...
            "The one-shot run directory already exists; rerun is forbidden.");
    end
    rethrow(exception)
end
end

function writeExclusiveText(pathValue, payload)
pathObject = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
try
    channel = java.nio.file.Files.newByteChannel(pathObject, options);
catch exception
    if isfile(pathValue) || isfolder(pathValue)
        error("lineagemerge:OutputExists", ...
            "Refusing to overwrite an existing diagnostic artifact.");
    end
    rethrow(exception)
end
cleanup = onCleanup(@() closeChannel(channel)); %#ok<NASGU>
bytes = unicode2native(char(string(payload)), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(typecast(uint8(bytes), "int8"));
while buffer.hasRemaining()
    written = channel.write(buffer);
    if written <= 0
        error("lineagemerge:StatusWriteStalled", ...
            "The exclusive status write made no progress.");
    end
end
channel.force(true);
channel.close();
clear cleanup
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

function value = canonicalPath(pathValue)
value = string(java.io.File(char(pathValue)).getCanonicalPath());
end

function value = isoTimestamp()
value = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function closeChannel(channel)
if ~isempty(channel) && channel.isOpen()
    channel.close();
end
end
