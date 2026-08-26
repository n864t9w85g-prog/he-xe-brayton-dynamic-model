function tests = test_analyze_task8_h1a_s2_scheme_a_readonly
%TEST_ANALYZE_TASK8_H1A_S2_SCHEME_A_READONLY Scheme A recovery contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"), "-begin");
addpath(root, "-begin");
testCase.TestData.root = string(root);
testCase.TestData.tempRoot = string(tempname);
mkdir(testCase.TestData.tempRoot);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
if isfolder(testCase.TestData.tempRoot)
    rmdir(testCase.TestData.tempRoot, "s");
end
end

function testRealIntegralAndRootContinuePastOriginalBlock(testCase)
outputDir = fullfile(testCase.TestData.tempRoot, "scheme_a_success");
options = struct("testOnly", true, "outputDir", string(outputDir));
loadedBefore = loadedBlockDiagrams();
protectedBefore = protectedHashes(testCase.TestData.root);

analysis = analyze_task8_h1a_s2_scheme_a_readonly(options);

verifyEqual(testCase, analysis.scope.s2PhiVariant, "schemeA");
verifyTrue(testCase, analysis.scope.etaCp1Cp2HeldFixed);
verifyTrue(testCase, analysis.s2.integrationCompleted);
verifyTrue(testCase, analysis.s2.rootConverged);
verifyLessThanOrEqual(testCase, abs(analysis.s2.rootResidual_K), 1e-9);
verifyTrue(testCase, analysis.s2.pathAudit.allPhysical);
verifyEqual(testCase, analysis.s2.pathAudit.sampleCount, 1001);
verifyGreaterThan(testCase, analysis.s2.pathAudit.minCpMass_J_kgK, 0);
verifyGreaterThan(testCase, analysis.s2.pathAudit.minCvMass_J_kgK, 0);
verifyGreaterThan(testCase, analysis.s2.pathAudit.minGamma, 1);
verifyGreaterThan(testCase, analysis.s2.pathAudit.minPhi, 0);
verifyLessThan(testCase, analysis.s2.pathAudit.maxPhi, 1);
verifyFalse(testCase, analysis.authorizesRepair);
verifyFalse(testCase, analysis.formalModelPromotion);
verifyFalse(testCase, analysis.slxLoadedOrSimulated);
verifyFalse(testCase, analysis.h1bExecuted);
verifyEqual(testCase, analysis.inputs.expansionRatio, ...
    2.2812178550028612, "AbsTol", 1e-15);
verifyEqual(testCase, analysis.settings.rootBracketLow_K, ...
    664.1670261116656, "AbsTol", 1e-12);
verifyEqual(testCase, analysis.settings.rootBracketHigh_K, ...
    1515.109678670083, "AbsTol", 1e-12);
verifyEqual(testCase, analysis.settings.s2IntegralRelTol, 1e-8);
verifyEqual(testCase, analysis.settings.s2IntegralAbsTol, 1e-10);
verifyEqual(testCase, analysis.settings.rootAbsResidualTolerance_K, 1e-9);
verifyEqual(testCase, loadedBlockDiagrams(), loadedBefore);
verifyEqual(testCase, protectedHashes(testCase.TestData.root), ...
    protectedBefore);
verifyFalse(testCase, isfolder(officialH1aDir(testCase.TestData.root)));
end

function testOutputIsSelfContainedAndExplicitlyNonPromoting(testCase)
outputDir = fullfile(testCase.TestData.tempRoot, "scheme_a_evidence");
analysis = analyze_task8_h1a_s2_scheme_a_readonly( ...
    struct("testOnly", true, "outputDir", string(outputDir)));
entries = dir(outputDir);
entries = entries(~ismember(string({entries.name}), ["." ".."])) ;
verifyEqual(testCase, sort(string({entries.name})).', ...
    ["h1a_sensitivity.csv"; "h1a_summary.txt"]);
