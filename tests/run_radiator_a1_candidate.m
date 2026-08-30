function status = run_radiator_a1_candidate(runRoot, candidateId, outputDir, stopTime)
%RUN_RADIATOR_A1_CANDIDATE Blocking run; records every simulation failure.
if string(runRoot) == "__test_hooks__"
    status = struct('completionGate', @completionGate, ...
        'validateStopTime', @validateStopTime, ...
        'sameCandidateHash', @(a,b) string(a) == string(b));
    return
end
validateStopTime(stopTime);
repo = string(fileparts(fileparts(mfilename('fullpath'))));
runRoot = string(runRoot);
candidateId = string(candidateId);
outputDir = string(outputDir);
assert(isfolder(runRoot) && startsWith(runRoot, fullfile(repo, 'tmp') + filesep));
assert(startsWith(outputDir, runRoot + filesep));
assert(~isfolder(outputDir));
mkdir(outputDir);
candidateFile = fullfile(runRoot, 'candidates_500s', candidateId, 'candidate.slx');
manifestPath = fullfile(runRoot, 'representatives', candidateId, ...
    'parameter_manifest.json');
assert(isfile(candidateFile) && isfile(manifestPath));
candidateHash = hashFile(candidateFile);
preparation = jsondecode(fileread(fullfile(runRoot, 'candidates_500s', ...
    candidateId, 'preparation_status.json')));
assert(preparation.prepared && ...
    string(preparation.candidate_sha256) == candidateHash);
protected = readtable(fullfile(repo, 'data', 'provenance', 'baselines', ...
    'f8bcd83', 'protected_manifest_recovery.csv'), TextType='string');
checkProtected(protected);

status = struct('candidate_id', candidateId, ...
    'requested_stop_time_s', stopTime, 'actual_final_time_s', [], ...
    'success', false, 'error_id', "", 'error_message', "", ...
    'candidate_file', candidateFile, ...
    'candidate_sha256_before', candidateHash, ...
    'candidate_sha256_after', "", ...
    'all_logged_values_finite_real', false, ...
    'protected_hashes_unchanged', false, ...
    'paper_reproduced', false, 'formal_promotion', false);
oldPath = path;
cleanupPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
sourceDir = fullfile(repo, 'tmp', 'steady53_curves_20260828', ...
    'source_f8bcd83');
addpath(sourceDir, fullfile(sourceDir, 'tests', 'steady53'), ...
    fullfile(repo, 'tests'));
oldConfig = Simulink.fileGenControl('getConfig');
cleanupConfig = onCleanup(@() Simulink.fileGenControl('set', ...
    'CacheFolder', oldConfig.CacheFolder, ...
    'CodeGenFolder', oldConfig.CodeGenFolder, 'createDir', true)); %#ok<NASGU>
Simulink.fileGenControl('set', ...
    'CacheFolder', fullfile(outputDir, 'cache'), ...
    'CodeGenFolder', fullfile(outputDir, 'codegen'), 'createDir', true);
oldWarnings = warning;
cleanupWarnings = onCleanup(@() warning(oldWarnings)); %#ok<NASGU>
try
    evalin('base', "run('" + ...
        replace(fullfile(sourceDir, 'start.m'), "'", "''") + "')");
    reset_steady53_property_warning_state();
    for id = ["HeXe:T_lo", "HeXe:T_hi", ...
            "Lithium_property_simulink:TemperatureBelowRange", ...
            "Lithium_property_simulink:TemperatureAboveRange"]
        warning('error', id);
    end
    load_system(candidateFile);
    cleanupModel = onCleanup(@() closeOwnedModel()); %#ok<NASGU>
    [manifest, states] = steady53_signal_manifest("candidate");
    for k = 1:numel(manifest)
        logPort(manifest(k).block, manifest(k).port, manifest(k).name);
    end
    for k = 1:numel(states)
        logPort(states(k).path, 1, "state_" + compose('%03d', k));
    end
    input = Simulink.SimulationInput('candidate');
    input = input.setModelParameter( ...
        'StopTime', num2str(stopTime, '%.17g'), ...
        'ReturnWorkspaceOutputs', 'on', ...
        'SignalLogging', 'on', 'SignalLoggingName', 'logsout');
    timer = tic;
    output = sim(input);
    elapsed = toc(timer);
    save(fullfile(outputDir, 'raw_output.mat'), 'output', 'manifest', ...
        'states', 'elapsed', '-v7.3');
    exportLogs(output, outputDir);
    status.actual_final_time_s = output.tout(end);
    status.all_logged_values_finite_real = logsAreFiniteReal(output.logsout);
    status.success = completionGate(output.tout, "", ...
        flattenLogs(output.logsout), stopTime);
