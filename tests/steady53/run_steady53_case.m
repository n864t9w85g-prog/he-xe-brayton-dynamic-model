function result = run_steady53_case(modelPath, stopTime_s, logSignals)
%RUN_STEADY53_CASE Run a blocking, in-memory diagnostic simulation.
%   This exploration runner never saves the model. It redirects generated
%   files out of the repository, promotes only the approved property-domain
%   warnings to errors, and verifies the source model hash after cleanup.

arguments
    modelPath {mustBeTextScalar}
    stopTime_s (1, 1) double {mustBePositive, mustBeFinite}
    logSignals (1, 1) logical = true
end

modelPath = string(modelPath);
if ~startsWith(modelPath, filesep) || ~isfile(modelPath)
    error("steady53:ModelPathMustBeAbsolute", ...
        "modelPath must name an existing absolute .slx file.");
end
[modelDir, model, extension] = fileparts(modelPath);
if extension ~= ".slx"
    error("steady53:UnsupportedModelFile", ...
        "Expected an .slx model, got '%s'.", extension);
end

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
before = sha256File(modelPath);
result = emptyResult(before);

oldPath = path;
addpath(modelDir);
cleanupPath = onCleanup(@() path(oldPath));

fileGenRoot = string(tempname);
mkdir(fileGenRoot);
fileGenConfig = Simulink.fileGenControl("getConfig");
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(fileGenRoot, "codegen"), ...
    "createDir", true);
cleanupFileGen = onCleanup(@() restoreFileGeneration( ...
    fileGenConfig, fileGenRoot));

% start.m is a script. Evaluating it in base is required because Simulink
% resolves the table variables from the base workspace during compilation.
evalin("base", "run(" + matlabString(fullfile(root, "start.m")) + ")");

load_system(modelPath);
cleanupModel = onCleanup(@() closeLoadedModel(model));

warningIds = ["HeXe:T_lo", "HeXe:T_hi", ...
    "Lithium_property_simulink:TemperatureBelowRange", ...
    "Lithium_property_simulink:TemperatureAboveRange"];
oldWarnings = cell(size(warningIds));
for index = 1:numel(warningIds)
    oldWarnings{index} = warning("query", warningIds(index));
    warning("error", warningIds(index));
end
cleanupWarnings = onCleanup(@() restoreWarnings(oldWarnings));

