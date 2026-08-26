function published = publish_task8_h2a_evidence(analysis, options)
%PUBLISH_TASK8_H2A_EVIDENCE Atomically publishes approved H2a evidence only.
%   This publisher consumes an already-computed H2a analysis.  It never loads,
%   simulates, or modifies a model or source asset.

root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
config = defaultConfig(root);
if nargin >= 2
    config = applyTestOnlyOptions(config, options);
end
validateEvidence(analysis);
if isfolder(config.outputDir) || isfile(config.outputDir)
    error("steady53:H2aOutputExists", ...
        "H2a publication refuses to overwrite '%s'.", config.outputDir);
end
[csvHash, summaryHash] = writeOutputs(config, analysis);
published = struct("outputDir", config.outputDir, "csvSha256", csvHash, ...
    "summarySha256", summaryHash);
end

function config = defaultConfig(root)
runId = "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3";
config = struct("testOnly", false, "outputDir", string(fullfile(root, ...
    "tmp", "steady53", "task8_root_cause", "h2a", runId)), ...
    "outputFailureHook", @(~, ~, ~) []);
end

function config = applyTestOnlyOptions(config, options)
allowed = ["testOnly" "outputDir" "outputFailureHook"];
if ~isstruct(options) || ~isscalar(options) || ~isequal(sort(string(fieldnames(options))), ...
        sort(allowed(:))) || ~isfield(options, "testOnly") || ...
        ~isequal(options.testOnly, true) || ...
        ~(isstring(options.outputDir) || ischar(options.outputDir)) || ...
        ~isscalar(string(options.outputDir)) || ...
        ~startsWith(string(options.outputDir), filesep) || ...
        ~isa(options.outputFailureHook, "function_handle")
    error("steady53:H2aInvalidPublishOptions", ...
        "Test-only publication options must provide the complete contract.");
end
config.testOnly = true;
config.outputDir = string(options.outputDir);
config.outputFailureHook = options.outputFailureHook;
end

function validateEvidence(analysis)
requireStruct(analysis, ["inputs" "sourceAudit" "approval" "baselineParity" ...
    "exceptionPoint" "fixedPressureSweep" "h1aPathSweep" ...
    "counterfactualVerdict"]);
require(analysis.inputs.runId == "run_1787582761047_bb4aa60600cc4d9e9cc15077c6f435d3" && ...
    analysis.inputs.exceptionT_K == 992.38742737169468 && ...
    analysis.inputs.exceptionP_Pa == 1007910.8613125964, "fixed input identity");
require(analysis.approval.scheme == "A" && analysis.approval.variant == ...
    "ignoreHePureThirdVirialBeforeCurrentMixingRule" && ...
    analysis.approval.pureHeliumThirdVirialTerm == "C111" && ...
    analysis.approval.pureHeliumThirdVirialTreatment == "setToZero" && ...
    analysis.approval.treatmentStage == "beforeCurrentMixingRule" && ...
    analysis.approval.currentMixingRule == "unchanged" && ...
    analysis.approval.allOtherPropertyTerms == "unchanged" && ...
    ~analysis.approval.authorizesRepair && ~analysis.approval.loadsOrSimulatesSlx && ...
    ~analysis.approval.publishesArtifacts, "approved read-only variant");
validateSourceAudit(analysis.sourceAudit);
validateParity(analysis.baselineParity);
validateException(analysis.exceptionPoint);
validateSweep(analysis.fixedPressureSweep, "fixedPressureSweep");
validateSweep(analysis.h1aPathSweep, "h1aPathSweep");
validatePathParityAgainstSweeps(analysis);
validateCanonicalDerivedEvidence(analysis);
require(analysis.counterfactualVerdict.status == "notComputedInTask3" && ...
    analysis.counterfactualVerdict.evidenceGrade == "❓", ...
    "counterfactual verdict boundary");
end

function validateSourceAudit(audit)
requireStruct(audit, ["modelSha256" "propertySha256" "compressorMatSha256" ...
    "radiatorMatSha256" "turbine1MatSha256" "turbine2MatSha256" ...
    "inputMatSha256" "thesisPdfSha256" "approvedH2CsvSha256" ...
    "approvedH2TxtSha256" "archiveTag" "archivePeeledCommit" ...
    "protectedAssetHashesBefore" "protectedAssetHashesAfter"]);
expected = struct( ...
    "modelSha256", "5423af38d6bbfc7730529475a6c4d046ef1386ec56782ba465c87dfae82cbf5d", ...
    "propertySha256", "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2", ...
    "compressorMatSha256", "f9c85bc1ae831333fac5f868f15a6f82ea1c1716ee17f23dfb301f4618c9f579", ...
    "radiatorMatSha256", "3f6e8a08f6ec9253b84d07f8eff11d2b093f785bafcfde515f2c6af4ec263304", ...
    "turbine1MatSha256", "10e72638374c530e2032d9bfe39b060d4181b0467bf69e03196efa0b90c4971d", ...
    "turbine2MatSha256", "cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33", ...
    "inputMatSha256", "4ea018c7be06c5e577f107970dc2bf549924bf7a9a2989a89bcf1be76e98472b", ...
    "thesisPdfSha256", "983bfc23712221f30202a47875cbe34c9559edf79b9c332aa20931b6075e4e7a", ...
    "approvedH2CsvSha256", "b2998bdafd96cdd49d9fa4ff621dc586add229dd525a9d0d79a7c22fc71ee9d6", ...
    "approvedH2TxtSha256", "1fa29cebd816d891fecddfa8c54863d1f672f44a8793cb6e32cf3084241f9799");
names = string(fieldnames(expected));
for name = names.'
    require(string(audit.(name)) == string(expected.(name)), "protected source hash");
