function tests = test_run_speed_hypothesis
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = root;
testCase.TestData.source = fullfile(root, "final_steady_24a.slx");
testCase.TestData.sourceHash = ...
    "08b903324a5bf60a16d7b019fd83de7e7937242627e592ba7368404a817dc27a";
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testHashMismatchPrecedesArtifactCreation(testCase)
tmpRoot = string(tempname);
options = struct( ...
    "tmpRoot", tmpRoot, ...
    "stopTime_s", 1, ...
    "publishCurrent", false, ...
    "expectedSourceHash", repmat('0', 1, 64));

verifyError(testCase, @() run_speed_hypothesis(options), ...
    "steady53:UnexpectedSourceHash");
verifyFalse(testCase, isfolder(tmpRoot));
end

function testPreloadedModelsAreRejectedWithoutMutation(testCase)
tmpRoot = string(tempname);
options = shortOptions(tmpRoot, false);

load_system(testCase.TestData.source);
sourceCleanup = onCleanup(@() closeIfLoaded("final_steady_24a"));
set_param("final_steady_24a/TAC/Constant", "Value", "12345");
verifyError(testCase, @() run_speed_hypothesis(options), ...
    "steady53:SourceModelAlreadyLoaded");
verifyTrue(testCase, bdIsLoaded("final_steady_24a"));
verifyEqual(testCase, string(get_param( ...
    "final_steady_24a/TAC/Constant", "Value")), "12345");
verifyFalse(testCase, isfolder(tmpRoot));
clear sourceCleanup

ownedTestRoot = string(tempname);
mkdir(ownedTestRoot);
rootCleanup = onCleanup(@() removeTestDirectory(ownedTestRoot));
copyPath = fullfile(ownedTestRoot, "final_steady_speed55090.slx");
copyfile(testCase.TestData.source, copyPath);
copyHashBefore = sha256File(copyPath);
load_system(copyPath);
copyCleanup = onCleanup(@() closeIfLoaded("final_steady_speed55090"));
set_param("final_steady_speed55090/TAC/Constant", "Value", "12345");
verifyError(testCase, @() run_speed_hypothesis(options), ...
    "steady53:ExplorationModelAlreadyLoaded");
verifyTrue(testCase, bdIsLoaded("final_steady_speed55090"));
verifyEqual(testCase, string(get_param( ...
    "final_steady_speed55090/TAC/Constant", "Value")), "12345");
verifyEqual(testCase, sha256File(copyPath), copyHashBefore);
verifyFalse(testCase, isfolder(tmpRoot));
clear copyCleanup rootCleanup
end

function testUnknownAndOneSidedArtifactsAreNeverOverwritten(testCase)
for mode = ["unknown_pair", "copy_only"]
    tmpRoot = string(tempname);
    mkdir(tmpRoot);
    cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
    copyPath = fullfile(tmpRoot, "final_steady_speed55090.slx");
    writeText(copyPath, "unknown artifact");
    if mode == "unknown_pair"
        result = struct("success", true);
        summary = struct("sourceHashBefore", "forged");
        save(fullfile(tmpRoot, "speed55090_result.mat"), ...
            "result", "summary");
    end
    copyHashBefore = sha256File(copyPath);
    options = shortOptions(tmpRoot, true);
    verifyError(testCase, @() run_speed_hypothesis(options), ...
        "steady53:UnownedExplorationArtifact");
    verifyEqual(testCase, sha256File(copyPath), copyHashBefore);
    verifyFalse(testCase, isfile(fullfile( ...
        tmpRoot, "speed55090_current.mat")));
    verifyFalse(testCase, isfolder(fullfile(tmpRoot, "runs")));
    clear cleanup
end
end

