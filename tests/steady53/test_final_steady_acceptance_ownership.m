function tests = test_final_steady_acceptance_ownership
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = string(root);
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testAcceptanceEntryRejectsAndPreservesDirtyPreloadedModel(testCase)
model = "final_steady_24a";
modelPath = fullfile(testCase.TestData.root, model + ".slx");
verifyFalse(testCase, bdIsLoaded(model));
hashBefore = sha256File(modelPath);
load_system(modelPath);
cleanup = onCleanup(@() restoreAndClose(model));
set_param(model + "/TAC/Constant", "Value", "55091");
verifyEqual(testCase, string(get_param(model, "Dirty")), "on");

verifyError(testCase, @() run_final_steady_reachability( ...
    modelPath, 1, false), "steady53:ModelAlreadyLoaded");

verifyTrue(testCase, bdIsLoaded(model));
verifyEqual(testCase, string(get_param(model, "Dirty")), "on");
verifyEqual(testCase, string(get_param( ...
    model + "/TAC/Constant", "Value")), "55091");
verifyEqual(testCase, sha256File(modelPath), hashBefore);
clear cleanup
end

function restoreAndClose(model)
if bdIsLoaded(model)
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
