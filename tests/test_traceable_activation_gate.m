function test_traceable_activation_gate()
% Verify that the activation command cannot target the active file as input.

root = fileparts(fileparts(mfilename('fullpath')));
candidate = fullfile(root, 'hexe_compressor_lookup.mat');
didFail = false;
try
    activate_traceable_compressor_lookup(candidate);
catch ME
    didFail = strcmp(ME.identifier, 'compressorMap:CandidatePathRequired');
end
assert(didFail, ...
    'Activation must reject a candidate path outside the candidate directory.');
fprintf('PASS traceable compressor activation path gate.\n');
end
