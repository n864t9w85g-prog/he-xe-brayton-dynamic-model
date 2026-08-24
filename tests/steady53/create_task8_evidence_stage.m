function stage = create_task8_evidence_stage( ...
        evidenceRoot, runId, result, report, spec)
%CREATE_TASK8_EVIDENCE_STAGE Write one complete Task 8 evidence staging set.
%   The staging directory is retained on failure. A completed manifest is
%   written only after the raw MAT and every small evidence file exist and
%   have been hashed. Publication is a separate exclusive operation.

arguments
    evidenceRoot {mustBeTextScalar}
    runId {mustBeTextScalar}
    result (1, 1) struct
    report (1, 1) struct
    spec (1, 1) struct
end

evidenceRoot = string(evidenceRoot);
runId = string(runId);
if isempty(regexp(runId, '^run_[A-Za-z0-9_]+$', 'once'))
    error("steady53:InvalidEvidenceRunId", ...
        "Task 8 evidence runId is not a safe run identifier: %s", runId);
end
if ~isfolder(evidenceRoot)
    mkdir(evidenceRoot);
end

targetDir = string(fullfile(evidenceRoot, runId));
stageDir = string(fullfile(evidenceRoot, ".staging_" + runId));
if isfile(targetDir) || isfolder(targetDir) || ...
        isfile(stageDir) || isfolder(stageDir)
    error("steady53:EvidenceAlreadyExists", ...
        "Task 8 evidence run or staging path already exists: %s", runId);
end
mkdir(stageDir);

rawMatFile = "nominal_500_report.mat";
smallFiles = [ ...
    "metrics.csv"
    "lookup_audit.csv"
    "state_window_audit.csv"
    "signal_window_audit.csv"
    "failures.txt"
    "summary.txt"];
rawMatPath = string(fullfile(stageDir, rawMatFile));
save(rawMatPath, "result", "report", "spec", "-v7.3");
writetable(report.metrics, fullfile(stageDir, smallFiles(1)));
writetable(struct2table(report.audit.lookup), ...
    fullfile(stageDir, smallFiles(2)));
writetable(stateWindowTable(result, spec), ...
    fullfile(stageDir, smallFiles(3)));
writetable(report.signalDynamics, fullfile(stageDir, smallFiles(4)));
writelines(report.failures, fullfile(stageDir, smallFiles(5)));
writeSummary(fullfile(stageDir, smallFiles(6)), result, report, spec);

smallFileHashes = repmat(struct("name", "", "sha256", ""), ...
    numel(smallFiles), 1);
for index = 1:numel(smallFiles)
    smallFileHashes(index).name = smallFiles(index);
    smallFileHashes(index).sha256 = sha256File( ...
        fullfile(stageDir, smallFiles(index)));
end

manifest = struct( ...
    "schemaVersion", 1, ...
    "runId", runId, ...
    "sourceModelHash", sourceModelHash(result), ...
    "rawMatFile", rawMatFile, ...
    "rawMatHash", sha256File(rawMatPath), ...
    "smallFileHashes", smallFileHashes, ...
    "status", "completed", ...
    "createdAt", utcTimestamp());
manifestPath = string(fullfile(stageDir, "manifest.json"));
writeTextFile(manifestPath, jsonencode(manifest));

stage = struct( ...
    "runId", runId, ...
    "evidenceRoot", evidenceRoot, ...
    "stageDir", stageDir, ...
    "targetDir", targetDir, ...
    "rawMatPath", rawMatPath, ...
    "manifestPath", manifestPath, ...
    "payloadFiles", [rawMatFile; smallFiles]);
end

function hash = sourceModelHash(result)
required = ["modelHashBefore", "modelHashAfter"];
if ~all(isfield(result, required)) || ...
        ~validHash(result.modelHashBefore) || ...
        ~validHash(result.modelHashAfter) || ...
        string(result.modelHashBefore) ~= string(result.modelHashAfter)
    error("steady53:InvalidEvidenceSourceHash", ...
        "Task 8 evidence requires equal before/after SHA-256 model hashes.");
