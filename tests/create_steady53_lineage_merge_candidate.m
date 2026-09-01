function audit = create_steady53_lineage_merge_candidate(outputDir, repoRoot)
%CREATE_STEADY53_LINEAGE_MERGE_CANDIDATE Build the approved 40-state copy.
%   Exploration only. The immutable f8bcd83 steady model is copied and all
%   40 common Integrator InitialCondition expressions are replaced by the
%   repository-root model expressions. This function never simulates.

arguments
    outputDir {mustBeTextScalar}
    repoRoot {mustBeTextScalar}
end

ROOT_SHA256 = ...
    "a93cd94b6c5a0c941fe9eed40d8aea779019cbdb26fe2558df65f7c81c9dc159";
FROZEN_SHA256 = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";

repoRoot = canonicalPath(repoRoot);
requireDirectory(repoRoot, "repository root");
outputDir = validateNewOutput(outputDir, repoRoot);
rootPath = fullfile(repoRoot, "final_steady_24a.slx");
frozenPath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
requireHash(rootPath, ROOT_SHA256, "repository-root model");
requireHash(frozenPath, FROZEN_SHA256, "frozen f8bcd83 model");

rootContract = readModelContract(rootPath);
frozenContract = readModelContract(frozenPath);
assertExactStateMap(rootContract.states, frozenContract.states);

mkdir(outputDir);
candidatePath = fullfile(outputDir, "candidate.slx");
copyFileExclusive(frozenPath, candidatePath);
patchCandidate(candidatePath, rootContract.states);
candidateContract = readModelContract(candidatePath);
[stateAssignments, stateChanges] = compareStateVector( ...
    frozenContract.states, rootContract.states, candidateContract.states);

[changes, nonIcUnchanged] = compareDialogParameters( ...
    frozenContract.dialog_parameters, candidateContract.dialog_parameters);
blockUnchanged = isequal(frozenContract.blocks, candidateContract.blocks);
topologyUnchanged = isequal(frozenContract.edges, candidateContract.edges);
solverUnchanged = isequal(frozenContract.solver, candidateContract.solver);
if ~blockUnchanged
    error("lineagemerge:BlockInventoryChanged", ...
        "Candidate block inventory differs from the frozen model.");
end
if ~topologyUnchanged
    error("lineagemerge:TopologyChanged", ...
        "Candidate signal topology differs from the frozen model.");
end
if ~nonIcUnchanged || numel(changes) ~= 39 || numel(stateChanges) ~= 39 || ...
        any(string({changes.parameter}) ~= "InitialCondition")
    error("lineagemerge:NonICChange", ...
        "Candidate must assign 40 Integrator ICs with 39 effective changes.");
end
if ~solverUnchanged
    error("lineagemerge:SolverChanged", ...
        "Candidate solver configuration differs from the frozen model.");
end

audit = struct( ...
    "schema", "steady53_lineage_merge_candidate_v1", ...
    "experiment_scope", "exploration_only", ...
    "candidate_definition", ...
        "f8bcd83 equations and operating parameters plus root 40-state IC vector", ...
    "root_model_sha256", ROOT_SHA256, ...
    "frozen_model_sha256", FROZEN_SHA256, ...
    "candidate_model_sha256", sha256File(candidatePath), ...
    "state_count", 40, ...
    "assigned_state_count", 40, ...
    "changed_state_count", 39, ...
    "unchanged_state_count", 1, ...
    "state_assignments", stateAssignments, ...
    "changes", changes, ...
    "block_inventory_unchanged", blockUnchanged, ...
    "topology_unchanged", topologyUnchanged, ...
    "non_ic_dialog_parameters_unchanged", nonIcUnchanged, ...
    "solver_parameters_unchanged", solverUnchanged, ...
    "simulation_call_count", 0, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);
writeExclusiveText(fullfile(outputDir, "candidate_audit.json"), ...
    string(jsonencode(audit, PrettyPrint=true)) + newline);
