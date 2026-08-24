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
if ~all(isfield(stage, required)) || ~isfolder(stage.stageDir) || ...
        ~isfile(stage.manifestPath)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence stage is missing required files or metadata.");
end
if isfile(stage.targetDir) || isfolder(stage.targetDir)
    error("steady53:EvidenceAlreadyExists", ...
        "Task 8 evidence target already exists: %s", stage.targetDir);
end

manifest = jsondecode(fileread(stage.manifestPath));
if ~isfield(manifest, "status") || string(manifest.status) ~= "completed" || ...
        ~isfield(manifest, "runId") || ...
        string(manifest.runId) ~= string(stage.runId)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 evidence manifest is not a completed matching stage.");
end
verifyStageHashes(stage, manifest);

[status, output] = system("mkdir " + shellQuote(stage.targetDir));
if status ~= 0
    if isfile(stage.targetDir) || isfolder(stage.targetDir)
        error("steady53:EvidenceAlreadyExists", ...
            "Task 8 evidence target already exists: %s", stage.targetDir);
    end
    error("steady53:EvidencePublishFailed", ...
        "Could not reserve Task 8 evidence target: %s", output);
end

if isfield(testControl, "targetCollisionFile")
    collisionName = safeFileName(testControl.targetCollisionFile);
    collisionPath = fullfile(stage.targetDir, collisionName);
    fileId = fopen(collisionPath, "w");
    if fileId < 0
        error("steady53:EvidencePublishFailed", ...
            "Could not inject controlled target collision: %s", collisionPath);
    end
    fclose(fileId);
end

linkedCount = 0;
for index = 1:numel(stage.payloadFiles)
    name = safeFileName(stage.payloadFiles(index));
    source = fullfile(stage.stageDir, name);
    destination = fullfile(stage.targetDir, name);
    publishFileExclusive(source, destination);
    linkedCount = linkedCount + 1;
    if isfield(testControl, "interruptAfterFiles") && ...
            linkedCount >= testControl.interruptAfterFiles
        error("steady53:EvidencePublishInterrupted", ...
            "Controlled Task 8 evidence publication interruption.");
    end
end

% Completion is visible only after every payload has been published.
publishFileExclusive(stage.manifestPath, ...
    fullfile(stage.targetDir, "manifest.json"));

published = struct( ...
    "runId", string(stage.runId), ...
    "runDir", string(stage.targetDir), ...
    "rawMatPath", string(fullfile( ...
        stage.targetDir, string(manifest.rawMatFile))), ...
    "manifestPath", string(fullfile(stage.targetDir, "manifest.json")), ...
    "rawMatHash", string(manifest.rawMatHash));
rmdir(stage.stageDir, "s");
end

function verifyStageHashes(stage, manifest)
if ~isfield(manifest, "rawMatHash") || ...
        sha256File(stage.rawMatPath) ~= string(manifest.rawMatHash)
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 raw MAT hash does not match its manifest.");
end
if ~isfield(manifest, "smallFileHashes")
    error("steady53:InvalidEvidenceStage", ...
        "Task 8 manifest lacks small-file hashes.");
end
items = manifest.smallFileHashes;
for index = 1:numel(items)
    name = safeFileName(items(index).name);
    filePath = fullfile(stage.stageDir, name);
    if ~isfile(filePath) || sha256File(filePath) ~= string(items(index).sha256)
        error("steady53:InvalidEvidenceStage", ...
            "Task 8 small-file hash mismatch: %s", name);
    end
end
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