function testInjectedFailuresPublishRunFailureAndRestoreEnvironment(testCase)
for point = ["after_save", "before_runner"]
    tmpRoot = string(tempname);
    cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
    Simulink.fileGenControl("getConfig");
    environmentBefore = environmentSnapshot();
    baseGuard = preserveBaseVariables(["N_design", ...
        "steady53_failure_sentinel"]); %#ok<NASGU>
    assignin("base", "N_design", -123);
    assignin("base", "steady53_failure_sentinel", pi);
    baseNamesBefore = baseWorkspaceNames();
    warningBefore = warning("query", "HeXe:T_lo");
    warning("off", "HeXe:T_lo");
    warningExpected = warning("query", "HeXe:T_lo");
    options = shortOptions(tmpRoot, false);
    options.injectFailureAt = point;

    verifyError(testCase, @() run_speed_hypothesis(options), ...
        "steady53:InjectedSpeedHypothesisFailure");
    verifyEnvironmentRestored(testCase, environmentBefore);
    verifyEqual(testCase, warning("query", "HeXe:T_lo"), ...
        warningExpected);
    verifyEqual(testCase, baseWorkspaceNames(), baseNamesBefore);
    verifyEqual(testCase, evalin("base", "N_design"), -123);
    verifyEqual(testCase, evalin("base", ...
        "steady53_failure_sentinel"), pi);
    verifyFalse(testCase, bdIsLoaded("final_steady_speed55090"));
    verifyEqual(testCase, sha256File(testCase.TestData.source), ...
        testCase.TestData.sourceHash);

    runs = runDirectories(tmpRoot);
    verifyNumElements(testCase, runs, 1);
    runDirectory = fullfile(runs(1).folder, runs(1).name);
    verifyTrue(testCase, isfile(fullfile(runDirectory, "failure.mat")));
    verifyTrue(testCase, isfile(fullfile(runDirectory, "errorReport.txt")));
    verifyFalse(testCase, isfile(fullfile( ...
        runDirectory, "speed55090_result.mat")));
    loaded = load(fullfile(runDirectory, "failure.mat"), "failure");
    verifyEqual(testCase, string(loaded.failure.runId), ...
        string(runs(1).name));
    verifyEqual(testCase, string(loaded.failure.status), "tool_failed");
    verifyEqual(testCase, string(loaded.failure.errorId), ...
        "steady53:InjectedSpeedHypothesisFailure");
    verifyEqual(testCase, string(loaded.failure.sourceHashBefore), ...
        testCase.TestData.sourceHash);
    verifyEqual(testCase, string(loaded.failure.sourceHashAfter), ...
        testCase.TestData.sourceHash);
    verifyFalse(testCase, isfile(fullfile( ...
        tmpRoot, "speed55090_current.mat")));

    warning(warningBefore.state, warningBefore.identifier);
    clear baseGuard cleanup
end
end

function testNormalShortRunIsSelfConsistentAndSemanticallyMinimal(testCase)
tmpRoot = string(tempname);
cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
summary = run_speed_hypothesis(shortOptions(tmpRoot, false));

verifyTrue(testCase, summary.success, summary.errorReport);
verifyEqual(testCase, summary.tFinal_s, 1, "AbsTol", 1e-12);
verifyEqual(testCase, string(summary.status), "completed");
verifyEqual(testCase, string(summary.sourceHash), ...
    testCase.TestData.sourceHash);
verifyEqual(testCase, string(summary.sourceHashBefore), ...
    testCase.TestData.sourceHash);
verifyEqual(testCase, string(summary.sourceHashAfter), ...
    testCase.TestData.sourceHash);
verifyTrue(testCase, summary.sourceUnchanged);
verifyEqual(testCase, summary.normalizedCompressorSpeed, 1);
verifyTrue(testCase, summary.compressorSpeedInRange);
verifyFalse(testCase, any(isfield(summary, {'t', 'signals', 'states'})));
verifyTrue(testCase, isfolder(summary.runDirectory));
verifyTrue(testCase, isfile(summary.explorationCopyPath));
verifyTrue(testCase, isfile(summary.resultPath));
verifyEqual(testCase, sha256File(summary.explorationCopyPath), ...
    string(summary.copyHash));

loaded = load(summary.resultPath, "result", "summary");
verifyEqual(testCase, string(loaded.result.runId), string(summary.runId));
verifyEqual(testCase, string(loaded.summary.runId), string(summary.runId));
verifyTrue(testCase, all(isfield(loaded.result, ...
    {'t', 'signals', 'states'})));
verifyOnlyExpectedSemanticDelta(testCase, testCase.TestData.source, ...
    summary.explorationCopyPath, "1");
clear cleanup
end

function testRepeatedRunsUseDistinctImmutableDirectories(testCase)
tmpRoot = string(tempname);
cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
options = shortOptions(tmpRoot, false);
first = run_speed_hypothesis(options);
firstResultHash = sha256File(first.resultPath);
firstCopyHash = sha256File(first.explorationCopyPath);
second = run_speed_hypothesis(options);

