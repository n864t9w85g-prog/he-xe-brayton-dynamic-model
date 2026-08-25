function tests = test_publish_task8_h2_evidence
%TEST_PUBLISH_TASK8_H2_EVIDENCE Task 8 H2 exclusive publication contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
addpath(root);
testCase.TestData.root = string(root);
testCase.TestData.analysis = analyze_task8_h2_hexe_property_readonly();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testPublisherSourceIsSeparatedFromReadOnlyAnalyzer(testCase)
analyzerPath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "analyze_task8_h2_hexe_property_readonly.m");
publisherPath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "publish_task8_h2_evidence.m");
analyzer = fileread(analyzerPath);
publisher = fileread(publisherPath);
verifyEmpty(testCase, regexp(analyzer, ...
    '(?<![A-Za-z0-9_])(save|writetable|writecell|writematrix|fopen|copyfile|movefile)\s*\(', ...
    'match'));
verifyEmpty(testCase, regexp(publisher, ...
    '(?<![A-Za-z0-9_])(set_param|sim|save_system|load_system|bdclose)\s*\(', ...
    'match'));
verifyNotEmpty(testCase, regexp(publisher, 'java\.nio\.file\.Files', 'once'));
verifyEmpty(testCase, regexp(publisher, 'REPLACE_EXISTING', 'once'));
end

function testCompleteAnalysisPublishesExactlyTwoFilesAndHashes(testCase)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
published = publish_task8_h2_evidence(testCase.TestData.analysis, options);
verifyTrue(testCase, isfolder(options.outputDir));
entries = dir(options.outputDir);
names = sort(string({entries(~[entries.isdir]).name}));
verifyEqual(testCase, names, sort([ ...
    "h2_property_diagnostics.csv" "h2_summary.txt"]));
verifyEqual(testCase, published.csvSha256, ...
    sha256File(fullfile(options.outputDir, "h2_property_diagnostics.csv")));
verifyEqual(testCase, published.summarySha256, ...
    sha256File(fullfile(options.outputDir, "h2_summary.txt")));
verifyEmpty(testCase, stagingDirectories(options.outputDir));

diagnostics = readtable(fullfile(options.outputDir, ...
    "h2_property_diagnostics.csv"), "TextType", "string");
verifyTrue(testCase, all(ismember(["section" "name" "value" ...
    "units" "evidenceGrade" "source"], ...
    string(diagnostics.Properties.VariableNames))));
summary = string(fileread(fullfile(options.outputDir, "h2_summary.txt")));
verifyPublishedCompleteness(testCase, diagnostics, summary);
verifyTrue(testCase, contains(summary, "implementation_error=❌"));
verifyTrue(testCase, contains(summary, "density_root_error=❌"));
verifyTrue(testCase, contains(summary, ...
    "direct_paper_correlation_nonphysical=✅"));
verifyTrue(testCase, contains(summary, "authorizesRepair=false"));
verifyFalse(testCase, contains(summary, "clipValue="));
verifyFalse(testCase, contains(summary, "replacementProperty="));
end

function testEveryIncompleteMapSweepSingularityAndPoleCaseFailsClosed(testCase)
base = testCase.TestData.analysis;
cases = cell(11, 1);
cases{1} = base;
cases{1}.sourceAudit = rmfield(cases{1}.sourceAudit, "equationMap");
cases{2} = base;
cases{2}.sourceAudit.equationMap.diagnosticPath(1) = "missing.path";
cases{3} = base;
cases{3}.domainSweep.fixedPressure.boundaries(:,:) = [];
cases{4} = base;
cases{4}.domainSweep.h1aLowEndPath.boundaries(:,:) = [];
cases{5} = base;
cases{5}.domainSweep.quantitiesSearched(1) = "wrong";
cases{6} = base;
cases{6}.domainSweep.fixedPressure.quantitiesSearched(4) = "wrong";
cases{7} = base;
cases{7}.domainSweep.h1aLowEndPath.boundaryCountByQuantity.count(1) = 0;
cases{8} = base;
cases{8}.domainSweep.C111DerivativeDiscontinuity = rmfield( ...
    cases{8}.domainSweep.C111DerivativeDiscontinuity, "classification");
cases{9} = base;
cases{9}.domainSweep.C111DerivativeDiscontinuity.C111Residual = 1;
cases{10} = base;
cases{10}.domainSweep.fixedPressure.gammaPoleAtCvZero.classification = ...
    "gammaEqualsOneRoot";
