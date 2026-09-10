function patch_nak_enthalpy_candidate(model, destination)
% Exploration-only replacement of the radiator inlet-cp algebraic shortcut.
model = string(model);
destination = string(destination);
repo = string(fileparts(fileparts(mfilename('fullpath'))));
file = string(get_param(model, 'FileName'));
assert(model == "nak_enthalpy_candidate");
assert(startsWith(destination, fullfile(repo, 'tmp') + filesep));
assert(file == fullfile(destination, model + ".slx"));
assert(hashFile(file) == "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");

red = jsondecode(fileread(fullfile(repo, 'tmp', 'precooler_boundary_kd0F3a', ...
    'nak_loop_energy.json')));
assert(abs(red.radiator_minus_common_enthalpy_W) > 43000);
assert(abs(red.precooler_minus_common_enthalpy_W) < 1000);
assert(~isfile(fullfile(destination, 'patch_audit.json')));

before = inventory(model);
block = model + "/rediator/Tho";
assert(strcmp(get_param(block, 'BlockType'), 'Fcn'));
assert(strcmp(get_param(block, 'Expr'), '((u(2)-0.8)*u(3)+u(1))/(u(2)+0.2)'));
position = get_param(block, 'Position');
orientation = get_param(block, 'Orientation');
requireSource(block, 1, model + "/rediator/Mux4", 1);
requireDestination(block, 1, model + "/rediator/Mux2", 6);
requireDestination(block, 1, model + "/rediator/T_ho", 1);

delete_block(block);
add_block('simulink/User-Defined Functions/MATLAB Function', block, ...
    'Position', position, 'Orientation', orientation);
root = sfroot;
chart = root.find('-isa', 'Stateflow.EMChart', 'Path', block);
assert(numel(chart) == 1);
chart.Script = scriptText();
set_param(model, 'SimulationCommand', 'update');
ensureConnection(model + "/rediator", 'Mux4/1', 'Tho/1');
ensureConnection(model + "/rediator", 'Tho/1', 'Mux2/6');
ensureConnection(model + "/rediator", 'Tho/1', 'T_ho/1');

after = inventory(model);
prefix = "/rediator/Tho";
beforeOtherBlocks = before.blocks(~startsWith(before.blocks.relative, prefix), :);
afterOtherBlocks = after.blocks(~startsWith(after.blocks.relative, prefix), :);
assert(isequal(beforeOtherBlocks, afterOtherBlocks));
beforeOtherParameters = before.parameters(~startsWith(before.parameters.key, prefix + "|"), :);
afterOtherParameters = after.parameters(~startsWith(after.parameters.key, prefix + "|"), :);
afterOtherParameters = afterOtherParameters(~startsWith(afterOtherParameters.key, prefix + "/"), :);
assert(isequal(beforeOtherParameters, afterOtherParameters));
beforeExternalEdges = before.edges(~contains(before.edges, prefix + "/"));
afterExternalEdges = after.edges(~contains(after.edges, prefix + "/"));
assert(isequal(beforeExternalEdges, afterExternalEdges));
assert(isequal(before.settings, after.settings));
newChart = after.charts(strcmp(string({after.charts.path}), prefix));
assert(numel(newChart) == 1 && contains(newChart.script, 'nak_enthalpy_outlet'));
oldCharts = after.charts(~strcmp(string({after.charts.path}), prefix));
assert(isequal(before.charts, oldCharts));
assert(strcmp(get_param(block, 'SFBlockType'), 'MATLAB Function'));

save_system(model, file);
close_system(model, 0);
load_system(file);
reopened = inventory(model);
assert(isequal(after, reopened), 'Inventory changed on reopen');
audit = struct('before', before, 'after', after, ...
    'candidate_file', file, 'candidate_sha256', hashFile(file), ...
    'patch_sha256', hashFile(string(mfilename('fullpath')) + ".m"), ...
    'red_energy_evidence', red, ...
    'scope', ['Exploration-only replacement of rediator/Tho. Same current NaK cp polynomial; ' ...
    'mass flow, h, area, radiation, initial states, settings and all other blocks unchanged.']);
writeJSON(fullfile(destination, 'patch_audit.json'), audit);
fprintf('NAK_ENTHALPY_PATCH_STRUCTURE_PASS; REPLACED=/rediator/Tho\n');
end

