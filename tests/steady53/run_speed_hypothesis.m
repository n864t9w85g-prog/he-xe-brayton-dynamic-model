function output = run_speed_hypothesis(options)
%RUN_SPEED_HYPOTHESIS Evaluate 55090 rpm on an isolated, auditable copy.
%   With no arguments, this performs the approved 500 s experiment and
%   atomically publishes a validated current-evidence pointer under
%   tmp/steady53. Controlled options exist only for exploration tests.

arguments
    options (1, 1) struct = struct()
end

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = normalizeOptions(options, root);
sourceModel = string(erase(string(getFileName(config.sourcePath)), ".slx"));
copyModel = "final_steady_speed55090";

if config.validateCurrentOnly
    output = validateCurrentEvidence(config.tmpRoot, ...
        config.expectedSourceHash);
    return
end

% Ownership checks precede hashing, directory creation, copying, and every
% MATLAB/Simulink environment mutation.
if bdIsLoaded(sourceModel)
    error("steady53:SourceModelAlreadyLoaded", ...
        "Source model '%s' is already loaded; no artifacts were changed.", ...
        sourceModel);
end
if bdIsLoaded(copyModel)
    error("steady53:ExplorationModelAlreadyLoaded", ...
        "Exploration model '%s' is already loaded; it was not closed " + ...
        "or overwritten.", copyModel);
end

runId = makeRunId();
runDirectory = fullfile(config.tmpRoot, "runs", runId);
copyPath = fullfile(runDirectory, "final_steady_speed55090.slx");
resultPath = fullfile(runDirectory, "speed55090_result.mat");
startedAt = utcTimestamp();
lifecycle = emptyLifecycle();
primaryException = [];
result = struct();
summary = struct();
modelCleanup = [];

sourceHashBefore = sha256File(config.sourcePath);
if sourceHashBefore ~= config.expectedSourceHash
    mismatch = MException("steady53:UnexpectedSourceHash", ...
        "Source model hash is %s, expected %s; no artifact was created.", ...
        sourceHashBefore, config.expectedSourceHash);
    try
        sourceHashAfter = sha256File(config.sourcePath);
    catch hashException
        mismatch = addCause(mismatch, hashException);
        throw(mismatch)
    end
    throwSourceGuarded(mismatch, {}, config.sourcePath, ...
        sourceHashBefore, sourceHashAfter);
end

% Compatibility files are never assumed to be ours. A valid marker is
% checked; a markerless legacy pair is strictly audited and migrated first.
if config.publishCurrent
    try
        prepareCurrentEvidence(config, sourceHashBefore);
    catch exception
        try
            sourceHashAfter = sha256File(config.sourcePath);
        catch hashException
            exception = addCause(exception, hashException);
            throw(exception)
        end
        throwSourceGuarded(exception, {}, config.sourcePath, ...
            sourceHashBefore, sourceHashAfter);
    end
end