end

function outputDir = validateNewOutput(outputDir, repoRoot)
outputDir = canonicalPath(outputDir);
tmpRoot = canonicalPath(fullfile(repoRoot, "tmp"));
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
relative = extractAfter(outputDir, strlength(tmpRoot) + 1);
if ~startsWith(outputDir, tmpRoot + filesep) || strlength(relative) == 0 || ...
        contains(relative, filesep)
    error("lineagemerge:OutputBoundary", ...
        "Output must be a direct child of the repository tmp directory.");
end
if isfile(outputDir) || isfolder(outputDir)
    error("lineagemerge:OutputExists", ...
        "Refusing to overwrite an existing output path.");
end
end

function contract = readModelContract(modelPath)
[~, model] = fileparts(modelPath);
model = string(model);
if bdIsLoaded(model)
    error("lineagemerge:ModelAlreadyLoaded", ...
        "Refusing to inspect model '%s' while it is already loaded.", model);
end
load_system(modelPath);
cleanup = onCleanup(@() closeIfLoaded(model)); %#ok<NASGU>
contract = struct( ...
    "states", stateSnapshot(model), ...
    "blocks", blockSnapshot(model), ...
    "edges", edgeSnapshot(model), ...
    "dialog_parameters", dialogSnapshot(model), ...
    "solver", solverSnapshot(model));
close_system(model, 0);
clear cleanup
end

function states = stateSnapshot(model)
paths = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "Integrator"));
paths = sort(paths(:));
states = repmat(struct("relative_path", "", "expression", ""), ...
    numel(paths), 1);
for index = 1:numel(paths)
    states(index) = struct( ...
        "relative_path", relativeBlockPath(paths(index), model), ...
        "expression", string(get_param(paths(index), "InitialCondition")));
end
end

function blocks = blockSnapshot(model)
paths = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
paths = sort(paths(:));
blocks = strings(numel(paths), 2);
for index = 1:numel(paths)
    blocks(index, :) = [relativeBlockPath(paths(index), model), ...
        string(get_param(paths(index), "BlockType"))];
end
end

function records = dialogSnapshot(model)
paths = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
paths = sort(paths(:));
records = strings(0, 4);
for blockIndex = 1:numel(paths)
    block = paths(blockIndex);
    blockType = string(get_param(block, "BlockType"));
    dialog = get_param(block, "DialogParameters");
    if isempty(dialog)
        continue
    end
    names = sort(string(fieldnames(dialog)));
    for nameIndex = 1:numel(names)
        name = names(nameIndex);
        records(end + 1, :) = [ ... %#ok<AGROW>
            relativeBlockPath(block, model), blockType, name, ...
            encodeValue(get_param(block, name))];
    end
end
records = sortrows(records, [1, 3, 2, 4]);
end

function edges = edgeSnapshot(model)
lines = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "FindAll", "on", "Type", "Line");
edges = strings(0, 4);
for lineIndex = 1:numel(lines)
    sourcePort = get_param(lines(lineIndex), "SrcPortHandle");
    destinationPorts = get_param(lines(lineIndex), "DstPortHandle");
    if isempty(sourcePort) || sourcePort == -1 || isempty(destinationPorts)
        continue
    end
    sourceBlock = string(get_param(sourcePort, "Parent"));
    sourceNumber = string(get_param(sourcePort, "PortNumber"));
    for destinationIndex = 1:numel(destinationPorts)
        destinationPort = destinationPorts(destinationIndex);
        if destinationPort == -1
            continue
        end
        destinationBlock = string(get_param(destinationPort, "Parent"));
        destinationNumber = string(get_param(destinationPort, "PortNumber"));
        edges(end + 1, :) = [ ... %#ok<AGROW>
            relativeBlockPath(sourceBlock, model), sourceNumber, ...
            relativeBlockPath(destinationBlock, model), destinationNumber];
    end
