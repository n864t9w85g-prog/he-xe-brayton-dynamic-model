function tests = test_run_steady53_case
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
testCase.TestData.testFolder = fullfile(root, "tests", "steady53");
if bdIsLoaded("final_steady_24a")
    error("steady53:TestModelAlreadyLoaded", ...
        "Task 3 tests require final_steady_24a to be initially unloaded.");
end
testCase.TestData.originalPath = path;
addpath(testCase.TestData.testFolder);

testCase.TestData.fileGenConfig = Simulink.fileGenControl("getConfig");
testCase.TestData.fileGenRoot = string(tempname);
mkdir(testCase.TestData.fileGenRoot);
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(testCase.TestData.fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(testCase.TestData.fileGenRoot, "codegen"), ...
    "createDir", true);
end

function teardownOnce(testCase)
cfg = testCase.TestData.fileGenConfig;
Simulink.fileGenControl("set", ...
    "CacheFolder", cfg.CacheFolder, ...
    "CodeGenFolder", cfg.CodeGenFolder, ...
    "createDir", true);
if isfolder(testCase.TestData.fileGenRoot)
    rmdir(testCase.TestData.fileGenRoot, "s");
end
path(testCase.TestData.originalPath);
end

function testManifestResolvesCurrentModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));

[manifest, ~] = steady53_signal_manifest("final_steady_24a");
verifyGreaterThan(testCase, numel(manifest), 0);
verifyEqual(testCase, numel(unique(string({manifest.name}))), ...
    numel(manifest));
verifyTrue(testCase, all(isfield(manifest, ...
    ["name", "block", "port", "fluid", "constant"])));
expectedConstants = sort(["rotor_speed"; "lithium_mdot_reactor"; ...
    "lithium_mdot_ihx"; "compressor_lookup_speed_eff"; ...
    "compressor_lookup_speed_pr"; "turbine_lookup_speed_flow"; ...
    "turbine_lookup_speed_eff"]);
verifyEqual(testCase, sort(string({manifest([manifest.constant]).name}).'), ...
    expectedConstants);
for index = 1:numel(manifest)
    verifyNotEqual(testCase, ...
        getSimulinkBlockHandle(manifest(index).block), -1, ...
        "Missing manifest block: " + manifest(index).block);
    ports = get_param(manifest(index).block, "PortHandles");
    verifyGreaterThanOrEqual(testCase, numel(ports.Outport), ...
        manifest(index).port, ...
        "Invalid output port for " + manifest(index).name);
end
clear c
end

function testStateManifestCoversEveryIntegratorExactlyOnce(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));

[~, stateMeta] = steady53_signal_manifest("final_steady_24a");
actual = string(find_system("final_steady_24a", ...
    "LookUnderMasks", "all", "FollowLinks", "on", ...
    "BlockType", "Integrator"));
listed = string({stateMeta.path}).';

verifyEqual(testCase, numel(listed), numel(actual));
verifyEqual(testCase, numel(unique(listed)), numel(listed));
verifyEqual(testCase, sort(listed), sort(actual));
verifyTrue(testCase, all(isfield(stateMeta, ...
    ["path", "fluid", "kind", "signPolicy"])));
verifyTrue(testCase, all(ismember(string({stateMeta.fluid}), ...
    ["HeXe", "Lithium", "none"])));
verifyTrue(testCase, all(ismember(string({stateMeta.kind}), ...
    ["temperature", "pressure", "power", "massFlow", ...
     "speed", "dimensionless", "other"])));
verifyTrue(testCase, all(ismember(string({stateMeta.signPolicy}), ...
    ["positive", "nonnegative", "signed"])));
clear c
end

function testCriticalStateSemanticsAreExplicit(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));
[~, stateMeta] = steady53_signal_manifest("final_steady_24a");

verifyState(testCase, stateMeta, ...
    "final_steady_24a/TAC/rotor/N_rpm_Integrator", ...
    "none", "speed", "nonnegative");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/reactor/Integrator6", ...
    "none", "power", "nonnegative");

