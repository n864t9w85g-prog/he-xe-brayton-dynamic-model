function tests = test_build_rotating_map_candidate_bundles
%TEST_BUILD_ROTATING_MAP_CANDIDATE_BUNDLES C0-C3 coordinate contract.
tests = functiontests(localfunctions);
end

function testBuildsExactFourCaseBundles(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
outputDir = newOutput(repoRoot);
cleanup = onCleanup(@() cleanupOutput(outputDir, repoRoot)); %#ok<NASGU>
protected = [fullfile(repoRoot, "hexe_compressor_lookup.mat"); ...
    fullfile(repoRoot, "turbine_table1.mat"); ...
    fullfile(repoRoot, "turbine_table2.mat")];
before = arrayfun(@sha256File, protected);

result = build_rotating_map_candidate_bundles(repoRoot, outputDir);

verifyEqual(testCase, string(result.schema), ...
    "rotating_map_candidate_bundles_v1");
verifyEqual(testCase, string({result.cases.case_id}), ...
    ["C0", "C1", "C2", "C3"]);
verifyEqual(testCase, string({result.cases.compressor_source}), ...
    ["current", "recovered_candidate", "current", ...
     "recovered_candidate"]);
verifyEqual(testCase, string({result.cases.turbine_source}), ...
    ["current", "current", "recovered_candidate", ...
     "recovered_candidate"]);
verifyEqual(testCase, arrayfun(@sha256File, protected), before);
verifyTrue(testCase, isfile(fullfile(outputDir, "bundle_manifest.json")));

currentCompressor = load(fullfile(repoRoot, "hexe_compressor_lookup.mat"));
currentTurbineFlow = load(fullfile(repoRoot, "turbine_table1.mat"));
currentTurbineEfficiency = load(fullfile(repoRoot, "turbine_table2.mat"));
candidate = load(fullfile(repoRoot, "data", "provenance", ...
    "rotating_machinery", "recovered_20260902", "source", ...
    "Xu2022_PaperStyle_Equivalent_Lookup.mat"));

c0 = load(fullfile(outputDir, "C0_lookup.mat"));
c1 = load(fullfile(outputDir, "C1_lookup.mat"));
c2 = load(fullfile(outputDir, "C2_lookup.mat"));
c3 = load(fullfile(outputDir, "C3_lookup.mat"));
verifyEqual(testCase, c0.compressor_speed_bp, ...
    currentCompressor.speed_bp);
verifyEqual(testCase, c0.compressor_flow_bp, ...
    currentCompressor.m_ratio_bp);
verifyEqual(testCase, c0.compressor_pr_table, ...
    currentCompressor.PR_table);
verifyEqual(testCase, c0.compressor_eta_table, ...
    currentCompressor.ETAT_table);
verifyEqual(testCase, c0.turbine_flow_table, ...
    currentTurbineFlow.table_mf);
verifyEqual(testCase, c0.turbine_eta_table, ...
    currentTurbineEfficiency.table_eff);

verifyEqual(testCase, c1.compressor_speed_bp, ...
    candidate.N_bp / 55090, "AbsTol", 0);
verifyEqual(testCase, c1.compressor_flow_bp, ...
    candidate.mC_bp / 12.04, "AbsTol", 0);
verifyEqual(testCase, c1.compressor_pr_table, candidate.PRc_tbl);
verifyEqual(testCase, c1.compressor_eta_table, candidate.etac_tbl);
verifyEqual(testCase, c1.turbine_flow_table, c0.turbine_flow_table);
verifyEqual(testCase, c1.turbine_eta_table, c0.turbine_eta_table);

verifyEqual(testCase, c2.compressor_pr_table, c0.compressor_pr_table);
verifyEqual(testCase, c2.compressor_eta_table, c0.compressor_eta_table);
verifyEqual(testCase, c2.turbine_er_bp, candidate.PRt_bp(:));
verifyEqual(testCase, c2.turbine_speed_bp, candidate.N_bp(:));
verifyEqual(testCase, c2.turbine_flow_table, candidate.mT_tbl.');
verifyEqual(testCase, c2.turbine_mf_bp, candidate.mT_bp(:));
verifyEqual(testCase, c2.turbine_eta_table, candidate.etat_tbl.');
verifyEqual(testCase, c3.compressor_pr_table, c1.compressor_pr_table);
verifyEqual(testCase, c3.turbine_flow_table, c2.turbine_flow_table);

targetFlow = 12.022308;
candidateDirect = interp2(candidate.mC_bp, candidate.N_bp, ...
    candidate.PRc_tbl, targetFlow, 55090);
candidateMapped = interp2(c1.compressor_flow_bp, ...
    c1.compressor_speed_bp, c1.compressor_pr_table, ...
    targetFlow / 12.04, 1);
verifyEqual(testCase, candidateMapped, candidateDirect, ...
    "AbsTol", 10 * eps(candidateDirect));
candidateTurbineDirect = interp2(candidate.PRt_bp, candidate.N_bp, ...
    candidate.mT_tbl, 1.539 / 0.676, 55090);
candidateTurbineMapped = interp2(c2.turbine_speed_bp, ...
    c2.turbine_er_bp, c2.turbine_flow_table, ...
    55090, 1.539 / 0.676);
verifyEqual(testCase, candidateTurbineMapped, candidateTurbineDirect, ...
    "AbsTol", 10 * eps(candidateTurbineDirect));

for bundle = {c0, c1, c2, c3}
    contract = bundle{1}.bundle_contract;
    verifyFalse(testCase, contract.surface_smoothed);
    verifyFalse(testCase, contract.parameter_fitted);
    verifyFalse(testCase, contract.formal_promotion);
    verifyEqual(testCase, contract.compressor_input_order, ...
        ["normalized_speed", "normalized_mass_flow"]);
    verifyEqual(testCase, contract.turbine_flow_input_order, ...
        ["expansion_ratio", "speed_rpm"]);
    verifyEqual(testCase, contract.turbine_efficiency_input_order, ...
        ["mass_flow_kg_s", "speed_rpm"]);
end
end

function outputDir = newOutput(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
outputDir = string(tempname(tmpRoot));
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
