function analysis = analyze_task8_h2_hexe_property_readonly(options)
%ANALYZE_TASK8_H2_HEXE_PROPERTY_READONLY Performs the Task 2 H2 audit.
%   The audit independently recomputes the active Virial intermediates and
%   calls the production property function only for final-output comparison.
%   It never loads or runs a Simulink model and never creates an H2 artifact.

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

equationMap = buildEquationMap();
coefficients = evaluateVirialCoefficients(config.exceptionT_K);
coefficients.status = "computedInTask2";
coefficients.classification = "calculatedConsequenceOfActiveSource";
zeroT_K = fzero(@componentC111, ...
    [config.exceptionT_K - 0.1, config.exceptionT_K + 0.1]);
coefficients.C111ZeroT_K = zeroT_K;
coefficients.C111AtZero = componentC111(zeroT_K);
coefficients.C111ZeroOffset_K = config.exceptionT_K - zeroT_K;

analytic = evaluateAnalyticDerivatives(config.exceptionT_K, coefficients);
finiteDifference = evaluateFiniteDifferences(config.exceptionT_K, analytic);
derivatives = struct( ...
    "status", "computedInTask2", ...
    "classification", "calculatedConsequenceOfActiveSource", ...
    "analytic", analytic, ...
    "finiteDifference", finiteDifference);

densityRoots = evaluateDensityRoots(config.exceptionT_K, ...
    config.exceptionP_Pa, coefficients);
diagnostic = evaluateThermalDiagnostic(config.exceptionT_K, coefficients, ...
    analytic, densityRoots.productionNewton.clampedFinal);
derivatives.drhoHat_dT = diagnostic.drhoHat_dT;
resolvedPropertyPath = string(which("HeXe_property_simulink"));
if resolvedPropertyPath ~= propertyPath
    error("steady53:H2PropertyResolutionMismatch", ...
        "Production property function resolved to an unapproved source.");
end
[calledCpMass, calledGamma, calledRho] = HeXe_property_simulink( ...
    config.exceptionT_K, config.exceptionP_Pa);
called = struct("cpMass", calledCpMass, "gamma", calledGamma, ...
    "rho", calledRho, "cvMassDerived", calledCpMass/calledGamma);
tolerances = struct("cpMassAbs", 1e-10, "gammaAbs", 1e-13, ...
    "rhoAbs", 1e-13);
absoluteError = struct( ...
    "cpMass", abs(diagnostic.cpMass - called.cpMass), ...
    "gamma", abs(diagnostic.gamma - called.gamma), ...
    "rho", abs(diagnostic.rho - called.rho));
allWithinTolerance = absoluteError.cpMass <= tolerances.cpMassAbs && ...
    absoluteError.gamma <= tolerances.gammaAbs && ...
    absoluteError.rho <= tolerances.rhoAbs;
if ~allWithinTolerance
    error("steady53:H2ProductionParityMismatch", ...
        "Independent Task 2 recomputation does not match production output.");
end
production = struct( ...
    "called", called, ...
    "diagnostic", diagnostic, ...
    "parity", struct("absoluteError", absoluteError, ...
        "tolerances", tolerances, "allWithinTolerance", allWithinTolerance));

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
    "reviewedPdfPages", [33 34 35], ...
    "reviewedPrintedPages", [18 19 20], ...
    "equationMap", equationMap, ...
    "resolvedPropertyPath", resolvedPropertyPath, ...
    "originalLiterature", originalLiteratureAudit(), ...
    "protectedAssetHashesBefore", protectedBefore, ...
    "protectedAssetHashesAfter", protectedAfter);
analysis.coefficients = coefficients;
analysis.derivatives = derivatives;
analysis.densityRoots = densityRoots;
analysis.production = production;
analysis.thermoIdentity = laterTaskPlaceholder();
analysis.domainSweep = laterTaskPlaceholder();
analysis.hypothesisVerdicts = laterTaskPlaceholder();
end

function map = buildEquationMap()
paperEquation = ["2.7"; "2.8"; "2.9"; "2.10"; "2.11"; "2.12"; ...
    "2.13"; "2.14"; "2.15"; "2.16"; "2.17"];