end
require(isequal(string(audit.archiveTag), "archive/pre-restart-20260824") && ...
    isequal(string(audit.archivePeeledCommit), "8f625c268c35a95c18a626305c1aa6a79ae2ace7"), ...
    "archive identity");
require(isequaln(audit.protectedAssetHashesBefore, ...
    audit.protectedAssetHashesAfter), "protected before/after identity");
end

function validateParity(parity)
requireStruct(parity, ["status" "evidenceGrade" "runIdMatches" ...
    "exceptionPointMatches" "protectedAssetsUnchanged" "allSatisfied" ...
    "pointAllSatisfied" "pathAllSatisfied" "table" "pathTable"]);
require(parity.status == "verifiedReadOnlyAgainstApprovedH2" && ...
    parity.evidenceGrade == "✅" && parity.runIdMatches && ...
    parity.exceptionPointMatches && parity.protectedAssetsUnchanged, ...
    "baseline parity identity");
requiredPoint = ["B11" "B22" "B12" "B" "C111" "C222" "C112" "C122" "C" ...
    "dB_dT" "d2B_dT2" "dC_dT" "d2C_dT2" "eosRoot1" "eosRoot2" ...
    "eosRoot3" "stablePositiveRealRootCount" "newtonRawFinal" ...
    "newtonClampedFinal" "newtonClampChanged" "rho" "cpMolar" "cvMolar" ...
    "cpMass" "gamma" "cp.ideal" "cp.BExplicit" "cp.CExplicit" ...
    "cp.densityDerivativeB" "cp.densityDerivativeC" ...
    "cp.densityDerivativeTotal" "cp.total" "cv.ideal" "cv.B" "cv.C" "cv.total"];
point = parity.table;
require(istable(point) && isequal(string(point.Properties.VariableNames), ...
    ["name" "h2Value" "h2aBaselineValue" "absoluteError" "tolerance" "pass"]), ...
    "point parity columns");
validateExactNameSet(point.name, requiredPoint, "point parity names");
expectedTolerance = pointParityTolerances(point.name, point.h2Value);
expectedError = abs(point.h2Value - point.h2aBaselineValue);
expectedPass = expectedError <= expectedTolerance;
require(all(isfinite(point.h2Value)) && all(isfinite(point.h2aBaselineValue)) && ...
    isequaln(point.absoluteError, expectedError) && ...
    isequaln(point.tolerance, expectedTolerance) && ...
    isequal(point.pass, expectedPass) && all(expectedPass), "point parity arithmetic");

path = parity.pathTable;
requiredPath = ["fixedPressure.cp=0" "fixedPressure.cv=0" ...
    "h1aPath.cp=0" "h1aPath.cv=0"];
require(istable(path) && isequal(string(path.Properties.VariableNames), ...
    ["name" "approvedValue" "h2Value" "h2aBaselineValue" ...
    "absoluteError" "tolerance" "pass"]), "path parity columns");
validateExactNameSet(path.name, requiredPath, "path parity names");
[~, order] = ismember(path.name, requiredPath);
approved = [992.3980970081318 992.40367034763892 ...
    0.61427357048046893 0.61426702062376992];
tolerances = [1e-8 1e-8 1e-10 1e-10];
expectedApproved = approved(order).';
expectedTolerance = tolerances(order).';
expectedError = max([abs(path.h2Value - expectedApproved), ...
    abs(path.h2aBaselineValue - expectedApproved), ...
    abs(path.h2aBaselineValue - path.h2Value)], [], 2);
expectedPass = expectedError <= expectedTolerance;
require(isequaln(path.approvedValue, expectedApproved) && ...
    all(isfinite(path.h2Value)) && all(isfinite(path.h2aBaselineValue)) && ...
    isequaln(path.absoluteError, expectedError) && ...
    isequaln(path.tolerance, expectedTolerance) && ...
    isequal(path.pass, expectedPass) && all(expectedPass), "path parity arithmetic");
require(parity.pointAllSatisfied == all(point.pass) && ...
    parity.pathAllSatisfied == all(path.pass) && ...
    parity.allSatisfied == (all(point.pass) && all(path.pass)), ...
    "baseline parity status");
end

function validateExactNameSet(actual, expected, label)
actual = string(actual(:));
expected = string(expected(:));
require(numel(actual) == numel(expected) && numel(unique(actual)) == numel(actual) && ...
    isequal(sort(actual), sort(expected)), label);
end

function tolerance = pointParityTolerances(names, h2Values)
tolerance = max(1e-12, 1e-10*abs(h2Values));
microNames = ["B11" "B22" "B12" "B" "C111" "C222" "C112" "C122" ...
    "C" "dB_dT" "d2B_dT2" "dC_dT" "d2C_dT2"];
micro = ismember(names, microNames);
tolerance(micro) = max(1e-30, 1e-8*abs(h2Values(micro)));
tolerance(names == "gamma") = 1e-13;
tolerance(ismember(names, ["stablePositiveRealRootCount" ...
    "newtonClampChanged"])) = 0;
end

function validateException(point)
requireStruct(point, ["status" "baseline" "counterfactual" "singleVariableGate"]);
require(point.status == "completed", "exception point status");
base = point.baseline;
cf = point.counterfactual;
require(base.variant == "baseline" && cf.variant == "ignoreHePureThirdVirial", ...
    "point branch identity");
zeroNames = ["C111" "C112" "C122" "dC111_dT" "dC112_dT" "dC122_dT" ...
    "d2C111_dT2" "d2C112_dT2" "d2C122_dT2"];
for name = zeroNames
    require(isfield(cf, name) && cf.(name) == 0, "counterfactual C component");
