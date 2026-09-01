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
formalBefore = formalIdentities(repoRoot);

createDirectoryExclusive(runDir);
runIdentity = pathIdentity(runDir, "directory");
stagingDir = createPrivateStagingDirectory(runDir);
stagingIdentity = pathIdentity(stagingDir, "directory");
stagingCandidatePath = fullfile(stagingDir, "candidate.slx");
candidatePath = fullfile(runDir, "candidate.slx");
copyFileExclusive(sourcePath, stagingCandidatePath)
stagingCandidateIdentity = pathIdentity(stagingCandidatePath, "file");
assertSameIdentity(runIdentity, runDir, "run directory");
assertSameIdentity(stagingIdentity, stagingDir, "staging directory");
if sha256File(stagingCandidatePath) ~= sourceHashBefore
    error("fig519a3:CopyHashMismatch", ...
        "The candidate copy is not byte-identical before the API edit.");
end

oldFolder = string(pwd);
oldPath = path;
oldFileGeneration = Simulink.fileGenControl("getConfig");
baseSnapshot = captureStartupWorkspace();
sourceModel = "final_steady_24a";
model = "candidate";
if bdIsLoaded(sourceModel) || bdIsLoaded(model)
    error("fig519a3:ModelAlreadyLoaded", ...
        "Source or candidate model is already loaded; refusing unsaved state.");
end
callerCleanup = onCleanup(@() restoreCallerState(sourceModel, model, ...
    oldFileGeneration, baseSnapshot, oldFolder, oldPath));
cd(runDir);
addpath(runtimeDir, fullfile(repoRoot, "tests", "steady53"));

startPath = fullfile(runtimeDir, "start.m");
evalin("base", "run(" + matlabString(startPath) + ")");

fileGenerationRoot = fullfile(runDir, "filegen");
cacheFolder = fullfile(fileGenerationRoot, "cache");
codegenFolder = fullfile(fileGenerationRoot, "codegen");
createDirectoryExclusive(fileGenerationRoot);
createDirectoryExclusive(cacheFolder);
createDirectoryExclusive(codegenFolder);
fileGenerationRootIdentity = pathIdentity(fileGenerationRoot, "directory");
cacheIdentity = pathIdentity(cacheFolder, "directory");
codegenIdentity = pathIdentity(codegenFolder, "directory");
Simulink.fileGenControl("set", "CacheFolder", cacheFolder, ...
    "CodeGenFolder", codegenFolder, "createDir", false);
activeFileGeneration = Simulink.fileGenControl("getConfig");
assertFileGeneration(activeFileGeneration, cacheFolder, codegenFolder, ...
    runDir, fileGenerationRootIdentity, cacheIdentity, codegenIdentity);
injectFailure("after_environment_setup", stagingDir);

assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
load_system(sourcePath);
assertLoadedFile(sourceModel, sourcePath);
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
assertFileGeneration(Simulink.fileGenControl("getConfig"), cacheFolder, ...
    codegenFolder, runDir, fileGenerationRootIdentity, cacheIdentity, ...
    codegenIdentity);
injectFailure("after_source_load");
sourceStates = stateSnapshot(sourceModel);
sourceSolver = solverSnapshot(sourceModel);
sourceSemantic = semanticSnapshot(sourceModel);
sourceWorkspace = modelWorkspaceSnapshot(sourceModel);
closeWithoutSaving(sourceModel);

assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
load_system(stagingCandidatePath);
assertLoadedFile(model, stagingCandidatePath);
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
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
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
save_system(model, stagingCandidatePath);
assertSameIdentity(runIdentity, runDir, "run directory");
assertSameIdentity(stagingIdentity, stagingDir, "staging directory");
stagingCandidateIdentity = pathIdentity(stagingCandidatePath, "file");
closeWithoutSaving(model);
injectFailure("after_candidate_save", stagingCandidatePath, sourcePath);

% Reopen the persisted bytes, perform the only diagram update, and audit
% without saving again so compilation side effects cannot enter candidate.slx.
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
load_system(stagingCandidatePath);
assertLoadedFile(model, stagingCandidatePath);
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
set_param(model, "SimulationCommand", "update")
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
assertFileGeneration(Simulink.fileGenControl("getConfig"), cacheFolder, ...
    codegenFolder, runDir, fileGenerationRootIdentity, cacheIdentity, ...
    codegenIdentity);
