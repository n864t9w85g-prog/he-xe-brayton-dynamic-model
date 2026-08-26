function tests = test_h1b_cpbar_candidate_readonly
%TEST_H1B_CPBar_CANDIDATE_READONLY Pure H1b path-average solver contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"), "-begin");
testCase.TestData.inputs = struct("T1_K", 1500, "P1_Pa", 1.5e6, ...
    "P2_Pa", 0.7e6, "T2s_K", 1100, "eta", 0.87);
testCase.TestData.numerics = fixedNumerics();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testConstantCpRecoversEtaEquation(testCase)
for variant = ["linearEndpointPressure" "constantP1" "constantP2"]
    result = h1b_cpbar_candidate_readonly(testCase.TestData.inputs, ...
        variant, @constantProperty, testCase.TestData.numerics);
    inputs = testCase.TestData.inputs;
    expected = inputs.T1_K-inputs.eta*(inputs.T1_K-inputs.T2s_K);
    verifyEqual(testCase, result.T2_K, expected, "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarIsentropic_J_kgK, 520, ...
        "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarActual_J_kgK, 520, ...
        "AbsTol", 1e-10);
    verifyEqual(testCase, result.cpBarRatio, 1, "AbsTol", 1e-12);
end
end

function testAnalyticCpMatchesAllPressurePaths(testCase)
inputs = testCase.TestData.inputs;
for variant = ["linearEndpointPressure" "constantP1" "constantP2"]
    result = h1b_cpbar_candidate_readonly(inputs, variant, ...
        @analyticProperty, testCase.TestData.numerics);
    expectedIdeal = analyticAverage(inputs, inputs.T2s_K, variant);
    expectedActual = analyticAverage(inputs, result.T2_K, variant);
    expectedResidual = result.T2_K-(inputs.T1_K-inputs.eta* ...
        (expectedIdeal/expectedActual)*(inputs.T1_K-inputs.T2s_K));
    verifyEqual(testCase, result.cpBarIsentropic_J_kgK, expectedIdeal, ...
        "AbsTol", 1e-8);
    verifyEqual(testCase, result.cpBarActual_J_kgK, expectedActual, ...
        "AbsTol", 1e-8);
    verifyEqual(testCase, result.cpBarRatio, ...
        expectedIdeal/expectedActual, "AbsTol", 1e-12);
    verifyEqual(testCase, result.rootResidual_K, expectedResidual, ...
        "AbsTol", 1e-12);
end
end

function testAuditHas1001PhysicalPoints(testCase)
result = h1b_cpbar_candidate_readonly(testCase.TestData.inputs, ...
    "linearEndpointPressure", @analyticProperty, ...
    testCase.TestData.numerics);
for audit = [result.idealPathAudit result.actualPathAudit]
    verifyEqual(testCase, audit.sampleCount, 1001);
    verifyGreaterThan(testCase, audit.minCpMass_J_kgK, 0);
    verifyGreaterThan(testCase, audit.minCvMass_J_kgK, 0);
    verifyGreaterThan(testCase, audit.minGamma, 1);
    verifyGreaterThan(testCase, audit.minRho_kg_m3, 0);
    verifyTrue(testCase, audit.allPhysical);
    verifyFalse(testCase, audit.formalGlobalProof);
    verifyEqual(testCase, audit.classification, ...
        "finite1001PointAuditNotFormalGlobalProof");
end
end

function testInvalidInputsAndVariantFailClosed(testCase)
stateBefore = warning;
inputs = testCase.TestData.inputs;
inputs.extra = 1;
verifyError(testCase, @() h1b_cpbar_candidate_readonly(inputs, ...
    "constantP1", @constantProperty, testCase.TestData.numerics), ...
    "steady53:H1bInvalidInput");
verifyError(testCase, @() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "unapprovedPressurePath", ...
    @constantProperty, testCase.TestData.numerics), ...
    "steady53:H1bInvalidPathVariant");
verifyEqual(testCase, warning, stateBefore);
end

function testNonphysicalPropertyFailsClosed(testCase)
stateBefore = warning;
invalidProperties = {@nonpositiveCpProperty, @unitGammaProperty, ...
    @nonpositiveRhoProperty};
for index = 1:numel(invalidProperties)
    propertyFunction = invalidProperties{index};
    verifyError(testCase, @() h1b_cpbar_candidate_readonly( ...
        testCase.TestData.inputs, "constantP1", propertyFunction, ...
        testCase.TestData.numerics), "steady53:H1bInvalidProperty");
end
verifyEqual(testCase, warning, stateBefore);
end

function testPropertyWarningFailsClosed(testCase)
stateBefore = warning;
exception = captureException(@() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "constantP1", @warningProperty, ...
    testCase.TestData.numerics));
verifyEqual(testCase, string(exception.identifier), ...
    "steady53:H1bPropertyWarning");
verifyCauseIdentifier(testCase, exception, ...
    "tests:H1bSyntheticPropertyWarning");
verifyEqual(testCase, warning, stateBefore);
end

function testIntegralFailurePreservesCause(testCase)
stateBefore = warning;
numerics = testCase.TestData.numerics;
numerics.integralFunction = @failingIntegral;
exception = captureException(@() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "constantP1", @constantProperty, numerics));
verifyEqual(testCase, string(exception.identifier), ...
    "steady53:H1bIntegrationFailed");