for suffix = ["Integrator", "Integrator1", "Integrator2", ...
        "Integrator3", "Integrator4", "Integrator5"]
    verifyState(testCase, stateMeta, ...
        "final_steady_24a/reactor/" + suffix, ...
        "none", "other", "nonnegative");
end

verifyState(testCase, stateMeta, ...
    "final_steady_24a/reactor/Integrator7", ...
    "none", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/IHX/IHX_region_1/T_c1_average_Integrator", ...
    "HeXe", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/IHX/IHX_region_1/T_h1_average_Integrator", ...
    "Lithium", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/IHX/IHX_region_1/T_wall_Integrator", ...
    "none", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/precooler/precooler_1/T_h1_average_Integrator", ...
    "HeXe", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/precooler/precooler_1/T_c1_average_Integrator", ...
    "none", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/recuperator/MannRegion_1/T_c1_average_Integrator", ...
    "HeXe", "temperature", "positive");
verifyState(testCase, stateMeta, ...
    "final_steady_24a/rediator/T_rad_Integrator", ...
    "none", "temperature", "positive");
clear c
end

function testCriticalManifestConnectionsMatchCurrentTopology(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));
[manifest, ~] = steady53_signal_manifest("final_steady_24a");

powerLine = get_param( ...
    "final_steady_24a/reactor/P_sw", "LineHandles");
verifyEqual(testCase, string(getfullname(get_param( ...
    powerLine.Inport, "SrcBlockHandle"))), ...
    "final_steady_24a/reactor/Integrator6");

verifyManifestRow(testCase, manifest, "rotor_speed", ...
    "final_steady_24a/TAC/Constant", 1);
rotorPorts = get_param("final_steady_24a/TAC/Constant", "PortHandles");
rotorLine = get_param(rotorPorts.Outport(1), "Line");
rotorDestinations = string(getfullname( ...
    get_param(rotorLine, "DstBlockHandle")));
verifyTrue(testCase, any(rotorDestinations == ...
    "final_steady_24a/TAC/Turbine"));
verifyTrue(testCase, any(rotorDestinations == ...
    "final_steady_24a/TAC/Compressor"));

verifyManifestRow(testCase, manifest, "turbine_power", ...
    "final_steady_24a/TAC/Turbine", 4);
verifyManifestRow(testCase, manifest, "compressor_power", ...
    "final_steady_24a/TAC/Compressor", 2);
verifyOutportSource(testCase, ...
    "final_steady_24a/TAC/Turbine/WT", ...
    "final_steady_24a/TAC/Turbine/Product4");
verifyOutportSource(testCase, ...
    "final_steady_24a/TAC/Compressor/W_c", ...
    "final_steady_24a/TAC/Compressor/Product4");

compressorEfficiency = "final_steady_24a/TAC/Compressor/2-D Lookup" + ...
    newline + "Table1";
compressorPressureRatio = ...
    "final_steady_24a/TAC/Compressor/2-D Lookup" + newline + "Table3";
turbineFlow = "final_steady_24a/TAC/Turbine/2-D Lookup" + ...
    newline + "Table";
turbineEfficiency = "final_steady_24a/TAC/Turbine/2-D Lookup" + ...
    newline + "Table1";
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Compressor/Gain2", compressorEfficiency, 1);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Compressor/Gain4", compressorEfficiency, 2);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Compressor/Gain1", compressorPressureRatio, 1);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Compressor/Gain3", compressorPressureRatio, 2);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Turbine/Product2", turbineFlow, 1);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Turbine/From2", turbineFlow, 2);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Turbine/From24", turbineEfficiency, 1);
verifyFeedsPort(testCase, ...
    "final_steady_24a/TAC/Turbine/From3", turbineEfficiency, 2);
clear c
end

function testShortRunDoesNotRewriteModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
before = sha256File(modelPath);
environmentBefore = environmentSnapshot();
baseGuard = preserveBaseVariables(["N_design", "paper54"]); %#ok<NASGU>
assignin("base", "N_design", -123);
evalin("base", "clear paper54");
baseNamesBefore = baseWorkspaceNames();
result = run_steady53_case(modelPath, 1, false);
after = sha256File(modelPath);

verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 1, "AbsTol", 1e-12);
verifyEqual(testCase, result.modelHashBefore, before);
verifyEqual(testCase, result.modelHashAfter, before);
verifyEqual(testCase, after, before);
verifyEqual(testCase, evalin("base", "N_design"), -123);
verifyEqual(testCase, evalin("base", "exist('paper54','var')"), 0);
verifyEqual(testCase, baseWorkspaceNames(), baseNamesBefore);
verifyEnvironmentRestored(testCase, environmentBefore);
verifyFalse(testCase, isfolder(result.fileGenRoot));
verifyFalse(testCase, bdIsLoaded("final_steady_24a"));
clear baseGuard
end

function testShortLoggedRunReturnsManifestAndStates(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
result = run_steady53_case(modelPath, 1, true);

verifyTrue(testCase, result.success, result.errorReport);
requiredSignals = [steady53_spec().metrics.name; ...
    "hexe_mdot_turbine"; "hexe_mdot_compressor"; ...
    "hexe_mdot_ihx"; "hexe_mdot_recup_hot"; ...
    "hexe_mdot_recup_cold"; "lithium_mdot_reactor"; ...
    "lithium_mdot_ihx"; "turbine_expansion_ratio"; ...
    "compressor_lookup_speed_eff"; "compressor_lookup_flow_eff"; ...
    "compressor_lookup_speed_pr"; "compressor_lookup_flow_pr"; ...
    "turbine_lookup_expansion_ratio"; "turbine_lookup_speed_flow"; ...
    "turbine_lookup_mass_flow"; "turbine_lookup_speed_eff"];
verifyTrue(testCase, all(isfield(result.signals, requiredSignals)));

load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));
[~, stateMeta] = steady53_signal_manifest("final_steady_24a");
verifyEqual(testCase, numel(result.states), numel(stateMeta));
verifyTrue(testCase, all(isfield(result.states, ...
    ["path", "fluid", "data", "kind", "signPolicy"])));
for index = 1:numel(result.states)
    verifyEqual(testCase, numel(result.states(index).data), ...
        numel(result.t), "State length mismatch: " + ...
        result.states(index).path);
end
clear c
end

function testPreloadedDirtyModelIsRejectedWithoutMutation(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() closeOwnedModel("final_steady_24a"));
set_param("final_steady_24a", "StopTime", "123.456");
verifyEqual(testCase, string(get_param( ...
    "final_steady_24a", "Dirty")), "on");
environmentBefore = environmentSnapshot();

verifyError(testCase, @() run_steady53_case(modelPath, 1, false), ...
    "steady53:ModelAlreadyLoaded");

verifyTrue(testCase, bdIsLoaded("final_steady_24a"));
verifyEqual(testCase, string(get_param( ...
    "final_steady_24a", "Dirty")), "on");
verifyEqual(testCase, string(get_param( ...
    "final_steady_24a", "StopTime")), ...
    "123.456");
verifyEnvironmentRestored(testCase, environmentBefore);
clear c
end

