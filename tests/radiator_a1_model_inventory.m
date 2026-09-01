function data = radiator_a1_model_inventory(model)
%RADIATOR_A1_MODEL_INVENTORY Deterministic API inventory for A1 audits.
model = string(model);
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
            values(end+1, 1) = string(jsonencode( ...
                get_param(block, names(j)))); %#ok<AGROW>
        end
    end
    handles = get_param(block, 'PortHandles');
    for j = 1:numel(handles.Inport)
        line = get_param(handles.Inport(j), 'Line');
        if line < 0, continue; end
        source = get_param(line, 'SrcPortHandle');
        if source < 0, continue; end
        edges(end+1, 1) = extractAfter( ...
            string(get_param(source, 'Parent')), strlength(model)) + ...
            "#" + get_param(source, 'PortNumber') + "->" + ...
            relative(k) + "#" + j; %#ok<AGROW>
    end
end
settings = struct();
for key = ["Solver", "SolverType", "StartTime", "StopTime", ...
        "RelTol", "AbsTol", "MaxStep", "LoadInitialState", ...
        "InitialState", "AlgebraicLoopSolver"]
    settings.(key) = get_param(model, key);
end
root = sfroot;
allCharts = root.find('-isa', 'Stateflow.EMChart');
charts = struct('path', {}, 'script', {});
for k = 1:numel(allCharts)
    if startsWith(string(allCharts(k).Path), model + "/")
        charts(end+1) = struct( ...
            'path', extractAfter( ...
                string(allCharts(k).Path), strlength(model)), ...
            'script', string(allCharts(k).Script)); %#ok<AGROW>
    end
end
if ~isempty(charts)
    [~, order] = sort(string({charts.path}));
    charts = charts(order);
end
[sortedKeys, order] = sort(keys);
data = struct();
data.blocks = struct('relative', cellstr(relative), ...
                     'type', cellstr(types));
data.edges = cellstr(sort(edges));
data.parameters = struct('key', cellstr(sortedKeys), ...
                         'value', cellstr(values(order)));
data.settings = settings;
data.charts = charts;
end
