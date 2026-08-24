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
s.scale.dimensionless = 1;
s.scale.other = 1;

s.requiredLookupNames = [ ...
    "compressor_efficiency_speed"
    "compressor_efficiency_flow"
    "compressor_pressure_ratio_speed"
    "compressor_pressure_ratio_flow"
    "turbine_flow_expansion_ratio"
    "turbine_flow_speed"
    "turbine_efficiency_mass_flow"
    "turbine_efficiency_speed"];

signalName = [ ...
    "reactor_inlet_T"
    "turbine_inlet_P"
    "turbine_inlet_T"
    "reactor_outlet_T"
    "turbine_outlet_P"
    "turbine_outlet_T"
    "compressor_outlet_T"
    "compressor_outlet_P"
    "recuperator_hot_outlet_T"
    "recuperator_hot_outlet_P"
    "recuperator_cold_outlet_P"
    "recuperator_cold_outlet_T"
    "compressor_inlet_P"
    "compressor_inlet_T"
    "cooler_cold_outlet_T"
    "cooler_cold_inlet_T"
    "turbine_power"
    "compressor_power"
    "rotor_speed"
    "turbine_expansion_ratio"
    "hexe_mdot_turbine"
    "hexe_mdot_compressor"
    "hexe_mdot_ihx"
    "hexe_mdot_recup_hot"
    "hexe_mdot_recup_cold"
    "lithium_mdot_reactor"
    "lithium_mdot_ihx"
    "compressor_lookup_speed_eff"
    "compressor_lookup_flow_eff"
    "compressor_lookup_speed_pr"
    "compressor_lookup_flow_pr"
    "turbine_lookup_expansion_ratio"
    "turbine_lookup_speed_flow"
    "turbine_lookup_mass_flow"
    "turbine_lookup_speed_eff"
    "reactor_power"
    "tac_electric_power"];
signalKind = [ ...
    "temperature"; "pressure"; "temperature"; "temperature"; ...
    "pressure"; "temperature"; "temperature"; "pressure"; ...
    "temperature"; "pressure"; "pressure"; "temperature"; ...
    "pressure"; "temperature"; "temperature"; "temperature"; ...
    "power"; "power"; "speed"; "dimensionless"; ...
    repmat("massFlow", 7, 1); ...
    "dimensionless"; "dimensionless"; "dimensionless"; ...
    "dimensionless"; "dimensionless"; "speed"; "massFlow"; ...
    "speed"; "power"; "power"];
signalConstant = false(37, 1);
signalConstant([19 26 27 28 30 33 35]) = true;
signalScaleFloor = ones(37, 1);
s.signalMetadata = table(signalName, signalKind, signalConstant, ...
    signalScaleFloor, 'VariableNames', ...
    {'name', 'kind', 'constant', 'scaleFloor'});

assert(numel(s.requiredLookupNames) == 8 && ...
    numel(unique(s.requiredLookupNames)) == 8, ...
    "steady53_spec requires eight unique lookup names.");
assert(height(s.signalMetadata) == 37 && ...
    numel(unique(s.signalMetadata.name)) == 37, ...
    "steady53_spec requires 37 unique signal metadata rows.");

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

relTol = repmat(s.outputRelTol, numel(name), 1);
speedRow = name == "rotor_speed";
assert(nnz(speedRow) == 1, "Expected exactly one rotor_speed metric.");
relTol(speedRow) = s.speedAbsTol_rpm / target(speedRow);

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
