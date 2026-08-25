function published = publish_task8_h2_evidence(analysis, options)
%PUBLISH_TASK8_H2_EVIDENCE Exclusively publishes approved Task 4 evidence.
%   The analyzer remains read-only. This publisher accepts only a complete,
%   fail-closed H2 analysis and atomically moves one fully validated staging
%   directory into the fixed run directory without replacement.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = defaultPublishConfig(root);
if nargin > 1
    config = applyTestOnlyPublishOptions(config, options);
end
validateCompleteEvidence(analysis);
outputDir = requireAbsolutePath(config.outputDir, "outputDir");

[outputParent, outputName, outputExtension] = fileparts(outputDir);
outputParent = string(outputParent);
outputLeaf = string(outputName) + string(outputExtension);
if ~isfolder(outputParent) || strlength(outputLeaf) == 0
    error("steady53:H2OutputFailed", ...
        "The H2 output parent must already exist.");
end
if isfolder(outputDir) || isfile(outputDir)
    error("steady53:H2OutputExists", ...
        "H2 output target already exists: '%s'.", outputDir);
end

diagnostics = buildDiagnosticsTable(analysis);
summaryText = buildSummaryText(analysis);
[csvHash, summaryHash] = writeOutputs(outputDir, diagnostics, ...
    summaryText, config.outputFailureHook);
published = struct( ...
    "status", "completed", ...
    "outputDir", outputDir, ...
    "csvFile", "h2_property_diagnostics.csv", ...
    "summaryFile", "h2_summary.txt", ...
    "csvSha256", csvHash, ...
    "summarySha256", summaryHash);
end

function config = defaultPublishConfig(root)
runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
config = struct( ...
    "testOnly", false, ...
    "outputDir", string(fullfile(root, "tmp", "steady53", ...
        "task8_root_cause", "h2", runId)), ...
    "outputFailureHook", @(~, ~) []);
end

function config = applyTestOnlyPublishOptions(~, options)
if ~isstruct(options) || ~isscalar(options) || ...
        ~all(isfield(options, ["testOnly" "outputDir" ...
        "outputFailureHook"])) || numel(fieldnames(options)) ~= 3 || ...
        ~isequal(options.testOnly, true) || ...
        ~isa(options.outputFailureHook, "function_handle")
    error("steady53:H2InvalidPublishOptions", ...
        "Publish overrides require the complete explicit testOnly contract.");
end
config = options;
end