injectFailure("after_update");

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
assertPathOperationIdentities(runIdentity, runDir, stagingIdentity, ...
    stagingDir, stagingCandidateIdentity, stagingCandidatePath);
assertFileGeneration(Simulink.fileGenControl("getConfig"), cacheFolder, ...
    codegenFolder, runDir, fileGenerationRootIdentity, cacheIdentity, ...
    codegenIdentity);
restoreFileGeneration(oldFileGeneration);
assertFileGenerationRestored(oldFileGeneration);
restoreBaseWorkspace(baseSnapshot);

injectFailure("before_candidate_publish", candidatePath);
moveFileExclusive(stagingCandidatePath, candidatePath)
candidateIdentity = pathIdentity(candidatePath, "file");
if candidateIdentity.file_key ~= stagingCandidateIdentity.file_key
    error("fig519a3:AtomicMoveIdentityChanged", ...
        "Atomic publication changed the candidate file identity.");
end
assertSameIdentity(runIdentity, runDir, "run directory");
assertSameIdentity(stagingIdentity, stagingDir, "staging directory");

sourceHashAfter = sha256File(sourcePath);
runtimeAfter = runtimeIdentities(runtimeDir, repoRoot);
protectedAfter = protectedIdentities(protectedPath, repoRoot);
formalAfter = formalIdentities(repoRoot);
assertIdentitySetUnchanged(runtimeBefore, runtimeAfter, "runtime dependency");
assertIdentitySetUnchanged(protectedBefore, protectedAfter, "protected file");
assertIdentitySetUnchanged(formalBefore, formalAfter, "formal root file");
if sourceHashAfter ~= expectedSourceHash || sourceHashAfter ~= sourceHashBefore
    error("fig519a3:SourceChanged", ...
        "Candidate generation changed the immutable source model.");
end
assertRegularFile(candidatePath, "candidate model");
candidateHash = sha256File(candidatePath);

runtimeRecords = beforeAfterRecords(runtimeBefore, runtimeAfter);
protectedRecords = beforeAfterRecords(protectedBefore, protectedAfter);
formalRecords = beforeAfterFormalRecords(formalBefore, formalAfter);
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
injectFailure("after_audit_open", runDir, stagingDir);
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
    "formal_identity_schema", "repository_root_formal_identity_v1", ...
    "formal_files", formalRecords, ...
    "file_generation_settings", fileGenerationSettings, ...
    "threat_model", ...
        "private_0700_random_staging_and_repeated_no_follow_file_key_gates_detect_finite_replacement_but_do_not_claim_protection_against_a_continuously_mutating_same_uid_adversary", ...
    "artifact_audit", artifacts, ...
    "update_diagram_count", 1, ...
    "paper_reproduced", false, ...
    "author_initial_state_identified", false, ...
    "formal_promotion", false);

auditText = string(jsonencode(audit, PrettyPrint=true)) + newline;
writeOpenChannel(auditChannel, auditText);
injectFailure("after_audit_write");
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
restoreCallerState(sourceModel, model, oldFileGeneration, baseSnapshot, ...
    oldFolder, oldPath);
clear callerCleanup
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
maskRecords = strings(numel(blocks), 1);
maskInventory = repmat(struct("path", "", "mask_enabled", "", ...
    "mask_type", ""), numel(blocks), 1);
maskEnabledCount = 0;
lineInventory = repmat(struct("source", "", "destinations", strings(0, 1), ...
    "canonical", ""), 0, 1);
