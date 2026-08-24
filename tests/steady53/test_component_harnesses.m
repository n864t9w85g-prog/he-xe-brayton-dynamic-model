function tests = test_component_harnesses
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = string(root);
testCase.TestData.source = fullfile(root, "final_steady_24a.slx");
testCase.TestData.environment = captureEnvironment();
testCase.TestData.base = captureBaseWorkspace();

addpath(root);
addpath(fullfile(root, "tests", "steady53"));
fileGenRoot = string(tempname);
mkdir(fileGenRoot);
testCase.TestData.fileGenRoot = fileGenRoot;
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(fileGenRoot, "codegen"), ...
    "createDir", true);
evalin("base", "run(" + matlabString(fullfile(root, "start.m")) + ")");
end

function teardownOnce(testCase)
closeHarnessModels();
restoreBaseWorkspace(testCase.TestData.base);
restoreEnvironment(testCase.TestData.environment);
if isfolder(testCase.TestData.fileGenRoot)
    rmdir(testCase.TestData.fileGenRoot, "s");
end
end

function testBoundaryValuesSourcesAndGradesAreExplicit(testCase)
b = steady53_component_boundaries();

verifyEqual(testCase, b.IHX.inputs, ...
    [1600 4.572 11.97 1100.91 1.543e6]);
verifyEqual(testCase, b.IHX.inputNames, ...
    ["T_hi" "mdot_Li" "mdot_HeXe" "T_ci" "P_ci"]);
verifyEqual(testCase, b.IHX.outputNames, ...
    ["T_ho" "P_co" "T_co" "mdot_Li_out" "mdot_c_out"]);
verifyEqual(testCase, b.recuperator.inputs, ...
    [11.97 1162 0.676e6 1.551e6 601.90 11.97]);
verifyEqual(testCase, b.precooler.inputs, ...
    [360.10 6.95 663.63 0.676e6 11.97]);
verifyEqual(testCase, b.rediator.inputs, [609.58 6.95]);
verifyEqual(testCase, b.reactor.inputs, 1443.27);
verifyEqual(testCase, b.TAC.inputs, ...
    [1.539e6 1522.96 405.16 0.658e6 11.97 1000e3]);

components = expectedComponents();
verifyEqual(testCase, sort(string(fieldnames(b))), sort(components(:)));
for component = components
    item = b.(component);
    verifyEqual(testCase, numel(item.inputs), numel(item.inputNames), ...
        "Input-name count: " + component);
    verifyEqual(testCase, numel(item.inputs), numel(item.source), ...
        "Source count: " + component);
    verifyEqual(testCase, numel(item.inputs), numel(item.evidenceGrade), ...
        "Evidence-grade count: " + component);
    verifyTrue(testCase, all(strlength(item.inputNames) > 0));
    verifyTrue(testCase, all(strlength(item.source) > 0));
    verifyTrue(testCase, all(startsWith(item.evidenceGrade, ...
        ["✅" "⚠️" "❓" "❌"])), ...
        "Invalid evidence grade: " + component);
end

verifyTrue(testCase, contains(b.IHX.source(2), "not thesis direct"));
verifyTrue(testCase, startsWith(b.IHX.evidenceGrade(2), "❓"));
verifyTrue(testCase, contains(b.TAC.source(6), "Section 5.3.1"));
verifyTrue(testCase, startsWith(b.TAC.evidenceGrade(6), "❓"));
end

