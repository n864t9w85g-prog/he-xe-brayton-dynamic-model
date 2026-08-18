function test_compressor_corrected_coordinates_model()
% Verify that both lookup tables receive audited corrected coordinates.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
evalin('base', sprintf('run(''%s'')', startPath));
assignin('base', 'Pload_sched', [0 1000.21e3; 1 1000.21e3]);
assignin('base', 'rho_sched', [0 0; 1 0]);
mdl = 'final_dynamic_24a';
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>

base = [mdl '/TAC/Compressor'];
coordinatePath = [base '/Corrected_Coordinates'];
assert(getSimulinkBlockHandle(coordinatePath) > 0, ...
    'Missing shared corrected-coordinate subsystem.');

assert_gain([coordinatePath '/N_over_Ndesign'], '1/paper54.N_rpm');
assert_gain([coordinatePath '/mdot_over_mdesign'], '1/mdot_design');
assert_gain([coordinatePath '/T_over_Tdesign'], ...
    '1/paper54.compressor.Tin_K');
assert_gain([coordinatePath '/P_over_Pdesign'], ...
    '1/paper54.compressor.Pin_Pa');
assert(strcmp(get_param([coordinatePath '/sqrt_T_ratio'], 'Operator'), ...
    'sqrt'));
assert(strcmp(get_param([coordinatePath '/CorrectedSpeed'], 'Inputs'), ...
    '*/'));
assert(strcmp(get_param([coordinatePath '/CorrectedFlow'], 'Inputs'), ...
    '**/'));

assert(strcmp(get_param([coordinatePath '/SpeedAboveMinimum'], ...
    'const'), 'speed_bp(1)'));
assert(strcmp(get_param([coordinatePath '/SpeedBelowMaximum'], ...
    'const'), 'speed_bp(end)'));
assert(strcmp(get_param([coordinatePath '/FlowAboveMinimum'], ...
    'const'), 'm_ratio_bp(1)'));
assert(strcmp(get_param([coordinatePath '/FlowBelowMaximum'], ...
    'const'), 'm_ratio_bp(end)'));
assert(numel(find_system(coordinatePath, 'SearchDepth', 1, ...
    'BlockType', 'Assertion')) == 4, ...
    'Corrected coordinates require four explicit domain assertions.');

for oldName = ["Gain1", "Gain2", "Gain3", "Gain4"]
    assert(getSimulinkBlockHandle([base '/' char(oldName)]) < 0, ...
        'Obsolete uncorrected normalization block remains: %s', oldName);
end

prLookup = [base '/2-D Lookup' newline 'Table3'];
etaLookup = [base '/2-D Lookup' newline 'Table1'];
assert_output_reaches(coordinatePath, 1, prLookup, 1);
assert_output_reaches(coordinatePath, 1, etaLookup, 1);
assert_output_reaches(coordinatePath, 2, prLookup, 2);
assert_output_reaches(coordinatePath, 2, etaLookup, 2);

set_param(mdl, 'SimulationCommand', 'update');
fprintf('PASS corrected compressor coordinates and domain assertions.\n');
end

function assert_gain(path, expression)
assert(getSimulinkBlockHandle(path) > 0, 'Missing gain block %s.', path);
assert(strcmp(get_param(path, 'Gain'), expression), ...
    'Unexpected gain expression at %s.', path);
end

function assert_output_reaches(sourcePath, sourcePortIndex, ...
    destinationPath, destinationPortIndex)
sourcePorts = get_param(sourcePath, 'PortHandles');
destinationPorts = get_param(destinationPath, 'PortHandles');
line = get_param(sourcePorts.Outport(sourcePortIndex), 'Line');
assert(line > 0, 'Corrected-coordinate output %d is unconnected.', ...
    sourcePortIndex);
destinations = get_param(line, 'DstPortHandle');
assert(any(destinations == destinationPorts.Inport(destinationPortIndex)), ...
    'Corrected coordinate does not reach %s input %d.', ...
    destinationPath, destinationPortIndex);
end
