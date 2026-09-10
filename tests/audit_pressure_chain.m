function audit_pressure_chain(runDirectory)
% Saved-data and offline recurrence audit. No load_system, sim or model save.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,string(runDirectory));assert(isfolder(dest));
assert(startsWith(dest,fullfile(repo,'tmp')+filesep));
assert(~isfile(fullfile(dest,'audit.json')) && ~isfile(fullfile(dest,'diary.txt')));
diary(fullfile(dest,'diary.txt'));cleanDiary=onCleanup(@() diary('off'));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
oldDir=pwd;cleanDir=onCleanup(@() cd(oldDir));cd(dest);
oldPath=path;cleanPath=onCleanup(@() path(oldPath));addpath(source);
protectedFile=fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640','protected_after.csv');
protected=readtable(protectedFile,TextType='string');checkProtected(protected);
previousFile=fullfile(repo,'tmp','tac_power_trace_Hnbkhl','summary.json');
assert(hashFile(previousFile)=="713468aa5d4f3c3d05bd27b080afca01a0a4da6ee2a70e503ae7110434a4f30c");
previous=jsondecode(fileread(previousFile));
for k=1:numel(previous.source_hashes)
    row=previous.source_hashes(k);assert(hashFile(row.path)==string(row.sha256));
end
rawFile=string(previous.source_hashes(3).path);
d=load(rawFile,'result');r=d.result;assert(r.success&&r.tFinal_s==500);
s=r.signals;
names={'compressor_outlet_P','recuperator_cold_outlet_P','turbine_inlet_P', ...
 'turbine_outlet_P','recuperator_hot_outlet_P','compressor_inlet_P', ...
 'turbine_expansion_ratio','turbine_lookup_expansion_ratio','hexe_mdot_compressor', ...
 'hexe_mdot_turbine','compressor_power','turbine_power'};
all=array2table(r.t(:),VariableNames={'time_s'});
for k=1:numel(names),all.(names{k})=s.(names{k})(:);end
writetable(all,fullfile(dest,'saved_500_aligned_signals.csv'));
% The saved runner linearly aligned individual logs. Use exact ten-second
% timestamps, not the visually interpolated pressure values between them.
times=(0:10:500)';idx=zeros(size(times));
for k=1:numel(times)
    hits=find(abs(r.t-times(k))<1e-8);assert(~isempty(hits));idx(k)=hits(end);
end
hits=all(idx,:);
C=load(fullfile(source,'hexe_compressor_lookup.mat'));
F=load(fullfile(source,'turbine_table1.mat'));
high=12000;low=18000;h=.005158+.002579;l=.011605;
q=1551000;m=11.982029;offline=zeros(numel(times),8);
for k=1:numel(times)
    [rc,er,mt]=mapsAt(m,C,F,h,l);
    qnew=rc*((q-high)/er-low);
    offline(k,:)=[times(k),q,m,rc,er,mt,qnew,qnew-q];
    q=qnew;m=mt;
end
replay=array2table(offline,VariableNames={'time_s','delay_pressure_Pa','delay_flow_kg_s', ...
 'compressor_ratio','turbine_ratio','turbine_flow_kg_s','compressor_outlet_Pa','update_residual_Pa'});
errP=max(abs(replay.compressor_outlet_Pa-hits.compressor_outlet_P));
errM=max(abs(replay.delay_flow_kg_s-hits.hexe_mdot_compressor));
errDelay=max(abs(replay.delay_pressure_Pa-(hits.recuperator_cold_outlet_P+8000)));
assert(errP<1e-5 && errM<1e-10 && errDelay<1e-5);
assert(max(abs(hits.recuperator_cold_outlet_P-hits.turbine_inlet_P-4000))<1e-6);
assert(max(abs(hits.turbine_outlet_P-hits.recuperator_hot_outlet_P))<1e-6);
assert(max(abs(hits.recuperator_hot_outlet_P-hits.compressor_inlet_P-18000))<1e-6);
writetable(hits,fullfile(dest,'saved_500_exact_hits.csv'));
writetable(replay,fullfile(dest,'offline_recurrence.csv'));

root=fzero(@(v) flowResidual(v,C,F,h,l),[11.95 12.04]);
[rstar,estar,mtstar]=mapsAt(root,C,F,h,l);assert(abs(root-mtstar)<1e-10);
alpha=rstar/estar;qstar=(alpha*high+rstar*low)/(alpha-1);
epsm=1e-4;[~,~,mp]=mapsAt(root+epsm,C,F,h,l);[~,~,mm]=mapsAt(root-epsm,C,F,h,l);
lambda=(mp-mm)/(2*epsm);assert(alpha>1&&abs(lambda)<1);
[ranchor,eanchor,manchor]=mapsAt(12.04,C,F,h,l);
rpaper=1551000/658000;epaper=1539000/676000;
exactH=high/1551000;exactL=low/1551000;
epaperExact=rpaper*(1-exactH)/(1+rpaper*exactL);
assert(abs(epaperExact-epaper)<1e-12);
estarExact=rstar*(1-exactH)/(1+rstar*exactL);
tu=previous.turbine;
cases=struct([]);ratios=[estar,eanchor,epaper,estarExact];
labels=["actual","paper_r_with_current_normalized_drops","paper_pressure_ratio", ...
        "actual_r_with_exact_reference_normalized_drops"];
