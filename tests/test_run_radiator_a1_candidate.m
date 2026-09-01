function tests = test_run_radiator_a1_candidate
tests = functiontests(localfunctions);
end

function testCompletionGateRequiresExactStopAndFiniteData(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyTrue(testCase, hooks.completionGate([0; 250; 500], "", [1; 2; 3], 500));
verifyFalse(testCase, hooks.completionGate([0; 499.9], "", [1; 2], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "solver failed", [1; 2], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "", [1; Inf], 500));
verifyFalse(testCase, hooks.completionGate([0; 500], "", [1; 2+1i], 500));
end

function testStageContractAllowsOnly500And14000(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyWarningFree(testCase, @() hooks.validateStopTime(500));
verifyWarningFree(testCase, @() hooks.validateStopTime(14000));
verifyError(testCase, @() hooks.validateStopTime(501), ...
    'radiatorA1:UnsupportedStopTime');
end

function testLongStageMustReferenceSameCandidateHash(testCase)
hooks = run_radiator_a1_candidate("__test_hooks__", "", "", 500);
verifyTrue(testCase, hooks.sameCandidateHash("abc", "abc"));
verifyFalse(testCase, hooks.sameCandidateHash("abc", "def"));
end
