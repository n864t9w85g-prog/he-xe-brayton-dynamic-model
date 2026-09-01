function audit = create_fig519_ihx_r2_hexe_shift_candidate(runDir, repoRoot)
%CREATE_FIG519_IHX_R2_HEXE_SHIFT_CANDIDATE Build the isolated A3 candidate.
%   This function performs no integration. It copies the immutable f8bcd83
%   steady model, translates the two IHX region-2 He-Xe temperature initial
%   conditions by one shared delta, performs one diagram update, and audits
%   the candidate without changing a formal model or runtime dependency.

arguments
    runDir {mustBeTextScalar}
    repoRoot {mustBeTextScalar}
end

repoRoot = validateRepoRoot(repoRoot);
tmpRoot = fullfile(repoRoot, "tmp");
runDir = validateNewRunDirectory(runDir, tmpRoot);
sourcePath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "final_steady_24a.slx");
runtimeDir = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "runtime");
protectedPath = fullfile(repoRoot, "data", "provenance", "baselines", ...
    "f8bcd83", "protected_manifest_recovery.csv");
expectedSourceHash = ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";

assertRegularFile(sourcePath, "immutable source model");
assertNoSymlinkAncestors(sourcePath, repoRoot);
sourceHashBefore = sha256File(sourcePath);
if sourceHashBefore ~= expectedSourceHash
    error("fig519a3:SourceHashMismatch", ...
        "The immutable f8bcd83 source does not match the A3 contract.");
end
runtimeBefore = runtimeIdentities(runtimeDir, repoRoot);
protectedBefore = protectedIdentities(protectedPath, repoRoot);

createDirectoryExclusive(runDir);
candidatePath = fullfile(runDir, "candidate.slx");
copyFileExclusive(sourcePath, candidatePath)
assertRegularFile(candidatePath, "candidate model");
if sha256File(candidatePath) ~= sourceHashBefore
    error("fig519a3:CopyHashMismatch", ...
        "The candidate copy is not byte-identical before the API edit.");
end

oldFolder = string(pwd);
folderCleanup = onCleanup(@() cd(oldFolder));
cd(runDir);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath));
addpath(runtimeDir, fullfile(repoRoot, "tests", "steady53"));

baseSnapshot = captureBaseWorkspace();
baseCleanup = onCleanup(@() restoreBaseWorkspace(baseSnapshot));
startPath = fullfile(runtimeDir, "start.m");
evalin("base", "run(" + matlabString(startPath) + ")");

oldFileGeneration = Simulink.fileGenControl("getConfig");
fileGenerationRoot = fullfile(runDir, "filegen");
cacheFolder = fullfile(fileGenerationRoot, "cache");
codegenFolder = fullfile(fileGenerationRoot, "codegen");
fileGenerationCleanup = onCleanup(@() restoreFileGeneration(oldFileGeneration));
Simulink.fileGenControl("set", "CacheFolder", cacheFolder, ...
    "CodeGenFolder", codegenFolder, "createDir", true);
activeFileGeneration = Simulink.fileGenControl("getConfig");
if canonicalPath(activeFileGeneration.CacheFolder) ~= ...
        canonicalPath(cacheFolder) || ...
        canonicalPath(activeFileGeneration.CodeGenFolder) ~= ...
        canonicalPath(codegenFolder)
    error("fig519a3:FileGenerationConfigurationMismatch", ...
        "Simulink did not activate the contained file-generation folders.");
end

sourceModel = "final_steady_24a";
model = "candidate";
if bdIsLoaded(sourceModel) || bdIsLoaded(model)
    error("fig519a3:ModelAlreadyLoaded", ...
        "Source or candidate model is already loaded; refusing unsaved state.");
end