end
edges = sortrows(edges, [1, 2, 3, 4]);
end

function records = solverSnapshot(model)
names = ["StartTime"; "StopTime"; "SolverName"; "SolverType"; ...
    "FixedStep"; "MaxStep"; "MinStep"; "InitialStep"; "MaxOrder"; ...
    "RelTol"; "AbsTol"; "AutoScaleAbsTol"; "Refine"; ...
    "NumberNewtonIterations"; "ShapePreserveControl"; ...
    "ZeroCrossControl"; "ZeroCrossAlgorithm"; "ZcThreshold"; ...
    "ConsecutiveZCsStepRelTol"; "MaxConsecutiveZCs"; "MaxZcPerStep"; ...
    "MaxZcBracketingIterations"; "EnableFixedStepZeroCrossing"; ...
    "MinStepSizeMsg"; "SolverPrmCheckMsg"; "AlgebraicLoopMsg"; ...
    "ArtificialAlgebraicLoopMsg"; "ConsistencyChecking"; "DaesscMode"; ...
    "ODENIntegrationMethod"; "ExtrapolationOrder"; ...
    "StateRefinementMethod"; "SolverJacobianMethodControl"; ...
    "SolverResetMethod"; "DecoupledContinuousIntegration"; ...
    "UseModelRefSolver"; "EnableMultiTasking"];
records = strings(numel(names), 2);
for index = 1:numel(names)
    records(index, :) = [names(index), encodeValue(get_param(model, names(index)))];
end
end

function assertExactStateMap(rootStates, frozenStates)
if numel(rootStates) ~= 40 || numel(frozenStates) ~= 40 || ...
        ~isequal(string({rootStates.relative_path}), ...
            string({frozenStates.relative_path}))
    error("lineagemerge:StateSetMismatch", ...
        "Root and frozen models must expose the same exact 40 Integrator paths.");
end
end

function [assignments, changes] = compareStateVector(frozen, root, candidate)
if numel(frozen) ~= 40 || numel(root) ~= 40 || numel(candidate) ~= 40 || ...
        ~isequal(string({frozen.relative_path}), string({root.relative_path})) || ...
        ~isequal(string({root.relative_path}), string({candidate.relative_path}))
    error("lineagemerge:StateSetMismatch", ...
        "Frozen, root, and candidate state inventories must match exactly.");
end
assignments = repmat(struct("relative_path", "", ...
    "frozen_expression", "", "root_expression", "", ...
    "candidate_expression", "", "value_changed", false, ...
    "candidate_matches_root", false), 40, 1);
for index = 1:40
    valueChanged = frozen(index).expression ~= root(index).expression;
    candidateMatchesRoot = candidate(index).expression == root(index).expression;
    assignments(index) = struct( ...
        "relative_path", root(index).relative_path, ...
        "frozen_expression", frozen(index).expression, ...
        "root_expression", root(index).expression, ...
        "candidate_expression", candidate(index).expression, ...
        "value_changed", valueChanged, ...
        "candidate_matches_root", candidateMatchesRoot);
end
if ~all([assignments.candidate_matches_root])
    error("lineagemerge:CandidateStateMismatch", ...
        "Candidate state vector does not exactly match the root model.");
end
changes = assignments([assignments.value_changed]);
unchanged = assignments(~[assignments.value_changed]);
if numel(changes) ~= 39 || numel(unchanged) ~= 1 || ...
        string(unchanged.relative_path) ~= "TAC/rotor/N_rpm_Integrator"
    error("lineagemerge:StateDifferenceCountMismatch", ...
        "Expected 39 differing Integrators and one common rotor-speed IC.");
end
end

function patchCandidate(candidatePath, rootStates)
model = "candidate";
if bdIsLoaded(model)
    error("lineagemerge:ModelAlreadyLoaded", ...
        "Refusing to edit an already-loaded candidate model.");
