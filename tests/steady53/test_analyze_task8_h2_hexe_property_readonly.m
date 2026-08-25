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
    "densityRoots" "production" "thermoIdentity" "domainSweep" ...
    "hypothesisVerdicts"];
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
verifyEqual(testCase, analysis.sourceAudit.archiveTag, ...
    "archive/pre-restart-20260824");
verifyEqual(testCase, analysis.sourceAudit.archivePeeledCommit, ...
    "8f625c268c35a95c18a626305c1aa6a79ae2ace7");
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

function testFixedH2FormalOutputIsComplete(testCase)
outputDir = fullfile(testCase.TestData.root, "tmp", "steady53", ...
    "task8_root_cause", "h2", ...
    "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3");
verifyTrue(testCase, isfolder(outputDir));
entries = dir(outputDir);
names = sort(string({entries(~[entries.isdir]).name}));
verifyEqual(testCase, names, sort([ ...
    "h2_property_diagnostics.csv" "h2_summary.txt"]));
for name = names
    info = dir(fullfile(outputDir, name));
    verifyGreaterThan(testCase, info.bytes, 0);
end
diagnostics = readtable(fullfile(outputDir, ...
    "h2_property_diagnostics.csv"), "TextType", "string");
summary = string(fileread(fullfile(outputDir, "h2_summary.txt")));
verifyEqual(testCase, sum(diagnostics.section == "equationMap"), 11);
verifyEqual(testCase, sum(diagnostics.section == "hash" & ...
    ismember(diagnostics.name, ["final_steady_24a.slx" ...
    "HeXe_property_simulink.m" "hexe_compressor_lookup.mat" ...
    "radiator_table.mat" "turbine_table1.mat" "turbine_table2.mat" ...
    "fixedInputMat" "thesisPdf" "archivePeeledCommit"])), 9);
verifyEqual(testCase, sum(diagnostics.section == "scanContract"), 8);
verifyEqual(testCase, sum(diagnostics.section == "discontinuity" & ...
    contains(diagnostics.name, "gammaPoleAtCvZero")), 2);
verifyTrue(testCase, contains(summary, ...
    "fixedPressure.searched.gamma=1=searched:true,count:0"));
verifyTrue(testCase, contains(summary, ...
    "h1aLowEndPath.searched.dP/drho=0=searched:true,count:0"));
verifyTrue(testCase, contains(summary, ...
    "gammaPoleAtCvZeroNotGammaEqualsOneRoot"));
end