verifyCauseIdentifier(testCase, exception, ...
    "tests:H1bSyntheticIntegralFailure");
verifyEqual(testCase, warning, stateBefore);
end

function testNoBracketFailsClosed(testCase)
stateBefore = warning;
numerics = testCase.TestData.numerics;
sequence = [100 1 1];
callCount = 0;
numerics.integralFunction = @sequenceIntegral;
verifyError(testCase, @() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "constantP1", @constantProperty, numerics), ...
    "steady53:H1bNoBracket");
verifyEqual(testCase, warning, stateBefore);

    function value = sequenceIntegral(varargin)
        assert(~isempty(varargin));
        callCount = callCount+1;
        value = sequence(min(callCount, numel(sequence)));
    end
end

function testRootNonconvergenceFailsClosed(testCase)
stateBefore = warning;
numerics = testCase.TestData.numerics;
numerics.rootFunction = @nonconvergentRoot;
verifyError(testCase, @() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "constantP1", @constantProperty, numerics), ...
    "steady53:H1bRootFailed");
verifyEqual(testCase, warning, stateBefore);
end

function testWarningStateRestoredAfterFailure(testCase)
identifier = "tests:H1bCallerWarningState";
originalState = warning;
cleanup = onCleanup(@() warning(originalState));
warning("off", identifier);
stateBefore = warning;
verifyError(testCase, @() h1b_cpbar_candidate_readonly( ...
    testCase.TestData.inputs, "constantP1", @warningProperty, ...
    testCase.TestData.numerics), "steady53:H1bPropertyWarning");
verifyEqual(testCase, warning, stateBefore);
clear cleanup
end

function numerics = fixedNumerics()
numerics = struct("integralFunction", @integral, ...
    "rootFunction", @fzero, "integralRelTol", 1e-8, ...
    "integralAbsTol_J_kgK", 1e-8, "rootTolX_K", 1e-12, ...
    "rootMaxIterations", 1000, ...
    "rootMaxFunctionEvaluations", 5000, ...
    "rootAbsResidualTolerance_K", 1e-9, "auditSampleCount", 1001);
end

function value = analyticAverage(inputs, Tout_K, variant)
meanT = (inputs.T1_K+Tout_K)/2;
switch variant
    case "linearEndpointPressure"
        meanP = (inputs.P1_Pa+inputs.P2_Pa)/2;
    case "constantP1"
        meanP = inputs.P1_Pa;
    case "constantP2"
        meanP = inputs.P2_Pa;
end
value = 480+0.02*meanT+1e-6*meanP;
end

function [cp, gamma, rho] = constantProperty(~, ~)
cp = 520;
gamma = 1.65;
rho = 4;
end

function [cp, gamma, rho] = analyticProperty(T_K, P_Pa)
cp = 480+0.02*T_K+1e-6*P_Pa;
gamma = 1.65+zeros(size(cp));
rho = P_Pa./(287*T_K);
end

function [cp, gamma, rho] = nonpositiveCpProperty(~, ~)
cp = 0;
gamma = 1.65;
rho = 4;
end

function [cp, gamma, rho] = unitGammaProperty(~, ~)
cp = 520;
gamma = 1;
rho = 4;
end

function [cp, gamma, rho] = nonpositiveRhoProperty(~, ~)
cp = 520;
gamma = 1.65;
rho = -1;
end

function [cp, gamma, rho] = warningProperty(~, ~)
warning("tests:H1bSyntheticPropertyWarning", ...
    "Synthetic property warning for fail-closed coverage.");
cp = 520;
gamma = 1.65;
rho = 4;
end

function value = failingIntegral(varargin)
value = NaN;
assert(~isempty(varargin));
throwSyntheticIntegrationFailure();
end

function throwSyntheticIntegrationFailure()
error("tests:H1bSyntheticIntegralFailure", ...
    "Synthetic integration failure for cause coverage.");
end

function [root, fval, exitflag, output] = nonconvergentRoot(fun, bracket, varargin)
assert(~isempty(varargin));
root = mean(bracket);
fval = fun(root);
exitflag = 0;
output = struct("iterations", 0, "funcCount", 1, ...
    "algorithm", "synthetic", "message", "Synthetic nonconvergence.");
end

function exception = captureException(functionHandle)
try
    functionHandle();
    exception = MException("tests:H1bExpectedFailureMissing", ...
        "Expected the supplied function to fail.");
catch exception
end
end

function verifyCauseIdentifier(testCase, exception, expectedIdentifier)
identifiers = causeIdentifiers(exception);
verifyTrue(testCase, any(identifiers == expectedIdentifier), ...
    sprintf("Expected cause %s; observed causes: %s", expectedIdentifier, ...
    strjoin(identifiers, ", ")));
end

function identifiers = causeIdentifiers(exception)
identifiers = strings(0, 1);
pending = exception.cause(:);
while ~isempty(pending)
    current = pending{1};
    pending(1) = [];
    identifiers(end+1, 1) = string(current.identifier); %#ok<AGROW>
    pending = [pending; current.cause(:)]; %#ok<AGROW>
end
end
