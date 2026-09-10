% Candidate-only replacement of the reactor outlet algebraic heat balance.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
baselineDir=fullfile(repo,'tmp','tpc62c4458_6d68_4bf1_9446_6dc3806024b2');
baseline=fullfile(baselineDir,'reactor_ha_candidate.slx');
assert(hashFile(baseline)=="407dd51c8d3fcdd6a4b4ba4c526ed85718b0f756b951dba7f6d4f65e1048bb88");
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('CANDIDATE_DIR=%s\n',dest);
protected=readtable(fullfile(baselineDir,'protected_after.csv'),TextType='string');
verifyProtected(protected); writetable(protected,fullfile(dest,'protected_before.csv'));
addpath(fullfile(repo,'tests'),source,fullfile(source,'tests','steady53'));
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
assert(string(which('reactor_li_enthalpy_outlet'))==fullfile(repo,'tests','reactor_li_enthalpy_outlet.m'));
candidateFile=fullfile(dest,'reactor_li_candidate.slx'); copyfile(baseline,candidateFile);
Simulink.fileGenControl('set','CacheFolder',fullfile(dest,'cache'), ...
    'CodeGenFolder',fullfile(dest,'codegen'),'createDir',true);
run(fullfile(source,'start.m')); load_system(candidateFile); model="reactor_li_candidate";
before=inventory(model); p=model+"/reactor"; new=p+"/Li_Enthalpy_Outlet_Candidate";
assert(getSimulinkBlockHandle(new)==-1);
ph=get_param(p+"/Goto3",'PortHandles'); oldLine=get_param(ph.Inport(1),'Line');
sp=get_param(oldLine,'SrcPortHandle');
assert(string(get_param(sp,'Parent'))==p+"/Sum15" && get_param(sp,'PortNumber')==1);
assert(string(get_param(p+"/From33",'GotoTag'))=="T_in");
assert(str2double(get_param(p+"/hA1",'Value'))==.2906/2.246e-5);
add_block('simulink/User-Defined Functions/MATLAB Function',new,'Position',[1300 1050 1480 1140]);
sf=sfroot; chart=sf.find('-isa','Stateflow.EMChart','Path',char(new)); assert(isscalar(chart));
chart.Script=sprintf(['function Tout = Li_Enthalpy_Outlet_Candidate(Tin,Tf,mdot,hA)\n' ...
    'coder.extrinsic(''reactor_li_enthalpy_outlet'');\n' ...
    'Tout=0;\nTout=reactor_li_enthalpy_outlet(Tin,Tf,mdot,hA);\nend\n']);
% The original arithmetic path is retained, but only its output edge is
% replaced. No state or coefficient is changed, and no new feedback added.
delete_line(p,'Sum15/1','Goto3/1');
sources=["From33","Integrator7","Constant1","hA1"];
for k=1:4
    add_line(p,sources(k)+"/1","Li_Enthalpy_Outlet_Candidate/"+k,'autorouting','on');
end
add_line(p,'Li_Enthalpy_Outlet_Candidate/1','Goto3/1','autorouting','on');
after=inventory(model);
prefix="/reactor/Li_Enthalpy_Outlet_Candidate";
oldRows=~startsWith(after.blocks.relative,prefix);
assert(isequal(before.blocks,after.blocks(oldRows,:)));
oldParams=~startsWith(after.parameters.key,prefix);
assert(isequal(before.parameters,after.parameters(oldParams,:)));
assert(isequal(before.settings,after.settings));
oldCharts=~startsWith(string({after.charts.path}),prefix);
assert(isequal(before.charts,after.charts(oldCharts)));
removed=setdiff(before.edges,after.edges); added=setdiff(after.edges,before.edges);
assert(isequal(removed,"/reactor/Sum15#1->/reactor/Goto3#1"));
expected=["/reactor/From33#1->"+prefix+"#1";"/reactor/Integrator7#1->"+prefix+"#2"; ...
    "/reactor/Constant1#1->"+prefix+"#3";"/reactor/hA1#1->"+prefix+"#4";prefix+"#1->/reactor/Goto3#1"];
for edge=added.'
    parts=split(edge,'->'); internal=all(startsWith(parts,prefix+"/"));
    assert(any(expected==edge)||internal,'Unexpected connection change: %s',edge);
end
assert(all(ismember(expected,added)));
writeJSON(fullfile(dest,'inventory.json'),struct('before',before,'after',after,'added_edges',added,'removed_edges',removed));
save_system(model,candidateFile); close_system(model,0); load_system(candidateFile);
assert(isequal(after,inventory(model)),'Reopened inventory mismatch');
fprintf('BEGIN_UPDATE\n'); set_param(model,'SimulationCommand','update'); close_system(model,0);
fprintf('BEGIN_ENTHALPY_CANDIDATE_14000\n'); tic;
result=run_steady53_case(candidateFile,14000,true); seconds=toc;
save(fullfile(dest,'result.mat'),'result','seconds','-v7.3');
writeJSON(fullfile(dest,'status.json'),struct('success',result.success,'final_time_s',result.tFinal_s, ...
    'errorId',result.errorId,'errorReport',result.errorReport));
