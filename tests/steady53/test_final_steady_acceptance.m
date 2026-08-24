function tests = test_final_steady_acceptance
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
testCase.TestData.testFolder = fullfile(root, "tests", "steady53");
if bdIsLoaded("final_steady_24a")
    error("steady53:TestModelAlreadyLoaded", ...
        "Acceptance tests require final_steady_24a to be initially unloaded.");
end
testCase.TestData.originalPath = path;
addpath(testCase.TestData.testFolder);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testActualComponentSpeedIsPaperNominal(testCase)
model = "final_steady_24a";
modelPath = fullfile(testCase.TestData.root, model + ".slx");
wasLoaded = bdIsLoaded(model);
load_system(modelPath);
cleanup = onCleanup(@() closeTestOwnedModel(model, wasLoaded));

actual = str2double(get_param(model + "/TAC/Constant", "Value"));
compressorMap = load(fullfile(testCase.TestData.root, ...
    "hexe_compressor_lookup.mat"), "N_design", "speed_bp");
normalized = actual / compressorMap.N_design;

fprintf(1, ['TAC actual speed: %.15g rpm\n' ...
    'Compressor N_design: %.15g rpm\n' ...
    'Normalized compressor speed: %.15g\n' ...
    'Compressor speed breakpoint range: [%.15g, %.15g]\n'], ...
    actual, compressorMap.N_design, normalized, ...
    min(compressorMap.speed_bp), max(compressorMap.speed_bp));

verifyEqual(testCase, actual, 55090, "AbsTol", 1);
verifyGreaterThanOrEqual(testCase, normalized, ...
    min(compressorMap.speed_bp));
verifyLessThanOrEqual(testCase, normalized, ...
    max(compressorMap.speed_bp));
end

function testModelReaches14000WithoutPropertyOrSolverFailure(testCase)
model = "final_steady_24a";
if bdIsLoaded(model)
    close_system(model, 0);
end
modelPath = fullfile(testCase.TestData.root, model + ".slx");
result = run_steady53_case(modelPath, 14000, false);

fprintf(1, ['14000 s run success: %d\n' ...
    'tFinal_s: %.17g\n' ...
    'errorId: %s\n' ...
    'warningIds: %s\n' ...
    'errorReport follows:\n%s\n'], ...
    result.success, result.tFinal_s, result.errorId, ...
    strjoin(result.warningIds, ", "), result.errorReport);

verifyTrue(testCase, result.success, result.errorReport);
verifyEqual(testCase, result.tFinal_s, 14000, "AbsTol", 1e-9);
verifyEmpty(testCase, result.warningIds);
end

function closeTestOwnedModel(model, wasLoaded)
if ~wasLoaded && bdIsLoaded(model)
    close_system(model, 0);
end
end
