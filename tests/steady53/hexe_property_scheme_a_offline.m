function [cpMass, gamma, rho, audit] = ...
        hexe_property_scheme_a_offline(T_K, P_Pa)
%HEXE_PROPERTY_SCHEME_A_OFFLINE H2a Scheme A thermodynamic evaluator.
%   Exploration-only pure evaluator. Scheme A removes the helium pure
%   third-Virial term before the current mixing rule. It does not call or
%   modify the formal property implementation and does not calculate
%   transport properties.

validateInput(T_K, P_Pa);
k = hexeConstants();
[b, dB, d2B] = secondVirialTerms(T_K, k);
[c, dc, d2c] = schemeAThirdVirialTerms(T_K, k);
density = densityState(T_K, P_Pa, b.B, c.C, k.R0);
thermal = thermalState(T_K, b.B, dB, d2B, c.C, dc.C, d2c.C, ...
    density.rhoHat, k);

cpMass = thermal.cpMass;
gamma = thermal.gamma;
rho = thermal.rho;
audit = struct( ...
    "T_K", T_K, "P_Pa", P_Pa, "xHe", k.xHe, "xXe", k.xXe, ...
    "B11", b.B11, "B22", b.B22, "B12", b.B12, "B", b.B, ...
    "dB_dT", dB, "d2B_dT2", d2B, ...
    "C111", c.C111, "C222", c.C222, ...
    "C112", c.C112, "C122", c.C122, "C", c.C, ...
    "dC111_dT", dc.C111, "dC222_dT", dc.C222, ...
    "dC112_dT", dc.C112, "dC122_dT", dc.C122, ...
    "dC_dT", dc.C, ...
    "d2C111_dT2", d2c.C111, "d2C222_dT2", d2c.C222, ...
    "d2C112_dT2", d2c.C112, "d2C122_dT2", d2c.C122, ...
    "d2C_dT2", d2c.C, ...
    "rhoHat", density.rhoHat, "rho", thermal.rho, ...
    "dPdrho", density.dPdrho, ...
    "stablePositiveRealRootCount", ...
        density.stablePositiveRealRootCount, ...
    "eos", density.eos, "productionNewton", density.productionNewton, ...
    "cpMolar", thermal.cpMolar, "cvMolar", thermal.cvMolar, ...
    "cpMass", thermal.cpMass, "cvMass", thermal.cvMass, ...
    "gamma", thermal.gamma, "drhoHat_dT", thermal.drhoHat_dT, ...
    "contributions", thermal.contributions, ...
    "variant", "ignoreHePureThirdVirialBeforeCurrentMixingRule");
end

function validateInput(T_K, P_Pa)
validT = isnumeric(T_K) && isscalar(T_K) && isreal(T_K) && ...
    isfinite(T_K) && T_K > 0;
validP = isnumeric(P_Pa) && isscalar(P_Pa) && isreal(P_Pa) && ...
    isfinite(P_Pa) && P_Pa > 0;
if ~validT || ~validP
    error("steady53:SchemeAInvalidInput", ...
        "T_K and P_Pa must be finite, real, positive numeric scalars.");
end
end

function k = hexeConstants()
k = struct("R0", 8.314, "MHe", 4.0026e-3, ...
    "MXe", 131.293e-3, "xHe", 0.7172, "xXe", 1.0 - 0.7172, ...
    "TcHe", 5.19, "TcXe", 289.6, "rhoCHe", 69.64, ...
    "rhoCXe", 1099.7);
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
b.B = k.xHe^2*b.B11 + 2*k.xHe*k.xXe*b.B12 + ...
    k.xXe^2*b.B22;
dB11 = (-.0018 - 57.5/T^(3/2) + 835/T^2)*1e-6;
d2B11 = (86.25/T^2.5 - 1670/T^3)*1e-6;
[dB22, d2B22] = secondVirialDerivatives( ...
    thetaXe, k.TcXe, k.vXe, .01);
[dB12, d2B12] = secondVirialDerivatives( ...
    theta12, k.Tc12, k.v12, .001);
dB = k.xHe^2*dB11 + 2*k.xHe*k.xXe*dB12 + k.xXe^2*dB22;
d2B = k.xHe^2*d2B11 + 2*k.xHe*k.xXe*d2B12 + ...
    k.xXe^2*d2B22;
end

function B = secondVirial(theta, v, slope)
u = 102.732 - slope*theta - .44/theta^1.22;
B = v*(-102.6 + u*tanh(4.5*sqrt(theta)));
end

function [first, second] = secondVirialDerivatives( ...
        theta, criticalT, v, slope)
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

