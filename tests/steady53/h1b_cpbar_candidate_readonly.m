function result = h1b_cpbar_candidate_readonly( ...
    inputs, pathVariant, propertyFunction, numerics)
%H1B_CPBar_CANDIDATE_READONLY Solve one offline path-average cp candidate.

validateInputs(inputs);
validatePathVariant(pathVariant);
validatePropertyFunction(propertyFunction);
validateNumerics(numerics);

cpBarIsentropic = pathAverageCp(inputs.T2s_K, inputs, pathVariant, ...
    propertyFunction, numerics);
residual = @(T2_K) turbineResidual(T2_K, cpBarIsentropic, inputs, ...
    pathVariant, propertyFunction, numerics);
bracket = [inputs.T2s_K inputs.T1_K];
residualLow = residual(bracket(1));
residualHigh = residual(bracket(2));

if residualLow == 0
    T2_K = bracket(1);
    rootFunctionValue = residualLow;
    exitflag = 1;
elseif residualHigh == 0
    T2_K = bracket(2);
    rootFunctionValue = residualHigh;
    exitflag = 1;
elseif sign(residualLow) == sign(residualHigh)
    error("steady53:H1bNoBracket", ...
        "The fixed [T2s,T1] bracket does not contain a sign change.");
else
    rootOptions = optimset("TolX", numerics.rootTolX_K, ...
        "MaxIter", numerics.rootMaxIterations, ...
        "MaxFunEvals", numerics.rootMaxFunctionEvaluations, ...
        "Display", "off");
    try
        [T2_K, rootFunctionValue, exitflag] = numerics.rootFunction( ...
            residual, bracket, rootOptions);
    catch exception
        failure = MException("steady53:H1bRootFailed", ...
            "The bracketed H1b root solve failed.");
        failure = addCause(failure, exception);
        throw(failure);
    end
end

if ~isFiniteRealScalar(T2_K) || exitflag <= 0 || ...
        T2_K < bracket(1) || T2_K > bracket(2)
    error("steady53:H1bRootFailed", ...
        "The bracketed H1b root solve did not converge inside the bracket.");
end
rootResidual_K = residual(T2_K);
if ~isFiniteRealScalar(rootFunctionValue) || ...
        ~isFiniteRealScalar(rootResidual_K) || ...
        abs(rootResidual_K) > numerics.rootAbsResidualTolerance_K
    error("steady53:H1bRootFailed", ...
        "The H1b root residual is invalid or exceeds its tolerance.");
end

cpBarActual = pathAverageCp(T2_K, inputs, pathVariant, ...
    propertyFunction, numerics);
idealPathAudit = auditPath(inputs.T2s_K, inputs, pathVariant, ...
    propertyFunction, numerics.auditSampleCount);
actualPathAudit = auditPath(T2_K, inputs, pathVariant, ...
    propertyFunction, numerics.auditSampleCount);

result = struct( ...
    "pathVariant", pathVariant, ...
    "cpBarIsentropic_J_kgK", cpBarIsentropic, ...
    "cpBarActual_J_kgK", cpBarActual, ...
    "cpBarRatio", cpBarIsentropic/cpBarActual, ...
    "T2_K", T2_K, ...
    "rootResidual_K", rootResidual_K, ...
    "rootBracket_K", bracket, ...
    "integrationCompleted", true, ...
    "rootConverged", true, ...
    "idealPathAudit", idealPathAudit, ...
    "actualPathAudit", actualPathAudit, ...
    "numerics", numerics);
end

function validateInputs(inputs)
required = ["T1_K" "P1_Pa" "P2_Pa" "T2s_K" "eta"];
if ~isScalarStructWithExactFields(inputs, required)
    error("steady53:H1bInvalidInput", ...
        "inputs must be a scalar struct with the exact required fields.");
end
positiveFields = ["T1_K" "P1_Pa" "P2_Pa" "T2s_K"];
for field = positiveFields
    if ~isFiniteRealScalar(inputs.(field)) || inputs.(field) <= 0
        error("steady53:H1bInvalidInput", ...
            "%s must be a finite positive real scalar.", field);
    end
end
if inputs.T2s_K >= inputs.T1_K || ~isFiniteRealScalar(inputs.eta) || ...
        inputs.eta <= 0 || inputs.eta >= 1
    error("steady53:H1bInvalidInput", ...
        "Require 0<T2s<T1 and 0<eta<1.");