verifyNotEqual(testCase, string(first.runId), string(second.runId));
verifyNotEqual(testCase, string(first.runDirectory), ...
    string(second.runDirectory));
verifyEqual(testCase, sha256File(first.resultPath), firstResultHash);
verifyEqual(testCase, sha256File(first.explorationCopyPath), firstCopyHash);
verifyTrue(testCase, isfile(second.resultPath));
verifyNumElements(testCase, runDirectories(tmpRoot), 2);
clear cleanup
end

function testMarkerCrossValidationAndTamperDetection(testCase)
tmpRoot = string(tempname);
cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
summary = run_speed_hypothesis(shortOptions(tmpRoot, true));
validateOptions = shortOptions(tmpRoot, false);
validateOptions.validateCurrentOnly = true;
current = run_speed_hypothesis(validateOptions);

verifyEqual(testCase, current.schemaVersion, 2);
verifyEqual(testCase, string(current.runId), string(summary.runId));
verifyFalse(testCase, current.cacheRebuilt);
verifyEqual(testCase, sha256File(current.copyPath), ...
    string(current.copyHash));
verifyEqual(testCase, sha256File(current.resultPath), ...
    string(current.resultHash));
verifyEqual(testCase, sha256File(current.runCopyPath), ...
    string(current.copyHash));
verifyEqual(testCase, sha256File(current.runResultPath), ...
    string(current.resultHash));

writeText(current.resultPath, "tampered current result");
repaired = run_speed_hypothesis(validateOptions);
verifyTrue(testCase, repaired.cacheRebuilt);
verifyEqual(testCase, sha256File(repaired.resultPath), ...
    string(repaired.resultHash));
delete(repaired.copyPath);
repaired = run_speed_hypothesis(validateOptions);
verifyTrue(testCase, repaired.cacheRebuilt);
verifyEqual(testCase, sha256File(repaired.copyPath), ...
    string(repaired.copyHash));

markerPath = fullfile(tmpRoot, "speed55090_current.mat");
pristine = load(markerPath, "current");
tamperCases = { ...
    "status", "tampered"; ...
    "completedAt", "1999-01-01T00:00:00.000Z"; ...
    "runDirectory", string(tempname); ...
    "runId", "run_tampered"; ...
    "runCopyPath", string(tempname) + ".slx"; ...
    "runResultPath", string(tempname) + ".mat"};
for index = 1:size(tamperCases, 1)
    current = pristine.current;
    current.(tamperCases{index, 1}) = tamperCases{index, 2};
    save(markerPath, "current");
    verifyError(testCase, @() run_speed_hypothesis(validateOptions), ...
        "steady53:MarkerMismatch", ...
        "Marker field was accepted: " + tamperCases{index, 1});
    current = pristine.current;
    save(markerPath, "current");
end
finalCurrent = run_speed_hypothesis(validateOptions);
verifyEqual(testCase, string(finalCurrent.runId), string(summary.runId));
clear cleanup
end

function testPublicationInterruptionsPreserveOrRecoverAuthority(testCase)
tmpRoot = string(tempname);
cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
validateOptions = shortOptions(tmpRoot, false);
validateOptions.validateCurrentOnly = true;

baseline = run_speed_hypothesis(shortOptions(tmpRoot, true));
oldCurrent = run_speed_hypothesis(validateOptions);
verifyEqual(testCase, string(oldCurrent.runId), string(baseline.runId));

beforeMarker = shortOptions(tmpRoot, true);
beforeMarker.stopTime_s = 1.05;
beforeMarker.injectFailureAt = "before_marker_move";
verifyError(testCase, @() run_speed_hypothesis(beforeMarker), ...
    "steady53:InjectedSpeedHypothesisFailure");
stillOld = run_speed_hypothesis(validateOptions);
verifyEqual(testCase, string(stillOld.runId), string(oldCurrent.runId));
verifyFalse(testCase, stillOld.cacheRebuilt);

afterMarker = shortOptions(tmpRoot, true);
afterMarker.stopTime_s = 1.1;
afterMarker.injectFailureAt = "after_marker_move_before_cache";
verifyError(testCase, @() run_speed_hypothesis(afterMarker), ...
    "steady53:InjectedSpeedHypothesisFailure");
