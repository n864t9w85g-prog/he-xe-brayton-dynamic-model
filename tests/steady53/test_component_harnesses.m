function tests = test_component_harnesses
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.loadedModelsBefore = loadedBlockDiagrams();
testCase.TestData.ownedModels = strings(0, 1);
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
matrixRunsRoot = fullfile(root, "tmp", "steady53", ...
    "components", "matrix_runs");
testCase.TestData.matrixEvidence = beginMatrixEvidenceRun(matrixRunsRoot);
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(fileGenRoot, "codegen"), ...
    "createDir", true);
evalin("base", "run(" + matlabString(fullfile(root, "start.m")) + ")");
end

function teardownOnce(testCase)
exceptions = cell(0, 1);
tryCleanup(@() closeOwnedHarnessModels( ...
    testCase.TestData.loadedModelsBefore, ...
    testCase.TestData.ownedModels));
tryCleanup(@() restoreBaseWorkspace(testCase.TestData.base));
tryCleanup(@() path(testCase.TestData.environment.path));
tryCleanup(@() cd(testCase.TestData.environment.pwd));
tryCleanup(@() restoreWarningSnapshot( ...
    testCase.TestData.environment.warnings));
tryCleanup(@() restoreFileGenerationSnapshot( ...
    testCase.TestData.environment.fileGeneration));
tryCleanup(@() removeOwnedDirectory(testCase.TestData.fileGenRoot));
if ~isempty(exceptions)
    combined = MException("steady53:ComponentHarnessTeardownFailed", ...
        "One or more component-harness teardown operations failed.");
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
    registerOwnedModel(testCase, h.model);
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
    verifyDutMatchesSource(testCase, h);
    if component == "TAC"
        verifyEqual(testCase, str2double(get_param( ...
            h.model + "/DUT/Constant", "Value")), 55090, "AbsTol", 1);
    end
    verifyEnvironmentEqual(testCase, captureEnvironment(), before);
    verifyBaseEqual(testCase, captureBaseWorkspace(), beforeBase);
    clear cleanup
end
verifyEqual(testCase, sha256File(testCase.TestData.source), sourceHash);
end

function testMatrixEvidenceRunsAreUniqueAndImmutable(testCase)
evidenceRoot = string(tempname);
mkdir(evidenceRoot);
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
matrix500 = syntheticMatrix(500);
matrix14000 = syntheticMatrix(14000);

first = beginMatrixEvidenceRun(evidenceRoot);
firstManifestHash = sha256File(first.manifestPath);
saveMatrix(first, matrix500, 500);
saveMatrix(first, matrix14000, 14000);
firstPaths = [first.matrix500Mat first.matrix500Text ...
    first.matrix14000Mat first.matrix14000Text];
firstHashes = arrayfun(@sha256File, firstPaths);

second = beginMatrixEvidenceRun(evidenceRoot);
saveMatrix(second, matrix500, 500);
saveMatrix(second, matrix14000, 14000);

verifyNotEqual(testCase, first.runId, second.runId);
verifyNotEqual(testCase, first.runDir, second.runDir);
verifyTrue(testCase, all(isfile(firstPaths)));
verifyTrue(testCase, all(startsWith(firstPaths, first.runDir + filesep)));
verifyEqual(testCase, arrayfun(@sha256File, firstPaths), firstHashes);
verifyEqual(testCase, sha256File(first.manifestPath), firstManifestHash);
verifyError(testCase, @() saveMatrix(first, matrix500, 500), ...
    "steady53:MatrixEvidenceAlreadyExists");
clear cleanup
end

function testOwnedCleanupPreservesPreloadedDirtyUserModels(testCase)
sourceModel = "final_steady_24a";
verifyFalse(testCase, bdIsLoaded(sourceModel));
load_system(testCase.TestData.source);
originalStopTime = string(get_param(sourceModel, "StopTime"));
sourceCleanup = onCleanup(@() restoreAndCloseSource( ...
    sourceModel, originalStopTime));
set_param(sourceModel, "StopTime", "801");
verifyEqual(testCase, string(get_param(sourceModel, "Dirty")), "on");

userModel = uniqueTestModelName("s53_user_");
new_system(userModel);
userCleanup = onCleanup(@() closeIfLoaded(userModel));
add_block("simulink/Sources/Constant", userModel + "/UserValue", ...
    "Value", "42");
verifyEqual(testCase, string(get_param(userModel, "Dirty")), "on");

suiteModel = uniqueTestModelName("s53_suite_");
new_system(suiteModel);
suiteCleanup = onCleanup(@() closeIfLoaded(suiteModel));
add_block("simulink/Sources/Constant", suiteModel + "/OwnedValue", ...
    "Value", "7");

loadedBefore = [sourceModel; userModel];
ownedModels = suiteModel;
closeOwnedHarnessModels(loadedBefore, ownedModels);