sourceCleanup = onCleanup(@() closeWithoutSaving(sourceModel));
load_system(sourcePath);
assertLoadedFile(sourceModel, sourcePath);
sourceStates = stateSnapshot(sourceModel);
sourceSolver = solverSnapshot(sourceModel);
sourceSemantic = semanticSnapshot(sourceModel);
sourceWorkspace = modelWorkspaceSnapshot(sourceModel);
closeWithoutSaving(sourceModel);
clear sourceCleanup

candidateCleanup = onCleanup(@() closeWithoutSaving(model));
load_system(candidatePath);
assertLoadedFile(model, candidatePath);
averageTarget = model + "/IHX/IHX_region_2/T_c1_average_Integrator";
outletTarget = model + "/IHX/IHX_region_2/T_c2_out_Integrator";
oldAverageK = numericInitialCondition(averageTarget);
oldOutletK = numericInitialCondition(outletTarget);
expectedOldAverageK = 1245.8184669844006;
expectedOldOutletK = 1393.6037139151003;
if abs(oldAverageK - expectedOldAverageK) > 1e-12 || ...
        abs(oldOutletK - expectedOldOutletK) > 1e-12
    error("fig519a3:InitialConditionMismatch", ...
        "The two frozen IHX initial conditions do not match the A3 contract.");
end

anchorK = 1200.0000000000000;
deltaTK = anchorK - oldOutletK;
newAverageK = oldAverageK + deltaTK;
newOutletK = oldOutletK + deltaTK;
oldGapK = oldOutletK - oldAverageK;
newGapK = newOutletK - newAverageK;
if abs(deltaTK - (-193.6037139151003)) > 1e-12 || ...
        abs(newAverageK - 1052.2147530693003) > 1e-12 || ...
        abs(newOutletK - 1200.0000000000000) > 1e-12 || ...
        abs(oldGapK - 147.7852469306997) > 1e-12 || ...
        abs(newGapK - oldGapK) > 1e-12
    error("fig519a3:SharedDeltaMismatch", ...
        "The one-scalar IHX translation contract was not preserved.");
end

set_param(averageTarget, "InitialCondition", num2str(newAverageK, "%.17g"));
set_param(outletTarget, "InitialCondition", num2str(newOutletK, "%.17g"));
save_system(model, candidatePath);
closeWithoutSaving(model);
clear candidateCleanup

% Reopen the persisted bytes, perform the only diagram update, and audit
% without saving again so compilation side effects cannot enter candidate.slx.
candidateCleanup = onCleanup(@() closeWithoutSaving(model));
load_system(candidatePath);
assertLoadedFile(model, candidatePath);
set_param(model, "SimulationCommand", "update")

candidateStates = stateSnapshot(model);
candidateSolver = solverSnapshot(model);
candidateSemantic = semanticSnapshot(model);
candidateWorkspace = modelWorkspaceSnapshot(model);
[stateRecords, changedRelativePaths] = compareStates( ...
    sourceStates, candidateStates, sourceModel, model);
expectedChanged = sort([ ...
    "IHX/IHX_region_2/T_c1_average_Integrator"; ...
    "IHX/IHX_region_2/T_c2_out_Integrator"]);
if numel(changedRelativePaths) ~= 2 || ...
        ~isequal(sort(changedRelativePaths), expectedChanged)
    error("fig519a3:StateDeltaMismatch", ...
        "Exactly the two contracted IHX states must change.");
end
if numel(stateRecords) ~= 40 || sum([stateRecords.unchanged]) ~= 38
    error("fig519a3:UnchangedStateCountMismatch", ...
        "The candidate must preserve exactly 38 of 40 state ICs.");
end
if numel(sourceSolver) ~= 37 || ~isequal(sourceSolver, candidateSolver)
    error("fig519a3:SolverChanged", ...
        "The candidate must preserve all 37 solver parameters.");
end
if ~isequal(sourceSemantic, candidateSemantic)
    error("fig519a3:SemanticTopologyChanged", ...
        "The candidate changed semantic block, port, line, or mask identity.");
end
if ~modelWorkspacesEqual(sourceWorkspace, candidateWorkspace)
    error("fig519a3:ModelWorkspaceChanged", ...
        "The candidate changed the model workspace.");
