function schedules = paper54_schedules(selector)
%PAPER54_SCHEDULES Exact Section 5.4 input schedules.
%
% The returned matrices are suitable for From Workspace blocks.  A step at
% t is represented by an old-value row at t and a new-value row at
% t + eps(t); the offset is numerical representation only, not a physical
% delay.  Load values are electrical output power, not shaft power.

if nargin < 1
    selector = 'all';
end
selector = validatestring(selector, {'all', 'load', 'reactivity'});

stopTime = 14000;

loadTransitions = [500 1500 2500];
loadPlateaus = [1000 950 1000 1050] * 1e3;
loadMatrix = make_step_matrix(loadTransitions, loadPlateaus, stopTime);

reactivityTransitions = [500 2000 3500 5000];
reactivityPlateaus = [0 1e-4 -1e-4 0 3e-4];
reactivityMatrix = make_step_matrix(reactivityTransitions, ...
    reactivityPlateaus, stopTime);

loadSchedule = struct( ...
    'kind', 'load', ...
    'unit', 'W_e', ...
    'source', 'Xu Chi thesis Section 5.4.2.2, Figure 5.31', ...
    'transition_times_s', loadTransitions, ...
    'plateau_values_W', loadPlateaus, ...
    'stop_time_s', stopTime, ...
    'matrix', loadMatrix);

reactivitySchedule = struct( ...
    'kind', 'reactivity', ...
    'unit', 'delta_rho', ...
    'source', 'Xu Chi thesis Section 5.4.2.3, Figure 5.33', ...
    'transition_times_s', reactivityTransitions, ...
    'plateau_values', reactivityPlateaus, ...
    'stop_time_s', stopTime, ...
    'matrix', reactivityMatrix);

switch selector
    case 'load'
        schedules = loadSchedule;
    case 'reactivity'
        schedules = reactivitySchedule;
    otherwise
        schedules = struct('load', loadSchedule, ...
            'reactivity', reactivitySchedule);
end
end

function matrix = make_step_matrix(transitions, plateaus, stopTime)
assert(numel(plateaus) == numel(transitions) + 1, ...
    'A step schedule needs one more plateau than transition.');
matrix = zeros(2 * numel(transitions) + 2, 2);
matrix(1, :) = [0 plateaus(1)];
for k = 1:numel(transitions)
    row = 2 * k;
    t = transitions(k);
    matrix(row, :) = [t plateaus(k)];
    matrix(row + 1, :) = [t + eps(t) plateaus(k + 1)];
end
matrix(end, :) = [stopTime plateaus(end)];
end
