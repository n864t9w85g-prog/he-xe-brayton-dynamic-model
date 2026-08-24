function tests = test_steady53_spec
tests = functiontests(localfunctions);
end

function testApprovedRunAndAcceptanceThresholds(testCase)
s = steady53_spec();

verifyEqual(testCase, s.stopTime_s, 14000);
verifyEqual(testCase, s.finalWindow_s, [13000 14000]);
verifyEqual(testCase, s.outputRelTol, 0.01);
verifyEqual(testCase, s.windowPeakToPeakTol, 0.001);
verifyEqual(testCase, s.windowTrendTol, 0.0001);
verifyEqual(testCase, s.massClosureTol, 1e-6);
verifyEqual(testCase, s.property.HeXe_K, [100 2000]);
verifyEqual(testCase, s.property.Lithium_K, [453.7 1608]);
verifyEqual(testCase, s.requiredIndependentRuns, 2);
verifyEqual(testCase, s.scale.temperature_K, 1);
verifyEqual(testCase, s.scale.pressure_Pa, 1);
verifyEqual(testCase, s.scale.massFlow_kg_s, 1);
verifyEqual(testCase, s.scale.power_W, 1);
verifyEqual(testCase, s.scale.speed_rpm, 1);
verifyEqual(testCase, s.scale.dimensionless, 1);
verifyEqual(testCase, s.scale.other, 1);
end

function testRequiredNominalMetricTargets(testCase)
s = steady53_spec();

verifyEqual(testCase, metricTarget(s, "rotor_speed"), 55090);
verifyEqual(testCase, metricTarget(s, "reactor_outlet_T"), 1600.00);
verifyEqual(testCase, metricTarget(s, "turbine_power"), 2252.2e3);
verifyEqual(testCase, metricTarget(s, "compressor_power"), 1231.6e3);
verifyEqual(testCase, metricTarget(s, "tac_electric_power"), 1000.21e3);
end

function testMetricTableContract(testCase)
s = steady53_spec();
expectedNames = [
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

verifyEqual(testCase, height(s.metrics), 21);
verifyEqual(testCase, s.metrics.name, expectedNames);
verifyEqual(testCase, numel(unique(s.metrics.name)), height(s.metrics));
verifyEqual(testCase, s.metrics.Properties.VariableNames, ...
    {'name', 'target', 'unit', 'relTol', 'settleDeadline_s'});

speedRow = s.metrics.name == "rotor_speed";
verifyEqual(testCase, nnz(speedRow), 1);
verifyEqual(testCase, s.metrics.relTol(speedRow), 1 / 55090);
verifyEqual(testCase, s.metrics.relTol(~speedRow), ...
    repmat(s.outputRelTol, nnz(~speedRow), 1));
end

function testRequiredLookupNamesAreFixedAndUnique(testCase)
s = steady53_spec();
expected = [ ...
    "compressor_efficiency_speed"
    "compressor_efficiency_flow"
    "compressor_pressure_ratio_speed"
    "compressor_pressure_ratio_flow"
    "turbine_flow_expansion_ratio"
    "turbine_flow_speed"
    "turbine_efficiency_mass_flow"
    "turbine_efficiency_speed"];

verifyEqual(testCase, s.requiredLookupNames, expected);
verifyEqual(testCase, numel(s.requiredLookupNames), 8);
verifyEqual(testCase, numel(unique(s.requiredLookupNames)), 8);
end

function testSignalMetadataIsFixedCompleteAndInternallyValid(testCase)
s = steady53_spec();
[expectedNames, expectedKinds, expectedConstants] = expectedSignalMetadata();
expected = table(expectedNames, expectedKinds, expectedConstants, ...
    ones(37, 1), 'VariableNames', ...
    {'name', 'kind', 'constant', 'scaleFloor'});

verifyEqual(testCase, s.signalMetadata, expected);
verifyEqual(testCase, height(s.signalMetadata), 37);
verifyEqual(testCase, numel(unique(s.signalMetadata.name)), 37);
verifyTrue(testCase, all(ismember(s.signalMetadata.kind, ...
    ["temperature", "pressure", "power", "massFlow", ...
     "speed", "dimensionless", "other"])));
verifyTrue(testCase, islogical(s.signalMetadata.constant));
verifyTrue(testCase, all(isfinite(s.signalMetadata.scaleFloor) & ...
    s.signalMetadata.scaleFloor > 0));
verifyTrue(testCase, all(ismember(s.metrics.name, s.signalMetadata.name)));
end

function [name, kind, constant] = expectedSignalMetadata()
name = [ ...
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
kind = [ ...
    "temperature"; "pressure"; "temperature"; "temperature"; ...
    "pressure"; "temperature"; "temperature"; "pressure"; ...
    "temperature"; "pressure"; "pressure"; "temperature"; ...
    "pressure"; "temperature"; "temperature"; "temperature"; ...
    "power"; "power"; "speed"; "dimensionless"; ...
    repmat("massFlow", 7, 1); ...
    "dimensionless"; "dimensionless"; "dimensionless"; ...
    "dimensionless"; "dimensionless"; "speed"; "massFlow"; ...
    "speed"; "power"; "power"];
constant = false(37, 1);
constant([19 26 27 28 30 33 35]) = true;
end

function target = metricTarget(s, name)
row = s.metrics.name == name;
assert(nnz(row) == 1, "Expected exactly one metric named '%s'.", name);
target = s.metrics.target(row);
end