fprintf('END_ENTHALPY_CANDIDATE success=%d time=%.17g seconds=%.3f\n',result.success,result.tFinal_s,seconds);
assert(result.success&&result.tFinal_s==14000,result.errorReport);
assert(result.modelHashBefore==result.modelHashAfter);
t=table(result.t,VariableNames={'time_s'}); names=fieldnames(result.signals);
for k=1:numel(names), t.(names{k})=result.signals.(names{k})(:); end
idx=find(endsWith(string({result.states.path}),'/reactor/Integrator7')); assert(isscalar(idx));
t.Tfuel_K=result.states(idx).data(:);
t.Qfuel_W=(.2906/2.246e-5)*(t.Tfuel_K-(t.reactor_inlet_T+t.reactor_outlet_T)/2);
F=@(T) .9615*1000*(-104400./T-135.1*log(T)+4.180*T);
t.Q_Li_enthalpy_W=t.lithium_mdot_reactor.*(F(t.reactor_outlet_T)-F(t.reactor_inlet_T));
t.enthalpy_residual_W=t.Qfuel_W-t.Q_Li_enthalpy_W;
t.cpbar_J_kgK=t.Q_Li_enthalpy_W./(t.lithium_mdot_reactor.*(t.reactor_outlet_T-t.reactor_inlet_T));
writetable(t,fullfile(dest,'signals.csv'));
assert(max(abs(t.enthalpy_residual_W))<.001);
verifyProtected(protected); writetable(protected,fullfile(dest,'protected_after.csv'));
assert(hashFile(baseline)=="407dd51c8d3fcdd6a4b4ba4c526ed85718b0f756b951dba7f6d4f65e1048bb88");
summary=struct('final_time_s',result.tFinal_s,'seconds',seconds,'model_sha256',result.modelHashAfter, ...
    'baseline_sha256',hashFile(baseline),'signals_sha256',hashFile(fullfile(dest,'signals.csv')), ...
    'max_abs_enthalpy_residual_W',max(abs(t.enthalpy_residual_W)),'last_sample',table2struct(t(end,:)), ...
    'scope','Exploratory warm whole-system run, not formal promotion or thesis curve acceptance');
writeJSON(fullfile(dest,'summary.json'),summary);
fprintf('ENTHALPY_CANDIDATE_14000_COMPLETE_PROTECTED_FILES_UNCHANGED\n'); diary off;

function data=inventory(model)
paths=sort(string(find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block')));
relative=extractAfter(paths,strlength(model)); types=strings(size(paths));
keys=strings(0,1); vals=strings(0,1); edges=strings(0,1);
for k=1:numel(paths)
    b=paths(k); types(k)=string(get_param(b,'BlockType')); params=get_param(b,'DialogParameters');
    if ~isempty(params)
        names=sort(string(fieldnames(params)));
        for j=1:numel(names)
            keys(end+1,1)=relative(k)+"|"+names(j); vals(end+1,1)=string(jsonencode(get_param(b,names(j)))); %#ok<SAGROW>
        end
    end
    ph=get_param(b,'PortHandles');
    for j=1:numel(ph.Inport)
        ln=get_param(ph.Inport(j),'Line'); if ln<0, continue; end
        sp=get_param(ln,'SrcPortHandle'); if sp<0, continue; end
        edges(end+1,1)=extractAfter(string(get_param(sp,'Parent')),strlength(model))+ ...
            "#"+get_param(sp,'PortNumber')+"->"+relative(k)+"#"+j; %#ok<SAGROW>
    end
end
settings=struct();
for key=["Solver","SolverType","StartTime","StopTime","RelTol","AbsTol","MaxStep","LoadInitialState","InitialState"]
    settings.(key)=get_param(model,key);
end
sf=sfroot; all=sf.find('-isa','Stateflow.EMChart'); charts=struct('path',{},'script',{});
for k=1:numel(all)
    if startsWith(string(all(k).Path),model+"/")
        charts(end+1)=struct('path',extractAfter(string(all(k).Path),strlength(model)),'script',string(all(k).Script)); %#ok<AGROW>
    end
end
if ~isempty(charts), [~,order]=sort(string({charts.path})); charts=charts(order); end
data=struct('blocks',table(relative,types),'edges',sort(edges), ...
    'parameters',sortrows(table(keys,vals,VariableNames={'key','value'}),'key'),'settings',settings,'charts',{charts});
end
function verifyProtected(t)
for k=1:height(t), assert(hashFile(t.paths(k))==t.hashes(k),'Protected file changed: %s',t.paths(k)); end
end
function hash=hashFile(p)
[status,txt]=system("shasum -a 256 '"+replace(string(p),"'","'\''")+"'");
assert(status==0); parts=split(strtrim(string(txt))); hash=parts(1);
end
function writeJSON(p,value)
fid=fopen(p,'w'); assert(fid~=-1); guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
