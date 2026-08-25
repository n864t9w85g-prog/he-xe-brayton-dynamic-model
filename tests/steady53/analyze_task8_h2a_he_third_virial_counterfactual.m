function analysis = analyze_task8_h2a_he_third_virial_counterfactual(options)
%ANALYZE_TASK8_H2A_HE_THIRD_VIRIAL_COUNTERFACTUAL Locks the H2a Task 1 contract.
%   This function verifies the approved read-only inputs and delegates only
%   to the approved H2 analyzer. Task 1 performs no counterfactual calculation
%   and creates no output artifact.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
approvedConfig = defaultConfig(root);
config = approvedConfig;
if nargin > 0
    config = applyTestOnlyOptions(config, options);
end
validateConfig(config);
validateImmutableIdentity(config, approvedConfig);

protectedBefore = protectedHashes(config);
validateProtectedHashes(protectedBefore, config);
archivePeeledCommit = validateArchiveIdentity( ...
    root, config.archiveTag, config.expectedArchivePeeledCommit);

originalPath = path;
pathCleanup = onCleanup(@() path(originalPath));
addpath(root, "-begin");
addpath(fullfile(root, "tests", "steady53"), "-begin");
resolvedH2AnalyzerPath = validateH2AnalyzerResolution( ...
    root, config.h2AnalyzerResolutionProbe);
h2 = analyze_task8_h2_hexe_property_readonly();
clear pathCleanup
runIdMatches = h2.inputs.runId == config.runId;
exceptionPointMatches = ...
    h2.inputs.exceptionT_K == config.exceptionT_K && ...
    h2.inputs.exceptionP_Pa == config.exceptionP_Pa;
validateApprovedH2Identity(h2, protectedBefore, config, ...
    archivePeeledCommit);

protectedAfter = protectedHashes(config);
protectedAssetsUnchanged = isequaln(protectedAfter, protectedBefore);
if ~protectedAssetsUnchanged
    error("steady53:H2aProtectedAssetChanged", ...
        "A protected H2a Task 1 input changed during the read-only audit.");
end
if ~runIdMatches || ~exceptionPointMatches
    error("steady53:H2aBaselineParityMismatch", ...
        "The approved H2 baseline identity does not match H2a Task 1.");
end

analysis = struct();
analysis.inputs = struct( ...
    "runId", config.runId, ...
    "exceptionT_K", config.exceptionT_K, ...
    "exceptionP_Pa", config.exceptionP_Pa);
analysis.sourceAudit = sourceAudit(config, protectedBefore, ...
    protectedAfter, archivePeeledCommit, resolvedH2AnalyzerPath);
analysis.approval = struct( ...
    "scheme", "A", ...
    "variant", "ignoreHePureThirdVirialBeforeCurrentMixingRule", ...
    "pureHeliumThirdVirialTerm", "C111", ...
    "pureHeliumThirdVirialTreatment", "setToZero", ...
    "treatmentStage", "beforeCurrentMixingRule", ...
    "currentMixingRule", "unchanged", ...
    "allOtherPropertyTerms", "unchanged", ...
    "authorizesRepair", false, ...
    "loadsOrSimulatesSlx", false, ...
    "publishesArtifacts", false);
analysis.baselineParity = struct( ...
    "status", "verifiedReadOnlyAgainstApprovedH2", ...
    "evidenceGrade", "✅", ...
    "runIdMatches", runIdMatches, ...
    "exceptionPointMatches", exceptionPointMatches, ...
    "protectedAssetsUnchanged", protectedAssetsUnchanged);
baseline = evaluatePoint(config.exceptionT_K, config.exceptionP_Pa, ...
    "baseline", "none");
baseline = applyParityMutation(baseline, config.testOnlyParityMutation);
parity = baselineParityTable(h2, baseline);
if ~all(parity.pass)
    error("steady53:H2aBaselineParityMismatch", ...
        "The H2a baseline does not reproduce approved H2 evidence.");
end
analysis.baselineParity = struct( ...
    "status", "verifiedReadOnlyAgainstApprovedH2", ...
    "evidenceGrade", "✅", ...
    "runIdMatches", runIdMatches, ...
    "exceptionPointMatches", exceptionPointMatches, ...
    "protectedAssetsUnchanged", protectedAssetsUnchanged, ...
    "table", parity, "allSatisfied", all(parity.pass));
counterfactual = evaluatePoint(config.exceptionT_K, config.exceptionP_Pa, ...
    "ignoreHePureThirdVirial", config.testOnlyNonCMutation);
singleVariableGate = evaluateSingleVariableGate(baseline, counterfactual);
if ~singleVariableGate.allSatisfied
    error("steady53:H2aSingleVariableViolation", ...
        "The counterfactual changed a non-approved quantity.");
end
analysis.exceptionPoint = struct( ...
    "status", "completed", "evidenceGrade", "❓", ...
    "baseline", baseline, "counterfactual", counterfactual, ...
    "singleVariableGate", singleVariableGate);
[fixedPressureSweep, h1aPathSweep, pathParity] = ...
    evaluateTask3Sweeps(h2, config);
if ~all(pathParity.pass)
    error("steady53:H2aBaselineParityMismatch", ...
        "The H2a baseline domain boundaries do not reproduce approved H2 evidence.");
end
analysis.baselineParity.pointAllSatisfied = all(parity.pass);
analysis.baselineParity.pathTable = pathParity;
analysis.baselineParity.pathAllSatisfied = all(pathParity.pass);
analysis.baselineParity.allSatisfied = ...
    analysis.baselineParity.pointAllSatisfied && ...
    analysis.baselineParity.pathAllSatisfied;
[fixedPressureSweep, h1aPathSweep] = applySweepTestOnlyMutation( ...
    fixedPressureSweep, h1aPathSweep, config.testOnlySweepMutation);
validateSweepCompleteness(fixedPressureSweep);
validateSweepCompleteness(h1aPathSweep);
analysis.fixedPressureSweep = fixedPressureSweep;
analysis.h1aPathSweep = h1aPathSweep;
analysis.counterfactualVerdict = struct( ...
    "status", "notComputedInTask3", "evidenceGrade", "❓");
end

function config = defaultConfig(root)
runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
h2Dir = fullfile(root, "tmp", "steady53", "task8_root_cause", ...
    "h2", runId);
config = struct();
config.testOnly = false;
config.runId = runId;
config.exceptionT_K = 992.38742737169468;
config.exceptionP_Pa = 1007910.8613125964;
config.modelPath = string(fullfile(root, "final_steady_24a.slx"));
config.expectedModelSha256 = ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d";
config.propertyPath = string(fullfile(root, "HeXe_property_simulink.m"));
config.expectedPropertySha256 = ...
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2";
config.compressorMatPath = string(fullfile(root, ...
    "hexe_compressor_lookup.mat"));
config.expectedCompressorMatSha256 = ...
    "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579";
config.radiatorMatPath = string(fullfile(root, "radiator_table.mat"));
config.expectedRadiatorMatSha256 = ...
    "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304";
config.turbine1MatPath = string(fullfile(root, "turbine_table1.mat"));
config.expectedTurbine1MatSha256 = ...
    "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d";
config.turbine2MatPath = string(fullfile(root, "turbine_table2.mat"));
config.expectedTurbine2MatSha256 = ...
    "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33";
config.inputMatPath = string(fullfile(root, "tmp", "steady53", "task8", ...
    runId, "nominal_500_report.mat"));
