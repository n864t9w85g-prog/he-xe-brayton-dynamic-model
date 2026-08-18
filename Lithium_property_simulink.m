function [cp_mass, gamma, rho, miu, lambda, Pr] = ...
        Lithium_property_simulink(T, P_Pa)
% Lithium_property_simulink  Liquid-lithium properties for the IHX.
%
% The correlations are kept in this external file so every Simulink
% MATLAB Function block remains a thin caller.  Source:
% Williams, Coleman and Yarbrough, ORNL/TM-10622, OSTI 5313590:
%   density       Eq. (2), printed page 3
%   cp            Eq. (8), printed page 7
%   vapor pressure Eq. (9), printed page 8
%   compressibility Eq. (11), printed page 9
%   viscosity     Eq. (12), printed page 12
%   conductivity  Eq. (16), printed page 17
%
% Inputs:
%   T    - local temperature (K)
%   P_Pa - local absolute pressure (Pa)
%
% Outputs (same order as HeXe_property_simulink):
%   cp_mass - mass-based constant-pressure heat capacity (J/kg/K)
%   gamma   - cp/cv, obtained from Eq. (11) and cp-cv identity
%   rho     - density (kg/m^3)
%   miu     - dynamic viscosity (Pa*s)
%   lambda  - thermal conductivity (W/m/K)
%   Pr      - Prandtl number (-)

if ~(isnumeric(T) && isscalar(T) && isreal(T) && isfinite(T))
    error('Lithium_property_simulink:InvalidTemperature', ...
        'T must be a finite real numeric scalar.');
end
persistent warned_lo warned_hi
if isempty(warned_lo), warned_lo = false; end
if isempty(warned_hi), warned_hi = false; end

CLAMP_LO = 453.7;
CLAMP_HI = 1608.0;

if T < CLAMP_LO
    if ~warned_lo
        warning('Lithium_property_simulink:TemperatureBelowRange', ...
            'T=%.4g K < %.1f K (Li melting). Clamping to %.1f K. (suppressed further)', ...
            T, CLAMP_LO, CLAMP_LO);
        warned_lo = true;
    end
    T = CLAMP_LO;
elseif T > CLAMP_HI
    if ~warned_hi
        warning('Lithium_property_simulink:TemperatureAboveRange', ...
            'T=%.4g K > %.1f K (ORNL fit limit). Clamping to %.1f K. (suppressed further)', ...
            T, CLAMP_HI, CLAMP_HI);
        warned_hi = true;
    end
    T = CLAMP_HI;
end
if ~(isnumeric(P_Pa) && isscalar(P_Pa) && isreal(P_Pa) && ...
        isfinite(P_Pa) && P_Pa > 0)
    error('Lithium_property_simulink:InvalidPressure', ...
        'P_Pa must be a finite positive real numeric scalar.');
end

% Eq. (9) is used only to reject a vapor-region operating point.  The
% recommended transport and heat-capacity correlations are temperature fits.
P_sat = 10.^(-7975.6 ./ T + 9.9624);  % Pa
if P_Pa < P_sat(1)
    error('Lithium_property_simulink:BelowSaturationPressure', ...
        'P_Pa is below the ORNL liquid-lithium saturation pressure.');
end

% Eq. (8), originally reported in kJ/(kg*K).
cp_mass = 1000 .* (1.044e5 ./ T.^2 - 135.1 ./ T + 4.180);

% Eq. (2), originally reported in Mg/m^3 (numerically g/cm^3).
rho = 1000 .* (0.5584 - 1.01e-4 .* T);

% Eq. (12), originally reported in mPa*s.
miu = 1e-3 .* (0.1157 - 1.418e-4 .* T + ...
    4.229e-8 .* T.^2 + 243.7 ./ T);

% Eq. (16).
lambda = 21.42 + 0.05230 .* T - 1.371e-5 .* T.^2;

% Eq. (11) and the thermodynamic identity cp-cv = T*alpha^2/(rho*kappa_T).
kappa_T = 8.366e-11 + 2.0706e-14 .* T + 4.665e-17 .* T.^2;
alpha_v = 1.01e-4 ./ (0.5584 - 1.01e-4 .* T);
cv_mass = cp_mass - T .* alpha_v.^2 ./ (rho .* kappa_T);
gamma = cp_mass ./ cv_mass;

Pr = cp_mass .* miu ./ lambda;
end