end

persistedAverageK = numericInitialCondition(averageTarget);
persistedOutletK = numericInitialCondition(outletTarget);
if abs(persistedAverageK - newAverageK) > 1e-12 || ...
        abs(persistedOutletK - newOutletK) > 1e-12
    error("fig519a3:PostUpdateValueMismatch", ...
        "The post-update candidate state values changed unexpectedly.");
end
closeWithoutSaving(model);
clear candidateCleanup
clear fileGenerationCleanup
clear baseCleanup

sourceHashAfter = sha256File(sourcePath);
runtimeAfter = runtimeIdentities(runtimeDir, repoRoot);
protectedAfter = protectedIdentities(protectedPath, repoRoot);
assertIdentitySetUnchanged(runtimeBefore, runtimeAfter, "runtime dependency");
assertIdentitySetUnchanged(protectedBefore, protectedAfter, "protected file");
if sourceHashAfter ~= expectedSourceHash || sourceHashAfter ~= sourceHashBefore
    error("fig519a3:SourceChanged", ...
        "Candidate generation changed the immutable source model.");
end
assertRegularFile(candidatePath, "candidate model");
candidateHash = sha256File(candidatePath);

runtimeRecords = beforeAfterRecords(runtimeBefore, runtimeAfter);
protectedRecords = beforeAfterRecords(protectedBefore, protectedAfter);
changedStates = [ ...
    struct("path", ...
        "final_steady_24a/IHX/IHX_region_2/T_c1_average_Integrator", ...
        "candidate_path", ...
        "candidate/IHX/IHX_region_2/T_c1_average_Integrator", ...
        "old_initial_condition_K", oldAverageK, ...
        "new_initial_condition_K", newAverageK, ...
        "delta_T_K", deltaTK); ...
    struct("path", ...
        "final_steady_24a/IHX/IHX_region_2/T_c2_out_Integrator", ...
        "candidate_path", ...
        "candidate/IHX/IHX_region_2/T_c2_out_Integrator", ...
        "old_initial_condition_K", oldOutletK, ...
        "new_initial_condition_K", newOutletK, ...
        "delta_T_K", deltaTK)];

auditPath = fullfile(runDir, "patch_audit.json");
auditChannel = openFileExclusive(auditPath);
auditChannelCleanup = onCleanup(@() closeChannel(auditChannel));
assertRegularFile(auditPath, "patch audit");
artifacts = artifactAudit(runDir, candidatePath, auditPath);
fileGenerationSettings = struct( ...
    "cache_folder", canonicalPath(activeFileGeneration.CacheFolder), ...
    "codegen_folder", canonicalPath(activeFileGeneration.CodeGenFolder), ...
    "contained", isContained(activeFileGeneration.CacheFolder, runDir) && ...
        isContained(activeFileGeneration.CodeGenFolder, runDir));
if ~fileGenerationSettings.contained
    error("fig519a3:FileGenerationOutsideRun", ...
        "File-generation folders must remain inside the owned run directory.");
end