pdfPage = [33; 33; 33; 33; 34; 34; 34; 34; 34; 34; 34];
printedPage = [18; 18; 18; 18; 19; 19; 19; 19; 19; 19; 19];
sourceLineStart = [86; 50; 76; 71; 72; 74; 81; 79; 185; 175; 180];
sourceLineEnd = [98; 50; 76; 71; 73; 75; 83; 80; 194; 177; 182];
diagnosticPath = ["densityRoots"; "coefficients.mixtureMolarMass"; ...
    "coefficients.B"; "coefficients.B11"; "coefficients.B22"; ...
    "coefficients.B12"; "coefficients.C"; "coefficients.C111_C222"; ...
    "production.diagnostic.cpMass"; "derivatives.drhoHat_dT"; ...
    "production.diagnostic.cvMolar"];
map = table(paperEquation, pdfPage, printedPage, sourceLineStart, ...
    sourceLineEnd, diagnosticPath);
end

function audit = originalLiteratureAudit()
claims = [ ...
    "Eq.(11) third-order Virial applicability to Ne/Ar/Kr"
    "Third-order Virial contribution for He described as negligible"
    "40 g/mol He-Xe at T>400 K and P<2 MPa differs under 1 percent from ideal heat-capacity ratios"];
audit = struct( ...
    "status", "pendingTask4Verification", ...
    "evidenceGrade", "❓", ...
    "authors", "Tournier/El-Genk/Gallo", ...
    "paperNumber", "AIAA 2006-4154", ...
    "doi", "10.2514/6.2006-4154", ...
    "claims", claims, ...
    "claimEvidenceGrade", repmat("❓", size(claims)));
end

function constants = hexeConstants()
constants = struct();
constants.R0 = 8.314;
constants.M_He = 4.0026e-3;
constants.M_Xe = 131.293e-3;
constants.x_He = 0.7172;
constants.x_Xe = 1.0 - constants.x_He;
constants.T_c_He = 5.19;
constants.T_c_Xe = 289.6;
constants.rho_c_He = 69.64;
constants.rho_c_Xe = 1099.7;
constants.T_c_12 = sqrt(constants.T_c_He * constants.T_c_Xe);
constants.v_He = constants.M_He / constants.rho_c_He;
constants.v_Xe = constants.M_Xe / constants.rho_c_Xe;
constants.v_12 = (1/8) * (constants.v_He^(1/3) + ...
    constants.v_Xe^(1/3))^3;
constants.M = constants.x_Xe*constants.M_Xe + ...
    constants.x_He*constants.M_He;
end

function values = evaluateVirialCoefficients(T)
k = hexeConstants();
T_Xe = T/k.T_c_Xe;
T_12 = T/k.T_c_12;
values = struct();
values.mixtureMolarMass = k.M;
values.B11 = (8.4 - 0.0018*T + 115/sqrt(T) - 835/T)*1e-6;
u_Xe = 102.732 - 0.01*T_Xe - 0.44/T_Xe^1.22;
values.B22 = k.v_Xe*(-102.6 + u_Xe*tanh(4.5*sqrt(T_Xe)));
u_12 = 102.732 - 0.001*T_12 - 0.44/T_12^1.22;
values.B12 = k.v_12*(-102.6 + u_12*tanh(4.5*sqrt(T_12)));
values.B = k.x_He^2*values.B11 + ...
    2*k.x_He*k.x_Xe*values.B12 + k.x_Xe^2*values.B22;
values.C111 = componentC(T, k.v_He, k.T_c_He);
values.C222 = componentC(T, k.v_Xe, k.T_c_Xe);
values.C112 = signedRealCubeRoot(values.C111^2*values.C222);
values.C122 = signedRealCubeRoot(values.C111*values.C222^2);
values.C = k.x_He^3*values.C111 + ...
    3*k.x_He^2*k.x_Xe*values.C112 + ...
    3*k.x_He*k.x_Xe^2*values.C122 + k.x_Xe^3*values.C222;
end

function value = componentC111(T)
k = hexeConstants();
value = componentC(T, k.v_He, k.T_c_He);
end

function value = componentC(T, characteristicVolume, criticalTemperature)
theta = T/criticalTemperature;
value = characteristicVolume^2*(0.0757 + ...
    (-0.0862 - 3.6e-5*theta + 0.0237/theta^0.059)*tanh(0.84*theta));
end

function value = signedRealCubeRoot(argument)
value = sign(argument)*abs(argument)^(1/3);
end

