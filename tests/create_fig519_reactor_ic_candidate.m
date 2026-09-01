function audit = create_fig519_reactor_ic_candidate(runDir)
%CREATE_FIG519_REACTOR_IC_CANDIDATE Build one isolated API-edited candidate.
%   This function never simulates a model.  It copies the immutable f8bcd83
%   baseline below repository tmp/, changes only reactor/Integrator6's
%   InitialCondition, saves through Simulink, reopens/updates the candidate,
%   and writes an exact-one-change audit.

arguments
    runDir {mustBeTextScalar}
end

repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
runDir = validateNewRunDirectory(runDir, tmpRoot);
sourcePath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
runtimeDir = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "runtime");
paperPath = fullfile(repo, "data", "provenance", "steady53", ...
    "fig5_19", "paper_points.csv");
protectedPath = fullfile(repo, "data", "provenance", "baselines", ...
    "f8bcd83", "protected_manifest_recovery.csv");
expectedSourceHash = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
sourceHashBefore = sha256File(sourcePath);
if sourceHashBefore ~= expectedSourceHash
    error("fig519cf:SourceHashMismatch", ...
        "The immutable f8bcd83 source does not match the Task 7 contract.");
end

[candidateValueW, paperPoint] = candidateValueFromPaper(paperPath);
runtimeBefore = runtimeIdentities(runtimeDir);
protectedBefore = protectedIdentities(protectedPath);

createDirectoryExclusive(runDir);
candidatePath = fullfile(runDir, "candidate.slx");
[copied, message] = copyfile(sourcePath, candidatePath, "f");
if ~copied
    error("fig519cf:CopyFailed", "Could not copy source model: %s", message);
end
if sha256File(candidatePath) ~= sourceHashBefore
    error("fig519cf:CopyHashMismatch", ...
        "The candidate copy is not byte-identical before the API edit.");
end

oldFolder = string(pwd);
folderCleanup = onCleanup(@() cd(oldFolder));
cd(runDir);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath));
addpath(runtimeDir, fullfile(repo, "tests", "steady53"));

startPath = fullfile(runtimeDir, "start.m");
baseSnapshot = captureBaseWorkspace();
baseCleanup = onCleanup(@() restoreBaseWorkspace(baseSnapshot));
evalin("base", "run(" + matlabString(startPath) + ")");

fileGenerationConfig = Simulink.fileGenControl("getConfig");
fileGenerationRoot = fullfile(runDir, "filegen");
fileGenerationCleanup = onCleanup(@() restoreFileGeneration(fileGenerationConfig));
Simulink.fileGenControl("set", ...
    "CacheFolder", fullfile(fileGenerationRoot, "cache"), ...
    "CodeGenFolder", fullfile(fileGenerationRoot, "codegen"), ...
    "createDir", true);

sourceModel = "final_steady_24a";
if bdIsLoaded(sourceModel) || bdIsLoaded("candidate")
    error("fig519cf:ModelAlreadyLoaded", ...
        "Source or candidate model is already loaded; refusing unsaved state.");
end
sourceCleanup = onCleanup(@() closeWithoutSaving(sourceModel));
load_system(sourcePath);
assertLoadedFile(sourceModel, sourcePath);
set_param(sourceModel, "SimulationCommand", "update");
sourceStates = stateSnapshot(sourceModel);
sourceSolver = solverSnapshot(sourceModel);
sourceSemantic = semanticSnapshot(sourceModel);
closeWithoutSaving(sourceModel);
clear sourceCleanup

candidateModel = "candidate";
candidateCleanup = onCleanup(@() closeWithoutSaving(candidateModel));
load_system(candidatePath);
assertLoadedFile(candidateModel, candidatePath);
set_param(candidateModel + "/reactor/Integrator6", ...
    "InitialCondition", num2str(candidateValueW, "%.17g"));
save_system(candidateModel, candidatePath);
closeWithoutSaving(candidateModel);
clear candidateCleanup

% Reopen and compile-update through the official API.  No save follows this
% update, so compilation/logging changes cannot leak into candidate.slx.
candidateCleanup = onCleanup(@() closeWithoutSaving(candidateModel));
load_system(candidatePath);
assertLoadedFile(candidateModel, candidatePath);
set_param(candidateModel, "SimulationCommand", "update");
candidateStates = stateSnapshot(candidateModel);
candidateSolver = solverSnapshot(candidateModel);
candidateSemantic = semanticSnapshot(candidateModel);
closeWithoutSaving(candidateModel);
clear candidateCleanup