function testInjectedFailureRestoresEveryExternalState(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
beforeHash = sha256File(modelPath);
environmentBefore = environmentSnapshot();
baseGuard = preserveBaseVariables(["N_design", "paper54"]); %#ok<NASGU>
assignin("base", "N_design", -123);
evalin("base", "clear paper54");
baseNamesBefore = baseWorkspaceNames();

control = struct("injectSimulationFailure", true);
result = run_steady53_case(modelPath, 180, false, control);

verifyFalse(testCase, result.success);
verifyEqual(testCase, result.errorId, ...
    "Simulink:Commands:SimInputPrePostFcnError");
verifySubstring(testCase, result.errorReport, ...
    "Controlled in-memory failure");
verifyNotEmpty(testCase, result.errorReport);
verifyEqual(testCase, result.modelHashBefore, beforeHash);
verifyEqual(testCase, result.modelHashAfter, beforeHash);
verifyEqual(testCase, sha256File(modelPath), beforeHash);
verifyEqual(testCase, evalin("base", "N_design"), -123);
verifyEqual(testCase, evalin("base", "exist('paper54','var')"), 0);
verifyEqual(testCase, baseWorkspaceNames(), baseNamesBefore);
verifyEnvironmentRestored(testCase, environmentBefore);
verifyFalse(testCase, isfolder(result.fileGenRoot));
verifyFalse(testCase, bdIsLoaded("final_steady_24a"));
clear baseGuard
end

function testAlignSeriesContracts(testCase)
hooks = steady53TestHooks();
align = hooks.alignSeries;

duplicateSeries = [0 1; 0 2; 1 3];
verifyEqual(testCase, align(duplicateSeries, [0; 0.5; 1], ...
    "duplicate", false), [2; 2.5; 3], "AbsTol", eps);
verifyError(testCase, @() align([0 1; 0.75 2; 0.5 3], ...
    [0; 0.5], "backtrack", false), "steady53:InvalidSeriesTime");
verifyError(testCase, @() align([0 1 9; 1 2 9], ...
    [0; 1], "three_columns", false), "steady53:UnsupportedSeries");
verifyError(testCase, @() align([0 7], [0; 1], ...
    "singleton", false), "steady53:SingletonNonConstant");
verifyEqual(testCase, align([0 7], [0; 0.5; 1], ...
    "constant", true), repmat(7, 3, 1));
verifyError(testCase, @() align([0.25 7], [0; 1], ...
    "late_constant", true), "steady53:IncompleteSeriesCoverage");

edgeTolerance = 8 * eps(1);
withinTolerance = [edgeTolerance 1; 1-edgeTolerance 2];
aligned = align(withinTolerance, [0; 0.5; 1], ...
    "endpoint_tolerance", false);
verifyEqual(testCase, aligned([1 end]), [1; 2], "AbsTol", eps);
verifyError(testCase, @() align([1e-6 1; 1-1e-6 2], ...
    [0; 1], "coverage_gap", false), ...
    "steady53:IncompleteSeriesCoverage");
end

function testSimulationTimeContract(testCase)
hooks = steady53TestHooks();
hooks.validateSimulationTime([0; 0.5; 1], 1);
verifyError(testCase, @() hooks.validateSimulationTime( ...
    [0; 0.5], 1), "steady53:IncompleteSimulation");
verifyError(testCase, @() hooks.validateSimulationTime( ...
    [0; 0.5; 0.5; 1], 1), "steady53:InvalidSimulationTime");
verifyError(testCase, @() hooks.validateSimulationTime( ...
    [eps; 0.5; 1], 1), "steady53:InvalidSimulationTime");
end

function testPropertyWarningIdsAreCollectedThroughCauses(testCase)
hooks = steady53TestHooks();
inner = MException("HeXe:T_hi", "property warning");
middle = MException("steady53:middle", "middle");
middle = addCause(middle, inner);
outer = MException("steady53:outer", "outer");
outer = addCause(outer, middle);
outer = addCause(outer, MException( ...
    "Lithium_property_simulink:TemperatureAboveRange", ...
    "lithium property warning"));

verifyEqual(testCase, hooks.propertyWarningIds(outer), ...
    ["HeXe:T_hi"; ...
     "Lithium_property_simulink:TemperatureAboveRange"]);
end

function verifyState(testCase, stateMeta, path, fluid, kind, signPolicy)
row = string({stateMeta.path}) == path;
verifyEqual(testCase, nnz(row), 1, "Missing or duplicate state: " + path);
if nnz(row) ~= 1
    return
end
verifyEqual(testCase, string(stateMeta(row).fluid), fluid);
verifyEqual(testCase, string(stateMeta(row).kind), kind);
verifyEqual(testCase, string(stateMeta(row).signPolicy), signPolicy);
end

function verifyManifestRow(testCase, manifest, name, block, port)
row = string({manifest.name}) == name;
verifyEqual(testCase, nnz(row), 1, "Missing manifest signal: " + name);
if nnz(row) ~= 1
    return
end
verifyEqual(testCase, string(manifest(row).block), block);
verifyEqual(testCase, manifest(row).port, port);
end

function verifyOutportSource(testCase, outportBlock, expectedSource)
ports = get_param(outportBlock, "PortHandles");
line = get_param(ports.Inport(1), "Line");
source = get_param(line, "SrcBlockHandle");
verifyEqual(testCase, string(getfullname(source)), expectedSource);
end

function verifyFeedsPort(testCase, sourceBlock, destinationBlock, port)
sourcePorts = get_param(sourceBlock, "PortHandles");
line = get_param(sourcePorts.Outport(1), "Line");
actualDestinationPorts = get_param(line, "DstPortHandle");
destinationPorts = get_param(destinationBlock, "PortHandles");
verifyTrue(testCase, any(actualDestinationPorts == ...
    destinationPorts.Inport(port)), ...
    sourceBlock + " does not feed port " + port + " of " + ...
    destinationBlock);
end

function snapshot = environmentSnapshot()
config = Simulink.fileGenControl("getConfig");
snapshot = struct( ...
    "path", string(path), ...
    "cacheFolder", string(config.CacheFolder), ...
    "codeGenFolder", string(config.CodeGenFolder), ...
    "warningStates", warningStates());
end

function verifyEnvironmentRestored(testCase, expected)
actual = environmentSnapshot();
verifyEqual(testCase, actual.path, expected.path);
verifyEqual(testCase, actual.cacheFolder, expected.cacheFolder);
verifyEqual(testCase, actual.codeGenFolder, expected.codeGenFolder);
verifyEqual(testCase, actual.warningStates, expected.warningStates);
end

function states = warningStates()
identifiers = propertyWarningIdentifiers();
states = strings(numel(identifiers), 1);
for index = 1:numel(identifiers)
    state = warning("query", identifiers(index));
    states(index) = string(state.state);
end
end

function identifiers = propertyWarningIdentifiers()
identifiers = ["HeXe:T_lo"; "HeXe:T_hi"; ...
    "Lithium_property_simulink:TemperatureBelowRange"; ...
    "Lithium_property_simulink:TemperatureAboveRange"];
end

function guard = preserveBaseVariables(names)
names = string(names(:));
existed = false(size(names));
values = cell(size(names));
for index = 1:numel(names)
    existed(index) = evalin("base", ...
        "exist(" + matlabString(names(index)) + ", 'var') == 1");
    if existed(index)
        values{index} = evalin("base", names(index));
    end
end
guard = onCleanup(@() restoreBaseVariables(names, existed, values));
end

function restoreBaseVariables(names, existed, values)
for index = 1:numel(names)
    if existed(index)
        assignin("base", names(index), values{index});
    else
        evalin("base", "clear " + names(index));
    end
end
end

function names = baseWorkspaceNames()
names = sort(string(evalin("base", "who")));
end

function hooks = steady53TestHooks()
hooks = run_steady53_case("__steady53_test_hooks__", 1, false);
end

function closeOwnedModel(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function h = sha256File(path)
[status, output] = system("shasum -a 256 " + shellQuote(path));
assert(status == 0, "Could not hash %s: %s", path, output);
parts = split(strtrim(output));
h = string(parts(1));
end

function q = shellQuote(value)
q = "'" + replace(string(value), "'", "'\\''") + "'";
end

function q = matlabString(value)
q = "'" + replace(string(value), "'", "''") + "'";
end
