function tests = test_evaluate_steady53
tests = functiontests(localfunctions);
end

function testNominalSteadyDataPasses(testCase)
[t, signals, audit, s] = nominalCase();

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, report.pass);
verifyEmpty(testCase, report.failures);
verifyEqual(testCase, height(report.metrics), height(s.metrics));
verifyEqual(testCase, report.audit, audit);
end

function testFinalWindowDriftFailsPeakToPeak(testCase)
[t, signals, audit, s] = nominalCase();
inFinalWindow = t >= s.finalWindow_s(1);
target = metricTarget(s, "reactor_inlet_T");
signals.reactor_inlet_T(inFinalWindow) = linspace( ...
    target, target * 1.002, nnz(inFinalWindow)).';

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == ...
    "reactor_inlet_T:peak_to_peak"));
end

function testWarningsAndLookupExcursionsBothFail(testCase)
[t, signals, audit, s] = nominalCase();
audit.warningIds = "HeXe:T_hi";
audit.lookup = struct( ...
    "name", "compressor_speed", ...
    "inputMin", 0.9, ...
    "inputMax", 1.2, ...
    "bpMin", 0.9, ...
    "bpMax", 1.1);

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == "warning:HeXe:T_hi"));
verifyTrue(testCase, any(report.failures == "lookup:compressor_speed"));
end

function testStateOutsideFluidDomainFails(testCase)
[t, signals, audit, s] = nominalCase();
audit.states = struct( ...
    "path", "model/recuperator/T_hot", ...
    "fluid", "HeXe", ...
    "data", repmat(2200, size(t)), ...
    "kind", "temperature", ...
    "signPolicy", "positive");

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == ...
    "state:HeXe_domain:model/recuperator/T_hot"));
end

function testMissingAuditFieldsFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
requiredFields = ["warningIds", "lookup", "property", ...
    "massClosureRel", "states"];

for field = requiredFields
    incompleteAudit = rmfield(audit, field);
    report = evaluate_steady53(t, signals, incompleteAudit, s);

    verifyFalse(testCase, report.pass);
    verifyTrue(testCase, any(report.failures == ...
        "audit:missing:" + field));
end
end

function testInvalidWarningIdsFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
audit.warningIds = struct("unexpected", true);

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == ...
    "audit:invalid:warningIds"));
end

function testMissingAndInvalidLookupEntriesFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
validLookup = struct( ...
    "name", "compressor_speed", ...
    "inputMin", 0.9, ...
    "inputMax", 1.1, ...
    "bpMin", 0.9, ...
    "bpMax", 1.1);

audit.lookup = rmfield(validLookup, "inputMax");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "lookup:invalid:compressor_speed");

audit.lookup = validLookup;
audit.lookup.inputMax = NaN;
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "lookup:invalid:compressor_speed");

audit.lookup = validLookup;
audit.lookup.bpMin = 1.2;
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "lookup:invalid:compressor_speed");

audit.lookup = rmfield(validLookup, "name");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "lookup:invalid:1");
end

function testIncompleteAndInvalidStatesFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
validState = struct( ...
    "path", "model/recuperator/T_hot", ...
    "fluid", "HeXe", ...
    "data", repmat(1000, size(t)), ...
    "kind", "temperature", ...
    "signPolicy", "positive");

audit.states = rmfield(validState, "fluid");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/recuperator/T_hot");

audit.states = validState;
audit.states.data = [];
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/recuperator/T_hot");

audit.states = validState;
audit.states.data = "not numeric";
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/recuperator/T_hot");

audit.states = rmfield(validState, "path");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:1");
end

function testInvalidPropertyFieldsFailClosed(testCase)
[t, signals, audit, s] = nominalCase();

audit.property = rmfield(audit.property, "HeXeMin_K");
verifyAuditFailure(testCase, t, signals, audit, s, "property:HeXe");

[~, ~, audit, ~] = nominalCase();
audit.property.HeXeMin_K = [100 101];
verifyAuditFailure(testCase, t, signals, audit, s, "property:HeXe");

[~, ~, audit, ~] = nominalCase();
audit.property.LithiumMax_K = Inf;
verifyAuditFailure(testCase, t, signals, audit, s, "property:Lithium");

[~, ~, audit, ~] = nominalCase();
audit.property.LithiumMin_K = 1000;
audit.property.LithiumMax_K = 900;
verifyAuditFailure(testCase, t, signals, audit, s, "property:Lithium");
end

function testNegativeMassClosureFails(testCase)
[t, signals, audit, s] = nominalCase();
audit.massClosureRel = -eps;

verifyAuditFailure(testCase, t, signals, audit, s, "mass:closure");
end

function testAlternateStopTimePasses(testCase)
s = steady53_spec();
s.stopTime_s = 500;
s.finalWindow_s = [400 500];
[t, signals, audit] = caseForSpec(s);

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, report.pass);
verifyEmpty(testCase, report.failures);
end

function testInvalidTimeAxesFailClosed(testCase)
[t, ~, audit, s] = nominalCase();
invalidAxes = cell(0, 1);

