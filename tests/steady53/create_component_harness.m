function harness = create_component_harness(component)
%CREATE_COMPONENT_HARNESS Copy one top-level component into an isolated model.
%   The source model is opened read-only and is never saved. Every call owns
%   a unique run directory and model name, so existing evidence is not
%   overwritten. The returned harness model is loaded and belongs to the
%   caller, which must close it without saving.

arguments
    component {mustBeTextScalar}
end
component = string(component);
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
sourceModel = "final_steady_24a";
sourcePath = fullfile(root, sourceModel + ".slx");
if ~isfile(sourcePath)
    error("steady53:MissingSourceModel", ...
        "Source model does not exist: %s", sourcePath);
end
if bdIsLoaded(sourceModel)
    error("steady53:SourceModelAlreadyLoaded", ...
        "Source model '%s' is already loaded; no harness was created.", ...
        sourceModel);
end

boundaries = steady53_component_boundaries();
if ~isfield(boundaries, component)
    error("steady53:UnknownComponent", ...
        "No approved Section 5.3.1 boundary exists for '%s'.", component);
end
boundary = boundaries.(component);
sourceHashBefore = sha256File(sourcePath);

componentsRoot = fullfile(root, "tmp", "steady53", "components");
if ~isfolder(componentsRoot)
    mkdir(componentsRoot);
end
runDir = string(tempname(componentsRoot));
mkdir(runDir);
[~, token] = fileparts(runDir);
model = string(matlab.lang.makeValidName( ...
    "s53_" + lower(component) + "_" + extractAfter(string(token), ...
    max(0, strlength(string(token)) - 11))));
model = extractBefore(model, min(strlength(model) + 1, namelengthmax + 1));
modelPath = fullfile(runDir, model + ".slx");
if bdIsLoaded(model)
    error("steady53:TargetModelAlreadyLoaded", ...
        "Generated target model '%s' is already loaded.", model);
end
if isfile(modelPath)
    error("steady53:TargetAlreadyExists", ...
        "Unique target already exists and will not be overwritten: %s", ...
        modelPath);
end

lifecycle = struct( ...
    "oldPath", path, ...
    "oldPwd", string(pwd), ...
    "fileGeneration", Simulink.fileGenControl("getConfig"), ...
    "fileGenRoot", fullfile(runDir, ".filegen"));
cleanup = onCleanup(@() restoreHarnessEnvironment( ...
    lifecycle, sourceModel, model));

addpath(root);
mkdir(lifecycle.fileGenRoot);
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(lifecycle.fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(lifecycle.fileGenRoot, "codegen"), ...
    "createDir", true);

% Ownership is established before load/new so partially completed calls
% cannot leave diagrams loaded.
load_system(sourcePath);
new_system(model);
add_block(sourceModel + "/" + component, model + "/DUT", ...
    "Position", [300 100 560 400]);

behavioralChanges = strings(0, 1);
if component == "TAC"
    speedPath = model + "/DUT/Constant";
    if string(get_param(speedPath, "Value")) ~= "66100"
        error("steady53:UnexpectedSourceSpeed", ...
            "Expected copied TAC speed 66100 rpm at %s.", speedPath);
    end
    set_param(speedPath, "Value", "55090");
    behavioralChanges = "DUT/Constant.Value: 66100 -> 55090 rpm";
end

inputNames = orderedPortNames(model + "/DUT", "Inport");
if numel(inputNames) ~= numel(boundary.inputs)
    error("steady53:ComponentInputCountMismatch", ...
        "Component %s has %d inputs but boundary contract has %d.", ...
        component, numel(inputNames), numel(boundary.inputs));
end
if ~isequal(inputNames, boundary.inputNames)
    error("steady53:ComponentInputNameMismatch", ...
        "Component %s actual inputs [%s] do not match contract [%s].", ...
        component, strjoin(inputNames, ", "), ...
        strjoin(boundary.inputNames, ", "));