verifyTrue(testCase, bdIsLoaded(sourceModel));
verifyEqual(testCase, string(get_param(sourceModel, "Dirty")), "on");
verifyEqual(testCase, string(get_param(sourceModel, "StopTime")), "801");
verifyTrue(testCase, bdIsLoaded(userModel));
verifyEqual(testCase, string(get_param(userModel, "Dirty")), "on");
verifyEqual(testCase, string(get_param(userModel + "/UserValue", "Value")), ...
    "42");
verifyFalse(testCase, bdIsLoaded(suiteModel));
clear suiteCleanup userCleanup sourceCleanup
end

function testHarnessesRunBoundedFor500Seconds(testCase)
matrix = runComponentMatrix(testCase, 500);
published = saveMatrix(testCase.TestData.matrixEvidence, matrix, 500);
verifyEqual(testCase, published.runDir, ...
    testCase.TestData.matrixEvidence.runDir);
verifyTrue(testCase, all([matrix.success]), matrixFailureMessage(matrix));
end

function testHarnessesRunBoundedFor14000Seconds(testCase)
matrix = runComponentMatrix(testCase, 14000);
published = saveMatrix(testCase.TestData.matrixEvidence, matrix, 14000);
verifyEqual(testCase, published.runDir, ...
    testCase.TestData.matrixEvidence.runDir);
verifyTrue(testCase, all([matrix.success]), matrixFailureMessage(matrix));
end

function testPoisonedWarningLatchesCannotHideInjectedFaults(testCase)
faults = [ ...
    propertyFault("HeXe:T_hi", "TAC", "Input_002", "Value", 2001); ...
    propertyFault("Lithium_property_simulink:TemperatureAboveRange", ...
        "IHX", "DUT/IHX_region_1/T_h1_average_Integrator", ...
        "InitialCondition", 1609); ...
    propertyFault("HeXe:T_lo", "TAC", "Input_003", "Value", 99); ...
    propertyFault("Lithium_property_simulink:TemperatureBelowRange", ...
        "IHX", "DUT/IHX_region_1/T_h1_average_Integrator", ...
        "InitialCondition", 453)];
cleanup = onCleanup(@clearPropertyFunctions);
for fault = faults(:).'
    poisonPropertyWarningLatch(fault.id);
    matrix = runComponentMatrix(testCase, 1, fault);
    target = matrix([matrix.component] == fault.component);
    verifyNumElements(testCase, target, 1);
    verifyFalse(testCase, target.success, ...
        "Poisoned warning latch hid fault " + fault.id);
    verifyEqual(testCase, target.warningIds, fault.id);
    verifyTrue(testCase, all([matrix( ...
        [matrix.component] ~= fault.component).success]), ...
        matrixFailureMessage(matrix));
end
clear cleanup
end

function matrix = runComponentMatrix(testCase, stopTime_s, fault)
if nargin < 3
    fault = struct("id", "", "component", "", ...
        "blockPath", "", "parameter", "", "value", NaN);
end
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
        registerOwnedModel(testCase, h.model);
        reset_steady53_property_warning_state();
        propertyCleanup = onCleanup( ...
            @reset_steady53_property_warning_state);
        modelCleanup = onCleanup(@() closeIfLoaded(h.model));
        applyPropertyFault(h, component, fault);
        out = sim(h.model, ...
            "StopTime", num2str(stopTime_s, "%.17g"), ...
            "ReturnWorkspaceOutputs", "on");
        validateOutput(out, h, stopTime_s);
        matrix(componentIndex).tFinal = double(out.tout(end));
        matrix(componentIndex).success = true;
        clear modelCleanup
        clear propertyCleanup
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
        reset_steady53_property_warning_state();
    end
end
clear warningCleanup
end

function fault = propertyFault(id, component, blockPath, parameter, value)
fault = struct("id", string(id), "component", string(component), ...
    "blockPath", string(blockPath), "parameter", string(parameter), ...
    "value", double(value));
end

function applyPropertyFault(h, component, fault)
if strlength(fault.id) == 0 || component ~= fault.component
    return
end
set_param(h.model + "/" + fault.blockPath, fault.parameter, ...
    num2str(fault.value, "%.17g"));
end

function poisonPropertyWarningLatch(identifier)
clearPropertyFunctions();
old = warning("query", identifier);
cleanup = onCleanup(@() warning(old.state, old.identifier));
warning("off", identifier);
invokePropertyFault(identifier);
clear cleanup
end

function invokePropertyFault(identifier)
switch string(identifier)
    case "HeXe:T_hi"
        HeXe_property_simulink(2001, 1e6);
    case "HeXe:T_lo"
        HeXe_property_simulink(99, 1e6);
    case "Lithium_property_simulink:TemperatureAboveRange"
        Lithium_property_simulink(1609, 1e6);
    case "Lithium_property_simulink:TemperatureBelowRange"
        Lithium_property_simulink(453, 1e6);
    otherwise
        error("steady53:UnknownPropertyFault", ...
            "Unknown property fault ID '%s'.", identifier);