config.expectedInputMatSha256 = ...
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b";
config.thesisPdfPath = string(fullfile( ...
    "/Users/ikunsredemptionmac/Downloads/不接入转子稳态模型", ...
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"));
config.expectedThesisPdfSha256 = ...
    "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a";
config.approvedH2CsvPath = string(fullfile( ...
    h2Dir, "h2_property_diagnostics.csv"));
config.expectedApprovedH2CsvSha256 = ...
    "b2998bdafd96cdd49d9fa4ff621dc586add229dd525a9d0d79a7c22fc71ee9d6";
config.approvedH2TxtPath = string(fullfile(h2Dir, "h2_summary.txt"));
config.expectedApprovedH2TxtSha256 = ...
    "1fa29cebd816d891fecddfa8c54863d1f672f44a8793cb6e32cf3084241f9799";
config.archiveTag = "archive/pre-restart-20260824";
config.expectedArchivePeeledCommit = ...
    "8f625c268c35a95c18a626305c1aa6a79ae2ace7";
config.h2AnalyzerResolutionProbe = string(fullfile(root, "tests", ...
    "steady53", "analyze_task8_h2_hexe_property_readonly.m"));
config.testOnlyNonCMutation = "none";
config.testOnlyParityMutation = "none";
config.testOnlySweepMutation = "none";
end

function config = applyTestOnlyOptions(config, options)
allowed = [ ...
    "testOnly" "runId" "exceptionT_K" "exceptionP_Pa" ...
    "modelPath" "expectedModelSha256" ...
    "propertyPath" "expectedPropertySha256" ...
    "compressorMatPath" "expectedCompressorMatSha256" ...
    "radiatorMatPath" "expectedRadiatorMatSha256" ...
    "turbine1MatPath" "expectedTurbine1MatSha256" ...
    "turbine2MatPath" "expectedTurbine2MatSha256" ...
    "inputMatPath" "expectedInputMatSha256" ...
    "thesisPdfPath" "expectedThesisPdfSha256" ...
    "approvedH2CsvPath" "expectedApprovedH2CsvSha256" ...
    "approvedH2TxtPath" "expectedApprovedH2TxtSha256" ...
    "archiveTag" "expectedArchivePeeledCommit" ...
    "h2AnalyzerResolutionProbe" "testOnlyNonCMutation" ...
    "testOnlyParityMutation" "testOnlySweepMutation"];
if ~isstruct(options) || ~isscalar(options) || ...
        ~isfield(options, "testOnly") || ~isequal(options.testOnly, true) || ...
        numel(fieldnames(options)) ~= numel(allowed) || ...
        ~all(ismember(allowed, string(fieldnames(options))))
    error("steady53:H2aInvalidOptions", ...
        "Test-only options must provide the complete approved contract.");
end
for index = 1:numel(allowed)
    config.(allowed(index)) = options.(allowed(index));
end
end

function validateConfig(config)
approvedRunId = ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
if ~isscalar(string(config.runId)) || config.runId ~= approvedRunId
    error("steady53:H2aRunIdMismatch", ...
        "H2a Task 1 run ID does not match the approved H2 run.");
end
if ~isscalar(config.exceptionT_K) || ~isreal(config.exceptionT_K) || ...
        ~isfinite(config.exceptionT_K) || ...
        ~isscalar(config.exceptionP_Pa) || ~isreal(config.exceptionP_Pa) || ...
        ~isfinite(config.exceptionP_Pa) || ...
        config.exceptionT_K ~= 992.38742737169468 || ...
        config.exceptionP_Pa ~= 1007910.8613125964
    error("steady53:H2aExceptionPointMismatch", ...
        "H2a Task 1 exception point is not the approved H2 point.");
end

pathFields = ["modelPath" "propertyPath" "compressorMatPath" ...
    "radiatorMatPath" "turbine1MatPath" "turbine2MatPath" ...
    "inputMatPath" "thesisPdfPath" "approvedH2CsvPath" ...
    "approvedH2TxtPath" "h2AnalyzerResolutionProbe"];
for field = pathFields
    value = string(config.(field));
    if ~isscalar(value) || ismissing(value) || strlength(value) == 0 || ...
            ~startsWith(value, filesep)
        error("steady53:H2aInvalidOptions", ...
            "Every H2a Task 1 source path must be absolute.");
    end
end

hashFields = ["expectedModelSha256" "expectedPropertySha256" ...
    "expectedCompressorMatSha256" "expectedRadiatorMatSha256" ...
    "expectedTurbine1MatSha256" "expectedTurbine2MatSha256" ...
    "expectedInputMatSha256" "expectedThesisPdfSha256" ...
    "expectedApprovedH2CsvSha256" "expectedApprovedH2TxtSha256"];
for field = hashFields
    value = char(string(config.(field)));
    if isempty(regexp(value, '^[0-9a-fA-F]{64}$', 'once'))
        error("steady53:H2aInvalidOptions", ...
            "Every expected H2a Task 1 file hash must be SHA-256.");
    end
end
if isempty(regexp(char(string(config.expectedArchivePeeledCommit)), ...
        '^[0-9a-fA-F]{40}$', 'once'))
    error("steady53:H2aInvalidOptions", ...
        "The expected H2a archive commit must be a Git SHA-1 ID.");
end
if ~isscalar(string(config.testOnlyNonCMutation)) || ...
        ~ismember(string(config.testOnlyNonCMutation), ...
        ["none" "B" "dB_dT" "C222"])
    error("steady53:H2aInvalidOptions", ...
        "testOnlyNonCMutation is restricted to the approved test fixture.");
end
if ~isscalar(string(config.testOnlyParityMutation)) || ...
        ~ismember(string(config.testOnlyParityMutation), ...
        ["none" "C111" "C" "dC_dT"])
    error("steady53:H2aInvalidOptions", ...
        "testOnlyParityMutation is restricted to the approved test fixture.");
end
if ~isscalar(string(config.testOnlySweepMutation)) || ...
        ~ismember(string(config.testOnlySweepMutation), ...
        ["none" "counterfactualNonphysical" "dropState" ...
        "unaccountedCoordinate" "unrecordedInvalid" ...
        "endpointZeroCandidate"])
    error("steady53:H2aInvalidOptions", ...
        "testOnlySweepMutation is restricted to the approved test fixture.");
end
end

function validateImmutableIdentity(config, approved)
pathFields = [ ...
    "modelPath"
    "propertyPath"
    "compressorMatPath"
    "radiatorMatPath"
    "turbine1MatPath"
    "turbine2MatPath"
    "inputMatPath"
    "thesisPdfPath"
    "approvedH2CsvPath"
    "approvedH2TxtPath"];
pathIdentifiers = [ ...
    "steady53:H2aModelPathMismatch"
    "steady53:H2aPropertyPathMismatch"
    "steady53:H2aCompressorMatPathMismatch"
    "steady53:H2aRadiatorMatPathMismatch"
    "steady53:H2aTurbine1MatPathMismatch"
    "steady53:H2aTurbine2MatPathMismatch"
    "steady53:H2aInputMatPathMismatch"
    "steady53:H2aThesisPdfPathMismatch"
    "steady53:H2aApprovedH2CsvPathMismatch"
    "steady53:H2aApprovedH2TxtPathMismatch"];
for index = 1:numel(pathFields)
    if string(config.(pathFields(index))) ~= ...
            string(approved.(pathFields(index)))
        error(pathIdentifiers(index), ...
            "H2a Task 1 path is not the independently approved identity.");
    end
end

hashFields = [ ...
    "expectedModelSha256"
    "expectedPropertySha256"
    "expectedCompressorMatSha256"
    "expectedRadiatorMatSha256"
    "expectedTurbine1MatSha256"
    "expectedTurbine2MatSha256"
    "expectedInputMatSha256"
    "expectedThesisPdfSha256"
    "expectedApprovedH2CsvSha256"
    "expectedApprovedH2TxtSha256"];
hashIdentifiers = [ ...
    "steady53:H2aModelHashMismatch"
    "steady53:H2aPropertyHashMismatch"
    "steady53:H2aCompressorMatHashMismatch"
    "steady53:H2aRadiatorMatHashMismatch"
    "steady53:H2aTurbine1MatHashMismatch"
    "steady53:H2aTurbine2MatHashMismatch"
    "steady53:H2aInputMatHashMismatch"
    "steady53:H2aThesisPdfHashMismatch"
    "steady53:H2aApprovedH2CsvHashMismatch"
    "steady53:H2aApprovedH2TxtHashMismatch"];
for index = 1:numel(hashFields)
    if lower(string(config.(hashFields(index)))) ~= ...
            lower(string(approved.(hashFields(index))))
        error(hashIdentifiers(index), ...
            "H2a Task 1 expected hash is not the approved identity.");
    end
end
end

function hashes = protectedHashes(config)
name = ["model"; "property"; "compressorMat"; "radiatorMat"; ...
    "turbine1Mat"; "turbine2Mat"; "inputMat"; "thesisPdf"; ...
    "approvedH2Csv"; "approvedH2Txt"];
pathValue = [config.modelPath; config.propertyPath; ...
    config.compressorMatPath; config.radiatorMatPath; ...
    config.turbine1MatPath; config.turbine2MatPath; ...
    config.inputMatPath; config.thesisPdfPath; ...
    config.approvedH2CsvPath; config.approvedH2TxtPath];
sha256 = strings(numel(pathValue), 1);
for index = 1:numel(pathValue)
    sha256(index) = sha256File(pathValue(index));
end
hashes = table(name, pathValue, sha256);
end

function validateProtectedHashes(hashes, config)
expected = [config.expectedModelSha256; config.expectedPropertySha256; ...
    config.expectedCompressorMatSha256; ...
    config.expectedRadiatorMatSha256; ...
    config.expectedTurbine1MatSha256; ...
    config.expectedTurbine2MatSha256; config.expectedInputMatSha256; ...
    config.expectedThesisPdfSha256; ...
    config.expectedApprovedH2CsvSha256; ...
    config.expectedApprovedH2TxtSha256];
identifiers = [ ...
    "steady53:H2aModelHashMismatch"
    "steady53:H2aPropertyHashMismatch"
    "steady53:H2aCompressorMatHashMismatch"
    "steady53:H2aRadiatorMatHashMismatch"
    "steady53:H2aTurbine1MatHashMismatch"
    "steady53:H2aTurbine2MatHashMismatch"
    "steady53:H2aInputMatHashMismatch"
    "steady53:H2aThesisPdfHashMismatch"
    "steady53:H2aApprovedH2CsvHashMismatch"
    "steady53:H2aApprovedH2TxtHashMismatch"];
for index = 1:height(hashes)
    if hashes.sha256(index) ~= lower(string(expected(index)))
        error(identifiers(index), ...
            "H2a Task 1 protected hash mismatch for '%s'.", ...
            hashes.pathValue(index));
    end
end
end

function commit = validateArchiveIdentity(root, tagName, expectedCommit)
approvedTag = "archive/pre-restart-20260824";
if ~isscalar(string(tagName)) || string(tagName) ~= approvedTag
    error("steady53:H2aArchiveTagMismatch", ...
        "H2a Task 1 archive tag is not the approved tag.");
end
command = "git -C " + shellQuote(root) + " rev-list -n 1 " + ...
    shellQuote(tagName);
[status, output] = system(command);
commit = lower(strtrim(string(output)));
if status ~= 0 || ...
        commit ~= lower(string(expectedCommit)) || ...
        commit ~= "8f625c268c35a95c18a626305c1aa6a79ae2ace7"
    error("steady53:H2aArchiveCommitMismatch", ...
        "H2a Task 1 archive tag does not resolve to the approved commit.");
end
end

function pathValue = validateH2AnalyzerResolution(root, resolutionProbe)
expected = string(fullfile(root, "tests", "steady53", ...
    "analyze_task8_h2_hexe_property_readonly.m"));
pathValue = string(which("analyze_task8_h2_hexe_property_readonly"));
if pathValue ~= expected || string(resolutionProbe) ~= expected
    error("steady53:H2aH2AnalyzerResolutionMismatch", ...
        "The H2 analyzer did not resolve to the approved worktree source.");
end
end

function validateApprovedH2Identity(h2, hashes, config, archiveCommit)
matches = h2.sourceAudit.modelSha256 == measuredHash(hashes, "model") && ...
    h2.sourceAudit.propertySha256 == measuredHash(hashes, "property") && ...
    h2.sourceAudit.inputMatSha256 == measuredHash(hashes, "inputMat") && ...
    h2.sourceAudit.paperPdfSha256 == measuredHash(hashes, "thesisPdf") && ...
    h2.sourceAudit.archiveTag == config.archiveTag && ...
    h2.sourceAudit.archivePeeledCommit == archiveCommit;
if ~matches
    error("steady53:H2aBaselineParityMismatch", ...
        "The read-only H2 baseline does not match the approved H2a sources.");
end
end

function audit = sourceAudit(config, before, after, archiveCommit, ...
        resolvedH2AnalyzerPath)
audit = struct( ...
    "modelSha256", measuredHash(before, "model"), ...
    "propertySha256", measuredHash(before, "property"), ...
    "compressorMatSha256", measuredHash(before, "compressorMat"), ...
    "radiatorMatSha256", measuredHash(before, "radiatorMat"), ...
    "turbine1MatSha256", measuredHash(before, "turbine1Mat"), ...
    "turbine2MatSha256", measuredHash(before, "turbine2Mat"), ...
    "inputMatSha256", measuredHash(before, "inputMat"), ...
    "thesisPdfSha256", measuredHash(before, "thesisPdf"), ...
    "approvedH2CsvSha256", measuredHash(before, "approvedH2Csv"), ...
    "approvedH2TxtSha256", measuredHash(before, "approvedH2Txt"), ...
    "archiveTag", config.archiveTag, ...
    "archivePeeledCommit", archiveCommit, ...
    "resolvedH2AnalyzerPath", resolvedH2AnalyzerPath, ...
    "approvedH2Outputs", struct( ...
        "csv", struct("path", measuredPath(before, "approvedH2Csv"), ...
            "sha256", measuredHash(before, "approvedH2Csv")), ...
        "txt", struct("path", measuredPath(before, "approvedH2Txt"), ...
            "sha256", measuredHash(before, "approvedH2Txt"))), ...
    "protectedAssetHashesBefore", before, ...
    "protectedAssetHashesAfter", after);
end

function hash = measuredHash(hashes, name)
row = hashes.name == string(name);
assert(nnz(row) == 1);
hash = hashes.sha256(row);
end

function pathValue = measuredPath(hashes, name)
row = hashes.name == string(name);
assert(nnz(row) == 1);
pathValue = hashes.pathValue(row);
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:H2aHashFailure", ...
        "Could not hash H2a Task 1 source '%s'.", filePath);
end
parts = split(strtrim(string(output)));
hash = lower(parts(1));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\''") + "'";
end

function state = evaluatePoint(T_K, P_Pa, variant, nonCMutation)
% Pure evaluator for the fixed approved point.  The two branches share every
% non-third-Virial operation; the counterfactual changes only approved C terms.
k = hexeConstants();
[b, dB, d2B] = secondVirialTerms(T_K, k);
[c, dc, d2c] = thirdVirialTerms(T_K, k, variant);
if string(nonCMutation) == "B"
    b.B = b.B + 1e-12;
elseif string(nonCMutation) == "dB_dT"
    dB = dB + 1e-12;
elseif string(nonCMutation) == "C222"
    c.C222 = 2*c.C222;
end
density = densityState(T_K, P_Pa, b.B, c.C, k.R0);
thermal = thermalState(T_K, b.B, dB, d2B, c.C, dc.C, d2c.C, density.rho, k);
state = struct( ...
    "T_K", T_K, "P_Pa", P_Pa, "variant", string(variant), ...
    "constants", k, ...
    "B11", b.B11, "B22", b.B22, "B12", b.B12, "B", b.B, ...
    "dB_dT", dB, "d2B_dT2", d2B, ...
    "C111", c.C111, "C222", c.C222, "C112", c.C112, "C122", c.C122, ...
    "C", c.C, "dC111_dT", dc.C111, "dC222_dT", dc.C222, ...
    "dC112_dT", dc.C112, "dC122_dT", dc.C122, "dC_dT", dc.C, ...
    "d2C111_dT2", d2c.C111, "d2C222_dT2", d2c.C222, ...
    "d2C112_dT2", d2c.C112, "d2C122_dT2", d2c.C122, "d2C_dT2", d2c.C, ...
    "eosForm", "P=rho*R*T*(1+B*rho+C*rho^2)", ...
    "eos", density.eos, "productionNewton", density.productionNewton, ...
    "newtonInitialGuess", density.productionNewton.initialGuess, ...
    "newtonIterations", density.productionNewton.maximumIterations, ...
    "clampRule", "rho=max(rawNewton,0.9*P_RT)", ...
    "tolerances", density.tolerances, "rho", thermal.rho, ...
    "cpMolar", thermal.cpMolar, "cvMolar", thermal.cvMolar, ...
    "cpMass", thermal.cpMass, "cvMass", thermal.cvMass, ...
    "gamma", thermal.gamma, "contributions", thermal.contributions);
end

function state = applyParityMutation(state, mutation)
% This test-only fixture attacks the baseline evidence after calculation; it
% never changes the approved default branch or any protected asset.
switch string(mutation)
    case "none"
    case "C111"
        state.C111 = 0;
    case "C"
        state.C = 0;
    case "dC_dT"
        state.dC_dT = 0;
    otherwise
        error("steady53:H2aInvalidOptions", "Parity mutation is not approved.");
end
end

function k = hexeConstants()
k = struct("R0", 8.314, "MHe", 4.0026e-3, "MXe", 131.293e-3, ...
    "xHe", 0.7172, "xXe", 1.0 - 0.7172, "TcHe", 5.19, "TcXe", 289.6, ...
    "rhoCHe", 69.64, "rhoCXe", 1099.7);
k.Tc12 = sqrt(k.TcHe*k.TcXe);
k.vHe = k.MHe/k.rhoCHe;
k.vXe = k.MXe/k.rhoCXe;
k.v12 = (1/8)*(k.vHe^(1/3) + k.vXe^(1/3))^3;
k.M = k.xXe*k.MXe + k.xHe*k.MHe;
end

function [b, dB, d2B] = secondVirialTerms(T, k)
thetaXe = T/k.TcXe;
theta12 = T/k.Tc12;
b = struct();
b.B11 = (8.4 - .0018*T + 115/sqrt(T) - 835/T)*1e-6;
b.B22 = secondVirial(thetaXe, k.vXe, .01);
b.B12 = secondVirial(theta12, k.v12, .001);
b.B = k.xHe^2*b.B11 + 2*k.xHe*k.xXe*b.B12 + k.xXe^2*b.B22;
dB11 = (-.0018 - 57.5/T^(3/2) + 835/T^2)*1e-6;
d2B11 = (86.25/T^2.5 - 1670/T^3)*1e-6;
[dB22, d2B22] = secondVirialDerivatives(thetaXe, k.TcXe, k.vXe, .01);
[dB12, d2B12] = secondVirialDerivatives(theta12, k.Tc12, k.v12, .001);
dB = k.xHe^2*dB11 + 2*k.xHe*k.xXe*dB12 + k.xXe^2*dB22;
d2B = k.xHe^2*d2B11 + 2*k.xHe*k.xXe*d2B12 + k.xXe^2*d2B22;
end

function B = secondVirial(theta, v, slope)
u = 102.732 - slope*theta - .44/theta^1.22;
B = v*(-102.6 + u*tanh(4.5*sqrt(theta)));
end

function [first, second] = secondVirialDerivatives(theta, criticalT, v, slope)
u = 102.732 - slope*theta - .44/theta^1.22;
t = tanh(4.5*sqrt(theta));
s2 = 1 - t^2;
du = -slope + .5368/theta^2.22;
dt = 2.25/sqrt(theta)*s2;
d2u = -1.191696/theta^3.22;
d2t = -1.125/theta^1.5*s2 - 10.125/theta*s2*t;
first = v*(du*t + u*dt)/criticalT;
second = v*(d2u*t + 2*du*dt + u*d2t)/criticalT^2;
end

function [c, dc, d2c] = thirdVirialTerms(T, k, variant)
[C111, dC111, d2C111] = thirdComponent(T, k.vHe, k.TcHe);
[C222, dC222, d2C222] = thirdComponent(T, k.vXe, k.TcXe);
if string(variant) == "ignoreHePureThirdVirial"
    c = struct("C111", 0, "C222", C222, "C112", 0, "C122", 0, ...
        "C", k.xXe^3*C222);
    dc = struct("C111", 0, "C222", dC222, "C112", 0, "C122", 0, ...
        "C", k.xXe^3*dC222);
    d2c = struct("C111", 0, "C222", d2C222, "C112", 0, "C122", 0, ...
        "C", k.xXe^3*d2C222);
    return
end
if string(variant) ~= "baseline"
    error("steady53:H2aInvalidOptions", "Variant is not approved.");
end
C112 = signedCubeRoot(C111^2*C222);
C122 = signedCubeRoot(C111*C222^2);
a = dC111/C111;
b = dC222/C222;
dc112 = C112*((2/3)*a + (1/3)*b);
dc122 = C122*((1/3)*a + (2/3)*b);
aPrime = d2C111/C111 - a^2;
bPrime = d2C222/C222 - b^2;
d2c112 = C112*((2/3)*aPrime + (1/3)*bPrime + ((2/3)*a + (1/3)*b)^2);
d2c122 = C122*((1/3)*aPrime + (2/3)*bPrime + ((1/3)*a + (2/3)*b)^2);
c = struct("C111", C111, "C222", C222, "C112", C112, "C122", C122, ...
    "C", k.xHe^3*C111 + 3*k.xHe^2*k.xXe*C112 + ...
    3*k.xHe*k.xXe^2*C122 + k.xXe^3*C222);
dc = struct("C111", dC111, "C222", dC222, "C112", dc112, "C122", dc122, ...
    "C", k.xHe^3*dC111 + 3*k.xHe^2*k.xXe*dc112 + ...
    3*k.xHe*k.xXe^2*dc122 + k.xXe^3*dC222);
d2c = struct("C111", d2C111, "C222", d2C222, "C112", d2c112, "C122", d2c122, ...
    "C", k.xHe^3*d2C111 + 3*k.xHe^2*k.xXe*d2c112 + ...
    3*k.xHe*k.xXe^2*d2c122 + k.xXe^3*d2C222);
end

function [value, first, second] = thirdComponent(T, v, criticalT)
theta = T/criticalT;
t = tanh(.84*theta);
s2 = 1 - t^2;
u = -.0862 - 3.6e-5*theta + .0237/theta^.059;
value = v^2*(.0757 + u*t);
du = -3.6e-5 - .0013983/theta^1.059;
dt = .84*s2;
d2u = .0014808/theta^2.059;
d2t = -1.4112*s2*t;
first = v^2*(du*t + u*dt)/criticalT;
second = v^2*(d2u*t + 2*du*dt + u*d2t)/criticalT^2;
end

function value = signedCubeRoot(argument)
value = sign(argument)*abs(argument)^(1/3);
end

function density = densityState(T, P, B, C, R0)
P_RT = P/(R0*T);
coefficients = [C B 1 -P_RT];
allRoots = roots(coefficients);
residual = polyval(coefficients, allRoots);
scale = abs(C)*abs(allRoots).^3 + abs(B)*abs(allRoots).^2 + ...
    abs(allRoots) + abs(P_RT);
slopes = R0*T*(1 + 2*B*allRoots + 3*C*allRoots.^2);
isReal = abs(imag(allRoots)) <= 1e-10*max(1, abs(allRoots));
stablePositiveCount = nnz(isReal & real(allRoots) > 0 & real(slopes) > 0);
rho = P_RT;
converged = false;
lastDelta = NaN;
for iteration = 1:30
    f = polyval(coefficients, rho);
    derivative = 3*C*rho^2 + 2*B*rho + 1;
    lastDelta = f/derivative;
    rho = rho - lastDelta;
    if abs(lastDelta) < 1e-14
        converged = true;
        break
    end
end
raw = rho;
clampFloor = .9*P_RT;
clamped = max(raw, clampFloor);
tolerances = struct("realRoot", 1e-10, "newtonDelta", 1e-14, ...
    "newtonIterations", 30, "clampFloorFactor", .9);
productionNewton = struct("initialGuess", P_RT, "maximumIterations", 30, ...
    "deltaTolerance", 1e-14, "iterations", iteration, "converged", converged, ...
    "lastDelta", lastDelta, "rawFinal", raw, "clampFloor", clampFloor, ...
    "clampedFinal", clamped, "clampChanged", clamped ~= raw, ...
    "rawPolynomialResidual", polyval(coefficients, raw));
eos = struct("polynomialCoefficients", coefficients, "allRoots", allRoots, ...
    "scaledResidual", abs(residual)./scale, "dPdrho", slopes, ...
    "stablePositiveRealRootCount", stablePositiveCount);
density = struct("rho", clamped, "eos", eos, ...
    "productionNewton", productionNewton, "tolerances", tolerances);
end

function thermal = thermalState(T, B, dB, d2B, C, dC, d2C, rho, k)
drhoNumerator = (rho + B*rho^2 + C*rho^3)/T + dB*rho^2 + dC*rho^3;
drhoDenominator = 1 + 2*B*rho + 3*C*rho^2;
drho = -drhoNumerator/drhoDenominator;
B1 = B - T*dB;
B2 = B1 - T^2*d2B;
C1 = 2*C - T*dC;
C2 = C - .5*T^2*d2C;
cpIdeal = 2.5*k.R0;
cpB = rho*k.R0*B2;
cpC = rho^2*k.R0*C2;
cpDensityB = k.R0*T*B1*drho;
cpDensityC = k.R0*T*rho*C1*drho;
cp = cpIdeal + cpB + cpC + cpDensityB + cpDensityC;
cvIdeal = 1.5*k.R0;
cvB = -rho*k.R0*T*(2*dB + T*d2B);
cvC = -rho^2*k.R0*T*(dC + .5*T*d2C);
cv = cvIdeal + cvB + cvC;
contributions = struct( ...
    "cpMolar", struct("ideal", cpIdeal, "BExplicit", cpB, ...
        "CExplicit", cpC, "densityDerivativeB", cpDensityB, ...
        "densityDerivativeC", cpDensityC, ...
        "densityDerivativeTotal", cpDensityB + cpDensityC, "total", cp), ...
    "cvMolar", struct("ideal", cvIdeal, "B", cvB, "C", cvC, "total", cv));
thermal = struct("rho", rho*k.M, "rhoHat", rho, "drhoHat_dT", drho, ...
    "cpMolar", cp, "cvMolar", cv, "cpMass", cp/k.M, "cvMass", cv/k.M, ...
    "gamma", cp/cv, "contributions", contributions);
end

function parity = baselineParityTable(h2, baseline)
names = strings(0, 1);
h2Values = zeros(0, 1);
h2aValues = zeros(0, 1);
    function append(name, h2Value, h2aValue)
        names(end + 1, 1) = string(name);
        h2Values(end + 1, 1) = h2Value;
        h2aValues(end + 1, 1) = h2aValue;
    end
append("B11", h2.coefficients.B11, baseline.B11);
append("B22", h2.coefficients.B22, baseline.B22);
append("B12", h2.coefficients.B12, baseline.B12);
append("B", h2.coefficients.B, baseline.B);
append("C111", h2.coefficients.C111, baseline.C111);
append("C222", h2.coefficients.C222, baseline.C222);
append("C112", h2.coefficients.C112, baseline.C112);
append("C122", h2.coefficients.C122, baseline.C122);
append("C", h2.coefficients.C, baseline.C);
append("dB_dT", h2.derivatives.analytic.dB_dT, baseline.dB_dT);
append("d2B_dT2", h2.derivatives.analytic.d2B_dT2, baseline.d2B_dT2);
append("dC_dT", h2.derivatives.analytic.dC_dT, baseline.dC_dT);
append("d2C_dT2", h2.derivatives.analytic.d2C_dT2, baseline.d2C_dT2);
for index = 1:numel(h2.densityRoots.allRoots)
    append("eosRoot" + index, real(h2.densityRoots.allRoots(index)), ...
        real(baseline.eos.allRoots(index)));
end
h2Stable = nnz([h2.densityRoots.realRootDiagnostics.root] > 0 & ...
    [h2.densityRoots.realRootDiagnostics.dPdrho_Pa_m3_per_mol] > 0);
append("stablePositiveRealRootCount", h2Stable, ...
    baseline.eos.stablePositiveRealRootCount);
append("newtonRawFinal", h2.densityRoots.productionNewton.rawFinal, ...
    baseline.productionNewton.rawFinal);
append("newtonClampedFinal", h2.densityRoots.productionNewton.clampedFinal, ...
    baseline.productionNewton.clampedFinal);
append("newtonClampChanged", double(h2.densityRoots.productionNewton.clampChanged), ...
    double(baseline.productionNewton.clampChanged));
append("rho", h2.production.diagnostic.rho, baseline.rho);
append("cpMolar", h2.thermoIdentity.eq2_15.analyticCpMolar, baseline.cpMolar);
append("cvMolar", h2.thermoIdentity.eq2_17.analyticCvMolar, baseline.cvMolar);
append("cpMass", h2.production.diagnostic.cpMass, baseline.cpMass);
append("gamma", h2.thermoIdentity.gamma.analytic, baseline.gamma);
cpNames = ["ideal" "BExplicit" "CExplicit" "densityDerivativeB" ...
    "densityDerivativeC" "densityDerivativeTotal" "total"];
for index = 1:numel(cpNames)
    name = cpNames(index);
    append("cp." + name, h2.thermoIdentity.contributions.cpMolar.(name), ...
        baseline.contributions.cpMolar.(name));
end
cvNames = ["ideal" "B" "C" "total"];
for index = 1:numel(cvNames)
    name = cvNames(index);
    append("cv." + name, h2.thermoIdentity.contributions.cvMolar.(name), ...
        baseline.contributions.cvMolar.(name));
end
names = names(:);
h2Values = h2Values(:);
h2aValues = h2aValues(:);
tolerance = parityTolerances(names, h2Values);
absoluteError = abs(h2Values - h2aValues);
pass = absoluteError <= tolerance;
parity = table(names, h2Values, h2aValues, absoluteError, tolerance, pass, ...
    'VariableNames', {'name' 'h2Value' 'h2aBaselineValue' ...
    'absoluteError' 'tolerance' 'pass'});
end

function tolerance = parityTolerances(names, h2Values)
% Coefficients and their temperature derivatives have microscopic units, so a
% macroscopic absolute floor would silently accept their deletion.  Use a
% relative tolerance with a sub-microscopic numerical floor for those rows.
tolerance = max(1e-12, 1e-10*abs(h2Values));
microNames = ["B11" "B22" "B12" "B" "C111" "C222" "C112" "C122" ...
    "C" "dB_dT" "d2B_dT2" "dC_dT" "d2C_dT2"];
micro = ismember(names, microNames);
tolerance(micro) = max(1e-30, 1e-8*abs(h2Values(micro)));
tolerance(names == "gamma") = 1e-13;
exact = ismember(names, ["stablePositiveRealRootCount" "newtonClampChanged"]);
tolerance(exact) = 0;
end

function [fixedSweep, h1aSweep, parity] = evaluateTask3Sweeps(h2, config)
persistent cachedFixed cachedH1a cachedParity
if ~isempty(cachedFixed)
    fixedSweep = cachedFixed;
    h1aSweep = cachedH1a;
    parity = cachedParity;
    return
end

zeroT_K = 992.38240920882117;
quantities = ["cp=0"; "cv=0"; "gamma=1"; "dP/drho=0"];
offsets_K = [1e-8; 3e-8; 1e-7; 3e-7; 1e-6; 3e-6; ...
    1e-5; 3e-5; 1e-4; 3e-4; 1e-3; 3e-3; 1e-2; 3e-2; 0.1];

fixedSpec = struct( ...
    "name", "fixedPressure", "coordinateName", "T_K", ...
    "coordinateRange", [zeroT_K - 0.1 zeroT_K + 0.1], ...
    "coarseCoordinates", linspace(zeroT_K - 0.1, zeroT_K + 0.1, 81)', ...
    "seedCoordinates", unique([zeroT_K; zeroT_K - offsets_K; ...
        zeroT_K + offsets_K]), ...
    "zeroCoordinate", zeroT_K, ...
    "fixedPressure_Pa", config.exceptionP_Pa);
fixedSweep = evaluateTask3Sweep(fixedSpec, quantities);

T1_K = 1515.109678670083;
P1_Pa = 1538809.802594816;
expansionRatio = 2.2812178550028612;
Tlow_K = T1_K/expansionRatio;
P2_Pa = 674556.267925093;
zeroLambda = (zeroT_K - T1_K)/(Tlow_K - T1_K);
lambdaOffsets = offsets_K/abs(Tlow_K - T1_K);
h1aSpec = struct( ...
    "name", "h1aPath", "coordinateName", "lambda", ...
    "coordinateRange", [0 1], ...
    "coarseCoordinates", linspace(0, 1, 101)', ...
    "seedCoordinates", unique([zeroLambda; zeroLambda - lambdaOffsets; ...
        zeroLambda + lambdaOffsets]), ...
    "zeroCoordinate", zeroLambda, ...
    "T1_K", T1_K, "P1_Pa", P1_Pa, ...
    "expansionRatio", expansionRatio, "Tlow_K", Tlow_K, "P2_Pa", P2_Pa);
h1aSpec.seedCoordinates = h1aSpec.seedCoordinates( ...
    h1aSpec.seedCoordinates >= 0 & h1aSpec.seedCoordinates <= 1);
h1aSweep = evaluateTask3Sweep(h1aSpec, quantities);
parity = task3BaselineParity(h2, fixedSweep, h1aSweep);

cachedFixed = fixedSweep;
cachedH1a = h1aSweep;
cachedParity = parity;
end

function sweep = evaluateTask3Sweep(spec, quantities)
[coordinates, candidateLedger] = adaptiveCoordinates(spec, quantities);
baseline = evaluateTask3Branch(spec, coordinates, candidateLedger, ...
    quantities, "baseline");
counterfactual = evaluateTask3Branch(spec, coordinates, candidateLedger, ...
    quantities, "counterfactual");
if ~baseline.hasC111ZeroDerivativeDiscontinuity || ...
        counterfactual.hasC111ZeroDerivativeDiscontinuity
    error("steady53:H2aC111ClassificationFailed", ...
        "The approved C111 discontinuity treatment was not reproduced.");
end
sweep = struct( ...
    "status", "completed", "evidenceGrade", "❓", ...
    "quantitiesSearched", quantities, ...
    "branchNames", ["baseline" "counterfactual"], ...
    "coordinateName", spec.coordinateName, ...
    "coordinateRange", spec.coordinateRange, ...
    "coarseCoordinates", spec.coarseCoordinates, ...
    "adaptiveCoordinates", coordinates, ...
    "candidateLedger", candidateLedger, ...
    "baseline", baseline, "counterfactual", counterfactual);
if spec.name == "fixedPressure"
    sweep.fixedPressure_Pa = spec.fixedPressure_Pa;
    sweep.C111ZeroT_K = spec.zeroCoordinate;
else
    sweep.path = struct("T1_K", spec.T1_K, "P1_Pa", spec.P1_Pa, ...
        "expansionRatio", spec.expansionRatio, "Tlow_K", spec.Tlow_K, ...
        "P2_Pa", spec.P2_Pa, ...
        "temperatureFormula", "T1+lambda*(Tlow-T1)", ...
        "pressureFormula", "P1+lambda*(P2-P1)");
    sweep.C111ZeroLambda = spec.zeroCoordinate;
end
end

function [coordinates, ledger] = adaptiveCoordinates(spec, quantities)
coordinates = sort(unique([spec.coarseCoordinates(:); ...
    spec.seedCoordinates(:); spec.coordinateRange(:)]));
ledger = emptyCandidateLedger();
for level = 1:2
    added = zeros(0, 1);
    for variant = ["baseline" "counterfactual"]
        stateTable = evaluateTask3StateTable(spec, coordinates, variant);
        for quantity = quantities.'
            values = stateMetric(stateTable, quantity);
            for index = 1:(height(stateTable) - 1)
                left = stateTable.coordinate(index);
                right = stateTable.coordinate(index + 1);
                invalidCandidate = ~stateTable.valid(index) || ...
                    ~stateTable.valid(index + 1);
                signCandidate = isfinite(values(index)) && ...
                    isfinite(values(index + 1)) && ...
                    sign(values(index)) ~= sign(values(index + 1));
                if ~(invalidCandidate || signCandidate)
                    continue
                end
                middle = (left + right)/2;
                quarterLeft = (3*left + right)/4;
                quarterRight = (left + 3*right)/4;
                added = [added; quarterLeft; middle; quarterRight]; %#ok<AGROW>
                reason = "signTransition";
                if invalidCandidate
                    reason = "nonfiniteOrDiscontinuityNeighborhood";
                end
                row = table(variant, quantity, reason, level, left, right, ...
                    middle, 'VariableNames', ledger.Properties.VariableNames);
                ledger = [ledger; row]; %#ok<AGROW>
            end
        end
    end
    added = added(added > spec.coordinateRange(1) & ...
        added < spec.coordinateRange(2));
    newCoordinates = setdiff(unique(added), coordinates);
    if isempty(newCoordinates)
        break
    end
    coordinates = sort(unique([coordinates; newCoordinates]));
end
end

function ledger = emptyCandidateLedger()
ledger = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'branch' 'quantity' 'reason' 'adaptiveLevel' ...
    'bracketLeft' 'bracketRight' 'addedMidpoint'});