try
    makeOwnedDirectory(runDirectory);
    lifecycle = captureLifecycle(lifecycle);
    addpath(root);
    copyfile(config.sourcePath, copyPath);
    injectFailure(config, "after_copy");

    lifecycle.fileGenerationRoot = string(tempname(runDirectory));
    mkdir(lifecycle.fileGenerationRoot);
    lifecycle.fileGenerationRootOwned = true;
    Simulink.fileGenControl("set", ...
        "CacheFolder", fullfile(lifecycle.fileGenerationRoot, "cache"), ...
        "CodeGenFolder", fullfile(lifecycle.fileGenerationRoot, "codegen"), ...
        "createDir", true);

    % Guard exists before load_system, so a partial load is also owned.
    modelCleanup = onCleanup(@() closeModelNoSave(copyModel));
    load_system(copyPath);
    changedBlockPath = copyModel + "/TAC/Constant";
    oldValue = string(get_param(changedBlockPath, "Value"));
    oldStopTime = string(get_param(copyModel, "StopTime"));
    newValue = "55090";
    newStopTime = string(num2str(config.stopTime_s, "%.17g"));
    set_param(changedBlockPath, "Value", newValue);
    set_param(copyModel, "StopTime", newStopTime);
    save_system(copyModel, copyPath);
    close_system(copyModel, 0);
    injectFailure(config, "after_save");

    compressorMap = load(fullfile(root, "hexe_compressor_lookup.mat"), ...
        "N_design", "speed_bp");
    injectFailure(config, "before_runner");
    result = run_steady53_case(copyPath, config.stopTime_s, true);

    copyHash = sha256File(copyPath);
    completedAt = utcTimestamp();
    status = simulationStatus(result);
    summary = compactSummary(result);
    summary = attachEvidenceMetadata(summary, runId, runDirectory, ...
        sourceHashBefore, "", copyHash, startedAt, completedAt, status);
    summary.sourcePath = string(config.sourcePath);
    summary.explorationCopyPath = string(copyPath);
    summary.resultPath = string(resultPath);
    summary.expectedSourceHash = config.expectedSourceHash;
    summary.sourceHashBefore = sourceHashBefore;
    summary.sourceHashAfter = "";
    summary.sourceUnchanged = false;
    summary.explorationCopyHash = copyHash;
    summary.changedBlockPath = changedBlockPath;
    summary.changedBlockOldValue = oldValue;
    summary.changedBlockNewValue = newValue;
    summary.stopTimeOldValue = oldStopTime;
    summary.stopTimeNewValue = newStopTime;
    summary.actualComponentSpeed_rpm = str2double(newValue);
    summary.compressorDesignSpeed_rpm = compressorMap.N_design;
    summary.compressorSpeedBreakpointMin = min(compressorMap.speed_bp(:));
    summary.compressorSpeedBreakpointMax = max(compressorMap.speed_bp(:));
    summary.normalizedCompressorSpeed = ...
        summary.actualComponentSpeed_rpm / compressorMap.N_design;
    summary.compressorSpeedInRange = ...
        summary.normalizedCompressorSpeed >= ...
            summary.compressorSpeedBreakpointMin && ...
        summary.normalizedCompressorSpeed <= ...
            summary.compressorSpeedBreakpointMax;
    result = attachEvidenceMetadata(result, runId, runDirectory, ...
        sourceHashBefore, "", copyHash, startedAt, completedAt, status);
catch exception
    primaryException = exception;
end

try
    cleanupExceptions = cleanupLifecycle( ...
        lifecycle, copyModel, modelCleanup);
catch cleanupException
    cleanupExceptions = {cleanupException};
end
try
    sourceHashAfter = sha256File(config.sourcePath);
    sourceHashAfterAvailable = true;
catch hashException
    cleanupExceptions{end + 1, 1} = hashException;
    sourceHashAfter = "";
    sourceHashAfterAvailable = false;
end

if sourceHashAfterAvailable && sourceHashAfter ~= sourceHashBefore
    rewriteException = sourceRewriteException(config.sourcePath, ...
        sourceHashBefore, sourceHashAfter, primaryException, ...
        cleanupExceptions);
    bestEffortFailureRecord(runDirectory, runId, sourceHashBefore, ...
        sourceHashAfter, startedAt, rewriteException);
    throw(rewriteException)
end
if ~isempty(primaryException) || ~isempty(cleanupExceptions)
    exception = mergeOrdinaryExceptions(primaryException, cleanupExceptions);
    bestEffortFailureRecord(runDirectory, runId, sourceHashBefore, ...
        sourceHashAfter, startedAt, exception);
    throw(exception)
end

% Publish only after cleanup and the post-run source guard succeed. This
% entire evidence phase has its own source guard because serialization,
% validation, staging, or marker publication can also fail.
try
    summary.sourceHash = sourceHashAfter;
    summary.sourceHashAfter = sourceHashAfter;
    summary.sourceUnchanged = true;
    result.sourceHash = sourceHashAfter;
    result.sourceHashAfter = sourceHashAfter;
    saveEvidenceAtomic(resultPath, result, summary);
    resultHash = sha256File(resultPath);
    verifyRunEvidence(resultPath, copyPath, summary, resultHash);
    if config.publishCurrent
        publishCurrentEvidence(config.tmpRoot, runId, runDirectory, ...
            copyPath, resultPath, sourceHashAfter, ...
            summary.explorationCopyHash, resultHash, summary.status, ...
            summary.completedAt);
        summary.current = validateCurrentEvidence( ...
            config.tmpRoot, sourceHashAfter);
    end
    sourceHashAfterPublish = sha256File(config.sourcePath);
    if sourceHashAfterPublish ~= sourceHashBefore
        error("steady53:SourceChangedDuringEvidencePublish", ...
            "Source changed during evidence publication.");
    end