function validateCompleteEvidence(analysis)
try
    requiredTop = ["inputs" "sourceAudit" "coefficients" "derivatives" ...
        "densityRoots" "production" "thermoIdentity" "domainSweep" ...
        "hypothesisVerdicts"];
    assert(isstruct(analysis) && isscalar(analysis) && ...
        all(isfield(analysis, requiredTop)));
    assert(analysis.inputs.runId == ...
        "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
    assert(analysis.sourceAudit.inputMatSha256 == ...
        "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b");
    assert(analysis.sourceAudit.modelSha256 == ...
        "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d");
    assert(analysis.sourceAudit.propertySha256 == ...
        "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
    assert(analysis.sourceAudit.paperPdfSha256 == ...
        "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a");
    assert(isequaln(analysis.sourceAudit.protectedAssetHashesBefore, ...
        analysis.sourceAudit.protectedAssetHashesAfter));
    assert(analysis.production.parity.allWithinTolerance);
    assert(analysis.thermoIdentity.formulaConsistency.allSatisfied);
    assert(~analysis.thermoIdentity.physicalDomain.allSatisfied);
    assert(analysis.domainSweep.status == "completedTask4");
    assert(analysis.domainSweep.evidenceGrade == "✅");
    assert(analysis.domainSweep.C111DerivativeDiscontinuity. ...
        derivativeIsNonContinuous);
    assertValidScan(analysis.domainSweep.fixedPressure);
    assertValidScan(analysis.domainSweep.h1aLowEndPath);
    verdicts = analysis.hypothesisVerdicts;
    assert(verdicts.status == "completedTask4");
    assert(~verdicts.implementationError.supported && ...
        verdicts.implementationError.evidenceGrade == "❌");
    assert(~verdicts.densityRootError.supported && ...
        verdicts.densityRootError.evidenceGrade == "❌");
    assert(verdicts.directPaperCorrelationNonphysical.supported && ...
        verdicts.directPaperCorrelationNonphysical.evidenceGrade == "✅");
    assert(verdicts.provenanceApplicability.evidenceGrade == "✅");
    assert(~verdicts.authorizesRepair);
    literature = analysis.sourceAudit.originalLiterature;
    assert(literature.status == "verifiedInTask4" && ...
        all(literature.claimEvidenceGrade == "✅"));
catch exception
    invalid = MException("steady53:H2InvalidEvidence", ...
        "H2 evidence is incomplete, inconsistent, or hash-mismatched.");
    invalid = addCause(invalid, exception);
    throw(invalid);
end
end

function assertValidScan(scan)
requiredColumns = ["quantity" "bracketLeft" "bracketRight" ...
    "rootCoordinate" "T_K" "P_Pa" "residual" ...
    "residualTolerance" "leftValue" "rightValue" ...
    "leftState" "rightState"];
assert(isstruct(scan) && isscalar(scan) && istable(scan.boundaries));
assert(all(ismember(requiredColumns, ...
    string(scan.boundaries.Properties.VariableNames))));
assert(all(scan.boundaries.bracketLeft < scan.boundaries.rootCoordinate));
assert(all(scan.boundaries.rootCoordinate < scan.boundaries.bracketRight));
assert(all(abs(scan.boundaries.residual) <= ...
    scan.boundaries.residualTolerance));
assert(all(scan.boundaries.leftState ~= scan.boundaries.rightState));
end

function diagnostics = buildDiagnosticsTable(analysis)
section = strings(0, 1);
name = strings(0, 1);
value = strings(0, 1);
units = strings(0, 1);
evidenceGrade = strings(0, 1);
source = strings(0, 1);
    function add(sectionValue, nameValue, valueValue, unitsValue, ...
            gradeValue, sourceValue)
        section(end + 1, 1) = sectionValue;
        name(end + 1, 1) = nameValue;
        value(end + 1, 1) = string(valueValue);
        units(end + 1, 1) = unitsValue;
        evidenceGrade(end + 1, 1) = gradeValue;
        source(end + 1, 1) = sourceValue;
    end

add("input", "exceptionT", compose("%.17g", analysis.inputs.exceptionT_K), ...
    "K", "✅", "fixed H1a-S2 exception point");
add("input", "exceptionP", compose("%.17g", analysis.inputs.exceptionP_Pa), ...
    "Pa", "✅", "fixed H1a-S2 exception point");
for hashName = ["inputMatSha256" "modelSha256" "propertySha256" ...
        "paperPdfSha256"]
    add("hash", hashName, analysis.sourceAudit.(hashName), "SHA-256", ...
        "✅", "read-only source audit");
end
thermo = analysis.thermoIdentity;
add("thermo", "cpMolar", compose("%.17g", ...
    thermo.eq2_15.analyticCpMolar), "J/(mol K)", "✅", "thesis Eq.2.15");
add("thermo", "cvMolar", compose("%.17g", ...
    thermo.eq2_17.analyticCvMolar), "J/(mol K)", "✅", "thesis Eq.2.17");
add("thermo", "gamma", compose("%.17g", thermo.gamma.analytic), ...
    "1", "✅", "cp/cv");
add("thermo", "enthalpyCpRelativeError", compose("%.17g", ...
    thermo.enthalpyFiniteDifference.finalRelativeError), "1", "✅", ...
    "fixed-P centered difference plus Richardson");
add("thermo", "cpMinusCvRelativeError", compose("%.17g", ...
    thermo.eosIdentity.relativeError), "1", "✅", "EOS identity");

cp = thermo.contributions.cpMolar;
for field = ["ideal" "BExplicit" "CExplicit" ...
        "densityDerivativeB" "densityDerivativeC" "total"]
    add("cpContribution", field, compose("%.17g", cp.(field)), ...
        "J/(mol K)", "✅", "Task3 contribution decomposition");
end
cv = thermo.contributions.cvMolar;
for field = ["ideal" "B" "C" "total"]
    add("cvContribution", field, compose("%.17g", cv.(field)), ...
        "J/(mol K)", "✅", "Task3 contribution decomposition");
end
components = thermo.contributions.thirdVirialComponents;
for index = 1:height(components)
    add("thirdVirial", components.name(index) + ".cvMolar", ...
        compose("%.17g", components.cvMolar(index)), "J/(mol K)", ...
        "✅", "C value/first/second derivative trace");
end

for scanName = ["fixedPressure" "h1aLowEndPath"]
    boundaries = analysis.domainSweep.(scanName).boundaries;
    for index = 1:height(boundaries)
        prefix = scanName + "." + boundaries.quantity(index) + "." + index;
        add("boundary", prefix + ".bracket", compose("[%.17g,%.17g]", ...
            boundaries.bracketLeft(index), boundaries.bracketRight(index)), ...
            analysis.domainSweep.(scanName).coordinateName, "✅", ...
            "adaptive fzero bracket");
        add("boundary", prefix + ".root", compose("%.17g", ...
            boundaries.rootCoordinate(index)), ...
            analysis.domainSweep.(scanName).coordinateName, "✅", ...
            "adaptive fzero root");
        add("boundary", prefix + ".residual", compose("%.17g", ...
            boundaries.residual(index)), "quantity units", "✅", ...
            "adaptive fzero residual");
    end
end
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;
add("boundary", "C111ZeroT", compose("%.17g", singularity.rootT_K), ...
    "K", "✅", "adaptive C111 root and one-sided states");
add("boundary", "C111Residual", compose("%.17g", ...
    singularity.C111Residual), "m6/mol2", "✅", "C111 correlation");

verdicts = analysis.hypothesisVerdicts;
add("verdict", "implementation_error", "not_supported", "", "❌", ...
    verdicts.implementationError.basis);
add("verdict", "density_root_error", "not_supported", "", "❌", ...
    "unique stable positive real root matches production Newton root");
add("verdict", "direct_paper_correlation_nonphysical", "supported", ...
    "", "✅", "formula-consistent direct thesis correlation is nonphysical");
add("verdict", "authorizesRepair", "false", "", "✅", ...
    "read-only H2 scope");

literature = analysis.sourceAudit.originalLiterature;
for index = 1:numel(literature.claims)
    add("provenance", "claim" + index, literature.claims(index), "", ...
        literature.claimEvidenceGrade(index), literature.fullTextUrl);
end
add("provenance", "officialMetadataRelationship", ...
    literature.officialMetadataRelationship, "", ...
    literature.officialMetadataEvidenceGrade, literature.officialMetadataUrl);
diagnostics = table(section, name, value, units, evidenceGrade, source);
end

function text = buildSummaryText(analysis)
thermo = analysis.thermoIdentity;
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;
fixed = analysis.domainSweep.fixedPressure.boundaries;
path = analysis.domainSweep.h1aLowEndPath.boundaries;
literature = analysis.sourceAudit.originalLiterature;
lines = [ ...
    "Task 8 H2 He-Xe property read-only root-cause evidence"
    "status=READ_ONLY_ROOT_CAUSE_COMPLETE"
    "h1aS2Status=BLOCKED_BY_PROPERTY_DOMAIN"
    "task8Status=RED_NOT_COMPLETED"
    "steady14000sStatus=NOT_COMPLETED"
    "slxLoadedOrSimulated=false"
    "formalAssetsModified=false"
    "authorizesRepair=false"
    "implementation_error=❌ not_supported"
    "density_root_error=❌ not_supported"
    "direct_paper_correlation_nonphysical=✅ supported"
    "provenance_applicability=✅ source framework differs from current thesis formula use"
    "inputRunId=" + analysis.inputs.runId
    "inputMatSha256=" + analysis.sourceAudit.inputMatSha256
    "modelSha256=" + analysis.sourceAudit.modelSha256
    "propertySha256=" + analysis.sourceAudit.propertySha256
    "paperPdfSha256=" + analysis.sourceAudit.paperPdfSha256
    compose("exceptionT_K=%.17g", analysis.inputs.exceptionT_K)
    compose("exceptionP_Pa=%.17g", analysis.inputs.exceptionP_Pa)
    compose("cpMolar_J_mol_K=%.17g", thermo.eq2_15.analyticCpMolar)
    compose("cvMolar_J_mol_K=%.17g", thermo.eq2_17.analyticCvMolar)
    compose("gamma=%.17g", thermo.gamma.analytic)
    compose("enthalpyCpRelativeError=%.17g", ...
        thermo.enthalpyFiniteDifference.finalRelativeError)
    compose("cpMinusCvRelativeError=%.17g", ...
        thermo.eosIdentity.relativeError)
    compose("C111ZeroT_K=%.17g", singularity.rootT_K)
    compose("C111Residual=%.17g", singularity.C111Residual)
    "fixedPressureBoundaryCount=" + height(fixed)
    "h1aLowEndPathBoundaryCount=" + height(path)
    "fullTextUrl=" + literature.fullTextUrl
    "officialMetadataUrl=" + literature.officialMetadataUrl
    "officialMetadataRelationship=" + literature.officialMetadataRelationship
    "Boundary: H2 diagnoses the current direct formula only; it does not select a repair, clipping value, or replacement property model."];
text = strjoin(lines, newline) + newline;
end

function [csvHash, summaryHash] = writeOutputs(outputDir, ...
        diagnostics, summaryText, outputFailureHook)
[outputParent, outputName, outputExtension] = fileparts(outputDir);
outputParent = string(outputParent);
outputLeaf = string(outputName) + string(outputExtension);
stagingPrefix = "." + outputLeaf + ".staging_";
[~, uniqueLeaf] = fileparts(tempname(outputParent));
stagingDir = fullfile(outputParent, stagingPrefix + string(uniqueLeaf));
if isfolder(stagingDir) || isfile(stagingDir)
    error("steady53:H2OutputFailed", ...
        "The unique H2 staging path unexpectedly exists.");
end
[created, message, messageId] = mkdir(stagingDir);
if ~created || strlength(string(messageId)) > 0 || ~isfolder(stagingDir)
    error("steady53:H2OutputFailed", ...
        "Could not create unique H2 staging directory '%s': %s", ...
        stagingDir, message);
end
stagingCleanup = onCleanup(@() cleanupStagingDirectory( ...
    stagingDir, outputParent, stagingPrefix));

stagedCsv = fullfile(stagingDir, "h2_property_diagnostics.csv");
stagedSummary = fullfile(stagingDir, "h2_summary.txt");
writetable(diagnostics, stagedCsv);
outputFailureHook("afterCsvBeforeSummary", stagingDir);
[fileId, message] = fopen(stagedSummary, "w", "native", "UTF-8");
if fileId < 0
    error("steady53:H2OutputFailed", ...
        "Could not create staged summary '%s': %s", stagedSummary, message);
end
try
    fprintf(fileId, "%s", summaryText);
catch exception
    fclose(fileId);
    rethrow(exception);
end
closeStatus = fclose(fileId);
if closeStatus ~= 0
    error("steady53:H2OutputFailed", ...
        "Could not close staged summary '%s'.", stagedSummary);
end
validateReadableOutput(stagedCsv);
validateReadableOutput(stagedSummary);
csvHash = sha256File(stagedCsv);
summaryHash = sha256File(stagedSummary);

if isfolder(outputDir) || isfile(outputDir)
    error("steady53:H2OutputExists", ...
        "H2 output target appeared before publication: '%s'.", outputDir);
end
outputFailureHook("beforePublish", stagingDir);
moveDirectoryNoReplace(stagingDir, outputDir);
try
    validatePublishedDirectory(outputDir, csvHash, summaryHash);
catch exception
    cleanupPublishedDirectory(outputDir, outputParent, outputLeaf);
    rethrow(exception);
end
clear stagingCleanup
end

function validateReadableOutput(filePath)
info = dir(filePath);
if numel(info) ~= 1 || info.bytes <= 0
    error("steady53:H2OutputFailed", ...
        "Staged H2 output is missing or empty: '%s'.", filePath);
end
[fileId, message] = fopen(filePath, "r");
if fileId < 0
    error("steady53:H2OutputFailed", ...
        "Staged H2 output is not readable '%s': %s", filePath, message);
end
closeStatus = fclose(fileId);
if closeStatus ~= 0
    error("steady53:H2OutputFailed", ...
        "Could not close staged H2 output '%s'.", filePath);
end
end

function validatePublishedDirectory(outputDir, csvHash, summaryHash)
entries = dir(outputDir);
names = sort(string({entries(~[entries.isdir]).name}));
expected = sort(["h2_property_diagnostics.csv" "h2_summary.txt"]);
if ~isfolder(outputDir) || ~isequal(names, expected)
    error("steady53:H2OutputFailed", ...
        "Published H2 output directory is incomplete or contains extras.");
end
if sha256File(fullfile(outputDir, expected(1))) ~= ...
        chooseExpectedHash(expected(1), csvHash, summaryHash) || ...
        sha256File(fullfile(outputDir, expected(2))) ~= ...
        chooseExpectedHash(expected(2), csvHash, summaryHash)
    error("steady53:H2OutputFailed", ...
        "Published H2 output hashes differ from staged hashes.");
end
end

function hash = chooseExpectedHash(name, csvHash, summaryHash)
if name == "h2_property_diagnostics.csv"
    hash = csvHash;
else
    hash = summaryHash;
end
end

function moveDirectoryNoReplace(stagingDir, outputDir)
sourcePath = javaObject("java.io.File", char(stagingDir)).toPath();
targetPath = javaObject("java.io.File", char(outputDir)).toPath();
noReplaceOptions = javaArray("java.nio.file.CopyOption", 0);
try
    javaMethod("move", "java.nio.file.Files", ...
        sourcePath, targetPath, noReplaceOptions);
catch exception
    if isfolder(outputDir) || isfile(outputDir)
        collision = MException("steady53:H2OutputExists", ...
            "H2 publication refused to overwrite '%s'.", outputDir);
        collision = addCause(collision, exception);
        throw(collision);
    end
    failure = MException("steady53:H2OutputFailed", ...
        "Could not publish staged H2 output directory.");
    failure = addCause(failure, exception);
    throw(failure);
end
end

function cleanupStagingDirectory(stagingDir, expectedParent, expectedPrefix)
if ~isfolder(stagingDir)
    return
end
[actualParent, name, extension] = fileparts(stagingDir);
leaf = string(name) + string(extension);
if string(actualParent) == string(expectedParent) && ...
        startsWith(leaf, string(expectedPrefix)) && ...
        strlength(leaf) > strlength(string(expectedPrefix))
    rmdir(stagingDir, "s");
end
end

function cleanupPublishedDirectory(outputDir, expectedParent, expectedLeaf)
if ~isfolder(outputDir)
    return
end
[actualParent, name, extension] = fileparts(outputDir);
leaf = string(name) + string(extension);
if string(actualParent) == string(expectedParent) && leaf == expectedLeaf
    entries = dir(outputDir);
    names = sort(string({entries(~[entries.isdir]).name}));
    if all(ismember(names, ["h2_property_diagnostics.csv" "h2_summary.txt"]))
        rmdir(outputDir, "s");
    end
end
end

function pathValue = requireAbsolutePath(value, label)
if ~(isstring(value) || ischar(value)) || ...
        ~isscalar(string(value)) || ismissing(string(value)) || ...
        strlength(string(value)) == 0 || ~startsWith(string(value), filesep)
    error("steady53:H2InvalidPublishOptions", ...
        "%s must be an absolute path.", label);
end
pathValue = string(value);
end

function hash = sha256File(filePath)
[status, output] = system("shasum -a 256 " + shellQuote(filePath));
if status ~= 0
    error("steady53:H2OutputFailed", "Hash failed: %s", output);
end
parts = split(strtrim(output));
hash = lower(string(parts(1)));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end
