function result = run_steady53_case( ...
        modelPath, stopTime_s, logSignals, testControl)
%RUN_STEADY53_CASE Run a blocking, in-memory diagnostic simulation.
%   The runner rejects an already-loaded model, restores every external
%   MATLAB/Simulink setting it changes, never saves the model, and verifies
%   the source model hash after both successful and failed runs.

arguments
    modelPath {mustBeTextScalar}
    stopTime_s (1, 1) double {mustBePositive, mustBeFinite}
    logSignals (1, 1) logical = true
    testControl (1, 1) struct = struct()
end

modelPath = string(modelPath);
if modelPath == "__steady53_test_hooks__"
    result = steady53TestHooks();
    return
end
if ~startsWith(modelPath, filesep) || ~isfile(modelPath)
    error("steady53:ModelPathMustBeAbsolute", ...
        "modelPath must name an existing absolute .slx file.");
end
[modelDir, model, extension] = fileparts(modelPath);
if extension ~= ".slx"
    error("steady53:UnsupportedModelFile", ...
        "Expected an .slx model, got '%s'.", extension);
end

% This check intentionally precedes every path, base-workspace, file-
% generation, warning, and model side effect. A loaded diagram may contain
% unsaved user work and does not belong to this isolated runner.
if bdIsLoaded(model)
    error("steady53:ModelAlreadyLoaded", ...
        "Model '%s' is already loaded; no diagnostic changes were made.", ...
        model);
end

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
before = sha256File(modelPath);
result = emptyResult(before);
propertyIds = propertyWarningIdentifiers();

pathNeedsRestore = false;
oldPath = "";
fileGenerationNeedsRestore = false;
fileGenerationConfig = struct();
fileGenerationRoot = "";
baseNeedsRestore = false;
baseSnapshot = struct();
warningsNeedRestore = false;
oldWarnings = {};
propertyStateNeedsReset = false;
modelNeedsClose = false;
cleanupExceptions = cell(0, 1);
primaryException = [];