end

function branch = evaluateTask3Branch(spec, coordinates, candidateLedger, ...
        quantities, variant)
stateTable = evaluateTask3StateTable(spec, coordinates, variant);
boundaries = task3Boundaries(spec, stateTable, variant, quantities, ...
    candidateLedger);
counts = zeros(numel(quantities), 1);
for index = 1:numel(quantities)
    counts(index) = nnz(boundaries.quantity == quantities(index) & ...
        boundaries.classification == "root");
end
boundaryCountByQuantity = table(quantities, counts, ...
    'VariableNames', {'quantity' 'count'});
nonphysicalIntervals = task3NonphysicalIntervals(spec, stateTable, boundaries);
sampledExtrema = task3SampledExtrema(spec, stateTable);
invalidRows = ~stateTable.valid;
invalidStates = stateTable(invalidRows, ...
    {'coordinate' 'T_K' 'P_Pa' 'classification' 'reason'});
allCoordinatesAccountedFor = height(stateTable) == numel(coordinates) && ...
    isequaln(stateTable.coordinate, coordinates(:)) && ...
    height(invalidStates) == nnz(invalidRows);
discontinuityEvidence = task3C111DiscontinuityEvidence(spec, variant);
extrema = task3ClassifiedExtrema(sampledExtrema, boundaries, variant, ...
    discontinuityEvidence);
