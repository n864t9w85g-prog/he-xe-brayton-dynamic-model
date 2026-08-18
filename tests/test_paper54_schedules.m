function test_paper54_schedules()
% Verify the Section 5.4 step schedules and their signal semantics.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);

S = paper54_schedules();
assert(isstruct(S) && isfield(S, 'load') && isfield(S, 'reactivity'), ...
    'paper54_schedules must return load and reactivity schedules.');

loadSchedule = S.load;
assert(strcmp(loadSchedule.unit, 'W_e'), ...
    'Section 5.4 load schedule must be electrical output power in W_e.');
assert(strcmp(loadSchedule.kind, 'load'), ...
    'Load schedule kind is incorrect.');
assert(isequal(loadSchedule.transition_times_s, [500 1500 2500]), ...
    'Load transition times must be 500, 1500, and 2500 s.');
assert(isequal(loadSchedule.plateau_values_W, [1000 950 1000 1050] * 1e3), ...
    'Load plateau values must be 1000, 950, 1000, and 1050 kW_e.');
assert_step_matrix(loadSchedule.matrix, loadSchedule.transition_times_s, ...
    loadSchedule.plateau_values_W, 'load');

rhoSchedule = S.reactivity;
assert(strcmp(rhoSchedule.unit, 'delta_rho'), ...
    'Reactivity schedule must be dimensionless delta-rho.');
assert(strcmp(rhoSchedule.kind, 'reactivity'), ...
    'Reactivity schedule kind is incorrect.');
assert(isequal(rhoSchedule.transition_times_s, [500 2000 3500 5000]), ...
    'Reactivity transition times must be 500, 2000, 3500, and 5000 s.');
assert(isequal(rhoSchedule.plateau_values, [0 1e-4 -1e-4 0 3e-4]), ...
    'Reactivity plateau values do not match Section 5.4.');
assert_step_matrix(rhoSchedule.matrix, rhoSchedule.transition_times_s, ...
    rhoSchedule.plateau_values, 'reactivity');
end

function assert_step_matrix(matrix, transitionTimes, plateauValues, label)
assert(size(matrix, 2) == 2, '%s schedule must be a two-column [time value] matrix.', label);
assert(all(diff(matrix(:, 1)) >= 0), '%s schedule times must be nondecreasing.', label);
assert(numel(matrix(:, 1)) == 2 * numel(transitionTimes) + 2, ...
    '%s schedule must use one epsilon-offset row per step.', label);
assert(matrix(1, 1) == 0 && matrix(1, 2) == plateauValues(1), ...
    '%s schedule initial value is incorrect.', label);

for k = 1:numel(transitionTimes)
    row = 2 * k;
    t = transitionTimes(k);
    assert(matrix(row, 1) == t, ...
        '%s left-continuous transition row has the wrong time.', label);
    assert(matrix(row + 1, 1) == t + eps(t), ...
        '%s transition offset must be eps(time), not an invented physical delay.', label);
    assert(matrix(row, 2) == plateauValues(k), ...
        '%s value immediately before transition is incorrect.', label);
    assert(matrix(row + 1, 2) == plateauValues(k + 1), ...
        '%s value immediately after transition is incorrect.', label);
end

last = size(matrix, 1);
assert(matrix(last, 2) == plateauValues(end), ...
    '%s final plateau value is incorrect.', label);
end