function text = scriptText()
lines = [
    "function Tout = nak_enthalpy_outlet(u)"
    "%#codegen"
    "% Exploration-only analytic enthalpy integral of the existing NaK cp(T)."
    "Twall = u(1);"
    "r = u(2);"
    "Tin = u(3);"
    "cpin = 1000*(1.061 - 3.694e-4*Tin + 4.615e-8*Tin^2 + 1.509e-10*Tin^3);"
    "assert(isfinite(Twall) && isfinite(r) && isfinite(Tin) && cpin > 0 && r > 0);"
    "lo = 260.5;"
    "hi = Tin;"
    "assert(hi > lo && Twall < Tin);"
    "hTin = 1000*(1.061*Tin - 3.694e-4*Tin^2/2 + 4.615e-8*Tin^3/3 + 1.509e-10*Tin^4/4);"
    "hLo = 1000*(1.061*lo - 3.694e-4*lo^2/2 + 4.615e-8*lo^3/3 + 1.509e-10*lo^4/4);"
    "fLo = (r/cpin)*(hTin-hLo) - (0.8*Tin+0.2*lo-Twall);"
    "fHi = -(Tin-Twall);"
    "assert(fLo >= 0 && fHi <= 0);"
    "for k = 1:60"
    "    mid = 0.5*(lo+hi);"
    "    hMid = 1000*(1.061*mid - 3.694e-4*mid^2/2 + 4.615e-8*mid^3/3 + 1.509e-10*mid^4/4);"
    "    fMid = (r/cpin)*(hTin-hMid) - (0.8*Tin+0.2*mid-Twall);"
    "    if fMid >= 0"
    "        lo = mid;"
    "    else"
    "        hi = mid;"
    "    end"
    "end"
    "Tout = 0.5*(lo+hi);"
    "end"
    ];
text = strjoin(lines, newline);
end

function requireSource(block, port, source, sourcePort)
handles = get_param(block, 'PortHandles');
line = get_param(handles.Inport(port), 'Line');
assert(line >= 0);
handle = get_param(line, 'SrcPortHandle');
assert(string(get_param(handle, 'Parent')) == source);
assert(get_param(handle, 'PortNumber') == sourcePort);
end

function requireDestination(block, port, destination, destinationPort)
handles = get_param(block, 'PortHandles');
line = get_param(handles.Outport(port), 'Line');
assert(line >= 0);
destinations = get_param(line, 'DstPortHandle');
matched = false;
for handle = reshape(destinations, 1, [])
    matched = matched || (string(get_param(handle, 'Parent')) == destination && ...
        get_param(handle, 'PortNumber') == destinationPort);
end
assert(matched);
end

function ensureConnection(system, source, destination)
destinationBlock = extractBefore(string(destination), "/");
destinationPort = str2double(extractAfter(string(destination), "/"));
handles = get_param(system + "/" + destinationBlock, 'PortHandles');
line = get_param(handles.Inport(destinationPort), 'Line');
if line < 0
    add_line(system, source, destination, 'autorouting', 'on');
    return;
end
sourceHandle = get_param(line, 'SrcPortHandle');
expectedBlock = system + "/" + extractBefore(string(source), "/");
expectedPort = str2double(extractAfter(string(source), "/"));
assert(string(get_param(sourceHandle, 'Parent')) == expectedBlock);
assert(get_param(sourceHandle, 'PortNumber') == expectedPort);
end

function data = inventory(model)
paths = sort(string(find_system(model, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'off', 'Type', 'Block')));
relative = extractAfter(paths, strlength(model));
types = strings(size(paths));
keys = strings(0, 1);
values = strings(0, 1);
edges = strings(0, 1);
for k = 1:numel(paths)
    block = paths(k);
    types(k) = string(get_param(block, 'BlockType'));
    parameters = get_param(block, 'DialogParameters');
    if ~isempty(parameters)
        names = sort(string(fieldnames(parameters)));
        for j = 1:numel(names)
            keys(end+1, 1) = relative(k) + "|" + names(j); %#ok<AGROW>
            values(end+1, 1) = string(jsonencode(get_param(block, names(j)))); %#ok<AGROW>
        end
    end
    handles = get_param(block, 'PortHandles');
    for j = 1:numel(handles.Inport)
        line = get_param(handles.Inport(j), 'Line');
        if line < 0, continue; end
        source = get_param(line, 'SrcPortHandle');
        if source < 0, continue; end
        edges(end+1, 1) = extractAfter(string(get_param(source, 'Parent')), strlength(model)) + ...
            "#" + get_param(source, 'PortNumber') + "->" + relative(k) + "#" + j; %#ok<AGROW>
    end
end
settings = struct();
for key = ["Solver", "SolverType", "StartTime", "StopTime", "RelTol", "AbsTol", ...
        "MaxStep", "LoadInitialState", "InitialState", "AlgebraicLoopSolver"]
    settings.(key) = get_param(model, key);
end
root = sfroot;
all = root.find('-isa', 'Stateflow.EMChart');
charts = struct('path', {}, 'script', {});
for k = 1:numel(all)
    if startsWith(string(all(k).Path), model + "/")
        charts(end+1) = struct('path', extractAfter(string(all(k).Path), strlength(model)), ...
            'script', string(all(k).Script)); %#ok<AGROW>
    end
end
if ~isempty(charts)
    [~, order] = sort(string({charts.path}));
    charts = charts(order);
end
data = struct('blocks', table(relative, types), 'edges', sort(edges), ...
    'parameters', sortrows(table(keys, values, VariableNames={'key', 'value'}), 'key'), ...
    'settings', settings, 'charts', {charts});
end

function value = hashFile(path)
[status, output] = system("shasum -a 256 '" + replace(string(path), "'", "'\\''") + "'");
assert(status == 0);
parts = split(strtrim(string(output)));
value = parts(1);
end

function writeJSON(path, value)
file = fopen(path, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
