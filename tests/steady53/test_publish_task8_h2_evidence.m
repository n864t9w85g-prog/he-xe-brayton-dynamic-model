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
verifyTrue(testCase, contains(summary, "implementation_error=❌"));
verifyTrue(testCase, contains(summary, "density_root_error=❌"));
verifyTrue(testCase, contains(summary, ...
    "direct_paper_correlation_nonphysical=✅"));
verifyTrue(testCase, contains(summary, "authorizesRepair=false"));
verifyFalse(testCase, contains(summary, "clipValue="));
verifyFalse(testCase, contains(summary, "replacementProperty="));
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
