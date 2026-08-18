function apply_compressor_corrected_coordinates()
%APPLY_COMPRESSOR_CORRECTED_COORDINATES Add audited corrected map inputs.

root = fileparts(mfilename('fullpath'));
mdl = 'final_dynamic_24a';
modelFile = fullfile(root, [mdl '.slx']);
backupFile = fullfile(root, ...
    [mdl '.slx.before_corrected_coordinates.bak']);
if ~isfile(backupFile)
    copyfile(modelFile, backupFile);
end

startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
evalin('base', sprintf('run(''%s'')', startPath));
assignin('base', 'Pload_sched', [0 1000.21e3; 1 1000.21e3]);
assignin('base', 'rho_sched', [0 0; 1 0]);
load_system(modelFile);
cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>
base = [mdl '/TAC/Compressor'];
coordinatePath = [base '/Corrected_Coordinates'];
if getSimulinkBlockHandle(coordinatePath) > 0
    set_param(mdl, 'SimulationCommand', 'update');
    save_system(mdl, modelFile);
    return;
end

% Remove the four existing lookup-input lines explicitly before deleting the
% old normalization blocks; delete_block alone can leave a line handle alive.
for lookupName = {['2-D Lookup' newline 'Table3'], ...
        ['2-D Lookup' newline 'Table1']}
    lookupPath = [base '/' lookupName{1}];
    lookupPorts = get_param(lookupPath, 'PortHandles');
    for port = lookupPorts.Inport(:).'
        line = get_param(port, 'Line');
        if line > 0
            delete_line(line);
        end
    end
end

oldBlocks = {'Gain1', 'Gain2', 'Gain3', 'Gain4', ...
    'From', 'From1', 'From2', 'From14'};
for k = 1:numel(oldBlocks)
    path = [base '/' oldBlocks{k}];
    if getSimulinkBlockHandle(path) > 0
        delete_block(path);
    end
end

add_block('simulink/Ports & Subsystems/Subsystem', coordinatePath, ...
    'Position', [535 135 700 255]);
clear_subsystem(coordinatePath);
build_coordinate_subsystem(coordinatePath);

add_from(base, 'Corrected_N', 'N', [420 145 475 165]);
add_from(base, 'Corrected_mdot', 'm_in', [420 170 475 190]);
add_from(base, 'Corrected_Pin', 'P_in', [420 195 475 215]);
add_from(base, 'Corrected_Tin', 'T_in', [420 220 475 240]);
add_line(base, 'Corrected_N/1', 'Corrected_Coordinates/1', ...
    'autorouting', 'on');
add_line(base, 'Corrected_mdot/1', 'Corrected_Coordinates/2', ...
    'autorouting', 'on');
add_line(base, 'Corrected_Pin/1', 'Corrected_Coordinates/3', ...
    'autorouting', 'on');
add_line(base, 'Corrected_Tin/1', 'Corrected_Coordinates/4', ...
    'autorouting', 'on');

prLookup = ['2-D Lookup' newline 'Table3'];
etaLookup = ['2-D Lookup' newline 'Table1'];
add_line(base, 'Corrected_Coordinates/1', [prLookup '/1'], ...
    'autorouting', 'on');
add_line(base, 'Corrected_Coordinates/1', [etaLookup '/1'], ...
    'autorouting', 'on');
add_line(base, 'Corrected_Coordinates/2', [prLookup '/2'], ...
    'autorouting', 'on');
add_line(base, 'Corrected_Coordinates/2', [etaLookup '/2'], ...
    'autorouting', 'on');

set_param(mdl, 'SimulationCommand', 'update');
save_system(mdl, modelFile);
fprintf('APPLIED corrected compressor map coordinates: %s\n', modelFile);
end

function clear_subsystem(path)
lines = find_system(path, 'FindAll', 'on', 'SearchDepth', 1, ...
    'Type', 'line');
for line = lines(:).'
    delete_line(line);
end
blocks = find_system(path, 'SearchDepth', 1, 'Type', 'Block');
for k = 2:numel(blocks)
    delete_block(blocks{k});
end
end

function build_coordinate_subsystem(path)
add_block('simulink/Ports & Subsystems/In1', [path '/N_rpm'], ...
    'Port', '1', 'Position', [25 28 55 42]);
add_block('simulink/Ports & Subsystems/In1', [path '/mdot'], ...
    'Port', '2', 'Position', [25 93 55 107]);