[stateRecords, changedStatePaths] = compareStates(sourceStates, candidateStates);
if numel(changedStatePaths) ~= 1 || ...
        changedStatePaths(1) ~= "reactor/Integrator6"
    error("fig519cf:StateDeltaMismatch", ...
        "Exactly reactor/Integrator6 must be the only changed state IC.");
end
if ~isequal(sourceSolver, candidateSolver)
    error("fig519cf:SolverChanged", ...
        "Candidate save changed one or more solver parameters.");
end
if ~isequal(sourceSemantic, candidateSemantic)
    error("fig519cf:SemanticTopologyChanged", ...
        "Candidate save changed block topology or connectivity.");
end

sourceHashAfter = sha256File(sourcePath);
runtimeAfter = runtimeIdentities(runtimeDir);
protectedAfter = protectedIdentities(protectedPath);
assertIdentitySetUnchanged(runtimeBefore, runtimeAfter, "runtime dependency");
assertIdentitySetUnchanged(protectedBefore, protectedAfter, "protected file");
if sourceHashAfter ~= sourceHashBefore
    error("fig519cf:SourceChanged", ...
        "Candidate generation changed the immutable source model.");
end

runtimeRecords = beforeAfterRecords(runtimeBefore, runtimeAfter);
matRecords = runtimeRecords(endsWith(string({runtimeRecords.name}), ".mat"));
propertyRecords = runtimeRecords(ismember(string({runtimeRecords.name}), ...
    ["HeXe_property_simulink.m", "Lithium_property_simulink.m"]));
protectedRecords = beforeAfterRecords(protectedBefore, protectedAfter);
candidateHash = sha256File(candidatePath);
audit = struct( ...
    "patch_schema", "steady53_fig519_reactor_ic_counterfactual_patch_v1", ...
    "source_repository_relative_path", relativeToRepo(sourcePath, repo), ...
    "source_absolute_path", canonicalPath(sourcePath), ...
    "source_sha256", sourceHashBefore, ...
    "source_sha256_after", sourceHashAfter, ...
    "source_hash_unchanged", sourceHashAfter == sourceHashBefore, ...
    "candidate_repository_relative_path", relativeToRepo(candidatePath, repo), ...
    "candidate_absolute_path", canonicalPath(candidatePath), ...
    "candidate_sha256", candidateHash, ...
    "candidate_value_identity", ...
        "figure_5_19_digitized_t10_proxy_not_author_t0", ...
    "candidate_value_W", candidateValueW, ...
    "paper_point", paperPoint, ...
    "circular_counterfactual", true, ...
    "counterfactual_question", ...
        "Can the full four-power transient be explained by changing the reactor power state alone?", ...
    "changed_blocks", {{"reactor/Integrator6"}}, ...
    "changed_parameters", {{"InitialCondition"}}, ...
    "state_count", numel(stateRecords), ...
    "state_initial_conditions", stateRecords, ...
    "solver_contract", struct("unchanged", true, ...
        "parameter_count", numel(sourceSolver), "parameters", sourceSolver), ...
    "semantic_snapshot", struct("unchanged", true, ...
        "source", sourceSemantic, "candidate", candidateSemantic), ...
    "runtime_dependencies", runtimeRecords, ...
    "mat_files", matRecords, ...
    "property_files", propertyRecords, ...
    "protected_manifest_sha256", sha256File(protectedPath), ...
    "protected_files", protectedRecords, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);

writeExclusiveText(fullfile(runDir, "patch_audit.json"), ...
    string(jsonencode(audit, PrettyPrint=true)) + newline);
end

function runDir = validateNewRunDirectory(runDir, tmpRoot)
runDir = string(runDir);
if ~startsWith(runDir, filesep)
    error("fig519cf:RunDirMustBeAbsolute", "runDir must be absolute.");
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalRun = canonicalPath(runDir);
if canonicalRun == canonicalTmp || ~startsWith(canonicalRun, canonicalTmp + filesep)
    error("fig519cf:RunDirOutsideTmp", ...
        "runDir must be a child of repository tmp/.");
end
assertNoSymlinkAncestors(runDir, canonicalTmp);
if isfolder(runDir) || isfile(runDir) || java.nio.file.Files.isSymbolicLink( ...
        java.nio.file.Paths.get(char(runDir), javaArray("java.lang.String", 0)))
    error("fig519cf:RunDirExists", "runDir must not already exist.");
end
runDir = canonicalRun;
end

