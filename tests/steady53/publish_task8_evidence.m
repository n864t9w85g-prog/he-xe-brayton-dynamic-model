function published = publish_task8_evidence(stage, testControl)
%PUBLISH_TASK8_EVIDENCE Exclusively publish a completed Task 8 stage.
%   The target manifest is linked last. A collision or injected interruption
%   therefore cannot produce a target directory that claims completion.

arguments
    stage (1, 1) struct
    testControl (1, 1) struct = struct()
end

required = ["runId", "stageDir", "targetDir", "rawMatPath", ...
    "manifestPath", "payloadFiles"];
if ~all(isfield(stage, required)) || ~isfolder(stage.stageDir)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence stage is missing required files or metadata.");
end

[rawMatFile, smallFiles] = evidenceFileContract();
requiredPayloadFiles = [rawMatFile; smallFiles];
verifyExactFileSet(stage.payloadFiles, requiredPayloadFiles, ...
    "Task 8 stage payload claim does not match the fixed contract.");

manifestPath = string(fullfile(stage.stageDir, "manifest.json"));
if ~isscalar(string(stage.manifestPath)) || ...
        ismissing(string(stage.manifestPath)) || ...
        string(stage.manifestPath) ~= manifestPath || ~isfile(manifestPath)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 stage manifest path does not match its fixed staged path.");
end
manifest = jsondecode(fileread(manifestPath));
targetDir = verifiedManifestEnvelope(stage, manifest);
[payloadFiles, payloadHashes] = verifiedStagePayloads( ...
    stage, manifest, rawMatFile, smallFiles);
validatedManifestHash = sha256File(manifestPath);

if isfile(targetDir) || isfolder(targetDir)
    error("steady53:EvidenceAlreadyExists", ...
        "Task 8 evidence target already exists: %s", targetDir);
end

[status, output] = system("mkdir " + shellQuote(targetDir));
if status ~= 0
    if isfile(targetDir) || isfolder(targetDir)
        error("steady53:EvidenceAlreadyExists", ...
            "Task 8 evidence target already exists: %s", targetDir);
    end
    error("steady53:EvidencePublishFailed", ...
        "Could not reserve Task 8 evidence target: %s", output);
end

if isfield(testControl, "targetCollisionFile")
    collisionName = safeFileName(testControl.targetCollisionFile);
    collisionPath = fullfile(targetDir, collisionName);
    fileId = fopen(collisionPath, "w");
    if fileId < 0
        error("steady53:EvidencePublishFailed", ...
            "Could not inject controlled target collision: %s", collisionPath);
    end
    fclose(fileId);
end

linkedCount = 0;
for index = 1:numel(payloadFiles)
    name = payloadFiles(index);
    source = fullfile(stage.stageDir, name);
    destination = fullfile(targetDir, name);
    publishFileExclusive(source, destination);
    linkedCount = linkedCount + 1;
    if isfield(testControl, "interruptAfterFiles") && ...
            linkedCount >= testControl.interruptAfterFiles
        error("steady53:EvidencePublishInterrupted", ...
            "Controlled Task 8 evidence publication interruption.");
    end
end

if isfield(testControl, "tamperTargetBeforeManifest")
    tamperName = safeFileName(testControl.tamperTargetBeforeManifest);
    if ~any(payloadFiles == tamperName)
        error("steady53:InvalidEvidenceStage", ...
            "Controlled target tamper must name a required payload.");
    end
    tamperFile(fullfile(targetDir, tamperName));
end

% Completion is visible only after every payload has been published.
verifyPublishedPayloads(targetDir, payloadFiles, payloadHashes);
if sha256File(manifestPath) ~= validatedManifestHash
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 manifest changed after validation.");
end
publishFileExclusive(manifestPath, fullfile(targetDir, "manifest.json"));

published = struct( ...
    "runId", string(manifest.runId), ...
    "runDir", targetDir, ...
    "rawMatPath", string(fullfile(targetDir, rawMatFile)), ...
    "manifestPath", string(fullfile(targetDir, "manifest.json")), ...
    "rawMatHash", string(manifest.rawMatHash));
rmdir(stage.stageDir, "s");
end

