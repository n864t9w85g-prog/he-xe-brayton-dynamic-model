function audit = audit_paper52_baseline(stopTime)
%AUDIT_PAPER52_BASELINE Measure the coupled baseline without tuning it.

if nargin == 0
    stopTime = 0;
end

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
C = paper54_constants();
startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
evalin('base', sprintf('run(''%s'')', startPath));
assignin('base', 'Pload_sched', ...
    [0 C.generator.electric_power_W; max(1, stopTime) C.generator.electric_power_W]);
assignin('base', 'rho_sched', [0 0; max(1, stopTime) 0]);

mdl = 'final_dynamic_24a';
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>
set_param([mdl '/TAC/rotor/N_rpm_Integrator'], ...
    'InitialCondition', num2str(C.N_rpm, 17));
set_param(mdl, 'SignalLogging', 'on', 'SignalLoggingName', 'logsout');
enable_port_log([mdl '/TAC/Compressor'], 'input', 2, 'compressor_m_in');
enable_port_log([mdl '/TAC/Compressor'], 'input', 3, 'compressor_p_in');
enable_port_log([mdl '/TAC/Compressor'], 'input', 4, 'compressor_T_in');
enable_port_log([mdl '/TAC/Compressor'], 'output', 1, 'compressor_PR');
enable_port_log([mdl '/TAC/Compressor'], 'output', 3, 'compressor_T_out');
enable_port_log([mdl '/TAC/Compressor'], 'output', 5, 'compressor_p_out');
enable_port_log([mdl '/TAC/Turbine'], 'input', 3, 'turbine_p_in');
enable_port_log([mdl '/TAC/Turbine'], 'input', 4, 'turbine_T_in');
enable_port_log([mdl '/TAC/Turbine'], 'output', 1, 'turbine_mdot');
enable_port_log([mdl '/TAC/Turbine'], 'output', 2, 'turbine_p_out');
enable_port_log([mdl '/TAC/Turbine'], 'output', 3, 'turbine_T_out');

simIn = Simulink.SimulationInput(mdl);
simIn = simIn.setModelParameter('StopTime', num2str(stopTime, 17));
simOut = sim(simIn);

N = simOut.get('N_log');
Wt = simOut.get('WT_log');
Wc = simOut.get('Wc_log');
Pelec = simOut.get('Pload_log');
logsout = simOut.get('logsout');

audit.time_s = N.Time(:);
audit.N_rpm = N.Data(:);
audit.Wt_W = Wt.Data(:);
audit.Wc_W = Wc.Data(:);
audit.Pelectric_W = Pelec.Data(:);
audit.Pshaft_W = audit.Pelectric_W / C.generator.eta_calculated;
audit.shaft_residual_W = audit.Wt_W - audit.Wc_W - audit.Pshaft_W;
audit.compressor.m_in_kg_s = first_logged_value(logsout, 'compressor_m_in');
audit.compressor.p_in_Pa = first_logged_value(logsout, 'compressor_p_in');
audit.compressor.T_in_K = first_logged_value(logsout, 'compressor_T_in');
audit.compressor.PR = first_logged_value(logsout, 'compressor_PR');
audit.compressor.T_out_K = first_logged_value(logsout, 'compressor_T_out');
audit.compressor.p_out_Pa = first_logged_value(logsout, 'compressor_p_out');
audit.turbine.p_in_Pa = first_logged_value(logsout, 'turbine_p_in');
audit.turbine.T_in_K = first_logged_value(logsout, 'turbine_T_in');
audit.turbine.mdot_kg_s = first_logged_value(logsout, 'turbine_mdot');
audit.turbine.p_out_Pa = first_logged_value(logsout, 'turbine_p_out');
audit.turbine.T_out_K = first_logged_value(logsout, 'turbine_T_out');

fprintf(['BASELINE t=%.9g s N=%.9f rpm Wt=%.6f kW ' ...
    'Wc=%.6f kW Pelec=%.6f kWe Pshaft=%.6f kW residual=%.6f kW\n'], ...
    audit.time_s(1), audit.N_rpm(1), audit.Wt_W(1) / 1e3, ...
    audit.Wc_W(1) / 1e3, audit.Pelectric_W(1) / 1e3, ...
    audit.Pshaft_W(1) / 1e3, audit.shaft_residual_W(1) / 1e3);
fprintf(['COMPRESSOR Tin=%.6f K Pin=%.6f MPa m=%.9f kg/s ' ...
    'PR=%.9f Tout=%.6f K Pout=%.6f MPa\n'], ...
    audit.compressor.T_in_K, audit.compressor.p_in_Pa / 1e6, ...
    audit.compressor.m_in_kg_s, audit.compressor.PR, ...
    audit.compressor.T_out_K, audit.compressor.p_out_Pa / 1e6);
fprintf(['TURBINE Tin=%.6f K Pin=%.6f MPa m=%.9f kg/s ' ...
    'Tout=%.6f K Pout=%.6f MPa\n'], ...
    audit.turbine.T_in_K, audit.turbine.p_in_Pa / 1e6, ...
    audit.turbine.mdot_kg_s, audit.turbine.T_out_K, ...
    audit.turbine.p_out_Pa / 1e6);

assert(abs(audit.shaft_residual_W(1)) < 1, ...
    'Initial shaft residual must be below the 1 W numerical audit threshold.');
end

function enable_port_log(blockPath, side, index, logName)
ports = get_param(blockPath, 'PortHandles');
if strcmp(side, 'input')
    line = get_param(ports.Inport(index), 'Line');
    assert(line > 0, 'Input port has no signal line: %s port %d', ...
        blockPath, index);
    port = get_param(line, 'SrcPortHandle');
else
    port = ports.Outport(index);
end
set_param(port, 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', logName);
end

function value = first_logged_value(logsout, logName)
element = logsout.getElement(logName);
assert(~isempty(element), 'Missing logged signal: %s', logName);
value = element.Values.Data(1);
end
