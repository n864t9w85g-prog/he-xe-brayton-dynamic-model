function status = run_fig519_ihx_r2_hexe_shift(runDir, repoRoot)
%RUN_FIG519_IHX_R2_HEXE_SHIFT Execute the consumed A3 500 s attempt once.
%   This exploration-only runner validates the A3 two-state/one-delta
%   candidate, claims a unique run directory, invokes the blocking steady53
%   case exactly once, and records only artifacts that actually exist.

arguments
    runDir {mustBeTextScalar}
    repoRoot {mustBeTextScalar}
end

if string(runDir) == "__a3_test_hooks__"
    hookRoot = validateRepoRoot(repoRoot);
    status = struct( ...
        "testExclusiveTextCreation", @() testExclusiveTextCreation(hookRoot), ...
        "testExclusiveDirectoryCreation", ...
            @() testExclusiveDirectoryCreation(hookRoot), ...
        "testThrownCallArtifactTruthfulness", ...
            @() testThrownCallArtifactTruthfulness(hookRoot), ...
        "testCallGateFiniteReplacement", ...
            @(kind) testCallGateFiniteReplacement(hookRoot, kind), ...
        "testRawExclusivePublicationAttack", ...
            @(kind) testRawExclusivePublicationAttack(hookRoot, kind), ...
        "testExactAuditNegativeValidation", ...
            @() testExactAuditNegativeValidation(hookRoot), ...
        "testCapturedProtectedRecords", ...
            @() testCapturedProtectedRecords(hookRoot), ...
        "testCapturedHelperFiniteReplacement", ...
            @(kind) testCapturedHelperFiniteReplacement(hookRoot, kind), ...
        "testHookCleanupInventoryDrift", ...
            @() testHookCleanupInventoryDrift(hookRoot));
    return
end

repoRoot = validateRepoRoot(repoRoot);
runDir = validateExistingRunDirectory(runDir, fullfile(repoRoot, "tmp"));
[~, runName] = fileparts(runDir);
if string(runName) ~= "fig519_ihx_r2_hexe_20260901_A3"
    error("fig519a3run:RunNameMismatch", ...
        "The A3 run directory must use the frozen attempt name.");
end

candidatePath = fullfile(runDir, "candidate.slx");
auditPath = fullfile(runDir, "patch_audit.json");
sourcePath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
[invocationBinding, auditByteHash] = bindInvocationInputs( ...
    runDir, candidatePath, auditPath, sourcePath, repoRoot);
assertInvocationBindings(invocationBinding, runDir, candidatePath, ...
    auditPath, sourcePath);
audit = jsondecode(fileread(auditPath));
candidateFrozenHash = string(audit.candidate_sha256);
assertInvocationHashes(invocationBinding, auditByteHash, ...
    candidateFrozenHash, auditPath, candidatePath, sourcePath);
validatePatchAuditIdentity(audit, candidatePath, sourcePath, repoRoot, ...
    invocationBinding);
referenceSeries(repoRoot);

runPath = fullfile(runDir, "run");
createDirectoryExclusive(runPath);
runIdentity = pathIdentity(runPath, "directory");
candidateIdentity = pathIdentity(candidatePath, "file");
auditIdentity = pathIdentity(auditPath, "file");
startedAt = isoTimestamp();
startRecord = struct( ...
    "experiment_schema", "steady53_fig519_ihx_r2_hexe_shift_started_v1", ...
    "attempt_id", "20260901_A3", ...
    "started_at_utc", startedAt, ...
    "approved_run_limit", 1, ...
    "run_steady53_case_call_count_at_start", 0, ...
    "retry_count", 0, ...
    "rerun_forbidden", true);
assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
    candidatePath, auditIdentity, auditPath);
assertInvocationBindings(invocationBinding, runDir, candidatePath, ...
    auditPath, sourcePath);
assertInvocationHashes(invocationBinding, auditByteHash, ...
    candidateFrozenHash, auditPath, candidatePath, sourcePath);
writeExclusiveText(fullfile(runPath, "experiment_started.json"), ...
    string(jsonencode(startRecord, PrettyPrint=true)) + newline);
assertInvocationBindings(invocationBinding, runDir, candidatePath, ...
    auditPath, sourcePath);
assertInvocationHashes(invocationBinding, auditByteHash, ...
    candidateFrozenHash, auditPath, candidatePath, sourcePath);

identityBefore = identitySnapshot(audit, sourcePath, candidatePath, repoRoot);
runResult = struct();
callReturned = false;
runnerException = [];
rawWritten = false;
candidateCurvesWritten = false;
referenceCurvesWritten = false;

disp("BEGIN_A3_500")
assertInvocationBindings(invocationBinding, runDir, candidatePath, ...
    auditPath, sourcePath);
assertInvocationHashes(invocationBinding, auditByteHash, ...
    candidateFrozenHash, auditPath, candidatePath, sourcePath);
try
    runResult = run_steady53_case(candidatePath, 500, true);
    callReturned = true;
catch exception
    runnerException = exception;
    runResult = thrownCallResult(exception);
end
try
    assertInvocationBindings(invocationBinding, runDir, candidatePath, ...
        auditPath, sourcePath);
    assertInvocationHashes(invocationBinding, auditByteHash, ...
        candidateFrozenHash, auditPath, candidatePath, sourcePath);
catch exception
    runnerException = appendException(runnerException, exception);
end

rawPath = fullfile(runPath, "raw_result.mat");
candidateCsv = fullfile(runPath, "candidate_curves.csv");
referenceCsv = fullfile(runPath, "reference_curves.csv");
[rawWritten, candidateCurvesWritten, runnerException] = ...
    persistReturnedCallArtifacts(runPath, runResult, callReturned, ...
        rawPath, candidateCsv, runnerException, runIdentity, ...
        @() assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
            candidatePath, auditIdentity, auditPath));
try
    writeReferenceCurves(referenceCsv, repoRoot);
    referenceCurvesWritten = true;
catch exception
    runnerException = appendException(runnerException, exception);
end

try
    identityAfter = identitySnapshot(audit, sourcePath, candidatePath, repoRoot);
    identityUnchanged = isequal(identityBefore, identityAfter);
    if ~identityUnchanged
        runnerException = appendException(runnerException, MException( ...
            "fig519a3run:IdentityChanged", ...
            "Candidate, source, runtime, protected, or formal identity changed."));
    end
catch exception
    identityAfter = struct();
    identityUnchanged = false;
    runnerException = appendException(runnerException, exception);
end

if ~isempty(runnerException) || ~identityUnchanged
    experimentStatus = "runner_or_hash_gate_failed";
elseif ~logicalField(runResult, "success")
    experimentStatus = "completed_model_failure";
elseif ~rawWritten || ~candidateCurvesWritten || ...
        ~referenceCurvesWritten || finiteOrNull(runResult.tFinal_s) ~= 500
    experimentStatus = "completed_incomplete_output";
else
    experimentStatus = "completed_success";
end

artifacts = artifactRecords(runDir, candidatePath, auditPath, ...
    rawPath, candidateCsv, referenceCsv);
status = buildRunStatus(experimentStatus, startedAt, runResult, ...
    callReturned, runnerException, identityUnchanged, identityBefore, identityAfter, ...
    artifacts);
assertSameIdentity(runIdentity, runPath, "run directory");
writeExclusiveText(fullfile(runPath, "run_status.json"), ...
    string(jsonencode(status, PrettyPrint=true)) + newline);
end

function validatePatchAuditIdentity(audit, candidatePath, sourcePath, repoRoot, ...
        invocationBinding)
expectedSource = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
requiredText = struct( ...
    "patch_schema", "steady53_fig519_ihx_r2_hexe_shift_candidate_v1", ...
    "attempt_id", "20260901_A3", ...
    "candidate_value_identity", ...
        "figure_5_18a_t0_visual_proxy_not_author_initial_state");
names = string(fieldnames(requiredText));
for index = 1:numel(names)
    name = names(index);
    if ~isfield(audit, name) || string(audit.(name)) ~= requiredText.(name)
        error("fig519a3run:PatchAuditMismatch", ...
            "The patch audit field %s does not match A3.", name);
    end
end
if string(audit.source_sha256) ~= expectedSource || ...
        string(audit.source_sha256_after) ~= expectedSource || ...
        string(audit.source_model_sha256) ~= expectedSource || ...
        ~logical(audit.source_hash_unchanged) || ...
        sha256File(sourcePath) ~= expectedSource || ...
        sha256File(candidatePath) ~= string(audit.candidate_sha256)
    error("fig519a3run:PatchHashMismatch", ...
        "Source or candidate hash does not match the A3 patch audit.");
end
expectedSourceRelative = ...
    "data/provenance/baselines/f8bcd83/final_steady_24a.slx";
expectedCandidateRelative = ...
    "tmp/fig519_ihx_r2_hexe_20260901_A3/candidate.slx";
if string(audit.source_repository_relative_path) ~= expectedSourceRelative || ...
        string(audit.source_absolute_path) ~= canonicalPath(sourcePath) || ...
        string(audit.candidate_repository_relative_path) ~= ...
            expectedCandidateRelative || ...
        string(audit.candidate_absolute_path) ~= canonicalPath(candidatePath) || ...
        string(audit.publication_identity.run_directory_file_key) ~= ...
            invocationBinding.run_dir.file_key || ...
        string(audit.publication_identity.candidate_file_key) ~= ...
            invocationBinding.candidate.file_key || ...
        string(audit.publication_identity.audit_file_key) ~= ...
            invocationBinding.audit.file_key
    error("fig519a3run:PublicationIdentityMismatch", ...
        "Candidate/source paths or publication file keys do not match A3.");