end
gate = point.singleVariableGate;
requireStruct(gate, ["allSatisfied" "invariants"]);
required = ["constants" "B11" "B22" "B12" "B" "dB_dT" "d2B_dT2" ...
    "C222" "dC222_dT" "d2C222_dT2" "eosForm" "newtonInitialGuess" ...
    "newtonIterations" "clampRule" "tolerances" "T_K" "P_Pa"];
validateExactNameSet(gate.invariants.name, required, "single-variable invariant names");
commonFields = ["constants" "B11" "B22" "B12" "B" "dB_dT" "d2B_dT2" ...
    "C222" "dC222_dT" "d2C222_dT2" "eosForm" "newtonInitialGuess" ...
    "newtonIterations" "clampRule" "tolerances" "T_K" "P_Pa"];
actualPass = false(numel(required), 1);
for index = 1:numel(required)
    actualPass(index) = isequaln(base.(required(index)), cf.(required(index)));
end
[~, gateOrder] = ismember(gate.invariants.name, required);
require(isequal(gate.invariants.pass, actualPass(gateOrder)) && ...
    gate.allSatisfied == all(actualPass) && all(actualPass), ...
    "single-variable underlying invariants");
for name = commonFields
    require(isequaln(base.(name), cf.(name)), "single-variable common field");
end
require(base.eosForm == "P=rho*R*T*(1+B*rho+C*rho^2)" && ...
    base.productionNewton.maximumIterations == 30 && ...
    base.clampRule == "rho=max(rawNewton,0.9*P_RT)", "EOS/Newton/clamp identity");
require(cf.C == cf.constants.xXe^3*cf.C222 && ...
    cf.dC_dT == cf.constants.xXe^3*cf.dC222_dT && ...
    cf.d2C_dT2 == cf.constants.xXe^3*cf.d2C222_dT2, ...
    "Scheme A current mixing result");
require(base.contributions.cpMolar.total == base.cpMolar && ...
    cf.contributions.cpMolar.total == cf.cpMolar && ...
    base.contributions.cvMolar.total == base.cvMolar && ...
    cf.contributions.cvMolar.total == cf.cvMolar && ...
    base.gamma == base.cpMolar/base.cvMolar && ...
    cf.gamma == cf.cpMolar/cf.cvMolar, "point thermodynamic closure");
validatePointDensityEvidence(base);
validatePointDensityEvidence(cf);
end

function validatePointDensityEvidence(point)
k = point.constants;
P_RT = point.P_Pa/(k.R0*point.T_K);
coefficients = [point.C point.B 1 -P_RT];
allRoots = roots(coefficients);
residual = polyval(coefficients, allRoots);
scale = abs(point.C)*abs(allRoots).^3 + abs(point.B)*abs(allRoots).^2 + ...
    abs(allRoots) + abs(P_RT);
slopes = k.R0*point.T_K*(1 + 2*point.B*allRoots + 3*point.C*allRoots.^2);
isReal = abs(imag(allRoots)) <= point.tolerances.realRoot*max(1, abs(allRoots));
stableCount = nnz(isReal & real(allRoots) > 0 & real(slopes) > 0);
expectedEos = struct("polynomialCoefficients", coefficients, ...
    "allRoots", allRoots, "scaledResidual", abs(residual)./scale, ...
    "dPdrho", slopes, "stablePositiveRealRootCount", stableCount);
require(isequaln(point.eos, expectedEos), "EOS coefficient/root closure");

rho = P_RT;
converged = false;
lastDelta = NaN;
for iteration = 1:point.tolerances.newtonIterations
    f = polyval(coefficients, rho);
    derivative = 3*point.C*rho^2 + 2*point.B*rho + 1;
    lastDelta = f/derivative;
    rho = rho - lastDelta;
    if abs(lastDelta) < point.tolerances.newtonDelta
        converged = true;
        break
    end
end
raw = rho;
floorValue = point.tolerances.clampFloorFactor*P_RT;
clamped = max(raw, floorValue);
expectedNewton = struct("initialGuess", P_RT, ...
    "maximumIterations", point.tolerances.newtonIterations, ...
    "deltaTolerance", point.tolerances.newtonDelta, ...
    "iterations", iteration, "converged", converged, ...
    "lastDelta", lastDelta, "rawFinal", raw, "clampFloor", floorValue, ...
    "clampedFinal", clamped, "clampChanged", clamped ~= raw, ...
    "rawPolynomialResidual", polyval(coefficients, raw));
require(isequaln(point.productionNewton, expectedNewton) && ...
    point.newtonInitialGuess == P_RT && ...
    point.newtonIterations == point.tolerances.newtonIterations && ...
    point.rho == clamped*k.M, "production Newton closure");
end

function validateSweep(sweep, label)
requireStruct(sweep, ["status" "evidenceGrade" "quantitiesSearched" ...
    "branchNames" "coordinateName" "coordinateRange" "coarseCoordinates" ...
    "adaptiveCoordinates" "candidateLedger" "baseline" "counterfactual"]);
quantities = ["cp=0"; "cv=0"; "gamma=1"; "dP/drho=0"];
require(sweep.status == "completed" && isequal(sweep.quantitiesSearched, quantities) && ...
    sweep.evidenceGrade == "❓" && ...
    isequal(sort(sweep.branchNames), sort(["baseline" "counterfactual"])), label);
if label == "fixedPressureSweep"
    require(sweep.coordinateName == "T_K" && ...
        isequaln(sweep.coordinateRange, [992.2824092088212 992.4824092088212]) && ...
        sweep.fixedPressure_Pa == 1007910.8613125964 && ...
        sweep.C111ZeroT_K == 992.38240920882117, "fixed-pressure identity");