function [candidateValueW, record] = candidateValueFromPaper(paperPath)
if sha256File(paperPath) ~= ...
        "e63607ad0f599c84fe6980ed26e05c91902b7928a53fabf5bf4a95a3de0098f2"
    error("fig519cf:PaperPointsHashMismatch", ...
        "Durable Figure 5.19 points do not match the Task 4 contract.");
end
points = readtable(paperPath, TextType="string", ...
    VariableNamingRule="preserve");
reactor = points(points.panel_id == "a", :);
if height(reactor) ~= 15
    error("fig519cf:PaperPanelMismatch", ...
        "Figure 5.19 panel a must contain exactly 15 fixed points.");
end
[firstTime, index] = min(reactor.time_s);
if firstTime ~= 10
    error("fig519cf:PaperProxyTimeMismatch", ...
        "The earliest fixed reactor point must be t=10 s.");
end
powerKW = reactor.power_kW(index);
candidateValueW = 1000 * powerKW;
if ~isscalar(candidateValueW) || ~isfinite(candidateValueW) || ...
        candidateValueW ~= 3186507.937
    error("fig519cf:PaperProxyValueMismatch", ...
        "The contracted t=10 reactor proxy changed.");
end
record = struct("panel_id", "a", "time_s", firstTime, ...
    "power_kW", powerKW, "conversion", "1000*power_kW", ...
    "is_author_t0", false, ...
    "limitation", "digitized t=10 proxy; not an author t0 value");
end

function records = stateSnapshot(model)
paths = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "BlockType", "Integrator"));
paths = sort(paths(:));
if numel(paths) ~= 40
    error("fig519cf:StateCountMismatch", ...
        "Expected 40 Integrator states, found %d.", numel(paths));
end
records = repmat(struct("path", "", "expression", ""), numel(paths), 1);
for index = 1:numel(paths)
    records(index).path = relativeBlockPath(paths(index), model);
    records(index).expression = string(get_param(paths(index), "InitialCondition"));
end
end

function [records, changed] = compareStates(source, candidate)
if numel(source) ~= 40 || numel(candidate) ~= 40 || ...
        ~isequal(string({source.path}), string({candidate.path}))
    error("fig519cf:StateInventoryMismatch", ...
        "Source and candidate state inventories differ.");
end
records = repmat(struct("path", "", "source_expression", "", ...
    "candidate_expression", "", "unchanged", false), numel(source), 1);
changed = strings(0, 1);
for index = 1:numel(source)
    same = source(index).expression == candidate(index).expression;
    records(index) = struct("path", source(index).path, ...
        "source_expression", source(index).expression, ...
        "candidate_expression", candidate(index).expression, ...
        "unchanged", same);
    if ~same
        changed(end + 1, 1) = source(index).path; %#ok<AGROW>
    end
end
end