try
    oldPath = path;
    pathNeedsRestore = true;
    addpath(modelDir);

    fileGenerationConfig = Simulink.fileGenControl("getConfig");
    fileGenerationNeedsRestore = true;
    fileGenerationRoot = string(tempname);
    result.fileGenRoot = fileGenerationRoot;
    mkdir(fileGenerationRoot);
    Simulink.fileGenControl("set", ...
        "CacheFolder", fullfile(fileGenerationRoot, "cache"), ...
        "CodeGenFolder", fullfile(fileGenerationRoot, "codegen"), ...
        "createDir", true);

    startPath = fullfile(root, "start.m");
    startVariables = startWorkspaceVariables(startPath);
    baseSnapshot = captureBaseWorkspace(startVariables);
    baseNeedsRestore = true;
    evalin("base", "run(" + matlabString(startPath) + ")");

    % These functions persist only one-shot warning-suppression latches.
    % Rearm them before warning(error) so a prior call in the same MATLAB
    % session cannot hide an out-of-domain state from this isolated run.
    propertyStateNeedsReset = true;
    reset_steady53_property_warning_state();

    oldWarnings = cell(size(propertyIds));
    for index = 1:numel(propertyIds)
        oldWarnings{index} = warning("query", propertyIds(index));
    end
    warningsNeedRestore = true;
    for index = 1:numel(propertyIds)
        warning("error", propertyIds(index));
    end

    % Set the ownership flag before load_system so even a partial load is
    % closed without saving. The precondition above proved it was not a
    % user-owned loaded model.
    modelNeedsClose = true;
    load_system(modelPath);

    if isfield(testControl, "propertyFaultId")
        injectPropertyFault(testControl.propertyFaultId);
    end

    [manifest, stateMeta] = steady53_signal_manifest(model);
    stateLogNames = compose( ...
        "steady53_state_%03d", (1:numel(stateMeta)).');
    if logSignals
        enableManifestLogging(manifest);
        enableStateLogging(stateMeta, stateLogNames);
        signalLogging = "on";
    else
        signalLogging = "off";
    end

    simulationInput = Simulink.SimulationInput(model);
    simulationInput = simulationInput.setModelParameter( ...
        "StopTime", num2str(stopTime_s, "%.17g"), ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", signalLogging, ...
        "SignalLoggingName", "logsout");
    if isfield(testControl, "injectSimulationFailure") && ...
            isequal(testControl.injectSimulationFailure, true)
        simulationInput = simulationInput.setPreSimFcn( ...
            @injectSimulationFailure);
    end

    output = sim(simulationInput);
    result.t = output.tout(:);
    validateSimulationTime(result.t, stopTime_s);
    result.tFinal_s = result.t(end);
    if logSignals
        result.signals = collectManifestSignals( ...
            output.logsout, manifest, result.t);
        result.signals.reactor_power = workspaceSeries( ...
            output, "P_sw", result.t);

        % Read-only arithmetic diagnostic. eta is derived from thesis Table
        % 5.2 values (evidence grade ❓), is not a model parameter, and is
        % never written back into final_steady_24a.slx.
        etaGenerator = 1000.21e3 / (2252.2e3 - 1231.6e3);
        result.signals.tac_electric_power = etaGenerator .* ...
            (result.signals.turbine_power - ...
             result.signals.compressor_power);
        result.states = collectStates( ...
            output.logsout, stateMeta, stateLogNames, result.t);
    end
    result.success = true;
catch exception
    primaryException = exception;
    result = recordFailure(result, exception, propertyIds);
end

cleanupAll();
result.modelHashAfter = sha256File(modelPath);
if result.modelHashAfter ~= result.modelHashBefore
    rewriteException = MException( ...
        "steady53:ModelWasRewritten", ...
        "Diagnostic run rewrote the model file '%s'.", modelPath);
    if ~isempty(primaryException)
        rewriteException = addCause(rewriteException, primaryException);
    end
    for index = 1:numel(cleanupExceptions)
        rewriteException = addCause( ...
            rewriteException, cleanupExceptions{index});
    end
    throw(rewriteException)
end

if ~isempty(cleanupExceptions)
    cleanupException = MException("steady53:CleanupFailed", ...
        "One or more diagnostic cleanup operations failed.");
    if ~isempty(primaryException)
        cleanupException = addCause(cleanupException, primaryException);
    end
    for index = 1:numel(cleanupExceptions)
        cleanupException = addCause( ...
            cleanupException, cleanupExceptions{index});
    end
    result = recordFailure(result, cleanupException, propertyIds);
end

    function cleanupAll()
        if modelNeedsClose
            modelNeedsClose = false;
            try
                closeLoadedModel(model);
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
        if propertyStateNeedsReset
            propertyStateNeedsReset = false;
            try
                reset_steady53_property_warning_state();
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
        if warningsNeedRestore
            warningsNeedRestore = false;
            try
                restoreWarnings(oldWarnings);
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
        if baseNeedsRestore
            baseNeedsRestore = false;
            try
                restoreBaseWorkspace(baseSnapshot);
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
        if fileGenerationNeedsRestore
            fileGenerationNeedsRestore = false;
            try
                Simulink.fileGenControl("set", ...
                    "CacheFolder", fileGenerationConfig.CacheFolder, ...
                    "CodeGenFolder", fileGenerationConfig.CodeGenFolder, ...
                    "createDir", true);
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
            try
                if isfolder(fileGenerationRoot)
                    rmdir(fileGenerationRoot, "s");
                end
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
        if pathNeedsRestore
            pathNeedsRestore = false;
            try
                path(oldPath);
            catch exception
                cleanupExceptions{end + 1, 1} = exception;
            end
        end
    end
end

function injectPropertyFault(identifier)
identifier = string(identifier);
switch identifier
    case "HeXe:T_hi"
        HeXe_property_simulink(2001, 1e6);
    case "HeXe:T_lo"
        HeXe_property_simulink(99, 1e6);
    case "Lithium_property_simulink:TemperatureAboveRange"
        Lithium_property_simulink(1609, 1e6);
    case "Lithium_property_simulink:TemperatureBelowRange"
        Lithium_property_simulink(453, 1e6);
    otherwise
        error("steady53:UnsupportedPropertyFault", ...
            "Unsupported diagnostic property fault ID '%s'.", identifier);
end
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
    "modelHashAfter", "", ...
    "fileGenRoot", "");
end

function result = recordFailure(result, exception, propertyIds)
result.success = false;
result.errorId = string(exception.identifier);
result.errorReport = string(getReport( ...
    exception, "extended", "hyperlinks", "off"));
result.warningIds = propertyWarningIds(exception, propertyIds);
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
        element.Values, targetTime, manifest(index).name, ...
        manifest(index).constant);
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
        element.Values, targetTime, stateMeta(index).path, false);
end
end

function values = workspaceSeries(output, name, targetTime)
try
    series = output.get(name);
catch exception
    missing = MException("steady53:MissingWorkspaceSeries", ...
        "Simulation output does not contain '%s'.", name);
    missing = addCause(missing, exception);
    throw(missing)
end
values = alignSeries(series, targetTime, name, false);
end

function aligned = alignSeries(series, targetTime, label, allowConstant)
arguments
    series
    targetTime
    label {mustBeTextScalar}
    allowConstant (1, 1) logical
end

targetTime = validateTargetTime(targetTime, label);
if isa(series, "timeseries")
    sourceTime = series.Time;
    sourceData = series.Data;
elseif isnumeric(series) && ismatrix(series) && size(series, 2) == 2
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
if any(diff(sourceTime) < 0)
    error("steady53:InvalidSeriesTime", ...
        "Logged series '%s' moves backward in time.", label);
end

tolerance = timeTolerance([sourceTime; targetTime]);
if isscalar(sourceTime)
    if ~allowConstant
        error("steady53:SingletonNonConstant", ...
            "Nonconstant series '%s' contains only one sample.", label);
    end
    if abs(sourceTime - targetTime(1)) > tolerance
        error("steady53:IncompleteSeriesCoverage", ...
            "Constant series '%s' does not start with the target time.", ...
            label);
    end
    aligned = repmat(sourceData, size(targetTime));
    return