for index = 1:numel(blocks)
    relative = relativeBlockPath(blocks(index), model);
    maskEnabled = string(get_param(blocks(index), "Mask"));
    maskType = string(get_param(blocks(index), "MaskType"));
    if ~ismember(maskEnabled, ["on", "off"])
        error("fig519a3:MaskStateInvalid", ...
            "Every block must expose an on/off Mask state.");
    end
    maskEnabledCount = maskEnabledCount + double(maskEnabled == "on");
    maskInventory(index) = struct("path", relative, ...
        "mask_enabled", maskEnabled, "mask_type", maskType);
    maskRecords(index) = relative + "|" + maskEnabled + "|" + maskType;
    handles = get_param(blocks(index), "PortHandles");
    portKinds = sort(string(fieldnames(handles)));
    portCounts = strings(numel(portKinds), 1);
    for kindIndex = 1:numel(portKinds)
        portCounts(kindIndex) = portKinds(kindIndex) + ":" + ...
            string(numel(handles.(portKinds(kindIndex))));
    end
    blockRecords(index) = relative + "|" + ...
        string(get_param(blocks(index), "BlockType")) + "|" + ...
        maskEnabled + "|" + maskType + "|" + ...
        string(get_param(blocks(index), "ReferenceBlock"));
    portRecords(end + 1, 1) = relative + "|" + ...
        strjoin(portCounts, ","); %#ok<AGROW>
end
lines = find_system(model, "FindAll", "on", "Type", "line");
for index = 1:numel(lines)
    sourcePort = get_param(lines(index), "SrcPortHandle");
    destinationPorts = get_param(lines(index), "DstPortHandle");
    source = endpointIdentity(sourcePort, model, "<unconnected-source>");
    if isempty(destinationPorts)
        destinations = "<no-destination>";
    else
        destinations = strings(numel(destinationPorts), 1);
        for destinationIndex = 1:numel(destinationPorts)
            destinations(destinationIndex) = endpointIdentity( ...
                destinationPorts(destinationIndex), model, ...
                "<unconnected-destination>");
        end
    end
    destinations = sort(destinations(:));
    canonical = source + "->" + strjoin(destinations, ",");
    lineInventory(end + 1, 1) = struct("source", source, ...
        "destinations", destinations, "canonical", canonical); %#ok<AGROW>
end
portRecords = sort(portRecords);
if ~isempty(lineInventory)
    [~, order] = sort(string({lineInventory.canonical}));
    lineInventory = lineInventory(order);
end
lineRecords = string({lineInventory.canonical}).';
snapshot = struct( ...
    "block_count", numel(blockRecords), ...
    "port_owner_count", numel(portRecords), ...
    "line_count", numel(lineInventory), ...
    "edge_count", sum(arrayfun(@(item) numel(item.destinations), ...
        lineInventory)), ...
    "mask_enabled_count", maskEnabledCount, ...
    "mask_inventory", maskInventory, ...
    "mask_fingerprint", sha256Text(strjoin(maskRecords, newline)), ...
    "block_mask_fingerprint", ...
        sha256Text(strjoin(blockRecords, newline)), ...
    "port_fingerprint", sha256Text(strjoin(portRecords, newline)), ...
    "line_inventory", lineInventory, ...
    "line_fingerprint", sha256Text(strjoin(lineRecords, newline)));
end

function endpoint = endpointIdentity(portHandle, model, sentinel)
if isempty(portHandle) || portHandle == -1
    endpoint = sentinel;
    return
end
endpoint = relativeBlockPath(string(get_param(portHandle, "Parent")), model) + ...
    ":" + string(get_param(portHandle, "PortNumber"));
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

function records = formalIdentities(repoRoot)
fixed = ["final_steady_24a.slx"; "final_dynamic_24a.slx"; ...
    "HeXe_property_simulink.m"; "Lithium_property_simulink.m"];