catch exception
    try
        sourceHashAfterPublish = sha256File(config.sourcePath);
        sourceHashAfterPublishAvailable = true;
    catch hashException
        exception = addCause(exception, hashException);
        sourceHashAfterPublish = "";
        sourceHashAfterPublishAvailable = false;
    end
    if sourceHashAfterPublishAvailable && ...
            sourceHashAfterPublish ~= sourceHashBefore
        exception = sourceRewriteException(config.sourcePath, ...
            sourceHashBefore, sourceHashAfterPublish, exception, {});
    end
    bestEffortFailureRecord(runDirectory, runId, sourceHashBefore, ...
        sourceHashAfterPublish, startedAt, exception);
    throw(exception)
end
output = summary;
end

function config = normalizeOptions(options, root)
allowed = ["tmpRoot", "stopTime_s", "publishCurrent", ...
    "injectFailureAt", "expectedSourceHash", "validateCurrentOnly"];
unknown = setdiff(string(fieldnames(options)), allowed);
if ~isempty(unknown)
    error("steady53:UnsupportedOption", ...
        "Unsupported option(s): %s", strjoin(unknown, ", "));
end
config = struct( ...
    "sourcePath", string(fullfile(root, "final_steady_24a.slx")), ...
    "tmpRoot", string(fullfile(root, "tmp", "steady53")), ...
    "stopTime_s", 500, ...
    "publishCurrent", true, ...
    "injectFailureAt", "", ...
    "expectedSourceHash", ...
        "08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a", ...
    "validateCurrentOnly", false);
names = string(fieldnames(options));
for index = 1:numel(names)
    config.(names(index)) = options.(names(index));
end
config.tmpRoot = string(config.tmpRoot);
config.expectedSourceHash = string(config.expectedSourceHash);
config.injectFailureAt = string(config.injectFailureAt);
if ~startsWith(config.tmpRoot, filesep)
    error("steady53:TmpRootMustBeAbsolute", ...
        "tmpRoot must be an absolute path.");
end
if ~isscalar(config.stopTime_s) || ~isnumeric(config.stopTime_s) || ...
        ~isfinite(config.stopTime_s) || config.stopTime_s <= 0
    error("steady53:InvalidStopTime", ...
        "stopTime_s must be one positive finite numeric scalar.");
end
if ~isscalar(config.publishCurrent) || ~islogical(config.publishCurrent)
    error("steady53:InvalidPublishCurrent", ...
        "publishCurrent must be a logical scalar.");
end
if ~isscalar(config.validateCurrentOnly) || ...
        ~islogical(config.validateCurrentOnly)
    error("steady53:InvalidValidateMode", ...
        "validateCurrentOnly must be a logical scalar.");
end
allowedFailures = ["", "after_copy", "after_save", "before_runner"];
if ~isscalar(config.injectFailureAt) || ...
        ~ismember(config.injectFailureAt, allowedFailures)
    error("steady53:InvalidFailureInjection", ...
        "injectFailureAt is not an approved exploration test hook.");
end
if ~isscalar(config.expectedSourceHash) || ...
        strlength(config.expectedSourceHash) ~= 64
    error("steady53:InvalidExpectedSourceHash", ...
        "expectedSourceHash must be one 64-character SHA-256 string.");
end
end

function prepareCurrentEvidence(config, sourceHash)
paths = currentPaths(config.tmpRoot);
hasMarker = isfile(paths.marker);
hasCopy = isfile(paths.copy);
hasResult = isfile(paths.result);
if hasMarker
    if ~(hasCopy && hasResult)
        error("steady53:UnownedExplorationArtifact", ...
            "Current marker exists without both compatibility artifacts.");
    end
    validateCurrentEvidence(config.tmpRoot, sourceHash);
    return
end
if ~hasCopy && ~hasResult
    return
end
if xor(hasCopy, hasResult)
    error("steady53:UnownedExplorationArtifact", ...
        "A markerless one-sided artifact will not be overwritten.");
end