if variant == "baseline"
    c111Treatment = "currentFractionalPowerMixingRule";
else
    c111Treatment = "identicallyZeroBeforeCurrentMixingRule";
end
branchLedger = candidateLedger(candidateLedger.branch == variant, :);
rootSearchAssurance = task3RootSearchAssurance(coordinates, ...
    branchLedger, stateTable);
branch = struct( ...
    "name", variant, "status", "completed", ...
    "stateTable", stateTable, "boundaries", boundaries, ...
    "boundaryCountByQuantity", boundaryCountByQuantity, ...
    "nonphysicalIntervals", nonphysicalIntervals, "extrema", extrema, ...
    "sampledExtrema", sampledExtrema, ...
    "invalidStates", invalidStates, ...
    "allCoordinatesAccountedFor", allCoordinatesAccountedFor, ...
    "coarseCoordinates", spec.coarseCoordinates(:), ...
    "requestedCoordinates", coordinates(:), ...
    "candidateLedger", branchLedger, ...
    "rootSearchAssurance", rootSearchAssurance, ...
    "c111Treatment", c111Treatment, ...
    "C111ZeroCoordinate", spec.zeroCoordinate, ...
    "C111DiscontinuityEvidence", discontinuityEvidence, ...
    "hasC111ZeroDerivativeDiscontinuity", ...
        discontinuityEvidence.derivativeIsNonContinuous);