function d = evaluateAnalyticDerivatives(T, values)
k = hexeConstants();
T_Xe = T/k.T_c_Xe;
T_12 = T/k.T_c_12;
d = struct();
d.dB11_dT = (-0.0018 - 57.5/T^(3/2) + 835/T^2)*1e-6;
d.d2B11_dT2 = (86.25/T^2.5 - 1670/T^3)*1e-6;
[d.dB22_dT, d.d2B22_dT2] = secondVirialDerivatives( ...
    T_Xe, k.T_c_Xe, k.v_Xe, 0.01);
[d.dB12_dT, d.d2B12_dT2] = secondVirialDerivatives( ...
    T_12, k.T_c_12, k.v_12, 0.001);
d.dB_dT = k.x_He^2*d.dB11_dT + ...
    2*k.x_He*k.x_Xe*d.dB12_dT + k.x_Xe^2*d.dB22_dT;
d.d2B_dT2 = k.x_He^2*d.d2B11_dT2 + ...
    2*k.x_He*k.x_Xe*d.d2B12_dT2 + k.x_Xe^2*d.d2B22_dT2;

[d.dC111_dT, d.d2C111_dT2] = thirdVirialDerivatives( ...
    T, k.T_c_He, k.v_He);
[d.dC222_dT, d.d2C222_dT2] = thirdVirialDerivatives( ...
    T, k.T_c_Xe, k.v_Xe);
a = d.dC111_dT/values.C111;
b = d.dC222_dT/values.C222;
d.dC112_dT = values.C112*((2/3)*a + (1/3)*b);
d.dC122_dT = values.C122*((1/3)*a + (2/3)*b);
aPrime = d.d2C111_dT2/values.C111 - a^2;
bPrime = d.d2C222_dT2/values.C222 - b^2;
d.d2C112_dT2 = values.C112*((2/3)*aPrime + (1/3)*bPrime + ...
    ((2/3)*a + (1/3)*b)^2);
d.d2C122_dT2 = values.C122*((1/3)*aPrime + (2/3)*bPrime + ...
    ((1/3)*a + (2/3)*b)^2);
d.dC_dT = k.x_He^3*d.dC111_dT + ...
    3*k.x_He^2*k.x_Xe*d.dC112_dT + ...
    3*k.x_He*k.x_Xe^2*d.dC122_dT + k.x_Xe^3*d.dC222_dT;
d.d2C_dT2 = k.x_He^3*d.d2C111_dT2 + ...
    3*k.x_He^2*k.x_Xe*d.d2C112_dT2 + ...
    3*k.x_He*k.x_Xe^2*d.d2C122_dT2 + k.x_Xe^3*d.d2C222_dT2;
end

function [first, second] = secondVirialDerivatives(theta, criticalT, v, slope)
u = 102.732 - slope*theta - 0.44/theta^1.22;
t = tanh(4.5*sqrt(theta));
s2 = 1 - t^2;
du = -slope + 0.5368/theta^2.22;
dt = 2.25/sqrt(theta)*s2;
d2u = -1.191696/theta^3.22;
d2t = -1.125/theta^1.5*s2 - 10.125/theta*s2*t;
first = v*(du*t + u*dt)/criticalT;
second = v*(d2u*t + 2*du*dt + u*d2t)/criticalT^2;
end

function [first, second] = thirdVirialDerivatives(T, criticalT, v)
theta = T/criticalT;
t = tanh(0.84*theta);
s2 = 1 - t^2;
u = -0.0862 - 3.6e-5*theta + 0.0237/theta^0.059;
du = -3.6e-5 - 0.0013983/theta^1.059;
dt = 0.84*s2;
d2u = 0.0014808/theta^2.059;
d2t = -1.4112*s2*t;
first = v^2*(du*t + u*dt)/criticalT;
second = v^2*(d2u*t + 2*du*dt + u*d2t)/criticalT^2;
end

function fd = evaluateFiniteDifferences(T, analytic)
names = ["B11" "B22" "B12" "B" ...
    "C111" "C222" "C112" "C122" "C"];
