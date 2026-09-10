function run_nak_enthalpy_candidate(runDirectory, stopTime)
% Run the exploration-only candidate from the immutable steady snapshot.
repo = string(fileparts(fileparts(mfilename('fullpath'))));
destination = fullfile(repo, string(runDirectory));
assert(isfolder(destination) && startsWith(destination, fullfile(repo, 'tmp') + filesep));
assert(any(stopTime == [500, 14000]));
caseDirectory = fullfile(destination, "candidate_" + stopTime);
assert(~isfolder(caseDirectory));
mkdir(caseDirectory);
diary(fullfile(caseDirectory, 'diary.txt'));
finishDiary = onCleanup(@() diary('off')); %#ok<NASGU>

protected = readtable(fullfile(repo, 'tmp', 'tp7d213f64_7fad_4bfa_b722_0771b21d9640', ...
    'protected_after.csv'), TextType='string');
checkProtected(protected);
source = fullfile(repo, 'tmp', 'steady53_curves_20260828', 'source_f8bcd83');
original = fullfile(source, 'final_steady_24a.slx');
assert(hashFile(original) == "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
model = "nak_enthalpy_candidate";
modelFile = fullfile(destination, model + ".slx");
assert(~bdIsLoaded(model));
if ~isfile(modelFile)
    assert(stopTime == 500);
    copyfile(original, modelFile);
    isNew = true;
else
    assert(stopTime == 14000);
    isNew = false;
end

oldDirectory = pwd;
finishDirectory = onCleanup(@() cd(oldDirectory)); %#ok<NASGU>
cd(caseDirectory);
oldPath = path;
finishPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(source, fullfile(source, 'tests', 'steady53'), fullfile(repo, 'tests'), destination);
assert(string(which('HeXe_property_simulink')) == fullfile(source, 'HeXe_property_simulink.m'));
assert(string(which('Lithium_property_simulink')) == fullfile(source, 'Lithium_property_simulink.m'));
fileConfig = Simulink.fileGenControl('getConfig');
finishFiles = onCleanup(@() Simulink.fileGenControl('set', ...
    'CacheFolder', fileConfig.CacheFolder, 'CodeGenFolder', fileConfig.CodeGenFolder, ...
    'createDir', true)); %#ok<NASGU>
Simulink.fileGenControl('set', 'CacheFolder', fullfile(caseDirectory, 'cache'), ...
    'CodeGenFolder', fullfile(caseDirectory, 'codegen'), 'createDir', true);
startScript = replace(fullfile(source, 'start.m'), "'", "''");
evalin('base', "run('" + startScript + "')");
load_system(modelFile);
finishModel = onCleanup(@() closeModel(model)); %#ok<NASGU>
if isNew
    patch_nak_enthalpy_candidate(model, destination);
end
modelHash = hashFile(modelFile);

[manifest, states] = steady53_signal_manifest(model);
for k = 1:numel(manifest)
    logPort(manifest(k).block, manifest(k).port, manifest(k).name);
end
for k = 1:numel(states)
    logPort(states(k).path, 1, "state_" + compose('%03d', k));
end
reset_steady53_property_warning_state();
warnings = warning;
finishWarnings = onCleanup(@() warning(warnings)); %#ok<NASGU>
for id = ["HeXe:T_lo", "HeXe:T_hi", ...
        "Lithium_property_simulink:TemperatureBelowRange", ...
        "Lithium_property_simulink:TemperatureAboveRange"]
    warning('error', id);
end
set_param(model, 'StopTime', num2str(stopTime), 'SignalLogging', 'on', ...
    'SignalLoggingName', 'logsout');
fprintf('BEGIN_NAK_ENTHALPY_CANDIDATE_%d\n', stopTime);
timer = tic;
out = sim(model, 'CaptureErrors', 'on', 'ReturnWorkspaceOutputs', 'on');
seconds = toc(timer);
save(fullfile(caseDirectory, 'output.mat'), 'out', 'manifest', 'states', 'seconds', '-v7.3');
success = isempty(out.ErrorMessage) && ~isempty(out.tout) && out.tout(end) == stopTime;
sourceFiles = [original, fullfile(source, 'HeXe_property_simulink.m'), ...
    fullfile(source, 'Lithium_property_simulink.m'), ...
    fullfile(source, 'hexe_compressor_lookup.mat'), fullfile(source, 'turbine_table1.mat'), ...
    fullfile(source, 'turbine_table2.mat'), string(mfilename('fullpath')) + ".m", ...
    fullfile(repo, 'tests', 'patch_nak_enthalpy_candidate.m'), ...
    fullfile(source, 'tests', 'steady53', 'steady53_signal_manifest.m')];
hashes = struct([]);
for k = 1:numel(sourceFiles)
    hashes(k).path = sourceFiles(k); %#ok<AGROW>
    hashes(k).sha256 = hashFile(sourceFiles(k)); %#ok<AGROW>
end
status = struct('success', success, 'requested_stop_time_s', stopTime, ...
    'seconds', seconds, 'error', out.ErrorMessage, 'model_file', modelFile, ...
    'model_sha256', modelHash, 'source_hashes', hashes, ...
    'mode', 'candidate', 'formal_mutations', false, 'paper_acceptance', false);
if ~isempty(out.tout)
    status.final_time_s = out.tout(end);
else
    status.final_time_s = [];
end
writeJSON(fullfile(caseDirectory, 'status.json'), status);
if isprop(out, 'logsout') || any(string(out.who) == "logsout")
    for k = 1:out.logsout.numElements
        element = out.logsout.getElement(k);
        series = element.Values;
        data = reshape(series.Data, numel(series.Time), []);
        assert(size(data, 2) == 1);
        writetable(table(series.Time(:), data, VariableNames={'time_s', 'value'}), ...
            fullfile(caseDirectory, element.Name + ".csv"));
    end
end
for name = ["P_sw", "WT_sw", "Wc_sw"]
    series = out.get(name);
    writetable(table(series.Time(:), series.Data(:), VariableNames={'time_s', 'value'}), ...
        fullfile(caseDirectory, name + ".csv"));
end
assert(hashFile(modelFile) == modelHash);
checkProtected(protected);
writetable(protected, fullfile(caseDirectory, 'protected_after.csv'));
fprintf('END_NAK_ENTHALPY_CANDIDATE_%d_SUCCESS=%d_SECONDS=%.3f\n', ...
    stopTime, success, seconds);
assert(success, out.ErrorMessage);
end

function logPort(block, port, name)
handles = get_param(block, 'PortHandles');
set_param(handles.Outport(port), 'DataLogging', 'on', ...
    'DataLoggingNameMode', 'Custom', 'DataLoggingName', name);
end

function closeModel(model)
if bdIsLoaded(model), close_system(model, 0); end
end

function checkProtected(tableValue)
for k = 1:height(tableValue)
    assert(hashFile(tableValue.paths(k)) == tableValue.hashes(k), tableValue.paths(k));
end
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