else
    require(sweep.coordinateName == "lambda" && ...
        isequaln(sweep.coordinateRange, [0 1]) && ...
        sweep.path.T1_K == 1515.109678670083 && ...
        sweep.path.P1_Pa == 1538809.802594816 && ...
        sweep.path.expansionRatio == 2.2812178550028612 && ...
        sweep.path.Tlow_K == 664.1670261116656 && ...
        sweep.path.P2_Pa == 674556.267925093 && ...
        sweep.path.temperatureFormula == "T1+lambda*(Tlow-T1)" && ...
        sweep.path.pressureFormula == "P1+lambda*(P2-P1)", "H1a path identity");
end
for branchName = ["baseline" "counterfactual"]
    branch = sweep.(branchName);
    requireStruct(branch, ["status" "stateTable" "boundaries" ...
        "boundaryCountByQuantity" "nonphysicalIntervals" "invalidStates" ...
        "allCoordinatesAccountedFor" "requestedCoordinates" ...
        "rootSearchAssurance" "sampledExtrema" "extrema" "c111Treatment" ...
        "hasC111ZeroDerivativeDiscontinuity" "C111DiscontinuityEvidence"]);
    states = branch.stateTable;
    require(branch.status == "completed" && istable(states) && height(states) > 0 && ...
        all(ismember(["coordinate" "T_K" "P_Pa" "rho" "cpMolar" "cvMolar" ...
        "gamma" "dPdrho" "finite" "valid"], string(states.Properties.VariableNames))), label);
    require(branch.allCoordinatesAccountedFor && height(states) == numel(branch.requestedCoordinates) && ...
        isequaln(states.coordinate, branch.requestedCoordinates(:)) && ...
        all(isfinite(states.coordinate)) && all(isfinite(states.T_K)) && ...
        all(isfinite(states.P_Pa)), label);
    validateStateCoordinates(states, sweep, label);
    expectedFinite = isfinite(states.rho) & isfinite(states.cpMolar) & ...
        isfinite(states.cvMolar) & isfinite(states.gamma) & isfinite(states.dPdrho);
    require(isequal(states.finite, expectedFinite) && ...
        all(~states.valid | states.finite) && all(states.valid | ~states.finite) && ...
        all(isfinite(states.stablePositiveRealRootCount)) && ...
        all(states.stablePositiveRealRootCount >= 0) && ...
        all(states.stablePositiveRealRootCount == fix(states.stablePositiveRealRootCount)), ...
        "state numerical accounting");
    invalid = ~states.valid;
    expectedInvalid = states(invalid, ["coordinate" "T_K" "P_Pa" ...
        "classification" "reason"]);
    require(istable(branch.invalidStates) && ...
        isequaln(branch.invalidStates, expectedInvalid), "invalid-state accounting");
    require(all(states.classification(~invalid) == "validFinite") && ...
        all(states.reason(~invalid) == "none"), "valid-state classification");
    validateNonphysicalIntervals(branch.nonphysicalIntervals, states, ...
        branch.boundaries, sweep, label);
    validateBoundaries(branch, quantities, label);
    assurance = branch.rootSearchAssurance;
    requireStruct(assurance, ["method" "formalRootExclusion" "notFoundMeaning" ...
        "sampleCount" "allCandidatesResolved"]);
    require(assurance.method == "adaptiveSignAndEndpointSearch" && ...
        ~assurance.formalRootExclusion && ...
        assurance.notFoundMeaning == "noRootDetectedByDeclaredNumericalSearchNotFormalProof" && ...
        assurance.sampleCount == height(states) && assurance.allCandidatesResolved, ...
        "root search assurance");
    validateExtrema(branch, branchName);
    if branchName == "baseline"
        require(branch.c111Treatment == "currentFractionalPowerMixingRule" && ...
            branch.hasC111ZeroDerivativeDiscontinuity && ...
            branch.C111DiscontinuityEvidence.derivativeIsNonContinuous, ...
            "baseline C111 discontinuity");
    else
        require(branch.c111Treatment == "identicallyZeroBeforeCurrentMixingRule" && ...
            ~branch.hasC111ZeroDerivativeDiscontinuity && ...
            ~branch.C111DiscontinuityEvidence.derivativeIsNonContinuous, ...
            "counterfactual C111 discontinuity disappearance");
    end
end
end

function validateStateCoordinates(states, sweep, label)
if label == "fixedPressureSweep"
    require(isequaln(states.T_K, states.coordinate) && ...
        all(states.P_Pa == sweep.fixedPressure_Pa), "fixed-pressure state coordinates");
else
    expectedT = sweep.path.T1_K + states.coordinate.* ...
        (sweep.path.Tlow_K - sweep.path.T1_K);
    expectedP = sweep.path.P1_Pa + states.coordinate.* ...
        (sweep.path.P2_Pa - sweep.path.P1_Pa);
    require(isequaln(states.T_K, expectedT) && isequaln(states.P_Pa, expectedP), ...
        "H1a state coordinates");
end
end

function validateNonphysicalIntervals(intervals, states, boundaries, sweep, label)
requiredColumns = ["criterion" "startCoordinate" "endCoordinate" ...
    "startT_K" "endT_K" "startP_Pa" "endP_Pa"];
require(istable(intervals) && isequal(string(intervals.Properties.VariableNames), ...
    requiredColumns), "nonphysical interval columns");
expected = rebuildNonphysicalIntervals(states, boundaries, sweep, label);
require(isequaln(intervals, expected), "nonphysical interval reconstruction");
if isempty(intervals)
    return