add_block('simulink/Ports & Subsystems/In1', [path '/P_in'], ...
    'Port', '3', 'Position', [25 158 55 172]);
add_block('simulink/Ports & Subsystems/In1', [path '/T_in'], ...
    'Port', '4', 'Position', [25 223 55 237]);

add_block('simulink/Math Operations/Gain', [path '/N_over_Ndesign'], ...
    'Gain', '1/paper54.N_rpm', 'Position', [90 20 180 50]);
add_block('simulink/Math Operations/Gain', [path '/mdot_over_mdesign'], ...
    'Gain', '1/mdot_design', 'Position', [90 85 180 115]);
add_block('simulink/Math Operations/Gain', [path '/P_over_Pdesign'], ...
    'Gain', '1/paper54.compressor.Pin_Pa', ...
    'Position', [90 150 180 180]);
add_block('simulink/Math Operations/Gain', [path '/T_over_Tdesign'], ...
    'Gain', '1/paper54.compressor.Tin_K', ...
    'Position', [90 215 180 245]);
add_block('simulink/Math Operations/Math Function', ...
    [path '/sqrt_T_ratio'], 'Operator', 'sqrt', ...
    'Position', [220 215 270 245]);
add_block('simulink/Math Operations/Product', ...
    [path '/CorrectedSpeed'], 'Inputs', '*/', ...
    'Position', [315 25 355 65]);
add_block('simulink/Math Operations/Product', ...
    [path '/CorrectedFlow'], 'Inputs', '**/', ...
    'Position', [315 120 355 170]);

add_block('simulink/Ports & Subsystems/Out1', ...
    [path '/speed_ratio'], 'Port', '1', ...
    'Position', [625 38 655 52]);
add_block('simulink/Ports & Subsystems/Out1', ...
    [path '/flow_ratio'], 'Port', '2', ...
    'Position', [625 138 655 152]);

add_domain_assertion(path, 'SpeedAboveMinimum', '>=', ...
    'speed_bp(1)', [405 5 520 35], [555 5 585 35]);
add_domain_assertion(path, 'SpeedBelowMaximum', '<=', ...
    'speed_bp(end)', [405 45 520 75], [555 45 585 75]);
add_domain_assertion(path, 'FlowAboveMinimum', '>=', ...
    'm_ratio_bp(1)', [405 100 520 130], [555 100 585 130]);
add_domain_assertion(path, 'FlowBelowMaximum', '<=', ...
    'm_ratio_bp(end)', [405 155 520 185], [555 155 585 185]);

add_line(path, 'N_rpm/1', 'N_over_Ndesign/1');
add_line(path, 'mdot/1', 'mdot_over_mdesign/1');
add_line(path, 'P_in/1', 'P_over_Pdesign/1');
add_line(path, 'T_in/1', 'T_over_Tdesign/1');
add_line(path, 'T_over_Tdesign/1', 'sqrt_T_ratio/1');
add_line(path, 'N_over_Ndesign/1', 'CorrectedSpeed/1');
add_line(path, 'sqrt_T_ratio/1', 'CorrectedSpeed/2');
add_line(path, 'mdot_over_mdesign/1', 'CorrectedFlow/1');
add_line(path, 'sqrt_T_ratio/1', 'CorrectedFlow/2');
add_line(path, 'P_over_Pdesign/1', 'CorrectedFlow/3');
add_line(path, 'CorrectedSpeed/1', 'speed_ratio/1');
add_line(path, 'CorrectedSpeed/1', 'SpeedAboveMinimum/1');
add_line(path, 'CorrectedSpeed/1', 'SpeedBelowMaximum/1');
add_line(path, 'CorrectedFlow/1', 'flow_ratio/1');
add_line(path, 'CorrectedFlow/1', 'FlowAboveMinimum/1');
add_line(path, 'CorrectedFlow/1', 'FlowBelowMaximum/1');
end

function add_domain_assertion(path, name, relation, constant, ...
    comparePosition, assertionPosition)
add_block('simulink/Logic and Bit Operations/Compare To Constant', ...
    [path '/' name], 'relop', relation, 'const', constant, ...
    'Position', comparePosition);
add_block('simulink/Model Verification/Assertion', ...
    [path '/' name '_Assertion'], 'Position', assertionPosition);
add_line(path, [name '/1'], [name '_Assertion/1']);
end

function add_from(parent, name, tag, position)
add_block('simulink/Signal Routing/From', [parent '/' name], ...
    'GotoTag', tag, 'Position', position);
end
