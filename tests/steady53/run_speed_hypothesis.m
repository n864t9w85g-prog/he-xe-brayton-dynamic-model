function summary = run_speed_hypothesis()
%RUN_SPEED_HYPOTHESIS Test the 55090 rpm hypothesis on an isolated copy.
%   The production model and lookup tables are read-only inputs.  The only
%   physical-model change is TAC/Constant: 66100 -> 55090 rpm, and it is
%   saved exclusively in tmp/steady53/final_steady_speed55090.slx.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
source = fullfile(root, "final_steady_24a.slx");
tmpDir = fullfile(root, "tmp", "steady53");
copyPath = fullfile(tmpDir, "final_steady_speed55090.slx");
resultPath = fullfile(tmpDir, "speed55090_result.mat");
sourceModel = "final_steady_24a";
copyModel = "final_steady_speed55090";
expectedSourceHash = ...
    "08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a";
originalPath = path;
pathCleanup = onCleanup(@() path(originalPath));

if bdIsLoaded(sourceModel)
    error("steady53:SourceModelAlreadyLoaded", ...
        "Source model '%s' is already loaded; no files were changed.", ...
        sourceModel);
end
if bdIsLoaded(copyModel)
    error("steady53:ExplorationModelAlreadyLoaded", ...
        "Exploration model '%s' is already loaded. It may contain " + ...
        "unsaved work, so it was neither closed nor overwritten.", ...
        copyModel);
end
if ~isfile(source)
    error("steady53:MissingSourceModel", ...
        "Source model does not exist: %s", source);
end

sourceHashBefore = sha256File(source);
if sourceHashBefore ~= expectedSourceHash
    error("steady53:UnexpectedSourceHash", ...
        "Source model hash is %s, expected %s; no copy was created.", ...
        sourceHashBefore, expectedSourceHash);
end

if ~isfolder(tmpDir)
    mkdir(tmpDir);
end
copyfile(source, copyPath, "f");

% Loading and saving the copied diagram must not leak file-generation state.
fileGenerationConfig = Simulink.fileGenControl("getConfig");
fileGenerationRoot = string(tempname);
mkdir(fileGenerationRoot);
fileGenerationCleanup = onCleanup(@() restoreFileGeneration( ...
    fileGenerationConfig, fileGenerationRoot));
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(fileGenerationRoot, "cache"), ...
    "CodeGenFolder", fullfile(fileGenerationRoot, "codegen"), ...
    "createDir", true);

% Cleanup ownership is established before load_system.  The loaded-copy
% precheck above protects any user-owned diagram with unsaved changes.
modelCleanup = onCleanup(@() closeModelNoSave(copyModel));
load_system(copyPath);

changedBlockPath = copyModel + "/TAC/Constant";
oldValue = string(get_param(changedBlockPath, "Value"));
oldStopTime = string(get_param(copyModel, "StopTime"));
newValue = "55090";
newStopTime = "500";
set_param(changedBlockPath, "Value", newValue);
set_param(copyModel, "StopTime", newStopTime);
save_system(copyModel, copyPath);
close_system(copyModel, 0);

compressorMap = load(fullfile(root, "hexe_compressor_lookup.mat"), ...
    "N_design", "speed_bp");
result = run_steady53_case(copyPath, 500, true);

summary = rmfield(result, {'t', 'signals', 'states'});
summary.sourcePath = string(source);
summary.explorationCopyPath = string(copyPath);
summary.resultPath = string(resultPath);
summary.expectedSourceHash = expectedSourceHash;
summary.sourceHashBefore = sourceHashBefore;
summary.sourceHashAfter = sha256File(source);
summary.sourceUnchanged = ...
    summary.sourceHashAfter == sourceHashBefore && ...
    summary.sourceHashAfter == expectedSourceHash;
summary.explorationCopyHash = sha256File(copyPath);
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

% Preserve full trajectory evidence separately from the compact summary,
% including a failed simulation result returned by the isolated runner.
save(resultPath, "result", "summary", "-v7.3");
assert(summary.sourceUnchanged, ...
    "steady53:SourceModelWasRewritten", ...
    "The formal source model changed during the exploration experiment.");

% Run cleanup deterministically before returning the summary; the cleanup
% objects remain fallbacks for every earlier error path.
clear modelCleanup
clear fileGenerationCleanup
clear pathCleanup
assert(strcmp(path, originalPath), ...
    "steady53:PathCleanupFailed", ...
    "The exploration function did not restore the caller's MATLAB path.");
end

function closeModelNoSave(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function restoreFileGeneration(config, generatedRoot)
Simulink.fileGenControl("set", ...
    "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, ...
    "createDir", true);
if isfolder(generatedRoot)
    rmdir(generatedRoot, "s");
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:HashFailed", ...
        "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
