function apply_paper52_generator_load()
%APPLY_PAPER52_GENERATOR_LOAD Insert the Table 5.2 electrical/shaft boundary.

root = fileparts(mfilename('fullpath'));
mdl = 'final_dynamic_24a';
rotor = [mdl '/TAC/rotor'];
gainName = 'Generator_Electrical_to_Shaft';
gainPath = [rotor '/' gainName];
gainExpression = '1/paper54.generator.eta_calculated';

startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
evalin('base', sprintf('run(''%s'')', startPath));
assignin('base', 'Pload_sched', [0 1000.21e3; 1 1000.21e3]);
assignin('base', 'rho_sched', [0 0; 1 0]);
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_loaded_model(mdl)); %#ok<NASGU>

existing = getSimulinkBlockHandle(gainPath);
if existing > 0
    assert(strcmp(get_param(gainPath, 'BlockType'), 'Gain'), ...
        'Existing generator conversion block is not a Gain block.');
    assert(strcmp(get_param(gainPath, 'Gain'), gainExpression), ...
        'Existing generator conversion has a different expression.');
else
    pLoadPath = [rotor '/Pload'];
    sumPath = [rotor '/Sum'];
    pLoadPorts = get_param(pLoadPath, 'PortHandles');
    sumPorts = get_param(sumPath, 'PortHandles');
    directLine = get_param(pLoadPorts.Outport, 'Line');
    assert(directLine > 0, 'Pload has no outgoing line to replace.');
    directDestinations = get_param(directLine, 'DstPortHandle');
    assert(isscalar(directDestinations) && ...
        directDestinations == sumPorts.Inport(3), ...
        'Pload is not connected only to the third Sum input.');

    add_block('simulink/Math Operations/Gain', gainPath, ...
        'Gain', gainExpression, ...
        'Position', [60 142 130 178]);
    delete_line(directLine);
    add_line(rotor, 'Pload/1', [gainName '/1'], 'autorouting', 'on');
    add_line(rotor, [gainName '/1'], 'Sum/3', 'autorouting', 'on');
end

set_param(mdl, 'SimulationCommand', 'update');
save_system(mdl);
close_system(mdl, 0);
end

function close_loaded_model(mdl)
if bdIsLoaded(mdl)
    close_system(mdl, 0);
end
end