candidate = t;
candidate(50) = NaN;
invalidAxes{end + 1, 1} = candidate;
candidate = t;
candidate(50) = Inf;
invalidAxes{end + 1, 1} = candidate;
candidate = complex(t);
candidate(50) = candidate(50) + 1i;
invalidAxes{end + 1, 1} = candidate;
candidate = t;
candidate(50) = candidate(49);
invalidAxes{end + 1, 1} = candidate;
candidate = t;
candidate(50) = candidate(49) - 1;
invalidAxes{end + 1, 1} = candidate;
invalidAxes{end + 1, 1} = flipud(t);
invalidAxes{end + 1, 1} = zeros(0, 1);
invalidAxes{end + 1, 1} = [t(t < s.finalWindow_s(1)); s.stopTime_s];

for index = 1:numel(invalidAxes)
    invalidTime = invalidAxes{index};
    signals = signalsForTime(invalidTime, s);
    report = evaluate_steady53(invalidTime, signals, audit, s);

    verifyFalse(testCase, report.pass);
    verifyTrue(testCase, any(report.failures == "time:invalid"));
end
end

function testWrongStopTimeFailsWithGenericIdentifier(testCase)
[t, ~, audit, s] = nominalCase();
t = t(1:end - 1);
signals = signalsForTime(t, s);

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == "time:not_stop_time"));
end

function testFluidNoneStableNonTemperatureStatePasses(testCase)
[t, signals, audit, s] = nominalCase();
audit.states = struct( ...
    "path", "model/TAC/shaft_power", ...
    "fluid", "none", ...
    "data", repmat(1e6, size(t)), ...
    "kind", "power", ...
    "signPolicy", "nonnegative");

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, report.pass);
end

function testStateFinalWindowDriftFailsDynamics(testCase)
[t, signals, audit, s] = nominalCase();
data = repmat(1e6, size(t));
inFinalWindow = t >= s.finalWindow_s(1);
data(inFinalWindow) = linspace(1e6, 1.002e6, nnz(inFinalWindow)).';
audit.states = struct( ...
    "path", "model/TAC/shaft_power", ...
    "fluid", "none", ...
    "data", data, ...
    "kind", "power", ...
    "signPolicy", "nonnegative");

report = evaluate_steady53(t, signals, audit, s);

verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == ...
    "state:peak_to_peak:model/TAC/shaft_power"));
verifyTrue(testCase, any(report.failures == ...
    "state:trend:model/TAC/shaft_power"));
end

function testStateNonnegativeAndLengthContractsFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
data = repmat(1e3, size(t));
data(2) = -1;
audit.states = struct( ...
    "path", "model/TAC/power", ...
    "fluid", "none", ...
    "data", data, ...
    "kind", "power", ...
    "signPolicy", "nonnegative");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:negative:model/TAC/power");

audit.states.data = audit.states.data(1:end - 1);
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/TAC/power");
end

function testMetricTargetOnlyFailure(testCase)
[t, signals, audit, s] = nominalCase();
name = "turbine_inlet_P";
signals.(name) = repmat(metricTarget(s, name) * 1.02, size(t));

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, any(report.failures == name + ":target"));
verifyFalse(testCase, any(report.failures == name + ":peak_to_peak"));
verifyFalse(testCase, any(report.failures == name + ":trend"));
verifyFalse(testCase, any(report.failures == name + ":settling"));
end

function testMetricTrendCanFailBelowPeakToPeakGate(testCase)
[t, signals, audit, s] = nominalCase();
name = "turbine_inlet_P";
target = metricTarget(s, name);
inFinalWindow = t >= s.finalWindow_s(1);
values = signals.(name);
values(inFinalWindow) = linspace( ...
    target * (1 - 0.00025), target * (1 + 0.00025), ...
    nnz(inFinalWindow)).';
signals.(name) = values;

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, any(report.failures == name + ":trend"));
verifyFalse(testCase, any(report.failures == name + ":peak_to_peak"));
verifyFalse(testCase, any(report.failures == name + ":target"));
end

function testMetricSettlingDeadlineFailure(testCase)
[t, signals, audit, s] = nominalCase();
name = "reactor_inlet_T";
target = metricTarget(s, name);
values = signals.(name);
values(t < 100) = target * 1.02;
signals.(name) = values;

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, any(report.failures == name + ":settling"));
verifyFalse(testCase, any(report.failures == name + ":target"));
verifyFalse(testCase, any(report.failures == name + ":peak_to_peak"));
verifyFalse(testCase, any(report.failures == name + ":trend"));
end

function testInvalidMetricSignalsFailClosed(testCase)
[t, signals, audit, s] = nominalCase();
signals = rmfield(signals, "reactor_outlet_T");
signals.turbine_inlet_T = signals.turbine_inlet_T(1:end - 1);
signals.compressor_inlet_T(10) = NaN;
signals.compressor_outlet_T = complex(signals.compressor_outlet_T, 1);

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, any(report.failures == "reactor_outlet_T:missing"));
verifyTrue(testCase, any(report.failures == "turbine_inlet_T:length"));
verifyTrue(testCase, any(report.failures == "compressor_inlet_T:nonfinite"));
verifyTrue(testCase, any(report.failures == "compressor_outlet_T:complex"));
end

