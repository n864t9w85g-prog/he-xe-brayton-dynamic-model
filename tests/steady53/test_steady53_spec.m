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
end

function testRequiredNominalMetricTargets(testCase)
s = steady53_spec();

verifyEqual(testCase, metricTarget(s, "rotor_speed"), 55090);
verifyEqual(testCase, metricTarget(s, "reactor_outlet_T"), 1600.00);
verifyEqual(testCase, metricTarget(s, "turbine_power"), 2252.2e3);
verifyEqual(testCase, metricTarget(s, "compressor_power"), 1231.6e3);
verifyEqual(testCase, metricTarget(s, "tac_electric_power"), 1000.21e3);
end

function target = metricTarget(s, name)
row = s.metrics.name == name;
assert(nnz(row) == 1, "Expected exactly one metric named '%s'.", name);
target = s.metrics.target(row);
end
