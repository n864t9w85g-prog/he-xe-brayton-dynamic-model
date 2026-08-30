function summary = prepare_radiator_a1_candidates(runRoot)
%PREPARE_RADIATOR_A1_CANDIDATES Copy, patch, reopen and compile candidates.
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
source = fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'final_steady_24a.slx');
sourceHash = hashFile(source);
assert(sourceHash == ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
selection = jsondecode(fileread(fullfile(runRoot, ...
    'representatives', 'selection.json')));
ids = string(selection.eligible_candidate_ids);
summary = struct('candidate_id', {}, 'prepared', {}, 'error', {}, ...
    'candidate_file', {}, 'candidate_sha256', {});

oldPath = path;
cleanupPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
sourceDir = fullfile(repo, 'tmp', 'steady53_curves_20260828', ...
    'source_f8bcd83');
assert(isfolder(sourceDir));
addpath(sourceDir, fullfile(sourceDir, 'tests', 'steady53'), ...
    fullfile(repo, 'tests'));
evalin('base', "run('" + ...
    replace(fullfile(sourceDir, 'start.m'), "'", "''") + "')");

for k = 1:numel(ids)
    id = ids(k);
    destination = fullfile(runRoot, 'candidates_500s', id);
    mkdir(destination);
    candidateFile = fullfile(destination, 'candidate.slx');
    manifest = fullfile(runRoot, 'representatives', id, ...
        'parameter_manifest.json');
    row = struct('candidate_id', id, 'prepared', false, 'error', "", ...
        'candidate_file', candidateFile, 'candidate_sha256', "");
    oldConfig = Simulink.fileGenControl('getConfig');
    cleanupConfig = onCleanup(@() Simulink.fileGenControl('set', ...
        'CacheFolder', oldConfig.CacheFolder, ...
        'CodeGenFolder', oldConfig.CodeGenFolder, 'createDir', true)); %#ok<NASGU>
    Simulink.fileGenControl('set', ...
        'CacheFolder', fullfile(destination, 'cache'), ...
        'CodeGenFolder', fullfile(destination, 'codegen'), 'createDir', true);
    try
        copyfile(source, candidateFile);
        assert(hashFile(candidateFile) == sourceHash);
        load_system(candidateFile);
        cleanupModel = onCleanup(@() closeOwnedModel()); %#ok<NASGU>
        audit = patch_radiator_a1_candidate("candidate", manifest, destination);
        set_param('candidate', 'SimulationCommand', 'update');
        close_system('candidate', 0);
        load_system(candidateFile);
        set_param('candidate', 'SimulationCommand', 'update');
        close_system('candidate', 0);
        row.prepared = true;
        row.candidate_sha256 = audit.candidate_sha256;
    catch exception
        row.error = string(getReport(exception, 'extended', 'hyperlinks', 'off'));
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
    writeJSON(fullfile(destination, 'preparation_status.json'), row);
    summary(end+1) = row; %#ok<AGROW>
end
writeJSON(fullfile(runRoot, 'final_audit', 'preparation_summary.json'), summary);

    function closeOwnedModel()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function value = hashFile(pathValue)
[status, output] = system("shasum -a 256 '" + ...
    replace(string(pathValue), "'", "'\''") + "'");
assert(status == 0);
parts = split(strtrim(string(output)));
value = parts(1);
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
