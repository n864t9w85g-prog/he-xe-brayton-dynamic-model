function status = steady53_speed_hypothesis_lifecycle()
%STEADY53_SPEED_HYPOTHESIS_LIFECYCLE Classify Task 5 after baseline promotion.
%   This is a read-only current-baseline check. The original Task 5 runner
%   remains archived with its old source-hash contract and must not be
%   silently retargeted to the promoted model.

root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
model = "final_steady_24a";
modelPath = fullfile(root, model + ".slx");
if bdIsLoaded(model)
    error("steady53:LifecycleModelAlreadyLoaded", ...
        "Current-baseline lifecycle check requires '%s' to be unloaded.", ...
        model);
end

hashBefore = sha256File(modelPath);
cleanup = onCleanup(@() closeIfLoaded(model));
load_system(modelPath);
actualSpeed = str2double(get_param(model + "/TAC/Constant", "Value"));
map = load(fullfile(root, "hexe_compressor_lookup.mat"), ...
    "N_design", "speed_bp");
normalizedSpeed = actualSpeed / map.N_design;
inRange = isfinite(normalizedSpeed) && ...
    normalizedSpeed >= min(map.speed_bp(:)) && ...
    normalizedSpeed <= max(map.speed_bp(:));
clear cleanup

hashAfter = sha256File(modelPath);
if hashAfter ~= hashBefore
    error("steady53:LifecycleCheckRewroteModel", ...
        "Lifecycle check rewrote the formal model '%s'.", modelPath);
end

alreadyApplied = isfinite(actualSpeed) && abs(actualSpeed - 55090) <= 1 && ...
    abs(map.N_design - 55090) <= 1 && inRange;
if alreadyApplied
    lifecycle = "historical_not_applicable";
    message = "The historical Task 5 hypothesis has already been applied " + ...
        "to the promoted 55090 rpm formal baseline; its old-hash runner " + ...
        "is historical and not applicable to current acceptance.";
elseif isfinite(actualSpeed) && abs(actualSpeed - 66100) <= 1
    lifecycle = "unpromoted_baseline_detected";
    message = "The formal model still has the pre-promotion 66100 rpm " + ...
        "boundary; current-baseline acceptance cannot proceed.";
else
    lifecycle = "inconsistent_current_baseline";
    message = "The formal TAC speed is neither the promoted 55090 rpm " + ...
        "baseline nor the documented pre-promotion 66100 rpm value.";
end

archiveRoot = fullfile(root, "docs", "archive", "steady53", "task5");
status = struct( ...
    "lifecycle", lifecycle, ...
    "message", message, ...
    "hypothesisAlreadyApplied", alreadyApplied, ...
    "legacyRunnerApplicable", false, ...
    "historicalRunnerPath", fullfile(archiveRoot, ...
        "run_speed_hypothesis.m"), ...
    "actualComponentSpeed_rpm", actualSpeed, ...
    "compressorDesignSpeed_rpm", map.N_design, ...
    "compressorSpeedBreakpointMin", min(map.speed_bp(:)), ...
    "compressorSpeedBreakpointMax", max(map.speed_bp(:)), ...
    "normalizedCompressorSpeed", normalizedSpeed, ...
    "compressorSpeedInRange", inRange, ...
    "modelHashBefore", hashBefore, ...
    "modelHashAfter", hashAfter);
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function hash = sha256File(filePath)
[commandStatus, output] = system("shasum -a 256 " + shellQuote(filePath));
if commandStatus ~= 0
    error("steady53:HashFailed", ...
        "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
