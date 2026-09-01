function C = paper54_constants()
%PAPER54_CONSTANTS Thesis literals and reproducible calculated consequences.
%
% Direct values are from Xu Chi, Table 5.2 and Section 5.3.1. Calculated
% values below retain their complete formulas and are not thesis literals.

C.source.document = ...
    'Xu Chi thesis: Table 5.2, Eqs. (5.17)-(5.18), Sections 5.3.1 and 5.4';
C.source.pdf_page_table52 = 104;
C.source.pdf_page_rotor_equations = 102;

% Thesis direct values.
C.N_rpm = 55090;
C.compressor.Tin_K = 405.16;
C.compressor.Pin_Pa = 0.658e6;
C.compressor.Tout_K = 601.90;
C.compressor.Pout_Pa = 1.551e6;
C.compressor.power_W = 1231.6e3;
C.turbine.power_W = 2252.2e3;
C.generator.electric_power_W = 1000.21e3;

% Additional Table 5.2 simulation-result boundaries used by the coupled
% steady-state audit. These are direct thesis values, not fitted states.
C.reactor.inlet_T_K = 1443.27;
C.reactor.outlet_T_K = 1600.00;
C.reactor.outlet_P_Pa = 0.234e6;
C.turbine.Tin_K = 1522.96;
C.turbine.Pin_Pa = 1.539e6;
C.turbine.Tout_K = 1162.00;
C.turbine.Pout_Pa = 0.676e6;
C.recuperator.hot_out_T_K = 663.63;
C.recuperator.hot_out_P_Pa = 0.676e6;
C.recuperator.cold_out_T_K = 1100.91;
C.recuperator.cold_out_P_Pa = 1.543e6;
C.cooler.cold_inlet_T_K = 360.10;
C.cooler.cold_out_T_K = 609.58;
C.cooler.cold_inlet_P_Pa = 0.200e6;

% Reproducible consequences of the thesis values above.
C.compressor.PR = ...
    C.compressor.Pout_Pa / C.compressor.Pin_Pa;
C.generator.eta_calculated = C.generator.electric_power_W / ...
    (C.turbine.power_W - C.compressor.power_W);
C.generator.shaft_power_W = C.generator.electric_power_W / ...
    C.generator.eta_calculated;
end