function records = solverSnapshot(model)
names = ["StartTime"; "StopTime"; "SolverName"; ...
    "SolverType"; "FixedStep"; "MaxStep"; "MinStep"; "InitialStep"; ...
    "MaxOrder"; "RelTol"; "AbsTol"; "AutoScaleAbsTol"; "Refine"; ...
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
config = getActiveConfigSet(model);
available = string(config.getProp);
records = repmat(struct("name", "", "value", ""), numel(names), 1);
for index = 1:numel(names)
    if ~ismember(names(index), available)
        error("fig519cf:SolverParameterUnavailable", ...
            "Required solver parameter is unavailable: %s", names(index));
    end
    value = get_param(model, names(index));
    if isstring(value) || ischar(value)
        encoded = string(value);
    elseif isnumeric(value) || islogical(value)
        encoded = string(jsonencode(value));
    else
        encoded = string(jsonencode(value));
    end
    records(index) = struct("name", names(index), "value", encoded);
end
end

function snapshot = semanticSnapshot(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
blocks = sort(blocks(:));
blockRecords = strings(numel(blocks), 1);
edges = strings(0, 1);
for index = 1:numel(blocks)
    relative = relativeBlockPath(blocks(index), model);
    blockRecords(index) = relative + "|" + ...
        string(get_param(blocks(index), "BlockType")) + "|" + ...
        string(get_param(blocks(index), "MaskType")) + "|" + ...
        string(get_param(blocks(index), "ReferenceBlock"));
end
lines = find_system(model, "FindAll", "on", "Type", "line");
for index = 1:numel(lines)
    sourcePort = get_param(lines(index), "SrcPortHandle");
    destinationPorts = get_param(lines(index), "DstPortHandle");
    if isempty(sourcePort) || sourcePort == -1 || isempty(destinationPorts)
        continue
    end
    sourceBlock = string(get_param(sourcePort, "Parent"));
    sourceNumber = string(get_param(sourcePort, "PortNumber"));
    for destinationIndex = 1:numel(destinationPorts)
        if destinationPorts(destinationIndex) == -1
            continue
        end
        destinationBlock = string(get_param( ...
            destinationPorts(destinationIndex), "Parent"));
        destinationNumber = string(get_param( ...
            destinationPorts(destinationIndex), "PortNumber"));
        edges(end + 1, 1) = ...
            relativeBlockPath(sourceBlock, model) + ":" + sourceNumber + ...
            "->" + relativeBlockPath(destinationBlock, model) + ":" + ...
            destinationNumber; %#ok<AGROW>
    end
end
edges = sort(unique(edges));
snapshot = struct("block_count", numel(blockRecords), ...
    "edge_count", numel(edges), ...
    "block_fingerprint", sha256Text(strjoin(blockRecords, newline)), ...
    "edge_fingerprint", sha256Text(strjoin(edges, newline)));
end

function records = runtimeIdentities(runtimeDir)
names = ["HeXe_property_simulink.m"; "Lithium_property_simulink.m"; ...
    "hexe_compressor_lookup.mat"; "radiator_table.mat"; ...
    "turbine_table1.mat"; "turbine_table2.mat"; "paper54_constants.m"; ...
    "sys_param_rad_fixed.m"; "start.m"];
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "sha256", ""), numel(names), 1);
repo = string(fileparts(fileparts(fileparts(fileparts(fileparts(runtimeDir))))));
for index = 1:numel(names)
    filePath = fullfile(runtimeDir, names(index));
    assertNoSymlinkAncestors(filePath, runtimeDir);
    if ~isfile(filePath)
        error("fig519cf:RuntimeMissing", ...
            "Missing contracted runtime dependency: %s", names(index));
    end
    records(index) = struct("name", names(index), ...
        "repository_relative_path", relativeToRepo(filePath, repo), ...
        "absolute_path", canonicalPath(filePath), ...
        "sha256", sha256File(filePath));
end
end

function records = protectedIdentities(manifestPath)
if sha256File(manifestPath) ~= ...
        "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"
    error("fig519cf:ProtectedManifestHashMismatch", ...
        "Protected recovery manifest identity changed.");
end
tableData = readtable(manifestPath, TextType="string", ...
    VariableNamingRule="preserve");
required = ["original_path", "expected_sha256", "resolved_path", ...
    "resolved_sha256", "resolution"];
if height(tableData) ~= 34 || ...
        ~all(ismember(required, string(tableData.Properties.VariableNames)))
    error("fig519cf:ProtectedManifestShape", ...
        "Protected manifest must contain the fixed 34 resolved rows.");
end
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "sha256", ""), height(tableData), 1);
repo = string(fileparts(fileparts(fileparts(fileparts(fileparts(manifestPath))))));
for index = 1:height(tableData)
    filePath = tableData.resolved_path(index);
    if tableData.resolution(index) == "unresolved" || ~isfile(filePath) || ...
            sha256File(filePath) ~= tableData.resolved_sha256(index)
        error("fig519cf:ProtectedFileMismatch", ...
            "Protected row %d is unresolved or changed.", index);
    end
    records(index) = struct("name", tableData.original_path(index), ...
        "repository_relative_path", relativeIfWithinRepo(filePath, repo), ...
        "absolute_path", canonicalPath(filePath), ...
        "sha256", tableData.resolved_sha256(index));
end
end

function output = beforeAfterRecords(before, after)
if numel(before) ~= numel(after) || ...
        ~isequal(string({before.name}), string({after.name}))
    error("fig519cf:IdentitySetChanged", "Identity record names changed.");
end
output = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "before_sha256", "", ...
    "after_sha256", "", "unchanged", false), numel(before), 1);
for index = 1:numel(before)
    output(index) = struct("name", before(index).name, ...
        "repository_relative_path", before(index).repository_relative_path, ...
        "absolute_path", before(index).absolute_path, ...
        "before_sha256", before(index).sha256, ...
        "after_sha256", after(index).sha256, ...
        "unchanged", before(index).sha256 == after(index).sha256);
end
end

function assertIdentitySetUnchanged(before, after, label)
if numel(before) ~= numel(after) || ~isequal(before, after)
    error("fig519cf:IdentityChanged", "%s identity changed.", label);
end
end

function assertLoadedFile(model, expectedPath)
if canonicalPath(get_param(model, "FileName")) ~= canonicalPath(expectedPath)
    error("fig519cf:WrongModelLoaded", ...
        "Simulink did not load the explicitly requested model file.");
