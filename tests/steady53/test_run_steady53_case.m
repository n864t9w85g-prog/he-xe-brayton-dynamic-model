function tests = test_run_steady53_case
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
testCase.TestData.testFolder = fullfile(root, "tests", "steady53");
addpath(testCase.TestData.testFolder);

% start.m is a script whose variables must be visible to Simulink through
% the base workspace, not trapped in this function workspace.
evalin("base", "run(" + matlabString(fullfile(root, "start.m")) + ")");

testCase.TestData.fileGenConfig = Simulink.fileGenControl("getConfig");
testCase.TestData.fileGenRoot = string(tempname);
mkdir(testCase.TestData.fileGenRoot);
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(testCase.TestData.fileGenRoot, "cache"), ...
    "CodeGenFolder", fullfile(testCase.TestData.fileGenRoot, "codegen"), ...
    "createDir", true);
end

function teardownOnce(testCase)
if bdIsLoaded("final_steady_24a")
    close_system("final_steady_24a", 0);
end
cfg = testCase.TestData.fileGenConfig;
Simulink.fileGenControl("set", ...
    "CacheFolder", cfg.CacheFolder, ...
    "CodeGenFolder", cfg.CodeGenFolder, ...
    "createDir", true);
if isfolder(testCase.TestData.fileGenRoot)
    rmdir(testCase.TestData.fileGenRoot, "s");
end
rmpath(testCase.TestData.testFolder);
end

function testManifestResolvesCurrentModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
load_system(modelPath);
c = onCleanup(@() close_system("final_steady_24a", 0));

[manifest, ~] = steady53_signal_manifest("final_steady_24a");
verifyGreaterThan(testCase, numel(manifest), 0);
verifyEqual(testCase, numel(unique(string({manifest.name}))), ...
    numel(manifest));
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

function testShortRunDoesNotRewriteModel(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
before = sha256File(modelPath);
result = run_steady53_case(modelPath, 1, false);
after = sha256File(modelPath);

verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 1, "AbsTol", 1e-12);
verifyEqual(testCase, result.modelHashBefore, before);
verifyEqual(testCase, result.modelHashAfter, before);
verifyEqual(testCase, after, before);
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
