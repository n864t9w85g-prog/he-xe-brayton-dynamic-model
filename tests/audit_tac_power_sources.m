function audit_tac_power_sources(runDirectory)
% Read-only saved-state reconstruction with the unchanged official property.
% No SLX loading/simulation, Scheme A, H1b activation, fitting or model writes.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,string(runDirectory)); assert(isfolder(dest));
assert(startsWith(dest,fullfile(repo,'tmp')+filesep));
assert(~isfile(fullfile(dest,'summary.json')) && ~isfile(fullfile(dest,'diary.txt')));
diary(fullfile(dest,'diary.txt')); cleanupDiary=onCleanup(@() diary('off'));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
savedDirectory=pwd;cleanupDirectory=onCleanup(@() cd(savedDirectory));cd(dest);
savedPath=path;cleanupPath=onCleanup(@() path(savedPath));addpath(source);
savedWarnings=warning;cleanupWarning=onCleanup(@() warning(savedWarnings));
warning('error','HeXe:T_lo');warning('error','HeXe:T_hi');
warning('error','MATLAB:quadgk:MaxIntervalCountReached');
warning('error','MATLAB:quadgk:NonFiniteValue');
prop=fullfile(source,'HeXe_property_simulink.m');
assert(string(which('HeXe_property_simulink'))==prop);
assert(hashFile(prop)=="2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640','protected_after.csv'),TextType='string');
checkProtected(protected);writetable(protected,fullfile(dest,'protected_before.csv'));
prior=fullfile(fileparts(repo),'不接入转子稳态模型_副本','tmp','steady53','task8', ...
    'run_1787845512573_a1e82217bf864a55aceb5277bc0a0660');
manifestFile=fullfile(prior,'manifest.json');manifest=jsondecode(fileread(manifestFile));
modelHash="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
assert(string(manifest.sourceModelHash)==modelHash);
rawFile=fullfile(prior,manifest.rawMatFile);assert(hashFile(rawFile)==string(manifest.rawMatHash));
for k=1:numel(manifest.smallFileHashes)
    q=manifest.smallFileHashes(k);assert(hashFile(fullfile(prior,q.name))==string(q.sha256));
end
data=load(rawFile,'result');r=data.result;
assert(r.success && r.tFinal_s==500 && r.modelHashBefore==modelHash && r.modelHashAfter==modelHash);
s=r.signals;names=fieldnames(s);point=struct();
for k=1:numel(names),point.(names{k})=s.(names{k})(end);end
N=point.rotor_speed;mc=point.hexe_mdot_compressor;mt=point.hexe_mdot_turbine;
assert(abs(N-55090)<1e-10);
C=load(fullfile(source,'hexe_compressor_lookup.mat'));
F=load(fullfile(source,'turbine_table1.mat'));
E=load(fullfile(source,'turbine_table2.mat'));
ns=N/55090;mr=mc/12.04;
assert(abs(ns-point.compressor_lookup_speed_pr)<1e-12);
assert(abs(mr-point.compressor_lookup_flow_pr)<1e-12);
assert(ns>=min(C.speed_bp)&&ns<=max(C.speed_bp)&&mr>=min(C.m_ratio_bp)&&mr<=max(C.m_ratio_bp));
pr=interpn(C.speed_bp,C.m_ratio_bp,C.PR_table,ns,mr,'linear');
ec=interpn(C.speed_bp,C.m_ratio_bp,C.ETAT_table,ns,mr,'linear');
er=point.turbine_lookup_expansion_ratio;
mtLookup=interpn(F.bp_er,F.bp_speed,F.table_mf,er,N,'linear');
et=interpn(E.bp_mf,E.bp_speed,E.table_eff,mt,N,'linear');
assert(abs(pr-point.turbine_expansion_ratio)<1e-10);
assert(abs(mtLookup-mt)<1e-9);
assert(abs(point.turbine_inlet_P/er-point.turbine_outlet_P)<1e-6);
% In SLX, expansion ratio uses normalized pressure drops, not compressor r.
erFromDrops=pr*(1-.005158-.002579)/(1+pr*(0+.011605));
assert(abs(erFromDrops-er)<1e-10);

co=machine('compressor',point.compressor_inlet_T,point.compressor_inlet_P,pr,ec,mc);
tu=machine('turbine',point.turbine_inlet_T,point.turbine_inlet_P,er,et,mt);
assert(abs(co.Tout_K-point.compressor_outlet_T)<1e-7);
assert(abs(tu.Tout_K-point.turbine_outlet_T)<1e-7);
assert(abs(co.W_W-point.compressor_power)<1e-4);
assert(abs(tu.W_W-point.turbine_power)<1e-4);
% Algebraically, inlet cp cancels between Tout formula and W formula.
assert(abs(co.W_W-mc*co.cp_isentropic_J_kgK*(co.Tis_K-co.Tin_K)/ec)<1e-7);
assert(abs(tu.W_W-mt*tu.cp_isentropic_J_kgK*(tu.Tin_K-tu.Tis_K)*et)<1e-7);

% Actual baseline inputs are fixed in each one-at-a-time counterfactual.
% Paper eta=.85/.87 are DESIGN references, not claimed Table5.2 measured eta.
cf=struct([]);
cf=addCase(cf,'compressor_Tin_only',co,machine('compressor',405.16,co.Pin_Pa,pr,ec,mc));
cf=addCase(cf,'compressor_Pin_only',co,machine('compressor',co.Tin_K,658000,pr,ec,mc));
cf=addCase(cf,'compressor_ratio_only',co,machine('compressor',co.Tin_K,co.Pin_Pa,1551000/658000,ec,mc));
cf=addCase(cf,'turbine_Tin_only',tu,machine('turbine',1522.96,tu.Pin_Pa,er,et,mt));
cf=addCase(cf,'turbine_Pin_only',tu,machine('turbine',tu.Tin_K,1539000,er,et,mt));
cf=addCase(cf,'turbine_ratio_only',tu,machine('turbine',tu.Tin_K,tu.Pin_Pa,1539000/676000,et,mt));
% No efficiency/flow scan: the current tables and flow inputs remain fixed.

% Fixed endpoint power accounting, not a self-consistent new machine solution.
paperInputs=[405.16 601.90 658000 1551000 1231600; ...
             1522.96 1162 1539000 676000 2252200];
states={co,tu};labels=["compressor","turbine"];accounting=struct([]);samples=[];
for k=1:2
    a=states{k};v=paperInputs(k,:);dta=abs(a.Tout_K-a.Tin_K);dtp=abs(v(2)-v(1));
    [cpp,~,~]=HeXe_property_simulink(v(1),v(3));
    % Explicit ordered identity: replace deltaT, then inlet-cp evaluation.
    dTemperature=a.mdot_kg_s*a.cp_inlet_J_kgK*(dtp-dta);
    dCp=a.mdot_kg_s*(cpp-a.cp_inlet_J_kgK)*dtp;
    referencePower=a.mdot_kg_s*cpp*dtp;
    remaining=v(5)-referencePower;
    assert(abs((v(5)-a.W_W)-dTemperature-dCp-remaining)<1e-6);
    cpa=pathAverage(a.Tin_K,a.Tout_K,a.Pin_Pa);
    cppath=pathAverage(v(1),v(2),v(3));
    item=struct('machine',labels(k),'paper_Tin_K',v(1),'paper_Tout_K',v(2), ...
        'paper_Pin_Pa',v(3),'paper_Pout_Pa',v(4),'paper_power_W',v(5), ...
        'actual_deltaT_K',dta,'paper_deltaT_K',dtp,'official_cp_at_paper_inlet',cpp, ...
        'actual_to_paper_power_difference_W',v(5)-a.W_W, ...
        'ordered_deltaT_contribution_W',dTemperature,'ordered_cp_contribution_W',dCp, ...
        'fixed_actual_flow_paper_endpoints_power_W',referencePower, ...
        'remaining_power_gap_at_paper_endpoints_W',remaining, ...
        'inverse_flow_with_point_cp_kg_s',v(5)/(cpp*dtp), ...
        'actual_path_cpbar',cpa,'paper_path_cpbar',cppath, ...
        'fixed_actual_endpoints_cpbar_power_W',a.mdot_kg_s*cpa.cpbar*dta, ...
        'cpbar_readout_change_W',a.mdot_kg_s*(cpa.cpbar-a.cp_inlet_J_kgK)*dta, ...
        'inverse_flow_with_cpbar_kg_s',v(5)/(cppath.cpbar*dtp));
    if k==1,accounting=item;else,accounting(k)=item;end
    for branch=1:2
        if branch==1,ti=a.Tin_K;to=a.Tout_K;p=a.Pin_Pa;else,ti=v(1);to=v(2);p=v(3);end
        for T=linspace(min(ti,to),max(ti,to),1001)
            [cp,gamma,rho]=HeXe_property_simulink(T,p);
            assert(cp>0&&gamma>1&&rho>0&&all(isfinite([cp gamma rho])));
            samples(end+1,:)=[k branch T p cp cp/gamma gamma rho]; %#ok<AGROW>
        end
    end
end
writetable(array2table(samples,VariableNames={'machine_index','branch_actual_or_paper', ...
    'T_K','P_Pa','cp_J_kgK','cv_J_kgK','gamma','rho_kg_m3'}),fullfile(dest,'cp_path_samples.csv'));
writetable(struct2table(cf),fullfile(dest,'single_factor_cases.csv'));
tables=struct('compressor',struct('speed_bp',C.speed_bp,'m_ratio_bp',C.m_ratio_bp, ...
    'PR_table',C.PR_table,'ETAT_table',C.ETAT_table), ...
    'turbine_flow',F,'turbine_efficiency',E);
lookup=struct('speed_ratio',ns,'flow_ratio',mr,'compressor_r',pr,'compressor_eta',ec, ...
    'turbine_expansion_ratio',er,'turbine_expansion_from_drops',erFromDrops, ...
    'turbine_mass_flow_from_map',mtLookup,'turbine_eta',et);
checkProtected(protected);writetable(protected,fullfile(dest,'protected_after.csv'));
files=[string(mfilename('fullpath'))+".m",prop,rawFile,manifestFile, ...
    fullfile(source,'hexe_compressor_lookup.mat'),fullfile(source,'turbine_table1.mat'), ...
    fullfile(source,'turbine_table2.mat'),fullfile(source,'final_steady_24a.slx'), ...
    fullfile(source,'tests','steady53','steady53_signal_manifest.m'), ...
    fullfile(repo,'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf')];
hashes=struct([]);for k=1:numel(files),hashes(k).path=files(k);hashes(k).sha256=hashFile(files(k));end
out=struct('record_kind','Saved 500 s instrumented run, same SLX hash, not the 14000 s trajectory.', ...
    'saved_point',point,'saved_time_s',r.t(end),'lookup',lookup,'tables',tables, ...
    'compressor',co,'turbine',tu,'single_factor_cases',cf,'accounting',accounting, ...
    'source_hashes',hashes,'protected_count',height(protected),'scheme_A_used',false, ...
    'H1b_activated',false,'no_SLX_loaded_or_simulated',true,'model_acceptance_passed',false, ...
    'scope','Official-property offline reconstruction and fixed-state accounting. Single-factor changes hold other machine inputs and maps fixed; no closed-loop causality claim or parameter promotion.');
fid=fopen(fullfile(dest,'summary.json'),'w');assert(fid>=0);fprintf(fid,'%s\n',jsonencode(out,PrettyPrint=true));fclose(fid);
disp(co);disp(tu);disp(lookup);disp(struct2table(cf));disp(accounting);
fprintf('TAC_POWER_SOURCE_RECONSTRUCTION_PASS; OFFICIAL_PROPERTY_ONLY; NO_SIMULATION; PROTECTED=34\n');
end
function a=machine(kind,T,P,ratio,eta,m)
[cp1,gamma,~]=HeXe_property_simulink(T,P);phi=1-1/gamma;
if strcmp(kind,'compressor'),Tis=T*ratio^phi;Pout=P*ratio;sgn=1;
else,Tis=T*ratio^(-phi);Pout=P/ratio;sgn=-1;end
[cp2,~,~]=HeXe_property_simulink(Tis,Pout);
if sgn==1,Tout=T+cp2*(Tis-T)/(cp1*eta);else,Tout=T-eta*cp2*(T-Tis)/cp1;end
W=m*cp1*abs(Tout-T);
a=struct('kind',kind,'Tin_K',T,'Pin_Pa',P,'ratio',ratio,'eta',eta,'mdot_kg_s',m, ...
    'gamma_inlet',gamma,'cp_inlet_J_kgK',cp1,'cp_isentropic_J_kgK',cp2, ...
    'Tis_K',Tis,'Pout_Pa',Pout,'Tout_K',Tout,'W_W',W);
end
function cases=addCase(cases,name,before,after)
row=struct('name',name,'Tin_K',after.Tin_K,'Pin_Pa',after.Pin_Pa,'ratio',after.ratio, ...
    'eta',after.eta,'mdot_kg_s',after.mdot_kg_s,'Tout_K',after.Tout_K, ...
    'power_W',after.W_W,'power_change_W',after.W_W-before.W_W);
if isempty(cases),cases=row;else,cases(end+1)=row;end
end
function result=pathAverage(Ti,To,P)
assert(~(min(Ti,To)<992.3824092088217&&max(Ti,To)>992.3824092088217));
f=@(ts) arrayfun(@(t) officialCp(t,P),ts);
[q,e]=quadgk(f,Ti,To,'RelTol',1e-10,'AbsTol',1e-6);
x=linspace(Ti,To,2001);y=f(x);q2=(To-Ti)/2000/3*(y(1)+y(end)+4*sum(y(2:2:end-1))+2*sum(y(3:2:end-2)));
assert(abs(q-q2)<1e-4);
result=struct('cpbar',q/(To-Ti),'temperature_integral_J_kg',q, ...
    'simpson_J_kg',q2,'quadgk_error',e,'pressure_held_Pa',P, ...
    'pressure_enthalpy_term_included',false);
end
function cp=officialCp(T,P)
[cp,~,~]=HeXe_property_simulink(T,P);assert(isfinite(cp)&&cp>0);
end
function checkProtected(t)
for k=1:height(t),assert(hashFile(t.paths(k))==t.hashes(k),t.paths(k));end
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