end
if audit.paper_reproduced || audit.author_initial_state_identified || ...
        audit.formal_promotion || audit.changed_state_count ~= 2 || ...
        audit.unchanged_state_count ~= 38 || audit.state_count ~= 40 || ...
        audit.solver_parameter_count ~= 37 || ...
        audit.update_diagram_count ~= 1
    error("fig519a3run:PatchContractMismatch", ...
        "Patch count, update, or promotion contracts do not match A3.");
end
if abs(audit.anchor_K - 1200.0000000000000) > 1e-12 || ...
        abs(audit.delta_T_K - (-193.6037139151003)) > 1e-12 || ...
        abs(audit.old_gap_K - 147.7852469306997) > 1e-12 || ...
        abs(audit.new_gap_K - audit.old_gap_K) > 1e-12
    error("fig519a3run:SharedDeltaMismatch", ...
        "The common-delta and preserved-gap contract does not match A3.");
end
validateChangedStates(audit.changed_states);
validateStateInventory(audit.state_initial_conditions);
validateStateInventoryValues(audit.state_initial_conditions);
if ~audit.solver_contract.unchanged || ...
        audit.solver_contract.parameter_count ~= 37 || ...
        ~audit.semantic_snapshot.unchanged || ~audit.model_workspace.unchanged || ...
        numel(audit.runtime_dependencies) ~= 9 || ...
        numel(audit.protected_files) ~= 34
    error("fig519a3run:PatchInventoryIncomplete", ...
        "Patch solver, semantic, workspace, runtime, or protected audit is incomplete.");
end
if string(audit.protected_manifest_sha256) ~= ...
        "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"
    error("fig519a3run:ProtectedManifestIdentityMismatch", ...
        "The protected manifest SHA-256 does not match the fixed manifest.");
end
validateExactRuntimeSet(audit.runtime_dependencies, repoRoot);
validateExactProtectedSet(audit.protected_files, repoRoot);
validateExactFormalSet(audit.formal_files, repoRoot);
validateUnchangedRecords(audit.runtime_dependencies, repoRoot, ...
    "runtime dependency");
validateProtectedRecords(audit.protected_files, repoRoot);
validateFormalRecords(audit.formal_files, repoRoot);
end

function validateChangedStates(changed)
if numel(changed) ~= 2
    error("fig519a3run:ChangedStateShape", ...
        "Exactly two dependent state changes are required.");
