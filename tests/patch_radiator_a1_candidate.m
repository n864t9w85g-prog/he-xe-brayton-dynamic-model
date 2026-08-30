function audit = patch_radiator_a1_candidate(model, manifestPath, outputDir)
%PATCH_RADIATOR_A1_CANDIDATE Exploration-only official-API patch.
model = string(model);
manifestPath = string(manifestPath);
outputDir = string(outputDir);
repo = string(fileparts(fileparts(mfilename('fullpath'))));
file = string(get_param(model, 'FileName'));
assert(startsWith(file, fullfile(repo, 'tmp') + filesep));
assert(startsWith(manifestPath, fullfile(repo, 'tmp') + filesep));
assert(startsWith(outputDir, fullfile(repo, 'tmp') + filesep));
sourceHash = hashFile(file);
assert(sourceHash == ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
manifest = jsondecode(fileread(manifestPath));
assert(manifest.eligible_for_slx);
assert(~manifest.paper_reproduced && ~manifest.formal_promotion);

expected = {
    model + "/Constant", 'Constant', 'Value', '6.95';
    model + "/rediator/T_env", 'Constant', 'Value', '225';
    model + "/rediator/Subsystem/Constant", ...
        'Constant', 'Value', 'epsilon';
    model + "/rediator/Subsystem/Constant2", ...
        'Constant', 'Value', '1113';
    model + "/rediator/Subsystem/Constant3", ...
        'Constant', 'Value', '5744';
    model + "/rediator/Subsystem/Constant4", ...
        'Constant', 'Value', 'Cp_rad';
    model + "/rediator/Subsystem/Constant5", ...
        'Constant', 'Value', '9.755'};
for k = 1:size(expected, 1)
    assert(strcmp(get_param(expected{k,1}, 'BlockType'), expected{k,2}));
    assert(strcmp(get_param(expected{k,1}, expected{k,3}), expected{k,4}));
end
tho = model + "/rediator/Tho";
assert(strcmp(get_param(tho, 'BlockType'), 'Fcn'));
assert(strcmp(get_param(tho, 'Expr'), ...
    '((u(2)-0.8)*u(3)+u(1))/(u(2)+0.2)'));

before = radiator_a1_model_inventory(model);
position = get_param(tho, 'Position');
orientation = get_param(tho, 'Orientation');
delete_block(tho);
add_block('simulink/User-Defined Functions/MATLAB Function', tho, ...
    'Position', position, 'Orientation', orientation);
root = sfroot();
chart = root.find('-isa', 'Stateflow.EMChart', 'Path', tho);
assert(numel(chart) == 1);
chart.Script = integralScript();
ensureLine(model + "/rediator", 'Mux4/1', 'Tho/1');
ensureLine(model + "/rediator", 'Tho/1', 'Mux2/6');
ensureLine(model + "/rediator", 'Tho/1', 'T_ho/1');

set_param(model + "/Constant", ...
    'Value', number(manifest.m_dot_NaK_kg_s));
set_param(model + "/rediator/T_env", ...
    'Value', number(manifest.T_sink_K));
set_param(model + "/rediator/Subsystem/Constant", ...
    'Value', number(manifest.epsilon));
set_param(model + "/rediator/Subsystem/Constant2", ...
    'Value', number(manifest.A_rad_m2));
set_param(model + "/rediator/Subsystem/Constant3", ...
    'Value', number(manifest.M_rad_kg));
set_param(model + "/rediator/Subsystem/Constant4", ...
    'Value', number(manifest.cp_proxy_J_kgK));
set_param(model + "/rediator/Subsystem/Constant5", ...
    'Value', number(manifest.h_W_m2K));
set_param(model, 'SimulationCommand', 'update');
after = radiator_a1_model_inventory(model);
assert(isequal(before.settings, after.settings));
assertOnlyWhitelisted(before, after);

save_system(model, file);
close_system(model, 0);
load_system(file);
reopened = radiator_a1_model_inventory(model);
assert(isequal(after, reopened), 'Saved inventory changed on reopen');
candidateHash = hashFile(file);
changed = ["Constant"; "rediator/Subsystem/Constant"; ...
    "rediator/Subsystem/Constant2"; ...
    "rediator/Subsystem/Constant3"; ...
    "rediator/Subsystem/Constant4"; ...
    "rediator/Subsystem/Constant5"; ...
    "rediator/T_env"; "rediator/Tho"];
audit = struct( ...
    'candidate_id', string(manifest.candidate_id), ...
    'source_sha256', sourceHash, ...
    'candidate_sha256', candidateHash, ...
    'manifest_sha256', hashFile(manifestPath), ...
    'patch_sha256', hashFile(string(mfilename('fullpath')) + ".m"), ...
    'changed_parameter_paths', changed, ...
    'official_api_only', true, ...
    'paper_reproduced', false, ...
    'formal_promotion', false);
writeJSON(fullfile(outputDir, 'patch_manifest.json'), audit);
writeJSON(fullfile(outputDir, 'structural_diff.json'), ...
    struct('before', before, 'after', after, 'whitelist_pass', true));
end

function assertOnlyWhitelisted(before, after)
allowed = ["/Constant|Value"; "/rediator/T_env|Value"; ...
    "/rediator/Subsystem/Constant|Value"; ...
    "/rediator/Subsystem/Constant2|Value"; ...
    "/rediator/Subsystem/Constant3|Value"; ...
    "/rediator/Subsystem/Constant4|Value"; ...
    "/rediator/Subsystem/Constant5|Value"];
beforeKeys = string({before.parameters.key});
beforeValues = string({before.parameters.value});
afterKeys = string({after.parameters.key});
afterValues = string({after.parameters.value});
allKeys = union(beforeKeys, afterKeys);
for key = reshape(allKeys, 1, [])
    if startsWith(key, "/rediator/Tho|") || ...
            startsWith(key, "/rediator/Tho/")
        continue
    end
    beforeIndex = find(beforeKeys == key);
    afterIndex = find(afterKeys == key);
    assert(isscalar(beforeIndex) && isscalar(afterIndex));
    if beforeValues(beforeIndex) ~= afterValues(afterIndex)
        assert(any(key == allowed), "Unexpected parameter change: " + key);
    end
end
beforeBlocks = string({before.blocks.relative});
afterBlocks = string({after.blocks.relative});
assert(isequal( ...
    beforeBlocks(~startsWith(beforeBlocks, "/rediator/Tho")), ...
    afterBlocks(~startsWith(afterBlocks, "/rediator/Tho"))));
beforeEdges = string(before.edges);
afterEdges = string(after.edges);
assert(isequal( ...
    beforeEdges(~contains(beforeEdges, "/rediator/Tho")), ...
    afterEdges(~contains(afterEdges, "/rediator/Tho"))));
end

function text = integralScript()
lines = [
    "function Tout = nak_enthalpy_outlet(u)"
    "%#codegen"
    "% Exploration-only analytic integral of the existing NaK cp(T)."
    "Twall=u(1); r=u(2); Tin=u(3);"
    "cpin=1000*(1.061-3.694e-4*Tin+4.615e-8*Tin^2+1.509e-10*Tin^3);"
    "assert(isfinite(Twall)&&isfinite(r)&&isfinite(Tin)&&cpin>0&&r>0);"
    "lo=260.5; hi=Tin; assert(hi>lo&&Twall<Tin);"
    "hTin=1000*(1.061*Tin-3.694e-4*Tin^2/2+4.615e-8*Tin^3/3+1.509e-10*Tin^4/4);"
    "hLo=1000*(1.061*lo-3.694e-4*lo^2/2+4.615e-8*lo^3/3+1.509e-10*lo^4/4);"
    "fLo=(r/cpin)*(hTin-hLo)-(0.8*Tin+0.2*lo-Twall);"
    "fHi=-(Tin-Twall); assert(fLo>=0&&fHi<=0);"
    "for k=1:60"
    " mid=0.5*(lo+hi);"
    " hMid=1000*(1.061*mid-3.694e-4*mid^2/2+4.615e-8*mid^3/3+1.509e-10*mid^4/4);"
    " fMid=(r/cpin)*(hTin-hMid)-(0.8*Tin+0.2*mid-Twall);"
    " if fMid>=0, lo=mid; else, hi=mid; end"
    "end"
    "Tout=0.5*(lo+hi);"
    "end"];
text = strjoin(lines, newline);
end

function ensureLine(system, source, destination)
destinationBlock = extractBefore(string(destination), "/");
destinationPort = str2double(extractAfter(string(destination), "/"));
handles = get_param(system + "/" + destinationBlock, 'PortHandles');
line = get_param(handles.Inport(destinationPort), 'Line');
if line < 0
    add_line(system, source, destination, 'autorouting', 'on');
else
    sourceHandle = get_param(line, 'SrcPortHandle');
    assert(string(get_param(sourceHandle, 'Parent')) == ...
        system + "/" + extractBefore(string(source), "/"));
end
end

function value = number(input)
value = char(string(num2str(double(input), '%.17g')));
end

function value = hashFile(path)
[status, output] = system("shasum -a 256 '" + ...
    replace(string(path), "'", "'\''") + "'");
assert(status == 0);
parts = split(strtrim(string(output)));
value = parts(1);
end

function writeJSON(path, value)
assert(~isfile(path));
file = fopen(path, 'w');
assert(file >= 0);
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', jsonencode(value, PrettyPrint=true));
end