% B'' needs a larger window to avoid subtractive cancellation, while C is
% evaluated close to the C111 zero and needs a smaller zero-not-crossing window.
% All estimates remain ordinary centered differences of coefficient values.
steps = [1.6; 0.8; 0.4; 1.6e-3; 8e-4; 4e-4; 2e-4; 1e-4];
BSecondWindow = 1:3;
BFirstWindow = 4:6;
CWindow = 6:8;
first = struct();
second = struct();
for name = names
    first.(name) = zeros(numel(steps), 1);
    second.(name) = zeros(numel(steps), 1);
end
center = evaluateVirialCoefficients(T);
for index = 1:numel(steps)
    h = steps(index);
    below = evaluateVirialCoefficients(T - h);
    above = evaluateVirialCoefficients(T + h);
    for name = names
        first.(name)(index) = (above.(name) - below.(name))/(2*h);
        second.(name)(index) = ...
            (above.(name) - 2*center.(name) + below.(name))/h^2;
    end
end
richardson = struct( ...
    "dB_dT", richardsonEvidence(first.B, steps, BFirstWindow), ...
    "d2B_dT2", richardsonEvidence(second.B, steps, BSecondWindow), ...
    "dC_dT", richardsonEvidence(first.C, steps, CWindow), ...
    "d2C_dT2", richardsonEvidence(second.C, steps, CWindow));
convergence = struct( ...
    "BFirst", convergenceEvidence(first.B, analytic.dB_dT, 1e-7, BFirstWindow), ...
    "BSecond", convergenceEvidence(second.B, analytic.d2B_dT2, 1e-5, BSecondWindow), ...
    "CFirst", convergenceEvidence(first.C, analytic.dC_dT, 2e-4, CWindow), ...
    "CSecond", convergenceEvidence(second.C, analytic.d2C_dT2, 2e-3, CWindow));
fd = struct("stepSizes_K", steps, "first", first, "second", second, ...
    "richardson", richardson, "convergence", convergence, ...
    "method", "independentCenteredEvaluationOfCoefficientFunctions");
end

function evidence = richardsonEvidence(estimates, steps, indices)
selected = estimates(indices);
selectedSteps = steps(indices);
evidence = struct( ...
    "stepIndices", indices, ...
    "stepSizes_K", selectedSteps, ...
    "estimates", selected, ...
    "extrapolated", (4*selected(end) - selected(end - 1))/3);
end

function evidence = convergenceEvidence(estimates, analytic, tolerance, indices)
selected = estimates(indices);
successiveDelta = abs(diff(selected));
ratio = successiveDelta(1)/successiveDelta(2);
relativeError = abs(selected(end) - analytic)/max(abs(analytic), realmin);
evidence = struct( ...
    "stepIndices", indices, ...
    "successiveDelta", successiveDelta, ...
    "observedRefinementRatio", ratio, ...
    "finalRelativeError", relativeError, ...
    "requiredRelativeError", tolerance, ...
    "success", isfinite(relativeError) && relativeError < tolerance);
end

function density = evaluateDensityRoots(T, P_Pa, values)
k = hexeConstants();
P_RT = P_Pa/(k.R0*T);
polynomialCoefficients = [values.C values.B 1 -P_RT];
allRoots = roots(polynomialCoefficients);
realTolerance = 1e-10;
isReal = abs(imag(allRoots)) <= realTolerance.*max(1, abs(allRoots));
realRoots = real(allRoots(isReal));
polynomialResiduals = polyval(polynomialCoefficients, allRoots);
eosPressureResiduals_Pa = k.R0*T*polynomialResiduals;
residualScales = abs(polynomialCoefficients(1))*abs(allRoots).^3 + ...
    abs(polynomialCoefficients(2))*abs(allRoots).^2 + ...
    abs(polynomialCoefficients(3))*abs(allRoots) + ...
    abs(polynomialCoefficients(4));
normalizedPolynomialResiduals = abs(polynomialResiduals)./residualScales;
template = struct("root", 0, "polynomialResidual", 0, ...
    "eosPressureResidual_Pa", 0, "dPdrho_Pa_m3_per_mol", 0, ...
    "stabilitySign", "zero");