end

function assurance = task3RootSearchAssurance(coordinates, ledger, stateTable)
candidateCoordinates = ledger.addedMidpoint;
allCandidatesResolved = all(ismember(candidateCoordinates, ...
    stateTable.coordinate));
assurance = struct( ...
    "method", "adaptiveSignAndEndpointSearch", ...
    "formalRootExclusion", false, ...
    "notFoundMeaning", ...
        "noRootDetectedByDeclaredNumericalSearchNotFormalProof", ...
    "sampleCount", numel(coordinates), ...
    "maximumCoordinateGap", max(diff(coordinates)), ...
    "candidateLedgerEntryCount", height(ledger), ...
    "allCandidatesResolved", allCandidatesResolved);
end

function stateTable = evaluateTask3StateTable(spec, coordinates, variant)
states = repmat(emptyTask3State(), numel(coordinates), 1);
for index = 1:numel(coordinates)
    coordinate = coordinates(index);
    [T_K, P_Pa] = task3CoordinateToPoint(spec, coordinate);
    state = emptyTask3State();
    state.coordinate = coordinate;
    state.T_K = T_K;
    state.P_Pa = P_Pa;
    if variant == "baseline" && ...
            abs(coordinate - spec.zeroCoordinate) <= 1e-13
        point = evaluatePoint(T_K, P_Pa, "baseline", "none");
        rhoHat = point.productionNewton.clampedFinal;
        state.rho = point.rho;
        state.dPdrho = point.constants.R0*T_K*(1 + 2*point.B*rhoHat + ...
            3*point.C*rhoHat^2);
        state.stablePositiveRealRootCount = ...
            point.eos.stablePositiveRealRootCount;
        state.classification = "invalidRecordedDiscontinuity";
        state.reason = "C111ZeroDerivativeDiscontinuity";
        states(index) = state;
        continue
    end
    evaluatorVariant = "baseline";
    if variant == "counterfactual"
        evaluatorVariant = "ignoreHePureThirdVirial";
    end
    point = evaluatePoint(T_K, P_Pa, evaluatorVariant, "none");
    rhoHat = point.productionNewton.clampedFinal;
    dPdrho = point.constants.R0*T_K*(1 + 2*point.B*rhoHat + ...
        3*point.C*rhoHat^2);
    values = [point.rho point.cpMolar point.cvMolar point.gamma dPdrho ...
        point.eos.stablePositiveRealRootCount];
    state.rho = point.rho;
    state.cpMolar = point.cpMolar;
    state.cvMolar = point.cvMolar;
    state.gamma = point.gamma;
    state.dPdrho = dPdrho;
    state.stablePositiveRealRootCount = ...
        point.eos.stablePositiveRealRootCount;
    state.finite = isreal(values) && all(isfinite(values));
    state.valid = state.finite;
    if state.valid
        state.classification = "validFinite";
        state.reason = "none";
    else
        state.classification = "invalidRecordedNonfiniteOrComplex";
        state.reason = "nonfiniteOrComplexPropertyState";
    end
    states(index) = state;