audit = struct( ...
    "patch_schema", "steady53_fig519_ihx_r2_hexe_shift_candidate_v1", ...
    "attempt_id", "20260901_A3", ...
    "candidate_value_identity", ...
        "figure_5_18a_t0_visual_proxy_not_author_initial_state", ...
    "source_repository_relative_path", relativeToRepo(sourcePath, repoRoot), ...
    "source_absolute_path", canonicalPath(sourcePath), ...
    "source_model_sha256", sourceHashBefore, ...
    "source_sha256", sourceHashBefore, ...
    "source_sha256_after", sourceHashAfter, ...
    "source_hash_unchanged", sourceHashAfter == sourceHashBefore, ...
    "candidate_repository_relative_path", ...
        relativeToRepo(candidatePath, repoRoot), ...
    "candidate_absolute_path", canonicalPath(candidatePath), ...
    "candidate_sha256", candidateHash, ...
    "anchor_K", anchorK, ...
    "delta_T_K", deltaTK, ...
    "old_gap_K", oldGapK, ...
    "new_gap_K", newGapK, ...
    "changed_states", changedStates, ...
    "changed_state_count", 2, ...
    "unchanged_state_count", 38, ...
    "state_count", 40, ...
    "state_initial_conditions", stateRecords, ...
    "solver_parameter_count", 37, ...
    "solver_contract", struct("unchanged", true, ...
        "parameter_count", numel(sourceSolver), "parameters", sourceSolver), ...
    "semantic_snapshot", struct("unchanged", true, ...
        "source", sourceSemantic, "candidate", candidateSemantic), ...
    "model_workspace", struct("unchanged", true, ...
        "source", sourceWorkspace.records, ...
        "candidate", candidateWorkspace.records), ...
    "runtime_dependencies", runtimeRecords, ...
    "protected_manifest_sha256", sha256File(protectedPath), ...
    "protected_files", protectedRecords, ...
    "file_generation_settings", fileGenerationSettings, ...
    "artifact_audit", artifacts, ...
    "update_diagram_count", 1, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);

auditText = string(jsonencode(audit, PrettyPrint=true)) + newline;
writeOpenChannel(auditChannel, auditText);
auditChannel.force(true);
auditChannel.close();
clear auditChannelCleanup
assertRegularFile(auditPath, "patch audit");
expectedAuditHash = sha256Text(auditText);
persistedAuditHash = sha256File(auditPath);
if persistedAuditHash ~= expectedAuditHash
    error("fig519a3:AuditPersistenceMismatch", ...
        "The exclusively written patch audit did not persist exactly " + ...
        "(expected SHA256 %s, got %s).", ...
        expectedAuditHash, persistedAuditHash);
end
end

function repoRoot = validateRepoRoot(repoRoot)
repoRoot = string(repoRoot);
if ~startsWith(repoRoot, filesep) || ~isfolder(repoRoot)
    error("fig519a3:RepoRootInvalid", ...
        "repoRoot must be an existing absolute directory.");
end
repoJavaPath = java.nio.file.Paths.get(char(repoRoot), ...
    javaArray("java.lang.String", 0));
if java.nio.file.Files.isSymbolicLink(repoJavaPath)
    error("fig519a3:RepoRootSymlink", "repoRoot must not be a symlink.");
end
detected = string(fileparts(fileparts(mfilename("fullpath"))));
repoRoot = canonicalPath(repoRoot);
if repoRoot ~= canonicalPath(detected)
    error("fig519a3:RepoRootMismatch", ...
        "repoRoot must identify the repository containing this generator.");
end
end

function runDir = validateNewRunDirectory(runDir, tmpRoot)
runDir = string(runDir);
if ~startsWith(runDir, filesep)
    error("fig519a3:RunDirMustBeAbsolute", "runDir must be absolute.");
end
canonicalTmp = canonicalPath(tmpRoot);
canonicalRun = canonicalPath(runDir);
if canonicalRun == canonicalTmp || ...
        ~startsWith(canonicalRun, canonicalTmp + filesep)
    error("fig519a3:RunDirOutsideTmp", ...
        "runDir must be a child of repository tmp/.");
end
assertNoSymlinkAncestors(runDir, canonicalTmp);
javaPath = java.nio.file.Paths.get(char(runDir), ...
    javaArray("java.lang.String", 0));
if isfolder(runDir) || isfile(runDir) || ...
        java.nio.file.Files.isSymbolicLink(javaPath)
    error("fig519a3:RunDirExists", "runDir must not already exist.");
end
runDir = canonicalRun;
end

function value = numericInitialCondition(blockPath)
expression = string(get_param(blockPath, "InitialCondition"));
value = str2double(expression);
if ~isscalar(value) || ~isfinite(value)
    error("fig519a3:NonNumericInitialCondition", ...
        "The contracted initial condition must be a finite numeric literal.");
