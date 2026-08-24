function tests = test_analyze_task8_h1a_readonly
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
addpath(root);
testCase.TestData.root = string(root);
testCase.TestData.tempRoot = string(tempname);
mkdir(testCase.TestData.tempRoot);
testCase.TestData.options = validTestOptions(root, ...
    fullfile(testCase.TestData.tempRoot, "blocked_output"));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
if isfolder(testCase.TestData.tempRoot)
    rmdir(testCase.TestData.tempRoot, "s");
end
end

function testFunctionEntryPointExists(testCase)
verifyNotEmpty(testCase, which("analyze_task8_h1a_readonly"));
end

function testDefaultContractIsFixed(testCase)
source = fileread(fullfile(testCase.TestData.root, "tests", ...
    "steady53", "analyze_task8_h1a_readonly.m"));
required = [ ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3"
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b"
    "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33"
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d"
    "h1a_sensitivity.csv"
    "h1a_summary.txt"];
for index = 1:numel(required)
    verifyTrue(testCase, contains(source, required(index)));
end
end

function testFixedInputIntegrationNonconvergenceFailsBeforeOutput(testCase)
outputDir = fullfile(testCase.TestData.root, "tmp", "steady53", ...
    "task8_root_cause", "h1a", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
loadedBefore = loadedBlockDiagrams();
protectedBefore = protectedHashes(testCase.TestData.root);
pathBefore = path;
warningsBefore = warning;

try
    analyze_task8_h1a_readonly();
    verifyFail(testCase, "Expected fail-closed S2 integration warning.");
catch exception
    verifyEqual(testCase, string(exception.identifier), ...
        "steady53:H1aIntegrationNonconvergence");
    verifyEqual(testCase, numel(exception.cause), 1);
    verifyEqual(testCase, string(exception.cause{1}.identifier), ...
        "MATLAB:integral:MaxIntervalCountReached");
    stackNames = string({exception.cause{1}.stack.name});
    verifyTrue(testCase, any(contains(stackNames, "integralCalc")));
    verifyTrue(testCase, contains(string(exception.message), ...
        "phiBar=0.39978932815006674"));
    verifyTrue(testCase, contains(string(exception.message), ...
        "T2s_K=1089.5641955018075"));
    verifyTrue(testCase, contains(string(exception.message), ...
        "T2_K=1143.6630406569668"));
    verifyTrue(testCase, contains(string(exception.message), ...
        "rootResidual_K=1.5916157281026244e-12"));
end

verifyFalse(testCase, isfolder(outputDir));
verifyFalse(testCase, isfile(fullfile(outputDir, "h1a_sensitivity.csv")));
verifyFalse(testCase, isfile(fullfile(outputDir, "h1a_summary.txt")));
verifyEqual(testCase, loadedBlockDiagrams(), loadedBefore);
verifyEqual(testCase, protectedHashes(testCase.TestData.root), ...
    protectedBefore);
verifyEqual(testCase, path, pathBefore);
verifyEqual(testCase, warning, warningsBefore);
end

function testInputHashMismatchFailsBeforeOutput(testCase)
outputDir = fullfile(testCase.TestData.tempRoot, "hash_mismatch");
options = validTestOptions(testCase.TestData.root, outputDir);
options.expectedInputSha256 = string(repmat('0', 1, 64));

verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "steady53:H1aInputHashMismatch");
verifyFalse(testCase, isfolder(outputDir));
verifyFalse(testCase, isfile(fullfile(outputDir, "h1a_sensitivity.csv")));
verifyFalse(testCase, isfile(fullfile(outputDir, "h1a_summary.txt")));
end

function testMissingSignalFieldFailsClosed(testCase)
inputMat = fullfile(testCase.TestData.tempRoot, "missing_field.mat");
payload = load(testCase.TestData.options.inputMat, ...
    "result", "report", "spec");
result = payload.result;
report = payload.report;
spec = payload.spec;
result.signals = rmfield(result.signals, "turbine_inlet_T");
save(inputMat, "result", "report", "spec", "-v7.3");
outputDir = fullfile(testCase.TestData.tempRoot, "missing_field_output");
options = validTestOptions(testCase.TestData.root, outputDir);
options.inputMat = string(inputMat);
options.expectedInputSha256 = sha256File(inputMat);

verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "steady53:H1aInvalidInput");
verifyFalse(testCase, isfolder(outputDir));
end

function testInvalidTimeAndFinalWindowFailClosed(testCase)
payload = load(testCase.TestData.options.inputMat, ...
    "result", "report", "spec");

result = payload.result;
report = payload.report;
spec = payload.spec;
result.t(end) = result.t(end - 1);
inputMat = fullfile(testCase.TestData.tempRoot, "invalid_time.mat");
save(inputMat, "result", "report", "spec", "-v7.3");
options = validTestOptions(testCase.TestData.root, ...
    fullfile(testCase.TestData.tempRoot, "invalid_time_output"));
options.inputMat = string(inputMat);
options.expectedInputSha256 = sha256File(inputMat);
verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "steady53:H1aInvalidInput");
verifyFalse(testCase, isfolder(options.outputDir));

result = payload.result;
report = payload.report;
spec = payload.spec;
spec.finalWindow_s = [500 400];
inputMat = fullfile(testCase.TestData.tempRoot, "invalid_window.mat");
save(inputMat, "result", "report", "spec", "-v7.3");
options = validTestOptions(testCase.TestData.root, ...
    fullfile(testCase.TestData.tempRoot, "invalid_window_output"));
options.inputMat = string(inputMat);
options.expectedInputSha256 = sha256File(inputMat);
verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "steady53:H1aInvalidInput");
verifyFalse(testCase, isfolder(options.outputDir));
end

function testPropertyOutOfRangeFailsClosed(testCase)
payload = load(testCase.TestData.options.inputMat, ...
    "result", "report", "spec");
result = payload.result;
report = payload.report;
spec = payload.spec;
result.signals.turbine_inlet_T(end) = 2001;
inputMat = fullfile(testCase.TestData.tempRoot, "property_out_of_range.mat");
save(inputMat, "result", "report", "spec", "-v7.3");
options = validTestOptions(testCase.TestData.root, ...
    fullfile(testCase.TestData.tempRoot, "property_out_of_range_output"));
options.inputMat = string(inputMat);
options.expectedInputSha256 = sha256File(inputMat);

verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "HeXe:T_hi");
verifyFalse(testCase, isfolder(options.outputDir));
end

function testNoBracketFailsClosed(testCase)
payload = load(testCase.TestData.options.inputMat, ...
    "result", "report", "spec");
result = payload.result;
report = payload.report;
spec = payload.spec;
result.signals.turbine_outlet_P(end) = ...
    2 * result.signals.turbine_inlet_P(end);
result.signals.turbine_lookup_expansion_ratio(end) = 0.5;
[cp1, gamma1] = HeXe_property_simulink( ...
    result.signals.turbine_inlet_T(end), ...
    result.signals.turbine_inlet_P(end));
phi = 1 - 1 / gamma1;
T2s = result.signals.turbine_inlet_T(end) * 0.5^(-phi);
[cp2, ~] = HeXe_property_simulink(T2s, ...
    result.signals.turbine_outlet_P(end));
tablePayload = load(fullfile(testCase.TestData.root, ...
    "turbine_table2.mat"), "bp_mf", "bp_speed", "table_eff");
eta = interpn(tablePayload.bp_mf, tablePayload.bp_speed, ...
    tablePayload.table_eff, ...
    result.signals.turbine_lookup_mass_flow(end), ...
    result.signals.turbine_lookup_speed_eff(end), "linear");
result.signals.turbine_outlet_T(end) = ...
    result.signals.turbine_inlet_T(end) - eta * cp2 * ...
    (result.signals.turbine_inlet_T(end) - T2s) / cp1;
clear("HeXe_property_simulink");
inputMat = fullfile(testCase.TestData.tempRoot, "no_bracket.mat");
save(inputMat, "result", "report", "spec", "-v7.3");
options = validTestOptions(testCase.TestData.root, ...
    fullfile(testCase.TestData.tempRoot, "no_bracket_output"));
options.inputMat = string(inputMat);
options.expectedInputSha256 = sha256File(inputMat);

verifyError(testCase, @() analyze_task8_h1a_readonly(options), ...
    "steady53:H1aNoBracket");
verifyFalse(testCase, isfolder(options.outputDir));
end