matItems = dir(fullfile(repoRoot, "*.mat"));
names = unique([fixed; sort(string({matItems.name}).')], "stable");
records = repmat(struct("name", "", "repository_relative_path", "", ...
    "exists", false, "absolute_path", "", "file_key", "", ...
    "sha256", ""), numel(names), 1);
for index = 1:numel(names)
    filePath = fullfile(repoRoot, names(index));
    exists = isfile(filePath) || isfolder(filePath) || isSymbolicLink(filePath);
    if exists
        assertNoSymlinkAncestors(filePath, repoRoot);
        assertRegularFile(filePath, "formal root file");
        identity = pathIdentity(filePath, "file");
        absolutePath = identity.absolute_path;
        fileKey = identity.file_key;
        hash = sha256File(filePath);
    else
        absolutePath = string(java.io.File(filePath).getAbsolutePath());
        fileKey = "";
        hash = "";
    end
    records(index) = struct("name", names(index), ...
        "repository_relative_path", names(index), "exists", exists, ...
        "absolute_path", absolutePath, "file_key", fileKey, ...
        "sha256", hash);
end
end

function output = beforeAfterFormalRecords(before, after)
if numel(before) ~= numel(after) || ...
        ~isequal(string({before.repository_relative_path}), ...
        string({after.repository_relative_path}))
    error("fig519a3:FormalIdentitySetChanged", ...
        "Formal root identity record names changed.");
end
output = repmat(struct("repository_relative_path", "", ...
    "exists_before", false, "exists_after", false, ...
    "absolute_path", "", "before_file_key", "", ...
    "after_file_key", "", "before_sha256", "", "after_sha256", "", ...
    "unchanged", false), numel(before), 1);
for index = 1:numel(before)
    unchanged = isequal(before(index), after(index));
    output(index) = struct( ...
        "repository_relative_path", before(index).repository_relative_path, ...
        "exists_before", before(index).exists, ...
        "exists_after", after(index).exists, ...
        "absolute_path", before(index).absolute_path, ...
        "before_file_key", before(index).file_key, ...
        "after_file_key", after(index).file_key, ...
        "before_sha256", before(index).sha256, ...
        "after_sha256", after(index).sha256, "unchanged", unchanged);
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
[files, directories] = walkArtifactTree(runDir, runDir);
artifacts = struct( ...
    "candidate_regular_file", isRegularFile(candidatePath), ...
    "candidate_symlink", isSymbolicLink(candidatePath), ...
    "candidate_contained", isContained(candidatePath, runDir), ...
    "audit_regular_file", isRegularFile(auditPath), ...
    "audit_symlink", isSymbolicLink(auditPath), ...
    "audit_contained", isContained(auditPath, runDir), ...
    "all_paths_contained", all([files.contained]) && ...
        all([directories.contained]), ...
    "all_files_regular", all([files.regular_file]), ...
    "all_directories_real", all([directories.real_directory]), ...
    "any_symlink", any([files.symlink]) || any([directories.symlink]), ...
    "files", files, "directories", directories, ...
    "raw_result_present", isfile(fullfile(runDir, "raw_result.mat")), ...
    "run_directory_present", isfolder(fullfile(runDir, "run")));
if ~artifacts.candidate_regular_file || artifacts.candidate_symlink || ...
        ~artifacts.candidate_contained || ~artifacts.audit_regular_file || ...
        artifacts.audit_symlink || ~artifacts.audit_contained || ...
        ~artifacts.all_paths_contained || ~artifacts.all_files_regular || ...
        ~artifacts.all_directories_real || ...
        artifacts.any_symlink || artifacts.raw_result_present || ...
        artifacts.run_directory_present
    error("fig519a3:ArtifactAuditFailed", ...
        "The zero-simulation candidate artifact audit failed.");
end
end

function [files, directories] = walkArtifactTree(root, current)
files = repmat(struct("repository_relative_path", "", ...
    "absolute_path", "", "file_key", "", "regular_file", false, ...
    "symlink", false, "contained", false), 0, 1);
directories = repmat(struct("repository_relative_path", "", ...
    "absolute_path", "", "file_key", "", "real_directory", false, ...
    "symlink", false, "contained", false), 0, 1);
stream = java.nio.file.Files.newDirectoryStream(nioPath(current));
streamCleanup = onCleanup(@() stream.close());
iterator = stream.iterator();
children = strings(0, 1);
while iterator.hasNext()
    children(end + 1, 1) = string(iterator.next().toString()); %#ok<AGROW>
end
clear streamCleanup
stream.close();
children = sort(children);
for index = 1:numel(children)
    itemPath = children(index);
    symlink = isSymbolicLink(itemPath);
    contained = isContainedLexically(itemPath, root);
    if symlink || ~contained
        error("fig519a3:UnsafeArtifact", ...
            "Artifact entries must be contained and must not be symlinks.");
    end
    relative = lexicalRelative(itemPath, root);
    if isDirectoryNoFollow(itemPath)
        identity = pathIdentity(itemPath, "directory");
        directories(end + 1, 1) = struct( ...
            "repository_relative_path", relative, ...
            "absolute_path", identity.absolute_path, ...
            "file_key", identity.file_key, "real_directory", true, ...
            "symlink", false, "contained", true); %#ok<AGROW>
        [nestedFiles, nestedDirectories] = walkArtifactTree(root, itemPath);
        files = [files; nestedFiles]; %#ok<AGROW>
        directories = [directories; nestedDirectories]; %#ok<AGROW>
    elseif isRegularFile(itemPath)
        identity = pathIdentity(itemPath, "file");
        files(end + 1, 1) = struct( ...
            "repository_relative_path", relative, ...
            "absolute_path", identity.absolute_path, ...
            "file_key", identity.file_key, "regular_file", true, ...
            "symlink", false, "contained", true); %#ok<AGROW>
    else
        error("fig519a3:UnsafeArtifact", ...
            "Artifact entries must be regular files or real directories.");
    end
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

function restoreCallerState(sourceModel, model, fileGeneration, ...
        baseSnapshot, folder, matlabPath)
closeWithoutSaving(model);
closeWithoutSaving(sourceModel);
restoreFileGeneration(fileGeneration);
restoreBaseWorkspace(baseSnapshot);
cd(folder);
path(matlabPath);
end

function restoreFileGeneration(config)
Simulink.fileGenControl("set", "CacheFolder", config.CacheFolder, ...
    "CodeGenFolder", config.CodeGenFolder, "createDir", true);
end

function assertFileGeneration(config, cacheFolder, codegenFolder, runDir, ...
        rootIdentity, cacheIdentity, codegenIdentity)
if canonicalPath(config.CacheFolder) ~= canonicalPath(cacheFolder) || ...
        canonicalPath(config.CodeGenFolder) ~= canonicalPath(codegenFolder) || ...
        ~isContained(config.CacheFolder, runDir) || ...
        ~isContained(config.CodeGenFolder, runDir)
    error("fig519a3:FileGenerationConfigurationMismatch", ...
        "Active file-generation folders are not the bound contained folders.");
end
assertSameIdentity(rootIdentity, fileparts(cacheFolder), ...
    "file-generation root");
assertSameIdentity(cacheIdentity, cacheFolder, "cache folder");
assertSameIdentity(codegenIdentity, codegenFolder, "codegen folder");
end

function assertFileGenerationRestored(expected)
actual = Simulink.fileGenControl("getConfig");
if ~isequal(string(actual.CacheFolder), string(expected.CacheFolder)) || ...
        ~isequal(string(actual.CodeGenFolder), string(expected.CodeGenFolder))
    error("fig519a3:FileGenerationRestoreFailed", ...
        "File-generation settings were not restored exactly.");
end
end

function snapshot = captureStartupWorkspace()
names = ["ETAT_table"; "N_design"; "PR_design"; "PR_table"; ...
    "P_in_design"; "P_out_design"; "P_out_table"; "Power_design"; ...
    "Power_table"; "T_in_design"; "T_out_design"; "T_out_table"; ...
    "choke_m_ratio"; "common_valid_flow_ratio"; "coordinate_definition"; ...
    "cp_hexe"; "description"; "eta_design"; "gamma_hexe"; ...
    "m_ratio_bp"; "mdot_design"; "provenance"; "reference"; ...
    "simulink_usage"; "speed_bp"; "surge_m_ratio"; ...
    "valid_flow_ratio_by_speed"; "valid_mask"; "version"; ...
    "A_rad"; "Cp_rad"; "M_rad"; "ans"; "epsilon"; "h_h"; ...
    "out"; "theta"; "bp_er"; "bp_speed"; "table_mf"; "bp_mf"; ...
    "table_eff"; "I_TAC"; "scriptDir"; "paper54"];
base = Simulink.data.BaseWorkspace;
accessor = base.getDataAccessor;
snapshot = repmat(struct("name", "", "existed", false, "value", []), ...
    numel(names), 1);
for index = 1:numel(names)
    snapshot(index).name = names(index);
    snapshot(index).existed = logical(base.exist(char(names(index))));
    if snapshot(index).existed
        identifiers = accessor.identifyByName(char(names(index)));
        if isempty(identifiers)
            error("fig519a3:BaseWorkspaceCaptureFailed", ...
                "Could not capture startup variable %s.", names(index));
        end
        snapshot(index).value = accessor.getVariable(identifiers(1));
    end
end
end

function restoreBaseWorkspace(snapshot)
base = Simulink.data.BaseWorkspace;
for index = 1:numel(snapshot)
    if snapshot(index).existed
        base.assignin(char(snapshot(index).name), snapshot(index).value);
    elseif base.exist(char(snapshot(index).name))
        base.clear(char(snapshot(index).name));
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
javaPath = nioPath(pathValue);
tf = java.nio.file.Files.isRegularFile(javaPath, ...
    noFollowOptions());
end

function tf = isSymbolicLink(pathValue)
javaPath = nioPath(pathValue);
tf = java.nio.file.Files.isSymbolicLink(javaPath);
end

function tf = isDirectoryNoFollow(pathValue)
tf = java.nio.file.Files.isDirectory(nioPath(pathValue), noFollowOptions());
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

function tf = isContainedLexically(pathValue, root)
pathValue = string(nioPath(pathValue).toAbsolutePath().normalize().toString());
root = string(nioPath(root).toAbsolutePath().normalize().toString());
tf = pathValue ~= root && startsWith(pathValue, root + filesep);
end

function relative = lexicalRelative(pathValue, root)
relative = string(nioPath(root).toAbsolutePath().normalize().relativize( ...
    nioPath(pathValue).toAbsolutePath().normalize()).toString());
relative = replace(relative, filesep, "/");
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

function moveFileExclusive(sourcePath, candidatePath)
try
    java.nio.file.Files.createLink(nioPath(candidatePath), nioPath(sourcePath));
    linkedIdentity = pathIdentity(candidatePath, "file");
    sourceIdentity = pathIdentity(sourcePath, "file");
    if linkedIdentity.file_key ~= sourceIdentity.file_key
        error("fig519a3:AtomicPublishIdentityMismatch", ...
            "Exclusive hard-link publication changed file identity.");
    end
    java.nio.file.Files.delete(nioPath(sourcePath));
catch exception
    if isfile(candidatePath) || isfolder(candidatePath) || ...
            isSymbolicLink(candidatePath)
        error("fig519a3:CandidateExists", ...
            "Refusing to overwrite public candidate '%s'.", candidatePath);
    end
    rethrow(exception)
end
end

function moveDirectoryExclusive(sourcePath, destinationPath)
options = javaArray("java.nio.file.CopyOption", 0);
java.nio.file.Files.move(nioPath(sourcePath), nioPath(destinationPath), options);
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

function stagingDir = createPrivateStagingDirectory(runDir)
for attempt = 1:16
    stagingDir = fullfile(runDir, ".fig519a3-stage-" + ...
        string(char(java.util.UUID.randomUUID)));
    try
        createDirectoryExclusive(stagingDir);
        permissions = java.nio.file.attribute.PosixFilePermissions.fromString( ...
            "rwx------");
        java.nio.file.Files.setPosixFilePermissions(nioPath(stagingDir), permissions);
        assertSameIdentity(pathIdentity(stagingDir, "directory"), stagingDir, ...
            "private staging directory");
        return
    catch exception
        if ~strcmp(exception.identifier, "fig519a3:RunDirExists")
            rethrow(exception)
        end
    end
end
error("fig519a3:StagingCreationFailed", ...
    "Could not create an exclusive randomized private staging directory.");
end

function identity = pathIdentity(pathValue, expectedKind)
javaPath = nioPath(pathValue);
if java.nio.file.Files.isSymbolicLink(javaPath)
    error("fig519a3:SymlinkForbidden", ...
        "Identity-bound paths must not be symlinks: %s", pathValue);
end
attributes = java.nio.file.Files.readAttributes(javaPath, ...
    "basic:fileKey,isDirectory,isRegularFile", noFollowOptions());
isDirectory = logical(attributes.get("isDirectory"));
isRegular = logical(attributes.get("isRegularFile"));
if (expectedKind == "directory" && ~isDirectory) || ...
        (expectedKind == "file" && ~isRegular)
    error("fig519a3:IdentityKindMismatch", ...
        "Identity-bound path has the wrong kind: %s", pathValue);
end
fileKey = string(attributes.get("fileKey"));
if strlength(fileKey) == 0 || fileKey == "null"
    error("fig519a3:FileKeyUnavailable", ...
        "A stable no-follow file key is required: %s", pathValue);
end
identity = struct("absolute_path", ...
    string(javaPath.toAbsolutePath().normalize().toString()), ...
    "file_key", fileKey, "kind", expectedKind);
end

function assertSameIdentity(expected, pathValue, label)
actual = pathIdentity(pathValue, expected.kind);
if actual.absolute_path ~= expected.absolute_path || ...
        actual.file_key ~= expected.file_key
    error("fig519a3:PathIdentityChanged", ...
        "%s was replaced during candidate generation.", label);
end
end

function assertPathOperationIdentities(runIdentity, runDir, ...
        stagingIdentity, stagingDir, candidateIdentity, candidatePath)
assertSameIdentity(runIdentity, runDir, "run directory");
assertSameIdentity(stagingIdentity, stagingDir, "staging directory");
assertSameIdentity(candidateIdentity, candidatePath, "staging candidate");
end

function injectFailure(point, varargin)
key = "fig519a3_test_failure_point";
if ~isappdata(0, key)
    return
end
hook = getappdata(0, key);
if (isstring(hook) || ischar(hook)) && string(hook) == string(point)
    error("fig519a3:InjectedFailure", ...
        "Deterministic zero-simulation test failure at %s.", point);
end
if ~isstruct(hook) || ~isfield(hook, "point") || ...
        string(hook.point) ~= string(point)
    return
end
action = string(hook.action);
switch action
    case "replace_staging_directory"
        original = string(varargin{1});
        displaced = original + ".replaced-" + ...
            string(char(java.util.UUID.randomUUID));
        moveDirectoryExclusive(original, displaced);
        createDirectoryExclusive(original);
    case "replace_hashed_candidate"
        % Performed inside sha256File after the no-follow channel is open.
    case "install_public_candidate"
        publicPath = string(varargin{1});
        channel = openFileExclusive(publicPath);
        writeOpenChannel(channel, "replacement");
        channel.close();
    case "install_symlink_directory"
        linkPath = fullfile(string(varargin{1}), ...
            "injected-symlink-directory");
        java.nio.file.Files.createSymbolicLink(nioPath(linkPath), ...
            nioPath(string(varargin{2})), ...
            javaArray("java.nio.file.attribute.FileAttribute", 0));
    otherwise
        error("fig519a3:InvalidTestHook", ...
            "The zero-simulation test hook action is not allowlisted.");
end
end

function injectHashReplacement(filePath)
key = "fig519a3_test_failure_point";
if ~isappdata(0, key)
    return
end
hook = getappdata(0, key);
if ~isstruct(hook) || ~isfield(hook, "point") || ...
        string(hook.point) ~= "during_hash" || ...
        string(hook.action) ~= "replace_hashed_candidate" || ...
        ~endsWith(string(filePath), "candidate.slx")
    return
end
displaced = string(filePath) + ".replaced-" + ...
    string(char(java.util.UUID.randomUUID));
moveFileExclusive(filePath, displaced);
channel = openFileExclusive(filePath);
writeOpenChannel(channel, "replacement");
channel.close();
end

function javaPath = nioPath(pathValue)
javaPath = java.nio.file.Paths.get(char(string(pathValue)), ...
    javaArray("java.lang.String", 0));
end

function options = noFollowOptions()
options = javaArray("java.nio.file.LinkOption", 1);
options(1) = java.nio.file.LinkOption.NOFOLLOW_LINKS;
end

function hash = sha256File(filePath)
before = pathIdentity(filePath, "file");
options = javaArray("java.nio.file.OpenOption", 2);
options(1) = java.nio.file.StandardOpenOption.READ;
options(2) = java.nio.file.LinkOption.NOFOLLOW_LINKS;
channel = java.nio.file.Files.newByteChannel(nioPath(filePath), options);
cleanup = onCleanup(@() closeChannel(channel));
injectHashReplacement(filePath);
digest = java.security.MessageDigest.getInstance("SHA-256");
buffer = java.nio.ByteBuffer.allocate(1024 * 1024);
while true
    count = channel.read(buffer);
    if count < 0
        break
    end
    if count == 0
        continue
    end
    digest.update(buffer.array(), 0, count);
    buffer.clear();
end
channel.close();
clear cleanup
assertSameIdentity(before, filePath, "hashed file");
raw = digest.digest();
hash = string(lower(reshape(dec2hex(typecast(raw, "uint8"), 2).', 1, [])));
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