end
end

function validatePathVariant(pathVariant)
allowed = ["linearEndpointPressure" "constantP1" "constantP2"];
if ~isstring(pathVariant) || ~isscalar(pathVariant) || ...
        ~any(pathVariant == allowed)
    error("steady53:H1bInvalidPathVariant", ...
        "Unknown H1b pressure-path variant.");
end
end

function validatePropertyFunction(propertyFunction)
if ~isa(propertyFunction, "function_handle") || ~isscalar(propertyFunction)
    error("steady53:H1bInvalidInput", ...
        "propertyFunction must be a scalar function handle.");
end
end

function validateNumerics(numerics)
required = ["integralFunction" "rootFunction" "integralRelTol" ...
    "integralAbsTol_J_kgK" "rootTolX_K" "rootMaxIterations" ...
    "rootMaxFunctionEvaluations" "rootAbsResidualTolerance_K" ...
    "auditSampleCount"];
if ~isScalarStructWithExactFields(numerics, required)
    error("steady53:H1bInvalidInput", ...
        "numerics must be a scalar struct with the exact required fields.");
end
if ~isa(numerics.integralFunction, "function_handle") || ...
        ~isscalar(numerics.integralFunction) || ...
        ~isa(numerics.rootFunction, "function_handle") || ...
        ~isscalar(numerics.rootFunction)
    error("steady53:H1bInvalidInput", ...
        "The injected numerical functions must be scalar function handles.");
end
positiveScalars = ["integralRelTol" "integralAbsTol_J_kgK" ...
    "rootTolX_K" "rootAbsResidualTolerance_K"];
for field = positiveScalars
    if ~isFiniteRealScalar(numerics.(field)) || numerics.(field) <= 0
        error("steady53:H1bInvalidInput", ...
            "%s must be a finite positive real scalar.", field);
    end
end
positiveIntegers = ["rootMaxIterations" ...
    "rootMaxFunctionEvaluations" "auditSampleCount"];
for field = positiveIntegers
    value = numerics.(field);
    if ~isFiniteRealScalar(value) || value <= 0 || value ~= fix(value)
        error("steady53:H1bInvalidInput", ...
            "%s must be a finite positive integer.", field);
    end
end
if numerics.auditSampleCount ~= 1001
    error("steady53:H1bInvalidInput", ...
        "auditSampleCount must equal the approved value 1001.");
end
end

function valid = isScalarStructWithExactFields(value, required)
valid = isstruct(value) && isscalar(value);
if valid
    actual = sort(string(fieldnames(value)));
    valid = isequal(actual(:), sort(required(:)));
end
end

function value = pathAverageCp(Tout_K, inputs, pathVariant, ...
    propertyFunction, numerics)
integrand = @(lambda) cpAtPathPoint(lambda, Tout_K, inputs, ...
    pathVariant, propertyFunction);
try
    value = numerics.integralFunction(integrand, 0, 1, ...
        "RelTol", numerics.integralRelTol, ...
        "AbsTol", numerics.integralAbsTol_J_kgK, ...
        "ArrayValued", true);
catch exception
    if exceptionContainsIdentifier(exception, ...
            ["steady53:H1bPropertyWarning" "steady53:H1bInvalidProperty"])
        throw(exception);
    end
    failure = MException("steady53:H1bIntegrationFailed", ...
        "The H1b path-average cp integration failed.");
    failure = addCause(failure, exception);
    throw(failure);
end
if ~isFiniteRealScalar(value) || value <= 0
    error("steady53:H1bIntegrationFailed", ...
        "The H1b path-average cp integral is not finite and positive.");
end
end

function cp = cpAtPathPoint(lambda, Tout_K, inputs, pathVariant, ...
    propertyFunction)
[T_K, P_Pa] = pathPoint(lambda, Tout_K, inputs, pathVariant);
[cp, ~, ~, ~] = propertyState(T_K, P_Pa, propertyFunction);
end

function residual_K = turbineResidual(T2_K, cpBarIsentropic, inputs, ...
    pathVariant, propertyFunction, numerics)
cpBarActual = pathAverageCp(T2_K, inputs, pathVariant, ...
    propertyFunction, numerics);
predictedT2_K = inputs.T1_K-inputs.eta* ...
    (cpBarIsentropic/cpBarActual)*(inputs.T1_K-inputs.T2s_K);