function testHarnessesCompileAndPreserveSource(testCase)
sourceHash = sha256File(testCase.TestData.source);
components = expectedComponents();
for component = components
    before = captureEnvironment();
    beforeBase = captureBaseWorkspace();
    h = create_component_harness(component);
    cleanup = onCleanup(@() closeIfLoaded(h.model));

    verifyTrue(testCase, startsWith(h.path, h.runDir + filesep));
    verifyTrue(testCase, isfile(h.path));
    verifyTrue(testCase, bdIsLoaded(h.model));
    verifyEqual(testCase, h.component, component);
    verifyEqual(testCase, h.sourceHash, sourceHash);
    verifyEqual(testCase, sha256File(testCase.TestData.source), sourceHash);
    verifyEqual(testCase, h.inputNames, ...
        steady53_component_boundaries().(component).inputNames);
    verifyEqual(testCase, h.outputNames, ...
        steady53_component_boundaries().(component).outputNames);
    verifyEqual(testCase, orderedPortNames(h.model + "/DUT", "Inport"), ...
        h.inputNames);
    verifyEqual(testCase, orderedPortNames(h.model + "/DUT", "Outport"), ...
        h.outputNames);
    verifyEqual(testCase, countTopBlocks(h.model, "Constant"), ...
        numel(h.inputNames));
    verifyEqual(testCase, countTopBlocks(h.model, "ToWorkspace"), ...
        numel(h.outputNames));

    set_param(h.model, "SimulationCommand", "update");
    verifyDutSemanticDelta(testCase, h, component == "TAC");
    verifyEnvironmentEqual(testCase, captureEnvironment(), before);
    verifyBaseEqual(testCase, captureBaseWorkspace(), beforeBase);
    clear cleanup
end
verifyEqual(testCase, sha256File(testCase.TestData.source), sourceHash);
end

function testHarnessesRunBoundedFor500Seconds(testCase)
matrix = runComponentMatrix(testCase, 500);
saveMatrix(testCase.TestData.root, matrix, 500);
verifyTrue(testCase, all([matrix.success]), matrixFailureMessage(matrix));
end

function testHarnessesRunBoundedFor14000Seconds(testCase)
matrix = runComponentMatrix(testCase, 14000);
saveMatrix(testCase.TestData.root, matrix, 14000);
verifyTrue(testCase, all([matrix.success]), matrixFailureMessage(matrix));
end

function matrix = runComponentMatrix(~, stopTime_s)
ids = propertyWarningIdentifiers();
old = cell(size(ids));
for index = 1:numel(ids)
    old{index} = warning("query", ids(index));
    warning("error", ids(index));
end
warningCleanup = onCleanup(@() restoreWarningStates(old));

components = expectedComponents();
blank = struct("component", "", "stopTime", stopTime_s, ...
    "success", false, "tFinal", NaN, "failureTime_s", NaN, ...
    "errorId", "", "errorReport", "", ...
    "warningIds", strings(0, 1));
matrix = repmat(blank, numel(components), 1);
for componentIndex = 1:numel(components)
    component = components(componentIndex);
    matrix(componentIndex).component = component;
    h = struct("model", "");
    try
        h = create_component_harness(component);
        modelCleanup = onCleanup(@() closeIfLoaded(h.model));
        out = sim(h.model, ...
            "StopTime", num2str(stopTime_s, "%.17g"), ...
            "ReturnWorkspaceOutputs", "on");
        validateOutput(out, h, stopTime_s);
        matrix(componentIndex).tFinal = double(out.tout(end));
        matrix(componentIndex).success = true;
        clear modelCleanup
    catch exception
        matrix(componentIndex).errorId = string(exception.identifier);
        matrix(componentIndex).errorReport = string(getReport( ...
            exception, "extended", "hyperlinks", "off"));
        matrix(componentIndex).warningIds = propertyWarningIds(exception, ids);
        matrix(componentIndex).failureTime_s = ...
            firstFailureTime(matrix(componentIndex).errorReport);
        if strlength(h.model) > 0
            closeIfLoaded(h.model);
        end
    end
end
clear warningCleanup
end

function validateOutput(out, h, stopTime_s)
time = double(out.tout(:));
if isempty(time) || any(~isfinite(time)) || ~isreal(time) || ...
        time(1) ~= 0 || any(diff(time) <= 0) || ...
        abs(time(end) - stopTime_s) > 16 * eps(max(1, stopTime_s))
    error("steady53:InvalidComponentTime", ...
        "Component %s returned an invalid or incomplete time vector.", ...
        h.component);
end
for outputIndex = 1:numel(h.outputVariables)
    variable = h.outputVariables(outputIndex);
    series = out.get(variable);
    if ~isa(series, "timeseries") || isempty(series.Data) || ...
            any(~isfinite(series.Data(:))) || ~isreal(series.Data)
        error("steady53:InvalidComponentOutput", ...
            "Component %s output %s is not finite real timeseries data.", ...
            h.component, variable);
    end
end
end