legacy = load(paths.result, "result", "summary");
if ~isfield(legacy, "result") || ~isfield(legacy, "summary")
    error("steady53:UnownedExplorationArtifact", ...
        "Markerless result lacks result and summary evidence.");
end
copyHash = sha256File(paths.copy);
expectedStop = string(num2str(config.stopTime_s, "%.17g"));
summary = legacy.summary;
owned = all(isfield(summary, { ...
    'sourceHashBefore', 'explorationCopyHash', 'changedBlockPath', ...
    'changedBlockOldValue', 'changedBlockNewValue', ...
    'stopTimeOldValue', 'stopTimeNewValue'})) && ...
    string(summary.sourceHashBefore) == sourceHash && ...
    string(summary.explorationCopyHash) == copyHash && ...
    string(summary.changedBlockPath) == ...
        "final_steady_speed55090/TAC/Constant" && ...
    string(summary.changedBlockOldValue) == "66100" && ...
    string(summary.changedBlockNewValue) == "55090" && ...
    string(summary.stopTimeOldValue) == "800" && ...
    string(summary.stopTimeNewValue) == expectedStop;
if ~owned
    error("steady53:UnownedExplorationArtifact", ...
        "Markerless artifacts failed the strict ownership audit.");
end

adoptRunId = "legacy_" + extractAfter(makeRunId(), "run_");
adoptDirectory = fullfile(config.tmpRoot, "runs", adoptRunId);
makeOwnedDirectory(adoptDirectory);
adoptCopy = fullfile(adoptDirectory, "final_steady_speed55090.slx");
adoptResult = fullfile(adoptDirectory, "speed55090_result.mat");
copyfile(paths.copy, adoptCopy);
timestamp = utcTimestamp();
status = simulationStatus(legacy.result);
summary = attachEvidenceMetadata(summary, adoptRunId, adoptDirectory, ...
    sourceHash, sourceHash, copyHash, timestamp, timestamp, status);
summary.sourceHashAfter = sourceHash;
summary.sourceUnchanged = true;
summary.explorationCopyPath = string(adoptCopy);
summary.resultPath = string(adoptResult);
summary.adoptedLegacy = true;
result = attachEvidenceMetadata(legacy.result, adoptRunId, ...
    adoptDirectory, sourceHash, sourceHash, copyHash, timestamp, ...
    timestamp, status);
result.adoptedLegacy = true;
saveEvidenceAtomic(adoptResult, result, summary);
resultHash = sha256File(adoptResult);
verifyRunEvidence(adoptResult, adoptCopy, summary, resultHash);
publishCurrentEvidence(config.tmpRoot, adoptRunId, adoptDirectory, ...
    adoptCopy, adoptResult, sourceHash, copyHash, resultHash, status, ...
    timestamp);
validateCurrentEvidence(config.tmpRoot, sourceHash);
end

function current = publishCurrentEvidence(tmpRoot, runId, runDirectory, ...
        runCopy, runResult, sourceHash, copyHash, resultHash, status, ...
        completedAt)
paths = currentPaths(tmpRoot);
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
stageDirectory = fullfile(tmpRoot, ".publish_" + makeRunId());
makeOwnedDirectory(stageDirectory);
stageCleanup = onCleanup(@() removeOwnedDirectory(stageDirectory));
stageCopy = fullfile(stageDirectory, "final_steady_speed55090.slx");
stageResult = fullfile(stageDirectory, "speed55090_result.mat");
stageMarker = fullfile(stageDirectory, "speed55090_current.mat");
copyfile(runCopy, stageCopy);
copyfile(runResult, stageResult);
if sha256File(stageCopy) ~= copyHash || ...
        sha256File(stageResult) ~= resultHash
    error("steady53:PublishStagingHashMismatch", ...
        "Staged evidence does not match immutable run evidence.");
end
current = struct( ...
    "schemaVersion", 1, ...
    "runId", string(runId), ...
    "runDirectory", string(runDirectory), ...
    "sourceHash", string(sourceHash), ...
    "copyHash", string(copyHash), ...
    "resultHash", string(resultHash), ...
    "status", string(status), ...
    "completedAt", string(completedAt), ...
    "copyPath", string(paths.copy), ...
    "resultPath", string(paths.result), ...
    "runCopyPath", string(runCopy), ...
    "runResultPath", string(runResult));
