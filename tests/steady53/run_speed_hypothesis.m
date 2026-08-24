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

if config.validateCurrentOnly
    sourceHashBefore = sha256File(config.sourcePath);
    if sourceHashBefore ~= config.expectedSourceHash
        mismatch = MException("steady53:UnexpectedSourceHash", ...
            "Source model hash is %s, expected %s; no artifact was changed.", ...
            sourceHashBefore, config.expectedSourceHash);
        sourceHashAfter = sha256File(config.sourcePath);
        throwSourceGuarded(mismatch, {}, config.sourcePath, ...
            sourceHashBefore, sourceHashAfter);
    end
    try
        output = validateCurrentEvidence(config.tmpRoot, ...
            config.expectedSourceHash, "");
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
    sourceHashAfter = sha256File(config.sourcePath);
    if sourceHashAfter ~= sourceHashBefore
        throw(sourceRewriteException(config.sourcePath, sourceHashBefore, ...
            sourceHashAfter, [], {}));
    end
    return
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

% The marker is the sole current-evidence authority. Markerless compatibility
% files are never adopted, regardless of their self-reported metadata.
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
        publishCurrentEvidence(config, runId, runDirectory, ...
            copyPath, resultPath, sourceHashAfter, ...
            summary.explorationCopyHash, resultHash, summary.status, ...
            summary.completedAt);
        summary.current = validateCurrentEvidence( ...
            config.tmpRoot, sourceHashAfter, "");
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
allowedFailures = ["", "after_copy", "after_save", "before_runner", ...
    "before_marker_move", "after_marker_move_before_cache", ...
    "after_current_copy_move", "after_current_result_move"];
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
    validateCurrentEvidence(config.tmpRoot, sourceHash, "");
    return
end
if ~hasCopy && ~hasResult
    return
end
error("steady53:UnownedExplorationArtifact", ...
    "Compatibility artifacts exist without an authoritative marker; " + ...
    "they will not be adopted or overwritten.");
end

function current = publishCurrentEvidence(config, runId, runDirectory, ...
        runCopy, runResult, sourceHash, copyHash, resultHash, status, ...
        completedAt)