realRootDiagnostics = repmat(template, numel(realRoots), 1);
for index = 1:numel(realRoots)
    rootValue = realRoots(index);
    realRootDiagnostics(index).root = rootValue;
    realRootDiagnostics(index).polynomialResidual = ...
        polyval(polynomialCoefficients, rootValue);
    realRootDiagnostics(index).eosPressureResidual_Pa = ...
        k.R0*T*realRootDiagnostics(index).polynomialResidual;
    derivative = k.R0*T*(1 + 2*values.B*rootValue + ...
        3*values.C*rootValue^2);
    realRootDiagnostics(index).dPdrho_Pa_m3_per_mol = derivative;
    realRootDiagnostics(index).stabilitySign = signLabel(derivative);
end

rhoHat = P_RT;
initialGuess = rhoHat;
converged = false;
lastDelta = NaN;
for iteration = 1:30
    f = polyval(polynomialCoefficients, rhoHat);
    df = 3*values.C*rhoHat^2 + 2*values.B*rhoHat + 1;
    lastDelta = f/df;
    rhoHat = rhoHat - lastDelta;
    if abs(lastDelta) < 1e-14
        converged = true;
        break
    end
end
rawFinal = rhoHat;
clampFloor = 0.9*P_RT;
clampedFinal = max(rawFinal, clampFloor);
productionNewton = struct( ...
    "initialGuess", initialGuess, ...
    "maximumIterations", 30, ...
    "deltaTolerance", 1e-14, ...
    "iterations", iteration, ...
    "converged", converged, ...
    "lastDelta", lastDelta, ...
    "rawFinal", rawFinal, ...
    "rawPolynomialResidual", polyval(polynomialCoefficients, rawFinal), ...
    "rawEosPressureResidual_Pa", ...
        k.R0*T*polyval(polynomialCoefficients, rawFinal), ...
    "clampFloor", clampFloor, ...
    "clampedFinal", clampedFinal, ...
    "clampedPolynomialResidual", ...
        polyval(polynomialCoefficients, clampedFinal), ...
    "clampChanged", clampedFinal ~= rawFinal);
density = struct( ...
    "status", "computedInTask2", ...
    "P_RT", P_RT, ...
    "polynomialCoefficients", polynomialCoefficients, ...
    "allRoots", allRoots, ...
    "realTolerance", realTolerance, ...
    "isReal", isReal, ...
    "realRoots", realRoots, ...
    "polynomialResiduals", polynomialResiduals, ...
    "polynomialResidualScales", residualScales, ...
    "normalizedPolynomialResiduals", normalizedPolynomialResiduals, ...
    "eosPressureResiduals_Pa", eosPressureResiduals_Pa, ...
    "realRootDiagnostics", realRootDiagnostics, ...
    "productionNewton", productionNewton);
end

function label = signLabel(value)
if value > 0
    label = "positive";
elseif value < 0
    label = "negative";
else
    label = "zero";
end
end

function diagnostic = evaluateThermalDiagnostic(T, values, d, rhoHat)
k = hexeConstants();
drhoNumerator = (rhoHat + values.B*rhoHat^2 + values.C*rhoHat^3)/T + ...
    d.dB_dT*rhoHat^2 + d.dC_dT*rhoHat^3;
drhoDenominator = 1 + 2*values.B*rhoHat + 3*values.C*rhoHat^2;
drhoHat_dT = -drhoNumerator/drhoDenominator;
cvMolar = 1.5*k.R0 - rhoHat*k.R0*T*( ...
    2*d.dB_dT + T*d.d2B_dT2 + ...
    rhoHat*(d.dC_dT + 0.5*T*d.d2C_dT2));
B1 = values.B - T*d.dB_dT;
B2 = B1 - T^2*d.d2B_dT2;
C1 = 2*values.C - T*d.dC_dT;
C2 = values.C - 0.5*T^2*d.d2C_dT2;
cpMolar = 2.5*k.R0 + rhoHat*k.R0*(B2 + rhoHat*C2) + ...
    k.R0*T*(B1 + rhoHat*C1)*drhoHat_dT;
diagnostic = struct( ...
    "rhoHat", rhoHat, ...
    "drhoHat_dT", drhoHat_dT, ...
    "cpMolar", cpMolar, ...
    "cvMolar", cvMolar, ...
    "cpMass", cpMolar/k.M, ...
    "cvMass", cvMolar/k.M, ...
    "gamma", cpMolar/cvMolar, ...
    "rho", rhoHat*k.M);
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

function placeholder = laterTaskPlaceholder()
placeholder = struct("status", "notComputedInTask2", ...
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
