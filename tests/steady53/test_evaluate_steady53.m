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
    "data", repmat(2200, size(t)));

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
    "data", repmat(1000, size(t)));

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

function [t, signals, audit, s] = nominalCase()
s = steady53_spec();
t = (0:10:s.stopTime_s).';
signals = struct();
for row = 1:height(s.metrics)
    name = s.metrics.name(row);
    signals.(name) = repmat(s.metrics.target(row), size(t));
end

audit = struct();
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
audit.states = struct("path", {}, "fluid", {}, "data", {});
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