save(stageMarker, "current");
moveReplace(stageCopy, paths.copy);
moveReplace(stageResult, paths.result);
% Marker is deliberately last: interrupted earlier moves are detectable.
moveReplace(stageMarker, paths.marker);
clear stageCleanup
end

function current = validateCurrentEvidence(tmpRoot, expectedSourceHash)
paths = currentPaths(tmpRoot);
if ~(isfile(paths.marker) && isfile(paths.copy) && isfile(paths.result))
    error("steady53:CurrentEvidenceIncomplete", ...
        "Current marker, copy, and result must all exist.");
end
loaded = load(paths.marker, "current");
if ~isfield(loaded, "current")
    error("steady53:CurrentEvidenceInvalid", ...
        "Current marker lacks the current pointer.");
end
current = loaded.current;
required = {'schemaVersion', 'runId', 'runDirectory', 'sourceHash', ...
    'copyHash', 'resultHash', 'status', 'copyPath', 'resultPath', ...
    'runCopyPath', 'runResultPath'};
if ~all(isfield(current, required)) || current.schemaVersion ~= 1 || ...
        string(current.sourceHash) ~= string(expectedSourceHash) || ...
        string(current.copyPath) ~= string(paths.copy) || ...
        string(current.resultPath) ~= string(paths.result) || ...
        ~isfile(current.runCopyPath) || ~isfile(current.runResultPath)
    error("steady53:CurrentEvidenceInvalid", ...
        "Marker schema, source, paths, or run artifacts are invalid.");
end
if sha256File(paths.copy) ~= string(current.copyHash) || ...
        sha256File(current.runCopyPath) ~= string(current.copyHash) || ...
        sha256File(paths.result) ~= string(current.resultHash) || ...
        sha256File(current.runResultPath) ~= string(current.resultHash)
    error("steady53:CurrentEvidenceHashMismatch", ...
        "Compatibility artifacts do not match marker/run hashes.");
end
fixed = load(paths.result, "result", "summary");
immutable = load(current.runResultPath, "result", "summary");
if ~isfield(fixed, "result") || ~isfield(fixed, "summary") || ...
        ~isfield(immutable, "result") || ~isfield(immutable, "summary") || ...
        string(fixed.result.runId) ~= string(current.runId) || ...
        string(fixed.summary.runId) ~= string(current.runId) || ...
        string(immutable.result.runId) ~= string(current.runId) || ...
        string(immutable.summary.runId) ~= string(current.runId) || ...
        string(fixed.summary.copyHash) ~= string(current.copyHash) || ...
        string(fixed.summary.sourceHash) ~= string(current.sourceHash)
    error("steady53:CurrentEvidenceCrossReferenceMismatch", ...
        "Marker, result, summary, and immutable run metadata disagree.");
end
end

function verifyRunEvidence(resultPath, copyPath, summary, resultHash)
if sha256File(copyPath) ~= string(summary.copyHash) || ...
        sha256File(resultPath) ~= string(resultHash)
    error("steady53:RunEvidenceHashMismatch", ...
        "Immutable run evidence failed its internal hash audit.");
end
loaded = load(resultPath, "result", "summary");
if string(loaded.result.runId) ~= string(summary.runId) || ...
        string(loaded.summary.runId) ~= string(summary.runId) || ...
        string(loaded.result.copyHash) ~= string(summary.copyHash) || ...
        string(loaded.summary.sourceHash) ~= string(summary.sourceHash)
    error("steady53:RunEvidenceCrossReferenceMismatch", ...
        "Immutable result and summary metadata are inconsistent.");
end
end

function saveEvidenceAtomic(resultPath, result, summary)
stagePath = resultPath + ".stage_" + replace(string(char( ...
    java.util.UUID.randomUUID())), "-", "");
stageCleanup = onCleanup(@() deleteOwnedFile(stagePath));
save(stagePath, "result", "summary", "-v7.3");
moveReplace(stagePath, resultPath);
clear stageCleanup
end

function bestEffortFailureRecord(runDirectory, runId, sourceHashBefore, ...
        sourceHashAfter, startedAt, exception)
if strlength(string(runDirectory)) == 0 || ~isfolder(runDirectory)
    return