verifyFalse(testCase, any([entries.isdir]));
verifyEqual(testCase, sha256File(analysis.csvPath), analysis.csvSha256);
verifyEqual(testCase, sha256File(analysis.summaryPath), ...
    analysis.summarySha256);

summary = string(fileread(analysis.summaryPath));
required = [ ...
    "s2PhiVariant=schemeA"
    "s2PhiScope=only H1a-S2 phi integrand"
    "etaCp1Cp2HeldFixed=true"
    "s2IntegrationCompleted=true"
    "s2RootConverged=true"
    "s2PathAuditSampleCount=1001"
    "s2PathAuditFormalGlobalProof=false"
    "authorizesRepair=false"
    "formalModelPromotion=false"
    "slxLoadedOrSimulated=false"
    "h1bExecuted=false"
    "6a8398b7a32685cb3d198a1fe39b3b9365cfdefe65143d5613c68ffdd44366f4"
    "afd75b1b31cd0abdbdb2926b95ab987f260caa81a55fe2e901fdde4dafd72465"];
for item = required
    verifyTrue(testCase, contains(summary, item));
end
end

function testOriginalH1aStillFailsAtApprovedPoint(testCase)
try
    analyze_task8_h1a_readonly();
    verifyFail(testCase, "Original H1a unexpectedly stopped failing closed.");
catch exception
    verifyEqual(testCase, string(exception.identifier), ...
        "steady53:H1aInvalidProperty");
    verifyTrue(testCase, contains(string(exception.message), ...
        "T=992.38742737169468 K"));
end
verifyFalse(testCase, isfolder(officialH1aDir(testCase.TestData.root)));
end

function testUnknownOrNonTestOverrideFailsClosed(testCase)
verifyError(testCase, @() analyze_task8_h1a_s2_scheme_a_readonly( ...
    struct("testOnly", false, "outputDir", testCase.TestData.tempRoot)), ...
    "steady53:H1aSchemeAInvalidOptions");
verifyError(testCase, @() analyze_task8_h1a_s2_scheme_a_readonly( ...
    struct("testOnly", true, "outputDir", testCase.TestData.tempRoot, ...
    "extra", true)), "steady53:H1aSchemeAInvalidOptions");
end

function testWrapperContainsNoModelApis(testCase)
source = fileread(fullfile(testCase.TestData.root, "tests", "steady53", ...
    "analyze_task8_h1a_s2_scheme_a_readonly.m"));
forbidden = regexp(source, ...
    '(?<![A-Za-z0-9_])(set_param|sim|load_system|save_system|open_system|bdclose)\s*\(', ...
    "match");
verifyEmpty(testCase, forbidden);
verifyTrue(testCase, contains(source, ...
    "hexe_property_scheme_a_offline"));
verifyTrue(testCase, contains(source, ...
    "5820e957b90b1affce777c1774aee6cc685f40430310408fb00f303846f606d0"));
end

function pathValue = officialH1aDir(root)
pathValue = fullfile(root, "tmp", "steady53", "task8_root_cause", ...
    "h1a", "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
end

function diagrams = loadedBlockDiagrams()
diagrams = sort(string(find_system("type", "block_diagram")));
diagrams = diagrams(:);
end

function hashes = protectedHashes(root)
paths = [ ...
    string(fullfile(root, "final_steady_24a.slx"))
    string(fullfile(root, "HeXe_property_simulink.m"))
    string(fullfile(root, "turbine_table2.mat"))
    string(fullfile(root, "tmp", "steady53", "task8", ...
        "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
        "nominal_500_report.mat"))
    string(fullfile(root, "tmp", "steady53", "task8_root_cause", ...
        "h2a", "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
        "h2a_counterfactual_diagnostics.csv"))
    string(fullfile(root, "tmp", "steady53", "task8_root_cause", ...
        "h2a", "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
        "h2a_summary.txt"))];
sha256 = strings(numel(paths), 1);
for index = 1:numel(paths)
    sha256(index) = sha256File(paths(index));
end
hashes = table(paths, sha256);
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, "Hash failed: %s", output);
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\''") + "'";
end
