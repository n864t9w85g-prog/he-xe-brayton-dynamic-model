function test_paper52_power_balance()
% Require an explicit electrical-to-shaft load boundary in the rotor model.

root = fileparts(fileparts(mfilename('fullpath')));
mdl = 'final_dynamic_24a';
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>

gainPath = [mdl '/TAC/rotor/Generator_Electrical_to_Shaft'];
assert(getSimulinkBlockHandle(gainPath) > 0, ...
    'Missing explicit electrical-to-shaft generator load conversion.');
assert(strcmp(get_param(gainPath, 'BlockType'), 'Gain'), ...
    'Generator load conversion must be an explicit Gain block.');
assert(strcmp(get_param(gainPath, 'Gain'), ...
    '1/paper54.generator.eta_calculated'), ...
    'Generator load conversion is not tied to the Table 5.2 calculation.');
end