tmpRoot = config.tmpRoot;
paths = currentPaths(tmpRoot);
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
current = struct( ...
    "schemaVersion", 2, ...
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
% Validate the immutable candidate before the single authoritative switch.
validateMarkerAndImmutable(current, tmpRoot, sourceHash);
stageMarker = string(tempname(tmpRoot)) + ".mat";
stageCleanup = onCleanup(@() deleteOwnedFile(stageMarker));
save(stageMarker, "current");
injectFailure(config, "before_marker_move");
% This one move is the only current-authority transition.
moveReplace(stageMarker, paths.marker);
injectFailure(config, "after_marker_move_before_cache");
ensureCurrentCaches(current, tmpRoot, config.injectFailureAt);
clear stageCleanup
end

function current = validateCurrentEvidence(tmpRoot, expectedSourceHash, ...
        injectFailureAt)
paths = currentPaths(tmpRoot);
if ~isfile(paths.marker)
    error("steady53:CurrentEvidenceIncomplete", ...
        "The authoritative current marker is missing.");
end
loaded = load(paths.marker, "current");
if ~isfield(loaded, "current")
    error("steady53:CurrentEvidenceInvalid", ...
        "Current marker lacks the current pointer.");
end
current = loaded.current;
validateMarkerAndImmutable(current, tmpRoot, expectedSourceHash);
current.cacheRebuilt = ensureCurrentCaches( ...
    current, tmpRoot, string(injectFailureAt));
end

function validateMarkerAndImmutable(current, tmpRoot, expectedSourceHash)
required = {'schemaVersion', 'runId', 'runDirectory', 'sourceHash', ...
    'copyHash', 'resultHash', 'status', 'completedAt', 'copyPath', ...
    'resultPath', 'runCopyPath', 'runResultPath'};
if ~isstruct(current) || ~isscalar(current) || ...
        ~all(isfield(current, required)) || ...
        ~isequal(current.schemaVersion, 2)
    error("steady53:MarkerMismatch", ...
        "Current marker does not have the complete schema-v2 contract.");
end
paths = currentPaths(tmpRoot);
runsRoot = string(fullfile(tmpRoot, "runs"));
runId = string(current.runId);
runDirectory = string(current.runDirectory);
runCopy = string(current.runCopyPath);
runResult = string(current.runResultPath);
[runParent, runBase] = fileparts(runDirectory);
[copyParent, copyName, copyExtension] = fileparts(runCopy);
[resultParent, resultName, resultExtension] = fileparts(runResult);
validPaths = string(runParent) == runsRoot && ...
    string(runBase) == runId && ...
    string(copyParent) == runDirectory && ...
    string(resultParent) == runDirectory && ...
    string(copyName) + string(copyExtension) == ...
        "final_steady_speed55090.slx" && ...
    string(resultName) + string(resultExtension) == ...
        "speed55090_result.mat" && ...
    runCopy == fullfile(runDirectory, ...
        "final_steady_speed55090.slx") && ...
    runResult == fullfile(runDirectory, "speed55090_result.mat") && ...
    string(current.copyPath) == paths.copy && ...
    string(current.resultPath) == paths.result;
if ~validPaths || string(current.sourceHash) ~= string(expectedSourceHash)
    error("steady53:MarkerMismatch", ...
        "Current marker source or path fields violate the authority boundary.");
end
if ~isfile(runCopy) || ~isfile(runResult)
    error("steady53:CurrentEvidenceIncomplete", ...
        "Marker-referenced immutable run evidence is missing.");
end
if sha256File(runCopy) ~= string(current.copyHash) || ...
        sha256File(runResult) ~= string(current.resultHash)
    error("steady53:CurrentEvidenceHashMismatch", ...
        "Marker-referenced immutable evidence does not match its hashes.");
end
immutable = load(runResult, "result", "summary");
if ~isfield(immutable, "result") || ~isfield(immutable, "summary")
    error("steady53:CurrentEvidenceInvalid", ...
        "Immutable result lacks result and summary evidence.");
end
metadata = {'schemaVersion', 'runId', 'runDirectory', 'sourceHash', ...
    'copyHash', 'status', 'completedAt'};
for index = 1:numel(metadata)
    field = metadata{index};
    if ~isfield(immutable.result, field) || ...
            ~isfield(immutable.summary, field) || ...
            ~isequal(string(immutable.result.(field)), ...
                string(current.(field))) || ...
            ~isequal(string(immutable.summary.(field)), ...
                string(current.(field)))
        error("steady53:MarkerMismatch", ...
            "Marker field '%s' disagrees with immutable evidence.", field);
    end
end
if ~isfield(immutable.summary, "explorationCopyPath") || ...
        ~isfield(immutable.summary, "resultPath") || ...
        string(immutable.summary.explorationCopyPath) ~= runCopy || ...
        string(immutable.summary.resultPath) ~= runResult
    error("steady53:MarkerMismatch", ...
        "Immutable summary paths disagree with the marker.");
end
end

function cacheRebuilt = ensureCurrentCaches(current, tmpRoot, ...
        injectFailureAt)
paths = currentPaths(tmpRoot);
cacheRebuilt = false;
if ~isfile(paths.copy) || ...
        sha256File(paths.copy) ~= string(current.copyHash)
    replaceCache(current.runCopyPath, paths.copy, current.copyHash);
    cacheRebuilt = true;
    injectFailureValue(injectFailureAt, "after_current_copy_move");
end
if ~isfile(paths.result) || ...
        sha256File(paths.result) ~= string(current.resultHash)
    replaceCache(current.runResultPath, paths.result, current.resultHash);
    cacheRebuilt = true;
    injectFailureValue(injectFailureAt, "after_current_result_move");
end
if sha256File(paths.copy) ~= string(current.copyHash) || ...
        sha256File(paths.result) ~= string(current.resultHash)
    error("steady53:CurrentCacheRebuildFailed", ...
        "Compatibility caches do not match authoritative immutable evidence.");
end
end

function replaceCache(source, destination, expectedHash)
stage = string(tempname(fileparts(destination)));
stageCleanup = onCleanup(@() deleteOwnedFile(stage));
copyfile(source, stage);
if sha256File(stage) ~= string(expectedHash)
    error("steady53:PublishStagingHashMismatch", ...
        "A staged compatibility cache failed its hash audit.");
end
moveReplace(stage, destination);
clear stageCleanup
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
        "schemaVersion", 2, ...
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
value.schemaVersion = 2;
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
injectFailureValue(config.injectFailureAt, point);
end

function injectFailureValue(injectFailureAt, point)
if string(injectFailureAt) == string(point)
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
