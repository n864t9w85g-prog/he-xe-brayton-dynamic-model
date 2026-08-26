function tests = test_hexe_property_scheme_a_offline
%TEST_HEXE_PROPERTY_SCHEME_A_OFFLINE Approved H2a Scheme A parity contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
testCase.TestData.originalPath = path;
addpath(fullfile(root, "tests", "steady53"), "-begin");
testCase.TestData.root = string(root);
testCase.TestData.h2a = ...
    analyze_task8_h2a_he_third_virial_counterfactual();
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testApprovedFixedPointParity(testCase)
expected = testCase.TestData.h2a.exceptionPoint.counterfactual;
[cpMass, gamma, rho, audit] = hexe_property_scheme_a_offline( ...
    expected.T_K, expected.P_Pa);

verifyEqual(testCase, cpMass, expected.cpMass, "AbsTol", 1e-10);
verifyEqual(testCase, gamma, expected.gamma, "AbsTol", 1e-13);
verifyEqual(testCase, rho, expected.rho, "AbsTol", 1e-12);
verifyEqual(testCase, audit.cpMolar, ...
    20.787832416605639, "AbsTol", 1e-12);
verifyEqual(testCase, audit.cvMolar, ...
    12.476129332826748, "AbsTol", 1e-12);
verifyEqual(testCase, audit.gamma, ...
    1.6662084739623075, "AbsTol", 1e-13);
verifyEqual(testCase, audit.cpMolar, expected.cpMolar, ...
    "AbsTol", 1e-12);
verifyEqual(testCase, audit.cvMolar, expected.cvMolar, ...
    "AbsTol", 1e-12);

zeroFields = ["C111" "C112" "C122" ...
    "dC111_dT" "dC112_dT" "dC122_dT" ...
    "d2C111_dT2" "d2C112_dT2" "d2C122_dT2"];
for field = zeroFields
    verifyEqual(testCase, audit.(field), 0);
end
verifyNotEqual(testCase, audit.C222, 0);
verifyEqual(testCase, audit.C, audit.xXe^3*audit.C222, ...
    "AbsTol", 1e-30);
verifyEqual(testCase, audit.dC_dT, ...
    audit.xXe^3*audit.dC222_dT, "AbsTol", 1e-30);
verifyEqual(testCase, audit.d2C_dT2, ...
    audit.xXe^3*audit.d2C222_dT2, "AbsTol", 1e-30);
end

function testAllApprovedCounterfactualSweepStatesMatch(testCase)
h2a = testCase.TestData.h2a;
tables = {h2a.fixedPressureSweep.counterfactual.stateTable, ...
    h2a.h1aPathSweep.counterfactual.stateTable};
for tableIndex = 1:numel(tables)
    expected = tables{tableIndex};
    for row = 1:height(expected)
        [~, gamma, rho, audit] = hexe_property_scheme_a_offline( ...
            expected.T_K(row), expected.P_Pa(row));
        verifyEqual(testCase, rho, expected.rho(row), ...
            "AbsTol", 1e-12);
        verifyEqual(testCase, audit.cpMolar, expected.cpMolar(row), ...
            "AbsTol", 1e-10);
        verifyEqual(testCase, audit.cvMolar, expected.cvMolar(row), ...
            "AbsTol", 1e-10);
        verifyEqual(testCase, gamma, expected.gamma(row), ...
            "AbsTol", 1e-12);
        verifyEqual(testCase, audit.dPdrho, expected.dPdrho(row), ...
            "AbsTol", 1e-8);
        verifyEqual(testCase, audit.stablePositiveRealRootCount, ...
            expected.stablePositiveRealRootCount(row));
    end
end
end

function testInvalidInputsFailClosed(testCase)
invalid = { ...
    {NaN, 1e6}, {Inf, 1e6}, {1000, NaN}, {1000, Inf}, ...
    {0, 1e6}, {-1, 1e6}, {1000, 0}, {1000, -1}, ...
    {[900 1000], 1e6}, {1000, [1e6 1.1e6]}};
for index = 1:numel(invalid)
    args = invalid{index};
    verifyError(testCase, ...
        @() hexe_property_scheme_a_offline(args{1}, args{2}), ...
        "steady53:SchemeAInvalidInput");
end
end

function testSourceIsPureOfflineEvaluator(testCase)
sourcePath = fullfile(testCase.TestData.root, "tests", "steady53", ...
    "hexe_property_scheme_a_offline.m");
source = fileread(sourcePath);
forbidden = regexp(source, ...
    ['(?<![A-Za-z0-9_])(HeXe_property_simulink|load|save|' ...
    'writetable|writecell|fopen|fprintf|set_param|sim|' ...
    'load_system|save_system|open_system|bdclose)\s*\('], "match");
verifyEmpty(testCase, forbidden);
verifyFalse(testCase, contains(source, "miu"));
verifyFalse(testCase, contains(source, "lambda_mix"));
end