function saveMatrix(root, matrix, stopTime_s)
outputDir = fullfile(root, "tmp", "steady53", "components");
if ~isfolder(outputDir)
    mkdir(outputDir);
end
matPath = fullfile(outputDir, ...
    "component_matrix_" + stopTime_s + ".mat");
textPath = fullfile(outputDir, ...
    "component_matrix_" + stopTime_s + ".txt");
save(matPath, "matrix", "-v7.3");
fileId = fopen(textPath, "w");
assert(fileId >= 0, "Could not create matrix text evidence.");
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "component\tstopTime\tsuccess\ttFinal\tfailureTime\terrorId\twarningIds\n");
for index = 1:numel(matrix)
    fprintf(fileId, "%s\t%.17g\t%d\t%.17g\t%.17g\t%s\t%s\n", ...
        matrix(index).component, matrix(index).stopTime, ...
        matrix(index).success, matrix(index).tFinal, ...
        matrix(index).failureTime_s, matrix(index).errorId, ...
        strjoin(matrix(index).warningIds, ","));
end
clear cleanup
end

function message = matrixFailureMessage(matrix)
failed = matrix(~[matrix.success]);
if isempty(failed)
    message = "All component harnesses completed.";
    return
end
lines = strings(numel(failed), 1);
for index = 1:numel(failed)
    lines(index) = failed(index).component + ...
        ": tFinal=" + string(failed(index).tFinal) + ...
        ", failureTime=" + string(failed(index).failureTime_s) + ...
        ", id=" + failed(index).errorId + ...
        ", propertyWarnings=" + printableIds(failed(index).warningIds);
end
message = strjoin(lines, newline);
end

function value = printableIds(ids)
if isempty(ids)
    value = "<none>";
else
    value = strjoin(ids, ",");
end
end

function verifyDutSemanticDelta(testCase, h, expectSpeedDelta)
sourceModel = "final_steady_24a";
load_system(h.sourcePath);
sourceCleanup = onCleanup(@() closeIfLoaded(sourceModel));
sourceRoot = sourceModel + "/" + h.component;
dutRoot = h.model + "/DUT";

