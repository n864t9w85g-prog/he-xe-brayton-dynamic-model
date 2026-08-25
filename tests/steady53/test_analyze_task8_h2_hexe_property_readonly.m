function tests = test_analyze_task8_h2_hexe_property_readonly
%TEST_ANALYZE_TASK8_H2_HEXE_PROPERTY_READONLY Task 8 H2 read-only contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"));
addpath(root);
testCase.TestData.root = string(root);
testCase.TestData.options = validTestOptions(root);
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testFixedContractReturnsRequiredReadOnlySections(testCase)
before = protectedHashes(testCase.TestData.root);
analysis = analyze_task8_h2_hexe_property_readonly();
after = protectedHashes(testCase.TestData.root);

required = ["inputs" "sourceAudit" "coefficients" "derivatives" ...
    "densityRoots" "thermoIdentity" "domainSweep" "hypothesisVerdicts"];
verifyTrue(testCase, all(isfield(analysis, required)));
verifyEqual(testCase, analysis.inputs.exceptionT_K, ...
    992.38742737169468, "AbsTol", 1e-12);
verifyEqual(testCase, analysis.inputs.exceptionP_Pa, ...
    1007910.8613125964, "AbsTol", 1e-6);
verifyEqual(testCase, analysis.sourceAudit.inputMatSha256, ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b");
verifyEqual(testCase, analysis.sourceAudit.modelSha256, ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d");
verifyEqual(testCase, analysis.sourceAudit.propertySha256, ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
verifyEqual(testCase, analysis.sourceAudit.paperPdfSha256, ...
    "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a");
verifyEqual(testCase, after, before);
end

function testIncorrectExceptionPointFailsClosed(testCase)
options = testCase.TestData.options;
options.exceptionT_K = options.exceptionT_K + 1;
verifyError(testCase, @() analyze_task8_h2_hexe_property_readonly(options), ...
    "steady53:H2ExceptionPointMismatch");
end

function testInputHashMismatchFailsClosed(testCase)
options = testCase.TestData.options;
options.expectedInputSha256 = string(repmat('0', 1, 64));
verifyError(testCase, @() analyze_task8_h2_hexe_property_readonly(options), ...
    "steady53:H2InputHashMismatch");
end

function testModelHashMismatchFailsClosed(testCase)
options = testCase.TestData.options;
options.expectedModelSha256 = string(repmat('0', 1, 64));
verifyError(testCase, @() analyze_task8_h2_hexe_property_readonly(options), ...
    "steady53:H2ModelHashMismatch");
end

function testPropertyHashMismatchFailsClosed(testCase)
options = testCase.TestData.options;
options.expectedPropertySha256 = string(repmat('0', 1, 64));
verifyError(testCase, @() analyze_task8_h2_hexe_property_readonly(options), ...
    "steady53:H2PropertyHashMismatch");
end

function testPaperPdfHashMismatchFailsClosed(testCase)
options = testCase.TestData.options;
options.expectedPaperPdfSha256 = string(repmat('0', 1, 64));
verifyError(testCase, @() analyze_task8_h2_hexe_property_readonly(options), ...
    "steady53:H2PaperPdfHashMismatch");
end

function testSourceIsStaticReadOnlyAndMatLoadIsRestricted(testCase)
sourcePath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "analyze_task8_h2_hexe_property_readonly.m");
source = fileread(sourcePath);
forbiddenModelApis = regexp(source, ...
    '(?<![A-Za-z0-9_])(set_param|sim|save_system|load_system|bdclose)\s*\(', ...
    'match');
verifyEmpty(testCase, forbiddenModelApis);
forbiddenWriters = regexp(source, ...
    '(?<![A-Za-z0-9_])(save|writetable|writecell|writematrix|fopen|copyfile|movefile)\s*\(', ...
    'match');
verifyEmpty(testCase, forbiddenWriters);
verifyNotEmpty(testCase, regexp(source, ...
    'load\(inputMat,\s*"result",\s*"report",\s*"spec"\)', 'once'));
verifyEmpty(testCase, regexp(source, ...
    'load\([^\n]*\.slx', 'once'));
end

function testNoH2FormalOutputExists(testCase)
outputDir = fullfile(testCase.TestData.root, "tmp", "steady53", ...
    "task8_root_cause", "h2", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
verifyFalse(testCase, isfolder(outputDir));
verifyFalse(testCase, isfile(fullfile(outputDir, ...
    "h2_property_diagnostics.csv")));
verifyFalse(testCase, isfile(fullfile(outputDir, "h2_summary.txt")));
end

function options = validTestOptions(root)
options = struct();
options.testOnly = true;
options.inputMat = string(fullfile(root, "tmp", "steady53", "task8", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
    "nominal_500_report.mat"));
options.expectedInputSha256 = ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b";
options.modelPath = string(fullfile(root, "final_steady_24a.slx"));
options.expectedModelSha256 = ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d";
options.propertyPath = string(fullfile(root, "HeXe_property_simulink.m"));
options.expectedPropertySha256 = ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2";
options.paperPdfPath = string(fullfile( ...
    "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型", ...
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"));
options.expectedPaperPdfSha256 = ...
    "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a";
options.exceptionT_K = 992.38742737169468;
options.exceptionP_Pa = 1007910.8613125964;
end

function hashes = protectedHashes(root)
paths = string([ ...
    fullfile(root, "final_steady_24a.slx")
    fullfile(root, "HeXe_property_simulink.m")
    fullfile(root, "hexe_compressor_lookup.mat")
    fullfile(root, "radiator_table.mat")
    fullfile(root, "turbine_table1.mat")
    fullfile(root, "turbine_table2.mat")
    fullfile(root, "tmp", "steady53", "task8", ...
        "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3", ...
        "nominal_500_report.mat")
    "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型/空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"]);
hashes = strings(numel(paths), 1);
for index = 1:numel(paths)
    hashes(index) = sha256File(paths(index));
end
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
assert(status == 0, "Hash failed: %s", output);
hash = string(split(strtrim(output)));
hash = hash(1);
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
