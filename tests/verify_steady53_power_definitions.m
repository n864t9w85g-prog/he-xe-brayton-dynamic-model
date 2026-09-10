function verify_steady53_power_definitions(runDirectory)
% Independent arithmetic and original MAT/CSV check. No SLX load or sim.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=string(runDirectory);
if ~startsWith(dest,filesep), dest=fullfile(repo,dest); end
assert(startsWith(dest,fullfile(repo,'tmp')+filesep));
outputFile=fullfile(dest,'matlab_independent_verification.json');
diaryFile=fullfile(dest,'matlab_verification_diary.txt');
assert(~isfile(outputFile) && ~isfile(diaryFile),'Refusing to overwrite evidence.');
diary(diaryFile);diaryCleanup=onCleanup(@() diary('off'));
inputFile=fullfile(dest,'power_definition_audit.json');
audit=jsondecode(fileread(inputFile));
protectedFile=fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640','protected_after.csv');
protected=readtable(protectedFile,TextType='string');
checkProtected(protected);
prior=fullfile(repo,'tmp','steady53_curves_20260828','results');
rawFile=fullfile(prior,'baseline.mat');
raw=load(rawFile,'out','meta'); % Saved data object only, not a model.
assert(string(raw.meta.commit)=="f8bcd833e816eb681982b7dd04364e4b856948e3");
assert(raw.out.tout(end)==14000 && isempty(raw.out.ErrorMessage));
assert(string(raw.meta.sourceFile)==fullfile(repo,'tmp','steady53_curves_20260828', ...
    'source_f8bcd83','final_steady_24a.slx'));
assert(hashFile(raw.meta.sourceFile)=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
names=["WT_sw","Wc_sw","P_sw"]; comparisons=struct([]);last=zeros(1,3);
for k=1:3
    ts=raw.out.get(char(names(k)));
    expected=[ts.Time(:) reshape(ts.Data,numel(ts.Time),[])];
    csvFile=fullfile(prior,"baseline_"+names(k)+".csv");actual=readmatrix(csvFile);
    assert(isequal(size(expected),size(actual)));
    err=max(abs(expected-actual),[],'all');assert(err<1e-7);
    comparisons(k).signal=names(k);comparisons(k).rows=size(actual,1);
    comparisons(k).max_mat_csv_difference=err;
    last(k)=expected(end,2)/1000;
end
net=last(1)-last(2);newElectric=.98*net;oldElectric=.96527*net;
saved=audit.saved_baseline_postprocessing;
assert(abs(net-saved.shaft_net_final_kW)<1e-7);
assert(abs(newElectric-saved.paper_eta_postprocessed_final_kWe)<1e-7);
assert(abs(oldElectric-saved.current_synthesized_final_kWe)<1e-7);
tableResidual=2647.18-1622-(2252.2-1231.6);
assert(abs(tableResidual-4.58)<1e-10);
assert(abs(tableResidual-str2double(audit.arithmetic.heat_minus_shaft_kW))<1e-10);
assert(abs(.98*(2252.2-1231.6)-1000.188)<1e-9);
assert(abs(100*1000.21/2647.18-str2double(audit.arithmetic.electric_over_IHX_percent))<1e-10);
qInverse=1000.21/.3754;
assert(qInverse>2663.5 && qInverse<2664.5);
assert(abs(qInverse-str2double(audit.arithmetic.heat_input_inferred_from_efficiency_kW))<1e-9);
assert(audit.telescoping_identity.candidate_signed_recuperator_gap_kW<0 && tableResidual>0);
checkProtected(protected);
files=[string(mfilename('fullpath'))+".m",inputFile,rawFile,protectedFile];hashes=struct([]);
for k=1:numel(files), hashes(k).path=files(k);hashes(k).sha256=hashFile(files(k));end
result=struct('mat_csv_checks',comparisons,'raw_final_time_s',raw.out.tout(end), ...
    'raw_commit',raw.meta.commit,'source_hashes',hashes,'protected_count',height(protected), ...
    'shaft_net_kW',net,'electric_existing_metric_kWe',oldElectric, ...
    'electric_paper_eta_postprocess_kWe',newElectric,'table_heat_minus_shaft_kW',tableResidual, ...
    'model_loaded_or_simulated',false,'property_function_evaluated',false, ...
    'model_acceptance_passed',false,'scope','Independent saved-MAT and arithmetic verification only.');
fid=fopen(outputFile,'w');assert(fid>=0);fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true));fclose(fid);
disp(result);
fprintf('POWER_DEFINITION_MATLAB_VERIFICATION_PASS; RAW_MAT_MATCHES_CSV; NO_SIMULATION; PROTECTED=34\n');
end
function checkProtected(t)
for n=1:height(t), assert(hashFile(t.paths(n))==t.hashes(n),t.paths(n)); end
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
