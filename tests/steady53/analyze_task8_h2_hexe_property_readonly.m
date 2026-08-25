function analysis = analyze_task8_h2_hexe_property_readonly(options)
%ANALYZE_TASK8_H2_HEXE_PROPERTY_READONLY Establishes the H2 read-only audit.
%   This Task 1 contract only verifies immutable sources and exposes empty
%   diagnostic sections for later, separately tested work. It never loads or
%   runs a Simulink model and it never creates an H2 report or data artifact.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = defaultConfig(root);
if nargin > 0
    config = applyTestOnlyOptions(config, options);
end

validateExceptionPoint(config.exceptionT_K, config.exceptionP_Pa);
inputMat = requireAbsolutePath(config.inputMat, "inputMat");
modelPath = requireAbsolutePath(config.modelPath, "modelPath");
propertyPath = requireAbsolutePath(config.propertyPath, "propertyPath");
paperPdfPath = requireAbsolutePath(config.paperPdfPath, "paperPdfPath");
validateExpectedHash(config.expectedInputSha256, "expectedInputSha256");
validateExpectedHash(config.expectedModelSha256, "expectedModelSha256");
validateExpectedHash(config.expectedPropertySha256, ...
    "expectedPropertySha256");
validateExpectedHash(config.expectedPaperPdfSha256, ...
    "expectedPaperPdfSha256");

protectedBefore = protectedHashes(root);
inputMatSha256 = requireMatchingHash(inputMat, ...
    config.expectedInputSha256, "steady53:H2InputHashMismatch", "Input MAT");
modelSha256 = requireMatchingHash(modelPath, ...
    config.expectedModelSha256, "steady53:H2ModelHashMismatch", "Formal model");
propertySha256 = requireMatchingHash(propertyPath, ...
    config.expectedPropertySha256, "steady53:H2PropertyHashMismatch", ...
    "He-Xe property source");
paperPdfSha256 = requireMatchingHash(paperPdfPath, ...
    config.expectedPaperPdfSha256, "steady53:H2PaperPdfHashMismatch", ...
    "Thesis PDF");

% Task 1 intentionally allows this one, named-variable MAT read only.
payload = load(inputMat, "result", "report", "spec");
validatePayload(payload);
propertySource = fileread(propertyPath);
if strlength(string(propertySource)) == 0
    error("steady53:H2InvalidPropertySource", ...
        "He-Xe property source is unexpectedly empty.");
end
paperInfo = dir(paperPdfPath);
if numel(paperInfo) ~= 1 || paperInfo.bytes <= 0
    error("steady53:H2InvalidPaperPdf", ...
        "Thesis PDF metadata is invalid.");
end

protectedAfter = protectedHashes(root);
if ~isequaln(protectedAfter, protectedBefore)
    error("steady53:H2ProtectedAssetChanged", ...
        "A protected asset changed during the read-only H2 audit.");
end

analysis = struct();
analysis.inputs = struct( ...
    "runId", config.runId, ...
    "exceptionT_K", config.exceptionT_K, ...
    "exceptionP_Pa", config.exceptionP_Pa, ...
    "inputMat", inputMat);
analysis.sourceAudit = struct( ...
    "inputMatSha256", inputMatSha256, ...
    "modelSha256", modelSha256, ...
    "propertySha256", propertySha256, ...
    "paperPdfSha256", paperPdfSha256, ...
    "paperPdfBytes", double(paperInfo.bytes), ...
    "protectedAssetHashesBefore", protectedBefore, ...
    "protectedAssetHashesAfter", protectedAfter);
analysis.coefficients = taskOnePlaceholder();
analysis.derivatives = taskOnePlaceholder();
analysis.densityRoots = taskOnePlaceholder();
analysis.thermoIdentity = taskOnePlaceholder();
analysis.domainSweep = taskOnePlaceholder();
analysis.hypothesisVerdicts = taskOnePlaceholder();
end

function config = defaultConfig(root)
runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
config = struct();
config.testOnly = false;
config.runId = runId;
config.inputMat = string(fullfile(root, "tmp", "steady53", "task8", ...
    runId, "nominal_500_report.mat"));
config.expectedInputSha256 = ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b";
config.modelPath = string(fullfile(root, "final_steady_24a.slx"));
config.expectedModelSha256 = ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d";
config.propertyPath = string(fullfile(root, "HeXe_property_simulink.m"));
config.expectedPropertySha256 = ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2";
config.paperPdfPath = string(fullfile( ...
    "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型", ...
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"));
config.expectedPaperPdfSha256 = ...
    "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a";
config.exceptionT_K = 992.38742737169468;
config.exceptionP_Pa = 1007910.8613125964;
end

function config = applyTestOnlyOptions(config, options)
if ~isstruct(options) || ~isscalar(options) || ...
        ~isfield(options, "testOnly") || ~isequal(options.testOnly, true)
    error("steady53:H2InvalidOptions", ...
        "Non-default options require explicit testOnly=true.");
end
allowed = ["testOnly" "inputMat" "expectedInputSha256" "modelPath" ...
    "expectedModelSha256" "propertyPath" "expectedPropertySha256" ...
    "paperPdfPath" "expectedPaperPdfSha256" "exceptionT_K" "exceptionP_Pa"];
actual = string(fieldnames(options));
if any(~ismember(actual, allowed)) || ~all(ismember(allowed, actual))
    error("steady53:H2InvalidOptions", ...
        "Test-only options must state the complete override contract.");
end
for index = 1:numel(allowed)
    config.(allowed(index)) = options.(allowed(index));
end
end

function validateExceptionPoint(T_K, P_Pa)
if ~isscalar(T_K) || ~isreal(T_K) || ~isfinite(T_K) || ...
        ~isscalar(P_Pa) || ~isreal(P_Pa) || ~isfinite(P_Pa) || ...
        T_K ~= 992.38742737169468 || P_Pa ~= 1007910.8613125964
    error("steady53:H2ExceptionPointMismatch", ...
        "H2 is restricted to the approved (T,P) exception point.");
end
end

function pathValue = requireAbsolutePath(value, label)
if ~(isstring(value) || ischar(value)) || ...
        ~isscalar(string(value)) || ismissing(string(value)) || ...
        strlength(string(value)) == 0 || ~startsWith(string(value), filesep)
    error("steady53:H2InvalidOptions", "%s must be an absolute path.", label);
end
pathValue = string(value);
end

function validateExpectedHash(value, label)
if ~(isstring(value) || ischar(value)) || ...
        isempty(regexp(char(string(value)), '^[0-9a-fA-F]{64}$', 'once'))
    error("steady53:H2InvalidOptions", "%s must be a SHA-256 value.", label);
end
end

function actual = requireMatchingHash(filePath, expected, identifier, label)
actual = sha256File(filePath);
if actual ~= lower(string(expected))
    error(identifier, "%s hash mismatch for '%s'.", label, filePath);
end
end

function validatePayload(payload)
required = ["result" "report" "spec"];
if ~isstruct(payload) || ~all(isfield(payload, required))
    error("steady53:H2InvalidInput", ...
        "Input MAT must contain result, report, and spec only.");
end
end

function placeholder = taskOnePlaceholder()
placeholder = struct("status", "notComputedInTask1", ...
    "evidenceGrade", "❓");
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
values = strings(numel(paths), 1);
for index = 1:numel(paths)
    values(index) = sha256File(paths(index));
end
hashes = table(paths, values, 'VariableNames', {'path', 'sha256'});
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:H2HashFailure", "Hash failed: %s", output);
end
parts = split(strtrim(output));
hash = lower(string(parts(1)));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
