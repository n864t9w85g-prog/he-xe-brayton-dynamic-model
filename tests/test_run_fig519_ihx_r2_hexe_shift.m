function tests = test_run_fig519_ihx_r2_hexe_shift
%TEST_RUN_FIG519_IHX_R2_HEXE_SHIFT Zero-simulation A3 runner tests.
tests = functiontests(localfunctions);
end

function testHooksAreNoSimulationAndExclusive(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
originalFolder = string(pwd);
folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
originalPath = string(path);
pathCleanup = onCleanup(@() path(char(originalPath))); %#ok<NASGU>
cd(repoRoot);
addpath(fullfile(repoRoot, "tests", "steady53"));

expectedRunDir = fullfile(repoRoot, "tmp", ...
    "fig519_ihx_r2_hexe_20260901_A3");
verifyFalse(testCase, isfolder(expectedRunDir));
loadedBefore = string(find_system("type", "block_diagram"));

hooks = run_fig519_ihx_r2_hexe_shift("__a3_test_hooks__", pwd);
textStatus = hooks.testExclusiveTextCreation();
directoryStatus = hooks.testExclusiveDirectoryCreation();
failureStatus = hooks.testThrownCallArtifactTruthfulness();
replacementKinds = ["run_dir", "candidate", "audit"];
replacementStatus = cell(size(replacementKinds));
for replacementIndex = 1:numel(replacementKinds)
    replacementStatus{replacementIndex} = ...
        hooks.testCallGateFiniteReplacement(replacementKinds(replacementIndex));
end
rawAttackKinds = ["existing_file", "symlink", "parent_replacement"];
rawAttackErrorIds = ["fig519a3run:OutputExists", ...
    "fig519a3run:OutputExists", "fig519a3run:PathIdentityChanged"];
rawAttackStatus = cell(size(rawAttackKinds));
for rawAttackIndex = 1:numel(rawAttackKinds)
    rawAttackStatus{rawAttackIndex} = ...
        hooks.testRawExclusivePublicationAttack(rawAttackKinds(rawAttackIndex));
end
auditNegativeStatus = hooks.testExactAuditNegativeValidation();
protectedStatus = hooks.testCapturedProtectedRecords();
helperKinds = ["run_steady53_case", "steady53_signal_manifest", ...
    "reset_steady53_property_warning_state"];
helperStatus = cell(size(helperKinds));
for helperIndex = 1:numel(helperKinds)
    helperStatus{helperIndex} = ...
        hooks.testCapturedHelperFiniteReplacement(helperKinds(helperIndex));
end
cleanupStatus = hooks.testHookCleanupInventoryDrift();

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
for replacementIndex = 1:numel(replacementStatus)
    verifyTrue(testCase, replacementStatus{replacementIndex}.rejected_before_call);
    verifyEqual(testCase, ...
        replacementStatus{replacementIndex}.simulation_call_count, 0);
    verifyNotEmpty(testCase, replacementStatus{replacementIndex}.error_id);
end
for rawAttackIndex = 1:numel(rawAttackStatus)
    verifyTrue(testCase, rawAttackStatus{rawAttackIndex}.overwrite_rejected);
    verifyTrue(testCase, rawAttackStatus{rawAttackIndex}.original_unchanged);
    verifyEqual(testCase, rawAttackStatus{rawAttackIndex}.simulation_call_count, 0);
    verifyEqual(testCase, string(rawAttackStatus{rawAttackIndex}.error_id), ...
        rawAttackErrorIds(rawAttackIndex));
end
verifyTrue(testCase, auditNegativeStatus.duplicate_rejected);
verifyTrue(testCase, auditNegativeStatus.missing_rejected);
verifyTrue(testCase, auditNegativeStatus.extra_rejected);
verifyTrue(testCase, auditNegativeStatus.changed_value_rejected);
verifyTrue(testCase, auditNegativeStatus.nan_state_rejected);
verifyTrue(testCase, auditNegativeStatus.inf_state_rejected);
verifyTrue(testCase, auditNegativeStatus.nonnumeric_state_rejected);
verifyTrue(testCase, auditNegativeStatus.duplicate_source_path_rejected);
verifyTrue(testCase, auditNegativeStatus.duplicate_candidate_path_rejected);
verifyTrue(testCase, auditNegativeStatus.symlink_ancestor_rejected);
verifyEqual(testCase, auditNegativeStatus.simulation_call_count, 0);
verifyTrue(testCase, protectedStatus.captured_empty_relative_passed);
verifyTrue(testCase, protectedStatus.tampered_path_rejected);
verifyTrue(testCase, protectedStatus.tampered_hash_rejected);
verifyEqual(testCase, protectedStatus.protected_record_count, 34);
verifyEqual(testCase, protectedStatus.simulation_call_count, 0);
for helperIndex = 1:numel(helperStatus)
    verifyTrue(testCase, helperStatus{helperIndex}.rejected_before_call);
    verifyEqual(testCase, helperStatus{helperIndex}.simulation_call_count, 0);
    verifyNotEmpty(testCase, helperStatus{helperIndex}.error_id);
end
verifyTrue(testCase, cleanupStatus.stable_inventory_cleaned);
verifyTrue(testCase, cleanupStatus.extra_inventory_retained);
verifyTrue(testCase, cleanupStatus.replaced_identity_retained);
verifyEqual(testCase, cleanupStatus.simulation_call_count, 0);
verifyEqual(testCase, string(find_system("type", "block_diagram")), loadedBefore);
verifyFalse(testCase, isfolder(expectedRunDir));
end
