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
end

function testCleanupRetainsOwnedNonemptyAndFinalBoundaryReplacement(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
owner = createOwnedTestSandbox(tmpRoot);
ownedOutput = fullfile(owner.path, "candidate-output");
mkdir(ownedOutput);
writelines("owned", fullfile(ownedOutput, "owned.txt"));
cleanupOwnedOutput(owner, tmpRoot);
verifyTrue(testCase, isfolder(owner.path));
verifyTrue(testCase, isfile(fullfile(ownedOutput, "owned.txt")));

boundary = @() replaceAtCleanupBoundary(owner.path);
cleanupOwnedOutput(owner, tmpRoot, boundary);
verifyTrue(testCase, isfolder(owner.path));
verifyTrue(testCase, isfile(fullfile(owner.path, "replacement.txt")));
end

function replaceAtCleanupBoundary(pathValue)
displaced = pathValue + "-owned-before-boundary";
movefile(pathValue, displaced);
mkdir(pathValue);
writelines("replacement", fullfile(pathValue, "replacement.txt"));
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
owner.path = string(tempname(tmpRoot));
mkdir(owner.path);
owner.token = string(char(java.util.UUID.randomUUID));
owner.token_path = fullfile(owner.path, ".fig519a3-test-owner");
writelines(owner.token, owner.token_path);
owner.file_key = fileIdentity(owner.path);
end

function cleanupOwnedOutput(owner, tmpRoot, boundaryHook)
arguments
    owner
    tmpRoot
    boundaryHook = []
end
outputDir = string(owner.path);
if ~isfolder(outputDir)
    return
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalOutput = canonicalPath(outputDir);
javaPath = java.nio.file.Paths.get(char(outputDir), ...
    javaArray("java.lang.String", 0));
if canonicalOutput == canonicalTmp || ...
        ~startsWith(canonicalOutput, canonicalTmp + filesep) || ...
        java.nio.file.Files.isSymbolicLink(javaPath) || ...
        fileIdentity(outputDir) ~= string(owner.file_key) || ...
        ~isfile(owner.token_path) || ...
        strtrim(string(fileread(owner.token_path))) ~= string(owner.token) || ...
        ~treeMatchesOwnedInventory(outputDir)
    fprintf(2, "Retained untrusted A3 test output: %s\n", outputDir);
    return
end
if ~isempty(boundaryHook)
    boundaryHook();
end
fprintf(2, "Retained nonempty A3 test output for external cleanup: %s\n", ...
    outputDir);
end

function tf = treeMatchesOwnedInventory(root)
items = dir(fullfile(root, "**", "*"));
items = items(~ismember({items.name}, {'.', '..'}));
tf = true;
for index = 1:numel(items)
    candidate = fullfile(items(index).folder, items(index).name);
    javaPath = java.nio.file.Paths.get(char(candidate), ...
        javaArray("java.lang.String", 0));
    regular = java.nio.file.Files.isRegularFile(javaPath, ...
        javaArray("java.nio.file.LinkOption", 0));
    directory = java.nio.file.Files.isDirectory(javaPath, ...
        javaArray("java.nio.file.LinkOption", 0));
    if java.nio.file.Files.isSymbolicLink(javaPath) || ...
            (~regular && ~directory) || ...
            ~startsWith(canonicalPath(candidate), canonicalPath(root) + filesep)
        tf = false;
        return
    end
end
top = dir(root);
top = string({top(~ismember({top.name}, {'.', '..'})).name});
tf = all(top == ".fig519a3-test-owner" | ...
    top == "candidate-output");
end

function key = fileIdentity(pathValue)
javaPath = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
attributes = java.nio.file.Files.readAttributes(javaPath, ...
    "basic:fileKey", javaArray("java.nio.file.LinkOption", 0));
key = string(attributes.get("fileKey"));
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
hook.capability_token = owner.token;
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