end
end

function records = stateSnapshot(model)
paths = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "BlockType", "Integrator"));
paths = sort(paths(:));
if numel(paths) ~= 40
    error("fig519a3:StateCountMismatch", ...
        "Expected 40 Integrator states, found %d.", numel(paths));
end
records = repmat(struct("relative_path", "", "expression", ""), ...
    numel(paths), 1);
for index = 1:numel(paths)
    records(index).relative_path = relativeBlockPath(paths(index), model);
    records(index).expression = string(get_param(paths(index), ...
        "InitialCondition"));
end
end

function [records, changed] = compareStates(source, candidate, sourceModel, model)
if numel(source) ~= 40 || numel(candidate) ~= 40 || ...
        ~isequal(string({source.relative_path}), ...
        string({candidate.relative_path}))
    error("fig519a3:StateInventoryMismatch", ...
        "Source and candidate state inventories differ.");
end
records = repmat(struct("source_path", "", "candidate_path", "", ...
    "source_expression", "", "candidate_expression", "", ...
    "unchanged", false), numel(source), 1);
changed = strings(0, 1);
for index = 1:numel(source)
    same = source(index).expression == candidate(index).expression;
    relative = source(index).relative_path;
    records(index) = struct( ...
        "source_path", sourceModel + "/" + relative, ...
        "candidate_path", model + "/" + relative, ...
        "source_expression", source(index).expression, ...
        "candidate_expression", candidate(index).expression, ...
        "unchanged", same);
    if ~same
        changed(end + 1, 1) = relative; %#ok<AGROW>
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
if numel(names) ~= 37
    error("fig519a3:SolverContractShape", ...
        "The frozen solver contract must contain exactly 37 parameters.");
end
config = getActiveConfigSet(model);
available = string(config.getProp);
records = repmat(struct("name", "", "value", ""), numel(names), 1);
for index = 1:numel(names)
    if ~ismember(names(index), available)
        error("fig519a3:SolverParameterUnavailable", ...
            "Required solver parameter is unavailable: %s", names(index));
    end
    value = get_param(model, names(index));
    if isstring(value) || ischar(value)
        encoded = string(value);
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
portRecords = strings(0, 1);
edges = strings(0, 1);
for index = 1:numel(blocks)
    relative = relativeBlockPath(blocks(index), model);
    handles = get_param(blocks(index), "PortHandles");
    portKinds = sort(string(fieldnames(handles)));
    portCounts = strings(numel(portKinds), 1);
    for kindIndex = 1:numel(portKinds)
        portCounts(kindIndex) = portKinds(kindIndex) + ":" + ...
            string(numel(handles.(portKinds(kindIndex))));
    end
    blockRecords(index) = relative + "|" + ...
        string(get_param(blocks(index), "BlockType")) + "|" + ...
        string(get_param(blocks(index), "MaskType")) + "|" + ...
        string(get_param(blocks(index), "ReferenceBlock"));
    portRecords(end + 1, 1) = relative + "|" + ...
        strjoin(portCounts, ","); %#ok<AGROW>
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
portRecords = sort(portRecords);
edges = sort(unique(edges));
snapshot = struct( ...
    "block_count", numel(blockRecords), ...
    "port_owner_count", numel(portRecords), ...
    "edge_count", numel(edges), ...
    "block_mask_fingerprint", ...
        sha256Text(strjoin(blockRecords, newline)), ...
    "port_fingerprint", sha256Text(strjoin(portRecords, newline)), ...
    "line_fingerprint", sha256Text(strjoin(edges, newline)));
end

function snapshot = modelWorkspaceSnapshot(model)
workspace = get_param(model, "ModelWorkspace");
variables = workspace.whos;
if isempty(variables)
    names = strings(0, 1);