end
criteria = ["cp<=0" "cv<=0" "gamma<=1"];
require(all(ismember(intervals.criterion, criteria)) && ...
    all(intervals.startCoordinate >= sweep.coordinateRange(1)) && ...
    all(intervals.startCoordinate <= sweep.coordinateRange(2)) && ...
    all(intervals.endCoordinate >= sweep.coordinateRange(1)) && ...
    all(intervals.endCoordinate <= sweep.coordinateRange(2)), label);
if label == "fixedPressureSweep"
    require(isequaln(intervals.startT_K, intervals.startCoordinate) && ...
        isequaln(intervals.endT_K, intervals.endCoordinate) && ...
        all(intervals.startP_Pa == sweep.fixedPressure_Pa) && ...
        all(intervals.endP_Pa == sweep.fixedPressure_Pa), "fixed interval mapping");
else
    startT = sweep.path.T1_K + intervals.startCoordinate.* ...
        (sweep.path.Tlow_K - sweep.path.T1_K);
    endT = sweep.path.T1_K + intervals.endCoordinate.* ...
        (sweep.path.Tlow_K - sweep.path.T1_K);
    startP = sweep.path.P1_Pa + intervals.startCoordinate.* ...
        (sweep.path.P2_Pa - sweep.path.P1_Pa);
    endP = sweep.path.P1_Pa + intervals.endCoordinate.* ...
        (sweep.path.P2_Pa - sweep.path.P1_Pa);
    require(isequaln(intervals.startT_K, startT) && isequaln(intervals.endT_K, endT) && ...
        isequaln(intervals.startP_Pa, startP) && isequaln(intervals.endP_Pa, endP), ...
        "H1a interval mapping");
end
end

function intervals = rebuildNonphysicalIntervals(states, boundaries, sweep, label)
intervals = table(strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), 'VariableNames', ...
    {'criterion' 'startCoordinate' 'endCoordinate' 'startT_K' ...
    'endT_K' 'startP_Pa' 'endP_Pa'});
criteria = ["cp<=0" "cv<=0" "gamma<=1"];
quantities = ["cp=0" "cv=0" "gamma=1"];
values = {states.cpMolar, states.cvMolar, states.gamma - 1};
for criterionIndex = 1:numel(criteria)
    mask = states.valid & values{criterionIndex} <= 0;
    edges = diff([false; mask; false]);
    starts = find(edges == 1);
    stops = find(edges == -1) - 1;
    for runIndex = 1:numel(starts)
        startCoordinate = states.coordinate(starts(runIndex));
        endCoordinate = states.coordinate(stops(runIndex));
        if starts(runIndex) > 1 && states.valid(starts(runIndex)-1)
            candidates = boundaries.quantity == quantities(criterionIndex) & ...
                ismember(boundaries.classification, ["root" "pole"]) & ...
                boundaries.coordinate >= states.coordinate(starts(runIndex)-1) & ...
                boundaries.coordinate <= startCoordinate;
            if any(candidates), startCoordinate = max(boundaries.coordinate(candidates)); end
        end
        if stops(runIndex) < height(states) && states.valid(stops(runIndex)+1)
            candidates = boundaries.quantity == quantities(criterionIndex) & ...
                ismember(boundaries.classification, ["root" "pole"]) & ...
                boundaries.coordinate >= endCoordinate & ...
                boundaries.coordinate <= states.coordinate(stops(runIndex)+1);
            if any(candidates), endCoordinate = min(boundaries.coordinate(candidates)); end
        end
        [startT, startP] = coordinateToPoint(sweep, label, startCoordinate);
        [endT, endP] = coordinateToPoint(sweep, label, endCoordinate);
        intervals = [intervals; table(criteria(criterionIndex), startCoordinate, ...
            endCoordinate, startT, endT, startP, endP, ...
            'VariableNames', intervals.Properties.VariableNames)]; %#ok<AGROW>
    end
end
end

function [T_K, P_Pa] = coordinateToPoint(sweep, label, coordinate)
if label == "fixedPressureSweep"
    T_K = coordinate;
    P_Pa = sweep.fixedPressure_Pa;
else
    T_K = sweep.path.T1_K + coordinate*(sweep.path.Tlow_K - sweep.path.T1_K);
    P_Pa = sweep.path.P1_Pa + coordinate*(sweep.path.P2_Pa - sweep.path.P1_Pa);
end
end

function validateExtrema(branch, branchName)
quantities = ["rho" "cpMolar" "cvMolar" "gamma" "dPdrho"];
for tableName = ["sampledExtrema" "extrema"]
    value = branch.(tableName);
    require(istable(value) && height(value) == 2*numel(quantities), "extrema row count");
    for quantity = quantities
        require(nnz(value.quantity == quantity & value.kind == "min") == 1 && ...
            nnz(value.quantity == quantity & value.kind == "max") == 1, ...
            "extrema quantity coverage");
    end
end
sampled = branch.sampledExtrema;
expectedSampled = rebuildSampledExtrema(branch.stateTable);
require(isequaln(sampled, expectedSampled) && ...
    all(sampled.scope == "sampledFiniteCandidateNotFormalGlobalExtremum") && ...
    all(sampled.classification == "finiteSampledCandidate") && ...
    all(isfinite(sampled.value)), "sampled extrema scope");
if branchName == "baseline"
    expectedClassified = expectedBaselineClassifiedExtrema(expectedSampled);
    require(isequaln(branch.extrema, expectedClassified), ...
        "baseline unbounded extrema classification");
else
    require(isequaln(branch.extrema, branch.sampledExtrema), ...
        "counterfactual sampled extrema classification");
end
end

