function tests = test_prepare_radiator_a1_candidates
tests = functiontests(localfunctions);
end

function testTwoCandidatesPrepareInIndependentCleanupScopes(testCase)
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(tempname(fullfile(repo, 'tmp')));
mkdir(runRoot);
cleanupRoot = onCleanup(@() removeOwnedTemp(runRoot)); %#ok<NASGU>
command = "cd '" + replace(repo, "'", "'\''") + ...
    "' && python3 tests/build_radiator_a1_screen.py '" + ...
    replace(runRoot, "'", "'\''") + "'";
[status, output] = system(command);
verifyEqual(testCase, status, 0, output);
selectionFile = fullfile(runRoot, 'representatives', 'selection.json');
selection = jsondecode(fileread(selectionFile));
selection.eligible_candidate_ids = selection.eligible_candidate_ids(1:2);
selection.eligible_count = 2;
writeJSON(selectionFile, selection);

summary = prepare_radiator_a1_candidates(runRoot);
verifyEqual(testCase, numel(summary), 2);
verifyTrue(testCase, all([summary.prepared]), ...
    strjoin(string({summary.error}), newline));
end

function writeJSON(pathValue, value)
file = fopen(pathValue, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end

function removeOwnedTemp(pathValue)
if bdIsLoaded('candidate'), close_system('candidate', 0); end
if isfolder(pathValue), rmdir(pathValue, 's'); end
end
