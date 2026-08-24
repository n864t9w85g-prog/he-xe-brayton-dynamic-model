function tests = test_property_warning_state
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.root = string(root);
testCase.TestData.originalPath = path;
testCase.TestData.warningSnapshot = warning("query", "all");
addpath(root);
addpath(fullfile(root, "tests", "steady53"));
end

function teardownOnce(testCase)
clear("HeXe_property_simulink", "Lithium_property_simulink");
restoreWarnings(testCase.TestData.warningSnapshot);
path(testCase.TestData.originalPath);
end

function testResetRearmsAllFourPoisonedWarningLatches(testCase)
for identifier = propertyIds()
    poisonLatch(identifier);
    reset_steady53_property_warning_state();
    old = warning("query", identifier);
    cleanup = onCleanup(@() warning(old.state, old.identifier));
    warning("error", identifier);
    verifyError(testCase, @() invokeFault(identifier), identifier);
    clear cleanup
end
end

function testRunnerDetectsAllFaultsAfterReverseOrderPoisoning(testCase)
modelPath = fullfile(testCase.TestData.root, "final_steady_24a.slx");
for identifier = fliplr(propertyIds())
    poisonLatch(identifier);
    control = struct("propertyFaultId", identifier);
    result = run_steady53_case(modelPath, 1, false, control);
    verifyFalse(testCase, result.success, ...
        "Runner missed poisoned-latch fault " + identifier);
    verifyEqual(testCase, result.errorId, identifier);
    verifyEqual(testCase, result.warningIds, identifier);
    verifyEqual(testCase, result.modelHashBefore, result.modelHashAfter);
end
end

function identifiers = propertyIds()
identifiers = ["HeXe:T_lo" "HeXe:T_hi" ...
    "Lithium_property_simulink:TemperatureBelowRange" ...
    "Lithium_property_simulink:TemperatureAboveRange"];
end

function poisonLatch(identifier)
clear("HeXe_property_simulink", "Lithium_property_simulink");
old = warning("query", identifier);
cleanup = onCleanup(@() warning(old.state, old.identifier));
warning("off", identifier);
invokeFault(identifier);
clear cleanup
end

function invokeFault(identifier)
switch string(identifier)
    case "HeXe:T_hi"
        HeXe_property_simulink(2001, 1e6);
    case "HeXe:T_lo"
        HeXe_property_simulink(99, 1e6);
    case "Lithium_property_simulink:TemperatureAboveRange"
        Lithium_property_simulink(1609, 1e6);
    case "Lithium_property_simulink:TemperatureBelowRange"
        Lithium_property_simulink(453, 1e6);
    otherwise
        error("steady53:UnknownPropertyFault", ...
            "Unknown property fault ID '%s'.", identifier);
end
end

function restoreWarnings(states)
for index = 1:numel(states)
    warning(states(index).state, states(index).identifier);
end
end
