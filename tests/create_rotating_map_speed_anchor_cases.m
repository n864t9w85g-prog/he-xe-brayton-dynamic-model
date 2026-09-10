function manifest = create_rotating_map_speed_anchor_cases( ...
        repoRoot, sourceRunRoot, outputRunRoot)
%CREATE_ROTATING_MAP_SPEED_ANCHOR_CASES Patch 66100->55090 in API copies.

arguments
    repoRoot (1,1) string
    sourceRunRoot (1,1) string
    outputRunRoot (1,1) string
end
repoRoot = canonicalPath(repoRoot, true);
sourceRunRoot = canonicalPath(sourceRunRoot, true);
outputRunRoot = canonicalPath(outputRunRoot, false);
tmpRoot = canonicalPath(fullfile(repoRoot, "tmp"), true);
if ~startsWith(outputRunRoot, tmpRoot + filesep)
    error("rotatingMap:OutputOutsideTmp", ...
        "Speed-anchor cases must remain under repository tmp.");
end
if isfolder(outputRunRoot) || isfile(outputRunRoot)
    error("rotatingMap:OutputExists", ...
        "Refusing to overwrite speed-anchor output.");
end

formalPath = fullfile(repoRoot, "final_steady_24a.slx");
formalHash = sha256File(formalPath);
mkdir(outputRunRoot);
modelDir = fullfile(outputRunRoot, "models");
bundleDir = fullfile(outputRunRoot, "bundles");
mkdir(modelDir);
mkdir(bundleDir);
try
    startPath = replace(fullfile(repoRoot, "start.m"), "'", "''");
    evalin("base", "run('" + startPath + "')");
    cases = struct([]);
    for caseId = ["C0", "C1", "C2", "C3"]
        sourceModelPath = fullfile(sourceRunRoot, "models", ...
            caseId + "_model.slx");
        sourceBundlePath = fullfile(sourceRunRoot, "bundles", ...
            caseId + "_lookup.mat");
        if ~isfile(sourceModelPath) || ~isfile(sourceBundlePath)
            error("rotatingMap:MissingSourceCase", ...
                "Missing prior Gate 2 source for %s.", caseId);
        end
        sourceModelHash = sha256File(sourceModelPath);
        bundle = load(sourceBundlePath);
        assignBundleToBase(bundle);
        destinationBundlePath = fullfile(bundleDir, ...
            caseId + "_lookup.mat");
        copyfile(sourceBundlePath, destinationBundlePath, "f");
        destinationModelPath = fullfile(modelDir, ...
            caseId + "_model.slx");
        model = caseId + "_model";
        if bdIsLoaded(model)
            error("rotatingMap:ModelAlreadyLoaded", ...
                "Refusing to modify loaded model %s.", model);
        end
        load_system(sourceModelPath);
        cleanup = onCleanup(@() closeIfLoaded(model)); %#ok<NASGU>
        speedBlock = model + "/TAC/Constant";
        oldSpeed = str2double(string(get_param(speedBlock, "Value")));
        if oldSpeed ~= 66100
            error("rotatingMap:UnexpectedSourceSpeed", ...
                "Expected the diagnosed 66100 rpm source in %s.", caseId);
        end
        set_param(speedBlock, "Value", "55090");
        set_param(model, "SimulationCommand", "update");
        save_system(model, destinationModelPath);
        close_system(model, 0);
        clear cleanup
        if sha256File(sourceModelPath) ~= sourceModelHash
            error("rotatingMap:SourceModelWasModified", ...
                "Source candidate model changed while creating %s.", caseId);
        end
        record = struct( ...
            "case_id", caseId, ...
            "source_model_repository_path", ...
                relativePath(sourceModelPath, repoRoot), ...
            "source_model_sha256", sourceModelHash, ...
            "model_repository_path", ...
                relativePath(destinationModelPath, repoRoot), ...
            "model_sha256", sha256File(destinationModelPath), ...
            "bundle_repository_path", ...
                relativePath(destinationBundlePath, repoRoot), ...
            "bundle_sha256", sha256File(destinationBundlePath), ...
            "changed_block", "TAC/Constant", ...
            "changed_parameter", "Value", ...
            "old_speed_rpm", oldSpeed, ...
            "new_speed_rpm", 55090, ...
            "simulation_call_count", 0, ...
            "formal_promotion", false);
        if isempty(cases)
            cases = record;
        else
            cases(end + 1) = record; %#ok<AGROW>
        end
    end
    if sha256File(formalPath) ~= formalHash
        error("rotatingMap:FormalModelWasModified", ...
            "Formal steady model changed during API copy creation.");
    end
    manifest = struct( ...
        "schema", "rotating_map_speed_anchor_cases_v1", ...
        "hypothesis", ...
            "66100 rpm conflicts with the 55090 rpm paper/design anchor", ...
        "changed_physical_parameter_count", 1, ...
        "formal_model_sha256", formalHash, ...
        "cases", cases, ...
        "simulation_call_count", 0, ...
        "formal_promotion", false);
    writelines(jsonencode(manifest, "PrettyPrint", true), ...
        fullfile(outputRunRoot, "speed_anchor_manifest.json"));
catch exception
    for caseId = ["C0", "C1", "C2", "C3"]
        closeIfLoaded(caseId + "_model");
    end
    if isfolder(outputRunRoot)
        rmdir(outputRunRoot, "s");
    end
    rethrow(exception)
end
end

function assignBundleToBase(bundle)
names = ["compressor_speed_bp", "compressor_flow_bp", ...
    "compressor_pr_table", "compressor_eta_table", ...
    "turbine_er_bp", "turbine_speed_bp", "turbine_flow_table", ...
    "turbine_mf_bp", "turbine_eta_table"];
for name = names
    assignin("base", name, bundle.(name));
end
end

function closeIfLoaded(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function value = relativePath(pathValue, repoRoot)
pathValue = canonicalPath(pathValue, true);
if ~startsWith(pathValue, repoRoot + filesep)
    error("rotatingMap:PathOutsideRepository", ...
        "Path escaped repository root.");
end
value = extractAfter(pathValue, strlength(repoRoot) + 1);
end

function value = sha256File(pathValue)
bytes = java.nio.file.Files.readAllBytes(java.nio.file.Paths.get( ...
    char(pathValue), javaArray("java.lang.String", 0)));
digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes);
value = string(lower(reshape(dec2hex( ...
    typecast(digest, "uint8"), 2).', 1, [])));
end

function value = canonicalPath(pathValue, mustExist)
file = java.io.File(char(pathValue));
if mustExist && ~file.exists()
    error("rotatingMap:MissingInput", ...
        "Required input does not exist: %s", pathValue);
end
value = string(file.getCanonicalPath());
end

