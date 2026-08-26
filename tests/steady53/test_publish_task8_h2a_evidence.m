function tests = test_publish_task8_h2a_evidence
%TEST_PUBLISH_TASK8_H2A_EVIDENCE Transactional H2a evidence publication.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
testCase.TestData.root = string(root);
testCase.TestData.analysis = analyze_task8_h2a_he_third_virial_counterfactual();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testValidAnalysisPublishesExactlyTwoSelfContainedFiles(testCase)
[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
published = publish_task8_h2a_evidence(testCase.TestData.analysis, options);
verifyTrue(testCase, isfolder(options.outputDir));
verifyEqual(testCase, published.outputDir, options.outputDir);
verifyEqual(testCase, outputNames(options.outputDir), ...
    ["h2a_counterfactual_diagnostics.csv"; "h2a_summary.txt"]);
verifyEqual(testCase, published.csvSha256, ...
    sha256File(fullfile(options.outputDir, "h2a_counterfactual_diagnostics.csv")));
verifyEqual(testCase, published.summarySha256, ...
    sha256File(fullfile(options.outputDir, "h2a_summary.txt")));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
csv = string(fileread(fullfile(options.outputDir, ...
    "h2a_counterfactual_diagnostics.csv")));
summary = string(fileread(fullfile(options.outputDir, "h2a_summary.txt")));
verifyTrue(testCase, contains(csv, "rootSearchAssurance"));
verifyTrue(testCase, contains(summary, "formalRootExclusion=false"));
verifyTrue(testCase, contains(summary, ...
    "noRootDetectedByDeclaredNumericalSearchNotFormalProof"));
verifyTrue(testCase, contains(summary, "sampledExtrema"));
verifyTrue(testCase, contains(summary, "unboundedAtC111DerivativeDiscontinuity"));
verifyTrue(testCase, contains(summary, "authorizesRepair=false"));
verifyTrue(testCase, contains(summary, ...
    "runId=run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3"));
verifyTrue(testCase, contains(summary, "exceptionT_K=992.38742737169468"));
verifyTrue(testCase, contains(summary, "temperatureFormula=T1+lambda*(Tlow-T1)"));
verifyTrue(testCase, contains(summary, "DOI=10.2514/6.2006-4154"));
verifyTrue(testCase, contains(summary, "scheme=A"));
verifyTrue(testCase, contains(summary, "baselineParity.point.B11.tolerance="));
verifyTrue(testCase, contains(summary, "exceptionPoint.delta.cpMolar="));
verifyTrue(testCase, contains(summary, ...
    "exceptionPoint.delta.eos.polynomialCoefficients(1)="));
verifyTrue(testCase, contains(summary, ...
    "fixedPressureSweep.baseline.boundary.cp=0.1.residual="));
verifyTrue(testCase, contains(summary, ...
    "fixedPressureSweep.baseline.nonphysicalInterval.cp<=0.1.startCoordinate="));
verifyTrue(testCase, contains(summary, ...
    "fixedPressureSweep.counterfactual.hasC111ZeroDerivativeDiscontinuity=false"));
verifyTrue(testCase, contains(summary, "H1a-S2=NOT_EXECUTED"));
verifyTrue(testCase, contains(summary, "Task8=NOT_COMPLETE"));
verifyTrue(testCase, contains(summary, "steady14000s=NOT_EXECUTED_OR_ACCEPTED"));
verifyTrue(testCase, contains(summary, "formalModelPromotion=NOT_AUTHORIZED"));
csvTable = readtable(fullfile(options.outputDir, ...
    "h2a_counterfactual_diagnostics.csv"), "TextType", "string");
verifyEqual(testCase, string(csvTable.Properties.VariableNames), ...
    ["section" "name" "value"]);
verifyGreaterThan(testCase, height(csvTable), 5000);
verifyTrue(testCase, any(csvTable.section == "baselineParity.point" & ...
    csvTable.name == "B11.tolerance"));
verifyTrue(testCase, any(csvTable.section == "fixedPressureSweep.baseline.stateTable"));
verifyTrue(testCase, any(csvTable.section == "h1aPathSweep.counterfactual.extrema"));
end

function testCoreEvidenceMutationsFailBeforeStaging(testCase)
base = testCase.TestData.analysis;
cases = cell(14, 1);
cases{1} = base; cases{1}.baselineParity.table(1, :) = [];
cases{2} = base; cases{2}.baselineParity.allSatisfied = false;
cases{3} = base; cases{3}.approval.variant = "wrong";
cases{4} = base; cases{4}.exceptionPoint.counterfactual.C111 = 1;
cases{5} = base; cases{5}.exceptionPoint.counterfactual.C112 = 1;
cases{6} = base; cases{6}.exceptionPoint.counterfactual.C122 = 1;
cases{7} = base; cases{7}.exceptionPoint.singleVariableGate.invariants.pass( ...
    cases{7}.exceptionPoint.singleVariableGate.invariants.name == "B") = false;
cases{8} = base; cases{8}.exceptionPoint.baseline.eosForm = "wrong";
cases{9} = base; cases{9}.exceptionPoint.baseline.productionNewton.maximumIterations = 1;
cases{10} = base; cases{10}.approval.authorizesRepair = true;
cases{11} = base; cases{11}.exceptionPoint.counterfactual.B = ...
    cases{11}.exceptionPoint.counterfactual.B + 1;
cases{12} = base; cases{12}.exceptionPoint.counterfactual.eosForm = "wrong";
cases{13} = base; cases{13}.exceptionPoint.counterfactual.newtonInitialGuess = ...
    cases{13}.exceptionPoint.counterfactual.newtonInitialGuess + 1;
cases{14} = base; cases{14}.baselineParity.table.h2aBaselineValue(1) = ...
    cases{14}.baselineParity.table.h2aBaselineValue(1) + 1;
cases{14}.baselineParity.table.absoluteError(1) = 0;
cases{14}.baselineParity.table.tolerance(1) = Inf;
cases{14}.baselineParity.table.pass(1) = true;
cases{15} = base; cases{15}.exceptionPoint.counterfactual.productionNewton.maximumIterations = 1;
cases{16} = base; cases{16}.exceptionPoint.counterfactual.eos.polynomialCoefficients(1) = ...
    cases{16}.exceptionPoint.counterfactual.eos.polynomialCoefficients(1) + 1;
for index = 1:numel(cases)
    [options, cleanup] = temporaryOptions(); %#ok<ASGLU>
    verifyError(testCase, @() publish_task8_h2a_evidence(cases{index}, options), ...
        "steady53:H2aInvalidEvidence");
    verifyFalse(testCase, isfolder(options.outputDir));
    verifyEmpty(testCase, stagingDirectories(options.outputDir));
    clear cleanup
end
end

function testPathHashAndStateMutationsFailBeforeStaging(testCase)
base = testCase.TestData.analysis;
cases = cell(7, 1);
cases{1} = base; cases{1}.fixedPressureSweep.quantitiesSearched(1) = "wrong";
cases{2} = base; cases{2}.h1aPathSweep.counterfactual.stateTable(:,:) = [];
cases{3} = base; cases{3}.fixedPressureSweep.baseline.allCoordinatesAccountedFor = false;
cases{4} = base; cases{4}.h1aPathSweep.baseline.stateTable.valid(1) = false;
cases{5} = base; cases{5}.sourceAudit.modelSha256 = repmat("0", 1, 64);
cases{6} = base; cases{6}.sourceAudit.archivePeeledCommit = repmat("0", 1, 40);
cases{7} = base; cases{7}.fixedPressureSweep.baseline.rootSearchAssurance.formalRootExclusion = true;
cases{8} = base; cases{8}.fixedPressureSweep.baseline.nonphysicalIntervals(1, :) = [];
cases{9} = base; cases{9}.fixedPressureSweep.counterfactual.extrema(:, :) = [];
cases{10} = base; cases{10}.h1aPathSweep.path.temperatureFormula = "wrong";
cases{11} = base; cases{11}.fixedPressureSweep.baseline.boundaries.coordinate(1) = ...
    cases{11}.fixedPressureSweep.baseline.boundaries.coordinate(1) + 1;
cases{12} = base; cases{12}.fixedPressureSweep.counterfactual.hasC111ZeroDerivativeDiscontinuity = true;
cases{13} = base;
interval = cases{13}.fixedPressureSweep.baseline.nonphysicalIntervals(1, :);
newStart = (interval.startCoordinate + interval.endCoordinate)/2;
cases{13}.fixedPressureSweep.baseline.nonphysicalIntervals.startCoordinate(1) = newStart;
cases{13}.fixedPressureSweep.baseline.nonphysicalIntervals.startT_K(1) = newStart;
cases{14} = base;
cases{14}.fixedPressureSweep.counterfactual.sampledExtrema.value(1) = ...
    cases{14}.fixedPressureSweep.counterfactual.sampledExtrema.value(1) + 1;
cases{14}.fixedPressureSweep.counterfactual.extrema = ...
    cases{14}.fixedPressureSweep.counterfactual.sampledExtrema;
cases{15} = base;
root = cases{15}.fixedPressureSweep.baseline.boundaries.classification == "root";
firstRoot = find(root, 1);
cases{15}.fixedPressureSweep.baseline.boundaries.residual(firstRoot) = ...
    cases{15}.fixedPressureSweep.baseline.boundaries.residualTolerance(firstRoot)/2;
cases{16} = base;
cases{16}.fixedPressureSweep.baseline.C111DiscontinuityEvidence.leftCpMolar(1) = ...
    cases{16}.fixedPressureSweep.baseline.C111DiscontinuityEvidence.leftCpMolar(1) + 1;
cases{17} = base;
row = cases{17}.fixedPressureSweep.baseline.extrema.quantity == "cpMolar" & ...
    cases{17}.fixedPressureSweep.baseline.extrema.kind == "min";
cases{17}.fixedPressureSweep.baseline.extrema.value(row) = 0;
for index = 1:numel(cases)
    [options, cleanup] = temporaryOptions(); %#ok<ASGLU>
    verifyError(testCase, @() publish_task8_h2a_evidence(cases{index}, options), ...
        "steady53:H2aInvalidEvidence");
    verifyFalse(testCase, isfolder(options.outputDir));
    verifyEmpty(testCase, stagingDirectories(options.outputDir));
    clear cleanup
end
end

function testStableRootCountIsRecordedNotUsedAsResultGate(testCase)
analysis = testCase.TestData.analysis;
analysis.fixedPressureSweep.counterfactual.stateTable.stablePositiveRealRootCount(1) = 0;
[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
published = publish_task8_h2a_evidence(analysis, options);
verifyTrue(testCase, isfolder(published.outputDir));
csv = readtable(fullfile(published.outputDir, ...
    "h2a_counterfactual_diagnostics.csv"), "TextType", "string");
rows = csv.section == "fixedPressureSweep.counterfactual.stateTable" & ...
    csv.name == "row1.stablePositiveRealRootCount";
verifyEqual(testCase, nnz(rows), 1);
verifyEqual(testCase, csv.value(rows), "0");
end

function testEmptyTargetRaceDoesNotReplaceExistingDirectory(testCase)
[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
options.outputFailureHook = @raceEmptyTarget;
verifyError(testCase, @() publish_task8_h2a_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2aOutputExists");
verifyTrue(testCase, isfolder(options.outputDir));
verifyEmpty(testCase, outputNames(options.outputDir));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function testExistingTargetRaceAndCsvFailureNeverPublishPartialOutput(testCase)
[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
mkdir(options.outputDir);
sentinel = fullfile(options.outputDir, "sentinel.txt");
writeText(sentinel, "owned");
before = sha256File(sentinel);
verifyError(testCase, @() publish_task8_h2a_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2aOutputExists");
verifyEqual(testCase, sha256File(sentinel), before);
clear cleanup

[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
options.outputFailureHook = @raceTarget;
verifyError(testCase, @() publish_task8_h2a_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2aOutputExists");
verifyEqual(testCase, string(fileread(fullfile(options.outputDir, "sentinel.txt"))), ...
    "other-owner");
verifyEmpty(testCase, stagingDirectories(options.outputDir));
clear cleanup

[options, cleanup] = temporaryOptions(); %#ok<ASGLU>
options.outputFailureHook = @failAfterCsv;
verifyError(testCase, @() publish_task8_h2a_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2aControlledOutputFailure");
verifyFalse(testCase, isfolder(options.outputDir));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function testPublisherHasNoModelApisAndFormalTargetIsFixed(testCase)
publisherPath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "publish_task8_h2a_evidence.m");
publisher = fileread(publisherPath);
verifyEmpty(testCase, regexp(publisher, ...
    '(?<![A-Za-z0-9_])(set_param|sim|load_system|save_system|bdclose|load)\s*\(', ...
    'match'));
verifyNotEmpty(testCase, regexp(publisher, 'java\.nio\.file\.Files', 'once'));
verifyEmpty(testCase, regexp(publisher, 'REPLACE_EXISTING', 'once'));
verifyEmpty(testCase, regexp(publisher, 'ATOMIC_MOVE', 'once'));
end

function [options, cleanup] = temporaryOptions()
parent = string(tempname);
mkdir(parent);
cleanup = onCleanup(@() cleanupParent(parent));
options = struct("testOnly", true, ...
    "outputDir", fullfile(parent, "h2a_test_output"), ...
    "outputFailureHook", @(~, ~, ~) []);
end

function names = outputNames(outputDir)
entries = dir(outputDir);
names = sort(string({entries(~[entries.isdir]).name})).';
end

function names = stagingDirectories(outputDir)
[parent, leaf] = fileparts(outputDir);
listing = dir(fullfile(parent, "." + string(leaf) + ".staging_*"));
names = string({listing([listing.isdir]).name});
end

function raceTarget(point, ~, outputDir)
if point == "beforePublish"
    mkdir(outputDir);
    writeText(fullfile(outputDir, "sentinel.txt"), "other-owner");
end
end

function raceEmptyTarget(point, ~, outputDir)
if point == "beforePublish"
    mkdir(outputDir);
end
end

function failAfterCsv(point, stagingDir, ~)
if point == "afterCsvBeforeSummary"
    assert(isfile(fullfile(stagingDir, "h2a_counterfactual_diagnostics.csv")));
    assert(~isfile(fullfile(stagingDir, "h2a_summary.txt")));
    error("steady53:H2aControlledOutputFailure", "Intentional test-only failure.");
end
end

function writeText(pathValue, content)
[fileId, message] = fopen(pathValue, "w", "native", "UTF-8");
assert(fileId >= 0, "%s", message);
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", content);
clear cleanup
end

function cleanupParent(parent)
if isfolder(parent)
    rmdir(parent, "s");
end
end

function hash = sha256File(pathValue)
[status, output] = system("shasum -a 256 " + shellQuote(pathValue));
assert(status == 0, "%s", output);
parts = split(strtrim(string(output)));
hash = lower(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\''") + "'";
end