cases{11} = base;
cases{11}.domainSweep.h1aLowEndPath.gammaPoleAtCvZero. ...
    isGammaEqualsOneRoot = true;

for index = 1:numel(cases)
    [options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
    verifyError(testCase, @() publish_task8_h2_evidence(cases{index}, options), ...
        "steady53:H2InvalidEvidence", sprintf("case %d", index));
    verifyFalse(testCase, isfolder(options.outputDir));
    verifyEmpty(testCase, stagingDirectories(options.outputDir));
    clear cleanup
end
end

function testAuditedEquationSourceCoordinatesFailClosedWhenTampered(testCase)
analysis = testCase.TestData.analysis;
analysis.sourceAudit.equationMap.sourceLineStart(:) = 1;
analysis.sourceAudit.equationMap.sourceLineEnd(:) = 1;
verifyInvalidEvidencePublishesNothing(testCase, analysis);
end

function testC111RootMustRemainBoundToApprovedCoefficient(testCase)
analysis = testCase.TestData.analysis;
analysis.domainSweep.C111DerivativeDiscontinuity.rootT_K = 123;
verifyInvalidEvidencePublishesNothing(testCase, analysis);
end

function testExistingTargetIsRefusedWithoutOverwrite(testCase)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
mkdir(options.outputDir);
sentinel = fullfile(options.outputDir, "sentinel.txt");
writeText(sentinel, "owned");
before = sha256File(sentinel);
verifyError(testCase, @() publish_task8_h2_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2OutputExists");
verifyEqual(testCase, sha256File(sentinel), before);
verifyEqual(testCase, string(fileread(sentinel)), "owned");
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function testIncompleteOrTamperedAnalysisFailsBeforeStaging(testCase)
cases = cell(4, 1);
cases{1} = testCase.TestData.analysis;
cases{1}.domainSweep.status = "incomplete";
cases{2} = testCase.TestData.analysis;
cases{2}.hypothesisVerdicts.densityRootError = rmfield( ...
    cases{2}.hypothesisVerdicts.densityRootError, "evidenceGrade");
cases{3} = testCase.TestData.analysis;
cases{3}.sourceAudit.modelSha256 = repmat("0", 1, 64);
cases{4} = testCase.TestData.analysis;
cases{4}.thermoIdentity.formulaConsistency.allSatisfied = false;
for index = 1:numel(cases)
    [options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
    verifyError(testCase, @() publish_task8_h2_evidence(cases{index}, options), ...
        "steady53:H2InvalidEvidence");
    verifyFalse(testCase, isfolder(options.outputDir));
    verifyEmpty(testCase, stagingDirectories(options.outputDir));
    clear cleanup
end
end

function testControlledFailureCleansStagingAndPublishesNothing(testCase)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
options.outputFailureHook = @controlledFailure;
verifyError(testCase, @() publish_task8_h2_evidence( ...
    testCase.TestData.analysis, options), ...
    "steady53:H2ControlledOutputFailure");
verifyFalse(testCase, isfolder(options.outputDir));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function testConcurrentTargetRaceDoesNotReplaceOtherOwner(testCase)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
options.outputFailureHook = @(point, stagingDir) ...
    concurrentTarget(point, stagingDir, options.outputDir);
verifyError(testCase, @() publish_task8_h2_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2OutputExists");
sentinel = fullfile(options.outputDir, "sentinel.txt");
verifyTrue(testCase, isfile(sentinel));
verifyEqual(testCase, string(fileread(sentinel)), "other-owner");
verifyFalse(testCase, isfile(fullfile(options.outputDir, ...
    "h2_property_diagnostics.csv")));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function testPublisherHooksRequireExplicitTestOnly(testCase)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
options.testOnly = false;
verifyError(testCase, @() publish_task8_h2_evidence( ...
    testCase.TestData.analysis, options), "steady53:H2InvalidPublishOptions");
verifyFalse(testCase, isfolder(options.outputDir));
end

function [options, cleanup] = temporaryOptions(~)
parent = string(tempname);
mkdir(parent);
cleanup = onCleanup(@() cleanupTemp(parent));
options = struct( ...
    "testOnly", true, ...
    "outputDir", fullfile(parent, "run_test_h2"), ...
    "outputFailureHook", @(~, ~) []);
end

function verifyInvalidEvidencePublishesNothing(testCase, analysis)
[options, cleanup] = temporaryOptions(testCase); %#ok<ASGLU>
verifyError(testCase, @() publish_task8_h2_evidence(analysis, options), ...
    "steady53:H2InvalidEvidence");
verifyFalse(testCase, isfolder(options.outputDir));
verifyEmpty(testCase, stagingDirectories(options.outputDir));
end

function entries = stagingDirectories(outputDir)
[parent, leaf, extension] = fileparts(outputDir);
prefix = "." + string(leaf) + string(extension) + ".staging_";
listing = dir(fullfile(parent, prefix + "*"));
entries = string({listing([listing.isdir]).name});
end

function controlledFailure(point, stagingDir)
if point ~= "afterCsvBeforeSummary"
    return
end
assert(isfolder(stagingDir));
assert(isfile(fullfile(stagingDir, "h2_property_diagnostics.csv")));
assert(~isfile(fullfile(stagingDir, "h2_summary.txt")));
error("steady53:H2ControlledOutputFailure", "Controlled staging failure.");
end

function concurrentTarget(point, stagingDir, outputDir) %#ok<INUSD>
if point ~= "beforePublish"
    return
end
mkdir(outputDir);
writeText(fullfile(outputDir, "sentinel.txt"), "other-owner");
end

function writeText(pathValue, textValue)
[fileId, message] = fopen(pathValue, "w", "native", "UTF-8");
assert(fileId >= 0, "%s", message);
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", textValue);
clear cleanup
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, "Hash failed: %s", output);
parts = split(strtrim(output));
hash = lower(string(parts(1)));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end

function cleanupTemp(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end

function verifyPublishedCompleteness(testCase, diagnostics, summary)
equations = diagnostics(diagnostics.section == "equationMap", :);
verifyEqual(testCase, height(equations), 11);
verifyEqual(testCase, equations.name, "Eq" + [ ...
    "2.7"; "2.8"; "2.9"; "2.10"; "2.11"; "2.12"; ...
    "2.13"; "2.14"; "2.15"; "2.16"; "2.17"]);
for index = 1:height(equations)
    verifyTrue(testCase, contains(equations.value(index), "pdfPage="));
    verifyTrue(testCase, contains(equations.value(index), "printedPage="));
    verifyTrue(testCase, contains(equations.value(index), "sourceLine="));
    verifyTrue(testCase, contains(equations.value(index), "diagnosticPath="));
    verifyTrue(testCase, contains(summary, equations.name(index) + ":"));
end

requiredHashes = ["final_steady_24a.slx" "HeXe_property_simulink.m" ...
    "hexe_compressor_lookup.mat" "radiator_table.mat" ...
    "turbine_table1.mat" "turbine_table2.mat" "fixedInputMat" ...
    "thesisPdf" "archivePeeledCommit"];
hashRows = diagnostics(diagnostics.section == "hash", :);
verifyTrue(testCase, all(ismember(requiredHashes, hashRows.name)));
for name = requiredHashes
    verifyTrue(testCase, contains(summary, name + "Sha256=") || ...
        (name == "archivePeeledCommit" && ...
        contains(summary, "archivePeeledCommit=")));
end

for scan = ["fixedPressure" "h1aLowEndPath"]
    quantities = ["cp=0" "cv=0" "gamma=1" "dP/drho=0"];
    counts = [1 1 0 0];
    for index = 1:numel(quantities)
        quantity = quantities(index);
        count = counts(index);
        rowName = scan + ".searched." + quantity;
        row = diagnostics.name == rowName;
        verifyEqual(testCase, nnz(row), 1);
        verifyTrue(testCase, contains(diagnostics.value(row), ...
            "searched=true;count=" + count));
        verifyTrue(testCase, contains(summary, rowName + ...
            "=searched:true,count:" + count));
    end
    poleName = scan + ".gammaPoleAtCvZero";
    verifyEqual(testCase, nnz(diagnostics.name == poleName), 1);
    verifyTrue(testCase, contains(diagnostics.value( ...
        diagnostics.name == poleName), ...
        "gammaPoleAtCvZeroNotGammaEqualsOneRoot"));
    verifyTrue(testCase, contains(summary, poleName + ...
        "=gammaPoleAtCvZeroNotGammaEqualsOneRoot"));
end

verifyEqual(testCase, nnz(diagnostics.name == "C111.leftCpMolar"), 1);
verifyEqual(testCase, nnz(diagnostics.name == "C111.rightCpMolar"), 1);
verifyTrue(testCase, contains(summary, "C111.oneSidedClassification="));
verifyTrue(testCase, contains(summary, "fixedPressure.temperatureRange_K="));
verifyTrue(testCase, contains(summary, "h1aLowEndPath.lambdaRange="));
end