end
end

function clearPropertyFunctions()
clear("HeXe_property_simulink", "Lithium_property_simulink");
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

function evidence = beginMatrixEvidenceRun(matrixRunsRoot)
matrixRunsRoot = string(matrixRunsRoot);
if ~isfolder(matrixRunsRoot)
    mkdir(matrixRunsRoot);
end
runId = makeMatrixRunId();
runDir = fullfile(matrixRunsRoot, runId);
if isfolder(runDir) || isfile(runDir)
    error("steady53:MatrixRunCollision", ...
        "Unique matrix evidence run already exists: %s", runDir);
end
mkdir(runDir);
evidence = struct( ...
    "schemaVersion", 1, ...
    "runId", runId, ...
    "runDir", string(runDir), ...
    "matrix500Mat", fullfile(runDir, "component_matrix_500.mat"), ...
    "matrix500Text", fullfile(runDir, "component_matrix_500.txt"), ...
    "matrix14000Mat", fullfile(runDir, "component_matrix_14000.mat"), ...
    "matrix14000Text", fullfile(runDir, "component_matrix_14000.txt"), ...
    "manifestPath", fullfile(runDir, "matrix_manifest.mat"), ...
    "createdAt", utcTimestamp());
manifest = evidence;
stage = string(tempname(runDir)) + ".mat";
stageCleanup = onCleanup(@() deleteOwnedFile(stage));
save(stage, "manifest", "-v7.3");
publishExclusive(stage, evidence.manifestPath);
clear stageCleanup
end

function published = saveMatrix(evidence, matrix, stopTime_s)
arguments
    evidence (1, 1) struct
    matrix struct
    stopTime_s (1, 1) double
end
if stopTime_s == 500
    matPath = string(evidence.matrix500Mat);
    textPath = string(evidence.matrix500Text);
elseif stopTime_s == 14000
    matPath = string(evidence.matrix14000Mat);
    textPath = string(evidence.matrix14000Text);
else
    error("steady53:UnsupportedMatrixStopTime", ...
        "Matrix evidence supports only 500 s and 14000 s.");
end
if ~isfolder(evidence.runDir) || ~isfile(evidence.manifestPath)
    error("steady53:MissingMatrixEvidenceRun", ...
        "Matrix evidence run or manifest is missing: %s", evidence.runDir);
end
if isfile(matPath) || isfile(textPath)
    error("steady53:MatrixEvidenceAlreadyExists", ...
        "Matrix evidence target already exists in immutable run %s.", ...
        evidence.runId);
end

metadata = struct( ...
    "schemaVersion", evidence.schemaVersion, ...
    "runId", evidence.runId, ...
    "runDir", evidence.runDir, ...
    "stopTime_s", stopTime_s, ...
    "matPath", matPath, ...
    "textPath", textPath, ...
    "publishedAt", utcTimestamp());
matStage = string(tempname(evidence.runDir)) + ".mat";
textStage = string(tempname(evidence.runDir)) + ".txt";
matCleanup = onCleanup(@() deleteOwnedFile(matStage));
textCleanup = onCleanup(@() deleteOwnedFile(textStage));
save(matStage, "matrix", "metadata", "-v7.3");
fileId = fopen(textStage, "w");
assert(fileId >= 0, "Could not create matrix text evidence.");
fileCleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "component\tstopTime\tsuccess\ttFinal\tfailureTime\terrorId\twarningIds\n");
for index = 1:numel(matrix)
    fprintf(fileId, "%s\t%.17g\t%d\t%.17g\t%.17g\t%s\t%s\n", ...
        matrix(index).component, matrix(index).stopTime, ...
        matrix(index).success, matrix(index).tFinal, ...
        matrix(index).failureTime_s, matrix(index).errorId, ...
        strjoin(matrix(index).warningIds, ","));
end
clear fileCleanup
publishExclusive(matStage, matPath);
clear matCleanup
publishExclusive(textStage, textPath);
clear textCleanup
published = struct( ...
    "runId", string(evidence.runId), ...
    "runDir", string(evidence.runDir), ...
    "stopTime_s", stopTime_s, ...
    "matPath", matPath, ...
    "textPath", textPath, ...
    "matHash", sha256File(matPath), ...
    "textHash", sha256File(textPath));
end

function publishExclusive(stage, destination)
if isfile(destination)
    error("steady53:MatrixEvidenceAlreadyExists", ...
        "Matrix evidence target already exists: %s", destination);
end
[status, output] = system("ln " + shellQuote(stage) + " " + ...
    shellQuote(destination));