end
load_system(candidatePath);
cleanup = onCleanup(@() closeIfLoaded(model)); %#ok<NASGU>
for index = 1:numel(rootStates)
    target = model + "/" + rootStates(index).relative_path;
    set_param(target, "InitialCondition", rootStates(index).expression);
end
save_system(model, candidatePath);
close_system(model, 0);
clear cleanup
end

function [changes, nonIcUnchanged] = compareDialogParameters(before, after)
if size(before, 1) ~= size(after, 1) || ...
        ~isequal(before(:, 1:3), after(:, 1:3))
    error("lineagemerge:DialogInventoryChanged", ...
        "Candidate dialog-parameter inventory differs from the source.");
end
different = before(:, 4) ~= after(:, 4);
rows = find(different);
changes = repmat(struct("relative_path", "", "block_type", "", ...
    "parameter", "", "old_expression", "", "new_expression", ""), ...
    numel(rows), 1);
for index = 1:numel(rows)
    row = rows(index);
    changes(index) = struct( ...
        "relative_path", before(row, 1), ...
        "block_type", before(row, 2), ...
        "parameter", before(row, 3), ...
        "old_expression", before(row, 4), ...
        "new_expression", after(row, 4));
end
nonIcUnchanged = ~any(different & before(:, 3) ~= "InitialCondition");
end

function value = relativeBlockPath(block, model)
prefix = model + "/";
block = string(block);
if ~startsWith(block, prefix)
    error("lineagemerge:UnexpectedBlockPath", ...
        "Block path is outside the loaded model: %s", block);
end
value = extractAfter(block, strlength(prefix));
end

function value = encodeValue(raw)
try
    value = string(jsonencode(raw));
catch
    value = strtrim(string(evalc("disp(raw)")));
end
end

function requireHash(pathValue, expected, label)
if ~isfile(pathValue)
    error("lineagemerge:MissingSource", "Missing %s: %s", label, pathValue);
end
if sha256File(pathValue) ~= expected
    error("lineagemerge:SourceHashMismatch", ...
        "%s does not match the approved SHA-256.", label);
end
end

function requireDirectory(pathValue, label)
if ~isfolder(pathValue)
    error("lineagemerge:MissingDirectory", "Missing %s: %s", label, pathValue);
end
end

function copyFileExclusive(sourcePath, destinationPath)
source = java.nio.file.Paths.get(char(sourcePath), ...
    javaArray("java.lang.String", 0));
destination = java.nio.file.Paths.get(char(destinationPath), ...
    javaArray("java.lang.String", 0));
try
    java.nio.file.Files.copy(source, destination, ...
        javaArray("java.nio.file.CopyOption", 0));
catch exception
    if isfile(destinationPath) || isfolder(destinationPath)
        error("lineagemerge:CandidateExists", ...
            "Refusing to overwrite the candidate path.");
    end
    rethrow(exception)
end
end

function writeExclusiveText(pathValue, payload)
pathObject = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
try
    channel = java.nio.file.Files.newByteChannel(pathObject, options);
catch exception
    if isfile(pathValue) || isfolder(pathValue)
        error("lineagemerge:OutputExists", ...
            "Refusing to overwrite an audit artifact.");
    end
    rethrow(exception)
end
cleanup = onCleanup(@() closeChannel(channel)); %#ok<NASGU>
bytes = unicode2native(char(string(payload)), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(typecast(uint8(bytes), "int8"));
while buffer.hasRemaining()
    written = channel.write(buffer);
    if written <= 0
        error("lineagemerge:AuditWriteStalled", ...
            "The exclusive audit write made no progress.");
    end
end
channel.force(true);
channel.close();
clear cleanup
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

function value = canonicalPath(pathValue)
value = string(java.io.File(char(pathValue)).getCanonicalPath());
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function closeChannel(channel)
if ~isempty(channel) && channel.isOpen()
    channel.close();
end
end