else
    names = sort(string({variables.name}).');
end
records = repmat(struct("name", "", "class", "", ...
    "size", zeros(1, 0)), numel(names), 1);
values = cell(numel(names), 1);
for index = 1:numel(names)
    value = workspace.getVariable(char(names(index)));
    values{index} = value;
    records(index) = struct("name", names(index), ...
        "class", string(class(value)), "size", size(value));
end
snapshot = struct("records", records, "values", {values});
end

function tf = modelWorkspacesEqual(before, after)
tf = isequal(before.records, after.records) && ...
    numel(before.values) == numel(after.values);
if ~tf
    return
end
for index = 1:numel(before.values)
    if ~isequaln(before.values{index}, after.values{index})
        tf = false;
        return
    end
end
end

function records = runtimeIdentities(runtimeDir, repoRoot)
names = ["HeXe_property_simulink.m"; "Lithium_property_simulink.m"; ...
    "hexe_compressor_lookup.mat"; "radiator_table.mat"; ...
    "turbine_table1.mat"; "turbine_table2.mat"; "paper54_constants.m"; ...
    "sys_param_rad_fixed.m"; "start.m"];
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "sha256", ""), numel(names), 1);
for index = 1:numel(names)
    filePath = fullfile(runtimeDir, names(index));
    assertNoSymlinkAncestors(filePath, runtimeDir);
    assertRegularFile(filePath, "runtime dependency");
    records(index) = struct("name", names(index), ...
        "repository_relative_path", relativeToRepo(filePath, repoRoot), ...
        "absolute_path", canonicalPath(filePath), ...
        "sha256", sha256File(filePath));
end
end

function records = protectedIdentities(manifestPath, repoRoot)
assertRegularFile(manifestPath, "protected manifest");
if sha256File(manifestPath) ~= ...
        "33f7a4b4bbda5e47932ec9345e490a42b68d5a8636bf541891840c76fde6ed64"
    error("fig519a3:ProtectedManifestHashMismatch", ...
        "Protected recovery manifest identity changed.");
end
tableData = readtable(manifestPath, TextType="string", ...
    VariableNamingRule="preserve");
required = ["original_path", "expected_sha256", "resolved_path", ...
    "resolved_sha256", "resolution"];
if height(tableData) ~= 34 || ...
        ~all(ismember(required, string(tableData.Properties.VariableNames)))
    error("fig519a3:ProtectedManifestShape", ...
        "Protected manifest must contain the fixed 34 resolved rows.");
end
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "absolute_path", "", "sha256", ""), height(tableData), 1);
for index = 1:height(tableData)
    filePath = tableData.resolved_path(index);
    if tableData.resolution(index) == "unresolved"
        error("fig519a3:ProtectedFileUnresolved", ...
            "Protected row %d is unresolved.", index);
    end
    assertRegularFile(filePath, "protected file");
    if sha256File(filePath) ~= tableData.resolved_sha256(index)
        error("fig519a3:ProtectedFileMismatch", ...
            "Protected row %d changed.", index);
    end
    records(index) = struct("name", tableData.original_path(index), ...
        "repository_relative_path", relativeIfWithinRepo(filePath, repoRoot), ...
        "absolute_path", canonicalPath(filePath), ...
        "sha256", tableData.resolved_sha256(index));
end
end

function output = beforeAfterRecords(before, after)
if numel(before) ~= numel(after) || ...
        ~isequal(string({before.name}), string({after.name}))
    error("fig519a3:IdentitySetChanged", "Identity record names changed.");
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
    error("fig519a3:IdentityChanged", "%s identity changed.", label);
end
end

function artifacts = artifactAudit(runDir, candidatePath, auditPath)
items = dir(fullfile(runDir, "**", "*"));
items = items(~[items.isdir]);
records = repmat(struct("repository_relative_path", "", ...
    "absolute_path", "", "regular_file", false, ...
    "symlink", false, "contained", false), numel(items), 1);
