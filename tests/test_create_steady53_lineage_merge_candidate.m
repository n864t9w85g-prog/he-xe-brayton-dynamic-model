function tests = test_create_steady53_lineage_merge_candidate
%TEST_CREATE_STEADY53_LINEAGE_MERGE_CANDIDATE Zero-simulation contract.
tests = functiontests(localfunctions);
end

function testBuildsExactFortyStateCandidateWithoutSimulation(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
outputDir = newOwnedOutput(repoRoot);
cleanup = onCleanup(@() cleanupOwnedOutput(outputDir, repoRoot)); %#ok<NASGU>

protected = formalPaths(repoRoot);
before = hashRecords(protected);
audit = create_steady53_lineage_merge_candidate(outputDir, repoRoot);
after = hashRecords(protected);

verifyEqual(testCase, before, after);
verifyEqual(testCase, string(audit.schema), ...
    "steady53_lineage_merge_candidate_v1");
verifyEqual(testCase, audit.state_count, 40);
verifyEqual(testCase, audit.assigned_state_count, 40);
verifyEqual(testCase, audit.changed_state_count, 39);
verifyEqual(testCase, audit.unchanged_state_count, 1);
verifyEqual(testCase, numel(audit.state_assignments), 40);
verifyTrue(testCase, all([audit.state_assignments.candidate_matches_root]));
unchanged = audit.state_assignments(~[audit.state_assignments.value_changed]);
verifyEqual(testCase, numel(unchanged), 1);
verifyEqual(testCase, string(unchanged.relative_path), ...
    "TAC/rotor/N_rpm_Integrator");
verifyEqual(testCase, unique(string({audit.changes.parameter})), ...
    "InitialCondition");
verifyEqual(testCase, string(audit.root_model_sha256), ...
    "a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159");
verifyEqual(testCase, string(audit.frozen_model_sha256), ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyTrue(testCase, audit.block_inventory_unchanged);
verifyTrue(testCase, audit.topology_unchanged);
verifyTrue(testCase, audit.non_ic_dialog_parameters_unchanged);
verifyTrue(testCase, audit.solver_parameters_unchanged);
verifyEqual(testCase, audit.simulation_call_count, 0);
verifyFalse(testCase, audit.paper_reproduced);
verifyFalse(testCase, audit.author_initial_state_identified);
verifyFalse(testCase, audit.formal_promotion);

candidatePath = fullfile(outputDir, "candidate.slx");
auditPath = fullfile(outputDir, "candidate_audit.json");
verifyTrue(testCase, isfile(candidatePath));
verifyTrue(testCase, isfile(auditPath));
verifyFalse(testCase, isfile(fullfile(outputDir, "raw_result.mat")));
verifyFalse(testCase, isfolder(fullfile(outputDir, "run")));
verifyFalse(testCase, bdIsLoaded("candidate"));
verifyFalse(testCase, bdIsLoaded("final_steady_24a"));

decoded = jsondecode(fileread(auditPath));
verifyEqual(testCase, string(decoded.schema), string(audit.schema));
verifyEqual(testCase, decoded.assigned_state_count, 40);
verifyEqual(testCase, decoded.changed_state_count, 39);
verifyEqual(testCase, string(decoded.candidate_model_sha256), ...
    string(audit.candidate_model_sha256));

source = lower(fileread(fullfile(repoRoot, "tests", ...
    "create_steady53_lineage_merge_candidate.m")));
verifyFalse(testCase, contains(source, "run_steady53_case"));
verifyFalse(testCase, contains(source, "simulationcommand"));
verifyFalse(testCase, contains(source, "sim("));
end

function testRefusesToOverwriteExistingOutput(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
outputDir = newOwnedOutput(repoRoot);
cleanup = onCleanup(@() cleanupOwnedOutput(outputDir, repoRoot)); %#ok<NASGU>
mkdir(outputDir);
writelines("sentinel", fullfile(outputDir, "sentinel.txt"));

verifyError(testCase, ...
    @() create_steady53_lineage_merge_candidate(outputDir, repoRoot), ...
    "lineagemerge:OutputExists");
verifyEqual(testCase, strtrim(string(fileread( ...
    fullfile(outputDir, "sentinel.txt")))), "sentinel");
end

function testRunnerCallsInjectedCaseExactlyOnce(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
outputDir = newOwnedOutput(repoRoot);
cleanup = onCleanup(@() cleanupOwnedOutput(outputDir, repoRoot)); %#ok<NASGU>
create_steady53_lineage_merge_candidate(outputDir, repoRoot);
candidateHashBefore = sha256File(fullfile(outputDir, "candidate.slx"));
calls = 0;

status = run_steady53_lineage_merge_diagnostic( ...
    outputDir, repoRoot, @fakeRunner);

verifyEqual(testCase, calls, 1);
verifyEqual(testCase, status.run_steady53_case_call_count, 1);
verifyEqual(testCase, status.retry_count, 0);
verifyEqual(testCase, status.final_time_s, 500);
verifyEqual(testCase, string(status.experiment_status), "completed_success");
verifyTrue(testCase, status.raw_result_present);
verifyTrue(testCase, status.curves_present);
verifyFalse(testCase, status.paper_reproduced);
verifyFalse(testCase, status.author_initial_state_identified);
verifyFalse(testCase, status.formal_promotion);
verifyEqual(testCase, sha256File(fullfile(outputDir, "candidate.slx")), ...
    candidateHashBefore);

actual = readmatrix(status.curves_path, "NumHeaderLines", 1, ...
    "OutputType", "double");
expected = [ ...
    0, 2.6e6, 2.2e6, 1.2e6, 0.98e6, 0.96527e6; ...
    250, 2.7e6, 2.3e6, 1.25e6, 1.029e6, 1.0135335e6; ...
    500, 2.664e6, 2.252e6, 1.232e6, 0.9996e6, 0.9845754e6];
verifyEqual(testCase, actual, expected, "AbsTol", 1e-10);

verifyError(testCase, @() run_steady53_lineage_merge_diagnostic( ...
    outputDir, repoRoot, @fakeRunner), "lineagemerge:RunExists");
verifyEqual(testCase, calls, 1);

runnerSource = fileread(fullfile(repoRoot, "tests", ...
    "run_steady53_lineage_merge_diagnostic.m"));
verifyEqual(testCase, count(runnerSource, ...
    "run_steady53_case(candidatePath, 500, true)"), 1);

    function result = fakeRunner(modelPath, stopTime, logSignals)
        calls = calls + 1;
        verifyEqual(testCase, canonicalPath(modelPath), ...
            canonicalPath(fullfile(outputDir, "candidate.slx")));
        verifyEqual(testCase, stopTime, 500);
        verifyTrue(testCase, logSignals);
        result = syntheticResult(candidateHashBefore);
    end
end

function result = syntheticResult(candidateHash)
result = struct( ...
    "success", true, ...
    "errorId", "", ...
    "errorReport", "", ...
    "tFinal_s", 500, ...
    "t", [0; 250; 500], ...
    "signals", struct( ...
        "reactor_power", [2.6e6; 2.7e6; 2.664e6], ...
        "turbine_power", [2.2e6; 2.3e6; 2.252e6], ...
        "compressor_power", [1.2e6; 1.25e6; 1.232e6]), ...
    "states", struct.empty, ...
    "warningIds", strings(0, 1), ...
    "modelHashBefore", candidateHash, ...
    "modelHashAfter", candidateHash, ...
    "fileGenRoot", "");
end

function pathValue = newOwnedOutput(repoRoot)
tmpRoot = fullfile(repoRoot, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
pathValue = string(tempname(tmpRoot));
end

function cleanupOwnedOutput(outputDir, repoRoot)
tmpRoot = canonicalPath(fullfile(repoRoot, "tmp"));
if ~isfolder(outputDir)
    return
end
candidate = canonicalPath(outputDir);
if ~startsWith(candidate, tmpRoot + filesep) || ...
        count(extractAfter(candidate, strlength(tmpRoot) + 1), filesep) ~= 0
    error("lineagemergetest:UnsafeCleanup", ...
        "Refusing to clean a path outside the direct tmp child boundary.");
end
rmdir(candidate, "s");
end

function records = hashRecords(paths)
records = strings(numel(paths), 2);
for index = 1:numel(paths)
    records(index, :) = [paths(index), sha256File(paths(index))];
end
end

function paths = formalPaths(repoRoot)
paths = [ ...
    fullfile(repoRoot, "final_steady_24a.slx"); ...
    fullfile(repoRoot, "HeXe_property_simulink.m"); ...
    fullfile(repoRoot, "Lithium_property_simulink.m"); ...
    fullfile(repoRoot, "data", "provenance", "baselines", ...
        "f8bcd83", "final_steady_24a.slx")];
dynamicPath = fullfile(repoRoot, "final_dynamic_24a.slx");
if isfile(dynamicPath)
    paths(end + 1, 1) = dynamicPath;
end
matFiles = dir(fullfile(repoRoot, "*.mat"));
for index = 1:numel(matFiles)
    paths(end + 1, 1) = string(fullfile( ...
        matFiles(index).folder, matFiles(index).name)); %#ok<AGROW>
end
paths = sort(paths);
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    canonicalPath(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

function value = canonicalPath(pathValue)
value = string(java.io.File(char(pathValue)).getCanonicalPath());
end
