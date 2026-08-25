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
    assert(analysis.sourceAudit.archiveTag == ...
        "archive/pre-restart-20260824");
    assert(analysis.sourceAudit.archivePeeledCommit == ...
        "8f625c268c35a95c18a626305c1aa6a79ae2ace7");
    assert(isequaln(analysis.sourceAudit.protectedAssetHashesBefore, ...
        analysis.sourceAudit.protectedAssetHashesAfter));
    assertProtectedHashes(analysis.sourceAudit.protectedAssetHashesBefore);
    assertEquationMap(analysis);
    assert(analysis.production.parity.allWithinTolerance);
    assert(analysis.thermoIdentity.formulaConsistency.allSatisfied);
    assert(~analysis.thermoIdentity.physicalDomain.allSatisfied);
    assert(analysis.domainSweep.status == "completedTask4");
    assert(analysis.domainSweep.evidenceGrade == "✅");
    assertSingularity(analysis);
    expectedQuantities = ["cp=0" "cv=0" "gamma=1" "dP/drho=0"];
    assert(isequal(analysis.domainSweep.quantitiesSearched, ...
        expectedQuantities));
    assertValidScan(analysis.domainSweep.fixedPressure, ...
        "fixedPressure", expectedQuantities);
    assertValidScan(analysis.domainSweep.h1aLowEndPath, ...
        "h1aLowEndPath", expectedQuantities);
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

function assertProtectedHashes(hashTable)
assert(istable(hashTable) && height(hashTable) == 8 && ...
    isequal(string(hashTable.Properties.VariableNames), ["path" "sha256"]));