function testEquationMapMatchesReviewedPaperPagesAndActiveSource(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
verifyEqual(testCase, analysis.sourceAudit.reviewedPdfPages, [33 34 35]);
verifyEqual(testCase, analysis.sourceAudit.reviewedPrintedPages, [18 19 20]);

map = analysis.sourceAudit.equationMap;
verifyClass(testCase, map, "table");
verifyEqual(testCase, map.paperEquation, ...
    ["2.7"; "2.8"; "2.9"; "2.10"; "2.11"; "2.12"; ...
     "2.13"; "2.14"; "2.15"; "2.16"; "2.17"]);
verifyEqual(testCase, map.pdfPage, [33; 33; 33; 33; 34; 34; 34; 34; 34; 34; 34]);
verifyEqual(testCase, map.printedPage, [18; 18; 18; 18; 19; 19; 19; 19; 19; 19; 19]);
verifyEqual(testCase, map.sourceLineStart, [86; 50; 76; 71; 72; 74; 81; 79; 185; 175; 180]);
verifyEqual(testCase, map.sourceLineEnd, [98; 50; 76; 71; 73; 75; 83; 80; 194; 177; 182]);
verifyEqual(testCase, map.diagnosticPath, ...
    ["densityRoots"; "coefficients.mixtureMolarMass"; "coefficients.B"; ...
     "coefficients.B11"; "coefficients.B22"; "coefficients.B12"; ...
     "coefficients.C"; "coefficients.C111_C222"; "production.diagnostic.cpMass"; ...
     "derivatives.drhoHat_dT"; "production.diagnostic.cvMolar"]);

sourceLines = splitlines(string(fileread(fullfile(testCase.TestData.root, ...
    "HeXe_property_simulink.m"))));
verifyNotEmpty(testCase, regexp(sourceLines(71), 'B11\s*=', 'once'));
verifyNotEmpty(testCase, regexp(sourceLines(79), 'C111\s*=', 'once'));
verifyNotEmpty(testCase, regexp(sourceLines(185), 'B_1\s*=', 'once'));
verifyNotEmpty(testCase, regexp(sourceLines(175), 'a_rho\s*=', 'once'));
verifyNotEmpty(testCase, regexp(sourceLines(180), 'term1_cv\s*=', 'once'));
end

function testEveryEquationMapDiagnosticPathResolves(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
map = analysis.sourceAudit.equationMap;

for index = 1:height(map)
    diagnosticPath = map.diagnosticPath(index);
    verifyTrue(testCase, hasDotPath(analysis, diagnosticPath), ...
        sprintf("Equation %s has an unresolved diagnostic path: %s", ...
        map.paperEquation(index), diagnosticPath));
end
end

function testVirialCoefficientsAndAnalyticDerivativesAreComplete(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
coefficientNames = ["B11" "B22" "B12" "B" ...
    "C111" "C222" "C112" "C122" "C"];
verifyTrue(testCase, all(isfield(analysis.coefficients, coefficientNames)));
coefficientValues = cellfun(@(name) analysis.coefficients.(name), ...
    cellstr(coefficientNames));
verifyTrue(testCase, all(isfinite(coefficientValues)));
verifyEqual(testCase, analysis.coefficients.B, ...
    0.7172^2*analysis.coefficients.B11 + ...
    2*0.7172*(1-0.7172)*analysis.coefficients.B12 + ...
    (1-0.7172)^2*analysis.coefficients.B22, "RelTol", 5e-15);
verifyEqual(testCase, analysis.coefficients.C, ...
    0.7172^3*analysis.coefficients.C111 + ...
    3*0.7172^2*(1-0.7172)*analysis.coefficients.C112 + ...
    3*0.7172*(1-0.7172)^2*analysis.coefficients.C122 + ...
    (1-0.7172)^3*analysis.coefficients.C222, "RelTol", 5e-15);
verifyLessThan(testCase, abs(analysis.coefficients.C111AtZero), 1e-24);
verifyGreaterThan(testCase, analysis.coefficients.C111ZeroOffset_K, 0);
verifyLessThan(testCase, analysis.coefficients.C111ZeroOffset_K, 0.01);

baseNames = ["B11" "B22" "B12" "B" ...
    "C111" "C222" "C112" "C122" "C"];
firstNames = "d" + baseNames + "_dT";
secondNames = "d2" + baseNames + "_dT2";
verifyTrue(testCase, all(isfield(analysis.derivatives.analytic, ...
    [firstNames secondNames])));
for name = [firstNames secondNames]
    verifyTrue(testCase, isfinite(analysis.derivatives.analytic.(name)));
end
end

function testIndependentFiniteDifferencesRecordThreeStepsAndConvergence(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
fd = analysis.derivatives.finiteDifference;
verifyGreaterThanOrEqual(testCase, numel(fd.stepSizes_K), 3);
verifyEqual(testCase, size(fd.first.B, 1), numel(fd.stepSizes_K));
verifyEqual(testCase, size(fd.second.B, 1), numel(fd.stepSizes_K));
verifyEqual(testCase, size(fd.first.C, 1), numel(fd.stepSizes_K));
verifyEqual(testCase, size(fd.second.C, 1), numel(fd.stepSizes_K));
verifyTrue(testCase, all(isfinite(fd.first.B)) && all(isfinite(fd.second.B)));
verifyTrue(testCase, all(isfinite(fd.first.C)) && all(isfinite(fd.second.C)));
verifyTrue(testCase, all(isfield(fd.richardson, ...
    ["dB_dT" "d2B_dT2" "dC_dT" "d2C_dT2"])));
verifyTrue(testCase, all(isfield(fd.convergence, ...
    ["BFirst" "BSecond" "CFirst" "CSecond"])));
verifyLessThan(testCase, fd.convergence.BFirst.finalRelativeError, 1e-7);
verifyLessThan(testCase, fd.convergence.BSecond.finalRelativeError, 1e-5);
verifyLessThan(testCase, fd.convergence.CFirst.finalRelativeError, 2e-4);
verifyLessThan(testCase, fd.convergence.CSecond.finalRelativeError, 2e-3);
verifyTrue(testCase, fd.convergence.BFirst.success);
verifyTrue(testCase, fd.convergence.BSecond.success);
verifyTrue(testCase, fd.convergence.CFirst.success);
verifyTrue(testCase, fd.convergence.CSecond.success);
end

function testDensityCubicRecordsAllRootsAndProductionNewtonEvidence(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
density = analysis.densityRoots;
verifyEqual(testCase, numel(density.polynomialCoefficients), 4);
verifyEqual(testCase, numel(density.allRoots), 3);
verifyEqual(testCase, numel(density.isReal), 3);
verifyEqual(testCase, density.realRoots, density.allRoots(density.isReal));
verifyEqual(testCase, numel(density.polynomialResiduals), 3);
verifyEqual(testCase, numel(density.eosPressureResiduals_Pa), 3);
verifyEqual(testCase, numel(density.normalizedPolynomialResiduals), 3);
verifyEqual(testCase, numel(density.realRootDiagnostics), nnz(density.isReal));
verifyLessThan(testCase, max(density.normalizedPolynomialResiduals), 1e-14);
for index = 1:numel(density.realRootDiagnostics)
    item = density.realRootDiagnostics(index);
    verifyTrue(testCase, isfinite(item.dPdrho_Pa_m3_per_mol));
    verifyTrue(testCase, ismember(item.stabilitySign, ["positive" "zero" "negative"]));
end

newton = density.productionNewton;
verifyEqual(testCase, newton.initialGuess, density.P_RT, "RelTol", 1e-15);
verifyGreaterThanOrEqual(testCase, newton.iterations, 1);
verifyLessThanOrEqual(testCase, newton.iterations, 30);
verifyTrue(testCase, newton.converged);
verifyLessThan(testCase, abs(newton.rawPolynomialResidual), 1e-12);
verifyEqual(testCase, newton.clampedFinal, ...
    max(newton.rawFinal, newton.clampFloor), "RelTol", 1e-15);
verifyEqual(testCase, newton.clampChanged, ...
    newton.clampedFinal ~= newton.rawFinal);
end

function testDiagnosticProductionParityFailsClosedAndTask4IsComplete(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
[cpMass, gamma, rho] = HeXe_property_simulink( ...
    analysis.inputs.exceptionT_K, analysis.inputs.exceptionP_Pa);
verifyEqual(testCase, analysis.production.called.cpMass, cpMass, "AbsTol", 1e-10);
verifyEqual(testCase, analysis.production.called.gamma, gamma, "AbsTol", 1e-13);
verifyEqual(testCase, analysis.production.called.rho, rho, "AbsTol", 1e-13);
verifyEqual(testCase, analysis.production.diagnostic.cpMass, cpMass, "AbsTol", 1e-10);
verifyEqual(testCase, analysis.production.diagnostic.gamma, gamma, "AbsTol", 1e-13);
verifyEqual(testCase, analysis.production.diagnostic.rho, rho, "AbsTol", 1e-13);
verifyTrue(testCase, analysis.production.parity.allWithinTolerance);
verifyEqual(testCase, analysis.production.diagnostic.cvMolar, ...
    analysis.production.diagnostic.cpMolar / gamma, "AbsTol", 1e-12);

verifyEqual(testCase, analysis.domainSweep.status, "completedTask4");
verifyEqual(testCase, analysis.hypothesisVerdicts.status, "completedTask4");
literature = analysis.sourceAudit.originalLiterature;
verifyEqual(testCase, literature.status, "verifiedInTask4");
verifyEqual(testCase, literature.evidenceGrade, "✅");
verifyEqual(testCase, literature.paperNumber, "AIAA 2006-4154");
verifyEqual(testCase, literature.doi, "10.2514/6.2006-4154");
verifyTrue(testCase, all(literature.claimEvidenceGrade == "✅"));
end

function testThermodynamicIdentitiesSeparateConsistencyFromPhysicalDomain(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
thermo = analysis.thermoIdentity;

verifyEqual(testCase, thermo.status, "computedInTask3");
verifyEqual(testCase, thermo.classification, ...
    "calculatedConsequenceOfActiveSource");
verifyEqual(testCase, thermo.eq2_15.analyticCpMolar, ...
    analysis.production.diagnostic.cpMolar, "AbsTol", 1e-12);
verifyEqual(testCase, thermo.eq2_17.analyticCvMolar, ...
    analysis.production.diagnostic.cvMolar, "AbsTol", 1e-12);

enthalpy = thermo.enthalpyFiniteDifference;
verifyGreaterThanOrEqual(testCase, numel(enthalpy.stepSizes_K), 3);
verifyEqual(testCase, size(enthalpy.cpMolarEstimates), ...
    size(enthalpy.stepSizes_K));
verifyTrue(testCase, all(isfinite(enthalpy.cpMolarEstimates)));
verifyLessThan(testCase, enthalpy.finalRelativeError, 2e-5);

identity = thermo.eosIdentity;
verifyEqual(testCase, identity.lhsCpMinusCv_Molar, ...
    thermo.eq2_15.analyticCpMolar - thermo.eq2_17.analyticCvMolar, ...
    "AbsTol", 1e-12);
verifyEqual(testCase, identity.rhsMolar, ...
    analysis.inputs.exceptionT_K * identity.dP_dT_atRho_Pa_K * ...
    identity.minusDrhoHat_dT_atP_mol_m3_K / identity.rhoHat^2, ...
    "AbsTol", 1e-12);
verifyLessThan(testCase, identity.relativeError, 1e-12);
verifyEqual(testCase, thermo.gamma.analytic, ...
    thermo.eq2_15.analyticCpMolar / thermo.eq2_17.analyticCvMolar, ...
    "AbsTol", 1e-15);
verifyEqual(testCase, thermo.gamma.production, ...
    analysis.production.called.gamma, "AbsTol", 1e-13);

verifyTrue(testCase, thermo.formulaConsistency.cpVsEnthalpy);
verifyTrue(testCase, thermo.formulaConsistency.cpMinusCvIdentity);
verifyTrue(testCase, thermo.formulaConsistency.gammaParity);
verifyTrue(testCase, thermo.formulaConsistency.allSatisfied);
verifyFalse(testCase, thermo.physicalDomain.cpPositive);
verifyFalse(testCase, thermo.physicalDomain.cvPositive);
verifyFalse(testCase, thermo.physicalDomain.gammaGreaterThanOne);
verifyFalse(testCase, thermo.physicalDomain.allSatisfied);
end

function testHeatCapacityContributionsTraceAllThirdVirialMixedTerms(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
thermo = analysis.thermoIdentity;
contributions = thermo.contributions;

verifyTrue(testCase, all(isfield(contributions.cpMolar, ...
    ["ideal" "BExplicit" "CExplicit" "densityDerivativeB" ...
     "densityDerivativeC" "densityDerivativeTotal" "total"])));
verifyTrue(testCase, all(isfield(contributions.cvMolar, ...
    ["ideal" "B" "C" "total"])));
verifyEqual(testCase, contributions.cpMolar.densityDerivativeTotal, ...
    contributions.cpMolar.densityDerivativeB + ...
    contributions.cpMolar.densityDerivativeC, "AbsTol", 1e-12);
verifyEqual(testCase, contributions.cpMolar.total, ...
    contributions.cpMolar.ideal + contributions.cpMolar.BExplicit + ...
    contributions.cpMolar.CExplicit + ...
    contributions.cpMolar.densityDerivativeTotal, "AbsTol", 1e-12);
verifyEqual(testCase, contributions.cpMolar.total, ...
    thermo.eq2_15.analyticCpMolar, "AbsTol", 1e-12);
verifyEqual(testCase, contributions.cvMolar.total, ...
    contributions.cvMolar.ideal + contributions.cvMolar.B + ...
    contributions.cvMolar.C, "AbsTol", 1e-12);
verifyEqual(testCase, contributions.cvMolar.total, ...
    thermo.eq2_17.analyticCvMolar, "AbsTol", 1e-12);

components = contributions.thirdVirialComponents;
verifyClass(testCase, components, "table");
verifyEqual(testCase, components.name, ...
    ["C111"; "C222"; "C112"; "C122"]);
requiredColumns = ["mixtureWeight" "valueContribution" ...
    "firstDerivativeContribution" "secondDerivativeContribution" ...
    "cpExplicitMolar" "cpDensityDerivativeMolar" "cvMolar"];
verifyTrue(testCase, all(ismember(requiredColumns, ...
    string(components.Properties.VariableNames))));
for column = requiredColumns
    verifyTrue(testCase, all(isfinite(components.(column))));
end
verifyEqual(testCase, sum(components.valueContribution), ...
    analysis.coefficients.C, "AbsTol", 1e-24);
verifyEqual(testCase, sum(components.firstDerivativeContribution), ...
    analysis.derivatives.analytic.dC_dT, "AbsTol", 1e-24);
verifyEqual(testCase, sum(components.secondDerivativeContribution), ...
    analysis.derivatives.analytic.d2C_dT2, "AbsTol", 1e-24);
verifyEqual(testCase, sum(components.cpExplicitMolar), ...
    contributions.cpMolar.CExplicit, "AbsTol", 1e-12);
verifyEqual(testCase, sum(components.cpDensityDerivativeMolar), ...
    contributions.cpMolar.densityDerivativeC, "AbsTol", 1e-12);
verifyEqual(testCase, sum(components.cvMolar), ...
    contributions.cvMolar.C, "AbsTol", 1e-12);
end

function testTask4SweepsRefineEveryRequiredBoundary(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
sweep = analysis.domainSweep;

verifyEqual(testCase, sweep.status, "completedTask4");
verifyEqual(testCase, sweep.evidenceGrade, "✅");
verifyEqual(testCase, sweep.quantitiesSearched, ...
    ["cp=0" "cv=0" "gamma=1" "dP/drho=0"]);
verifyTrue(testCase, sweep.method.coarseGridOnlyFindsBrackets);
verifyEqual(testCase, sweep.method.rootSolver, "fzero");
verifyGreaterThanOrEqual(testCase, sweep.method.adaptiveLevels, 3);

for scanName = ["fixedPressure" "h1aLowEndPath"]
    scan = sweep.(scanName);
    verifyEqual(testCase, scan.quantitiesSearched, ...
        sweep.quantitiesSearched);
    verifyGreaterThan(testCase, numel(scan.coarseCoordinate), 2);
    verifyGreaterThan(testCase, numel(scan.adaptiveCoordinate), ...
        numel(scan.coarseCoordinate));
    verifyClass(testCase, scan.boundaries, "table");
    required = ["quantity" "bracketLeft" "bracketRight" ...
        "rootCoordinate" "T_K" "P_Pa" "residual" ...
        "leftValue" "rightValue" "leftState" "rightState"];
    verifyTrue(testCase, all(ismember(required, ...
        string(scan.boundaries.Properties.VariableNames))));
    verifyEqual(testCase, scan.boundaryCountByQuantity.quantity, ...
        sweep.quantitiesSearched(:));
    verifyEqual(testCase, scan.boundaryCountByQuantity.count, [1; 1; 0; 0]);
    verifyEqual(testCase, sum(scan.boundaryCountByQuantity.count), ...
        height(scan.boundaries));
    if ~isempty(scan.boundaries)
        verifyTrue(testCase, all(scan.boundaries.bracketLeft < ...
            scan.boundaries.rootCoordinate));
        verifyTrue(testCase, all(scan.boundaries.rootCoordinate < ...
            scan.boundaries.bracketRight));
        verifyTrue(testCase, all(abs(scan.boundaries.residual) <= ...
            scan.boundaries.residualTolerance));
        verifyTrue(testCase, all(scan.boundaries.leftState ~= ...
            scan.boundaries.rightState));
    end
    pole = scan.gammaPoleAtCvZero;
    verifyEqual(testCase, pole.classification, ...
        "gammaPoleAtCvZeroNotGammaEqualsOneRoot");
    verifyEqual(testCase, pole.cvBoundaryCount, 1);
    verifyEqual(testCase, pole.gammaEqualsOneBoundaryCount, 0);
    verifyFalse(testCase, pole.isGammaEqualsOneRoot);
    verifyTrue(testCase, pole.oppositeSignedOneSidedGamma);
    verifyTrue(testCase, all(isfinite([pole.leftGamma pole.rightGamma])));
end
end

function testC111ZeroAndDerivativeDiscontinuityAreIsolated(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
singularity = analysis.domainSweep.C111DerivativeDiscontinuity;

verifyEqual(testCase, singularity.classification, ...
    "C111ZeroAndMixedThirdVirialDerivativeDiscontinuity");
verifyEqual(testCase, singularity.rootT_K, ...
    analysis.coefficients.C111ZeroT_K, "AbsTol", 1e-11);
verifyLessThan(testCase, abs(singularity.C111Residual), 1e-24);
verifyGreaterThanOrEqual(testCase, numel(singularity.neighborhoodOffsets_K), 4);
verifyTrue(testCase, all(singularity.neighborhoodOffsets_K > 0));
verifyTrue(testCase, all(diff(singularity.neighborhoodOffsets_K) > 0));
verifyTrue(testCase, all(isfinite(singularity.leftCpMolar)));
verifyTrue(testCase, all(isfinite(singularity.rightCpMolar)));
verifyTrue(testCase, singularity.derivativeIsNonContinuous);
verifyGreaterThan(testCase, singularity.h1aLambda, 0);
verifyLessThan(testCase, singularity.h1aLambda, 1);
end

function testTask4HypothesisVerdictsAreEvidenceDrivenAndSeparated(testCase)
analysis = analyze_task8_h2_hexe_property_readonly();
verdicts = analysis.hypothesisVerdicts;

verifyEqual(testCase, verdicts.status, "completedTask4");
verifyEqual(testCase, verdicts.implementationError.evidenceGrade, "❌");
verifyFalse(testCase, verdicts.implementationError.supported);
verifyEqual(testCase, verdicts.densityRootError.evidenceGrade, "❌");
verifyFalse(testCase, verdicts.densityRootError.supported);
verifyEqual(testCase, ...
    verdicts.directPaperCorrelationNonphysical.evidenceGrade, "✅");
verifyTrue(testCase, verdicts.directPaperCorrelationNonphysical.supported);
verifyTrue(testCase, verdicts.directPaperCorrelationNonphysical.formulaConsistent);
verifyTrue(testCase, verdicts.directPaperCorrelationNonphysical.uniqueStableDensityRoot);
verifyFalse(testCase, verdicts.directPaperCorrelationNonphysical.physicalDomainSatisfied);
verifyEqual(testCase, verdicts.provenanceApplicability.status, ...
    "sourceFrameworkDiffersFromCurrentThesisFormulaUse");
verifyEqual(testCase, verdicts.provenanceApplicability.evidenceGrade, "✅");
verifyFalse(testCase, verdicts.authorizesRepair);
verifyEqual(testCase, verdicts.task8Status, "RED_NOT_COMPLETED");
verifyEqual(testCase, verdicts.h1aS2Status, "BLOCKED_BY_PROPERTY_DOMAIN");
end

function testOriginalLiteratureEvidenceKeepsDirectTextAndMetadataSeparate(testCase)
literature = analyze_task8_h2_hexe_property_readonly().sourceAudit.originalLiterature;
verifyEqual(testCase, literature.fullTextUrl, ...
    "https://www.researchgate.net/publication/268572975_Best_Estimates_of_Binary_Gas_Mixtures_Properties_for_Closed_Brayton_Cycle_Space_Applications");
verifyEqual(testCase, literature.officialMetadataUrl, ...
    "https://isnps.unm.edu/publications/529/");
verifyEqual(testCase, literature.fullTextEvidenceGrade, "✅");
verifyEqual(testCase, literature.officialMetadataEvidenceGrade, "✅");
verifyEqual(testCase, literature.claims, [ ...
    "Eq.(11) third-order Virial fit is stated for Ne/Ar/Kr"
    "The source states the third Virial coefficient for He can be neglected"
    "40 g/mol He-Xe at T>400 K and P<2 MPa has under 1 percent ideal-gas-property error"]);
verifyEqual(testCase, literature.officialMetadataRelationship, ...
    "related2008JournalRecordNotExactAIAAConferenceMetadata");
verifyTrue(testCase, literature.currentThesisFormulaKeptSeparate);
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
options.archiveTag = "archive/pre-restart-20260824";
options.expectedArchivePeeledCommit = ...
    "8f625c268c35a95c18a626305c1aa6a79ae2ace7";
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
