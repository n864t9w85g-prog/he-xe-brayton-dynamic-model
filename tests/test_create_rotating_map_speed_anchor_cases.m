function tests = test_create_rotating_map_speed_anchor_cases
%TEST_CREATE_ROTATING_MAP_SPEED_ANCHOR_CASES Single-variable API patch.
tests = functiontests(localfunctions);
end

function testPatchesOnlyTheCommonSpeedAnchor(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
sourceRoot = fullfile(repoRoot, "tmp", ...
    "rotating_map_candidate_A_20260902");
verifyTrue(testCase, isfolder(fullfile(sourceRoot, "models")));
outputRoot = string(tempname(fullfile(repoRoot, "tmp")));
cleanup = onCleanup(@() cleanupOutput(outputRoot, repoRoot)); %#ok<NASGU>
formalBefore = sha256File(fullfile(repoRoot, "final_steady_24a.slx"));

manifest = create_rotating_map_speed_anchor_cases( ...
    repoRoot, sourceRoot, outputRoot);

verifyEqual(testCase, string({manifest.cases.case_id}), ...
    ["C0", "C1", "C2", "C3"]);
verifyEqual(testCase, [manifest.cases.old_speed_rpm], ...
    [66100, 66100, 66100, 66100]);
verifyEqual(testCase, [manifest.cases.new_speed_rpm], ...
    [55090, 55090, 55090, 55090]);
verifyEqual(testCase, manifest.changed_physical_parameter_count, 1);
verifyEqual(testCase, ...
    sha256File(fullfile(repoRoot, "final_steady_24a.slx")), formalBefore);
for caseId = ["C0", "C1", "C2", "C3"]
    modelPath = fullfile(outputRoot, "models", caseId + "_model.slx");
    load_system(modelPath);
    cleanupModel = onCleanup(@() closeIfLoaded(caseId + "_model")); %#ok<NASGU>
    verifyEqual(testCase, string(get_param( ...
        caseId + "_model/TAC/Constant", "Value")), "55090");
    close_system(caseId + "_model", 0);
    clear cleanupModel
end
end

function cleanupOutput(outputRoot, repoRoot)
if ~isfolder(outputRoot)
    return
end
tmpRoot = string(java.io.File(fullfile(repoRoot, "tmp")).getCanonicalPath());
candidate = string(java.io.File(outputRoot).getCanonicalPath());
if ~startsWith(candidate, tmpRoot + filesep)
    error("rotatingMapTest:UnsafeCleanup", ...
        "Refusing to delete outside repository tmp.");
end
rmdir(candidate, "s");
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