for index = 1:numel(items)
    filePath = string(fullfile(items(index).folder, items(index).name));
    javaPath = java.nio.file.Paths.get(char(filePath), ...
        javaArray("java.lang.String", 0));
    regular = isRegularFile(filePath);
    symlink = java.nio.file.Files.isSymbolicLink(javaPath);
    contained = isContained(filePath, runDir);
    if ~regular || symlink || ~contained
        error("fig519a3:UnsafeArtifact", ...
            "Candidate artifact is non-regular, symlinked, or outside runDir.");
    end
    records(index) = struct( ...
        "repository_relative_path", ...
            replace(extractAfter(canonicalPath(filePath), ...
            strlength(canonicalPath(runDir) + filesep)), filesep, "/"), ...
        "absolute_path", canonicalPath(filePath), ...
        "regular_file", regular, "symlink", symlink, ...
        "contained", contained);
end
artifacts = struct( ...
    "candidate_regular_file", isRegularFile(candidatePath), ...
    "candidate_symlink", isSymbolicLink(candidatePath), ...
    "candidate_contained", isContained(candidatePath, runDir), ...
    "audit_regular_file", isRegularFile(auditPath), ...
    "audit_symlink", isSymbolicLink(auditPath), ...
    "audit_contained", isContained(auditPath, runDir), ...
    "all_paths_contained", all([records.contained]), ...
    "all_files_regular", all([records.regular_file]), ...
    "any_symlink", any([records.symlink]), ...
    "files", records, ...
    "raw_result_present", isfile(fullfile(runDir, "raw_result.mat")), ...
    "run_directory_present", isfolder(fullfile(runDir, "run")));
if ~artifacts.candidate_regular_file || artifacts.candidate_symlink || ...
        ~artifacts.candidate_contained || ~artifacts.audit_regular_file || ...
        artifacts.audit_symlink || ~artifacts.audit_contained || ...
        ~artifacts.all_paths_contained || ~artifacts.all_files_regular || ...
        artifacts.any_symlink || artifacts.raw_result_present || ...
        artifacts.run_directory_present
    error("fig519a3:ArtifactAuditFailed", ...
        "The zero-simulation candidate artifact audit failed.");
end
end

