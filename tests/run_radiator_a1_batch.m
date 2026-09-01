function summary = run_radiator_a1_batch(runRoot, stopTime)
%RUN_RADIATOR_A1_BATCH Run all candidates without batch-wide early abort.
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
if stopTime == 500
    source = jsondecode(fileread(fullfile(runRoot, ...
        'representatives', 'selection.json')));
    ids = string(source.eligible_candidate_ids);
    stage = 'candidates_500s';
elseif stopTime == 14000
    source = jsondecode(fileread(fullfile(runRoot, ...
        'comparisons', 'advance_14000.json')));
    ids = string(source.candidate_ids);
    stage = 'candidates_14000s';
else
    error('radiatorA1:UnsupportedStopTime', ...
        'Only 500 or 14000 s is approved.');
end
summary = struct('candidate_id', {}, 'success', {}, 'output_dir', {});
for k = 1:numel(ids)
    output = fullfile(runRoot, stage, ids(k), 'run');
    try
        status = run_radiator_a1_candidate(runRoot, ids(k), output, stopTime);
    catch exception
        status = struct('success', false, ...
            'error_message', string(getReport( ...
                exception, 'extended', 'hyperlinks', 'off')));
        if ~isfolder(output), mkdir(output); end
        writeJSON(fullfile(output, 'batch_failure.json'), status);
    end
    summary(end+1) = struct('candidate_id', ids(k), ...
        'success', logical(status.success), 'output_dir', output); %#ok<AGROW>
end
writeJSON(fullfile(runRoot, 'final_audit', ...
    "batch_" + stopTime + "_summary.json"), summary);
end

function writeJSON(pathValue, value)
folder = fileparts(pathValue);
if ~isfolder(folder), mkdir(folder); end
assert(~isfile(pathValue));
file = fopen(pathValue, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
