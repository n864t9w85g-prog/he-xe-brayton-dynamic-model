function tests = test_patch_radiator_a1_candidate
tests = functiontests(localfunctions);
end

function testPatchIsLimitedAndReopens(testCase)
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(tempname(fullfile(repo, 'tmp')));
mkdir(runRoot);
cleanupRoot = onCleanup(@() removeOwnedTemp(runRoot)); %#ok<NASGU>
command = "cd '" + replace(repo, "'", "'\''") + ...
    "' && python3 tests/build_radiator_a1_screen.py '" + ...
    replace(runRoot, "'", "'\''") + "'";
[status, output] = system(command);
verifyEqual(testCase, status, 0, output);
selection = jsondecode(fileread(fullfile(runRoot, ...
    'representatives', 'selection.json')));
verifyGreaterThan(testCase, numel(selection.eligible_candidate_ids), 0);
candidateId = string(selection.eligible_candidate_ids{1});
manifest = fullfile(runRoot, 'representatives', candidateId, ...
    'parameter_manifest.json');
candidateDir = fullfile(runRoot, 'candidate_test');
mkdir(candidateDir);
source = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'final_steady_24a.slx');
candidateFile = fullfile(candidateDir, 'candidate.slx');
copyfile(source, candidateFile);
startFile = replace(fullfile(repo, 'start.m'), "'", "''");
evalin('base', "run('" + startFile + "')");
load_system(candidateFile);
cleanupModel = onCleanup(@() closeCandidate()); %#ok<NASGU>
audit = patch_radiator_a1_candidate("candidate", manifest, candidateDir);
verifyEqual(testCase, audit.source_sha256, ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyEqual(testCase, audit.changed_parameter_paths, [ ...
    "Constant"; "rediator/Subsystem/Constant"; ...
    "rediator/Subsystem/Constant2"; ...
    "rediator/Subsystem/Constant3"; ...
    "rediator/Subsystem/Constant4"; ...
    "rediator/Subsystem/Constant5"; ...
    "rediator/T_env"; "rediator/Tho"]);
verifyTrue(testCase, isfile(fullfile(candidateDir, ...
    'patch_manifest.json')));
verifyTrue(testCase, isfile(fullfile(candidateDir, ...
    'structural_diff.json')));
verifyNotEqual(testCase, audit.candidate_sha256, audit.source_sha256);

    function closeCandidate()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function removeOwnedTemp(pathValue)
if bdIsLoaded('candidate'), close_system('candidate', 0); end
if isfolder(pathValue), rmdir(pathValue, 's'); end
end