newCurrent = run_speed_hypothesis(validateOptions);
verifyNotEqual(testCase, string(newCurrent.runId), string(stillOld.runId));
verifyTrue(testCase, newCurrent.cacheRebuilt);
verifyEqual(testCase, sha256File(newCurrent.copyPath), ...
    string(newCurrent.copyHash));
verifyEqual(testCase, sha256File(newCurrent.resultPath), ...
    string(newCurrent.resultHash));

afterCopy = shortOptions(tmpRoot, true);
afterCopy.stopTime_s = 1.2;
afterCopy.injectFailureAt = "after_current_copy_move";
verifyError(testCase, @() run_speed_hypothesis(afterCopy), ...
    "steady53:InjectedSpeedHypothesisFailure");
copyInterrupted = run_speed_hypothesis(validateOptions);
verifyNotEqual(testCase, string(copyInterrupted.runId), ...
    string(newCurrent.runId));
verifyTrue(testCase, copyInterrupted.cacheRebuilt);
verifyEqual(testCase, sha256File(copyInterrupted.copyPath), ...
    string(copyInterrupted.copyHash));
verifyEqual(testCase, sha256File(copyInterrupted.resultPath), ...
    string(copyInterrupted.resultHash));

nextOptions = shortOptions(tmpRoot, true);
nextOptions.stopTime_s = 1.3;
next = run_speed_hypothesis(nextOptions);
finalCurrent = run_speed_hypothesis(validateOptions);
verifyEqual(testCase, string(finalCurrent.runId), string(next.runId));
verifyFalse(testCase, finalCurrent.cacheRebuilt);
clear cleanup
end

function testMarkerlessPairIsRejectedEvenWithSynchronizedSelfReport(testCase)
tmpRoot = string(tempname);
cleanup = onCleanup(@() removeTestDirectory(tmpRoot));
unpublishedRun = run_speed_hypothesis(shortOptions(tmpRoot, false));
fixedCopy = fullfile(tmpRoot, "final_steady_speed55090.slx");
fixedResult = fullfile(tmpRoot, "speed55090_result.mat");
copyfile(unpublishedRun.explorationCopyPath, fixedCopy);
load_system(fixedCopy);
modelCleanup = onCleanup(@() closeIfLoaded("final_steady_speed55090"));
set_param("final_steady_speed55090/Constant14", "Value", "1087001");
save_system("final_steady_speed55090", fixedCopy);
clear modelCleanup
forgedCopyHash = sha256File(fixedCopy);
loaded = load(unpublishedRun.resultPath, "result", "summary");
result = loaded.result;
summary = loaded.summary;
result.copyHash = forgedCopyHash;
summary.copyHash = forgedCopyHash;
summary.explorationCopyHash = forgedCopyHash;
save(fixedResult, "result", "summary", "-v7.3");

verifyError(testCase, @() run_speed_hypothesis( ...
    shortOptions(tmpRoot, true)), ...
    "steady53:UnownedExplorationArtifact");
verifyFalse(testCase, isfile(fullfile( ...
    tmpRoot, "speed55090_current.mat")));
verifyEqual(testCase, sha256File(fixedCopy), forgedCopyHash);
clear cleanup
end

function options = shortOptions(tmpRoot, publishCurrent)
options = struct( ...
    "tmpRoot", string(tmpRoot), ...
    "stopTime_s", 1, ...
    "publishCurrent", logical(publishCurrent));
end

function verifyOnlyExpectedSemanticDelta(testCase, sourcePath, copyPath, ...
        expectedStopTime)
sourceModel = "final_steady_24a";
copyModel = "final_steady_speed55090";
load_system(sourcePath);
sourceCleanup = onCleanup(@() closeIfLoaded(sourceModel));
load_system(copyPath);
copyCleanup = onCleanup(@() closeIfLoaded(copyModel));

