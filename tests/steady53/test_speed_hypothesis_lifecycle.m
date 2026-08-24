function tests = test_speed_hypothesis_lifecycle
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

function testPromotedBaselineMarksTask5HistoricalAndAlreadyApplied(testCase)
status = steady53_speed_hypothesis_lifecycle();

verifyEqual(testCase, status.lifecycle, "historical_not_applicable");
verifyTrue(testCase, status.hypothesisAlreadyApplied);
verifyFalse(testCase, status.legacyRunnerApplicable);
verifyEqual(testCase, status.actualComponentSpeed_rpm, 55090, ...
    "AbsTol", 1);
verifyEqual(testCase, status.compressorDesignSpeed_rpm, 55090);
verifyEqual(testCase, status.normalizedCompressorSpeed, 1, ...
    "AbsTol", 16 * eps);
verifyTrue(testCase, status.compressorSpeedInRange);
verifyTrue(testCase, contains(status.message, ...
    "historical Task 5 hypothesis has already been applied", ...
    "IgnoreCase", true));
verifyEqual(testCase, status.modelHashBefore, status.modelHashAfter);
end

function testHistoricalTask5IsOutsideActiveDiscovery(testCase)
archive = fullfile(testCase.TestData.root, "docs", "archive", ...
    "steady53", "task5");
verifyTrue(testCase, isfile(fullfile(archive, ...
    "run_speed_hypothesis.m")));
verifyTrue(testCase, isfile(fullfile(archive, ...
    "historical_run_speed_hypothesis_tests.m")));
verifyFalse(testCase, isfile(fullfile(archive, ...
    "test_run_speed_hypothesis.m")));
verifyTrue(testCase, isfile(fullfile(archive, "README.md")));

active = fullfile(testCase.TestData.root, "tests", "steady53");
verifyFalse(testCase, isfile(fullfile(active, ...
    "run_speed_hypothesis.m")));
verifyFalse(testCase, isfile(fullfile(active, ...
    "test_run_speed_hypothesis.m")));
end
