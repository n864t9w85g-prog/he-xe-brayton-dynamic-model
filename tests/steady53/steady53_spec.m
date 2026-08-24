function s = steady53_spec()
%STEADY53_SPEC Approved nominal steady-state targets and acceptance gates.

s = struct();
s.stopTime_s = 14000;
s.finalWindow_s = [13000 14000];
s.outputRelTol = 0.01;
s.windowPeakToPeakTol = 0.001;
s.windowTrendTol = 0.0001;
s.massClosureTol = 1e-6;
s.requiredIndependentRuns = 2;

s.property.HeXe_K = [100 2000];
s.property.Lithium_K = [453.7 1608];

s.scale.temperature_K = 1;
s.scale.pressure_Pa = 1;
s.scale.massFlow_kg_s = 1;
s.scale.power_W = 1;
s.scale.speed_rpm = 1;
s.scale.other = 1;

s.speedAbsTol_rpm = 1;

name = [
    "reactor_inlet_T"
    "reactor_outlet_T"
    "turbine_inlet_T"
    "turbine_inlet_P"
    "turbine_outlet_T"
    "turbine_outlet_P"
    "compressor_inlet_T"
    "compressor_inlet_P"
    "compressor_outlet_T"
    "compressor_outlet_P"
    "recuperator_hot_outlet_T"
    "recuperator_hot_outlet_P"
    "recuperator_cold_outlet_T"
    "recuperator_cold_outlet_P"
    "cooler_cold_inlet_T"
    "cooler_cold_outlet_T"
    "reactor_power"
    "turbine_power"
    "compressor_power"
    "tac_electric_power"
    "rotor_speed"
    ];

target = [
    1443.27
    1600.00
    1522.96
    1.539e6
    1162.00
    0.676e6
    405.16
    0.658e6
    601.90
    1.551e6
    663.63
    0.676e6
    1100.91
    1.543e6
    360.10
    609.58
    2664e3
    2252.2e3
    1231.6e3
    1000.21e3
    55090
    ];

unit = [
    "K"
    "K"
    "K"
    "Pa"
    "K"
    "Pa"
    "K"
    "Pa"
    "K"
    "Pa"
    "K"
    "Pa"
    "K"
    "Pa"
    "K"
    "K"
    "W"
    "W"
    "W"
    "W"
    "rpm"
    ];

relTol = repmat(s.outputRelTol, 21, 1);
relTol(end) = s.speedAbsTol_rpm / target(end);

settleDeadline_s = [
    75
    NaN
    75
    NaN
    300
    NaN
    75
    NaN
    300
    NaN
    180
    NaN
    180
    NaN
    180
    75
    300
    300
    300
    300
    0
    ];

s.metrics = table(name, target, unit, relTol, settleDeadline_s);
end