sourceBlocks = string(find_system(sourceModel, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
copyBlocks = string(find_system(copyModel, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
sourceRelative = erase(sourceBlocks, sourceModel);
copyRelative = erase(copyBlocks, copyModel);
verifyEqual(testCase, sort(sourceRelative), sort(copyRelative));

differentDialogValues = strings(0, 1);
for relative = sourceRelative(:).'
    sourceBlock = sourceModel + relative;
    copyBlock = copyModel + relative;
    verifyEqual(testCase, string(get_param(sourceBlock, "BlockType")), ...
        string(get_param(copyBlock, "BlockType")));
    sourceDialog = get_param(sourceBlock, "DialogParameters");
    copyDialog = get_param(copyBlock, "DialogParameters");
    if isempty(sourceDialog) && isempty(copyDialog)
        continue
    end
    verifyTrue(testCase, isstruct(sourceDialog));
    verifyTrue(testCase, isstruct(copyDialog));
    sourceNames = string(fieldnames(sourceDialog));
    copyNames = string(fieldnames(copyDialog));
    verifyEqual(testCase, sort(sourceNames), sort(copyNames));
    for parameter = sourceNames(:).'
        sourceValue = get_param(sourceBlock, parameter);
        copyValue = get_param(copyBlock, parameter);
        if ~isequaln(sourceValue, copyValue)
            differentDialogValues(end + 1, 1) = ...
                relative + "::" + parameter; %#ok<AGROW>
        end
    end
end
verifyEqual(testCase, differentDialogValues, "/TAC/Constant::Value");
verifyEqual(testCase, string(get_param(sourceModel, "StopTime")), "800");
verifyEqual(testCase, string(get_param(copyModel, "StopTime")), ...
    string(expectedStopTime));
verifyEqual(testCase, lineSignatures(sourceModel), ...
    lineSignatures(copyModel));
clear copyCleanup sourceCleanup
end

function signatures = lineSignatures(model)
lines = find_system(model, "FindAll", "on", "Type", "line");
signatures = strings(0, 1);
for index = 1:numel(lines)
    sourceBlock = get_param(lines(index), "SrcBlockHandle");
    sourcePort = get_param(lines(index), "SrcPortHandle");
    destinationBlocks = get_param(lines(index), "DstBlockHandle");
    destinationPorts = get_param(lines(index), "DstPortHandle");
    if sourceBlock < 0 || isempty(destinationBlocks)
        continue
    end
    sourceName = erase(string(getfullname(sourceBlock)), string(model));
    sourceNumber = string(get_param(sourcePort, "PortNumber"));
    for destinationIndex = 1:numel(destinationBlocks)
        if destinationBlocks(destinationIndex) < 0
            continue
        end
        destinationName = erase(string(getfullname( ...
            destinationBlocks(destinationIndex))), string(model));
        destinationNumber = string(get_param( ...
            destinationPorts(destinationIndex), "PortNumber"));
        signatures(end + 1, 1) = sourceName + ":" + sourceNumber + ...
            "->" + destinationName + ":" + destinationNumber; %#ok<AGROW>
    end
end
signatures = sort(signatures);
end

function snapshot = environmentSnapshot()
snapshot = struct( ...
    "path", path, ...
    "pwd", string(pwd), ...
    "fileGeneration", Simulink.fileGenControl("getConfig"));
end

function verifyEnvironmentRestored(testCase, expected)
verifyEqual(testCase, path, expected.path);
verifyEqual(testCase, string(pwd), expected.pwd);
verifyEqual(testCase, Simulink.fileGenControl("getConfig"), ...
    expected.fileGeneration);
end

function cleanup = preserveBaseVariables(names)
names = string(names(:));
existed = false(size(names));
values = cell(size(names));
for index = 1:numel(names)
    existed(index) = evalin("base", ...
        "exist('" + names(index) + "','var') == 1");
    if existed(index)
        values{index} = evalin("base", names(index));
    end
end
cleanup = onCleanup(@() restoreBaseVariables(names, existed, values));
end

function restoreBaseVariables(names, existed, values)
for index = 1:numel(names)
    if existed(index)
        assignin("base", names(index), values{index});
    else
        evalin("base", "clear " + names(index));
    end
end
end

function names = baseWorkspaceNames()
names = sort(string(evalin("base", "who")));
end

function runs = runDirectories(tmpRoot)
runs = dir(fullfile(tmpRoot, "runs", "run_*"));
runs = runs([runs.isdir]);
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function removeTestDirectory(directory)
closeIfLoaded("final_steady_24a");
closeIfLoaded("final_steady_speed55090");
if isfolder(directory)
    rmdir(directory, "s");
end
end

function writeText(filePath, text)
fileId = fopen(filePath, "w");
assert(fileId >= 0);
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", text);
clear cleanup
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, output);
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
