function tests = test_evaluate_steady53
tests = functiontests(localfunctions);
end

function setupOnce(~)
testFile = mfilename("fullpath");
repositoryRoot = fileparts(fileparts(fileparts(testFile)));
addpath(repositoryRoot);
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
    "HeXe_K", s.property.HeXe_K, ...
    "Lithium_K", s.property.Lithium_K);
audit.massClosureRel = 0;
audit.states = struct("path", {}, "fluid", {}, "data", {});
end

function target = metricTarget(s, name)
row = s.metrics.name == name;
assert(nnz(row) == 1, "Expected exactly one metric named '%s'.", name);
target = s.metrics.target(row);
end