end
stateTable = struct2table(states);
end

function evidence = task3C111DiscontinuityEvidence(spec, variant)
offsets_K = [1e-8; 1e-7; 1e-6; 1e-5; 1e-4; 1e-3; 1e-2];
if spec.name == "fixedPressure"
    coordinateOffsets = offsets_K;
else
    coordinateOffsets = offsets_K/abs(spec.Tlow_K - spec.T1_K);
end
leftCp = zeros(size(coordinateOffsets));
rightCp = zeros(size(coordinateOffsets));
for index = 1:numel(coordinateOffsets)
    leftCoordinate = spec.zeroCoordinate - coordinateOffsets(index);
    rightCoordinate = spec.zeroCoordinate + coordinateOffsets(index);
    leftState = evaluateTask3StateTable(spec, leftCoordinate, variant);
    rightState = evaluateTask3StateTable(spec, rightCoordinate, variant);
    leftCp(index) = leftState.cpMolar;
    rightCp(index) = rightState.cpMolar;
end
smallMagnitude = max(abs([leftCp(1) rightCp(1)]));
largeMagnitude = max(abs([leftCp(end) rightCp(end)]));
derivativeIsNonContinuous = all(isfinite([leftCp; rightCp])) && ...
    smallMagnitude > 10*largeMagnitude;
evidence = struct("offsets_K", offsets_K, ...
    "leftCpMolar", leftCp, "rightCpMolar", rightCp, ...
    "smallOffsetMagnitude", smallMagnitude, ...
    "largeOffsetMagnitude", largeMagnitude, ...
    "derivativeIsNonContinuous", derivativeIsNonContinuous, ...
    "classificationMethod", ...
        "oneSidedAdaptiveMagnitudeGrowthTowardC111Zero");
end

function state = emptyTask3State()
state = struct("coordinate", NaN, "T_K", NaN, "P_Pa", NaN, ...
    "rho", NaN, "cpMolar", NaN, "cvMolar", NaN, "gamma", NaN, ...
    "dPdrho", NaN, "stablePositiveRealRootCount", NaN, ...
    "finite", false, "valid", false, "classification", "invalid", ...
    "reason", "notEvaluated");
end

function boundaries = task3Boundaries(spec, stateTable, variant, quantities, ...
        ~)
boundaries = emptyTask3BoundaryTable();
cpRoots = ordinaryRootRows(spec, stateTable, variant, "cp=0", []);
cvRoots = ordinaryRootRows(spec, stateTable, variant, "cv=0", []);
densityRoots = ordinaryRootRows(spec, stateTable, variant, ...
    "dP/drho=0", []);
cvCoordinates = cvRoots.coordinate(cvRoots.classification == "root");
gammaRoots = ordinaryRootRows(spec, stateTable, variant, ...
    "gamma=1", cvCoordinates);
gammaPoles = emptyTask3BoundaryTable();
for index = 1:numel(cvCoordinates)
    cvRow = cvRoots(cvRoots.coordinate == cvCoordinates(index), :);
    bracketWidth = min(cvCoordinates(index) - cvRow.bracketLeft, ...
        cvRow.bracketRight - cvCoordinates(index));
    delta = max(1e-12, 1e-3*bracketWidth);
    leftCoordinate = cvCoordinates(index) - delta;
    rightCoordinate = cvCoordinates(index) + delta;
    leftValue = task3MetricAtCoordinate(spec, leftCoordinate, variant, "gamma=1");
    rightValue = task3MetricAtCoordinate(spec, rightCoordinate, variant, "gamma=1");
    [T_K, P_Pa] = task3CoordinateToPoint(spec, cvCoordinates(index));
    row = task3BoundaryRow("gamma=1", "pole", cvCoordinates(index), ...
        T_K, P_Pa, leftCoordinate, rightCoordinate, NaN, NaN, ...
        leftValue, rightValue, "notApplicablePole", ...
        "cvZeroGammaPoleNotGammaEqualsOneRoot");
    gammaPoles = [gammaPoles; row]; %#ok<AGROW>
end

rootSets = {cpRoots, cvRoots, gammaRoots, densityRoots};
for index = 1:numel(quantities)
    rootsForQuantity = rootSets{index};
    boundaries = [boundaries; rootsForQuantity]; %#ok<AGROW>
    if quantities(index) == "gamma=1"
        boundaries = [boundaries; gammaPoles]; %#ok<AGROW>
    end
    if ~any(rootsForQuantity.classification == "root")
        notFound = task3BoundaryRow(quantities(index), "notFound", ...
            NaN, NaN, NaN, spec.coordinateRange(1), spec.coordinateRange(2), ...
            NaN, task3ResidualTolerance(quantities(index)), NaN, NaN, ...
            "notApplicableNotFound", ...
            "noRootDetectedByDeclaredNumericalSearchNotFormalProof");
        boundaries = [boundaries; notFound]; %#ok<AGROW>
    end
end
end

function rows = ordinaryRootRows(spec, stateTable, variant, quantity, ...
        excluded)