residual_K = T2_K-predictedT2_K;
end

function audit = auditPath(Tout_K, inputs, pathVariant, ...
    propertyFunction, sampleCount)
lambda = linspace(0, 1, sampleCount).';
[T_K, P_Pa] = pathPoint(lambda, Tout_K, inputs, pathVariant);
cp = zeros(sampleCount, 1);
gamma = zeros(sampleCount, 1);
rho = zeros(sampleCount, 1);
cv = zeros(sampleCount, 1);
for index = 1:sampleCount
    [cp(index), gamma(index), rho(index), cv(index)] = propertyState( ...
        T_K(index), P_Pa(index), propertyFunction);
end
audit = struct( ...
    "sampleCount", sampleCount, ...
    "minCpMass_J_kgK", min(cp, [], "all"), ...
    "maxCpMass_J_kgK", max(cp, [], "all"), ...
    "minCvMass_J_kgK", min(cv, [], "all"), ...
    "maxCvMass_J_kgK", max(cv, [], "all"), ...
    "minGamma", min(gamma, [], "all"), ...
    "maxGamma", max(gamma, [], "all"), ...
    "minRho_kg_m3", min(rho, [], "all"), ...
    "maxRho_kg_m3", max(rho, [], "all"), ...
    "allPhysical", true, ...
    "formalGlobalProof", false, ...
    "classification", "finite1001PointAuditNotFormalGlobalProof");
end

function [T_K, P_Pa] = pathPoint(lambda, Tout_K, inputs, pathVariant)
T_K = inputs.T1_K+lambda*(Tout_K-inputs.T1_K);
switch pathVariant
    case "linearEndpointPressure"
        P_Pa = inputs.P1_Pa+lambda*(inputs.P2_Pa-inputs.P1_Pa);
    case "constantP1"
        P_Pa = inputs.P1_Pa+zeros(size(lambda));
    case "constantP2"
        P_Pa = inputs.P2_Pa+zeros(size(lambda));
    otherwise
        error("steady53:H1bInvalidPathVariant", ...
            "Unknown H1b pressure-path variant.");
end
end

function [cp, gamma, rho, cv] = propertyState( ...
    T_K, P_Pa, propertyFunction)
warningState = warning;
[lastWarningMessage, lastWarningIdentifier] = lastwarn;
cleanup = onCleanup(@() restoreWarningState( ...
    warningState, lastWarningMessage, lastWarningIdentifier));
warning("off", "all");
lastwarn("", "");
propertyException = [];
try
    [cp, gamma, rho] = propertyFunction(T_K, P_Pa);
catch exception
    propertyException = exception;
end
[propertyWarningMessage, propertyWarningIdentifier] = lastwarn;
clear cleanup
if strlength(string(propertyWarningIdentifier)) > 0
    warningCause = MException(propertyWarningIdentifier, ...
        "%s", propertyWarningMessage);
    failure = MException("steady53:H1bPropertyWarning", ...
        "The H1b property evaluation emitted a warning.");
    failure = addCause(failure, warningCause);
    if ~isempty(propertyException)
        failure = addCause(failure, propertyException);
    end
    throw(failure);
end
if ~isempty(propertyException)
    throw(propertyException);
end
cv = cp./gamma;
quantities = {cp, gamma, rho, cv};
if ~all(cellfun(@isFiniteRealArray, quantities), "all") || ...
        ~isequal(size(cp), size(gamma), size(rho), size(cv)) || ...
        any(cp <= 0, "all") || any(gamma <= 1, "all") || ...
        any(cv <= 0, "all") || any(rho <= 0, "all")
    error("steady53:H1bInvalidProperty", ...
        "Property values must be finite, real, shape-consistent, and physical.");
end

function restoreWarningState(warningState, message, identifier)
warning(warningState);
lastwarn(message, identifier);
end
end

function valid = isFiniteRealArray(value)
valid = isnumeric(value) && ~isempty(value) && isreal(value) && ...
    all(isfinite(value), "all");
end

function valid = isFiniteRealScalar(value)
valid = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
end

function found = exceptionContainsIdentifier(exception, identifiers)
found = any(string(exception.identifier) == identifiers);
pending = exception.cause(:);
while ~found && ~isempty(pending)
    current = pending{1};
    pending(1) = [];
    found = any(string(current.identifier) == identifiers);
    pending = [pending; current.cause(:)]; %#ok<AGROW>
end
end