[manifest, stateMeta] = steady53_signal_manifest(model);
stateLogNames = compose("steady53_state_%03d", (1:numel(stateMeta)).');

if logSignals
    enableManifestLogging(manifest);
    enableStateLogging(stateMeta, stateLogNames);
end

simulationInput = Simulink.SimulationInput(model);
if logSignals
    signalLogging = "on";
else
    signalLogging = "off";
end
simulationInput = simulationInput.setModelParameter( ...
    "StopTime", num2str(stopTime_s, "%.17g"), ...
    "ReturnWorkspaceOutputs", "on", ...
    "SignalLogging", signalLogging, ...
    "SignalLoggingName", "logsout");

try
    output = sim(simulationInput);
    result.t = output.tout(:);
    if isempty(result.t)
        error("steady53:MissingSimulationTime", ...
            "Simulation returned an empty time vector.");
    end
    result.tFinal_s = result.t(end);
    if logSignals
        result.signals = collectManifestSignals( ...
            output.logsout, manifest, result.t);
        result.signals.reactor_power = workspaceSeries( ...
            output, "P_sw", result.t);

        % This is a read-only arithmetic diagnostic. eta is derived from
        % thesis Table 5.2 values (therefore evidence grade ❓), not a model
        % parameter and not written back into final_steady_24a.slx.
        etaGenerator = 1000.21e3 / (2252.2e3 - 1231.6e3);
        result.signals.tac_electric_power = etaGenerator .* ...
            (result.signals.turbine_power - ...
             result.signals.compressor_power);
        result.states = collectStates( ...
            output.logsout, stateMeta, stateLogNames, result.t);
    end
    result.success = true;
catch exception
    result.errorId = string(exception.identifier);
    result.errorReport = string(getReport( ...
        exception, "extended", "hyperlinks", "off"));
    if any(result.errorId == warningIds)
        result.warningIds = result.errorId;
    end
end

clear cleanupWarnings
clear cleanupModel
result.modelHashAfter = sha256File(modelPath);
assert(result.modelHashAfter == result.modelHashBefore, ...
    "steady53:ModelWasRewritten", ...
    "Diagnostic run rewrote the model file.");
clear cleanupFileGen cleanupPath
end

function result = emptyResult(before)
emptyStates = struct( ...
    "path", {}, "fluid", {}, "data", {}, ...
    "kind", {}, "signPolicy", {});
result = struct( ...
    "success", false, ...
    "errorId", "", ...
    "errorReport", "", ...
    "tFinal_s", NaN, ...
    "t", [], ...
    "signals", struct(), ...
    "states", emptyStates, ...
    "warningIds", strings(0, 1), ...
    "modelHashBefore", before, ...
    "modelHashAfter", "");
end

function enableManifestLogging(manifest)
for index = 1:numel(manifest)
    ports = get_param(manifest(index).block, "PortHandles");
    set_param(ports.Outport(manifest(index).port), ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", manifest(index).name);
end
end

function enableStateLogging(stateMeta, stateLogNames)
for index = 1:numel(stateMeta)
    ports = get_param(stateMeta(index).path, "PortHandles");
    set_param(ports.Outport(1), ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", stateLogNames(index));
end
end

function signals = collectManifestSignals(logsout, manifest, targetTime)
signals = struct();
for index = 1:numel(manifest)
    element = logsout.get(manifest(index).name);
    if isempty(element)
        error("steady53:MissingLoggedSignal", ...
            "No logged signal named '%s'.", manifest(index).name);
    end
    signals.(manifest(index).name) = alignSeries( ...
        element.Values, targetTime, manifest(index).name);
end
end

function states = collectStates(logsout, stateMeta, stateLogNames, targetTime)
states = repmat(struct( ...
    "path", "", "fluid", "", "data", [], ...
    "kind", "", "signPolicy", ""), numel(stateMeta), 1);
for index = 1:numel(stateMeta)
    element = logsout.get(stateLogNames(index));
    if isempty(element)
        error("steady53:MissingLoggedState", ...
            "No logged state named '%s' for '%s'.", ...
            stateLogNames(index), stateMeta(index).path);
    end
    states(index).path = stateMeta(index).path;
    states(index).fluid = stateMeta(index).fluid;
    states(index).kind = stateMeta(index).kind;
    states(index).signPolicy = stateMeta(index).signPolicy;
    states(index).data = alignSeries( ...
        element.Values, targetTime, stateMeta(index).path);
end
end

function values = workspaceSeries(output, name, targetTime)
try
    series = output.get(name);
catch exception
    error("steady53:MissingWorkspaceSeries", ...
        "Simulation output does not contain '%s': %s", ...
        name, exception.message);
end
values = alignSeries(series, targetTime, name);
end

function aligned = alignSeries(series, targetTime, label)
if isa(series, "timeseries")
    sourceTime = series.Time;
    sourceData = series.Data;
elseif isnumeric(series) && ismatrix(series) && size(series, 2) >= 2
    sourceTime = series(:, 1);
    sourceData = series(:, 2);
else
    error("steady53:UnsupportedSeries", ...
        "Unsupported logged series format for '%s'.", label);
end

sourceTime = double(sourceTime(:));
sourceData = squeeze(sourceData);
if ~isvector(sourceData)
    error("steady53:NonScalarSeries", ...
        "Logged series '%s' is not scalar-valued.", label);
end
sourceData = double(sourceData(:));
if numel(sourceTime) ~= numel(sourceData) || isempty(sourceTime) || ...
        any(~isfinite(sourceTime)) || any(~isfinite(sourceData)) || ...
        ~isreal(sourceTime) || ~isreal(sourceData)
    error("steady53:InvalidSeries", ...
        "Logged series '%s' has invalid time or data.", label);
end

% Keep the last sample at each repeated solver time. After this operation
% the time axis must be strictly increasing for interpolation.
[sourceTime, uniqueIndex] = unique(sourceTime, "last", "sorted");
sourceData = sourceData(uniqueIndex);
if isscalar(sourceTime)
    % A genuinely scalar logged constant has no temporal domain to
    % interpolate; replicating that one value is exact, not extrapolation.
    aligned = repmat(sourceData, size(targetTime));
    return
end
if any(diff(sourceTime) <= 0)
    error("steady53:InvalidSeriesTime", ...
        "Logged series '%s' has a non-increasing time axis.", label);
end

tolerance = 16 * eps(max(1, max(abs([sourceTime; targetTime(:)]))));
if targetTime(1) < sourceTime(1) - tolerance || ...
        targetTime(end) > sourceTime(end) + tolerance
    error("steady53:IncompleteSeriesCoverage", ...
        ["Logged series '%s' covers [%0.17g, %0.17g] but the " ...
         "simulation time covers [%0.17g, %0.17g]."], ...
        label, sourceTime(1), sourceTime(end), ...
        targetTime(1), targetTime(end));
end

clampedTarget = min(max(targetTime(:), sourceTime(1)), sourceTime(end));
aligned = interp1(sourceTime, sourceData, clampedTarget, "linear");
if any(~isfinite(aligned))
    error("steady53:AlignmentFailed", ...
        "Could not align logged series '%s'.", label);
end
end

function restoreWarnings(oldWarnings)
for index = 1:numel(oldWarnings)
    warning(oldWarnings{index}.state, oldWarnings{index}.identifier);
end
end

function closeLoadedModel(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function restoreFileGeneration(config, folder)
Simulink.fileGenControl("set", ...
    "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, ...
    "createDir", true);
if isfolder(folder)
    rmdir(folder, "s");
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

function quoted = matlabString(value)
quoted = "'" + replace(string(value), "'", "''") + "'";
end
