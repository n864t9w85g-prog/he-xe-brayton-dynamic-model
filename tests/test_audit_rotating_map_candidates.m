function tests = test_audit_rotating_map_candidates
%TEST_AUDIT_ROTATING_MAP_CANDIDATES Gate 1 offline map audit contract.
tests = functiontests(localfunctions);
end

function testValidCurrentAndRecoveredCandidate(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
outputDir = newOutput(repoRoot);
cleanup = onCleanup(@() cleanupOutput(outputDir, repoRoot)); %#ok<NASGU>

out = audit_rotating_map_candidates(repoRoot, outputDir);

verifyEqual(testCase, string(out.schema), "rotating_map_offline_audit_v1");
verifyTrue(testCase, out.current.compressor.pr_all_rows_strictly_decreasing);
verifyTrue(testCase, out.candidate.compressor.design_has_interior_pr_peak);
verifyLessThanOrEqual(testCase, out.candidate.design.max_relative_error, 0.05);
verifyTrue(testCase, out.candidate.domain.covers_all_required_speeds);
verifyEqual(testCase, out.simulation_call_count, 0);
verifyFalse(testCase, out.paper_reproduced);
verifyFalse(testCase, out.author_original_lookup_recovered);
verifyFalse(testCase, out.formal_promotion);
verifyTrue(testCase, isfile(fullfile(outputDir, "offline_map_audit.json")));
verifyTrue(testCase, isfile(fullfile(outputDir, "offline_map_summary.csv")));
verifyTrue(testCase, isfile(fullfile(outputDir, "offline_map_comparison.png")));
end

function testInvalidCandidateSurfacesFailClosed(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
source = fullfile(repoRoot, "data", "provenance", "rotating_machinery", ...
    "recovered_20260902", "source", ...
    "Xu2022_PaperStyle_Equivalent_Lookup.mat");
original = load(source);
mutations = {@withNaN, @withWrongOrientation, @withBadEfficiency};
for index = 1:numel(mutations)
    fixture = original;
    fixture = mutations{index}(fixture);
    fixturePath = string(tempname(fullfile(repoRoot, "tmp"))) + ".mat";
    outputDir = newOutput(repoRoot);
    cleanup = onCleanup(@() cleanupFixture( ...
        fixturePath, outputDir, repoRoot)); %#ok<NASGU>
    save(fixturePath, "-struct", "fixture");
    verifyError(testCase, @() audit_rotating_map_candidates( ...
        repoRoot, outputDir, fixturePath), "rotatingMap:InvalidCandidate");
    delete(fixturePath);
    clear cleanup
end
end

function value = withNaN(value)
value.PRc_tbl(1) = NaN;
end

function value = withWrongOrientation(value)
value.PRc_tbl = value.PRc_tbl.';
end

function value = withBadEfficiency(value)
value.etac_tbl(1) = 1.01;
end

function outputDir = newOutput(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
outputDir = string(tempname(tmpRoot));
end

function cleanupFixture(fixturePath, outputDir, repoRoot)
if isfile(fixturePath)
    delete(fixturePath);
end
cleanupOutput(outputDir, repoRoot);
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
