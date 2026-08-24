function tests = test_task8_evidence
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testControlledRunIdCollisionPreservesPublishedEvidence(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
runId = "run_controlled_collision";

stage = create_task8_evidence_stage( ...
    evidenceRoot, runId, result, report, spec);
published = publish_task8_evidence(stage);
before = hashPublishedFiles(published.runDir);

verifyError(testCase, @() create_task8_evidence_stage( ...
    evidenceRoot, runId, result, report, spec), ...
    "steady53:EvidenceAlreadyExists");
verifyEqual(testCase, hashPublishedFiles(published.runDir), before);
clear cleanup
end

function testTargetFileCollisionFailsWithoutCompletedPublication(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_target_file_collision", result, report, spec);
control = struct("targetCollisionFile", "metrics.csv");

verifyError(testCase, @() publish_task8_evidence(stage, control), ...
    "steady53:EvidenceAlreadyExists");

verifyTrue(testCase, isfolder(stage.targetDir));
verifyPublicationIncomplete(testCase, stage.targetDir);
verifyTrue(testCase, isfile(stage.manifestPath));
verifyEqual(testCase, string(jsondecode(fileread( ...
    stage.manifestPath)).status), ...
    "completed");
clear cleanup
end

function testPublishInterruptionLeavesNoCompletedTarget(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_interrupted_publish", result, report, spec);
control = struct("interruptAfterFiles", 2);

verifyError(testCase, @() publish_task8_evidence(stage, control), ...
    "steady53:EvidencePublishInterrupted");

verifyTrue(testCase, isfolder(stage.stageDir));
verifyTrue(testCase, isfile(stage.manifestPath));
verifyTrue(testCase, isfolder(stage.targetDir));
verifyPublicationIncomplete(testCase, stage.targetDir);
verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:EvidenceAlreadyExists");
clear cleanup
end

function testDeletedStagePayloadClaimIsRejectedBeforeReservation(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_deleted_payload_claim", result, report, spec);
stage.payloadFiles(1) = [];

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyFalse(testCase, isfolder(stage.targetDir));
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testUnknownStagePayloadClaimIsRejectedBeforeReservation(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_unknown_payload_claim", result, report, spec);
stage.payloadFiles(end + 1, 1) = "unknown.txt";

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyFalse(testCase, isfolder(stage.targetDir));
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testMissingManifestSmallHashIsRejectedWithoutCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_missing_small_hash", result, report, spec);
manifest = jsondecode(fileread(stage.manifestPath));
manifest.smallFileHashes(1) = [];
writeJson(stage.manifestPath, manifest);

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testDuplicateManifestSmallHashIsRejectedWithoutCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_duplicate_small_hash", result, report, spec);
manifest = jsondecode(fileread(stage.manifestPath));
manifest.smallFileHashes(end + 1) = manifest.smallFileHashes(1);
writeJson(stage.manifestPath, manifest);

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testChangedManifestRawNameIsRejectedWithoutCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_changed_raw_name", result, report, spec);
manifest = jsondecode(fileread(stage.manifestPath));
manifest.rawMatFile = "different.mat";
writeJson(stage.manifestPath, manifest);

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testAlternateStageRawPathIsRejectedWithoutCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_alternate_raw_path", result, report, spec);
alternatePath = fullfile(stage.stageDir, "alternate.mat");
copyfile(stage.rawMatPath, alternatePath);
stage.rawMatPath = string(alternatePath);

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testUnknownManifestSmallHashIsRejectedWithoutCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_unknown_small_hash", result, report, spec);
manifest = jsondecode(fileread(stage.manifestPath));
copyfile(fullfile(stage.stageDir, "metrics.csv"), ...
    fullfile(stage.stageDir, "unknown.csv"));
manifest.smallFileHashes(1).name = "unknown.csv";
writeJson(stage.manifestPath, manifest);

verifyError(testCase, @() publish_task8_evidence(stage), ...
    "steady53:InvalidEvidenceStage");
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testTargetPayloadHashIsRecheckedBeforeCompletion(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();
stage = create_task8_evidence_stage( ...
    evidenceRoot, "run_target_hash_recheck", result, report, spec);
control = struct("tamperTargetBeforeManifest", "metrics.csv");

verifyError(testCase, @() publish_task8_evidence(stage, control), ...
    "steady53:InvalidEvidenceStage");
verifyTrue(testCase, isfolder(stage.targetDir));
verifyPublicationIncomplete(testCase, stage.targetDir);
clear cleanup
end

function testManifestHashesAndOlderRunRemainImmutable(testCase)
evidenceRoot = ownedTempDirectory();
cleanup = onCleanup(@() removeOwnedDirectory(evidenceRoot));
[result, report, spec] = syntheticEvidence();

firstStage = create_task8_evidence_stage( ...
    evidenceRoot, "run_first_immutable", result, report, spec);
first = publish_task8_evidence(firstStage);
firstHashes = hashPublishedFiles(first.runDir);

secondStage = create_task8_evidence_stage( ...
    evidenceRoot, "run_second_immutable", result, report, spec);
publish_task8_evidence(secondStage);

verifyEqual(testCase, hashPublishedFiles(first.runDir), firstHashes);
manifest = jsondecode(fileread(first.manifestPath));
verifyEqual(testCase, string(manifest.runId), first.runId);
verifyEqual(testCase, string(manifest.sourceModelHash), ...
    result.modelHashAfter);
verifyEqual(testCase, string(manifest.rawMatHash), ...
    sha256File(first.rawMatPath));
verifyEqual(testCase, string(manifest.status), "completed");
verifyNotEmpty(testCase, string(manifest.createdAt));
verifyEqual(testCase, numel(manifest.smallFileHashes), 6);
for index = 1:numel(manifest.smallFileHashes)
    item = manifest.smallFileHashes(index);
    verifyEqual(testCase, string(item.sha256), ...
        sha256File(fullfile(first.runDir, string(item.name))));
end
clear cleanup
end

function [result, report, spec] = syntheticEvidence()
spec = steady53_spec();
spec.stopTime_s = 1;
spec.finalWindow_s = [0 1];
sourceHash = string(repmat('a', 1, 64));
result = struct( ...
    "success", true, ...
    "tFinal_s", 1, ...
    "errorId", "", ...
    "warningIds", strings(0, 1), ...
    "modelHashBefore", sourceHash, ...
    "modelHashAfter", sourceHash, ...
    "t", [0; 1], ...
    "signals", struct(), ...
    "states", struct("path", {}, "fluid", {}, "data", {}, ...
        "kind", {}, "signPolicy", {}));
report = struct();
report.metrics = table("synthetic_metric", 1, ...
    'VariableNames', {'metricName', 'target'});
report.signalDynamics = table("synthetic_signal", "other", 1, false, ...
    'VariableNames', {'name', 'kind', 'scaleFloor', 'constant'});
report.failures = "synthetic:red";
report.audit.lookup = struct( ...
    "name", "synthetic_lookup", "inputMin", 0, "inputMax", 0, ...
    "bpMin", -1, "bpMax", 1);
report.audit.property = struct( ...
    "HeXeMin_K", 500, "HeXeMax_K", 600, ...
    "LithiumMin_K", 700, "LithiumMax_K", 800);
report.audit.massClosureRel = 0;
end

function directory = ownedTempDirectory()
directory = string(tempname);
mkdir(directory);
end

function removeOwnedDirectory(directory)
if isfolder(directory)
    rmdir(directory, "s");
end
end

function verifyPublicationIncomplete(testCase, directory)
manifestPath = fullfile(directory, "manifest.json");
verifyFalse(testCase, isfile(manifestPath));
verifyEqual(testCase, publicationStatus(directory), "incomplete");
end

function status = publicationStatus(directory)
manifestPath = fullfile(directory, "manifest.json");
if ~isfile(manifestPath)
    status = "incomplete";
    return
end
manifest = jsondecode(fileread(manifestPath));
status = string(manifest.status);
end

function writeJson(filePath, value)
fileId = fopen(filePath, "w");
assert(fileId >= 0, "Could not open JSON fixture: %s", filePath);
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s\n", jsonencode(value));
clear cleanup
end

function hashes = hashPublishedFiles(directory)
listing = dir(directory);
names = sort(string({listing(~[listing.isdir]).name})).';
hashes = strings(numel(names), 2);
for index = 1:numel(names)
    hashes(index, :) = [names(index), ...
        sha256File(fullfile(directory, names(index)))];
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, "Could not hash %s: %s", filePath, output);
parts = split(strtrim(string(output)));
hash = parts(1);
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