catch exception
    status.error_id = string(exception.identifier);
    status.error_message = string(getReport( ...
        exception, 'extended', 'hyperlinks', 'off'));
end
if bdIsLoaded('candidate'), close_system('candidate', 0); end
status.candidate_sha256_after = hashFile(candidateFile);
status.protected_hashes_unchanged = checkProtected(protected);
status.success = status.success ...
    && status.candidate_sha256_before == status.candidate_sha256_after ...
    && status.protected_hashes_unchanged;
writeJSON(fullfile(outputDir, 'simulation_status.json'), status);
writeJSON(fullfile(outputDir, 'hashes.json'), struct( ...
    'candidate_sha256', status.candidate_sha256_after, ...
    'manifest_sha256', hashFile(manifestPath), ...
    'runner_sha256', hashFile(string(mfilename('fullpath')) + ".m")));

    function closeOwnedModel()
        if bdIsLoaded('candidate'), close_system('candidate', 0); end
    end
end

function validateStopTime(value)
if ~isscalar(value) || ~isreal(value) || ~isfinite(value) ...
        || ~any(value == [500 14000])
    error('radiatorA1:UnsupportedStopTime', ...
        'Only 500 or 14000 s is approved.');
end
end

function passed = completionGate(time, errorText, values, requested)
passed = ~isempty(time) && time(end) == requested ...
    && strlength(string(errorText)) == 0 ...
    && all(isfinite(values), 'all') && isreal(values);
end

function logPort(block, port, name)
handles = get_param(block, 'PortHandles');
set_param(handles.Outport(port), 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', name);
end

function exportLogs(output, destination)
for k = 1:output.logsout.numElements
    element = output.logsout.getElement(k);
    series = element.Values;
    data = reshape(series.Data, numel(series.Time), []);
    if size(data, 2) == 1
        writetable(table(series.Time(:), data, ...
            'VariableNames', {'time_s','value'}), ...
            fullfile(destination, element.Name + ".csv"));
    end
end
for name = ["P_sw", "WT_sw", "Wc_sw"]
    try
        series = output.get(name);
        writetable(table(series.Time(:), series.Data(:), ...
            'VariableNames', {'time_s','value'}), ...
            fullfile(destination, name + ".csv"));
    catch
    end
end
end

function values = flattenLogs(logs)
values = [];
for k = 1:logs.numElements
    values = [values; logs.getElement(k).Values.Data(:)]; %#ok<AGROW>
end
end

function result = logsAreFiniteReal(logs)
values = flattenLogs(logs);
result = ~isempty(values) && all(isfinite(values)) && isreal(values);
end

function unchanged = checkProtected(tableValue)
unchanged = true;
for k = 1:height(tableValue)
    unchanged = unchanged ...
        && hashFile(tableValue.resolved_path(k)) ...
        == tableValue.expected_sha256(k);
end
assert(unchanged, 'Protected file changed');
end

function value = hashFile(pathValue)
[status, output] = system("shasum -a 256 '" + ...
    replace(string(pathValue), "'", "'\''") + "'");
assert(status == 0);
parts = split(strtrim(string(output)));
value = parts(1);
end

function writeJSON(pathValue, value)
assert(~isfile(pathValue));
file = fopen(pathValue, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
