scriptDir = fileparts(mfilename('fullpath'));
load(fullfile(scriptDir, 'hexe_compressor_lookup.mat'));
load(fullfile(scriptDir, 'radiator_table.mat'));
load(fullfile(scriptDir, 'turbine_table1.mat'));
load(fullfile(scriptDir, 'turbine_table2.mat'));
sys_param_rad_fixed;
paper54 = paper54_constants();
