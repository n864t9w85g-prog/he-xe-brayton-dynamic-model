function tests = test_run_rotating_map_candidate_batch
%TEST_RUN_ROTATING_MAP_CANDIDATE_BATCH Fixed execution-budget contract.
tests = functiontests(localfunctions);
end

function testFixedCaseOrderAndStopTimes(testCase)
hooks = run_rotating_map_candidate_batch( ...
    "__rotating_map_test_hooks__", "", 500);
verifyWarningFree(testCase, @() hooks.validateStopTime(500));
verifyWarningFree(testCase, @() hooks.validateStopTime(14000));
verifyError(testCase, @() hooks.validateStopTime(501), ...
    "rotatingMap:UnsupportedStopTime");
verifyEqual(testCase, hooks.caseOrder, ["C0", "C1", "C2", "C3"]);
verifyEqual(testCase, hooks.runCallCountFor500Batch, 4);
verifyEqual(testCase, hooks.runCallCountFor14000Batch, 1);
end

function testSourceUsesTheApprovedRunnerExactlyOncePerCase(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
source = fileread(fullfile(repoRoot, "tests", ...
    "run_rotating_map_candidate_batch.m"));
verifyEqual(testCase, count(source, ...
    "run_steady53_case(candidateModelPath, stopTime, true)"), 1);
verifyFalse(testCase, contains(lower(source), "sim("));
verifyFalse(testCase, contains(lower(source), "save_system"));
end