suffixes = [ ...
    "final_steady_24a.slx"
    "HeXe_property_simulink.m"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"
    "tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat"
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"];
expected = [ ...
    "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d"
    "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2"
    "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579"
    "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304"
    "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d"
    "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33"
    "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b"
    "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a"];
for index = 1:numel(suffixes)
    row = endsWith(string(hashTable.path), suffixes(index));
    assert(nnz(row) == 1 && hashTable.sha256(row) == expected(index));
end
end

function assertEquationMap(analysis)
map = analysis.sourceAudit.equationMap;
required = ["paperEquation" "pdfPage" "printedPage" ...
    "sourceLineStart" "sourceLineEnd" "diagnosticPath"];
assert(istable(map) && height(map) == 11 && ...
    all(ismember(required, string(map.Properties.VariableNames))));
assert(isequal(map.paperEquation, ["2.7"; "2.8"; "2.9"; "2.10"; ...
    "2.11"; "2.12"; "2.13"; "2.14"; "2.15"; "2.16"; "2.17"]));
assert(isequal(map.pdfPage, [33; 33; 33; 33; 34; 34; 34; 34; 34; 34; 34]));
assert(isequal(map.printedPage, ...
    [18; 18; 18; 18; 19; 19; 19; 19; 19; 19; 19]));
assert(isequal(map.sourceLineStart, ...
    [86; 50; 76; 71; 72; 74; 81; 79; 185; 175; 180]));
assert(isequal(map.sourceLineEnd, ...
    [98; 50; 76; 71; 73; 75; 83; 80; 194; 177; 182]));
assert(isequal(map.diagnosticPath, [ ...
    "densityRoots"; "coefficients.mixtureMolarMass"; ...
    "coefficients.B"; "coefficients.B11"; "coefficients.B22"; ...
    "coefficients.B12"; "coefficients.C"; ...
    "coefficients.C111_C222"; "production.diagnostic.cpMass"; ...
    "derivatives.drhoHat_dT"; "production.diagnostic.cvMolar"]));
sourceText = fileread(analysis.sourceAudit.resolvedPropertyPath);
sourceLineCount = numel(splitlines(string(sourceText)));
assert(all(isfinite(map.sourceLineStart)) && ...
    all(mod(map.sourceLineStart, 1) == 0) && ...
    all(map.sourceLineStart >= 1) && ...
    all(map.sourceLineStart <= map.sourceLineEnd) && ...
    all(map.sourceLineEnd <= sourceLineCount));
assert(all(strlength(map.diagnosticPath) > 0));
for index = 1:height(map)
    assert(hasDotPath(analysis, map.diagnosticPath(index)));
end
end

function assertSingularity(analysis)
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;
required = ["classification" "rootT_K" "C111Residual" ...
    "neighborhoodOffsets_K" "leftCpMolar" "rightCpMolar" ...
    "leftClassification" "rightClassification" ...
    "derivativeIsNonContinuous" "boundaryTreatment"];
assert(isstruct(singularity) && isscalar(singularity) && ...
    all(isfield(singularity, required)));
assert(singularity.classification == ...
    "C111ZeroAndMixedThirdVirialDerivativeDiscontinuity");
approvedRootT_K = 992.38240920882117;
rootTolerance_K = 1e-12;
residualTolerance = 1e-24;
assert(isfinite(singularity.rootT_K) && ...
    isfield(analysis.coefficients, "C111ZeroT_K") && ...
    isfield(analysis.coefficients, "C111AtZero") && ...
    abs(singularity.rootT_K - approvedRootT_K) <= rootTolerance_K && ...
    abs(singularity.rootT_K - analysis.coefficients.C111ZeroT_K) <= ...
        rootTolerance_K && ...
    abs(singularity.C111Residual - analysis.coefficients.C111AtZero) <= ...
        residualTolerance && ...
    abs(singularity.C111Residual) <= residualTolerance);
offsets = singularity.neighborhoodOffsets_K;
assert(iscolumn(offsets) && numel(offsets) >= 4 && ...
    all(isfinite(offsets)) && all(offsets > 0) && all(diff(offsets) > 0));
assert(isequal(size(singularity.leftCpMolar), size(offsets)) && ...
    isequal(size(singularity.rightCpMolar), size(offsets)) && ...
    all(isfinite(singularity.leftCpMolar)) && ...
    all(isfinite(singularity.rightCpMolar)));
assert(isequal(singularity.leftClassification, ...
    arrayfun(@signLabelLocal, singularity.leftCpMolar)) && ...
    isequal(singularity.rightClassification, ...
    arrayfun(@signLabelLocal, singularity.rightCpMolar)));
assert(singularity.derivativeIsNonContinuous && ...
    singularity.boundaryTreatment == ...
    "isolatedFromRootBracketsAndRecordedWithOneSidedAdaptiveStates");
end

function assertValidScan(scan, expectedPathName, expectedQuantities)
requiredColumns = ["quantity" "bracketLeft" "bracketRight" ...
    "rootCoordinate" "T_K" "P_Pa" "residual" ...
    "residualTolerance" "leftValue" "rightValue" ...
    "leftState" "rightState"];
assert(isstruct(scan) && isscalar(scan) && ...
    scan.pathName == expectedPathName && ...
    isequal(scan.quantitiesSearched, expectedQuantities) && ...
    istable(scan.boundaries) && height(scan.boundaries) == 2);
assert(all(ismember(requiredColumns, ...
    string(scan.boundaries.Properties.VariableNames))));
assert(isequal(scan.boundaryCountByQuantity.quantity, ...
    expectedQuantities(:)) && ...
    isequal(scan.boundaryCountByQuantity.count, [1; 1; 0; 0]));
assert(sum(scan.boundaries.quantity == "cp=0") == 1 && ...
    sum(scan.boundaries.quantity == "cv=0") == 1 && ...
    sum(scan.boundaries.quantity == "gamma=1") == 0 && ...
    sum(scan.boundaries.quantity == "dP/drho=0") == 0);
assert(all(scan.boundaries.bracketLeft < scan.boundaries.rootCoordinate));
assert(all(scan.boundaries.rootCoordinate < scan.boundaries.bracketRight));
assert(all(abs(scan.boundaries.residual) <= ...
    scan.boundaries.residualTolerance));
assert(all(scan.boundaries.leftState ~= scan.boundaries.rightState));
assert(all(scan.boundaries.leftState == ...
    arrayfun(@signLabelLocal, scan.boundaries.leftValue)) && ...
    all(scan.boundaries.rightState == ...
    arrayfun(@signLabelLocal, scan.boundaries.rightValue)));
pole = scan.gammaPoleAtCvZero;
assert(isstruct(pole) && isscalar(pole) && ...
    pole.classification == "gammaPoleAtCvZeroNotGammaEqualsOneRoot" && ...
    pole.cvBoundaryCount == 1 && pole.gammaEqualsOneBoundaryCount == 0 && ...
    ~pole.isGammaEqualsOneRoot && pole.oppositeSignedOneSidedGamma && ...
    all(isfinite([pole.leftGamma pole.rightGamma])) && ...
    sign(pole.leftGamma) ~= sign(pole.rightGamma));
cvRoot = scan.boundaries(scan.boundaries.quantity == "cv=0", :);
assert(abs(pole.cvRootCoordinate - cvRoot.rootCoordinate) <= 1e-12 && ...
    abs(pole.cvRootT_K - cvRoot.T_K) <= 1e-12 && ...
    abs(pole.cvRootP_Pa - cvRoot.P_Pa) <= 1e-6);
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
protected = analysis.sourceAudit.protectedAssetHashesBefore;
hashNames = [ ...
    "final_steady_24a.slx"
    "HeXe_property_simulink.m"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"
    "fixedInputMat"
    "thesisPdf"];
hashSuffixes = [ ...
    "final_steady_24a.slx"
    "HeXe_property_simulink.m"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"
    "tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat"
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"];
for index = 1:numel(hashNames)
    add("hash", hashNames(index), ...
        protectedHashBySuffix(protected, hashSuffixes(index)), ...
        "SHA-256", "✅", "complete protected input hash contract");
end
add("hash", "archivePeeledCommit", ...
    analysis.sourceAudit.archivePeeledCommit, "git commit", "✅", ...
    analysis.sourceAudit.archiveTag);

map = analysis.sourceAudit.equationMap;
for index = 1:height(map)
    mapping = compose("pdfPage=%d;printedPage=%d;sourceLine=%d-%d;diagnosticPath=%s", ...
        map.pdfPage(index), map.printedPage(index), ...
        map.sourceLineStart(index), map.sourceLineEnd(index), ...
        map.diagnosticPath(index));
    add("equationMap", "Eq" + map.paperEquation(index), mapping, "", ...
        "✅", analysis.sourceAudit.resolvedPropertyPath);
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
    scan = analysis.domainSweep.(scanName);
    boundaries = scan.boundaries;
    for index = 1:height(scan.boundaryCountByQuantity)
        quantity = scan.boundaryCountByQuantity.quantity(index);
        count = scan.boundaryCountByQuantity.count(index);
        if count > 0
            status = "root";
        else
            status = "noRoot";
        end
        add("scanContract", scanName + ".searched." + quantity, ...
            "searched=true;count=" + count + ";status=" + status, ...
            "", "✅", "adaptive scan completeness contract");
    end
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
        add("boundary", prefix + ".rootT_K", compose("%.17g", ...
            boundaries.T_K(index)), "K", "✅", "adaptive fzero root");
        add("boundary", prefix + ".rootP_Pa", compose("%.17g", ...
            boundaries.P_Pa(index)), "Pa", "✅", "adaptive fzero root");
        add("boundary", prefix + ".left", compose("value=%.17g;state=%s", ...
            boundaries.leftValue(index), boundaries.leftState(index)), ...
            "quantity units", "✅", "one-sided bracket state");
        add("boundary", prefix + ".right", compose("value=%.17g;state=%s", ...
            boundaries.rightValue(index), boundaries.rightState(index)), ...
            "quantity units", "✅", "one-sided bracket state");
    end
    pole = scan.gammaPoleAtCvZero;
    add("discontinuity", scanName + ".gammaPoleAtCvZero", ...
        pole.classification + ";cvCount=" + pole.cvBoundaryCount + ...
        ";gammaEqualsOneCount=" + pole.gammaEqualsOneBoundaryCount + ...
        ";isGammaEqualsOneRoot=false;leftGamma=" + ...
        compose("%.17g", pole.leftGamma) + ";rightGamma=" + ...
        compose("%.17g", pole.rightGamma), "", "✅", ...
        "cv=0 pole classified separately from gamma=1 roots");
end
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;
add("boundary", "C111ZeroT", compose("%.17g", singularity.rootT_K), ...
    "K", "✅", "adaptive C111 root and one-sided states");
add("boundary", "C111Residual", compose("%.17g", ...
    singularity.C111Residual), "m6/mol2", "✅", "C111 correlation");
add("discontinuity", "C111.oneSidedClassification", ...
    singularity.classification + ";treatment=" + ...
    singularity.boundaryTreatment, "", "✅", ...
    "mixed third-Virial derivative discontinuity");
add("discontinuity", "C111.neighborhoodOffsets_K", ...
    formatNumericVector(singularity.neighborhoodOffsets_K), "K", "✅", ...
    "adaptive one-sided offsets");
add("discontinuity", "C111.leftCpMolar", ...
    formatNumericVector(singularity.leftCpMolar), "J/(mol K)", "✅", ...
    strjoin(singularity.leftClassification, ","));
add("discontinuity", "C111.rightCpMolar", ...
    formatNumericVector(singularity.rightCpMolar), "J/(mol K)", "✅", ...
    strjoin(singularity.rightClassification, ","));

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
lines = [lines; buildCompletenessSummaryLines(analysis)];
text = strjoin(lines, newline) + newline;
end

function lines = buildCompletenessSummaryLines(analysis)
protected = analysis.sourceAudit.protectedAssetHashesBefore;
names = [ ...
    "final_steady_24a.slx"
    "HeXe_property_simulink.m"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"
    "fixedInputMat"
    "thesisPdf"];
suffixes = [ ...
    "final_steady_24a.slx"
    "HeXe_property_simulink.m"
    "hexe_compressor_lookup.mat"
    "radiator_table.mat"
    "turbine_table1.mat"
    "turbine_table2.mat"
    "tmp/steady53/task8/run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3/nominal_500_report.mat"
    "空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf"];
lines = strings(0, 1);
for index = 1:numel(names)
    lines(end + 1, 1) = names(index) + "Sha256=" + ...
        protectedHashBySuffix(protected, suffixes(index)); %#ok<AGROW>
end
lines(end + 1, 1) = "archiveTag=" + analysis.sourceAudit.archiveTag;
lines(end + 1, 1) = "archivePeeledCommit=" + ...
    analysis.sourceAudit.archivePeeledCommit;

map = analysis.sourceAudit.equationMap;
for index = 1:height(map)
    lines(end + 1, 1) = "Eq" + map.paperEquation(index) + ":" + ...
        compose("pdfPage=%d,printedPage=%d,sourceLine=%d-%d,diagnosticPath=%s", ...
        map.pdfPage(index), map.printedPage(index), ...
        map.sourceLineStart(index), map.sourceLineEnd(index), ...
        map.diagnosticPath(index)); %#ok<AGROW>
end

for scanName = ["fixedPressure" "h1aLowEndPath"]
    scan = analysis.domainSweep.(scanName);
    for index = 1:height(scan.boundaryCountByQuantity)
        lines(end + 1, 1) = scanName + ".searched." + ...
            scan.boundaryCountByQuantity.quantity(index) + ...
            "=searched:true,count:" + ...
            scan.boundaryCountByQuantity.count(index); %#ok<AGROW>
    end
    pole = scan.gammaPoleAtCvZero;
    lines(end + 1, 1) = scanName + ".gammaPoleAtCvZero=" + ...
        pole.classification + ",isGammaEqualsOneRoot:false,leftGamma:" + ...
        compose("%.17g", pole.leftGamma) + ",rightGamma:" + ...
        compose("%.17g", pole.rightGamma); %#ok<AGROW>
end
fixed = analysis.domainSweep.fixedPressure;
path = analysis.domainSweep.h1aLowEndPath;
lines(end + 1, 1) = compose("fixedPressure.temperatureRange_K=[%.17g,%.17g]", ...
    fixed.temperatureRange_K(1), fixed.temperatureRange_K(2));
lines(end + 1, 1) = compose("h1aLowEndPath.lambdaRange=[%.17g,%.17g]", ...
    path.lambdaRange(1), path.lambdaRange(2));
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;
lines(end + 1, 1) = "C111.oneSidedClassification=" + ...
    singularity.classification + ",left=" + ...
    strjoin(singularity.leftClassification, ",") + ",right=" + ...
    strjoin(singularity.rightClassification, ",");
lines(end + 1, 1) = "C111.neighborhoodOffsets_K=" + ...
    formatNumericVector(singularity.neighborhoodOffsets_K);
lines(end + 1, 1) = "C111.leftCpMolar=" + ...
    formatNumericVector(singularity.leftCpMolar);
lines(end + 1, 1) = "C111.rightCpMolar=" + ...
    formatNumericVector(singularity.rightCpMolar);
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

function exists = hasDotPath(value, pathValue)
parts = split(string(pathValue), ".");
exists = true;
for index = 1:numel(parts)
    if ~isstruct(value) || ~isscalar(value) || ...
            ~isfield(value, parts(index))
        exists = false;
        return
    end
    value = value.(parts(index));
end
end

function label = signLabelLocal(value)
if value > 0
    label = "positive";
elseif value < 0
    label = "negative";
else
    label = "zero";
end
end

function hash = protectedHashBySuffix(hashTable, suffix)
row = endsWith(string(hashTable.path), string(suffix));
if nnz(row) ~= 1
    error("steady53:H2InvalidEvidence", ...
        "Protected hash suffix is missing or duplicated: '%s'.", suffix);
end
hash = hashTable.sha256(row);
end

function value = formatNumericVector(values)
value = "[" + strjoin(compose("%.17g", values(:)'), ",") + "]";
end
