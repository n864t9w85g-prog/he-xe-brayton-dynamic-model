function report = solve_paper52_operating_point(varargin)
%SOLVE_PAPER52_OPERATING_POINT Search for a paper-constrained coupled trim.
%
% The solver never creates paper52_operating_point.mat for a failed or
% non-stationary candidate. Use 'DryRun',true to inventory the 42 states
% without invoking the nonlinear optimizer.

parser = inputParser;
parser.addParameter('DryRun', false, @(x) islogical(x) && isscalar(x));
parser.addParameter('Save', true, @(x) islogical(x) && isscalar(x));
parser.addParameter('AuditSimulation', true, @(x) islogical(x) && isscalar(x));
parser.addParameter('MaxIterations', 400, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parser.addParameter('OptimizerType', 'graddescent-elim', @(x) ischar(x) || (isstring(x) && isscalar(x)));
parser.addParameter('ScaleProblem', 'none', @(x) ischar(x) || (isstring(x) && isscalar(x)));
parser.addParameter('OutputRoot', '', @(x) ischar(x) || (isstring(x) && isscalar(x)));
parser.parse(varargin{:});
options = parser.Results;

root = fileparts(mfilename('fullpath'));
if isempty(options.OutputRoot)
    outputRoot = fullfile(root, 'output', 'paper54_reproduction');
else
    outputRoot = char(options.OutputRoot);
end
if ~isfolder(outputRoot) && options.Save
    mkdir(outputRoot);
end

C = paper54_constants();
S54 = paper54_schedules();
assignin('base', 'Pload_sched', S54.load.matrix);
assignin('base', 'rho_sched', S54.reactivity.matrix);

% start.m loads thermophysical data and may clear the base workspace.
startPath = strrep(fullfile(root, 'start.m'), '''', '''''');
evalin('base', sprintf('run(''%s'')', startPath));
assignin('base', 'Pload_sched', S54.load.matrix);
assignin('base', 'rho_sched', S54.reactivity.matrix);

mdl = 'final_dynamic_24a';
load_system(fullfile(root, [mdl '.slx']));
cleanup = onCleanup(@() close_system(mdl, 0)); %#ok<NASGU>

spec = operspec(mdl);
[spec, outputConstraints] = add_paper52_output_constraints(spec, mdl, C);
nStates = numel(spec.States);
stateBlocks = cell(nStates, 1);
stateValues = nan(nStates, 1);
for k = 1:nStates
    stateBlocks{k} = char(spec.States(k).Block);
    value = spec.States(k).x;
    stateValues(k) = value(1);
    spec.States(k).SteadyState = true;
end

speedBlock = [mdl '/TAC/rotor/N_rpm_Integrator'];
speedIndex = find(strcmp(stateBlocks, speedBlock), 1);
assert(~isempty(speedIndex), 'Could not locate the rotor speed state.');
spec.States(speedIndex).x = C.N_rpm;
spec.States(speedIndex).Known = true;
spec.States(speedIndex).SteadyState = true;

report = base_report(C, stateBlocks, stateValues, nStates);
report.specification = spec;
report.output_constraints = outputConstraints;
report.output_constraints_count = numel(outputConstraints);
report.source_model = fullfile(root, [mdl '.slx']);
report.source_model_sha256 = sha256_file(report.source_model);
report.options = struct('optimizer_type', char(options.OptimizerType), ...
    'scale_problem', char(options.ScaleProblem), ...
    'max_iterations', options.MaxIterations);

if options.DryRun
    return;
end

findopError = '';
op = [];
opreport = [];
try
    trimOptions = findopOptions('OptimizerType', char(options.OptimizerType));
    trimOptions.DisplayReport = 'off';
    trimOptions.OptimizationOptions.MaxIter = options.MaxIterations;
    trimOptions.OptimizationOptions.ScaleProblem = char(options.ScaleProblem);
    [op, opreport] = findop(mdl, spec, trimOptions);
    report.findop_termination = char(opreport.TerminationString);
    report.states = state_values(op.States, 'x');
    report.state_derivatives = state_values(opreport.States, 'dx');
    report.state_blocks = state_blocks(opreport.States);
    report.output_values = nan(numel(opreport.Outputs), 1);
    for outputIndex = 1:numel(opreport.Outputs)
        report.output_values(outputIndex) = opreport.Outputs(outputIndex).y(1);
    end
    report.output_targets = nan(numel(spec.Outputs), 1);
    for outputIndex = 1:numel(spec.Outputs)
        report.output_targets(outputIndex) = spec.Outputs(outputIndex).y(1);
    end
    report.output_residuals = report.output_values - report.output_targets;
    report.optimizer = opreport.OptimizationOutput;
catch exception
    findopError = getReport(exception, 'extended', 'hyperlinks', 'off');
    report.findop_termination = 'ERROR';
end
report.findop_error = findopError;

if ~isempty(op) && options.AuditSimulation
    try
        boundary = audit_from_operating_point(mdl, op, C);
        report.compressor = boundary.compressor;
        report.turbine = boundary.turbine;
        report.power = boundary.power;
        report.simulation_audit = boundary;
    catch exception
        report.simulation_audit_error = getReport(exception, ...
            'extended', 'hyperlinks', 'off');
    end
end

report.residuals.max_abs_state_derivative = max(abs(report.state_derivatives), [], 'omitnan');
report.residuals.shaft_power_W = report.power.shaft_residual_W;
report.residuals.lookup_domain_violation = NaN;
report.verified = isfinite(report.residuals.max_abs_state_derivative) && ...
    report.residuals.max_abs_state_derivative <= 1e-6 && ...
    isfinite(report.power.shaft_residual_W) && ...
    abs(report.power.shaft_residual_W) <= 1;

report.formal_file_created = false;
if options.Save
    if ~isfolder(outputRoot)
        mkdir(outputRoot);
    end
    residualPath = fullfile(outputRoot, 'paper52_steady_residuals.mat');
    save(residualPath, 'report', '-v7.3');
    report.residual_file = residualPath;
    if report.verified
        operating_point = op; %#ok<NASGU>
        paper_constraints = report.constraints; %#ok<NASGU>
        source_model_sha256 = report.source_model_sha256; %#ok<NASGU>
        matlab_release = version('-release'); %#ok<NASGU>
        created_utc = char(datetime('now', 'TimeZone', 'UTC', ...
            'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX')); %#ok<NASGU>
        formalPath = fullfile(root, 'paper52_operating_point.mat');
        save(formalPath, 'operating_point', 'report', ...
            'source_model_sha256', 'paper_constraints', ...
            'matlab_release', 'created_utc', '-v7.3');
        report.formal_file_created = true;
        report.formal_file = formalPath;
    end
end
end

function report = base_report(C, blocks, values, nStates)
report = struct;
report.states = values;
report.state_derivatives = nan(nStates, 1);
report.state_blocks = blocks;
report.compressor = struct('m_in_kg_s', NaN, 'p_in_Pa', NaN, ...
    'T_in_K', NaN, 'PR', NaN, 'T_out_K', NaN, 'p_out_Pa', NaN);
report.turbine = struct('m_in_kg_s', NaN, 'p_in_Pa', NaN, ...
    'T_in_K', NaN, 'T_out_K', NaN, 'p_out_Pa', NaN);
report.power = struct('turbine_W', NaN, 'compressor_W', NaN, ...
    'Pelectric_W', C.generator.electric_power_W, ...
    'Pshaft_W', C.generator.shaft_power_W, 'shaft_residual_W', NaN);
report.constraints = struct('N_rpm', C.N_rpm, ...
    'Pelectric_W', C.generator.electric_power_W, 'rho', 0, ...
    'compressor', C.compressor);
report.residuals = struct('max_abs_state_derivative', NaN, ...
    'shaft_power_W', NaN, 'lookup_domain_violation', NaN);
report.verified = false;
report.formal_file_created = false;
report.findop_termination = 'NOT_RUN';
report.findop_error = '';
report.output_constraints = cell(0, 1);
report.output_constraints_count = 0;
report.output_values = nan(0, 1);
report.output_targets = nan(0, 1);
report.output_residuals = nan(0, 1);
end

function [spec, names] = add_paper52_output_constraints(spec, mdl, C)
% Constrain only signals explicitly published in Table 5.2.
entries = {
    [mdl '/TAC/Compressor'], 1, C.compressor.PR, 'compressor_PR';
    [mdl '/TAC/Compressor'], 2, C.compressor.power_W, 'compressor_power_W';
    [mdl '/TAC/Compressor'], 3, C.compressor.Tout_K, 'compressor_Tout_K';
    [mdl '/TAC/Compressor'], 5, C.compressor.Pout_Pa, 'compressor_Pout_Pa';
    [mdl '/TAC/Turbine'], 2, C.turbine.Pout_Pa, 'turbine_Pout_Pa';
    [mdl '/TAC/Turbine'], 3, C.turbine.Tout_K, 'turbine_Tout_K';
    [mdl '/TAC/Turbine'], 4, C.turbine.power_W, 'turbine_power_W';
    [mdl '/recuperator'], 1, C.recuperator.hot_out_T_K, 'recuperator_hot_out_T_K';
    [mdl '/recuperator'], 2, C.recuperator.hot_out_P_Pa, 'recuperator_hot_out_P_Pa';
    [mdl '/recuperator'], 4, C.recuperator.cold_out_P_Pa, 'recuperator_cold_out_P_Pa';
    [mdl '/recuperator'], 6, C.recuperator.cold_out_T_K, 'recuperator_cold_out_T_K';
    [mdl '/reactor'], 1, C.reactor.outlet_T_K, 'reactor_outlet_T_K';
    [mdl '/IHX'], 1, C.reactor.inlet_T_K, 'reactor_inlet_T_K';
    [mdl '/IHX'], 3, C.turbine.Tin_K, 'turbine_inlet_T_K';
    [mdl '/precooler'], 4, C.cooler.cold_out_T_K, 'cooler_cold_out_T_K'};

names = cell(size(entries, 1), 1);
for k = 1:size(entries, 1)
    block = entries{k, 1};
    port = entries{k, 2};
    spec = addoutputspec(spec, block, port);
    outputIndex = numel(spec.Outputs);
    spec.Outputs(outputIndex).y = entries{k, 3};
    spec.Outputs(outputIndex).Known = true;
    names{k} = entries{k, 4};
end
end

function values = state_values(states, field)
values = nan(numel(states), 1);
for k = 1:numel(states)
    value = states(k).(field);
    values(k) = value(1);
end
end

function blocks = state_blocks(states)
blocks = cell(numel(states), 1);
for k = 1:numel(states)
    blocks{k} = char(states(k).Block);
end
end

function boundary = audit_from_operating_point(mdl, op, C)
% Run one short step from the candidate solely to measure published signals.
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
simIn = simIn.setModelParameter('StopTime', '0');
simIn = simIn.setInitialState(op);
simOut = sim(simIn);
logsout = simOut.get('logsout');
boundary.compressor.m_in_kg_s = first_logged_value(logsout, 'compressor_m_in');
boundary.compressor.p_in_Pa = first_logged_value(logsout, 'compressor_p_in');
boundary.compressor.T_in_K = first_logged_value(logsout, 'compressor_T_in');
boundary.compressor.PR = first_logged_value(logsout, 'compressor_PR');
boundary.compressor.T_out_K = first_logged_value(logsout, 'compressor_T_out');
boundary.compressor.p_out_Pa = first_logged_value(logsout, 'compressor_p_out');
boundary.turbine.p_in_Pa = first_logged_value(logsout, 'turbine_p_in');
boundary.turbine.T_in_K = first_logged_value(logsout, 'turbine_T_in');
boundary.turbine.m_in_kg_s = first_logged_value(logsout, 'turbine_mdot');
boundary.turbine.p_out_Pa = first_logged_value(logsout, 'turbine_p_out');
boundary.turbine.T_out_K = first_logged_value(logsout, 'turbine_T_out');
boundary.power.turbine_W = first_logged_value(simOut, 'WT_log');
boundary.power.compressor_W = first_logged_value(simOut, 'Wc_log');
boundary.power.Pelectric_W = first_logged_value(simOut, 'Pload_log');
boundary.power.Pshaft_W = boundary.power.Pelectric_W / C.generator.eta_calculated;
boundary.power.shaft_residual_W = boundary.power.turbine_W - ...
    boundary.power.compressor_W - boundary.power.Pshaft_W;
boundary.time_s = 0;
end

function enable_port_log(blockPath, side, index, logName)
ports = get_param(blockPath, 'PortHandles');
if strcmp(side, 'input')
    line = get_param(ports.Inport(index), 'Line');
    assert(line > 0, 'Input port has no signal line: %s port %d', blockPath, index);
    port = get_param(line, 'SrcPortHandle');
else
    port = ports.Outport(index);
end
set_param(port, 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', logName);
end

function value = first_logged_value(source, logName)
if isa(source, 'Simulink.SimulationOutput')
    value = source.get(logName).Data(1);
else
    element = source.getElement(logName);
    assert(~isempty(element), 'Missing logged signal: %s', logName);
    value = element.Values.Data(1);
end
end

function digest = sha256_file(path)
bytes = java.nio.file.Files.readAllBytes(java.io.File(path).toPath());
md = java.security.MessageDigest.getInstance('SHA-256');
digest = lower(char(org.apache.commons.codec.binary.Hex.encodeHex(md.digest(bytes))));
end
