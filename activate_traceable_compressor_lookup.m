function activate_traceable_compressor_lookup(candidatePath)
%ACTIVATE_TRACEABLE_COMPRESSOR_LOOKUP Replace active map only after all gates.

root = fileparts(mfilename('fullpath'));
allowedDir = canonical_path(fullfile(root, 'output', ...
    'paper54_reproduction'));
activePath = canonical_path(fullfile(root, ...
    'hexe_compressor_lookup.mat'));
if nargin == 0
    candidatePath = fullfile(allowedDir, ...
        'hexe_compressor_lookup_candidate.mat');
end
candidatePath = canonical_path(candidatePath);
if ~startsWith(candidatePath, [allowedDir filesep]) || ...
        strcmp(candidatePath, activePath)
    error('compressorMap:CandidatePathRequired', ...
        'Activation input must be a candidate under %s.', allowedDir);
end
assert(isfile(candidatePath), 'Candidate map is missing: %s', candidatePath);

expectedOldHash = ...
    'ab0fa69686d7fbb2d7815a1abf84939ad19506834d3de310c39883b7b3d57f3a';
assert(strcmpi(sha256_file(activePath), expectedOldHash), ...
    ['Active map hash differs from the audited pre-activation checkpoint; ' ...
     'refusing to overwrite it.']);

addpath(fullfile(root, 'tests'));
test_traceable_compressor_candidate(candidatePath);

backupPath = fullfile(root, ...
    'hexe_compressor_lookup.mat.before_traceable_map_20260818.bak');
if ~isfile(backupPath)
    copyfile(activePath, backupPath);
end
copyfile(candidatePath, activePath, 'f');

try
    test_traceable_compressor_candidate(activePath);
    startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
    evalin('base', sprintf('run(''%s'')', startPath));
    assignin('base', 'Pload_sched', [0 1000.21e3; 1 1000.21e3]);
    assignin('base', 'rho_sched', [0 0; 1 0]);
    mdl = 'final_dynamic_24a';
    load_system(fullfile(root, [mdl '.slx']));
    cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>
    set_param(mdl, 'SimulationCommand', 'update');
catch ME
    copyfile(backupPath, activePath, 'f');
    rethrow(ME);
end

fprintf('ACTIVATED traceable compressor map: %s\n', activePath);
fprintf('Backup preserved: %s\n', backupPath);
end

function path = canonical_path(path)
path = char(java.io.File(char(string(path))).getCanonicalPath());
end

function digest = sha256_file(path)
md = java.security.MessageDigest.getInstance('SHA-256');
bytes = java.nio.file.Files.readAllBytes(java.io.File(path).toPath());
digest = lower(reshape(dec2hex( ...
    typecast(md.digest(bytes), 'uint8'), 2).', 1, []));
end