function testMassClosureAboveGateFails(testCase)
[t, signals, audit, s] = nominalCase();
audit.massClosureRel = s.massClosureTol * 1.01;

verifyAuditFailure(testCase, t, signals, audit, s, "mass:closure");
end

function testLookupExactlyAtBoundaryPasses(testCase)
[t, signals, audit, s] = nominalCase();
audit.lookup = struct( ...
    "name", "compressor_speed", ...
    "inputMin", 0.9, ...
    "inputMax", 1.1, ...
    "bpMin", 0.9, ...
    "bpMax", 1.1);

report = evaluate_steady53(t, signals, audit, s);

verifyTrue(testCase, report.pass);
end

function testTimeMustStartAtZero(testCase)
[~, ~, audit, s] = nominalCase();
timeAxes = { ...
    (10:10:s.stopTime_s).'; ...
    (-10:10:s.stopTime_s).'};

for index = 1:numel(timeAxes)
    shiftedTime = timeAxes{index};
    signals = signalsForTime(shiftedTime, s);
    report = evaluate_steady53(shiftedTime, signals, audit, s);

    verifyFalse(testCase, report.pass);
    verifyTrue(testCase, any(report.failures == "time:invalid"));
end
end

function testStateRequiresExplicitKindAndSignPolicy(testCase)
[t, signals, audit, s] = nominalCase();
state = struct( ...
    "path", "model/reactor/Integrator6", ...
    "fluid", "none", ...
    "data", repmat(1e3, size(t)), ...
    "kind", "power", ...
    "signPolicy", "nonnegative");

audit.states = rmfield(state, "kind");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/reactor/Integrator6");

audit.states = rmfield(state, "signPolicy");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:invalid:model/reactor/Integrator6");
end

function testExplicitStateSignPolicies(testCase)
[t, signals, audit, s] = nominalCase();
data = repmat(1e3, size(t));
data(2) = -1;
audit.states = struct( ...
    "path", "model/reactor/Integrator6", ...
    "fluid", "none", ...
    "data", data, ...
    "kind", "power", ...
    "signPolicy", "nonnegative");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:negative:model/reactor/Integrator6");

audit.states = struct( ...
    "path", "model/TAC/rotor/N_rpm_Integrator", ...
    "fluid", "none", ...
    "data", data, ...
    "kind", "speed", ...
    "signPolicy", "nonnegative");
verifyAuditFailure(testCase, t, signals, audit, s, ...
    "state:negative:model/TAC/rotor/N_rpm_Integrator");
end

function testSignedStateAllowsNegativeButStillChecksDynamics(testCase)
[t, signals, audit, s] = nominalCase();
path = "model/reactor/Integrator6";
data = repmat(-1e3, size(t));
audit.states = struct( ...
    "path", path, ...
    "fluid", "none", ...
    "data", data, ...
    "kind", "other", ...
    "signPolicy", "signed");

report = evaluate_steady53(t, signals, audit, s);
verifyTrue(testCase, report.pass);

inFinalWindow = t >= s.finalWindow_s(1);
audit.states.data(inFinalWindow) = linspace( ...
    -1e3, -1.002e3, nnz(inFinalWindow)).';
report = evaluate_steady53(t, signals, audit, s);
verifyTrue(testCase, any(report.failures == ...
    "state:peak_to_peak:" + path));
verifyTrue(testCase, any(report.failures == "state:trend:" + path));
end

function [t, signals, audit, s] = nominalCase()
s = steady53_spec();
[t, signals, audit] = caseForSpec(s);
end

function [t, signals, audit] = caseForSpec(s)
t = (0:10:s.stopTime_s).';
signals = signalsForTime(t, s);

audit = struct();
% Contract: warningIds contains property-clamp warning IDs prefiltered by runner.
audit.warningIds = strings(0, 1);
audit.lookup = struct( ...
    "name", {}, ...
    "inputMin", {}, ...
    "inputMax", {}, ...
    "bpMin", {}, ...
    "bpMax", {});
audit.property = struct( ...
    "HeXeMin_K", s.property.HeXe_K(1), ...
    "HeXeMax_K", s.property.HeXe_K(2), ...
    "LithiumMin_K", s.property.Lithium_K(1), ...
    "LithiumMax_K", s.property.Lithium_K(2));
audit.massClosureRel = 0;
audit.states = struct( ...
    "path", {}, ...
    "fluid", {}, ...
    "data", {}, ...
    "kind", {}, ...
    "signPolicy", {});
end

function signals = signalsForTime(t, s)
signals = struct();
for row = 1:height(s.metrics)
    name = s.metrics.name(row);
    signals.(name) = repmat(s.metrics.target(row), size(t));
end
end

function target = metricTarget(s, name)
row = s.metrics.name == name;
assert(nnz(row) == 1, "Expected exactly one metric named '%s'.", name);
target = s.metrics.target(row);
end

function verifyAuditFailure(testCase, t, signals, audit, s, expectedFailure)
report = evaluate_steady53(t, signals, audit, s);
verifyFalse(testCase, report.pass);
verifyTrue(testCase, any(report.failures == expectedFailure));
end
