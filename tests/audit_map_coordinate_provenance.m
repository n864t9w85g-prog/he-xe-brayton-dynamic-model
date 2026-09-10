function audit_map_coordinate_provenance(runDirectory)
% Offline interface/provenance audit only. No SLX load, simulation or save.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,string(runDirectory));
assert(isfolder(dest)&&startsWith(dest,fullfile(repo,'tmp')+filesep));
assert(~isfile(fullfile(dest,'map_audit.json'))&&~isfile(fullfile(dest,'diary.txt')));
diary(fullfile(dest,'diary.txt'));finishDiary=onCleanup(@() diary('off'));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
oldPath=path;finishPath=onCleanup(@() path(oldPath));addpath(source);
oldDir=pwd;finishDir=onCleanup(@() cd(oldDir));cd(dest);
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640', ...
    'protected_after.csv'),TextType='string');checkProtected(protected);
previousFile=fullfile(repo,'tmp','tac_power_trace_Hnbkhl','summary.json');
assert(hashFile(previousFile)=="713468aa5d4f3c3d05bd27b080afca01a0a4da6ee2a70e503ae7110434a4f30c");
previous=jsondecode(fileread(previousFile));
for k=1:numel(previous.source_hashes)
    entry=previous.source_hashes(k);assert(hashFile(entry.path)==string(entry.sha256));
end
C=load(fullfile(source,'hexe_compressor_lookup.mat'));
F=load(fullfile(source,'turbine_table1.mat'));
E=load(fullfile(source,'turbine_table2.mat'));
assert(string(C.version)=="4.0-nasa-tmx2269-candidate");
assert(C.N_design==55090&&C.mdot_design==12.04);
assert(C.T_in_design==405.16&&C.P_in_design==658000);
assert(isfield(C.coordinate_definition,'speed')&&isfield(C.coordinate_definition,'flow'));
states=[struct('name',"declared_design",'mdot',C.mdot_design,'T',C.T_in_design,'P',C.P_in_design), ...
    struct('name',"saved_500_endpoint",'mdot',previous.compressor.mdot_kg_s, ...
    'T',previous.compressor.Tin_K,'P',previous.compressor.Pin_Pa)];
cases=struct([]);count=0;
for i=1:numel(states)
    s=states(i);
    for corrected=[false,true]
        ns=55090/C.N_design;mf=s.mdot/C.mdot_design;
        if corrected
            ns=ns/sqrt(s.T/C.T_in_design);
            mf=mf*sqrt(s.T/C.T_in_design)/(s.P/C.P_in_design);
        end
        assert(ns>=min(C.speed_bp)&&ns<=max(C.speed_bp));
        assert(mf>=min(C.m_ratio_bp)&&mf<=max(C.m_ratio_bp));
        rc=interpn(C.speed_bp,C.m_ratio_bp,C.PR_table,ns,mf,'linear');
        eta=interpn(C.speed_bp,C.m_ratio_bp,C.ETAT_table,ns,mf,'linear');
        er=rc*(1-.005158-.002579)/(1+rc*.011605);
        mt=interpn(F.bp_er,F.bp_speed,F.table_mf,er,55090,'linear');
        assert(all(isfinite([rc,eta,er,mt])));
        [cp1,gamma]=HeXe_property_simulink(s.T,s.P);
        tis=s.T*rc^(1-1/gamma);cp2=HeXe_property_simulink(tis,s.P*rc);
        tout=s.T+cp2*(tis-s.T)/(cp1*eta);
        w=s.mdot*cp1*(tout-s.T);
        row=struct('state',s.name,'use_metadata_coordinates',corrected, ...
            'Tin_K',s.T,'Pin_Pa',s.P,'mdot_kg_s',s.mdot,'N_rpm',55090, ...
            'speed_coordinate',ns,'flow_coordinate',mf,'PR',rc,'eta',eta, ...
            'turbine_ratio',er,'turbine_return_flow_kg_s',mt, ...
            'flow_return_residual_kg_s',mt-s.mdot,'compressor_Tout_K',tout, ...
            'compressor_power_W',w);
        count=count+1;if count==1,cases=row;else,cases(count)=row;end
    end
end
assert(abs(cases(1).PR-cases(2).PR)<1e-12);
assert(abs(cases(3).compressor_power_W-previous.compressor.W_W)<1e-4);
% Compare the calibrated active table to the original archived file, read only.
originalEfficiency=fullfile(repo,'turbine_table2.mat');
assert(hashFile(originalEfficiency)=="cda85dc4480a7723a0ef52bda0fb6f2795e14dfe1167ac74b38a8d64d5b58c33");
E0=load(originalEfficiency);
assert(isequal(E.bp_mf,E0.bp_mf)&&isequal(E.bp_speed,E0.bp_speed));
etaScale=E.table_eff./E0.table_eff;
assert(all(isfinite(etaScale),'all'));
etaScaleResidual=max(abs(E.table_eff-.9711*E0.table_eff),[],'all');
assert(etaScaleResidual<1e-12);
files=[string(mfilename('fullpath'))+".m",previousFile,fullfile(source,'final_steady_24a.slx'), ...
    fullfile(source,'hexe_compressor_lookup.mat'),fullfile(source,'turbine_table1.mat'), ...
    fullfile(source,'turbine_table2.mat'),originalEfficiency, ...
    fullfile(source,'HeXe_property_simulink.m')];
hashes=struct([]);
for k=1:numel(files),hashes(k).path=files(k);hashes(k).sha256=hashFile(files(k));end
out=struct('scope','Offline local map-interface counterfactual; not a new operating point or SLX run.', ...
    'compressor_mat',C,'turbine_flow_mat',F,'turbine_efficiency_fields',{fieldnames(E)}, ...
    'cases',cases,'efficiency_scale_min',min(etaScale,[],'all'), ...
    'efficiency_scale_max',max(etaScale,[],'all'), ...
    'efficiency_scale_09711_max_abs_residual',etaScaleResidual, ...
    'source_hashes',hashes,'model_loaded_or_simulated',false, ...
    'formal_mutations',false,'candidate_A_used',false,'model_acceptance_passed',false);
checkProtected(protected);writetable(protected,fullfile(dest,'protected_after.csv'));
fid=fopen(fullfile(dest,'map_audit.json'),'w');assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(out,PrettyPrint=true));fclose(fid);
disp(C.coordinate_definition);disp(C.provenance);disp(struct2table(cases));
fprintf('MAP_COORDINATE_AUDIT_PASS; CASES=4; NO_SLX; PROTECTED=%d\n',height(protected));
end

function checkProtected(t)
for k=1:height(t),assert(hashFile(t.paths(k))==t.hashes(k),t.paths(k));end
end

function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