function assertLoadedFile(model, expectedPath)
if canonicalPath(get_param(model, "FileName")) ~= canonicalPath(expectedPath)
    error("fig519a3:WrongModelLoaded", ...
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
snapshot = repmat(struct("name", "", "value", []), numel(names), 1);
for index = 1:numel(names)
    snapshot(index).name = names(index);
    snapshot(index).value = evalin("base", names(index));
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
    assignin("base", snapshot(index).name, snapshot(index).value);
end
end

function assertNoSymlinkAncestors(pathValue, stopAt)
probe = string(pathValue);
stopAt = canonicalPath(stopAt);
while strlength(probe) >= strlength(stopAt)
    javaPath = java.nio.file.Paths.get(char(probe), ...
        javaArray("java.lang.String", 0));
    if java.nio.file.Files.isSymbolicLink(javaPath)
        error("fig519a3:SymlinkForbidden", ...
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
error("fig519a3:PathNotAnchored", "Path is not anchored below its root.");
end

function assertRegularFile(pathValue, label)
if ~isRegularFile(pathValue) || isSymbolicLink(pathValue)
    error("fig519a3:RegularFileRequired", ...
        "%s must be a regular, non-symlink file: %s", label, pathValue);
end
end

function tf = isRegularFile(pathValue)
javaPath = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
tf = java.nio.file.Files.isRegularFile(javaPath, ...
    javaArray("java.nio.file.LinkOption", 0));
end

function tf = isSymbolicLink(pathValue)
javaPath = java.nio.file.Paths.get(char(pathValue), ...
    javaArray("java.lang.String", 0));
tf = java.nio.file.Files.isSymbolicLink(javaPath);
end

function relative = relativeBlockPath(pathValue, model)
prefix = model + "/";
pathValue = string(pathValue);
if pathValue == model
    relative = "";
elseif startsWith(pathValue, prefix)
    relative = extractAfter(pathValue, strlength(prefix));
else
    error("fig519a3:BlockOutsideModel", "Block path is outside the model.");
end
end

function relative = relativeToRepo(pathValue, repoRoot)
canonical = canonicalPath(pathValue);
repoRoot = canonicalPath(repoRoot);
if ~startsWith(canonical, repoRoot + filesep)
    error("fig519a3:PathOutsideRepo", "Path is outside the repository.");
end
relative = replace(extractAfter(canonical, ...
    strlength(repoRoot + filesep)), filesep, "/");
end

function relative = relativeIfWithinRepo(pathValue, repoRoot)
canonical = canonicalPath(pathValue);
repoRoot = canonicalPath(repoRoot);
if startsWith(canonical, repoRoot + filesep)
    relative = replace(extractAfter(canonical, ...
        strlength(repoRoot + filesep)), filesep, "/");
else
    relative = "";
end
end

function tf = isContained(pathValue, root)
canonical = canonicalPath(pathValue);
root = canonicalPath(root);
tf = canonical ~= root && startsWith(canonical, root + filesep);
end

function output = canonicalPath(pathValue)
output = string(java.io.File(string(pathValue)).getCanonicalPath());
end

function literal = matlabString(value)
literal = "'" + replace(string(value), "'", "''") + "'";
end

function copyFileExclusive(sourcePath, candidatePath)
sourceJavaPath = java.nio.file.Paths.get(char(sourcePath), ...
    javaArray("java.lang.String", 0));
candidateJavaPath = java.nio.file.Paths.get(char(candidatePath), ...
    javaArray("java.lang.String", 0));
options = javaArray("java.nio.file.CopyOption", 0);
try
    java.nio.file.Files.copy(sourceJavaPath, candidateJavaPath, options);
catch exception
    if isfile(candidatePath) || isfolder(candidatePath) || ...
            isSymbolicLink(candidatePath)
        error("fig519a3:CandidateExists", ...
            "Refusing to overwrite '%s'.", candidatePath);
    end
    rethrow(exception)
end
end

function channel = openFileExclusive(filePath)
javaPath = java.nio.file.Paths.get(char(filePath), ...
    javaArray("java.lang.String", 0));
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.CREATE_NEW;
options(2) = java.nio.file.StandardOpenOption.WRITE;
try
    channel = java.nio.file.Files.newByteChannel(javaPath, options);
catch exception
    if isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath)
        error("fig519a3:OutputExists", ...
            "Refusing to overwrite '%s'.", filePath);
    end
    rethrow(exception)
end
end

function writeOpenChannel(channel, text)
if ~channel.isOpen()
    error("fig519a3:AuditChannelClosed", ...
        "The exclusive audit channel closed before the write.");
end
bytes = unicode2native(char(text), "UTF-8");
buffer = java.nio.ByteBuffer.wrap(int8(bytes));
while buffer.hasRemaining()
    written = channel.write(buffer);
    if written <= 0
        error("fig519a3:AuditWriteStalled", ...
            "The exclusive audit write made no progress.");
    end
end
end

function closeChannel(channel)
if ~isempty(channel) && channel.isOpen()
    channel.close();
end
end

function createDirectoryExclusive(directoryPath)
javaPath = java.nio.file.Paths.get(char(directoryPath), ...
    javaArray("java.lang.String", 0));
attributes = javaArray("java.nio.file.attribute.FileAttribute", 0);
try
    java.nio.file.Files.createDirectory(javaPath, attributes);
catch exception
    if isfolder(directoryPath) || isfile(directoryPath) || ...
            isSymbolicLink(directoryPath)
        error("fig519a3:RunDirExists", ...
            "Refusing an existing candidate directory: '%s'.", directoryPath);
    end
    rethrow(exception)
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("fig519a3:HashFailed", ...
        "Could not hash '%s': %s", filePath, output);
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