function extrema = expectedBaselineClassifiedExtrema(sampled)
extrema = sampled;
for quantity = ["cpMolar" "cvMolar"]
    extrema = markExpectedUnbounded(extrema, quantity, ...
        "unboundedAtC111DerivativeDiscontinuity");
end
extrema = markExpectedUnbounded(extrema, "gamma", "unboundedAtCvZeroPole");
end

function extrema = markExpectedUnbounded(extrema, quantity, classification)
minimum = extrema.quantity == quantity & extrema.kind == "min";
maximum = extrema.quantity == quantity & extrema.kind == "max";
require(nnz(minimum) == 1 && nnz(maximum) == 1, ...
    "classified extrema source rows");
extrema.coordinate(minimum | maximum) = NaN;
extrema.T_K(minimum | maximum) = NaN;
extrema.P_Pa(minimum | maximum) = NaN;
extrema.value(minimum) = -Inf;
extrema.value(maximum) = Inf;
extrema.scope(minimum | maximum) = "continuousDomain";
extrema.classification(minimum | maximum) = classification;
end

function extrema = rebuildSampledExtrema(states)
extrema = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
    'VariableNames', {'quantity' 'kind' 'coordinate' 'T_K' 'P_Pa' ...
    'value' 'scope' 'classification'});
for quantity = ["rho" "cpMolar" "cvMolar" "gamma" "dPdrho"]
    values = states.(quantity);
    eligible = states.valid & isfinite(values);
    require(any(eligible), "sampled extrema eligible states");
    eligibleRows = find(eligible);
    [minimum, minOffset] = min(values(eligible));
    [maximum, maxOffset] = max(values(eligible));
    for item = {"min", minimum, eligibleRows(minOffset); ...
            "max", maximum, eligibleRows(maxOffset)}.'
        rowIndex = item{3};
        extrema = [extrema; table(quantity, string(item{1}), ...
            states.coordinate(rowIndex), states.T_K(rowIndex), states.P_Pa(rowIndex), ...
            item{2}, "sampledFiniteCandidateNotFormalGlobalExtremum", ...
            "finiteSampledCandidate", ...
            'VariableNames', extrema.Properties.VariableNames)]; %#ok<AGROW>
    end
end
end

function validateBoundaries(branch, quantities, label)
require(istable(branch.boundaries) && istable(branch.boundaryCountByQuantity), label);
validateExactNameSet(branch.boundaryCountByQuantity.quantity, quantities, ...
    "boundary count quantities");
for quantity = quantities.'
    rows = branch.boundaries.quantity == quantity;
    count = branch.boundaryCountByQuantity.quantity == quantity;
    roots = rows & branch.boundaries.classification == "root";
    require(any(rows) && nnz(count) == 1 && ...
        branch.boundaryCountByQuantity.count(count) == nnz(roots), label);
    if any(roots)
        rootRows = branch.boundaries(roots, :);
        require(all(rootRows.refinementMethod == "fzero") && ...
            all(isfinite(rootRows.bracketLeft)) && all(isfinite(rootRows.bracketRight)) && ...
            all(rootRows.coordinate >= rootRows.bracketLeft) && ...
            all(rootRows.coordinate <= rootRows.bracketRight) && ...
            all(isfinite(rootRows.leftValue)) && all(isfinite(rootRows.rightValue)) && ...
            all(rootRows.leftValue.*rootRows.rightValue <= 0) && ...
            all(abs(rootRows.residual) <= rootRows.residualTolerance), label);
    end
end
end

function validatePathParityAgainstSweeps(analysis)
path = analysis.baselineParity.pathTable;
expected = [rootCoordinate(analysis.fixedPressureSweep.baseline, "cp=0"); ...
    rootCoordinate(analysis.fixedPressureSweep.baseline, "cv=0"); ...
    rootCoordinate(analysis.h1aPathSweep.baseline, "cp=0"); ...
    rootCoordinate(analysis.h1aPathSweep.baseline, "cv=0")];
names = ["fixedPressure.cp=0"; "fixedPressure.cv=0"; ...
    "h1aPath.cp=0"; "h1aPath.cv=0"];
[~, order] = ismember(names, path.name);
require(isequaln(path.h2aBaselineValue(order), expected), ...
    "path parity boundary identity");
end

function coordinate = rootCoordinate(branch, quantity)
rows = branch.boundaries.quantity == quantity & ...
    branch.boundaries.classification == "root";
require(nnz(rows) == 1, "approved baseline root count");
coordinate = branch.boundaries.coordinate(rows);
end

function validateCanonicalDerivedEvidence(analysis)
reference = canonicalAnalysis();
for sweepName = ["fixedPressureSweep" "h1aPathSweep"]
    for branchName = ["baseline" "counterfactual"]
        actual = analysis.(sweepName).(branchName);
        expected = reference.(sweepName).(branchName);
        require(isequaln(actual.boundaries, expected.boundaries), ...
            "canonical root and residual evidence");
        require(isequaln(actual.C111DiscontinuityEvidence, ...
            expected.C111DiscontinuityEvidence), ...
            "canonical C111 one-sided evidence");
    end
end
end

function reference = canonicalAnalysis()
persistent cachedReference
if isempty(cachedReference)
    cachedReference = analyze_task8_h2a_he_third_virial_counterfactual();
end
reference = cachedReference;
end

function [csvHash, summaryHash] = writeOutputs(config, analysis)
[parent, name, ext] = fileparts(config.outputDir);
leaf = string(name) + string(ext);
prefix = "." + leaf + ".staging_";
[~, unique] = fileparts(tempname(parent));
staging = fullfile(parent, prefix + string(unique));
if ~mkdir(staging)
    error("steady53:H2aOutputFailed", "Could not create staging directory.");