end
expectedPaths = [ ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"];
expectedOld = [1245.8184669844006; 1393.6037139151003];
expectedNew = [1052.2147530693003; 1200.0000000000000];
[actualPaths, order] = sort(string({changed.path}).');
[expectedPaths, expectedOrder] = sort(expectedPaths);
if ~isequal(actualPaths, expectedPaths)
    error("fig519a3run:ChangedStatePathMismatch", ...
        "The changed state paths do not match A3.");
end
changed = changed(order);
expectedOld = expectedOld(expectedOrder);
expectedNew = expectedNew(expectedOrder);
for index = 1:2
    if abs(changed(index).old_initial_condition_K - expectedOld(index)) > 1e-12 || ...
            abs(changed(index).new_initial_condition_K - expectedNew(index)) > 1e-12 || ...
            abs(changed(index).delta_T_K - (-193.6037139151003)) > 1e-12
        error("fig519a3run:ChangedStateValueMismatch", ...
            "A changed state does not share the frozen A3 delta.");
    end
end
end

function validateStateInventory(states)
if numel(states) ~= 40 || sum([states.unchanged]) ~= 38
    error("fig519a3run:StateInventoryMismatch", ...
        "The audit must preserve exactly 38 of 40 state ICs.");
end
sourcePaths = string({states.source_path}).';
candidatePaths = string({states.candidate_path}).';
if numel(unique(sourcePaths)) ~= 40 || numel(unique(candidatePaths)) ~= 40
    error("fig519a3run:StateInventoryPathDuplicate", ...
        "All 40 source and candidate state paths must be unique.");
end
changed = states(~[states.unchanged]);
paths = sort(string({changed.source_path}).');
expected = sort([ ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"]);
if ~isequal(paths, expected)
    error("fig519a3run:StateInventoryPathMismatch", ...
        "The two changed inventory paths do not match A3.");
end
end

function validateStateInventoryValues(states)
for index = 1:numel(states)
    if states(index).unchanged && ...
            string(states(index).source_expression) ~= ...
            string(states(index).candidate_expression)
        error("fig519a3run:UnchangedStateValueMismatch", ...
            "An unchanged state has different source/candidate expressions.");
    end
end
expectedSource = [ ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator"];
expectedCandidate = [ ...
    "candidate/IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "candidate/IHX/IHX_region_2/T_c2_out_Integrator"];
expectedOld = [1245.8184669844006; 1393.6037139151003];
expectedNew = [1052.2147530693003; 1200.0000000000000];
for index = 1:2
    match = find(string({states.source_path}) == expectedSource(index));
    if numel(match) ~= 1
        error("fig519a3run:StateInventoryValueMismatch", ...
            "A target state inventory record is missing or duplicated.");
    end
    oldValue = finiteScalarStateExpression( ...
        states(match).source_expression, "source state expression");
    newValue = finiteScalarStateExpression( ...
        states(match).candidate_expression, "candidate state expression");
    if states(match).unchanged || ...
            string(states(match).candidate_path) ~= expectedCandidate(index) || ...
            abs(oldValue - expectedOld(index)) > 1e-12 || ...
            abs(newValue - expectedNew(index)) > 1e-12 || ...
            abs((newValue - oldValue) - ...
                (-193.6037139151003)) > 1e-12
        error("fig519a3run:StateInventoryValueMismatch", ...
            "A target state old/new value or candidate path differs from A3.");
    end
end
end

function value = finiteScalarStateExpression(expression, label)
text = string(expression);
if ~isscalar(text)
    error("fig519a3run:StateExpressionNotFiniteScalar", ...
        "%s must be a scalar finite numeric expression.", label);
end
value = str2double(text);
if ~isscalar(value) || ~isfinite(value)
    error("fig519a3run:StateExpressionNotFiniteScalar", ...
        "%s must be a scalar finite numeric expression.", label);
end
end

function validateExactRuntimeSet(records, repoRoot)
names = ["HeXe_property_simulink.m"; "Lithium_property_simulink.m"; ...
    "hexe_compressor_lookup.mat"; "radiator_table.mat"; ...
    "turbine_table1.mat"; "turbine_table2.mat"; "paper54_constants.m"; ...
    "sys_param_rad_fixed.m"; "start.m"];
relatives = "data/provenance/baselines/f8bcd83/runtime/" + names;
validateExactNameSet(string({records.name}).', names, "runtime dependency");
validateExactNameSet(string({records.repository_relative_path}).', ...
    relatives, "runtime repository-relative path");
for index = 1:numel(records)
    expected = resolveCapturedPath(repoRoot, ...
        string(records(index).repository_relative_path));
    if string(records(index).absolute_path) ~= canonicalPath(expected)
        error("fig519a3run:RuntimeAbsolutePathMismatch", ...
            "A runtime absolute path is not derived from the fixed allowlist.");
    end
end
end

function validateExactProtectedSet(records, repoRoot)
manifest = fixedProtectedManifest(repoRoot);
expectedNames = manifest.original_path;
validateExactNameSet(string({records.name}).', expectedNames, "protected name");
for index = 1:numel(records)
    row = find(manifest.original_path == string(records(index).name));
    if numel(row) ~= 1
        error("fig519a3run:ProtectedRecordMismatch", ...
            "A protected record name is absent from the fixed manifest.");
    end
    expectedPath = string(manifest.resolved_path(row));
    auditRelative = string(records(index).repository_relative_path);
    expectedRelative = relativeIfWithinRepo(expectedPath, repoRoot);
    if (~isempty(auditRelative) && ~isscalar(auditRelative)) || ...
            (strlength(auditRelative) > 0 && auditRelative ~= expectedRelative) || ...
            string(records(index).absolute_path) ~= canonicalPath(expectedPath) || ...
            string(records(index).before_sha256) ~= manifest.resolved_sha256(row) || ...
            string(records(index).after_sha256) ~= manifest.resolved_sha256(row) || ...
            ~logical(records(index).unchanged)
        error("fig519a3run:ProtectedRecordMismatch", ...
            "A protected record is not derived from the fixed manifest.");
    end
end
end

function validateProtectedRecords(records, repoRoot)
validateExactProtectedSet(records, repoRoot);
actual = recalcProtectedRecords(records, repoRoot);
manifest = fixedProtectedManifest(repoRoot);
for index = 1:numel(records)
    row = find(manifest.original_path == string(records(index).name));
    expectedHash = string(manifest.resolved_sha256(row));
    if actual(index).sha256 ~= expectedHash || ...
            string(records(index).before_sha256) ~= actual(index).sha256 || ...
            string(records(index).after_sha256) ~= actual(index).sha256
        error("fig519a3run:ProtectedIdentityMismatch", ...
            "A live read-only protected object differs from the fixed manifest.");
    end
end
end

function output = recalcProtectedRecords(records, repoRoot)
manifest = fixedProtectedManifest(repoRoot);
validateExactNameSet(string({records.name}).', manifest.original_path, ...
    "protected recalc name");
output = repmat(struct("name", "", "resolved_path", "", ...
    "sha256", "", "file_key", "", "device", "", "inode", ""), ...
    numel(records), 1);
for index = 1:numel(records)
    row = find(manifest.original_path == string(records(index).name));
    filePath = string(manifest.resolved_path(row));
    assertNoSymlinkAncestors(filePath, filesystemRoot(filePath));
    assertRegularFile(filePath, "manifest-resolved protected file");
    identity = pathIdentity(filePath, "file");
    currentHash = sha256File(filePath);
    if currentHash ~= string(manifest.resolved_sha256(row))
        error("fig519a3run:ProtectedManifestObjectChanged", ...
            "A manifest-resolved protected object changed: %s", filePath);
    end
    output(index) = struct("name", string(records(index).name), ...
        "resolved_path", canonicalPath(filePath), "sha256", currentHash, ...
        "file_key", identity.file_key, "device", identity.device, ...
        "inode", identity.inode);
end
end

function manifest = fixedProtectedManifest(repoRoot)
manifestPath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "protected_manifest_recovery.csv");
assertNoSymlinkAncestors(manifestPath, repoRoot);
assertRegularFile(manifestPath, "fixed protected manifest");
if sha256File(manifestPath) ~= ...
        "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"
    error("fig519a3run:ProtectedManifestHashMismatch", ...
        "The fixed protected manifest bytes changed.");
end
manifest = readtable(manifestPath, TextType="string", ...
    VariableNamingRule="preserve");
required = ["original_path", "resolved_path", "resolved_sha256"];
if height(manifest) ~= 34 || ...
        ~all(ismember(required, string(manifest.Properties.VariableNames)))
    error("fig519a3run:ProtectedManifestShape", ...
        "The fixed protected manifest must have 34 resolved rows.");
end
validateExactNameSet(manifest.original_path, unique(manifest.original_path), ...
    "protected manifest original path");
end

function root = filesystemRoot(pathValue)
root = lexicalAbsolute(pathValue);
while true
    parent = string(fileparts(root));
    if parent == root
        return
    end
    root = parent;
end
end

function validateExactFormalSet(records, repoRoot)
expected = ["final_steady_24a.slx"; "final_dynamic_24a.slx"; ...
    "HeXe_property_simulink.m"; "Lithium_property_simulink.m"; ...
    "hexe_compressor_lookup.mat"; "radiator_table.mat"; ...
    "turbine_table1.mat"; "turbine_table2.mat"];
validateExactNameSet(string({records.repository_relative_path}).', ...
    expected, "formal root path");
for index = 1:numel(records)
    filePath = fullfile(repoRoot, string(records(index).repository_relative_path));
    if string(records(index).absolute_path) ~= lexicalAbsolute(filePath)
        error("fig519a3run:FormalAbsolutePathMismatch", ...
            "A formal absolute path is not derived from the fixed allowlist.");
    end
end
end

function validateExactNameSet(actual, expected, label)
actual = string(actual(:));
expected = string(expected(:));
if numel(unique(actual)) ~= numel(actual) || ...
        numel(unique(expected)) ~= numel(expected) || ...
        ~isequal(sort(actual), sort(expected))
    error("fig519a3run:ExactSetMismatch", ...
        "%s set is duplicated, missing, or contains extras.", label);
end
end

function snapshot = identitySnapshot(audit, sourcePath, candidatePath, repoRoot)
snapshot = struct( ...
    "source_sha256", sha256File(sourcePath), ...
    "candidate_sha256", sha256File(candidatePath), ...
    "runtime_dependencies", recalcRecords(audit.runtime_dependencies, repoRoot), ...
    "protected_files", recalcProtectedRecords(audit.protected_files, repoRoot), ...
    "formal_files", recalcFormalRecords(audit.formal_files, repoRoot), ...
    "reference_curves", referenceIdentities(repoRoot));
end

function validateUnchangedRecords(records, repoRoot, label)
actual = recalcRecords(records, repoRoot);
for index = 1:numel(records)
    if ~logical(records(index).unchanged) || ...
            string(records(index).before_sha256) ~= actual(index).sha256 || ...
            string(records(index).after_sha256) ~= actual(index).sha256
        error("fig519a3run:IdentityContractMismatch", ...
            "%s differs from the candidate audit: %s", ...
            label, actual(index).repository_relative_path);
    end
end
end

function output = recalcRecords(records, repoRoot)
output = repmat(struct("repository_relative_path", "", "sha256", ""), ...
    numel(records), 1);
for index = 1:numel(records)
    relative = string(records(index).repository_relative_path);
    filePath = resolveCapturedPath(repoRoot, relative);
    assertRegularFile(filePath, "captured identity dependency");
    output(index) = struct("repository_relative_path", relative, ...
        "sha256", sha256File(filePath));
end
end

function validateFormalRecords(records, repoRoot)
actual = recalcFormalRecords(records, repoRoot);
for index = 1:numel(records)
    if ~logical(records(index).unchanged) || ...
            logical(records(index).exists_before) ~= actual(index).exists || ...
            logical(records(index).exists_after) ~= actual(index).exists || ...
            string(records(index).before_sha256) ~= actual(index).sha256 || ...
            string(records(index).after_sha256) ~= actual(index).sha256
        error("fig519a3run:FormalIdentityMismatch", ...
            "A formal root identity differs from the candidate audit.");
    end
end
end

function output = recalcFormalRecords(records, repoRoot)
output = repmat(struct("repository_relative_path", "", ...
    "exists", false, "sha256", ""), numel(records), 1);
for index = 1:numel(records)
    relative = string(records(index).repository_relative_path);
    filePath = resolveCapturedPath(repoRoot, relative);
    exists = isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath);
    hash = "";
    if exists
        assertRegularFile(filePath, "captured formal root file");
        hash = sha256File(filePath);
    end
    output(index) = struct("repository_relative_path", relative, ...
        "exists", exists, "sha256", hash);
end
end

function filePath = resolveCapturedPath(repoRoot, relative)
relative = replace(string(relative), "/", filesep);
if strlength(relative) == 0 || startsWith(relative, filesep) || ...
        any(split(relative, filesep) == "..")
    error("fig519a3run:CapturedPathInvalid", ...
        "Every executed dependency must use a captured repository-relative path.");
end
filePath = fullfile(repoRoot, relative);
if ~isContainedLexically(filePath, repoRoot)
    error("fig519a3run:CapturedPathOutsideRepo", ...
        "Captured dependency escaped repoRoot.");
end
assertNoSymlinkAncestors(filePath, repoRoot);
end

function writePowerAndStateCurves(filePath, result)
[time, reactor, turbine, compressor] = powerSeries(result);
average = stateSeries(result, ...
    "IHX/IHX_region_2/T_c1_average_Integrator", time);
outlet = stateSeries(result, ...
    "IHX/IHX_region_2/T_c2_out_Integrator", time);
content = "time_s,reactor_W,turbine_W,compressor_W,ihx_r2_average_K,ihx_r2_outlet_K\n" + ...
    string(sprintf("%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n", ...
        [time, reactor, turbine, compressor, average, outlet].'));
writeExclusiveText(filePath, content);
end

function writeReferenceCurves(filePath, repoRoot)
[time, reactor, turbine, compressor] = referenceSeries(repoRoot);
content = "time_s,reactor_W,turbine_W,compressor_W\n" + ...
    string(sprintf("%.17g,%.17g,%.17g,%.17g\n", ...
        [time, reactor, turbine, compressor].'));
writeExclusiveText(filePath, content);
end

function [time, reactor, turbine, compressor] = referenceSeries(repoRoot)
baselineDir = fullfile(repoRoot, "data", "provenance", "steady53", ...
    "fig5_19", "model_baseline");
names = ["baseline_P_sw.csv"; "baseline_WT_sw.csv"; "baseline_Wc_sw.csv"];
hashes = [ ...
    "288a9b031d31f8168517ea30d06f712d72c4d1dc31fd911f0a266aaa3023999f"; ...
    "28b852e9b997af51a860905e53da096821ddfbdd310857d16e9df0761ca2ab23"; ...
    "f44a9bca2c006780f287e4f3a7199f63d26348cc18ad261d4ad89570b0e9ad5c"];
series = cell(3, 1);
for index = 1:3
    filePath = fullfile(baselineDir, names(index));
    assertRegularFile(filePath, "captured model-baseline curve");
    if sha256File(filePath) ~= hashes(index)
        error("fig519a3run:ReferenceHashMismatch", ...
            "A fixed model-baseline curve is missing or changed: %s", names(index));
    end
    series{index} = readmatrix(filePath);
    if size(series{index}, 2) ~= 2
        error("fig519a3run:ReferenceShapeMismatch", ...
            "A fixed model-baseline curve must have two columns.");
    end
end
time = double(series{1}(:, 1));
reactor = double(series{1}(:, 2));
turbine = double(series{2}(:, 2));
compressor = double(series{3}(:, 2));
if ~isequal(time, double(series{2}(:, 1)), double(series{3}(:, 1)))
    error("fig519a3run:ReferenceTimeMismatch", ...
        "The three fixed model-baseline curves do not share one time vector.");
end
validateAlignedFinite(time, reactor, turbine, compressor);
end

function records = referenceIdentities(repoRoot)
baselineDir = fullfile(repoRoot, "data", "provenance", "steady53", ...
    "fig5_19", "model_baseline");
names = ["baseline_P_sw.csv"; "baseline_WT_sw.csv"; "baseline_Wc_sw.csv"];
records = repmat(struct("name", "", "sha256", ""), 3, 1);
for index = 1:3
    filePath = fullfile(baselineDir, names(index));
    records(index) = struct("name", names(index), "sha256", sha256File(filePath));
end
end

function [time, reactor, turbine, compressor] = powerSeries(result)
required = ["reactor_power", "turbine_power", "compressor_power"];
if ~isfield(result, "t") || ~isfield(result, "signals") || ...
        ~all(isfield(result.signals, required))
    error("fig519a3run:RunSignalsMissing", ...
        "runResult lacks one or more contracted power signals.");
end
time = double(result.t(:));
reactor = double(result.signals.reactor_power(:));
turbine = double(result.signals.turbine_power(:));
compressor = double(result.signals.compressor_power(:));
validateAlignedFinite(time, reactor, turbine, compressor);
end

function values = stateSeries(result, suffix, time)
if ~isfield(result, "states") || ~isstruct(result.states)
    error("fig519a3run:RunStatesMissing", ...
        "runResult lacks the contracted IHX state inventory.");
end
matches = endsWith(string({result.states.path}).', suffix);
if nnz(matches) ~= 1
    error("fig519a3run:RunStatePathMismatch", ...
        "Expected exactly one state ending in %s.", suffix);
end
values = double(result.states(matches).data(:));
if numel(values) ~= numel(time) || any(~isfinite(values))
    error("fig519a3run:RunStateInvalid", ...
        "IHX state data must be finite and aligned to runResult.t.");
end
end

function validateAlignedFinite(time, reactor, turbine, compressor)
if numel(time) < 2 || numel(reactor) ~= numel(time) || ...
        numel(turbine) ~= numel(time) || ...
        numel(compressor) ~= numel(time) || ...
        any(~isfinite([time; reactor; turbine; compressor])) || ...
        any(diff(time) <= 0)
    error("fig519a3run:RunSignalsInvalid", ...
        "Power curves must be finite and share a strictly increasing time vector.");
end
end

function saveRawExclusive(rawPath, runResult, runPath, expectedRunIdentity)
assertSameIdentity(expectedRunIdentity, runPath, "raw result parent");
stagingDir = fullfile(runPath, ".raw_" + string(java.util.UUID.randomUUID()));
createDirectoryExclusive(stagingDir);
stagingDirectoryIdentity = pathIdentity(stagingDir, "directory");
directoryCleanup = onCleanup(@() cleanupEmptyRawStaging( ...
    stagingDir, stagingDirectoryIdentity));
stagingPath = fullfile(stagingDir, "raw_result.mat");
save(stagingPath, "runResult", "-v7.3");
assertRegularFile(stagingPath, "staged raw result");
stagingIdentity = pathIdentity(stagingPath, "file");
clear directoryCleanup
stagingCleanup = onCleanup(@() cleanupKnownRawStaging( ...
    stagingDir, stagingDirectoryIdentity, stagingPath, stagingIdentity));
assertSameIdentity(expectedRunIdentity, runPath, "raw publication parent");
try
    java.nio.file.Files.createLink(nioPath(rawPath), nioPath(stagingPath), ...
        javaArray("java.nio.file.attribute.FileAttribute", 0));
catch exception
    if isfile(rawPath) || isfolder(rawPath) || isSymbolicLink(rawPath)
        error("fig519a3run:OutputExists", ...
            "Refusing to overwrite '%s'.", rawPath);
    end
    rethrow(exception)
end
publishedIdentity = pathIdentity(rawPath, "file");
assertSameIdentity(stagingIdentity, rawPath, "published raw hard link");
assertSameIdentity(expectedRunIdentity, runPath, "raw publication parent");
delete(stagingPath);
assertSameIdentity(publishedIdentity, rawPath, "published raw result");
cleanupEmptyRawStaging(stagingDir, stagingDirectoryIdentity);
clear stagingCleanup
end

function cleanupKnownRawStaging(stagingDir, expectedDirectoryIdentity, ...
        stagingPath, expectedFileIdentity)
cleanupKnownRawStagingFile(stagingPath, expectedFileIdentity);
cleanupEmptyRawStaging(stagingDir, expectedDirectoryIdentity);
end

function cleanupKnownRawStagingFile(stagingPath, expectedIdentity)
if ~isfile(stagingPath) || isSymbolicLink(stagingPath)
    return
end
try
    assertSameIdentity(expectedIdentity, stagingPath, "raw staging file");
    delete(stagingPath);
catch
    % Preserve unexpected or replaced paths as evidence.
end
end

function cleanupEmptyRawStaging(stagingDir, expectedIdentity)
if ~isfolder(stagingDir) || isSymbolicLink(stagingDir)
    return
end
try
    assertSameIdentity(expectedIdentity, stagingDir, "raw staging directory");
    listing = dir(stagingDir);
    names = string({listing.name});
    if ~any(~ismember(names, [".", ".."]))
        rmdir(stagingDir);
    end
catch
    % Preserve unexpected or replaced paths as evidence; never recurse.
end
end

function records = artifactRecords(runDir, candidatePath, auditPath, ...
        rawPath, candidateCsv, referenceCsv)
paths = [string(candidatePath); string(auditPath); string(rawPath); ...
    string(candidateCsv); string(referenceCsv)];
identities = ["candidate_slx"; "patch_audit"; "raw_result"; ...
    "candidate_curves"; "reference_curves"];
present = false(size(paths));
for index = 1:numel(paths)
    present(index) = isfile(paths(index)) && ~isSymbolicLink(paths(index));
end
paths = paths(present);
identities = identities(present);
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
records = repmat(struct("identity", "", ...
    "repository_relative_path", "", "absolute_path", "", ...
    "sha256", "", "bytes", 0, "storage", "external_tmp_not_copied"), ...
    numel(paths), 1);
for index = 1:numel(paths)
    assertRegularFile(paths(index), "actual run artifact");
    info = dir(paths(index));
    records(index) = struct("identity", identities(index), ...
        "repository_relative_path", relativeIfWithinRepo(paths(index), repoRoot), ...
        "absolute_path", canonicalPath(paths(index)), ...
        "sha256", sha256File(paths(index)), "bytes", info.bytes, ...
        "storage", "external_tmp_not_copied");
end
if ~isContainedLexically(runDir, fileparts(runDir))
    error("fig519a3run:RunContainmentLost", "Run containment changed.");
end
end

function [rawWritten, curvesWritten, runnerException] = ...
        persistReturnedCallArtifacts(runPath, runResult, callReturned, ...
        rawPath, candidateCsv, runnerException, runIdentity, identityGate)
rawWritten = false;
curvesWritten = false;
if ~callReturned
    return
end
try
    identityGate();
    saveRawExclusive(rawPath, runResult, runPath, runIdentity);
    rawWritten = true;
catch exception
    runnerException = appendException(runnerException, exception);
end
if logicalField(runResult, "success")
    try
        writePowerAndStateCurves(candidateCsv, runResult);
        curvesWritten = true;
    catch exception
        runnerException = appendException(runnerException, exception);
    end
end
end

function result = thrownCallResult(exception)
result = struct("success", false, ...
    "errorId", string(exception.identifier), ...
    "errorReport", string(getReport( ...
        exception, "extended", "hyperlinks", "off")), ...
    "tFinal_s", NaN, "t", [], "signals", struct(), "states", struct([]));
end

function status = buildRunStatus(experimentStatus, startedAt, runResult, ...
        callReturned, runnerException, identityUnchanged, identityBefore, ...
        identityAfter, artifacts)
status = struct( ...
    "run_schema", "steady53_fig519_ihx_r2_hexe_shift_run_v1", ...
    "attempt_id", "20260901_A3", ...
    "candidate_value_identity", ...
        "figure_5_18a_t0_visual_proxy_not_author_initial_state", ...
    "experiment_status", experimentStatus, ...
    "started_at_utc", startedAt, ...
    "completed_at_utc", isoTimestamp(), ...
    "run_steady53_case_call_count", 1, ...
    "run_steady53_case_returned", callReturned, ...
    "retry_count", 0, ...
    "rerun_forbidden", true, ...
    "candidate_success", logicalField(runResult, "success"), ...
    "candidate_final_time_s", finiteOrNull(fieldOr(runResult, "tFinal_s", NaN)), ...
    "candidate_error_id", string(fieldOr(runResult, "errorId", "")), ...
    "candidate_error_report", string(fieldOr(runResult, "errorReport", "")), ...
    "runner_exception_id", exceptionId(runnerException), ...
    "runner_exception_report", exceptionReport(runnerException), ...
    "identity_unchanged", identityUnchanged, ...
    "identity_before", identityBefore, ...
    "identity_after", identityAfter, ...
    "artifacts", artifacts, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);
end

function output = appendException(existing, added)
if isempty(existing)
    output = added;
else
    output = addCause(existing, added);
end
end

function value = fieldOr(item, name, fallback)
if isstruct(item) && isfield(item, name)
    value = item.(name);
else
    value = fallback;
end
end

function value = logicalField(item, name)
value = false;
if isstruct(item) && isfield(item, name) && ...
        islogical(item.(name)) && isscalar(item.(name))
    value = item.(name);
end
end

function value = finiteOrNull(value)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
    value = [];
end
end

function value = exceptionId(exception)
if isempty(exception)
    value = "";
else
    value = string(exception.identifier);
end
end

function value = exceptionReport(exception)
if isempty(exception)
    value = "";
else
    value = string(getReport(exception, "extended", "hyperlinks", "off"));
end
end

function timestamp = isoTimestamp()
timestamp = string(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"));
end

function repoRoot = validateRepoRoot(repoRoot)
repoRoot = canonicalPath(repoRoot);
detected = string(fileparts(fileparts(mfilename("fullpath"))));
if repoRoot ~= canonicalPath(detected)
    error("fig519a3run:RepoRootMismatch", ...
        "repoRoot must contain this captured runner.");
end
assertNoSymlinkAncestors(repoRoot, repoRoot);
end

function [binding, auditByteHash] = bindInvocationInputs( ...
        runDir, candidatePath, auditPath, sourcePath, repoRoot)
binding = struct( ...
    "run_ancestors", bindDirectoryAncestors(runDir, repoRoot), ...
    "run_dir", pathIdentity(runDir, "directory"), ...
    "candidate", pathIdentity(candidatePath, "file"), ...
    "audit", pathIdentity(auditPath, "file"), ...
    "source", pathIdentity(sourcePath, "file"), ...
    "matlab_helpers", bindCapturedMatlabHelpers(repoRoot));
auditByteHash = sha256File(auditPath);
if sha256File(sourcePath) ~= ...
        "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
    error("fig519a3run:SourceHashMismatch", ...
        "The captured immutable source model changed before audit parsing.");
end
end

function records = bindDirectoryAncestors(pathValue, stopAt)
pathValue = lexicalAbsolute(pathValue);
stopAt = lexicalAbsolute(stopAt);
if pathValue ~= stopAt && ~startsWith(pathValue, stopAt + filesep)
    error("fig519a3run:AncestorBindingOutsideRoot", ...
        "Invocation path is not below the captured repository root.");
end
paths = strings(0, 1);
probe = pathValue;
while true
    paths(end + 1, 1) = probe; %#ok<AGROW>
    if probe == stopAt
        break
    end
    parent = string(fileparts(probe));
    if parent == probe
        error("fig519a3run:AncestorBindingIncomplete", ...
            "Invocation ancestor chain did not reach repoRoot.");
    end
    probe = parent;
end
paths = flip(paths);
records = repmat(struct("path", "", "identity", struct()), ...
    numel(paths), 1);
for index = 1:numel(paths)
    records(index) = struct("path", paths(index), ...
        "identity", pathIdentity(paths(index), "directory"));
end
end

function assertInvocationBindings(binding, runDir, candidatePath, ...
        auditPath, sourcePath)
for index = 1:numel(binding.run_ancestors)
    assertSameIdentity(binding.run_ancestors(index).identity, ...
        binding.run_ancestors(index).path, "run ancestor");
end
assertSameIdentity(binding.run_dir, runDir, "candidate run directory");
assertSameIdentity(binding.candidate, candidatePath, "candidate model");
assertSameIdentity(binding.audit, auditPath, "patch audit");
assertSameIdentity(binding.source, sourcePath, "immutable source model");
assertCapturedMatlabHelpers(binding.matlab_helpers, ...
    string(fileparts(fileparts(mfilename("fullpath")))));
end

function records = bindCapturedMatlabHelpers(repoRoot)
functionNames = ["run_steady53_case"; "steady53_signal_manifest"; ...
    "reset_steady53_property_warning_state"];
fileNames = functionNames + ".m";
hashes = [ ...
    "686749ffe329f71ed884e0f98d2681d6c35aa5df258ff6675917a55c20b9da42"; ...
    "7807290de1b02cf4c2e513976a8c95e5780201ce5fdae0bdd97679b0f2e835bd"; ...
    "04f1be8b20c3b48f17e468c1dd15a282e15ea08f14f255f5a6f3d269f2d44ff0"];
records = repmat(struct("function_name", "", ...
    "repository_relative_path", "", "sha256", "", ...
    "identity", struct()), numel(functionNames), 1);
for index = 1:numel(functionNames)
    relative = "tests/steady53/" + fileNames(index);
    filePath = resolveCapturedPath(repoRoot, relative);
    assertRegularFile(filePath, "captured MATLAB helper");
    resolved = string(which(functionNames(index)));
    if strlength(resolved) == 0 || canonicalPath(resolved) ~= canonicalPath(filePath)
        error("fig519a3run:CapturedHelperResolutionMismatch", ...
            "MATLAB helper %s does not resolve to the captured file.", ...
            functionNames(index));
    end
    if sha256File(filePath) ~= hashes(index)
        error("fig519a3run:CapturedHelperHashMismatch", ...
            "Captured MATLAB helper hash differs: %s", relative);
    end
    records(index) = struct("function_name", functionNames(index), ...
        "repository_relative_path", relative, "sha256", hashes(index), ...
        "identity", pathIdentity(filePath, "file"));
end
end

function assertCapturedMatlabHelpers(records, repoRoot)
if numel(records) ~= 3
    error("fig519a3run:CapturedHelperSetMismatch", ...
        "Exactly three captured MATLAB helpers must remain bound.");
end
for index = 1:numel(records)
    filePath = resolveCapturedPath(repoRoot, ...
        records(index).repository_relative_path);
    assertSameIdentity(records(index).identity, filePath, ...
        "captured MATLAB helper");
    resolved = string(which(records(index).function_name));
    if strlength(resolved) == 0 || canonicalPath(resolved) ~= canonicalPath(filePath) || ...
            sha256File(filePath) ~= records(index).sha256
        error("fig519a3run:CapturedHelperBindingChanged", ...
            "Captured MATLAB helper binding changed: %s", ...
            records(index).function_name);
    end
end
end

function assertInvocationHashes(binding, auditByteHash, candidateFrozenHash, ...
        auditPath, candidatePath, sourcePath)
assertSameIdentity(binding.audit, auditPath, "patch audit hash input");
if sha256File(auditPath) ~= auditByteHash
    error("fig519a3run:AuditBytesChanged", ...
        "Patch audit bytes changed after first binding.");
end
assertSameIdentity(binding.candidate, candidatePath, "candidate hash input");
if sha256File(candidatePath) ~= candidateFrozenHash
    error("fig519a3run:CandidateHashChanged", ...
        "Candidate bytes differ from the frozen audit candidate SHA-256.");
end
assertSameIdentity(binding.source, sourcePath, "source hash input");
if sha256File(sourcePath) ~= ...
        "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391"
    error("fig519a3run:SourceHashChanged", ...
        "Immutable source bytes changed at the formal call gate.");
end
end

function runDir = validateExistingRunDirectory(runDir, tmpRoot)
runDir = string(runDir);
if ~startsWith(runDir, filesep)
    error("fig519a3run:RunDirMustBeAbsolute", "runDir must be absolute.");
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalRun = canonicalPath(runDir);
if canonicalRun == canonicalTmp || ...
        ~startsWith(canonicalRun, canonicalTmp + filesep)
    error("fig519a3run:RunDirOutsideTmp", ...
        "runDir must remain below captured repoRoot/tmp.");
end
assertNoSymlinkAncestors(runDir, canonicalTmp);
assertRealDirectory(runDir, "A3 candidate directory");
runDir = canonicalRun;
end

function assertRunArtifactsBound(runIdentity, runPath, candidateIdentity, ...
        candidatePath, auditIdentity, auditPath)
assertSameIdentity(runIdentity, runPath, "run directory");
assertSameIdentity(candidateIdentity, candidatePath, "candidate model");
assertSameIdentity(auditIdentity, auditPath, "patch audit");
end

function assertNoSymlinkAncestors(pathValue, stopAt)
probe = string(java.io.File(string(pathValue)).getAbsolutePath());
stopAt = canonicalPath(stopAt);
while true
    if isSymbolicLink(probe)
        error("fig519a3run:SymlinkForbidden", "Symlinked path: %s", probe);
    end
    if canonicalPath(probe) == stopAt
        return
    end
    parent = string(fileparts(probe));
    if parent == probe
        break
    end
    probe = parent;
end
error("fig519a3run:PathNotAnchored", ...
    "Path is not anchored below its required root.");
end

function assertRegularFile(pathValue, label)
if isSymbolicLink(pathValue) || ~isfile(pathValue) || ...
        ~java.nio.file.Files.isRegularFile(nioPath(pathValue), ...
            javaArray("java.nio.file.LinkOption", 0))
    error("fig519a3run:RegularFileRequired", ...
        "%s must be a non-symlink regular file: %s", label, pathValue);
end
end

function assertRealDirectory(pathValue, label)
if isSymbolicLink(pathValue) || ~isfolder(pathValue) || ...
        ~java.nio.file.Files.isDirectory(nioPath(pathValue), ...
            javaArray("java.nio.file.LinkOption", 0))
    error("fig519a3run:RealDirectoryRequired", ...
        "%s must be a non-symlink directory: %s", label, pathValue);
end
end

function identity = pathIdentity(pathValue, kind)
if kind == "file"
    assertRegularFile(pathValue, "identity target");
else
    assertRealDirectory(pathValue, "identity target");
end
attributes = java.nio.file.Files.readAttributes(nioPath(pathValue), ...
    "basic:fileKey,isRegularFile,isDirectory,isSymbolicLink", ...
    javaArray("java.nio.file.LinkOption", 0));
unix = java.nio.file.Files.readAttributes(nioPath(pathValue), ...
    "unix:dev,ino,mode", javaArray("java.nio.file.LinkOption", 0));
identity = struct("absolute_path", lexicalAbsolute(pathValue), ...
    "canonical_path", canonicalPath(pathValue), ...
    "file_key", string(attributes.get("fileKey")), ...
    "device", string(unix.get("dev")), ...
    "inode", string(unix.get("ino")), "kind", string(kind));
if strlength(identity.file_key) == 0 || identity.file_key == "null"
    error("fig519a3run:FileKeyUnavailable", ...
        "Filesystem identity is unavailable for %s.", pathValue);
end
end

function assertSameIdentity(expected, pathValue, label)
actual = pathIdentity(pathValue, expected.kind);
if actual.absolute_path ~= expected.absolute_path || ...
        actual.canonical_path ~= expected.canonical_path || ...
        actual.file_key ~= expected.file_key || ...
        actual.device ~= expected.device || actual.inode ~= expected.inode
    error("fig519a3run:PathIdentityChanged", ...
        "%s identity changed: %s", label, pathValue);
end
end

function createDirectoryExclusive(directoryPath)
try
    permissions = java.nio.file.attribute.PosixFilePermissions.fromString("rwx------");
    attributes = javaArray("java.nio.file.attribute.FileAttribute", 1);
    attributes(1) = java.nio.file.attribute.PosixFilePermissions.asFileAttribute(permissions);
catch exception
    unavailable = MException("fig519a3run:PosixModeUnavailable", ...
        "Could not construct the mandatory POSIX 0700 directory attribute.");
    unavailable = addCause(unavailable, exception);
    throw(unavailable)
end
try
    java.nio.file.Files.createDirectory(nioPath(directoryPath), attributes);
catch exception
    if isfile(directoryPath) || isfolder(directoryPath) || isSymbolicLink(directoryPath)
        error("fig519a3run:ExperimentAlreadyStarted", ...
            "The one-shot directory already exists: '%s'.", directoryPath);
    end
    rethrow(exception)
end
assertPosixDirectoryMode0700(directoryPath);
end

function assertPosixDirectoryMode0700(directoryPath)
attributes = java.nio.file.Files.readAttributes(nioPath(directoryPath), ...
    "unix:mode", javaArray("java.nio.file.LinkOption", 0));
mode = double(attributes.get("mode"));
if bitand(mode, 511) ~= 448
    error("fig519a3run:DirectoryModeMismatch", ...
        "Exclusive directory mode must be exactly POSIX 0700.");
end
end

function writeExclusiveText(filePath, content)
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
try
    channel = java.nio.file.Files.newByteChannel(nioPath(filePath), options);
catch exception
    if isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath)
        error("fig519a3run:OutputExists", ...
            "Refusing to overwrite '%s'.", filePath);
    end
    rethrow(exception)
end
cleanup = onCleanup(@() closeChannel(channel));
bytes = unicode2native(char(string(content)), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(typecast(uint8(bytes), "int8"));
while buffer.hasRemaining()
    channel.write(buffer);
end
channel.force(true);
channel.close();
clear cleanup
end

function closeChannel(channel)
try
    if ~isempty(channel) && channel.isOpen()
        channel.close();
    end
catch
end
end

function hash = sha256File(filePath)
assertRegularFile(filePath, "SHA-256 input");
digest = java.security.MessageDigest.getInstance("SHA-256");
fileBytes = java.nio.file.Files.readAllBytes(nioPath(filePath));
bytes = typecast(digest.digest(fileBytes), "uint8");
hash = lower(join(string(dec2hex(bytes, 2)).', ""));
end

function value = isSymbolicLink(pathValue)
value = java.nio.file.Files.isSymbolicLink(nioPath(pathValue));
end

function value = isContainedLexically(pathValue, root)
path = nioPath(pathValue).toAbsolutePath().normalize();
base = nioPath(root).toAbsolutePath().normalize();
value = path.startsWith(base) && ~path.equals(base);
end

function output = lexicalAbsolute(pathValue)
output = string(nioPath(pathValue).toAbsolutePath().normalize().toString());
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end

function output = relativeIfWithinRepo(pathValue, repoRoot)
absolute = lexicalAbsolute(pathValue);
root = lexicalAbsolute(repoRoot);
if absolute.startsWith(root + filesep)
    output = replace(extractAfter(absolute, strlength(root + filesep)), ...
        filesep, "/");
else
    output = "";
end
end

function pathValue = nioPath(pathValue)
pathValue = java.nio.file.Paths.get(char(string(pathValue)), ...
    javaArray("java.lang.String", 0));
end

function status = testExclusiveTextCreation(repoRoot)
sandbox = createHookSandbox(repoRoot);
filePath = fullfile(sandbox.path, "exclusive.txt");
writeExclusiveText(filePath, "first");
if string(fileread(filePath)) ~= "first"
    error("fig519a3run:HookContentMismatch", ...
        "Exclusive text helper wrote unexpected content.");
end
rejected = false;
try
    writeExclusiveText(filePath, "second");
catch exception
    if string(exception.identifier) ~= "fig519a3run:OutputExists"
        rethrow(exception)
    end
    rejected = true;
end
if ~rejected
    error("fig519a3run:HookOverwriteAccepted", ...
        "Exclusive text helper accepted an overwrite.");
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "overwrite_rejected", true);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testExclusiveDirectoryCreation(repoRoot)
sandbox = createHookSandbox(repoRoot);
claimPath = fullfile(sandbox.path, "claim");
createDirectoryExclusive(claimPath);
rejected = false;
try
    createDirectoryExclusive(claimPath);
catch exception
    if string(exception.identifier) ~= "fig519a3run:ExperimentAlreadyStarted"
        rethrow(exception)
    end
    rejected = true;
end
if ~rejected
    error("fig519a3run:HookSecondClaimAccepted", ...
        "Exclusive directory helper accepted a second claim.");
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "second_claim_rejected", true);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testThrownCallArtifactTruthfulness(repoRoot)
sandbox = createHookSandbox(repoRoot);
candidatePath = fullfile(sandbox.path, "candidate.slx");
auditPath = fullfile(sandbox.path, "patch_audit.json");
writeExclusiveText(candidatePath, "test-only candidate locator");
writeExclusiveText(auditPath, "test-only audit locator");
runPath = fullfile(sandbox.path, "run");
createDirectoryExclusive(runPath);
runIdentity = pathIdentity(runPath, "directory");
rawPath = fullfile(runPath, "raw_result.mat");
candidateCsv = fullfile(runPath, "candidate_curves.csv");
referenceCsv = fullfile(runPath, "reference_curves.csv");
injected = MException("fig519a3run:InjectedCallFailure", ...
    "Injected test-only thrown-call outcome.");
runResult = thrownCallResult(injected);
[rawWritten, curvesWritten, runnerException] = ...
    persistReturnedCallArtifacts(runPath, runResult, false, rawPath, ...
        candidateCsv, injected, runIdentity, @failUnexpectedPersistence);
if rawWritten || curvesWritten || isfile(rawPath) || isfile(candidateCsv)
    error("fig519a3run:HookSyntheticArtifactCreated", ...
        "A thrown call created a synthetic raw or candidate curve artifact.");
end
artifacts = artifactRecords(sandbox.path, candidatePath, auditPath, ...
    rawPath, candidateCsv, referenceCsv);
diskStatus = buildRunStatus("runner_or_hash_gate_failed", isoTimestamp(), ...
    runResult, false, runnerException, true, struct("test_hook", true), ...
    struct("test_hook", true), artifacts);
statusPath = fullfile(runPath, "run_status.json");
writeExclusiveText(statusPath, ...
    string(jsonencode(diskStatus, PrettyPrint=true)) + newline);
status = jsondecode(fileread(statusPath));
locatorExists = true;
for index = 1:numel(status.artifacts)
    locatorExists = locatorExists && ...
        isfile(status.artifacts(index).absolute_path);
end
status.test_only = true;
status.simulation_call_count = 0;
status.raw_result_present = isfile(rawPath);
status.candidate_curves_present = isfile(candidateCsv);
status.all_artifact_locators_existed_at_write = locatorExists;
delete(statusPath);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testCallGateFiniteReplacement(repoRoot, kind)
sandbox = createHookSandbox(repoRoot);
runDir = fullfile(sandbox.path, "candidate_run");
createDirectoryExclusive(runDir);
candidatePath = fullfile(runDir, "candidate.slx");
auditPath = fullfile(runDir, "patch_audit.json");
sourcePath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
writeExclusiveText(candidatePath, "test-only candidate bytes");
writeExclusiveText(auditPath, "test-only audit bytes");
binding = struct( ...
    "run_ancestors", bindDirectoryAncestors(runDir, repoRoot), ...
    "run_dir", pathIdentity(runDir, "directory"), ...
    "candidate", pathIdentity(candidatePath, "file"), ...
    "audit", pathIdentity(auditPath, "file"), ...
    "source", pathIdentity(sourcePath, "file"), ...
    "matlab_helpers", bindCapturedMatlabHelpers(repoRoot));
displacedPath = fullfile(sandbox.path, "displaced_" + kind);
switch string(kind)
    case "run_dir"
        movePathNoReplace(runDir, displacedPath);
        createDirectoryExclusive(runDir);
        cleanupReplacement = onCleanup(@() restoreDisplacedDirectory( ...
            runDir, displacedPath)); %#ok<NASGU>
    case "candidate"
        movePathNoReplace(candidatePath, displacedPath);
        writeExclusiveText(candidatePath, "replacement candidate bytes");
        cleanupReplacement = onCleanup(@() restoreDisplacedFile( ...
            candidatePath, displacedPath)); %#ok<NASGU>
    case "audit"
        movePathNoReplace(auditPath, displacedPath);
        writeExclusiveText(auditPath, "replacement audit bytes");
        cleanupReplacement = onCleanup(@() restoreDisplacedFile( ...
            auditPath, displacedPath)); %#ok<NASGU>
    otherwise
        error("fig519a3run:HookKindInvalid", ...
            "Unknown finite-replacement hook kind: %s", kind);
end
[rejected, errorId] = captureExpectedFailure(@() ...
    assertInvocationBindings(binding, runDir, candidatePath, auditPath, sourcePath));
if ~rejected
    error("fig519a3run:HookReplacementAccepted", ...
        "The call gate accepted a finite replacement of %s.", kind);
end
clear cleanupReplacement
status = struct("test_only", true, "simulation_call_count", 0, ...
    "rejected_before_call", true, "error_id", errorId);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testRawExclusivePublicationAttack(repoRoot, kind)
sandbox = createHookSandbox(repoRoot);
runPath = fullfile(sandbox.path, "run");
createDirectoryExclusive(runPath);
runIdentity = pathIdentity(runPath, "directory");
rawPath = fullfile(runPath, "raw_result.mat");
sentinelPath = fullfile(sandbox.path, "sentinel.txt");
sentinel = "owned sentinel bytes";
writeExclusiveText(sentinelPath, sentinel);
displacedPath = fullfile(sandbox.path, "displaced_run");
switch string(kind)
    case "existing_file"
        writeExclusiveText(rawPath, sentinel);
    case "symlink"
        java.nio.file.Files.createSymbolicLink( ...
            nioPath(rawPath), nioPath(sentinelPath), ...
            javaArray("java.nio.file.attribute.FileAttribute", 0));
    case "parent_replacement"
        movePathNoReplace(runPath, displacedPath);
        createDirectoryExclusive(runPath);
    otherwise
        error("fig519a3run:HookKindInvalid", ...
            "Unknown raw-publication attack hook kind: %s", kind);
end
runResult = struct("success", false, "test_only", true);
[rejected, errorId] = captureExpectedFailure(@() ...
    saveRawExclusive(rawPath, runResult, runPath, runIdentity));
if ~rejected
    error("fig519a3run:HookRawOverwriteAccepted", ...
        "Raw publication accepted attack kind %s.", kind);
end
switch string(kind)
    case "existing_file"
        unchanged = string(fileread(rawPath)) == sentinel;
        delete(rawPath);
    case "symlink"
        unchanged = isSymbolicLink(rawPath) && ...
            string(fileread(sentinelPath)) == sentinel;
        delete(rawPath);
    case "parent_replacement"
        unchanged = ~isfile(rawPath) && ~isfolder(rawPath) && ...
            ~isSymbolicLink(rawPath);
        rmdir(runPath);
        movePathNoReplace(displacedPath, runPath);
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "overwrite_rejected", true, "original_unchanged", unchanged, ...
    "error_id", errorId);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testExactAuditNegativeValidation(repoRoot)
[duplicateRejected, ~] = captureExpectedFailure(@() ...
    validateExactNameSet(["a"; "a"], ["a"; "b"], "hook duplicate"));
[missingRejected, ~] = captureExpectedFailure(@() ...
    validateExactNameSet("a", ["a"; "b"], "hook missing"));
[extraRejected, ~] = captureExpectedFailure(@() ...
    validateExactNameSet(["a"; "b"; "c"], ["a"; "b"], "hook extra"));
states = hookStateInventory();
states(39).candidate_expression = "1052.2147530694";
[changedValueRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventoryValues(states));
nanStates = hookStateInventory();
nanStates(39).candidate_expression = "NaN";
[nanStateRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventoryValues(nanStates));
infStates = hookStateInventory();
infStates(39).source_expression = "Inf";
[infStateRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventoryValues(infStates));
nonnumericStates = hookStateInventory();
nonnumericStates(40).candidate_expression = "not-a-number";
[nonnumericStateRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventoryValues(nonnumericStates));
duplicateSourceStates = hookStateInventory();
duplicateSourceStates(2).source_path = duplicateSourceStates(1).source_path;
[duplicateSourcePathRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventory(duplicateSourceStates));
duplicateCandidateStates = hookStateInventory();
duplicateCandidateStates(2).candidate_path = ...
    duplicateCandidateStates(1).candidate_path;
[duplicateCandidatePathRejected, ~] = captureExpectedFailure(@() ...
    validateStateInventory(duplicateCandidateStates));
sandbox = createHookSandbox(repoRoot);
realParent = fullfile(sandbox.path, "real_parent");
createDirectoryExclusive(realParent);
filePath = fullfile(realParent, "fixture.txt");
writeExclusiveText(filePath, "fixture");
linkParent = fullfile(sandbox.path, "link_parent");
java.nio.file.Files.createSymbolicLink( ...
    nioPath(linkParent), nioPath(realParent), ...
    javaArray("java.nio.file.attribute.FileAttribute", 0));
relative = relativeIfWithinRepo(fullfile(linkParent, "fixture.txt"), repoRoot);
[symlinkRejected, ~] = captureExpectedFailure(@() ...
    resolveCapturedPath(repoRoot, relative));
delete(linkParent);
delete(filePath);
rmdir(realParent);
status = struct("test_only", true, "simulation_call_count", 0, ...
    "duplicate_rejected", duplicateRejected, ...
    "missing_rejected", missingRejected, "extra_rejected", extraRejected, ...
    "changed_value_rejected", changedValueRejected, ...
    "nan_state_rejected", nanStateRejected, ...
    "inf_state_rejected", infStateRejected, ...
    "nonnumeric_state_rejected", nonnumericStateRejected, ...
    "duplicate_source_path_rejected", duplicateSourcePathRejected, ...
    "duplicate_candidate_path_rejected", duplicateCandidatePathRejected, ...
    "symlink_ancestor_rejected", symlinkRejected);
sandbox = freezeHookSandboxInventory(sandbox);
cleanup = onCleanup(@() cleanupHookSandbox(sandbox)); %#ok<NASGU>
end

function status = testCapturedProtectedRecords(repoRoot)
records = hookCapturedProtectedRecords(repoRoot);
validateProtectedRecords(records, repoRoot);
tamperedPath = records;
tamperedPath(1).absolute_path = tamperedPath(1).absolute_path + ".tampered";
[tamperedPathRejected, ~] = captureExpectedFailure(@() ...
    validateProtectedRecords(tamperedPath, repoRoot));
tamperedHash = records;
tamperedHash(1).before_sha256 = ...
    "0000000000000000000000000000000000000000000000000000000000000000";
[tamperedHashRejected, ~] = captureExpectedFailure(@() ...
    validateProtectedRecords(tamperedHash, repoRoot));
status = struct("test_only", true, "simulation_call_count", 0, ...
    "captured_empty_relative_passed", ...
        all(strlength(string({records.repository_relative_path})) == 0), ...
    "tampered_path_rejected", tamperedPathRejected, ...
    "tampered_hash_rejected", tamperedHashRejected, ...
    "protected_record_count", numel(records));
end

function records = hookCapturedProtectedRecords(repoRoot)
manifest = fixedProtectedManifest(repoRoot);
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "before_sha256", "", "after_sha256", "", ...
    "unchanged", true), height(manifest), 1);
for index = 1:height(manifest)
    records(index) = struct("name", manifest.original_path(index), ...
        "repository_relative_path", "", ...
        "absolute_path", canonicalPath(manifest.resolved_path(index)), ...
        "before_sha256", manifest.resolved_sha256(index), ...
        "after_sha256", manifest.resolved_sha256(index), ...
        "unchanged", true);
end
end

function status = testCapturedHelperFiniteReplacement(repoRoot, kind)
records = bindCapturedMatlabHelpers(repoRoot);
match = find(string({records.function_name}) == string(kind));
if numel(match) ~= 1
    error("fig519a3run:HookKindInvalid", ...
        "Unknown captured-helper replacement kind: %s", kind);
end
filePath = resolveCapturedPath(repoRoot, ...
    records(match).repository_relative_path);
displacedPath = fullfile(repoRoot, "tmp", ...
    ".fig519a3_helper_displaced_" + string(java.util.UUID.randomUUID()));
movePathNoReplace(filePath, displacedPath);
restore = onCleanup(@() restoreDisplacedFile(filePath, displacedPath));
writeExclusiveText(filePath, "% test-only finite replacement" + newline);
[rejected, errorId] = captureExpectedFailure(@() ...
    assertCapturedMatlabHelpers(records, repoRoot));
clear restore
if ~rejected || sha256File(filePath) ~= records(match).sha256
    error("fig519a3run:HookHelperReplacementAccepted", ...
        "Captured-helper replacement was accepted or not restored: %s", kind);
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "rejected_before_call", true, "error_id", errorId);
end

function status = testHookCleanupInventoryDrift(repoRoot)
stable = createHookSandbox(repoRoot);
writeExclusiveText(fullfile(stable.path, "known.txt"), "known");
stable = freezeHookSandboxInventory(stable);
stableCleaned = cleanupHookSandbox(stable);

extra = createHookSandbox(repoRoot);
knownExtraPath = fullfile(extra.path, "known.txt");
writeExclusiveText(knownExtraPath, "known");
extra = freezeHookSandboxInventory(extra);
extraPath = fullfile(extra.path, "extra.txt");
writeExclusiveText(extraPath, "extra");
extraCleaned = cleanupHookSandbox(extra);
extraRetained = ~extraCleaned && isfile(knownExtraPath) && isfile(extraPath);
delete(extraPath);
if ~cleanupHookSandbox(extra)
    error("fig519a3run:HookCleanupRecoveryFailed", ...
        "Stable cleanup failed after removing the injected extra entry.");
end

replaced = createHookSandbox(repoRoot);
knownReplacedPath = fullfile(replaced.path, "known.txt");
writeExclusiveText(knownReplacedPath, "known");
replaced = freezeHookSandboxInventory(replaced);
displacedPath = fullfile(repoRoot, "tmp", ...
    ".fig519a3_cleanup_displaced_" + string(java.util.UUID.randomUUID()));
movePathNoReplace(knownReplacedPath, displacedPath);
restore = onCleanup(@() restoreDisplacedFile(knownReplacedPath, displacedPath));
writeExclusiveText(knownReplacedPath, "replacement");
replacedCleaned = cleanupHookSandbox(replaced);
replacedRetained = ~replacedCleaned && isfile(knownReplacedPath) && ...
    isfile(displacedPath);
clear restore
if ~cleanupHookSandbox(replaced)
    error("fig519a3run:HookCleanupRecoveryFailed", ...
        "Stable cleanup failed after restoring the replaced entry.");
end
status = struct("test_only", true, "simulation_call_count", 0, ...
    "stable_inventory_cleaned", stableCleaned, ...
    "extra_inventory_retained", extraRetained, ...
    "replaced_identity_retained", replacedRetained);
end

function states = hookStateInventory()
states = repmat(struct("source_path", "", "candidate_path", "", ...
    "source_expression", "", "candidate_expression", "", ...
    "unchanged", true), 40, 1);
for index = 1:38
    path = "final_steady_24a/hook/state_" + string(index);
    states(index) = struct("source_path", path, ...
        "candidate_path", replace(path, "final_steady_24a/", "candidate/"), ...
        "source_expression", string(index), ...
        "candidate_expression", string(index), "unchanged", true);
end
states(39) = struct("source_path", ...
    "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator", ...
    "candidate_path", ...
    "candidate/IHX/IHX_region_2/T_c1_average_Integrator", ...
    "source_expression", "1245.8184669844006", ...
    "candidate_expression", "1052.2147530693003", "unchanged", false);
states(40) = struct("source_path", ...
    "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator", ...
    "candidate_path", ...
    "candidate/IHX/IHX_region_2/T_c2_out_Integrator", ...
    "source_expression", "1393.6037139151003", ...
    "candidate_expression", "1200.0000000000000", "unchanged", false);
end

function [failed, errorId] = captureExpectedFailure(callback)
failed = false;
errorId = "";
try
    callback();
catch exception
    failed = true;
    errorId = string(exception.identifier);
end
end

function movePathNoReplace(sourcePath, destinationPath)
java.nio.file.Files.move(nioPath(sourcePath), nioPath(destinationPath), ...
    javaArray("java.nio.file.CopyOption", 0));
end

function restoreDisplacedFile(replacementPath, displacedPath)
try
    if isfile(replacementPath) || isSymbolicLink(replacementPath)
        delete(replacementPath);
    end
    if isfile(displacedPath) && ~isSymbolicLink(displacedPath)
        movePathNoReplace(displacedPath, replacementPath);
    end
catch
    % Preserve unexpected test state for forensic inspection.
end
end

function restoreDisplacedDirectory(replacementPath, displacedPath)
try
    if isfolder(replacementPath) && ~isSymbolicLink(replacementPath)
        listing = dir(replacementPath);
        names = string({listing.name});
        if ~any(~ismember(names, [".", ".."]))
            rmdir(replacementPath);
        end
    end
    if isfolder(displacedPath) && ~isSymbolicLink(displacedPath) && ...
            ~isfolder(replacementPath)
        movePathNoReplace(displacedPath, replacementPath);
    end
catch
    % Preserve unexpected test state for forensic inspection.
end
end

function failUnexpectedPersistence()
error("fig519a3run:HookUnexpectedPersistence", ...
    "The persistence gate ran for a thrown-call outcome.");
end

function sandbox = createHookSandbox(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
assertRealDirectory(tmpRoot, "repository tmp directory");
sandboxPath = fullfile(tmpRoot, ...
    ".fig519a3_runner_hook_" + string(java.util.UUID.randomUUID()));
createDirectoryExclusive(sandboxPath);
sandbox = struct("path", sandboxPath, ...
    "identity", pathIdentity(sandboxPath, "directory"), ...
    "files", struct([]), "directories", struct([]), ...
    "inventory_frozen", false);
end

function sandbox = freezeHookSandboxInventory(sandbox)
assertSameIdentity(sandbox.identity, sandbox.path, "hook sandbox freeze root");
[sandbox.files, sandbox.directories] = hookInventorySnapshot(sandbox.path);
sandbox.inventory_frozen = true;
end

function [files, directories] = hookInventorySnapshot(rootPath)
files = repmat(struct("path", "", "identity", struct()), 0, 1);
directories = repmat(struct("path", "", "identity", struct()), 0, 1);
queue = string(rootPath);
nextIndex = 1;
while nextIndex <= numel(queue)
    parent = queue(nextIndex);
    nextIndex = nextIndex + 1;
    listing = dir(parent);
    names = string({listing.name});
    children = names(~ismember(names, [".", ".."]));
    for index = 1:numel(children)
        child = fullfile(parent, children(index));
        if isSymbolicLink(child)
            error("fig519a3run:HookInventorySymlink", ...
                "Hook cleanup inventory cannot contain a symlink: %s", child);
        elseif isfile(child)
            files(end + 1, 1) = struct("path", child, ... %#ok<AGROW>
                "identity", pathIdentity(child, "file"));
        elseif isfolder(child)
            directories(end + 1, 1) = struct("path", child, ... %#ok<AGROW>
                "identity", pathIdentity(child, "directory"));
            queue(end + 1, 1) = string(child); %#ok<AGROW>
        else
            error("fig519a3run:HookInventoryUnsupportedEntry", ...
                "Hook cleanup inventory found an unsupported entry: %s", child);
        end
    end
end
end

function assertHookInventoryUnchanged(sandbox)
if ~isfield(sandbox, "inventory_frozen") || ~sandbox.inventory_frozen
    error("fig519a3run:HookInventoryNotFrozen", ...
        "Hook cleanup requires a fixed creation-time inventory.");
end
assertSameIdentity(sandbox.identity, sandbox.path, "hook sandbox cleanup root");
[actualFiles, actualDirectories] = hookInventorySnapshot(sandbox.path);
validateExactNameSet(string({actualFiles.path}).', ...
    string({sandbox.files.path}).', "hook cleanup file path");
validateExactNameSet(string({actualDirectories.path}).', ...
    string({sandbox.directories.path}).', "hook cleanup directory path");
for index = 1:numel(sandbox.files)
    assertSameIdentity(sandbox.files(index).identity, ...
        sandbox.files(index).path, "known hook cleanup file");
end
for index = 1:numel(sandbox.directories)
    assertSameIdentity(sandbox.directories(index).identity, ...
        sandbox.directories(index).path, "known hook cleanup directory");
end
end

function cleaned = cleanupHookSandbox(sandbox)
cleaned = false;
if ~isfolder(sandbox.path) || isSymbolicLink(sandbox.path)
    return
end
try
    assertHookInventoryUnchanged(sandbox);
    for index = 1:numel(sandbox.files)
        assertSameIdentity(sandbox.files(index).identity, ...
            sandbox.files(index).path, "known hook cleanup file deletion");
        delete(sandbox.files(index).path);
    end
    directoryPaths = string({sandbox.directories.path}).';
    [~, order] = sort(strlength(directoryPaths), "descend");
    for index = 1:numel(order)
        record = sandbox.directories(order(index));
        assertSameIdentity(record.identity, record.path, ...
            "known hook cleanup directory deletion");
        listing = dir(record.path);
        names = string({listing.name});
        if any(~ismember(names, [".", ".."]))
            error("fig519a3run:HookDirectoryNotEmpty", ...
                "Known hook directory is not empty at deletion: %s", record.path);
        end
        rmdir(record.path);
    end
    assertSameIdentity(sandbox.identity, sandbox.path, ...
        "hook sandbox root deletion");
    listing = dir(sandbox.path);
    names = string({listing.name});
    if any(~ismember(names, [".", ".."]))
        error("fig519a3run:HookRootNotEmpty", ...
            "Known hook sandbox root is not empty at deletion.");
    end
    rmdir(sandbox.path);
    cleaned = true;
catch
    % Retain the entire unknown/replaced/drifted tree as evidence.
end
end
