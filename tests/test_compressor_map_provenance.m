function test_compressor_map_provenance(mat_path)
% Reject active compressor maps that cannot be reproduced from source data.

if nargin == 0
    root = fileparts(fileparts(mfilename('fullpath')));
    mat_path = fullfile(root, 'hexe_compressor_lookup.mat');
end

S = load(mat_path);
metadata = lower(strjoin(existing_text(S, ...
    {'version', 'description', 'reference'}), ' '));
forbidden = {'surrogate', 'gaussian', 'paper-shape'};
for k = 1:numel(forbidden)
    if contains(metadata, forbidden{k})
        error('compressorMap:UntraceableMetadata', ...
            'Untraceable compressor map: metadata contains "%s".', ...
            forbidden{k});
    end
end
test_traceable_compressor_candidate(mat_path);
end

function values = existing_text(S, names)
values = {};
for k = 1:numel(names)
    if isfield(S, names{k})
        values{end + 1} = char(string(S.(names{k}))); %#ok<AGROW>
    end
end
end