function [c, dc, d2c] = schemeAThirdVirialTerms(T, k)
[~, ~, ~] = thirdComponent(T, k.vHe, k.TcHe);
[C222, dC222, d2C222] = thirdComponent(T, k.vXe, k.TcXe);
c = struct("C111", 0, "C222", C222, "C112", 0, "C122", 0, ...
    "C", k.xXe^3*C222);
dc = struct("C111", 0, "C222", dC222, "C112", 0, "C122", 0, ...
    "C", k.xXe^3*dC222);
d2c = struct("C111", 0, "C222", d2C222, ...
    "C112", 0, "C122", 0, "C", k.xXe^3*d2C222);
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

function density = densityState(T, P, B, C, R0)
P_RT = P/(R0*T);
coefficients = [C B 1 -P_RT];
allRoots = roots(coefficients);
residual = polyval(coefficients, allRoots);
scale = abs(C)*abs(allRoots).^3 + abs(B)*abs(allRoots).^2 + ...
    abs(allRoots) + abs(P_RT);
slopes = R0*T*(1 + 2*B*allRoots + 3*C*allRoots.^2);
isReal = abs(imag(allRoots)) <= 1e-10*max(1, abs(allRoots));
stablePositiveCount = nnz(isReal & real(allRoots) > 0 & ...
    real(slopes) > 0);
rhoHat = P_RT;
converged = false;
lastDelta = NaN;
for iteration = 1:30
    f = polyval(coefficients, rhoHat);
    derivative = 3*C*rhoHat^2 + 2*B*rhoHat + 1;
    lastDelta = f/derivative;
    rhoHat = rhoHat - lastDelta;
    if abs(lastDelta) < 1e-14
        converged = true;
        break
    end
end
raw = rhoHat;
clampFloor = .9*P_RT;
rhoHat = max(raw, clampFloor);
dPdrho = R0*T*(1 + 2*B*rhoHat + 3*C*rhoHat^2);
productionNewton = struct("initialGuess", P_RT, ...
    "maximumIterations", 30, "deltaTolerance", 1e-14, ...
    "iterations", iteration, "converged", converged, ...
    "lastDelta", lastDelta, "rawFinal", raw, ...
    "clampFloor", clampFloor, "clampedFinal", rhoHat, ...
    "clampChanged", rhoHat ~= raw, ...
    "rawPolynomialResidual", polyval(coefficients, raw));
eos = struct("polynomialCoefficients", coefficients, ...
    "allRoots", allRoots, "scaledResidual", abs(residual)./scale, ...
    "dPdrho", slopes);
density = struct("rhoHat", rhoHat, "dPdrho", dPdrho, ...
    "stablePositiveRealRootCount", stablePositiveCount, ...
    "productionNewton", productionNewton, "eos", eos);
end

function thermal = thermalState(T, B, dB, d2B, C, dC, d2C, ...
        rhoHat, k)
drhoNumerator = (rhoHat + B*rhoHat^2 + C*rhoHat^3)/T + ...
    dB*rhoHat^2 + dC*rhoHat^3;
drhoDenominator = 1 + 2*B*rhoHat + 3*C*rhoHat^2;
drho = -drhoNumerator/drhoDenominator;
B1 = B - T*dB;
B2 = B1 - T^2*d2B;
C1 = 2*C - T*dC;
C2 = C - .5*T^2*d2C;
cpIdeal = 2.5*k.R0;
cpB = rhoHat*k.R0*B2;
cpC = rhoHat^2*k.R0*C2;
cpDensityB = k.R0*T*B1*drho;
cpDensityC = k.R0*T*rhoHat*C1*drho;
cpMolar = cpIdeal + cpB + cpC + cpDensityB + cpDensityC;
cvIdeal = 1.5*k.R0;
cvB = -rhoHat*k.R0*T*(2*dB + T*d2B);
cvC = -rhoHat^2*k.R0*T*(dC + .5*T*d2C);
cvMolar = cvIdeal + cvB + cvC;
contributions = struct( ...
    "cpMolar", struct("ideal", cpIdeal, "BExplicit", cpB, ...
        "CExplicit", cpC, "densityDerivativeB", cpDensityB, ...
        "densityDerivativeC", cpDensityC, ...
        "densityDerivativeTotal", cpDensityB + cpDensityC, ...
        "total", cpMolar), ...
    "cvMolar", struct("ideal", cvIdeal, "B", cvB, ...
        "C", cvC, "total", cvMolar));
thermal = struct("rho", rhoHat*k.M, "drhoHat_dT", drho, ...
    "cpMolar", cpMolar, "cvMolar", cvMolar, ...
    "cpMass", cpMolar/k.M, "cvMass", cvMolar/k.M, ...
    "gamma", cpMolar/cvMolar, "contributions", contributions);
end