end

% sourceTime is nondecreasing, so duplicates are contiguous. Retaining the
% final element of each run preserves original ordering without sorting and
% cannot hide a time-axis rollback.
keep = [diff(sourceTime) ~= 0; true];
sourceTime = sourceTime(keep);
sourceData = sourceData(keep);
if targetTime(1) < sourceTime(1) - tolerance || ...
        targetTime(end) > sourceTime(end) + tolerance
    error("steady53:IncompleteSeriesCoverage", ...
        "Logged series '%s' covers [%0.17g, %0.17g] but the " + ...
        "target time covers [%0.17g, %0.17g].", ...
        label, sourceTime(1), sourceTime(end), ...
        targetTime(1), targetTime(end));
end

clampedTarget = min(max(targetTime, sourceTime(1)), sourceTime(end));
aligned = interp1(sourceTime, sourceData, clampedTarget, "linear");
if any(~isfinite(aligned))
    error("steady53:AlignmentFailed", ...
        "Could not align logged series '%s'.", label);
end
end

function targetTime = validateTargetTime(targetTime, label)
if ~isnumeric(targetTime) || ~isvector(targetTime) || ...
        isempty(targetTime) || ~isreal(targetTime)
    error("steady53:InvalidTargetTime", ...
        "Target time for '%s' must be a nonempty real vector.", label);
end
targetTime = double(targetTime(:));
if any(~isfinite(targetTime)) || any(diff(targetTime) <= 0)
    error("steady53:InvalidTargetTime", ...
        "Target time for '%s' must be finite and strictly increasing.", ...
        label);
end
end

function validateSimulationTime(time, requestedStopTime)
if ~isnumeric(time) || ~isvector(time) || isempty(time) || ...
        ~isreal(time)
    error("steady53:InvalidSimulationTime", ...
        "Simulation returned an invalid time vector.");
end
time = double(time(:));
if any(~isfinite(time)) || time(1) ~= 0 || any(diff(time) <= 0)
    error("steady53:InvalidSimulationTime", ...
        "Simulation time must start at zero and be strictly increasing.");
end
tolerance = timeTolerance([time; requestedStopTime]);
if abs(time(end) - requestedStopTime) > tolerance
    error("steady53:IncompleteSimulation", ...
        "Simulation ended at %.17g s instead of the requested %.17g s " + ...
        "(tolerance %.17g s).", ...
        time(end), requestedStopTime, tolerance);
end
end

function simulationInput = injectSimulationFailure(simulationInput) %#ok<INUSD>
error("steady53:InjectedSimulationFailure", ...
    "Controlled in-memory failure injected by the Task 3 test suite.");
end

function tolerance = timeTolerance(values)
scale = max(1, max(abs(double(values(:)))));
tolerance = 16 * eps(scale);
end

function identifiers = propertyWarningIdentifiers()
identifiers = ["HeXe:T_lo"; "HeXe:T_hi"; ...
    "Lithium_property_simulink:TemperatureBelowRange"; ...
    "Lithium_property_simulink:TemperatureAboveRange"];
end

function identifiers = propertyWarningIds(exception, allowed)
identifiers = strings(0, 1);
visit(exception);
identifiers = unique(identifiers, "stable");

    function visit(current)
        identifier = string(current.identifier);
        if any(identifier == allowed)
            identifiers(end + 1, 1) = identifier;
        end
        causes = current.cause;
        for causeIndex = 1:numel(causes)
            visit(causes{causeIndex});
        end
    end
end

function hooks = steady53TestHooks()
allowed = propertyWarningIdentifiers();
hooks = struct( ...
    "alignSeries", @alignSeries, ...
    "validateSimulationTime", @validateSimulationTime, ...
    "propertyWarningIds", ...
    @(exception) propertyWarningIds(exception, allowed));
end

function names = startWorkspaceVariables(startPath)
variablesBefore = string(who);
run(startPath);
variablesAfter = string(who);
helperVariables = [variablesBefore; "variablesBefore"; ...
    "variablesAfter"; "helperVariables"; "names"];
names = setdiff(variablesAfter, helperVariables, "stable");
end

function snapshot = captureBaseWorkspace(names)
names = string(names(:));
snapshot = struct( ...
    "names", names, ...
    "existed", false(size(names)), ...
    "values", {cell(size(names))});
for index = 1:numel(names)
    snapshot.existed(index) = evalin("base", ...
        "exist(" + matlabString(names(index)) + ", 'var') == 1");
    if snapshot.existed(index)
        snapshot.values{index} = evalin("base", names(index));
    end
end
end

function restoreBaseWorkspace(snapshot)
for index = 1:numel(snapshot.names)
    name = snapshot.names(index);
    if snapshot.existed(index)
        assignin("base", name, snapshot.values{index});
    else
        evalin("base", "clear " + name);
    end
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