end
try
    failure = struct( ...
        "schemaVersion", 1, ...
        "runId", string(runId), ...
        "runDirectory", string(runDirectory), ...
        "sourceHash", string(sourceHashAfter), ...
        "sourceHashBefore", string(sourceHashBefore), ...
        "sourceHashAfter", string(sourceHashAfter), ...
        "copyHash", existingHash(fullfile(runDirectory, ...
            "final_steady_speed55090.slx")), ...
        "startedAt", string(startedAt), ...
        "completedAt", utcTimestamp(), ...
        "status", "tool_failed", ...
        "errorId", string(exception.identifier), ...
        "errorReport", string(getReport(exception, "extended", ...
            "hyperlinks", "off")));
    failurePath = fullfile(runDirectory, "failure.mat");
    stagePath = failurePath + ".stage";
    save(stagePath, "failure");
    moveReplace(stagePath, failurePath);
    reportPath = fullfile(runDirectory, "errorReport.txt");
    fileId = fopen(reportPath + ".stage", "w");
    if fileId < 0
        return
    end
    fileCleanup = onCleanup(@() fclose(fileId));
    fprintf(fileId, "%s\n", failure.errorReport);
    clear fileCleanup
    moveReplace(reportPath + ".stage", reportPath);
catch
    % Preserve the original exception if failure-recording is unavailable.
end
end

function exceptions = cleanupLifecycle( ...
        lifecycle, copyModel, modelCleanup)
exceptions = cell(0, 1);
tryCleanup(@() closeModelNoSave(copyModel));
if ~isempty(modelCleanup)
    try
        clear modelCleanup
    catch exception
        exceptions{end + 1, 1} = exception;
    end
end
if lifecycle.baseCaptured
    tryCleanup(@() restoreBaseWorkspace(lifecycle.baseSnapshot));
end
if lifecycle.warningsCaptured
    tryCleanup(@() restoreWarnings(lifecycle.warningStates));
end
if lifecycle.fileGenerationCaptured
    tryCleanup(@() restoreFileGeneration(lifecycle.fileGenerationConfig));
end
if lifecycle.fileGenerationRootOwned
    tryCleanup(@() removeOwnedDirectory(lifecycle.fileGenerationRoot));
end
if lifecycle.pwdCaptured
    tryCleanup(@() cd(lifecycle.originalPwd));
end
if lifecycle.pathCaptured
    tryCleanup(@() path(lifecycle.originalPath));
end

    function tryCleanup(operation)
        try
            operation();
        catch exception
            exceptions{end + 1, 1} = exception;
        end
    end
end

function lifecycle = captureLifecycle(lifecycle)
lifecycle.originalPath = path;
lifecycle.pathCaptured = true;
lifecycle.originalPwd = string(pwd);
lifecycle.pwdCaptured = true;
lifecycle.warningStates = warning("query", "all");
lifecycle.warningsCaptured = true;
lifecycle.baseSnapshot = captureBaseWorkspace();
lifecycle.baseCaptured = true;
lifecycle.fileGenerationConfig = Simulink.fileGenControl("getConfig");
lifecycle.fileGenerationCaptured = true;
end

function lifecycle = emptyLifecycle()
lifecycle = struct( ...
    "pathCaptured", false, "originalPath", "", ...
    "pwdCaptured", false, "originalPwd", "", ...
    "warningsCaptured", false, "warningStates", struct([]), ...
    "baseCaptured", false, "baseSnapshot", struct(), ...
    "fileGenerationCaptured", false, ...
    "fileGenerationConfig", struct(), ...
    "fileGenerationRootOwned", false, ...
    "fileGenerationRoot", "");
end

function snapshot = captureBaseWorkspace()
names = string(evalin("base", "who"));
values = cell(size(names));
for index = 1:numel(names)
    values{index} = evalin("base", names(index));
end
snapshot = struct("names", names, "values", {values});
end

function restoreBaseWorkspace(snapshot)
current = string(evalin("base", "who"));
added = setdiff(current, snapshot.names);
for index = 1:numel(added)
    evalin("base", "clear " + added(index));
end
for index = 1:numel(snapshot.names)
    assignin("base", snapshot.names(index), snapshot.values{index});
end
end

function restoreWarnings(states)
for index = 1:numel(states)
    warning(states(index).state, states(index).identifier);
end
end

function restoreFileGeneration(config)
Simulink.fileGenControl("set", ...
    "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, ...
    "createDir", true);