rows = emptyTask3BoundaryTable();
values = stateMetric(stateTable, quantity);
tolerance = task3ResidualTolerance(quantity);
for index = 1:(height(stateTable) - 1)
    if ~stateTable.valid(index) || ~stateTable.valid(index + 1) || ...
            ~isfinite(values(index)) || ~isfinite(values(index + 1))
        continue
    end
    left = stateTable.coordinate(index);
    right = stateTable.coordinate(index + 1);
    if any(excluded >= left & excluded <= right)
        continue
    end
    endpointZero = values(index) == 0 || values(index + 1) == 0;
    signChange = sign(values(index)) ~= sign(values(index + 1));
    if ~(endpointZero || signChange)
        continue
    end
    metric = @(coordinate) task3MetricAtCoordinate( ...
        spec, coordinate, variant, quantity);
    refinement = refineOrdinaryRoot(metric, left, right, tolerance, ...
        quantity, variant);
    evidence = "adaptiveBracketRefinedWithFzero";
    rootCoordinate = refinement.rootCoordinate;
    residual = refinement.residual;
    if any(rows.classification == "root" & ...
            abs(rows.coordinate - rootCoordinate) <= 1e-9)
        continue
    end
    [T_K, P_Pa] = task3CoordinateToPoint(spec, rootCoordinate);
    row = task3BoundaryRow(quantity, "root", rootCoordinate, T_K, P_Pa, ...
        left, right, residual, tolerance, values(index), values(index + 1), ...
        refinement.refinementMethod, evidence);
    rows = [rows; row]; %#ok<AGROW>
end
end

function refinement = refineOrdinaryRoot(metric, left, right, tolerance, ...
        quantity, variant)
candidateLeftValue = metric(left);
candidateRightValue = metric(right);
options = optimset("TolX", 1e-12, "Display", "off");
[rootCoordinate, residual, exitFlag, solverOutput] = ...
    fzero(metric, [left right], options);
if exitFlag <= 0 || ~isfinite(rootCoordinate) || ...
        ~isfinite(residual) || abs(residual) > tolerance
    error("steady53:H2aBoundaryRefinementFailed", ...
        "Could not refine %s for %s.", quantity, variant);
end
refinement = struct( ...
    "rootCoordinate", rootCoordinate, ...
    "residual", residual, ...
    "exitFlag", exitFlag, ...
    "functionEvaluations", solverOutput.funcCount, ...
    "candidateLeftValue", candidateLeftValue, ...
    "candidateRightValue", candidateRightValue, ...
    "candidateBracket", [left right], ...
    "refinementMethod", "fzero");
end

function row = task3BoundaryRow(quantity, classification, coordinate, ...
        T_K, P_Pa, bracketLeft, bracketRight, residual, tolerance, ...
        leftValue, rightValue, refinementMethod, evidence)
row = table(string(quantity), string(classification), coordinate, T_K, P_Pa, ...
    bracketLeft, bracketRight, residual, tolerance, leftValue, rightValue, ...
    string(refinementMethod), string(evidence), 'VariableNames', ...
    emptyTask3BoundaryTable().Properties.VariableNames);
end

function boundaries = emptyTask3BoundaryTable()
boundaries = table(strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), ...
    'VariableNames', {'quantity' 'classification' 'coordinate' 'T_K' 'P_Pa' ...
    'bracketLeft' 'bracketRight' 'residual' 'residualTolerance' ...
    'leftValue' 'rightValue' 'refinementMethod' 'evidence'});
end

function value = task3MetricAtCoordinate(spec, coordinate, variant, quantity)
stateTable = evaluateTask3StateTable(spec, coordinate, variant);
if ~stateTable.valid
    value = NaN;
else
    values = stateMetric(stateTable, quantity);
    value = values(1);
end
end

function values = stateMetric(stateTable, quantity)
switch quantity
    case "cp=0"
        values = stateTable.cpMolar;
    case "cv=0"
        values = stateTable.cvMolar;
    case "gamma=1"
        values = stateTable.gamma - 1;
    case "dP/drho=0"
        values = stateTable.dPdrho;
    otherwise
        error("steady53:H2aInvalidOptions", ...
            "Unknown H2a Task 3 boundary quantity '%s'.", quantity);
end
end

function tolerance = task3ResidualTolerance(quantity)
switch quantity
    case {"cp=0", "cv=0"}
        tolerance = 1e-6;
    case "gamma=1"
        tolerance = 1e-10;
    case "dP/drho=0"
        tolerance = 1e-3;
end
end

function intervals = task3NonphysicalIntervals(spec, stateTable, boundaries)
intervals = emptyTask3IntervalTable();
criteria = ["cp<=0" "cv<=0" "gamma<=1"];
quantities = ["cp=0" "cv=0" "gamma=1"];
for criterionIndex = 1:numel(criteria)
    switch criteria(criterionIndex)
        case "cp<=0"
            mask = stateTable.valid & stateTable.cpMolar <= 0;
        case "cv<=0"
            mask = stateTable.valid & stateTable.cvMolar <= 0;
        case "gamma<=1"
            mask = stateTable.valid & stateTable.gamma <= 1;
    end
    edges = diff([false; mask; false]);
    starts = find(edges == 1);
    stops = find(edges == -1) - 1;
    for run = 1:numel(starts)
        startCoordinate = stateTable.coordinate(starts(run));
        endCoordinate = stateTable.coordinate(stops(run));
        if starts(run) > 1 && stateTable.valid(starts(run) - 1)
            candidates = boundaries.quantity == quantities(criterionIndex) & ...
                ismember(boundaries.classification, ["root" "pole"]) & ...
                boundaries.coordinate >= stateTable.coordinate(starts(run) - 1) & ...
                boundaries.coordinate <= startCoordinate;
            if any(candidates)
                startCoordinate = max(boundaries.coordinate(candidates));
            end
        end
        if stops(run) < height(stateTable) && stateTable.valid(stops(run) + 1)
            candidates = boundaries.quantity == quantities(criterionIndex) & ...
                ismember(boundaries.classification, ["root" "pole"]) & ...
                boundaries.coordinate >= endCoordinate & ...
                boundaries.coordinate <= stateTable.coordinate(stops(run) + 1);
            if any(candidates)
                endCoordinate = min(boundaries.coordinate(candidates));
            end
        end
        [startT, startP] = task3CoordinateToPoint(spec, startCoordinate);
        [endT, endP] = task3CoordinateToPoint(spec, endCoordinate);
        row = table(criteria(criterionIndex), startCoordinate, endCoordinate, ...
            startT, endT, startP, endP, ...
            'VariableNames', intervals.Properties.VariableNames);
        intervals = [intervals; row]; %#ok<AGROW>
    end
end
end

function intervals = emptyTask3IntervalTable()
intervals = table(strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', {'criterion' 'startCoordinate' 'endCoordinate' ...
    'startT_K' 'endT_K' 'startP_Pa' 'endP_Pa'});
end

function extrema = task3SampledExtrema(spec, stateTable)
extrema = emptyTask3ExtremaTable();
quantityNames = ["rho" "cpMolar" "cvMolar" "gamma" "dPdrho"];
for quantity = quantityNames
    values = stateTable.(quantity);
    eligible = stateTable.valid & isfinite(values);
    if ~any(eligible)
        continue
    end
    eligibleRows = find(eligible);
    [minimum, minOffset] = min(values(eligible));
    [maximum, maxOffset] = max(values(eligible));
    for item = {"min", minimum, eligibleRows(minOffset); ...
            "max", maximum, eligibleRows(maxOffset)}.'
        kind = string(item{1});
        value = item{2};
        rowIndex = item{3};
        coordinate = stateTable.coordinate(rowIndex);
        [T_K, P_Pa] = task3CoordinateToPoint(spec, coordinate);
        row = table(quantity, kind, coordinate, T_K, P_Pa, value, ...
            "sampledFiniteCandidateNotFormalGlobalExtremum", ...
            "finiteSampledCandidate", ...
            'VariableNames', extrema.Properties.VariableNames);
        extrema = [extrema; row]; %#ok<AGROW>
    end
end
end

function extrema = task3ClassifiedExtrema(sampledExtrema, boundaries, ...
        variant, discontinuityEvidence)
extrema = sampledExtrema;
if variant ~= "baseline"
    return
end
if discontinuityEvidence.derivativeIsNonContinuous
    extrema = markUnbounded(extrema, ["cpMolar" "cvMolar"], ...
        "unboundedAtC111DerivativeDiscontinuity");
end
hasGammaPole = any(boundaries.quantity == "gamma=1" & ...
    boundaries.classification == "pole");
if hasGammaPole
    extrema = markUnbounded(extrema, "gamma", "unboundedAtCvZeroPole");
end
end

function extrema = markUnbounded(extrema, quantities, classification)
for quantity = quantities
    minimum = extrema.quantity == quantity & extrema.kind == "min";
    maximum = extrema.quantity == quantity & extrema.kind == "max";
    extrema.coordinate(minimum | maximum) = NaN;
    extrema.T_K(minimum | maximum) = NaN;
    extrema.P_Pa(minimum | maximum) = NaN;
    extrema.value(minimum) = -Inf;
    extrema.value(maximum) = Inf;
    extrema.scope(minimum | maximum) = "continuousDomain";
    extrema.classification(minimum | maximum) = classification;
end
end

