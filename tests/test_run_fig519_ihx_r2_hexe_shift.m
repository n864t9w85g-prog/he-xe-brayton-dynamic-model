function tests = test_run_fig519_ihx_r2_hexe_shift
%TEST_RUN_FIG519_IHX_R2_HEXE_SHIFT Zero-simulation A3 runner tests.
tests = functiontests(localfunctions);
end

function testHooksAreNoSimulationAndExclusive(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
originalFolder = string(pwd);
folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
cd(repoRoot);

expectedRunDir = fullfile(repoRoot, "tmp", ...
    "fig519_ihx_r2_hexe_20260901_A3");
verifyFalse(testCase, isfolder(expectedRunDir));
loadedBefore = string(find_system("type", "block_diagram"));

hooks = run_fig519_ihx_r2_hexe_shift("__a3_test_hooks__", pwd);
textStatus = hooks.testExclusiveTextCreation();
directoryStatus = hooks.testExclusiveDirectoryCreation();
failureStatus = hooks.testThrownCallArtifactTruthfulness();

verifyEqual(testCase, textStatus.simulation_call_count, 0);
verifyTrue(testCase, textStatus.overwrite_rejected);
verifyEqual(testCase, directoryStatus.simulation_call_count, 0);
verifyTrue(testCase, directoryStatus.second_claim_rejected);
verifyEqual(testCase, failureStatus.simulation_call_count, 0);
verifyFalse(testCase, failureStatus.run_steady53_case_returned);
verifyFalse(testCase, failureStatus.raw_result_present);
verifyFalse(testCase, failureStatus.candidate_curves_present);
verifyEqual(testCase, string(failureStatus.runner_exception_id), ...
    "fig519a3run:InjectedCallFailure");
verifyNotEmpty(testCase, failureStatus.runner_exception_report);
verifyFalse(testCase, any(ismember( ...
    string({failureStatus.artifacts.identity}), ...
    ["raw_result", "candidate_curves"])));
verifyTrue(testCase, failureStatus.all_artifact_locators_existed_at_write);
verifyEqual(testCase, string(find_system("type", "block_diagram")), loadedBefore);
verifyFalse(testCase, isfolder(expectedRunDir));
end
