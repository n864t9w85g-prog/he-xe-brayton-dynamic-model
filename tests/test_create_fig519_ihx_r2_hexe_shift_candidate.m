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
outputDir = string(tempname(tmpRoot));
cleanup = onCleanup(@() cleanupOwnedOutput(outputDir, tmpRoot));

sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
protectedManifest = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "protected_manifest_recovery.csv");
formalPaths = existingFormalPaths(repo, sourcePath, protectedManifest);
before = hashRecords(formalPaths);

audit = create_fig519_ihx_r2_hexe_shift_candidate(outputDir, repo);

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

candidatePath = fullfile(outputDir, "candidate.slx");
auditPath = fullfile(outputDir, "patch_audit.json");
verifyTrue(testCase, isRegularFile(candidatePath));
verifyTrue(testCase, isRegularFile(auditPath));
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
digest = java.security.MessageDigest.getInstance("SHA-256");
stream = java.io.BufferedInputStream(java.io.FileInputStream(char(filePath)));
cleanup = onCleanup(@() stream.close());
buffer = zeros(1, 1024 * 1024, "int8");
while true
    count = stream.read(buffer, 0, numel(buffer));
    if count < 0
        break
    end
    digest.update(buffer(1:count));
end
raw = digest.digest();
hash = string(lower(reshape(dec2hex(typecast(raw, "uint8"), 2).', 1, [])));
end

function cleanupOwnedOutput(outputDir, tmpRoot)
if ~isfolder(outputDir)
    return
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalOutput = canonicalPath(outputDir);
javaPath = java.nio.file.Paths.get(char(outputDir), ...
    javaArray("java.lang.String", 0));
if canonicalOutput == canonicalTmp || ...
        ~startsWith(canonicalOutput, canonicalTmp + filesep) || ...
        java.nio.file.Files.isSymbolicLink(javaPath)
    error("fig519a3test:UnsafeCleanup", ...
        "Refusing to remove an unowned or symlinked output path.");
end
rmdir(outputDir, "s");
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end