end

for index = 1:numel(inputNames)
    blockName = "Input_" + compose("%03d", index);
    add_block("simulink/Sources/Constant", model + "/" + blockName, ...
        "Value", num2str(boundary.inputs(index), "%.17g"), ...
        "Position", [40 35 + 48 * index 155 57 + 48 * index]);
    add_line(model, blockName + "/1", "DUT/" + index, ...
        "autorouting", "on");
end

outputNames = orderedPortNames(model + "/DUT", "Outport");
if ~isequal(outputNames, boundary.outputNames)
    error("steady53:ComponentOutputNameMismatch", ...
        "Component %s actual outputs [%s] do not match contract [%s].", ...
        component, strjoin(outputNames, ", "), ...
        strjoin(boundary.outputNames, ", "));
end
outputVariables = strings(size(outputNames));
for index = 1:numel(outputNames)
    blockName = "Output_" + compose("%03d", index);
    outputVariables(index) = "y_" + compose("%03d", index);
    add_block("simulink/Sinks/To Workspace", model + "/" + blockName, ...
        "VariableName", outputVariables(index), ...
        "SaveFormat", "Timeseries", ...
        "Position", [670 35 + 48 * index 810 57 + 48 * index]);
    add_line(model, "DUT/" + index, blockName + "/1", ...
        "autorouting", "on");
end

set_param(model, ...
    "Solver", "ode15s", ...
    "RelTol", "1e-3", ...
    "StopTime", "500", ...
    "ReturnWorkspaceOutputs", "on");
save_system(model, modelPath);
close_system(model, 0);
clear cleanup

sourceHashAfter = sha256File(sourcePath);
if sourceHashAfter ~= sourceHashBefore
    closeIfLoaded(model);
    error("steady53:SourceModelWasRewritten", ...
        "Harness creation rewrote the source model '%s'.", sourcePath);
end
load_system(modelPath);

harness = struct( ...
    "model", model, ...
    "path", string(modelPath), ...
    "component", component, ...
    "runDir", string(runDir), ...
    "sourcePath", string(sourcePath), ...
    "sourceHash", sourceHashAfter, ...
    "inputNames", inputNames, ...
    "outputNames", outputNames, ...
    "outputVariables", outputVariables, ...
    "behavioralChanges", behavioralChanges);
end

function names = orderedPortNames(root, blockType)
ports = find_system(root, "SearchDepth", 1, "BlockType", blockType);
numbers = cellfun(@(item) str2double(get_param(item, "Port")), ports);
[~, order] = sort(numbers);
ports = ports(order);
names = string(cellfun(@(item) get_param(item, "Name"), ...
    ports, "UniformOutput", false));
names = names(:).';
end

function restoreHarnessEnvironment(lifecycle, sourceModel, targetModel)
exceptions = cell(0, 1);
tryCleanup(@() closeIfLoaded(targetModel));
tryCleanup(@() closeIfLoaded(sourceModel));
tryCleanup(@() restoreFileGeneration(lifecycle.fileGeneration));
if isfolder(lifecycle.fileGenRoot)
    tryCleanup(@() rmdir(lifecycle.fileGenRoot, "s"));
end
tryCleanup(@() path(lifecycle.oldPath));
tryCleanup(@() cd(lifecycle.oldPwd));
if ~isempty(exceptions)
    combined = MException("steady53:HarnessCleanupFailed", ...
        "One or more harness cleanup operations failed.");
    for exceptionIndex = 1:numel(exceptions)
        combined = addCause(combined, exceptions{exceptionIndex});
    end
    throw(combined)
end

    function tryCleanup(operation)
        try
            operation();
        catch exception
            exceptions{end + 1, 1} = exception;
        end
    end
end

function restoreFileGeneration(config)
Simulink.fileGenControl("set", ...
    "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, ...
    "createDir", true);
end

function closeIfLoaded(model)
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
