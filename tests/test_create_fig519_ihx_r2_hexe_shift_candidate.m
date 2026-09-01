function tests = test_create_fig519_ihx_r2_hexe_shift_candidate
%TEST_CREATE_FIG519_IHX_R2_HEXE_SHIFT_CANDIDATE Zero-simulation A3 contract.
tests = functiontests(localfunctions);
end

function testBuildsAuditedCandidateWithoutSimulation(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
owner = createOwnedTestSandbox(tmpRoot);
cleanup = onCleanup(@() cleanupOwnedOutput(owner, tmpRoot));
outputDir = fullfile(owner.path, "candidate-output");

sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
protectedManifest = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "protected_manifest_recovery.csv");
formalPaths = existingFormalPaths(repo, sourcePath, protectedManifest);
before = hashRecords(formalPaths);
callerBefore = callerState();

audit = create_fig519_ihx_r2_hexe_shift_candidate(outputDir, repo);
verifyCallerState(testCase, callerBefore);
stagingItems = dir(fullfile(outputDir, ".fig519a3-stage-*"));
verifyEqual(testCase, numel(stagingItems), 1);
verifyEqual(testCase, posixMode(fullfile(stagingItems(1).folder, ...
    stagingItems(1).name)), "rwx------");

expectedSchema = "steady53_fig519_ihx_r2_hexe_shift_candidate_v1";
verifyEqual(testCase, string(audit.patch_schema), expectedSchema);
verifyEqual(testCase, string(audit.attempt_id), "20260901_A3");
verifyEqual(testCase, audit.delta_T_K, -193.6037139151003, "AbsTol", 1e-12);
verifyEqual(testCase, string(audit.source_model_sha256), ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyEqual(testCase, audit.changed_state_count, 2);
verifyEqual(testCase, audit.unchanged_state_count, 38);
verifyEqual(testCase, audit.state_count, 40);
verifyEqual(testCase, audit.solver_parameter_count, 37);
verifyEqual(testCase, audit.old_gap_K, 147.7852469306997, "AbsTol", 1e-12);
verifyEqual(testCase, audit.new_gap_K, audit.old_gap_K, "AbsTol", 1e-12);
verifyEqual(testCase, [audit.changed_states.delta_T_K], ...
    [audit.delta_T_K, audit.delta_T_K], "AbsTol", 1e-12);
verifyEqual(testCase, [audit.changed_states.old_initial_condition_K], ...
    [1245.8184669844006, 1393.6037139151003], "AbsTol", 1e-12);
verifyEqual(testCase, [audit.changed_states.new_initial_condition_K], ...
    [1052.2147530693003, 1200.0000000000000], "AbsTol", 1e-12);
verifyFalse(testCase, audit.paper_reproduced);
verifyFalse(testCase, audit.author_initial_state_identified);
verifyFalse(testCase, audit.formal_promotion);
verifyEqual(testCase, audit.update_diagram_count, 1);
verifyTrue(testCase, audit.source_hash_unchanged);
verifyTrue(testCase, audit.semantic_snapshot.unchanged);
sourceMasksPresent = verifyMaskInventory( ...
    testCase, audit.semantic_snapshot.source);
candidateMasksPresent = verifyMaskInventory( ...
    testCase, audit.semantic_snapshot.candidate);
if ~sourceMasksPresent || ~candidateMasksPresent
    return
end
verifyEqual(testCase, ...
    string(audit.semantic_snapshot.source.mask_fingerprint), ...
    string(audit.semantic_snapshot.candidate.mask_fingerprint));
verifyEqual(testCase, audit.semantic_snapshot.source.mask_inventory, ...
    audit.semantic_snapshot.candidate.mask_inventory);
verifyTrue(testCase, audit.model_workspace.unchanged);
verifyTrue(testCase, audit.file_generation_settings.contained);
verifyTrue(testCase, all([audit.runtime_dependencies.unchanged]));
verifyTrue(testCase, all([audit.protected_files.unchanged]));
verifyEqual(testCase, string(audit.formal_identity_schema), ...
    "repository_root_formal_identity_v1");
verifyTrue(testCase, all([audit.formal_files.unchanged]));
verifyTrue(testCase, any(string({audit.formal_files.repository_relative_path}) == ...
    "final_dynamic_24a.slx"));
formalNames = string({audit.formal_files.repository_relative_path});
verifyTrue(testCase, all(ismember(["final_steady_24a.slx", ...
    "HeXe_property_simulink.m", "Lithium_property_simulink.m"], ...
    formalNames)));
verifyTrue(testCase, isfield(audit.semantic_snapshot.source, "line_inventory"));
verifyEqual(testCase, audit.semantic_snapshot.source.line_inventory, ...
    audit.semantic_snapshot.candidate.line_inventory);
verifyTrue(testCase, isfield(audit.artifact_audit, "directories"));
verifyFalse(testCase, audit.artifact_audit.any_symlink);

candidatePath = fullfile(outputDir, "candidate.slx");
auditPath = fullfile(outputDir, "patch_audit.json");
verifyTrue(testCase, isRegularFile(candidatePath));
verifyTrue(testCase, isRegularFile(auditPath));
verifyEqual(testCase, string(audit.publication_identity.candidate_file_key), ...
    fileIdentity(candidatePath));
verifyEqual(testCase, string(audit.publication_identity.audit_file_key), ...
    fileIdentity(auditPath));
verifyFalse(testCase, isfile(fullfile(outputDir, "raw_result.mat")));
verifyFalse(testCase, isfolder(fullfile(outputDir, "run")));
verifyFalse(testCase, isfile(fullfile(outputDir, "experiment_started.json")));
verifyFalse(testCase, isfile(fullfile(outputDir, "run_status.json")));

decoded = jsondecode(fileread(auditPath));
verifyEqual(testCase, string(decoded.patch_schema), expectedSchema);
verifyEqual(testCase, string(decoded.candidate_sha256), ...
    string(audit.candidate_sha256));
verifyEqual(testCase, decoded.changed_state_count, 2);
verifyEqual(testCase, decoded.unchanged_state_count, 38);
verifyEqual(testCase, decoded.state_count, 40);
verifyEqual(testCase, decoded.update_diagram_count, 1);
verifyEqual(testCase, ...
    string(decoded.publication_identity.run_directory_file_key), ...
    string(audit.publication_identity.run_directory_file_key));
verifyEqual(testCase, ...
    string(decoded.publication_identity.candidate_file_key), ...
    string(audit.publication_identity.candidate_file_key));
verifyEqual(testCase, ...
    string(decoded.publication_identity.audit_file_key), ...
    string(audit.publication_identity.audit_file_key));
verifyEqual(testCase, string(decoded.formal_identity_schema), ...
    "repository_root_formal_identity_v1");
verifyTrue(testCase, all([decoded.formal_files.unchanged]));
verifyTrue(testCase, any(string({decoded.formal_files.repository_relative_path}) == ...
    "final_dynamic_24a.slx"));
sourceMasksPresent = verifyMaskInventory( ...
    testCase, decoded.semantic_snapshot.source);
candidateMasksPresent = verifyMaskInventory( ...
    testCase, decoded.semantic_snapshot.candidate);
if ~sourceMasksPresent || ~candidateMasksPresent
    return
end

after = hashRecords(formalPaths);
verifyEqual(testCase, before, after);
verifyFalse(testCase, bdIsLoaded("candidate"));
verifyFalse(testCase, bdIsLoaded("final_steady_24a"));

generatorSource = fileread(fullfile(repo, "tests", ...
    "create_fig519_ihx_r2_hexe_shift_candidate.m"));
verifyFalse(testCase, contains(lower(generatorSource), "run_steady53_case"));
verifyFalse(testCase, contains(lower(generatorSource), ...
    '"simulationcommand", "start"'));
verifyFalse(testCase, contains(lower(generatorSource), "sim("));
end

function testCleanupPreservesReplacementDirectory(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
displaced = owner.path + "-displaced";
movefile(owner.path, displaced);
mkdir(owner.path);
replacementIdentity = fileIdentity(owner.path);
replacementSentinel = fullfile(owner.path, "replacement.txt");
writelines("replacement", replacementSentinel);
cleanupOwnedOutput(owner, tmpRoot);
verifyTrue(testCase, isfolder(owner.path));
verifyTrue(testCase, isfile(replacementSentinel));
verifyEqual(testCase, fileIdentity(owner.path), replacementIdentity);
displacedOwner = owner;
displacedOwner.path = displaced;
displacedOwner.token_path = fullfile(displaced, ".fig519a3-test-owner");
cleanupOwnedOutput(displacedOwner, tmpRoot);
replacementOwner = claimOwnedTestSandbox(owner.path, tmpRoot);
cleanupOwnedOutput(replacementOwner, tmpRoot);
end

function testCleanupDeletesTrustedOwnedTree(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
ownedOutput = fullfile(owner.path, "candidate-output");
mkdir(ownedOutput);
writelines("owned", fullfile(ownedOutput, "owned.txt"));
result = cleanupOwnedOutput(owner, tmpRoot);
verifyEqual(testCase, string(result.status), "deleted");
verifyFalse(testCase, isfolder(owner.path));
end

function testCleanupRejectsForeignOwnerSchema(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
writelines("owned", fullfile(owner.path, "owned.txt"));
foreignOwner = owner;
foreignOwner.schema = "foreign_owner";
result = cleanupOwnedOutput(foreignOwner, tmpRoot);
verifyEqual(testCase, string(result.status), "retained_untrusted");
verifyTrue(testCase, isfile(fullfile(owner.path, "owned.txt")));
verifyEqual(testCase, string(cleanupOwnedOutput(owner, tmpRoot).status), ...
    "deleted");
end

function testCleanupDeletesSymlinkWithoutFollowingExternalTarget(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
externalOwner = createOwnedTestSandbox(tmpRoot);
externalSentinel = fullfile(externalOwner.path, "external.txt");
writelines("external", externalSentinel);
owner = createOwnedTestSandbox(tmpRoot);
ownedOutput = fullfile(owner.path, "candidate-output");
mkdir(ownedOutput);
linkPath = fullfile(ownedOutput, "external-link");
java.nio.file.Files.createSymbolicLink(nioPath(linkPath), ...
    nioPath(externalOwner.path), ...
    javaArray("java.nio.file.attribute.FileAttribute", 0));

result = cleanupOwnedOutput(owner, tmpRoot);
verifyEqual(testCase, string(result.status), "deleted");
verifyFalse(testCase, isfolder(owner.path));
verifyTrue(testCase, isfile(externalSentinel));
externalResult = cleanupOwnedOutput(externalOwner, tmpRoot);
verifyEqual(testCase, string(externalResult.status), "deleted");
end

function testCleanupRetainsOwnedNonemptyAndFinalBoundaryReplacement(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
ownedOutput = fullfile(owner.path, "candidate-output");
mkdir(ownedOutput);
writelines("owned", fullfile(ownedOutput, "owned.txt"));
boundary = @() replaceAtCleanupBoundary(owner.path);
result = cleanupOwnedOutput(owner, tmpRoot, boundary);
verifyEqual(testCase, string(result.status), "retained_untrusted");
verifyTrue(testCase, isfolder(owner.path));
verifyTrue(testCase, isfile(fullfile(owner.path, "replacement.txt")));
displacedOwner = owner;
displacedOwner.path = owner.path + "-owned-before-boundary";
displacedOwner.token_path = fullfile(displacedOwner.path, ...
    ".fig519a3-test-owner");
verifyEqual(testCase, string(cleanupOwnedOutput( ...
    displacedOwner, tmpRoot).status), "deleted");
replacementOwner = claimOwnedTestSandbox(owner.path, tmpRoot);
verifyEqual(testCase, string(cleanupOwnedOutput( ...
    replacementOwner, tmpRoot).status), "deleted");
end

function replaceAtCleanupBoundary(pathValue)
displaced = pathValue + "-owned-before-boundary";
movefile(pathValue, displaced);
mkdir(pathValue);
writelines("replacement", fullfile(pathValue, "replacement.txt"));
end

function testCleanupRetainsNestedReplacementAtDeletionBoundary(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
nested = fullfile(owner.path, "candidate-output", "nested");
mkdir(nested);
writelines("owned", fullfile(nested, "owned.txt"));
boundary = @() replaceNestedAtCleanupBoundary(nested);
result = cleanupOwnedOutput(owner, tmpRoot, boundary);
verifyEqual(testCase, string(result.status), "retained_untrusted");
verifyTrue(testCase, isfile(fullfile(nested, "replacement.txt")));
verifyTrue(testCase, isfile(fullfile(nested + "-displaced", "owned.txt")));
verifyEqual(testCase, string(cleanupOwnedOutput(owner, tmpRoot).status), ...
    "deleted");
end

function replaceNestedAtCleanupBoundary(pathValue)
displaced = pathValue + "-displaced";
movefile(pathValue, displaced);
mkdir(pathValue);
writelines("replacement", fullfile(pathValue, "replacement.txt"));
end

function testCleanupVerifiedHistoricalOwnersLeavesUntrustedEntries(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
untrustedPath = string(tempname(tmpRoot));
mkdir(untrustedPath);
sentinel = fullfile(untrustedPath, "untrusted.txt");
writelines("untrusted", sentinel);
trustedOwner = createOwnedTestSandbox(tmpRoot);
writelines("trusted", fullfile(trustedOwner.path, "trusted.txt"));

candidatePaths = [trustedOwner.path; untrustedPath];
historicalMode = string(getenv("FIG519A3_CLEAN_VERIFIED_HISTORICAL"));
if historicalMode == "dry-run-verified-owned" || ...
        historicalMode == "execute-verified-owned"
    candidatePaths = directTmpChildren(tmpRoot);
end
dryReport = cleanupVerifiedOwnedSandboxes(tmpRoot, candidatePaths, "dry_run");
verifyTrue(testCase, isfolder(trustedOwner.path));
verifyTrue(testCase, any(string(dryReport.verified_owned) == ...
    trustedOwner.path));
fprintf("A3 owned cleanup dry-run: verified=%d retained_untrusted=%d\n", ...
    numel(dryReport.verified_owned), numel(dryReport.retained_untrusted));
disp("A3 retained sample: " + ...
    join(string(dryReport.retained_untrusted( ...
    1:min(3, numel(dryReport.retained_untrusted)))), ", "));
verifiedTmpNames = leafNames(dryReport.verified_owned);
retainedTmpNames = leafNames(dryReport.retained_untrusted);
verifiedTp = startsWith(verifiedTmpNames, "tp");
retainedTp = startsWith(retainedTmpNames, "tp");
fprintf("A3 tp classification: verified=%d retained_untrusted=%d\n", ...
    nnz(verifiedTp), nnz(retainedTp));
disp("A3 retained tp sample: " + join(string( ...
    dryReport.retained_untrusted(find(retainedTp, ...
    min(3, nnz(retainedTp)), "first"))), ", "));
if historicalMode == "execute-verified-owned"
    report = cleanupVerifiedOwnedSandboxes(tmpRoot, candidatePaths, "execute");
else
    report = cleanupVerifiedOwnedSandboxes(tmpRoot, ...
        [trustedOwner.path; untrustedPath], "execute");
end
verifyFalse(testCase, isfolder(trustedOwner.path));
verifyTrue(testCase, any(string(report.deleted) == trustedOwner.path));
verifyTrue(testCase, isfolder(untrustedPath));
verifyTrue(testCase, isfile(sentinel));
verifyFalse(testCase, any(string(report.deleted) == untrustedPath));
verifyTrue(testCase, any(string(report.retained_untrusted) == untrustedPath));

untrustedOwner = claimOwnedTestSandbox(untrustedPath, tmpRoot);
verifyEqual(testCase, string(cleanupOwnedOutput( ...
    untrustedOwner, tmpRoot).status), "deleted");
end

function names = leafNames(paths)
names = strings(numel(paths), 1);
for index = 1:numel(paths)
    [~, names(index)] = fileparts(string(paths(index)));
end
end

function testInjectedFailuresRestoreCallerState(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
points = ["after_environment_setup", "after_source_load", ...
    "after_candidate_save", "after_update", "after_audit_open", ...
    "after_audit_write"];
for index = 1:numel(points)
    owner = createOwnedTestSandbox(tmpRoot);
    cleanup = onCleanup(@() cleanupOwnedOutput(owner, tmpRoot));
    outputDir = fullfile(owner.path, "candidate-output");
    state = callerState();
    installTestHook(owner, struct("point", points(index), ...
        "action", "fail"));
    hookCleanup = onCleanup(@() clearFailureHook());
    verifyError(testCase, ...
        @() create_fig519_ihx_r2_hexe_shift_candidate(outputDir, repo), ...
        "fig519a3:InjectedFailure");
    clear hookCleanup
    clearFailureHook();
    verifyCallerState(testCase, state);
    clear cleanup
    cleanupOwnedOutput(owner, tmpRoot);
end
end

function testStaleAmbientHookWithoutCapabilityIsIgnored(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
cleanup = onCleanup(@() cleanupOwnedOutput(owner, tmpRoot));
outputDir = fullfile(owner.path, "candidate-output");
setappdata(0, "fig519a3_test_failure_point", ...
    struct("point", "after_environment_setup", "action", "fail", ...
    "capability_token", "stale-or-foreign"));
hookCleanup = onCleanup(@() clearFailureHook());
audit = create_fig519_ihx_r2_hexe_shift_candidate(outputDir, repo);
verifyEqual(testCase, string(audit.attempt_id), "20260901_A3");
clear hookCleanup
clearFailureHook();
end

function testFiniteReplacementAndSymlinkAttacksAreDetected(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
cases = [ ...
    struct("point", "during_hash", "action", ...
        "replace_hashed_candidate", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "after_environment_setup", "action", ...
        "replace_staging_directory", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "before_candidate_publish", "action", ...
        "install_public_candidate", "error", "fig519a3:CandidateExists"); ...
    struct("point", "after_audit_open", "action", ...
        "install_symlink_directory", "error", "fig519a3:UnsafeArtifact"); ...
    struct("point", "after_candidate_publish", "action", ...
        "replace_public_candidate", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "after_candidate_hash", "action", ...
        "replace_public_candidate", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "after_audit_open", "action", ...
        "replace_audit_file", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "before_artifact_walk", "action", ...
        "replace_public_candidate", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "before_return", "action", ...
        "replace_public_candidate", "error", "fig519a3:PathIdentityChanged"); ...
    struct("point", "after_source_close", "action", ...
        "redirect_filegen", ...
        "error", "fig519a3:FileGenerationConfigurationMismatch"); ...
    struct("point", "after_candidate_load", "action", ...
        "redirect_filegen", ...
        "error", "fig519a3:FileGenerationConfigurationMismatch")];
for index = 1:numel(cases)
    owner = createOwnedTestSandbox(tmpRoot);
    cleanup = onCleanup(@() cleanupOwnedOutput(owner, tmpRoot));
    outputDir = fullfile(owner.path, "candidate-output");
    state = callerState();
    installTestHook(owner, cases(index));
    hookCleanup = onCleanup(@() clearFailureHook());
    verifyError(testCase, ...
        @() create_fig519_ihx_r2_hexe_shift_candidate(outputDir, repo), ...
        cases(index).error);
    clear hookCleanup
    clearFailureHook();
    verifyCallerState(testCase, state);
    verifyTrue(testCase, attackReplacementStillPresent(outputDir, ...
        cases(index).action));
    if cases(index).action == "install_symlink_directory"
        java.nio.file.Files.delete(java.nio.file.Paths.get(char(fullfile( ...
            outputDir, "injected-symlink-directory")), ...
            javaArray("java.lang.String", 0)));
    end
    clear cleanup
    cleanupOwnedOutput(owner, tmpRoot);
end
end

function present = attackReplacementStillPresent(outputDir, action)
switch action
    case "replace_hashed_candidate"
        present = ~isempty(dir(fullfile(outputDir, ...
            ".fig519a3-stage-*", "candidate.slx.replaced-*"))) && ...
            ~isempty(dir(fullfile(outputDir, ...
            ".fig519a3-stage-*", "candidate.slx")));
    case "replace_staging_directory"
        present = ~isempty(dir(fullfile(outputDir, ".fig519a3-stage-*"))) && ...
            ~isempty(dir(fullfile(outputDir, ".fig519a3-stage-*.replaced-*")));
    case "install_public_candidate"
        present = isfile(fullfile(outputDir, "candidate.slx"));
    case "install_symlink_directory"
        javaPath = java.nio.file.Paths.get(char(fullfile(outputDir, ...
            "injected-symlink-directory")), javaArray("java.lang.String", 0));
        present = java.nio.file.Files.isSymbolicLink(javaPath);
    case "replace_public_candidate"
        present = isfile(fullfile(outputDir, "candidate.slx")) && ...
            ~isempty(dir(fullfile(outputDir, "candidate.slx.replaced-*")));
    case "replace_audit_file"
        present = isfile(fullfile(outputDir, "patch_audit.json")) && ...
            ~isempty(dir(fullfile(outputDir, "patch_audit.json.replaced-*")));
    case "redirect_filegen"
        present = isfolder(fullfile(outputDir, "hook-filegen-redirect"));
    otherwise
        present = false;
end
end

function present = verifyMaskInventory(testCase, semantic)
present = all(isfield(semantic, ...
    ["mask_inventory", "mask_fingerprint", "mask_enabled_count"]));
verifyTrue(testCase, present);
if ~present
    return
end
inventory = semantic.mask_inventory;
verifyEqual(testCase, numel(inventory), semantic.block_count);
verifyTrue(testCase, all(isfield(inventory, ...
    ["path", "mask_enabled", "mask_type"])));
maskStates = string({inventory.mask_enabled});
verifyTrue(testCase, all(ismember(maskStates, ["on", "off"])));
verifyEqual(testCase, semantic.mask_enabled_count, sum(maskStates == "on"));
end

function paths = existingFormalPaths(repo, sourcePath, protectedManifest)
paths = [sourcePath; protectedManifest; ...
    fullfile(repo, "final_steady_24a.slx"); ...
    fullfile(repo, "final_dynamic_24a.slx")];
paths = paths(arrayfun(@isfile, paths));
end

function records = hashRecords(paths)
records = strings(numel(paths), 2);
for index = 1:numel(paths)
    records(index, :) = [canonicalPath(paths(index)), sha256File(paths(index))];
end
end

function tf = isRegularFile(pathValue)
javaPath = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
tf = java.nio.file.Files.isRegularFile(javaPath, ...
    javaArray("java.nio.file.LinkOption", 0)) && ...
    ~java.nio.file.Files.isSymbolicLink(javaPath);
end

function hash = sha256File(filePath)
before = fileIdentity(filePath);
digest = java.security.MessageDigest.getInstance("SHA-256");
javaPath = java.nio.file.Paths.get(char(filePath), ...
    javaArray("java.lang.String", 0));
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.READ;
options(2) = java.nio.file.LinkOption.NOFOLLOW_LINKS;
channel = java.nio.file.Files.newByteChannel(javaPath, options);
cleanup = onCleanup(@() channel.close());
buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
while true
    count = channel.read(buffer);
    if count < 0
        break
    end
    if count == 0
        continue
    end
    digest.update(buffer.array(), 0, count);
    buffer.clear();
end
channel.close();
clear cleanup
if fileIdentity(filePath) ~= before
    error("fig519a3test:HashIdentityChanged", ...
        "The test hash target was replaced while open.");
end
raw = digest.digest();
hash = string(lower(reshape(dec2hex(typecast(raw, "uint8"), 2).', 1, [])));
end

function owner = createOwnedTestSandbox(tmpRoot)
ownerPath = string(tempname(tmpRoot));
mkdir(ownerPath);
owner = claimOwnedTestSandbox(ownerPath, tmpRoot);
end

function owner = claimOwnedTestSandbox(ownerPath, tmpRoot)
owner.path = string(ownerPath);
owner.schema = "fig519a3_test_owner";
owner.version = 2;
owner.token = string(char(java.util.UUID.randomUUID));
owner.capability_text = "fig519a3_test_owner_v2:" + owner.token;
owner.token_path = fullfile(owner.path, ".fig519a3-test-owner");
writeOwnerTokenExclusive(owner.token_path, owner.capability_text + newline);
owner.file_key = fileIdentity(owner.path);
owner.token_file_key = fileIdentity(owner.token_path);
owner.posix_identity = posixPathIdentity(owner.path, "directory");
owner.token_posix_identity = posixPathIdentity(owner.token_path, "file");
owner.tmp_file_key = fileIdentity(tmpRoot);
owner.tmp_posix_identity = posixPathIdentity(tmpRoot, "directory");
end

function writeOwnerTokenExclusive(tokenPath, tokenText)
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
channel = java.nio.file.Files.newByteChannel(nioPath(tokenPath), options);
cleanup = onCleanup(@() channel.close());
bytes = unicode2native(char(tokenText), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(int8(bytes));
while buffer.hasRemaining()
    channel.write(buffer);
end
clear cleanup
channel.close();
end

function result = cleanupOwnedOutput(owner, tmpRoot, boundaryHook)
arguments
    owner
    tmpRoot
    boundaryHook = []
end
outputDir = string(owner.path);
result = struct("status", "absent", "path", outputDir, "reason", "");
if ~java.nio.file.Files.exists(nioPath(outputDir), noFollowOptions())
    return
end
try
    validateCleanupOwnerShape(owner);
    rootName = directChildName(outputDir, tmpRoot);
    tokenName = directChildName(owner.token_path, outputDir);
    os = py.importlib.import_module("os");
    % macOS's NIO provider lacks SecureDirectoryStream. These in-process
    % openat/unlinkat calls are the SecureDirectoryStream-equivalent gate.
    parentFd = openPathDirectoryNoFollow(os, tmpRoot);
    parentCleanup = onCleanup(@() closePythonFd(os, parentFd));
    assertPosixIdentity(posixFdIdentity(os, parentFd), ...
        owner.tmp_posix_identity, "tmp root");
    if fileIdentity(tmpRoot) ~= string(owner.tmp_file_key)
        error("fig519a3test:CleanupTmpIdentityChanged", ...
            "The cleanup tmp root fileKey changed.");
    end
    rootFd = openRelativeDirectoryNoFollow(os, parentFd, rootName);
    rootCleanup = onCleanup(@() closePythonFd(os, rootFd));
    assertPosixIdentity(posixFdIdentity(os, rootFd), ...
        owner.posix_identity, "owned root");
    assertRelativeIdentity(os, parentFd, rootName, ...
        owner.posix_identity, "owned root entry");
    if fileIdentity(outputDir) ~= string(owner.file_key)
        error("fig519a3test:CleanupRootFileKeyChanged", ...
            "The cleanup root fileKey changed.");
    end
    assertOwnedToken(os, rootFd, tokenName, owner);
    snapshot = snapshotDirectoryFd(os, rootFd);
    if ~isempty(boundaryHook)
        boundaryHook();
    end
    assertRelativeIdentity(os, parentFd, rootName, ...
        owner.posix_identity, "owned root deletion boundary");
    verifyDirectorySnapshotFd(os, rootFd, snapshot);
    deleteDirectorySnapshotFd(os, rootFd, snapshot, tokenName);
    assertRelativeIdentity(os, parentFd, rootName, ...
        owner.posix_identity, "owned root final boundary");
    os.rmdir(char(rootName), pyargs("dir_fd", parentFd));
    result.status = "deleted";
    clear rootCleanup parentCleanup
catch exception
    result.status = "retained_untrusted";
    result.reason = string(exception.identifier);
    fprintf(2, "Retained untrusted A3 test output: %s (%s)\n", ...
        outputDir, result.reason);
end
end

function paths = directTmpChildren(tmpRoot)
os = py.importlib.import_module("os");
parentFd = openPathDirectoryNoFollow(os, tmpRoot);
cleanup = onCleanup(@() closePythonFd(os, parentFd));
names = listFdNames(os, parentFd);
paths = fullfile(string(tmpRoot), names);
clear cleanup
closePythonFd(os, parentFd);
end

function report = cleanupVerifiedOwnedSandboxes(tmpRoot, candidatePaths, mode)
arguments
    tmpRoot
    candidatePaths
    mode {mustBeMember(mode, ["dry_run", "execute"])}
end
deleted = strings(0, 1);
retained = strings(0, 1);
verified = strings(0, 1);
for index = 1:numel(candidatePaths)
    candidatePath = string(candidatePaths(index));
    try
        owner = recoverOwnedTestSandbox(candidatePath, tmpRoot);
    catch
        retained(end + 1, 1) = candidatePath; %#ok<AGROW>
        continue
    end
    verified(end + 1, 1) = candidatePath; %#ok<AGROW>
    if mode == "dry_run"
        continue
    end
    result = cleanupOwnedOutput(owner, tmpRoot);
    if string(result.status) == "deleted"
        deleted(end + 1, 1) = candidatePath; %#ok<AGROW>
    else
        retained(end + 1, 1) = candidatePath; %#ok<AGROW>
    end
end
report = struct("verified_owned", verified, "deleted", deleted, ...
    "retained_untrusted", retained);
end

function owner = recoverOwnedTestSandbox(ownerPath, tmpRoot)
ownerPath = string(ownerPath);
rootName = directChildName(ownerPath, tmpRoot);
tokenName = ".fig519a3-test-owner";
os = py.importlib.import_module("os");
parentFd = openPathDirectoryNoFollow(os, tmpRoot);
parentCleanup = onCleanup(@() closePythonFd(os, parentFd));
tmpIdentity = posixFdIdentity(os, parentFd);
rootIdentity = posixRelativeIdentity(os, parentFd, rootName);
if rootIdentity.kind ~= "directory"
    error("fig519a3test:RecoveredOwnerKind", ...
        "Only real directories can carry an owned-test capability.");
end
rootFd = openRelativeDirectoryNoFollow(os, parentFd, rootName);
rootCleanup = onCleanup(@() closePythonFd(os, rootFd));
assertPosixIdentity(posixFdIdentity(os, rootFd), rootIdentity, ...
    "recovered owner root");
tokenIdentity = posixRelativeIdentity(os, rootFd, tokenName);
if tokenIdentity.kind ~= "file"
    error("fig519a3test:RecoveredTokenKind", ...
        "Recovered ownership tokens must be no-follow regular files.");
end
flags = bitor(int64(os.O_RDONLY), int64(os.O_NOFOLLOW));
tokenFd = os.open(char(tokenName), flags, pyargs("dir_fd", rootFd));
tokenCleanup = onCleanup(@() closePythonFd(os, tokenFd));
assertPosixIdentity(posixFdIdentity(os, tokenFd), tokenIdentity, ...
    "recovered owner token");
raw = os.read(tokenFd, int64(4096));
extra = os.read(tokenFd, int64(1));
capabilityText = strtrim(string(raw.decode("utf-8")));
uuidPattern = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
v2Match = regexp(char(capabilityText), ...
    ['^fig519a3_test_owner_v2:(' uuidPattern ')$'], 'tokens', 'once');
legacyMatch = regexp(char(capabilityText), ['^(' uuidPattern ')$'], ...
    'tokens', 'once');
if int64(py.len(extra)) ~= 0 || (isempty(v2Match) && isempty(legacyMatch))
    error("fig519a3test:RecoveredTokenInvalid", ...
        "Recovered ownership token is not an A3 owner capability.");
end
if ~isempty(v2Match)
    schema = "fig519a3_test_owner";
    version = 2;
    token = string(v2Match{1});
else
    schema = "fig519a3_test_owner_legacy";
    version = 1;
    token = string(legacyMatch{1});
    topNames = listFdNames(os, rootFd);
    if ~all(topNames == tokenName | topNames == "candidate-output")
        error("fig519a3test:RecoveredLegacyInventory", ...
            "Legacy A3 owners require the frozen top-level inventory.");
    end
    outputIndex = find(topNames == "candidate-output", 1);
    if ~isempty(outputIndex) && ...
            posixRelativeIdentity(os, rootFd, ...
            topNames(outputIndex)).kind ~= "directory"
        error("fig519a3test:RecoveredLegacyInventory", ...
            "Legacy candidate-output must be a real directory.");
    end
end
snapshotDirectoryFd(os, rootFd);
owner = struct("path", ownerPath, "schema", schema, ...
    "version", version, "token", token, ...
    "capability_text", capabilityText, ...
    "token_path", fullfile(ownerPath, tokenName), ...
    "file_key", fileIdentity(ownerPath), ...
    "token_file_key", fileIdentity(fullfile(ownerPath, tokenName)), ...
    "posix_identity", rootIdentity, ...
    "token_posix_identity", tokenIdentity, ...
    "tmp_file_key", fileIdentity(tmpRoot), ...
    "tmp_posix_identity", tmpIdentity);
assertRelativeIdentity(os, parentFd, rootName, rootIdentity, ...
    "recovered owner root boundary");
assertRelativeIdentity(os, rootFd, tokenName, tokenIdentity, ...
    "recovered owner token boundary");
clear tokenCleanup rootCleanup parentCleanup
closePythonFd(os, tokenFd);
closePythonFd(os, rootFd);
closePythonFd(os, parentFd);
end

function validateCleanupOwnerShape(owner)
required = ["path", "token", "token_path", "file_key", ...
    "token_file_key", "posix_identity", "token_posix_identity", ...
    "tmp_file_key", "tmp_posix_identity", "schema", "version", ...
    "capability_text"];
if ~isstruct(owner) || ~all(isfield(owner, required))
    error("fig519a3test:CleanupOwnerInvalid", ...
        "Safe cleanup requires the complete identity-bound owner record.");
end
v2 = string(owner.schema) == "fig519a3_test_owner" && ...
    double(owner.version) == 2 && ...
    string(owner.capability_text) == ...
    "fig519a3_test_owner_v2:" + string(owner.token);
legacy = string(owner.schema) == "fig519a3_test_owner_legacy" && ...
    double(owner.version) == 1 && ...
    string(owner.capability_text) == string(owner.token);
if ~(v2 || legacy)
    error("fig519a3test:CleanupOwnerSchema", ...
        "Safe cleanup requires the exact A3 owner schema/version.");
end
end

function name = directChildName(pathValue, parentValue)
pathObject = nioPath(pathValue).toAbsolutePath().normalize();
parentObject = nioPath(parentValue).toAbsolutePath().normalize();
relative = parentObject.relativize(pathObject);
if relative.getNameCount() ~= 1 || relative.isAbsolute() || ...
        string(relative.toString()) == ".."
    error("fig519a3test:CleanupContainment", ...
        "Safe cleanup targets must be direct lexical children.");
end
name = string(relative.toString());
end

function fd = openPathDirectoryNoFollow(os, pathValue)
flags = bitor(bitor(int64(os.O_RDONLY), int64(os.O_DIRECTORY)), ...
    int64(os.O_NOFOLLOW));
fd = os.open(char(string(pathValue)), flags);
end

function fd = openRelativeDirectoryNoFollow(os, parentFd, name)
flags = bitor(bitor(int64(os.O_RDONLY), int64(os.O_DIRECTORY)), ...
    int64(os.O_NOFOLLOW));
fd = os.open(char(name), flags, pyargs("dir_fd", parentFd));
end

function closePythonFd(os, fd)
try
    os.close(fd);
catch
end
end

function identity = posixPathIdentity(pathValue, kind)
os = py.importlib.import_module("os");
if kind == "directory"
    fd = openPathDirectoryNoFollow(os, pathValue);
else
    flags = bitor(int64(os.O_RDONLY), int64(os.O_NOFOLLOW));
    fd = os.open(char(string(pathValue)), flags);
end
cleanup = onCleanup(@() closePythonFd(os, fd));
identity = posixFdIdentity(os, fd);
if identity.kind ~= string(kind)
    error("fig519a3test:OwnerIdentityKind", ...
        "Owned path has the wrong no-follow POSIX kind.");
end
clear cleanup
closePythonFd(os, fd);
end

function identity = posixFdIdentity(os, fd)
identity = posixStatIdentity(os.fstat(fd));
end

function identity = posixRelativeIdentity(os, parentFd, name)
statResult = os.stat(char(name), pyargs("dir_fd", parentFd, ...
    "follow_symlinks", false));
identity = posixStatIdentity(statResult);
end

function identity = posixStatIdentity(statResult)
mode = uint64(statResult.st_mode);
kindBits = bitand(mode, uint64(61440));
if kindBits == uint64(16384)
    kind = "directory";
elseif kindBits == uint64(32768)
    kind = "file";
elseif kindBits == uint64(40960)
    kind = "symlink";
else
    kind = "other";
end
identity = struct("device", uint64(statResult.st_dev), ...
    "inode", uint64(statResult.st_ino), "kind", kind);
end

function assertPosixIdentity(actual, expected, label)
if actual.device ~= expected.device || actual.inode ~= expected.inode || ...
        actual.kind ~= string(expected.kind)
    error("fig519a3test:CleanupIdentityChanged", ...
        "%s changed before safe cleanup.", label);
end
end

function assertRelativeIdentity(os, parentFd, name, expected, label)
actual = posixRelativeIdentity(os, parentFd, name);
assertPosixIdentity(actual, expected, label);
end

function assertOwnedToken(os, rootFd, tokenName, owner)
assertRelativeIdentity(os, rootFd, tokenName, ...
    owner.token_posix_identity, "ownership token entry");
flags = bitor(int64(os.O_RDONLY), int64(os.O_NOFOLLOW));
tokenFd = os.open(char(tokenName), flags, pyargs("dir_fd", rootFd));
cleanup = onCleanup(@() closePythonFd(os, tokenFd));
assertPosixIdentity(posixFdIdentity(os, tokenFd), ...
    owner.token_posix_identity, "ownership token handle");
raw = os.read(tokenFd, int64(4096));
extra = os.read(tokenFd, int64(1));
if int64(py.len(extra)) ~= 0 || ...
        strtrim(string(raw.decode("utf-8"))) ~= string(owner.capability_text)
    error("fig519a3test:CleanupTokenChanged", ...
        "The exclusive ownership token changed.");
end
assertPosixIdentity(posixFdIdentity(os, tokenFd), ...
    owner.token_posix_identity, "ownership token handle");
if fileIdentity(owner.token_path) ~= string(owner.token_file_key)
    error("fig519a3test:CleanupTokenFileKeyChanged", ...
        "The ownership token fileKey changed.");
end
assertRelativeIdentity(os, rootFd, tokenName, ...
    owner.token_posix_identity, "ownership token entry");
clear cleanup
closePythonFd(os, tokenFd);
end

function snapshot = snapshotDirectoryFd(os, directoryFd)
snapshot = struct("identity", posixFdIdentity(os, directoryFd), ...
    "entries", []);
names = listFdNames(os, directoryFd);
entries = repmat(struct("name", "", "identity", struct(), ...
    "snapshot", []), 0, 1);
for index = 1:numel(names)
    name = names(index);
    identity = posixRelativeIdentity(os, directoryFd, name);
    nested = [];
    if identity.kind == "directory"
        childFd = openRelativeDirectoryNoFollow(os, directoryFd, name);
        childCleanup = onCleanup(@() closePythonFd(os, childFd));
        assertPosixIdentity(posixFdIdentity(os, childFd), identity, ...
            "snapshot directory");
        nested = snapshotDirectoryFd(os, childFd);
        clear childCleanup
        closePythonFd(os, childFd);
    elseif identity.kind ~= "file" && identity.kind ~= "symlink"
        error("fig519a3test:CleanupUnsupportedEntry", ...
            "Owned cleanup trees may contain only files, directories, or symlinks.");
    end
    entries(end + 1, 1) = struct("name", name, ...
        "identity", identity, "snapshot", nested); %#ok<AGROW>
end
snapshot.entries = entries;
end

function names = listFdNames(os, directoryFd)
values = cell(os.listdir(directoryFd));
names = strings(numel(values), 1);
for index = 1:numel(values)
    names(index) = string(values{index});
    if names(index) == "." || names(index) == ".." || ...
            contains(names(index), "/")
        error("fig519a3test:CleanupEntryName", ...
            "Unsafe directory entry name encountered.");
    end
end
names = sort(names);
end

function verifyDirectorySnapshotFd(os, directoryFd, snapshot)
assertPosixIdentity(posixFdIdentity(os, directoryFd), ...
    snapshot.identity, "snapshot directory handle");
names = listFdNames(os, directoryFd);
expectedNames = reshape(string({snapshot.entries.name}), [], 1);
if ~isequal(names, expectedNames)
    error("fig519a3test:CleanupInventoryChanged", ...
        "Directory inventory changed at the deletion boundary.");
end
for index = 1:numel(snapshot.entries)
    entry = snapshot.entries(index);
    assertRelativeIdentity(os, directoryFd, entry.name, ...
        entry.identity, "snapshot entry");
    if entry.identity.kind == "directory"
        childFd = openRelativeDirectoryNoFollow(os, directoryFd, entry.name);
        childCleanup = onCleanup(@() closePythonFd(os, childFd));
        verifyDirectorySnapshotFd(os, childFd, entry.snapshot);
        clear childCleanup
        closePythonFd(os, childFd);
    end
end
end

function deleteDirectorySnapshotFd(os, directoryFd, snapshot, tokenName)
verifyDirectorySnapshotFd(os, directoryFd, snapshot);
entries = snapshot.entries;
if strlength(tokenName) > 0 && ~isempty(entries)
    tokenIndex = find(string({entries.name}) == tokenName, 1);
    if ~isempty(tokenIndex)
        entries = [entries(1:tokenIndex - 1); entries(tokenIndex + 1:end); ...
            entries(tokenIndex)];
    end
end
for index = 1:numel(entries)
    entry = entries(index);
    assertRelativeIdentity(os, directoryFd, entry.name, ...
        entry.identity, "entry deletion boundary");
    if entry.identity.kind == "directory"
        childFd = openRelativeDirectoryNoFollow(os, directoryFd, entry.name);
        childCleanup = onCleanup(@() closePythonFd(os, childFd));
        assertPosixIdentity(posixFdIdentity(os, childFd), ...
            entry.identity, "directory deletion handle");
        deleteDirectorySnapshotFd(os, childFd, entry.snapshot, "");
        assertRelativeIdentity(os, directoryFd, entry.name, ...
            entry.identity, "directory final deletion boundary");
        os.rmdir(char(entry.name), pyargs("dir_fd", directoryFd));
        clear childCleanup
        closePythonFd(os, childFd);
    else
        os.unlink(char(entry.name), pyargs("dir_fd", directoryFd));
    end
end
if ~isempty(listFdNames(os, directoryFd))
    error("fig519a3test:CleanupDirectoryNotEmpty", ...
        "A replacement appeared during handle-relative cleanup.");
end
end

function key = fileIdentity(pathValue)
javaPath = nioPath(pathValue);
attributes = java.nio.file.Files.readAttributes(javaPath, ...
    "basic:fileKey", noFollowOptions());
key = string(attributes.get("fileKey"));
end

function javaPath = nioPath(pathValue)
javaPath = java.nio.file.Paths.get(char(string(pathValue)), ...
    javaArray("java.lang.String", 0));
end

function options = noFollowOptions()
options = javaArray("java.nio.file.LinkOption", 1);
options(1) = java.nio.file.LinkOption.NOFOLLOW_LINKS;
end

function state = callerState()
state = struct("folder", string(pwd), "matlab_path", string(path), ...
    "loaded", string(find_system("Type", "block_diagram")), ...
    "filegen", Simulink.fileGenControl("getConfig"), ...
    "base", captureBaseWorkspaceSnapshot());
end

function verifyCallerState(testCase, state)
verifyEqual(testCase, string(pwd), state.folder);
verifyEqual(testCase, string(path), state.matlab_path);
verifyEqual(testCase, string(find_system("Type", "block_diagram")), state.loaded);
actual = Simulink.fileGenControl("getConfig");
verifyEqual(testCase, string(actual.CacheFolder), ...
    string(state.filegen.CacheFolder));
verifyEqual(testCase, string(actual.CodeGenFolder), ...
    string(state.filegen.CodeGenFolder));
verifyTrue(testCase, baseWorkspaceSnapshotsEqual(state.base, ...
    captureBaseWorkspaceSnapshot()));
end

function snapshot = captureBaseWorkspaceSnapshot()
names = string(evalin("base", "who"));
snapshot = repmat(struct("name", "", "value", []), numel(names), 1);
for index = 1:numel(names)
    snapshot(index).name = names(index);
    snapshot(index).value = evalin("base", names(index));
end
end

function tf = baseWorkspaceSnapshotsEqual(before, after)
tf = isequal(string({before.name}), string({after.name}));
if ~tf
    return
end
for index = 1:numel(before)
    if ~isequaln(before(index).value, after(index).value)
        tf = false;
        return
    end
end
end

function clearFailureHook()
if isappdata(0, "fig519a3_test_failure_point")
    rmappdata(0, "fig519a3_test_failure_point");
end
end

function installTestHook(owner, hook)
hook.capability_path = owner.token_path;
hook.capability_token = owner.capability_text;
hook.capability_file_key = fileIdentity(owner.token_path);
hook.run_parent = owner.path;
hook.run_parent_file_key = owner.file_key;
setappdata(0, "fig519a3_test_failure_point", hook);
end

function mode = posixMode(pathValue)
permissions = java.nio.file.Files.getPosixFilePermissions( ...
    java.nio.file.Paths.get(char(pathValue), javaArray("java.lang.String", 0)), ...
    javaArray("java.nio.file.LinkOption", 0));
mode = string(java.nio.file.attribute.PosixFilePermissions.toString(permissions));
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end