end
hash = lower(string(result.modelHashAfter));
end

function valid = validHash(value)
valid = (isstring(value) || ischar(value)) && isscalar(string(value)) && ...
    ~isempty(regexp(string(value), '^[0-9A-Fa-f]{64}$', 'once'));
end

function writeSummary(filePath, result, report, spec)
summary = [ ...
    "success=" + string(result.success)
    "tFinal_s=" + compose("%.17g", result.tFinal_s)
    "errorId=" + string(result.errorId)
    "warningIds=" + strjoin(string(result.warningIds), ",")
    "HeXeMin_K=" + compose("%.17g", report.audit.property.HeXeMin_K)
    "HeXeMax_K=" + compose("%.17g", report.audit.property.HeXeMax_K)
    "LithiumMin_K=" + compose("%.17g", report.audit.property.LithiumMin_K)
    "LithiumMax_K=" + compose("%.17g", report.audit.property.LithiumMax_K)
    "massClosureRel=" + compose("%.17g", report.audit.massClosureRel)
    "massClosureTol=" + compose("%.17g", spec.massClosureTol)
    ];
writelines(summary, filePath);
end

function output = stateWindowTable(result, spec)
count = numel(result.states);
path = strings(count, 1);
fluid = strings(count, 1);
kind = strings(count, 1);
signPolicy = strings(count, 1);
finalValue = nan(count, 1);
windowMean = nan(count, 1);
windowMin = nan(count, 1);
windowMax = nan(count, 1);
windowPeakToPeakRel = nan(count, 1);
windowTrendRel = nan(count, 1);
mask = result.t >= spec.finalWindow_s(1) & ...
    result.t <= spec.finalWindow_s(2);
for index = 1:count
    state = result.states(index);
    values = state.data(:);
    windowValues = values(mask);
    windowTime = result.t(mask);
    scale = max(abs(mean(windowValues)), ...
        stateScaleFloor(state.kind, spec));
    fit = polyfit(windowTime, windowValues, 1);
    path(index) = state.path;
    fluid(index) = state.fluid;
    kind(index) = state.kind;
    signPolicy(index) = state.signPolicy;
    finalValue(index) = values(end);
    windowMean(index) = mean(windowValues);
    windowMin(index) = min(windowValues);
    windowMax(index) = max(windowValues);
    windowPeakToPeakRel(index) = ...
        (windowMax(index) - windowMin(index)) / scale;
    windowTrendRel(index) = abs(fit(1)) * ...
        diff(spec.finalWindow_s) / scale;
end
output = table(path, fluid, kind, signPolicy, finalValue, windowMean, ...
    windowMin, windowMax, windowPeakToPeakRel, windowTrendRel);
end

function scale = stateScaleFloor(kind, spec)
switch string(kind)
    case "temperature"
        scale = spec.scale.temperature_K;
    case "pressure"
        scale = spec.scale.pressure_Pa;
    case "power"
        scale = spec.scale.power_W;
    case "massFlow"
        scale = spec.scale.massFlow_kg_s;
    case "speed"
        scale = spec.scale.speed_rpm;
    case "dimensionless"
        scale = spec.scale.dimensionless;
    otherwise
        scale = spec.scale.other;
end
end

function writeTextFile(filePath, content)
fileId = fopen(filePath, "w");
if fileId < 0
    error("steady53:EvidenceStageWriteFailed", ...
        "Could not create Task 8 evidence file: %s", filePath);
end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", content);
clear cleanup
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:EvidenceStageHashFailed", ...
        "Could not hash Task 8 evidence file %s: %s", filePath, output);
end
parts = split(strtrim(string(output)));
hash = parts(1);
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end

function timestamp = utcTimestamp()
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