function targetDir = verifiedManifestEnvelope(stage, manifest)
if ~isfield(manifest, "schemaVersion") || ...
        ~isnumeric(manifest.schemaVersion) || ...
        ~isscalar(manifest.schemaVersion) || manifest.schemaVersion ~= 1
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest requires schemaVersion 1.");
end
if ~isfield(manifest, "status") || ...
        ~isscalar(string(manifest.status)) || ...
        ismissing(string(manifest.status)) || ...
        string(manifest.status) ~= "completed"
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest is not completed.");
end
if ~isfield(manifest, "runId")
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest lacks a run ID.");
end
runId = safeRunId(manifest.runId);
if ~isscalar(string(stage.runId)) || ismissing(string(stage.runId)) || ...
        string(stage.runId) ~= runId
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 stage and manifest run IDs do not match.");
end
stageDir = string(stage.stageDir);
stageDirName = string(java.io.File(char(stageDir)).getName());
if stageDirName ~= ".staging_" + runId
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 staging directory does not match the manifest run ID.");
end
targetDir = string(fullfile(fileparts(stageDir), runId));
if ~isscalar(string(stage.targetDir)) || ...
        ismissing(string(stage.targetDir)) || ...
        string(stage.targetDir) ~= targetDir
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 target directory does not match the manifest run ID.");
end
if ~isfield(manifest, "sourceModelHash") || ...
        ~validHash(manifest.sourceModelHash)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest lacks a valid source model hash.");
end
if ~isfield(manifest, "createdAt") || ~validUtcTimestamp(manifest.createdAt)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest lacks a valid UTC creation timestamp.");
end
end

function [rawMatFile, smallFiles] = evidenceFileContract()
rawMatFile = "nominal_500_report.mat";
smallFiles = [ ...
    "metrics.csv"
    "lookup_audit.csv"
    "state_window_audit.csv"
    "signal_window_audit.csv"
    "failures.txt"
    "summary.txt"];
end

function [payloadFiles, payloadHashes] = verifiedStagePayloads( ...
        stage, manifest, rawMatFile, smallFiles)
if ~isfield(manifest, "rawMatFile") || ...
        ~isscalar(string(manifest.rawMatFile)) || ...
        ismissing(string(manifest.rawMatFile)) || ...
        string(manifest.rawMatFile) ~= rawMatFile
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 manifest raw MAT name does not match the fixed contract.");
end
expectedRawPath = string(fullfile(stage.stageDir, rawMatFile));
if ~isscalar(string(stage.rawMatPath)) || ...
        ismissing(string(stage.rawMatPath)) || ...
        string(stage.rawMatPath) ~= expectedRawPath
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 stage raw MAT path does not match its fixed staged path.");
end
if ~isfield(manifest, "rawMatHash") || ...
        ~validHash(manifest.rawMatHash) || ...
        ~isfile(expectedRawPath) || ...
        sha256File(expectedRawPath) ~= lower(string(manifest.rawMatHash))
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 raw MAT hash does not match its manifest.");
end
verifyRawModelIdentity(expectedRawPath, manifest.sourceModelHash);
if ~isfield(manifest, "smallFileHashes") || ...
        ~isstruct(manifest.smallFileHashes) || ...
        ~all(isfield(manifest.smallFileHashes, ["name", "sha256"]))
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 manifest lacks valid small-file hash records.");
end
items = manifest.smallFileHashes;
itemNames = strings(numel(items), 1);
itemHashes = strings(numel(items), 1);
for index = 1:numel(items)
    itemNames(index) = safeFileName(items(index).name);
    if ~validHash(items(index).sha256)
        error("steady53:InvalidEvidenceStage", ...
            "Task 8 manifest contains an invalid small-file hash.");
    end
    itemHashes(index) = lower(string(items(index).sha256));
end
verifyExactFileSet(itemNames, smallFiles, ...
    "Task 8 manifest small-file set does not match the fixed contract.");

payloadFiles = [rawMatFile; smallFiles];
payloadHashes = strings(numel(payloadFiles), 1);
payloadHashes(1) = lower(string(manifest.rawMatHash));
for index = 1:numel(smallFiles)
    itemIndex = find(itemNames == smallFiles(index), 1);
    payloadHashes(index + 1) = itemHashes(itemIndex);
end
for index = 1:numel(payloadFiles)
    filePath = fullfile(stage.stageDir, payloadFiles(index));
    if ~isfile(filePath) || sha256File(filePath) ~= payloadHashes(index)
        error("steady53:InvalidEvidenceStage", ...
            "Task 8 staged payload hash mismatch: %s", payloadFiles(index));
    end
end
end

