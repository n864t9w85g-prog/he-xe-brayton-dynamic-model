function tests = test_create_rotating_map_candidate_models
%TEST_CREATE_ROTATING_MAP_CANDIDATE_MODELS API-only temporary SLX contract.
tests = functiontests(localfunctions);
end

function testCreatesFourApiPatchedModelsAndLeavesFormalFilesUntouched(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
parent = newOutput(repoRoot);
cleanup = onCleanup(@() cleanupOutput(parent, repoRoot)); %#ok<NASGU>
bundleDir = fullfile(parent, "bundles");
modelDir = fullfile(parent, "models");
build_rotating_map_candidate_bundles(repoRoot, bundleDir);
formal = formalPaths(repoRoot);
before = arrayfun(@sha256File, formal);

result = create_rotating_map_candidate_models(repoRoot, bundleDir, modelDir);

verifyEqual(testCase, string(result.schema), ...
    "rotating_map_candidate_models_v1");
verifyEqual(testCase, string({result.cases.case_id}), ...
    ["C0", "C1", "C2", "C3"]);
verifyEqual(testCase, arrayfun(@sha256File, formal), before);
verifyEqual(testCase, [result.cases.changed_parameter_count], ...
    [12, 12, 12, 12]);
verifyTrue(testCase, all([result.cases.block_inventory_unchanged]));
verifyTrue(testCase, all([result.cases.topology_unchanged]));
verifyTrue(testCase, all([result.cases.solver_unchanged]));
verifyTrue(testCase, all([result.cases.update_diagram_passed]));
verifyEqual(testCase, [result.cases.simulation_call_count], [0, 0, 0, 0]);
verifyFalse(testCase, result.formal_promotion);
verifyTrue(testCase, isfile(fullfile(modelDir, "model_manifest.json")));

for caseId = ["C0", "C1", "C2", "C3"]
    modelPath = fullfile(modelDir, caseId + "_model.slx");
    verifyTrue(testCase, isfile(modelPath));
    model = caseId + "_model";
    verifyFalse(testCase, bdIsLoaded(model));
    load_system(modelPath);
    modelCleanup = onCleanup(@() closeIfLoaded(model)); %#ok<NASGU>
    expected = expectedLookupParameters(model);
    verifyEqual(testCase, expected.values, expected.required);
    close_system(model, 0);
    clear modelCleanup
end

source = lower(fileread(fullfile(repoRoot, "tests", ...
    "create_rotating_map_candidate_models.m")));
verifyFalse(testCase, contains(source, "blockdiagram.xml"));
verifyFalse(testCase, contains(source, "system_"));
verifyFalse(testCase, contains(source, "unzip("));
verifyTrue(testCase, contains(source, "set_param"));
verifyTrue(testCase, contains(source, "save_system"));
end

function result = expectedLookupParameters(model)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "Lookup_n-D"));
isTAC = startsWith(blocks, model + "/TAC/");
blocks = blocks(isTAC);
values = strings(0, 4);
for index = 1:numel(blocks)
    tableExpression = string(get_param(blocks(index), "Table"));
    if any(tableExpression == ["compressor_eta_table", ...
            "compressor_pr_table", "turbine_flow_table", ...
            "turbine_eta_table"])
        values(end + 1, :) = [tableExpression, ... %#ok<AGROW>
            string(get_param(blocks(index), "BreakpointsForDimension1")), ...
            string(get_param(blocks(index), "BreakpointsForDimension2")), ...
            relativeBlockPath(blocks(index), model)];
    end
end
values = sortrows(values, 1);
required = sortrows([ ...
    "compressor_eta_table", "compressor_speed_bp", ...
        "compressor_flow_bp", "TAC/Compressor/2-D Lookup" + newline + "Table1"; ...
    "compressor_pr_table", "compressor_speed_bp", ...
        "compressor_flow_bp", "TAC/Compressor/2-D Lookup" + newline + "Table3"; ...
    "turbine_eta_table", "turbine_mf_bp", ...
        "turbine_speed_bp", "TAC/Turbine/2-D Lookup" + newline + "Table1"; ...
    "turbine_flow_table", "turbine_er_bp", ...
        "turbine_speed_bp", "TAC/Turbine/2-D Lookup" + newline + "Table"], 1);
result = struct("values", values, "required", required);
end

function value = relativeBlockPath(pathValue, model)
prefix = model + "/";
value = extractAfter(string(pathValue), strlength(prefix));
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function paths = formalPaths(repoRoot)
paths = [fullfile(repoRoot, "final_steady_24a.slx"); ...
    fullfile(repoRoot, "hexe_compressor_lookup.mat"); ...
    fullfile(repoRoot, "turbine_table1.mat"); ...
    fullfile(repoRoot, "turbine_table2.mat"); ...
    fullfile(repoRoot, "HeXe_property_simulink.m")];
dynamic = fullfile(repoRoot, "final_dynamic_24a.slx");
if isfile(dynamic)
    paths(end + 1, 1) = dynamic;
end
end

function outputDir = newOutput(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
outputDir = string(tempname(tmpRoot));
mkdir(outputDir);
end

function cleanupOutput(outputDir, repoRoot)
if ~isfolder(outputDir)
    return
end
tmpRoot = string(java.io.File(fullfile(repoRoot, "tmp")).getCanonicalPath());
candidate = string(java.io.File(outputDir).getCanonicalPath());
if ~startsWith(candidate, tmpRoot + filesep)
    error("rotatingMapTest:UnsafeCleanup", ...
        "Refusing to delete a directory outside repository tmp.");
end
rmdir(candidate, "s");
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end
