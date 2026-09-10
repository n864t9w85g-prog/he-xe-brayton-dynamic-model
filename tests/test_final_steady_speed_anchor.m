function tests = test_final_steady_speed_anchor
%TEST_FINAL_STEADY_SPEED_ANCHOR Paper speed and lookup coordinates agree.
tests = functiontests(localfunctions);
end

function testFormalSteadyUsesPaperTable52Speed(testCase)
repoRoot = string(fileparts(fileparts(mfilename("fullpath"))));
oldFolder = string(pwd);
cleanupFolder = onCleanup(@() cd(oldFolder)); %#ok<NASGU>
cd(repoRoot);
C = paper54_constants();
load_system("final_steady_24a.slx");
cleanupModel = onCleanup(@() closeIfLoaded("final_steady_24a")); %#ok<NASGU>
speed = str2double(string(get_param( ...
    "final_steady_24a/TAC/Constant", "Value")));
gain1 = eval(string(get_param( ...
    "final_steady_24a/TAC/Compressor/Gain1", "Gain")));
gain2 = eval(string(get_param( ...
    "final_steady_24a/TAC/Compressor/Gain2", "Gain")));
verifyEqual(testCase, speed, C.N_rpm);
verifyEqual(testCase, speed * gain1, 1, "AbsTol", 1e-12);
verifyEqual(testCase, speed * gain2, 1, "AbsTol", 1e-12);
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

