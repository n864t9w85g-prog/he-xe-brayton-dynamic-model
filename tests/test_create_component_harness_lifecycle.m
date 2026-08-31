function tests = test_create_component_harness_lifecycle
tests = functiontests(localfunctions);
end

function testSuccessfulCreationRestoresPathAndPreservesSource(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
beforePath = path;
beforeHash = sha256File(sourcePath);

harness = create_component_harness("reactor");
cleanup = onCleanup(@() closeHarness(harness)); %#ok<NASGU>
verifyTrue(testCase, startsWith(harness.path, fullfile(repo, "tmp") + filesep));
verifyTrue(testCase, isfile(harness.path));
verifyEqual(testCase, harness.sourcePath, sourcePath);
close_system(harness.model, 0);
clear cleanup

verifyEqual(testCase, path, beforePath);
verifyEqual(testCase, sha256File(sourcePath), beforeHash);
end

function testFailedCreationRestoresPathAndCreatesNoFormalOutput(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
beforePath = path;
beforeHash = sha256File(sourcePath);
formalOutput = fullfile(repo, "final_dynamic_24a.slx");
formalOutputExisted = isfile(formalOutput);
if formalOutputExisted
    formalOutputHash = sha256File(formalOutput);
end

verifyError(testCase, @() create_component_harness("not_a_component"), ...
    "steady53:UnknownComponent");
verifyEqual(testCase, path, beforePath);
verifyEqual(testCase, sha256File(sourcePath), beforeHash);
verifyEqual(testCase, isfile(formalOutput), formalOutputExisted);
if formalOutputExisted
    verifyEqual(testCase, sha256File(formalOutput), formalOutputHash);
end
end

function closeHarness(harness)
if isfield(harness, "model") && bdIsLoaded(harness.model)
    close_system(harness.model, 0);
end
if isfield(harness, "runDir") && isfolder(harness.runDir)
    rmdir(harness.runDir, "s");
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, "Could not hash %s: %s", filePath, output);
hash = string(split(strtrim(output)));
hash = hash(1);
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