for k=1:numel(ratios)
    [power,tout]=turbinePower(tu,ratios(k));
    row=struct('name',labels(k),'er',ratios(k),'power_W',power, ...
        'Tout_K',tout,'power_change_W',power-tu.W_W);
    if k==1,cases=row;else,cases(k)=row;end
end
assert(abs(cases(1).power_change_W)<1e-4);

baseFile=fullfile(repo,'tmp','steady53_curves_20260828','results','baseline.mat');
assert(hashFile(baseFile)=="18975fc912ed2af87f325769d4be9ab54f4ad0c091f925e4cda5df497aa55698");
base=load(baseFile,'out','meta');assert(base.out.tout(end)==14000&&isempty(base.out.ErrorMessage));
wt=base.out.WT_sw;wc=base.out.Wc_sw;
assert(isequal(wt.Time,wc.Time));
writetable(table(wt.Time(:),wt.Data(:),wc.Data(:),VariableNames={'time_s','Wt_W','Wc_W'}), ...
    fullfile(dest,'saved_14000_power.csv'));
% Preserve saved final states as text; this does not compile or load an SLX.
finalStateText=evalc('disp(base.out.xFinal)');
files=[string(mfilename('fullpath'))+".m",previousFile,rawFile,baseFile, ...
 fullfile(source,'final_steady_24a.slx'),fullfile(source,'HeXe_property_simulink.m'), ...
 fullfile(source,'hexe_compressor_lookup.mat'),fullfile(source,'turbine_table1.mat'), ...
 fullfile(source,'tests','steady53','run_steady53_case.m')];
hashes=struct([]);for k=1:numel(files),hashes(k).path=files(k);hashes(k).sha256=hashFile(files(k));end
out=struct('record_kind','Saved 500 s exact-hit replay plus saved 14000 s power, not a new SLX run.', ...
 'high_absolute_drop_Pa',high,'low_absolute_drop_Pa',low,'normalized_high',h,'normalized_low',l, ...
 'reference_pressure_Pa',1551000,'exact_reference_high',exactH,'exact_reference_low',exactL, ...
 'replay_count',height(replay),'replay_max_pressure_error_Pa',errP,'replay_max_flow_error',errM, ...
 'replay_max_delay_pressure_error_Pa',errDelay,'final_update_residual_Pa',replay.update_residual_Pa(end), ...
 'map_fixed_flow_kg_s',root,'map_fixed_r',rstar,'map_fixed_er',estar,'map_flow_multiplier',lambda, ...
 'pressure_multiplier',alpha,'pressure_fixed_point_Pa',qstar, ...
 'anchor_m_kg_s',12.04,'anchor_r',ranchor,'anchor_er',eanchor,'anchor_turbine_m_kg_s',manchor, ...
 'paper_r',rpaper,'paper_er',epaper,'paper_r_exact_drops_er',epaperExact, ...
 'local_power_cases',cases,'saved_14000_final_state_display',finalStateText, ...
 'source_hashes',hashes,'protected_count',height(protected),'model_loaded_or_simulated',false, ...
 'candidate_A_used',false,'formal_mutations',false,'model_acceptance_passed',false);
checkProtected(protected);writetable(protected,fullfile(dest,'protected_after.csv'));
fid=fopen(fullfile(dest,'audit.json'),'w');assert(fid>=0);fprintf(fid,'%s\n',jsonencode(out,PrettyPrint=true));fclose(fid);
disp(out);disp(struct2table(cases));
fprintf('PRESSURE_CHAIN_REPLAY_PASS; EXACT_HITS=51; NO_SLX_SIMULATION; PROTECTED=34\n');
end
function [r,e,mout]=mapsAt(m,C,F,h,l)
r=interpn(C.speed_bp,C.m_ratio_bp,C.PR_table,1,m/12.04,'linear');
e=r*(1-h)/(1+r*l);
mout=interpn(F.bp_er,F.bp_speed,F.table_mf,e,55090,'linear');
assert(isfinite(r)&&isfinite(e)&&isfinite(mout));
end
function v=flowResidual(m,C,F,h,l)
[~,~,mout]=mapsAt(m,C,F,h,l);v=mout-m;
end
function [w,tout]=turbinePower(tu,e)
[cp,gamma]=HeXe_property_simulink(tu.Tin_K,tu.Pin_Pa);
tis=tu.Tin_K*e^(-(1-1/gamma));
cp2=HeXe_property_simulink(tis,tu.Pin_Pa/e);
tout=tu.Tin_K-tu.eta*cp2*(tu.Tin_K-tis)/cp;
w=tu.mdot_kg_s*cp*(tu.Tin_K-tout);
end
function checkProtected(t)
for k=1:height(t),assert(hashFile(t.paths(k))==t.hashes(k),t.paths(k));end
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