function testOutputCollisionDoesNotOverwrite(testCase)
options = validTestOptions(testCase.TestData.root, ...
    fullfile(testCase.TestData.tempRoot, "collision_output"));
mkdir(options.outputDir);
sentinelPath = fullfile(options.outputDir, "sentinel.txt");
fileId = fopen(sentinelPath, "w");
assert(fileId >= 0);
fprintf(fileId, "do not overwrite\n");
fclose(fileId);
before = sha256File(sentinelPath);

verifyError(testCase, @() analyze_task8_h1a_readonly( ...
    options), "steady53:H1aOutputExists");
verifyEqual(testCase, sha256File(sentinelPath), before);
verifyFalse(testCase, isfile(fullfile(options.outputDir, ...
    "h1a_sensitivity.csv")));
verifyFalse(testCase, isfile(fullfile(options.outputDir, ...
    "h1a_summary.txt")));
end

function testNumericalSettingsAndFailClosedPolicyAreFixed(testCase)
source = fileread(fullfile(testCase.TestData.root, "tests", ...
    "steady53", "analyze_task8_h1a_readonly.m"));
required = [ ...
    """rootBracketLow_K"", 100"
    """rootAbsResidualTolerance_K"", 1e-9"
    """s2IntegralRelTol"", 1e-8"
    """s2IntegralAbsTol"", 1e-10"
    "warning(""error"", ""HeXe:T_lo"")"
    "warning(""error"", ""HeXe:T_hi"")"
    "warning(""error"", ""MATLAB:integral:MaxIntervalCountReached"")"
    """steady53:H1aIntegrationNonconvergence"""];
for index = 1:numel(required)
    verifyTrue(testCase, contains(source, required(index)));
end
verifyFalse(testCase, contains(source, 'warning("off"'));
verifyFalse(testCase, contains(source, "endpointCachedResidual"));
verifyEmpty(testCase, regexp(source, 'MaxIntervalCount\s*[,=]', 'once'));
end

function testForbiddenModelApisAreAbsentAndLoadIsRestricted(testCase)
sourcePath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "analyze_task8_h1a_readonly.m");
source = fileread(sourcePath);
forbidden = regexp(source, ...
    '(?<![A-Za-z0-9_])(set_param|load_system|save_system|sim)\s*\(', ...
    'match');
verifyEmpty(testCase, forbidden);
verifyNotEmpty(testCase, regexp(source, ...
    'load\(inputMat,\s*"result",\s*"report",\s*"spec"\)', ...
    'once'));
end

function testNoOfficialOutputIsPublishedWhenS2Blocks(testCase)
officialDir = fullfile(testCase.TestData.root, "tmp", "steady53", ...
    "task8_root_cause", "h1a", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
verifyFalse(testCase, isfolder(officialDir));
verifyFalse(testCase, isfile(fullfile(officialDir, ...
    "h1a_sensitivity.csv")));
verifyFalse(testCase, isfile(fullfile(officialDir, "h1a_summary.txt")));
end

function options = validTestOptions(root, outputDir)
options = struct();
options.testOnly = true;
options.runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
options.inputMat = string(fullfile(root, "tmp", "steady53", "task8", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
    "nominal_500_report.mat"));
options.expectedInputSha256 = ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b";
options.turbineTableMat = string(fullfile(root, "turbine_table2.mat"));
options.expectedTurbineTableSha256 = ...
    "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33";
options.modelPath = string(fullfile(root, "final_steady_24a.slx"));
options.expectedModelSha256 = ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d";
options.outputDir = string(outputDir);
end

function diagrams = loadedBlockDiagrams()
diagrams = sort(string(find_system("type", "block_diagram")));
diagrams = diagrams(:);
end

function hashes = protectedHashes(root)
paths = string(fullfile(root, [ ...
    "final_steady_24a.slx"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"]));
hash = strings(numel(paths), 1);
for index = 1:numel(paths)
    hash(index) = sha256File(paths(index));
end
hashes = table(paths(:), hash, 'VariableNames', {'path', 'sha256'});
end

function hash = sha256File(filePath)
[commandStatus, output] = system( ...
    "shasum -a 256 " + shellQuote(filePath));
assert(commandStatus == 0, "Hash failed: %s", output);
parts = split(strtrim(output));
hash = string(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