end
cleanup = onCleanup(@() cleanupStaging(staging, parent, prefix));
csvPath = fullfile(staging, "h2a_counterfactual_diagnostics.csv");
summaryPath = fullfile(staging, "h2a_summary.txt");
writetable(diagnosticsTable(analysis), csvPath);
config.outputFailureHook("afterCsvBeforeSummary", staging, config.outputDir);
writeText(summaryPath, summaryText(analysis));
validateReadable(csvPath); validateReadable(summaryPath);
csvHash = sha256File(csvPath); summaryHash = sha256File(summaryPath);
if isfolder(config.outputDir) || isfile(config.outputDir)
    error("steady53:H2aOutputExists", "H2a target appeared before publication.");
end
config.outputFailureHook("beforePublish", staging, config.outputDir);
moveNoReplace(staging, config.outputDir);
try
    validatePublished(config.outputDir, csvHash, summaryHash);
catch exception
    cleanupPublished(config.outputDir, parent, leaf);
    rethrow(exception);
end
clear cleanup
end

function rows = diagnosticsTable(analysis)
section = strings(0,1); name = strings(0,1); value = strings(0,1);
    function add(s, n, v)
        section(end+1,1)=s; name(end+1,1)=n; value(end+1,1)=string(v);
    end
add("literature", "authors", "Tournier, El-Genk and Gallo");
add("literature", "title", ...
    "Best Estimates of Binary Gas Mixtures Properties for Closed Brayton Cycle Space Applications");
add("literature", "publication", "AIAA 2006-4154");
add("literature", "DOI", "10.2514/6.2006-4154");
add("literature", "URL", ...
    "https://www.researchgate.net/publication/268572975_Best_Estimates_of_Binary_Gas_Mixtures_Properties_for_Closed_Brayton_Cycle_Space_Applications");
add("literature", "supportBoundary", ...
    "supports approved counterfactual candidate only; does not prove formal model correctness");
add("taskStatus", "H1a-S2", "NOT_EXECUTED");
add("taskStatus", "Task8", "NOT_COMPLETE");
add("taskStatus", "steady14000s", "NOT_EXECUTED_OR_ACCEPTED");
add("taskStatus", "formalModelPromotion", "NOT_AUTHORIZED");
add("evidenceGrade", "baselineParity", "✅");
add("evidenceGrade", "counterfactualNumerics", "✅");
add("evidenceGrade", "counterfactualPhysicalInterpretation", "⚠️");
add("evidenceGrade", "formalModelCorrectnessOrPromotion", "❌");
add("evidenceGrade", "H1aAndSteady14000s", "❓");

topFields = string(fieldnames(analysis));
for field = topFields.'
    appendValue(field, analysis.(field));
end
appendDeltas("", analysis.exceptionPoint.baseline, ...
    analysis.exceptionPoint.counterfactual);
rows = table(section, name, value);

    function appendValue(path, item)
        if isstruct(item)
            require(isscalar(item), "serializable scalar struct");
            fields = string(fieldnames(item));
            for fieldName = fields.'
                child = item.(fieldName);
                if isLeafScalar(child)
                    add(path, fieldName, formatScalar(child));
                elseif isLeafArray(child)
                    appendArray(path, fieldName, child);
                else
                    appendValue(path + "." + fieldName, child);
                end
            end
        elseif istable(item)
            appendTable(path, item);
        elseif isLeafArray(item)
            appendArray(path, "value", item);
        else
            error("steady53:H2aOutputFailed", ...
                "Unsupported self-contained evidence value at '%s'.", path);
        end
    end

    function appendArray(path, fieldName, item)
        item = item(:);
        for itemIndex = 1:numel(item)
            add(path, fieldName + "(" + itemIndex + ")", ...
                formatScalar(item(itemIndex)));
        end
    end

    function appendTable(path, item)
        outputSection = tableSection(path);
        variables = string(item.Properties.VariableNames);
        for rowIndex = 1:height(item)
            key = tableRowKey(path, item, rowIndex);
            for variable = variables
                cellValue = item.(variable)(rowIndex, :);
                if isLeafScalar(cellValue)
                    add(outputSection, key + "." + variable, ...
                        formatScalar(cellValue));
                elseif isLeafArray(cellValue)
                    values = cellValue(:);
                    for valueIndex = 1:numel(values)
                        add(outputSection, key + "." + variable + "(" + ...
                            valueIndex + ")", formatScalar(values(valueIndex)));
                    end
                else
                    error("steady53:H2aOutputFailed", ...
                        "Unsupported table evidence at '%s'.", path);
                end
            end
        end
    end

    function appendDeltas(prefix, baseline, counterfactual)
        fields = intersect(string(fieldnames(baseline)), ...
            string(fieldnames(counterfactual)), "stable");
        for fieldName = fields.'
            baseValue = baseline.(fieldName);
            cfValue = counterfactual.(fieldName);
            childName = fieldName;
            if strlength(prefix) > 0
                childName = prefix + "." + fieldName;
            end
            if isnumeric(baseValue) && isnumeric(cfValue) && ...
                    isequal(size(baseValue), size(cfValue))
                delta = cfValue - baseValue;
                if isscalar(delta)
                    add("exceptionPoint.delta", childName, formatScalar(delta));
                else
                    for valueIndex = 1:numel(delta)
                        add("exceptionPoint.delta", childName + "(" + valueIndex + ")", ...
                            formatScalar(delta(valueIndex)));
                    end
                end
            elseif isstruct(baseValue) && isscalar(baseValue) && ...
                    isstruct(cfValue) && isscalar(cfValue)
                appendDeltas(childName, baseValue, cfValue);
            end
        end
    end