end

function summary = compactSummary(result)
summary = rmfield(result, intersect(fieldnames(result), ...
    {'t', 'signals', 'states'}));
end

function value = attachEvidenceMetadata(value, runId, runDirectory, ...
        sourceHashBefore, sourceHashAfter, copyHash, startedAt, ...
        completedAt, status)
value.schemaVersion = 1;
value.runId = string(runId);
value.runDirectory = string(runDirectory);
value.sourceHash = string(sourceHashAfter);
value.sourceHashBefore = string(sourceHashBefore);
value.sourceHashAfter = string(sourceHashAfter);
value.copyHash = string(copyHash);
value.startedAt = string(startedAt);
value.completedAt = string(completedAt);
value.status = string(status);
end

function status = simulationStatus(result)
if isfield(result, "success") && isequal(result.success, true)
    status = "completed";
else
    status = "simulation_failed";
end
end

function exception = mergeOrdinaryExceptions(primary, cleanupExceptions)
if isempty(primary)
    exception = cleanupExceptions{1};
    startIndex = 2;
else
    exception = primary;
    startIndex = 1;
end
for index = startIndex:numel(cleanupExceptions)
    exception = addCause(exception, cleanupExceptions{index});
end
end

function exception = sourceRewriteException(sourcePath, before, after, ...
        primary, cleanupExceptions)
exception = MException("steady53:SourceModelWasRewritten", ...
    "Source model '%s' changed from SHA-256 %s to %s.", ...
    sourcePath, before, after);
if ~isempty(primary)
    exception = addCause(exception, primary);
end
for index = 1:numel(cleanupExceptions)
    exception = addCause(exception, cleanupExceptions{index});
end
end

function throwSourceGuarded(primary, cleanupExceptions, sourcePath, ...
        before, after)
if after ~= before
    throw(sourceRewriteException(sourcePath, before, after, primary, ...
        cleanupExceptions));
end
for index = 1:numel(cleanupExceptions)
    primary = addCause(primary, cleanupExceptions{index});
end
throw(primary)
end

function injectFailure(config, point)
if config.injectFailureAt == point
    error("steady53:InjectedSpeedHypothesisFailure", ...
        "Controlled exploration failure injected at %s.", point);
end
end

function paths = currentPaths(tmpRoot)
paths = struct( ...
    "copy", string(fullfile(tmpRoot, "final_steady_speed55090.slx")), ...
    "result", string(fullfile(tmpRoot, "speed55090_result.mat")), ...
    "marker", string(fullfile(tmpRoot, "speed55090_current.mat")));
end

function moveReplace(source, destination)
[ok, message] = movefile(source, destination, "f");
if ~ok
    error("steady53:AtomicMoveFailed", ...
        "Could not move '%s' to '%s': %s", source, destination, message);
end
end

function makeOwnedDirectory(directory)
if isfolder(directory) || isfile(directory)
    error("steady53:OwnedDirectoryCollision", ...
        "Refusing to reuse owned directory path: %s", directory);
end
[ok, message] = mkdir(directory);
if ~ok
    error("steady53:CreateDirectoryFailed", ...
        "Could not create '%s': %s", directory, message);
end
end

function removeOwnedDirectory(directory)
if strlength(string(directory)) > 0 && isfolder(directory)
    rmdir(directory, "s");
end
end

function deleteOwnedFile(filePath)
if isfile(filePath)
    delete(filePath);
end
end

function hash = existingHash(filePath)
if isfile(filePath)
    hash = sha256File(filePath);
else
    hash = "";
end
end

function closeModelNoSave(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function runId = makeRunId()
milliseconds = string(round(posixtime(datetime("now", ...
    "TimeZone", "UTC")) * 1000));
uuid = replace(string(char(java.util.UUID.randomUUID())), "-", "");
runId = "run_" + milliseconds + "_" + uuid;
end

function timestamp = utcTimestamp()
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function hash = sha256File(filePath)
if ~isfile(filePath)
    error("steady53:HashInputMissing", ...
        "Cannot hash missing file: %s", filePath);
end
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:HashFailed", ...
        "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = string(parts(1));
end

function value = getFileName(pathValue)
[~, name, extension] = fileparts(pathValue);
value = name + extension;
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