if status ~= 0
    if isfile(destination)
        error("steady53:MatrixEvidenceAlreadyExists", ...
            "Matrix evidence target already exists: %s", destination);
    end
    error("steady53:MatrixEvidencePublishFailed", ...
        "Could not exclusively publish %s: %s", destination, output);
end
deleteOwnedFile(stage);
end

function deleteOwnedFile(filePath)
if isfile(filePath)
    delete(filePath);
end
end

function runId = makeMatrixRunId()
milliseconds = string(round(posixtime(datetime("now", ...
    "TimeZone", "UTC")) * 1000));
uuid = replace(string(char(java.util.UUID.randomUUID())), "-", "");
runId = "matrix_" + milliseconds + "_" + uuid;
end

function timestamp = utcTimestamp()
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
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

function verifyDutMatchesSource(testCase, h)
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
verifyEmpty(testCase, different);
verifyEmpty(testCase, h.behavioralChanges);
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

function restoreWarningSnapshot(states)
exceptions = cell(0, 1);
for index = 1:numel(states)
    try
        warning(states(index).state, states(index).identifier);
    catch exception
        exceptions{end + 1, 1} = exception; %#ok<AGROW>
    end
end
throwCleanupExceptions("steady53:WarningRestoreFailed", ...
    "One or more warning states could not be restored.", exceptions);
end

function restoreFileGenerationSnapshot(config)
Simulink.fileGenControl("set", ...
    "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, ...
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
exceptions = cell(0, 1);
try
    current = string(evalin("base", "who"));
catch exception
    current = strings(0, 1);
    exceptions{end + 1, 1} = exception;
end
added = setdiff(current, snapshot.names);
for index = 1:numel(added)
    try
        evalin("base", "clear " + added(index));
    catch exception
        exceptions{end + 1, 1} = exception; %#ok<AGROW>
    end
end
for index = 1:numel(snapshot.names)
    try
        assignin("base", snapshot.names(index), snapshot.values{index});
    catch exception
        exceptions{end + 1, 1} = exception; %#ok<AGROW>
    end
end
throwCleanupExceptions("steady53:BaseRestoreFailed", ...
    "One or more base-workspace values could not be restored.", ...
    exceptions);
end

function verifyBaseEqual(testCase, actual, expected)
verifyEqual(testCase, actual.names, expected.names);
for index = 1:numel(actual.names)
    verifyTrue(testCase, isequaln(actual.values{index}, expected.values{index}), ...
        "Base variable changed: " + actual.names(index));
end
end

function registerOwnedModel(testCase, model)
model = string(model);
owned = string(testCase.TestData.ownedModels(:));
if ~any(owned == model)
    testCase.TestData.ownedModels(end + 1, 1) = model;
end
end

function closeOwnedHarnessModels(loadedModelsBefore, ownedModels)
loadedModelsBefore = string(loadedModelsBefore(:));
ownedModels = unique(string(ownedModels(:)), "stable");
current = loadedBlockDiagrams();
createdBySuite = setdiff(current, loadedModelsBefore, "stable");
toClose = intersect(createdBySuite, ownedModels, "stable");
exceptions = cell(0, 1);
for model = toClose(:).'
    try
        closeIfLoaded(model);
    catch exception
        exceptions{end + 1, 1} = exception; %#ok<AGROW>
    end
end
throwCleanupExceptions("steady53:OwnedModelCloseFailed", ...
    "One or more suite-owned harness models could not be closed.", ...
    exceptions);
end

function models = loadedBlockDiagrams()
models = string(find_system("Type", "block_diagram"));
models = models(:);
end

function throwCleanupExceptions(identifier, message, exceptions)
if isempty(exceptions)
    return
end
combined = MException(identifier, message);
for index = 1:numel(exceptions)
    combined = addCause(combined, exceptions{index});
end
throw(combined)
end

function closeIfLoaded(model)
if strlength(string(model)) > 0 && bdIsLoaded(model)
    close_system(model, 0);
end
end

function matrix = syntheticMatrix(stopTime_s)
matrix = struct( ...
    "component", "synthetic", ...
    "stopTime", stopTime_s, ...
    "success", true, ...
    "tFinal", stopTime_s, ...
    "failureTime_s", NaN, ...
    "errorId", "", ...
    "errorReport", "", ...
    "warningIds", strings(0, 1));
end

function removeOwnedDirectory(directory)
if isfolder(directory)
    rmdir(directory, "s");
end
end

function model = uniqueTestModelName(prefix)
token = replace(string(char(java.util.UUID.randomUUID())), "-", "");
model = string(matlab.lang.makeValidName(prefix + extractBefore(token, 13)));
end

function restoreAndCloseSource(model, stopTime)
if bdIsLoaded(model)
    set_param(model, "StopTime", stopTime);
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