sourceBlocks = string(find_system(sourceRoot, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
dutBlocks = string(find_system(dutRoot, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
sourceRelative = erase(sourceBlocks, sourceRoot);
dutRelative = erase(dutBlocks, dutRoot);
verifyEqual(testCase, sort(sourceRelative), sort(dutRelative));

different = strings(0, 1);
for relative = sourceRelative(:).'
    sourceBlock = sourceRoot + relative;
    dutBlock = dutRoot + relative;
    verifyEqual(testCase, string(get_param(sourceBlock, "BlockType")), ...
        string(get_param(dutBlock, "BlockType")));
    sourceDialog = get_param(sourceBlock, "DialogParameters");
    dutDialog = get_param(dutBlock, "DialogParameters");
    if isempty(sourceDialog) && isempty(dutDialog)
        continue
    end
    sourceNames = string(fieldnames(sourceDialog));
    dutNames = string(fieldnames(dutDialog));
    verifyEqual(testCase, sort(sourceNames), sort(dutNames));
    for parameter = sourceNames(:).'
        if ~isequaln(get_param(sourceBlock, parameter), ...
                get_param(dutBlock, parameter))
            different(end + 1, 1) = relative + "::" + parameter; %#ok<AGROW>
        end
    end
end
if expectSpeedDelta
    verifyEqual(testCase, different, "/Constant::Value");
    verifyEqual(testCase, string(get_param(dutRoot + "/Constant", "Value")), ...
        "55090");
    verifyEqual(testCase, h.behavioralChanges, ...
        "DUT/Constant.Value: 66100 -> 55090 rpm");
else
    verifyEmpty(testCase, different);
    verifyEmpty(testCase, h.behavioralChanges);
end
verifyEqual(testCase, lineSignatures(sourceRoot), lineSignatures(dutRoot));
clear sourceCleanup
end

function signatures = lineSignatures(root)
lines = find_system(root, "FindAll", "on", "Type", "line");
signatures = strings(0, 1);
for index = 1:numel(lines)
    sourceBlock = get_param(lines(index), "SrcBlockHandle");
    sourcePort = get_param(lines(index), "SrcPortHandle");
    destinationBlocks = get_param(lines(index), "DstBlockHandle");
    destinationPorts = get_param(lines(index), "DstPortHandle");
    if sourceBlock < 0 || isempty(destinationBlocks)
        continue
    end
    sourceName = erase(string(getfullname(sourceBlock)), root);
    sourceNumber = string(get_param(sourcePort, "PortNumber"));
    for destinationIndex = 1:numel(destinationBlocks)
        if destinationBlocks(destinationIndex) < 0
            continue
        end
        destinationName = erase(string(getfullname( ...
            destinationBlocks(destinationIndex))), root);
        destinationNumber = string(get_param( ...
            destinationPorts(destinationIndex), "PortNumber"));
        signatures(end + 1, 1) = sourceName + ":" + sourceNumber + ...
            "->" + destinationName + ":" + destinationNumber; %#ok<AGROW>
    end
end
signatures = sort(signatures);
end

function count = countTopBlocks(model, blockType)
blocks = find_system(model, "SearchDepth", 1, "BlockType", blockType);
count = numel(blocks);
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

function components = expectedComponents()
components = ["IHX" "recuperator" "precooler" "rediator" "reactor" "TAC"];
end

function ids = propertyWarningIdentifiers()
ids = ["HeXe:T_lo" "HeXe:T_hi" ...
    "Lithium_property_simulink:TemperatureBelowRange" ...
    "Lithium_property_simulink:TemperatureAboveRange"];
end

function ids = propertyWarningIds(exception, allowed)
ids = strings(0, 1);
visit(exception);
ids = unique(ids, "stable");
    function visit(current)
        identifier = string(current.identifier);
        if any(identifier == allowed)
            ids(end + 1, 1) = identifier;
        end
        for causeIndex = 1:numel(current.cause)
            visit(current.cause{causeIndex});
        end
    end
end

function value = firstFailureTime(report)
tokens = regexp(report, ...
    '(?:time|\u65f6\u95f4)\s*[=:]?\s*([0-9]+(?:\.[0-9]+)?)', ...
    'tokens', 'once', 'ignorecase');
if isempty(tokens)
    value = NaN;
else
    value = str2double(tokens{1});
end
end

function restoreWarningStates(old)
for index = 1:numel(old)
    warning(old{index}.state, old{index}.identifier);
end
end

function snapshot = captureEnvironment()
snapshot = struct( ...
    "path", path, ...
    "pwd", string(pwd), ...
    "warnings", warning("query", "all"), ...
    "fileGeneration", Simulink.fileGenControl("getConfig"));
end

function restoreEnvironment(snapshot)
path(snapshot.path);
cd(snapshot.pwd);
for index = 1:numel(snapshot.warnings)
    warning(snapshot.warnings(index).state, ...
        snapshot.warnings(index).identifier);
end
Simulink.fileGenControl("set", ...
    "CacheFolder", snapshot.fileGeneration.CacheFolder, ...
    "CodeGenFolder", snapshot.fileGeneration.CodeGenFolder, ...
    "createDir", true);
end

function verifyEnvironmentEqual(testCase, actual, expected)
verifyEqual(testCase, actual.path, expected.path);
verifyEqual(testCase, actual.pwd, expected.pwd);
verifyEqual(testCase, actual.warnings, expected.warnings);
verifyEqual(testCase, actual.fileGeneration, expected.fileGeneration);
end

function snapshot = captureBaseWorkspace()
names = sort(string(evalin("base", "who")));
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

function verifyBaseEqual(testCase, actual, expected)
verifyEqual(testCase, actual.names, expected.names);
for index = 1:numel(actual.names)
    verifyTrue(testCase, isequaln(actual.values{index}, expected.values{index}), ...
        "Base variable changed: " + actual.names(index));
end
end

function closeHarnessModels()
models = string(find_system("type", "block_diagram"));
for model = models(:).'
    if startsWith(model, "s53_") || model == "final_steady_24a"
        closeIfLoaded(model);
    end
end
end

function closeIfLoaded(model)
if strlength(string(model)) > 0 && bdIsLoaded(model)
    close_system(model, 0);
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, output);
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end

function quoted = matlabString(value)
quoted = "'" + replace(string(value), "'", "''") + "'";
end