function verifyRawModelIdentity(rawMatPath, sourceModelHash)
try
    contents = load(rawMatPath, "result");
catch exception
    error("steady53:InvalidEvidenceStage", ...
        "Could not read Task 8 raw MAT result: %s", exception.message);
end
if ~isfield(contents, "result") || ~isstruct(contents.result) || ...
        ~isscalar(contents.result) || ...
        ~all(isfield(contents.result, ["modelHashBefore", "modelHashAfter"]))
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 raw MAT lacks result model hashes.");
end
beforeHash = contents.result.modelHashBefore;
afterHash = contents.result.modelHashAfter;
if ~validHash(beforeHash) || ~validHash(afterHash) || ...
        lower(string(beforeHash)) ~= lower(string(afterHash)) || ...
        lower(string(beforeHash)) ~= lower(string(sourceModelHash))
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 raw MAT model hashes do not match the manifest source hash.");
end
end

function verifyExactFileSet(actualValues, expectedValues, message)
actual = string(actualValues(:));
expected = string(expectedValues(:));
if numel(actual) ~= numel(expected)
    error("steady53:InvalidEvidenceStage", "%s", message);
end
for index = 1:numel(actual)
    actual(index) = safeFileName(actual(index));
end
if numel(unique(actual)) ~= numel(actual) || ...
        ~isequal(sort(actual), sort(expected))
    error("steady53:InvalidEvidenceStage", "%s", message);
end
end

function verifyPublishedPayloads(targetDir, payloadFiles, payloadHashes)
listing = dir(targetDir);
actualNames = string({listing(~[listing.isdir]).name}).';
verifyExactFileSet(actualNames, payloadFiles, ...
    "Task 8 target payload set is incomplete or contains unknown files.");
for index = 1:numel(payloadFiles)
    filePath = fullfile(targetDir, payloadFiles(index));
    if ~isfile(filePath) || sha256File(filePath) ~= payloadHashes(index)
        error("steady53:InvalidEvidenceStage", ...
            "Task 8 target payload hash mismatch: %s", payloadFiles(index));
    end
end
end

function tamperFile(filePath)
fileId = fopen(filePath, "w");
if fileId < 0
    error("steady53:EvidencePublishFailed", ...
        "Could not inject controlled target tamper: %s", filePath);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "controlled tamper\n");
clear cleanup
end

function publishFileExclusive(source, destination)
if ~isfile(source)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 staged evidence file is missing: %s", source);
end
if isfile(destination) || isfolder(destination)
    error("steady53:EvidenceAlreadyExists", ...
        "Task 8 evidence target file already exists: %s", destination);
end
[status, output] = system("ln " + shellQuote(source) + " " + ...
    shellQuote(destination));
if status ~= 0
    if isfile(destination) || isfolder(destination)
        error("steady53:EvidenceAlreadyExists", ...
            "Task 8 evidence target file already exists: %s", destination);
    end
    error("steady53:EvidencePublishFailed", ...
        "Could not exclusively publish Task 8 evidence: %s", output);
end
end

function name = safeFileName(value)
name = string(value);
if ~isscalar(name) || ismissing(name) || strlength(name) == 0 || ...
        name ~= string(java.io.File(char(name)).getName())
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence contains an unsafe file name.");
end
end

function runId = safeRunId(value)
runId = string(value);
if ~isscalar(runId) || ismissing(runId) || ...
        isempty(regexp(runId, '^run_[A-Za-z0-9_]+$', 'once'))
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest contains an invalid run ID.");
end
end

function valid = validUtcTimestamp(value)
timestamp = string(value);
valid = false;
if ~isscalar(timestamp) || ismissing(timestamp) || strlength(timestamp) == 0 || ...
        isempty(regexp(timestamp, ...
        '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$', 'once'))
    return
end
try
    parsed = datetime(timestamp, ...
        "InputFormat", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", ...
        "TimeZone", "UTC");
    valid = ~isnat(parsed);
catch
    valid = false;
end
end

function valid = validHash(value)
valid = (isstring(value) || ischar(value)) && isscalar(string(value)) && ...
    ~ismissing(string(value)) && ...
    ~isempty(regexp(string(value), '^[0-9A-Fa-f]{64}$', 'once'));
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:InvalidEvidenceStage", ...
        "Could not hash Task 8 evidence file %s: %s", filePath, output);
end
parts = split(strtrim(string(output)));
hash = parts(1);
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