function extrema = emptyTask3ExtremaTable()
extrema = table(strings(0, 1), strings(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    strings(0, 1), 'VariableNames', ...
    {'quantity' 'kind' 'coordinate' 'T_K' 'P_Pa' 'value' ...
    'scope' 'classification'});
end

function [T_K, P_Pa] = task3CoordinateToPoint(spec, coordinate)
if spec.name == "fixedPressure"
    T_K = coordinate;
    P_Pa = spec.fixedPressure_Pa;
else
    T_K = spec.T1_K + coordinate*(spec.Tlow_K - spec.T1_K);
    P_Pa = spec.P1_Pa + coordinate*(spec.P2_Pa - spec.P1_Pa);
end
end

function parity = task3BaselineParity(h2, fixedSweep, h1aSweep)
names = ["fixedPressure.cp=0"; "fixedPressure.cv=0"; ...
    "h1aPath.cp=0"; "h1aPath.cv=0"];
approvedValue = [992.3980970081318; 992.40367034763892; ...
    0.61427357048046893; 0.61426702062376992];
h2Value = [ ...
    h2RootCoordinate(h2.domainSweep.fixedPressure.boundaries, "cp=0"); ...
    h2RootCoordinate(h2.domainSweep.fixedPressure.boundaries, "cv=0"); ...
    h2RootCoordinate(h2.domainSweep.h1aLowEndPath.boundaries, "cp=0"); ...
    h2RootCoordinate(h2.domainSweep.h1aLowEndPath.boundaries, "cv=0")];
h2aBaselineValue = [ ...
    h2aRootCoordinate(fixedSweep.baseline.boundaries, "cp=0"); ...
    h2aRootCoordinate(fixedSweep.baseline.boundaries, "cv=0"); ...
    h2aRootCoordinate(h1aSweep.baseline.boundaries, "cp=0"); ...
    h2aRootCoordinate(h1aSweep.baseline.boundaries, "cv=0")];
tolerance = [1e-8; 1e-8; 1e-10; 1e-10];
absoluteError = max([abs(h2Value - approvedValue), ...
    abs(h2aBaselineValue - approvedValue), ...
    abs(h2aBaselineValue - h2Value)], [], 2);
pass = absoluteError <= tolerance;
parity = table(names, approvedValue, h2Value, h2aBaselineValue, ...
    absoluteError, tolerance, pass, 'VariableNames', ...
    {'name' 'approvedValue' 'h2Value' 'h2aBaselineValue' ...
    'absoluteError' 'tolerance' 'pass'});
end

function coordinate = h2RootCoordinate(boundaries, quantity)
rows = boundaries.quantity == quantity;
if nnz(rows) ~= 1
    error("steady53:H2aBaselineParityMismatch", ...
        "Approved H2 did not contain exactly one %s boundary.", quantity);
end
coordinate = boundaries.rootCoordinate(rows);
end

function coordinate = h2aRootCoordinate(boundaries, quantity)
rows = boundaries.quantity == quantity & boundaries.classification == "root";
if nnz(rows) ~= 1
    error("steady53:H2aBaselineParityMismatch", ...
        "H2a baseline did not contain exactly one %s boundary.", quantity);
end
coordinate = boundaries.coordinate(rows);
end

function [fixedSweep, h1aSweep] = applySweepTestOnlyMutation( ...
        fixedSweep, h1aSweep, mutation)
switch string(mutation)
    case "none"
    case "counterfactualNonphysical"
        branch = fixedSweep.counterfactual;
        valid = branch.stateTable.valid;
        branch.stateTable.cpMolar(valid) = ...
            -abs(branch.stateTable.cpMolar(valid)) - 1;
        branch.stateTable.cvMolar(valid) = ...
            -abs(branch.stateTable.cvMolar(valid)) - 1;
        branch.stateTable.gamma(valid) = ...
            -abs(branch.stateTable.gamma(valid)) - 1;
        branch.boundaries = searchedNotFoundBoundaries( ...
            fixedSweep.quantitiesSearched, fixedSweep.coordinateRange);
        branch.boundaryCountByQuantity.count(:) = 0;
        spec = struct("name", "fixedPressure", ...
            "fixedPressure_Pa", fixedSweep.fixedPressure_Pa);
        branch.nonphysicalIntervals = task3NonphysicalIntervals( ...
            spec, branch.stateTable, branch.boundaries);
        branch.sampledExtrema = task3SampledExtrema(spec, branch.stateTable);
        branch.extrema = branch.sampledExtrema;
        fixedSweep.counterfactual = branch;
    case "dropState"
        fixedSweep.counterfactual.stateTable(end, :) = [];
    case "unaccountedCoordinate"
        fixedSweep.counterfactual.allCoordinatesAccountedFor = false;
    case "unrecordedInvalid"
        fixedSweep.counterfactual.stateTable.valid(1) = false;
        fixedSweep.counterfactual.stateTable.finite(1) = false;
        fixedSweep.counterfactual.stateTable.classification(1) = ...
            "invalidRecordedNonfiniteOrComplex";
        fixedSweep.counterfactual.stateTable.reason(1) = "testOnlyInvalid";
    case "endpointZeroCandidate"
        metric = @(coordinate) coordinate;
        fixedSweep.endpointZeroRefinementProbe = refineOrdinaryRoot( ...
            metric, 0, 1, 0, "testOnlyEndpointZero", "testOnly");
    otherwise
        error("steady53:H2aInvalidOptions", ...
            "Sweep mutation is not approved.");
end
end

function boundaries = searchedNotFoundBoundaries(quantities, coordinateRange)
boundaries = emptyTask3BoundaryTable();
for quantity = quantities.'
    row = task3BoundaryRow(quantity, "notFound", NaN, NaN, NaN, ...
        coordinateRange(1), coordinateRange(2), NaN, ...
        task3ResidualTolerance(quantity), NaN, NaN, ...
        "notApplicableNotFound", ...
        "noRootDetectedByDeclaredNumericalSearchNotFormalProof");
    boundaries = [boundaries; row]; %#ok<AGROW>
end
end

function validateSweepCompleteness(sweep)
requiredQuantities = ["cp=0"; "cv=0"; "gamma=1"; "dP/drho=0"];
complete = sweep.status == "completed" && ...
    isequal(sweep.quantitiesSearched, requiredQuantities) && ...
    isequal(sort(sweep.branchNames), sort(["baseline" "counterfactual"]));
for variant = ["baseline" "counterfactual"]
    branch = sweep.(variant);
    states = branch.stateTable;
    invalid = ~states.valid;
    invalidRecorded = height(branch.invalidStates) == nnz(invalid) && ...
        all(ismember(states.coordinate(invalid), branch.invalidStates.coordinate));
    coordinatesAccounted = branch.allCoordinatesAccountedFor && ...
        height(states) == numel(branch.requestedCoordinates) && ...
        isequaln(states.coordinate, branch.requestedCoordinates(:));
    finiteCoordinates = all(isfinite(states.coordinate)) && ...
        all(isfinite(states.T_K)) && all(isfinite(states.P_Pa));
    validStateEvidence = all(isfinite( ...
        states.stablePositiveRealRootCount(states.valid)));
    boundaryEvidence = true;
    for index = 1:numel(requiredQuantities)
        quantity = requiredQuantities(index);
        rows = branch.boundaries.quantity == quantity;
        countRow = branch.boundaryCountByQuantity.quantity == quantity;
        roots = rows & branch.boundaries.classification == "root";
        boundaryEvidence = boundaryEvidence && any(rows) && nnz(countRow) == 1 && ...
            branch.boundaryCountByQuantity.count(countRow) == nnz(roots);
        if any(roots)
            rootTable = branch.boundaries(roots, :);
            boundaryEvidence = boundaryEvidence && ...
                all(isfinite(rootTable.coordinate)) && ...
                all(isfinite(rootTable.T_K)) && all(isfinite(rootTable.P_Pa)) && ...
                all(isfinite(rootTable.bracketLeft)) && ...
                all(isfinite(rootTable.bracketRight)) && ...
                all(isfinite(rootTable.residual)) && ...
                all(abs(rootTable.residual) <= rootTable.residualTolerance) && ...
                all(isfinite(rootTable.leftValue)) && ...
                all(isfinite(rootTable.rightValue));
        end
    end
    complete = complete && branch.status == "completed" && ...
        coordinatesAccounted && finiteCoordinates && validStateEvidence && ...
        invalidRecorded && boundaryEvidence;
end
if ~complete
    error("steady53:H2aIncompleteSweep", ...
        "H2a Task 3 sweep evidence is incomplete or internally inconsistent.");
end
end

function gate = evaluateSingleVariableGate(baseline, counterfactual)
names = ["constants" "B11" "B22" "B12" "B" "eosForm" ...
    "newtonInitialGuess" "newtonIterations" "clampRule" "tolerances" "T_K" "P_Pa"]';
pass = [isequaln(baseline.constants, counterfactual.constants); ...
    baseline.B11 == counterfactual.B11; baseline.B22 == counterfactual.B22; ...
    baseline.B12 == counterfactual.B12; baseline.B == counterfactual.B; ...
    baseline.eosForm == counterfactual.eosForm; ...
    baseline.newtonInitialGuess == counterfactual.newtonInitialGuess; ...
    baseline.newtonIterations == counterfactual.newtonIterations; ...
    baseline.clampRule == counterfactual.clampRule; ...
    isequaln(baseline.tolerances, counterfactual.tolerances); ...
    baseline.T_K == counterfactual.T_K; baseline.P_Pa == counterfactual.P_Pa];
names = [names; "dB_dT"; "d2B_dT2"; "C222"; "dC222_dT"; "d2C222_dT2"];
pass = [pass; baseline.dB_dT == counterfactual.dB_dT; ...
    baseline.d2B_dT2 == counterfactual.d2B_dT2; ...
    baseline.C222 == counterfactual.C222; ...
    baseline.dC222_dT == counterfactual.dC222_dT; ...
    baseline.d2C222_dT2 == counterfactual.d2C222_dT2];
invariants = table(names, pass, 'VariableNames', {'name' 'pass'});
gate = struct("invariants", invariants, "allSatisfied", all(pass));
end