end
end

function closeWithoutSaving(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function restoreFileGeneration(config)
Simulink.fileGenControl("set", "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, "createDir", true);
end

function snapshot = captureBaseWorkspace()
names = string(evalin("base", "who"));
snapshot = repmat(struct("name", "", "existed", false, "value", []), ...
    numel(names), 1);
for index = 1:numel(names)
    snapshot(index).name = names(index);
    snapshot(index).existed = evalin("base", ...
        "exist(" + matlabString(names(index)) + ", 'var') == 1");
    if snapshot(index).existed
        snapshot(index).value = evalin("base", names(index));
    end
end
end

function restoreBaseWorkspace(snapshot)
expected = string({snapshot.name});
current = string(evalin("base", "who"));
created = setdiff(current, expected);
for index = 1:numel(created)
    evalin("base", "clear(" + matlabString(created(index)) + ")");
end
for index = 1:numel(snapshot)
    name = snapshot(index).name;
    if snapshot(index).existed
        assignin("base", name, snapshot(index).value);
    else
        evalin("base", "clear(" + matlabString(name) + ")");
    end
end
end

function assertNoSymlinkAncestors(pathValue, stopAt)
probe = string(pathValue);
stopAt = canonicalPath(stopAt);
while strlength(probe) >= strlength(stopAt)
    javaPath = java.nio.file.Paths.get(char(probe), ...
        javaArray("java.lang.String", 0));
    if java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:SymlinkForbidden", ...
            "Symlinked paths are forbidden: %s", probe);
    end
    if canonicalPath(probe) == stopAt
        return
    end
    parent = string(fileparts(probe));
    if parent == probe
        break
    end
    probe = parent;
end
error("fig519cf:PathNotAnchored", "Path is not anchored below its root.");
end

function relative = relativeBlockPath(pathValue, model)
prefix = model + "/";
pathValue = string(pathValue);
if pathValue == model
    relative = "";
elseif startsWith(pathValue, prefix)
    relative = extractAfter(pathValue, strlength(prefix));
else
    error("fig519cf:BlockOutsideModel", "Block path is outside the model.");
end
end

function relative = relativeToRepo(pathValue, repo)
canonical = canonicalPath(pathValue);
repo = canonicalPath(repo);
if ~startsWith(canonical, repo + filesep)
    error("fig519cf:PathOutsideRepo", "Path is outside the repository.");
end
relative = replace(extractAfter(canonical, strlength(repo + filesep)), ...
    filesep, "/");
end

function relative = relativeIfWithinRepo(pathValue, repo)
canonical = canonicalPath(pathValue);
repo = canonicalPath(repo);
if startsWith(canonical, repo + filesep)
    relative = replace(extractAfter(canonical, strlength(repo + filesep)), ...
        filesep, "/");
else
    relative = "";
end
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end

function literal = matlabString(value)
literal = "'" + replace(string(value), "'", "''") + "'";
end

function writeExclusiveText(filePath, text)
javaPath = java.nio.file.Paths.get(char(filePath), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createFile(javaPath, attributes);
catch exception
    if isfile(filePath) || isfolder(filePath) || ...
            java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:OutputExists", "Refusing to overwrite '%s'.", filePath);
    end
    rethrow(exception)
end
file = fopen(filePath, "w", "n", "UTF-8");
if file < 0
    error("fig519cf:WriteFailed", "Could not create '%s'.", filePath);
end
cleanup = onCleanup(@() fclose(file));
fprintf(file, "%s", text);
end

function createDirectoryExclusive(directoryPath)
javaPath = java.nio.file.Paths.get(char(directoryPath), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createDirectory(javaPath, attributes);
catch exception
    if isfolder(directoryPath) || isfile(directoryPath) || ...
            java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519cf:RunDirExists", ...
            "Refusing an existing candidate directory: '%s'.", directoryPath);
    end
    rethrow(exception)
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("fig519cf:HashFailed", "Could not hash '%s': %s", filePath, output);
end
parts = split(strtrim(output));
hash = string(parts(1));
end

function hash = sha256Text(text)
digest = java.security.MessageDigest.getInstance("SHA-256");
bytes = unicode2native(char(text), "UTF-8");
if isempty(bytes)
    raw = digest.digest();
else
    raw = digest.digest(int8(bytes));
end
hash = string(lower(reshape(dec2hex(typecast(raw, "uint8"), 2).', 1, [])));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\''") + "'";
end
