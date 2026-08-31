function tests = test_audit_fig519_initialization
%TEST_AUDIT_FIG519_INITIALIZATION Contract for the read-only Figure 5.19 audit.
tests = functiontests(localfunctions);
end

function testReadOnlyInitializationAudit(testCase)
repo = string(fileparts(fileparts(mfilename("fullpath"))));
tmpRoot = fullfile(repo, "tmp");
if ~isfolder(tmpRoot)
    mkdir(tmpRoot);
end
outputDir = string(tempname(tmpRoot));
cleanup = onCleanup(@() cleanupOwnedOutput(outputDir));

fixedRaw = fullfile(tmpRoot, "fig519_initialization_20260831_A1", ...
    "raw_reference.mat");
result = audit_fig519_initialization(outputDir, fixedRaw);

verifyEqual(testCase, result.model_sha256, ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
verifyEqual(testCase, result.state_count, 40);
verifyEqual(testCase, result.reference_final_time_s, 500);
verifyTrue(testCase, result.reference_success);
verifyFalse(testCase, result.direct_generator_signal_found);
verifyTrue(testCase, result.source_hash_unchanged);
verifyFalse(testCase, result.paper_reproduced);
verifyFalse(testCase, result.formal_promotion);
verifyFalse(testCase, result.repeated_prior_experiment);
verifyEqual(testCase, result.reference_run_reason, ...
    "missing direct state and derivative evidence in prior saved baseline");
verifyNotEmpty(testCase, result.solver_contract.solver_name);
verifyTrue(testCase, result.solver_contract.stop_time_dependency_checked);
verifyTrue(testCase, result.boundary_contract.all_inputs_classified);
verifyTrue(testCase, result.boundary_contract.load_input_classified);
verifyTrue(testCase, result.initial_residuals.all_items_accounted_for);
verifyTrue(testCase, result.flat_start_explanation.has_state_evidence);
verifyTrue(testCase, result.flat_start_explanation.has_signal_path_evidence);
verifyEqual(testCase, result.protected_manifest.resolved_count, 34);
verifyEqual(testCase, result.protected_manifest.unresolved_count, 0);
verifyTrue(testCase, result.runtime_dependency_contract.all_paths_durable);
verifyEqual(testCase, result.runtime_dependency_contract.dependency_count, 9);

inventory = result.state_inventory;
verifyEqual(testCase, numel(inventory), 40);
paths = string({inventory.path});
reactorPower = inventory(paths == "final_steady_24a/reactor/Integrator6");
reactorTemperature = inventory(paths == "final_steady_24a/reactor/Integrator7");
verifyEqual(testCase, numel(reactorPower), 1);
verifyEqual(testCase, numel(reactorTemperature), 1);
verifyEqual(testCase, reactorPower.initial_condition, ...
    2660960.9141046703, "AbsTol", 1e-9);
verifyEqual(testCase, reactorTemperature.initial_condition, ...
    1721.8648882133552, "AbsTol", 1e-12);
for index = 1:numel(inventory)
    verifyTrue(testCase, isfinite(inventory(index).t0_value));
    verifyTrue(testCase, isfinite(inventory(index).t500_value));
    verifyTrue(testCase, isfinite(inventory(index).absolute_change));
    verifyTrue(testCase, isfinite(inventory(index).first_sample_slope));
end

fixedSections = ["state_inventory", "boundary_contract", ...
    "solver_contract", "power_signal_paths", "initial_residuals", ...
    "flat_start_explanation"];
for section = fixedSections
    verifyTrue(testCase, isfield(result, section), ...
        "Missing fixed audit section: " + section);
end

residualNames = ["reactor_power_derivative", "shaft_excess_power", ...
    "ihx_energy", "recuperator_energy", "precooler_energy", ...
    "radiator_energy"];
records = result.initial_residuals.items;
verifyEqual(testCase, sort(string({records.name})), sort(residualNames));
for index = 1:numel(records)
    record = records(index);
    verifyTrue(testCase, any(string(record.status) == ...
        ["computed", "not_observable"]));
    if string(record.status) == "computed"
        verifyTrue(testCase, isfinite(record.value));
        verifyNotEmpty(testCase, record.unit);
        verifyNotEmpty(testCase, record.formula);
        verifyNotEmpty(testCase, record.source_paths);
    else
        verifyNotEmpty(testCase, record.missing_direct_signals);
    end
end

shaft = records(string({records.name}) == "shaft_excess_power");
verifyEqual(testCase, numel(shaft), 1);
verifyEqual(testCase, string(shaft.status), "computed");
verifyEqual(testCase, shaft.value, 35934.17908170889, "AbsTol", 1e-6);
verifyEqual(testCase, string(shaft.unit), "W");
verifyEqual(testCase, string(shaft.formula), "WT(t0)-Wc(t0)-Pload");
verifyTrue(testCase, all(ismember([ ...
    "final_steady_24a/TAC/Turbine", ...
    "final_steady_24a/TAC/Compressor", ...
    "final_steady_24a/Constant14", ...
    "final_steady_24a/TAC/Pload"], string(shaft.source_paths))));

loadPath = result.power_signal_paths.load;
verifyEqual(testCase, string(loadPath.status), "verified_by_official_api");
verifyEqual(testCase, string(loadPath.source_block), ...
    "final_steady_24a/Constant14");
verifyEqual(testCase, string(loadPath.destination_block), ...
    "final_steady_24a/TAC");
verifyEqual(testCase, loadPath.destination_input_port, 6);
verifyEqual(testCase, string(loadPath.destination_inport_block), ...
    "final_steady_24a/TAC/Pload");
verifyEqual(testCase, loadPath.value_W, 1000.21e3, "AbsTol", 1e-9);

flat = result.flat_start_explanation;
verifyEqual(testCase, flat.near_zero_rule.metric, ...
    "abs(first_sample_slope)/max(abs(t0_value),1)");
verifyGreaterThan(testCase, flat.near_zero_rule.threshold_per_s, 0);
verifyNotEmpty(testCase, flat.near_zero_state_derivatives);
verifyEqual(testCase, numel(flat.power_state_signal_mappings), 4);
for index = 1:numel(flat.power_state_signal_mappings)
    mapping = flat.power_state_signal_mappings(index);
    verifyNotEmpty(testCase, mapping.traced_state_paths);
    verifyNotEmpty(testCase, mapping.traced_signal_paths);
end
verifyFalse(testCase, flat.paper_initial_state_identified);

verifyFalse(testCase, isfile(fullfile(outputDir, "raw_reference.mat")));
verifyEqual(testCase, result.raw_reference.sha256, ...
    "185d59ca6e55647ad14fb5f23599bc85e6566f8da2ca6120f42a0ef8dedbb648");
jsonPath = fullfile(outputDir, "initialization_audit.json");
verifyTrue(testCase, isfile(jsonPath));
decoded = jsondecode(fileread(jsonPath));
verifyEqual(testCase, string(decoded.model_sha256), result.model_sha256);
verifyFalse(testCase, contains(lower(jsonencode(decoded)), ...
    "initial_conditions_wrong"));
end

function cleanupOwnedOutput(outputDir)
if isfolder(outputDir)
    rmdir(outputDir, "s");
end
end