end

function text = summaryText(analysis)
evidence = diagnosticsTable(analysis);
lines = ["H2a approved counterfactual evidence"; ...
    "resultNeutral=true"; ...
    "authorizesRepair=false"; ...
    "formalRootExclusion=false"; ...
    "notFoundMeaning=noRootDetectedByDeclaredNumericalSearchNotFormalProof"; ...
    "sampledExtrema=finite sampled candidates, not formal global extrema"; ...
    "baselineExtrema=unboundedAtC111DerivativeDiscontinuity;unboundedAtCvZeroPole"];
for index = 1:height(evidence)
    lines(end+1,1) = evidence.section(index) + "." + ...
        evidence.name(index) + "=" + evidence.value(index); %#ok<AGROW>
end
text = strjoin(lines, newline) + newline;
end

function tf = isLeafScalar(value)
tf = (isnumeric(value) || islogical(value) || isstring(value) || ...
    ischar(value)) && isscalar(value);
end

function tf = isLeafArray(value)
tf = isnumeric(value) || islogical(value) || isstring(value) || ischar(value);
tf = tf && ~isscalar(value);
end

function output = formatScalar(value)
if islogical(value)
    output = string(value);
elseif isnumeric(value)
    if ~isreal(value)
        output = compose("%.17g%+.17gi", real(value), imag(value));
    else
        output = compose("%.17g", value);
    end
else
    output = string(value);
end
end

function section = tableSection(path)
section = path;
if path == "baselineParity.table"
    section = "baselineParity.point";
elseif path == "baselineParity.pathTable"
    section = "baselineParity.path";
elseif endsWith(path, ".boundaries")
    section = extractBefore(path, strlength(path) - strlength(".boundaries") + 1) + ...
        ".boundary";
elseif endsWith(path, ".nonphysicalIntervals")
    section = extractBefore(path, ...
        strlength(path) - strlength(".nonphysicalIntervals") + 1) + ...
        ".nonphysicalInterval";
end
end

function key = tableRowKey(path, value, rowIndex)
if path == "baselineParity.table" || path == "baselineParity.pathTable"
    key = string(value.name(rowIndex));
elseif endsWith(path, ".boundaries")
    quantity = string(value.quantity(rowIndex));
    occurrence = nnz(value.quantity(1:rowIndex) == quantity);
    key = quantity + "." + occurrence;
elseif endsWith(path, ".nonphysicalIntervals")
    criterion = string(value.criterion(rowIndex));
    occurrence = nnz(value.criterion(1:rowIndex) == criterion);
    key = criterion + "." + occurrence;
elseif endsWith(path, ".extrema") || endsWith(path, ".sampledExtrema")
    key = string(value.quantity(rowIndex)) + "." + string(value.kind(rowIndex));
else
    key = "row" + rowIndex;
end
end

function moveNoReplace(source, target)
sourcePath = javaObject("java.io.File", char(source)).toPath();
targetPath = javaObject("java.io.File", char(target)).toPath();
options = javaArray("java.nio.file.CopyOption", 0);
try
    javaMethod("move", "java.nio.file.Files", sourcePath, targetPath, options);
catch exception
    if isfolder(target) || isfile(target)
        error("steady53:H2aOutputExists", "H2a publication refused target collision.");
    end
    failure = MException("steady53:H2aOutputFailed", "Atomic H2a publication failed.");
    failure = addCause(failure, exception);
    throw(failure);
end
end

function validatePublished(outputDir, csvHash, summaryHash)
names = sort(string({dir(outputDir).name}));
names = names(names ~= "." & names ~= "..");
expected = ["h2a_counterfactual_diagnostics.csv" "h2a_summary.txt"];
if ~isequal(names, expected) || sha256File(fullfile(outputDir, expected(1))) ~= csvHash || ...
        sha256File(fullfile(outputDir, expected(2))) ~= summaryHash
    error("steady53:H2aOutputFailed", "Published H2a directory is incomplete.");
end
end

function writeText(pathValue, content)
[fileId, message] = fopen(pathValue, "w", "native", "UTF-8");
if fileId < 0, error("steady53:H2aOutputFailed", "%s", message); end
cleanup = onCleanup(@() fclose(fileId));
fprintf(fileId, "%s", content);
clear cleanup
end

function validateReadable(pathValue)
info = dir(pathValue);
if numel(info) ~= 1 || info.bytes == 0
    error("steady53:H2aOutputFailed", "Staged H2a output is missing or empty.");
end
end

function cleanupStaging(staging, parent, prefix)
if isfolder(staging) && string(fileparts(staging)) == string(parent) && ...
        startsWith(string(extractAfter(staging, parent + filesep)), prefix)
    rmdir(staging, "s");
end
end

function cleanupPublished(outputDir, parent, leaf)
if isfolder(outputDir) && string(fileparts(outputDir)) == string(parent) && ...
        string(extractAfter(outputDir, parent + filesep)) == leaf
    rmdir(outputDir, "s");
end
end

function hash = sha256File(pathValue)
[status, output] = system("shasum -a 256 " + shellQuote(pathValue));
if status ~= 0, error("steady53:H2aOutputFailed", "Hash calculation failed."); end
hash = lower(extractBefore(strtrim(string(output)), " "));
end

function quoted = shellQuote(value)
quoted = "'" + replace(string(value), "'", "'\\''") + "'";
end

function requireStruct(value, names)
require(isstruct(value) && isscalar(value) && all(isfield(value, names)), "required evidence fields");
end

function require(condition, label)
if ~isequal(condition, true)
    error("steady53:H2aInvalidEvidence", "Invalid or incomplete H2a evidence: %s.", label);
end
end
