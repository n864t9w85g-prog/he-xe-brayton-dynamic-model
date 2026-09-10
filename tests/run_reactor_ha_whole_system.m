% Same two hA values, temporary whole-system candidate; no other changes.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',dest);
guard=readtable(fullfile(repo,'tmp','tp80484fa0_602f_4386_89ed_ae9ca96b3359','protected_after.csv'),TextType='string');
verifyProtected(guard); writetable(guard,fullfile(dest,'protected_before.csv'));
addpath(source,fullfile(source,'tests','steady53'));
assert(string(which('run_steady53_case'))==fullfile(source,'tests','steady53','run_steady53_case.m'));
assert(string(which('HeXe_property_simulink'))==fullfile(source,'HeXe_property_simulink.m'));
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
sourceFile=fullfile(source,'final_steady_24a.slx');
originalHash=hashFile(sourceFile);
assert(originalHash=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
candidateFile=fullfile(dest,'reactor_ha_candidate.slx');
assert(~isfile(candidateFile)); copyfile(sourceFile,candidateFile);
assert(hashFile(candidateFile)==originalHash);
Simulink.fileGenControl('set','CacheFolder',fullfile(dest,'cache'), ...
    'CodeGenFolder',fullfile(dest,'codegen'),'createDir',true);
run(fullfile(source,'start.m'));
load_system(candidateFile); model="reactor_ha_candidate";
before=inventory(model);
kappa=str2double(get_param(model+"/reactor/1//C_fuel",'Value'));
gamma=str2double(get_param(model+"/reactor/gamma_f",'Value'));
assert(kappa==2.246e-5 && gamma==.2906);
for b=["hA1","hA2"]
    p=model+"/reactor/"+b;
    assert(string(get_param(p,'BlockType'))=="Constant" && str2double(get_param(p,'Value'))==13296);
    set_param(p,'Value',num2str(gamma/kappa,'%.17g'));
end
after=inventory(model);
assert(isequal(before.blocks,after.blocks) && isequal(before.edges,after.edges) && ...
    isequal(before.settings,after.settings) && isequal(before.charts,after.charts));
assert(isequal(before.parameters.key,after.parameters.key));
changed=before.parameters.value~=after.parameters.value;
diff=table(before.parameters.key(changed),before.parameters.value(changed),after.parameters.value(changed), ...
    VariableNames={'key','before','after'});
assert(isequal(diff.key,["/reactor/hA1|Value";"/reactor/hA2|Value"]));
writetable(diff,fullfile(dest,'parameter_diff.csv'));
writeJSON(fullfile(dest,'inventory.json'),struct('before',before,'after',after));
fprintf('BEGIN_SAVE_AND_REOPEN_CANDIDATE\n');
save_system(model,candidateFile); close_system(model,0); load_system(candidateFile);
assert(isequal(after,inventory(model)),'Saved/reopened candidate inventory differs.');
fprintf('BEGIN_CANDIDATE_UPDATE\n');
set_param(model,'SimulationCommand','update'); close_system(model,0);
fprintf('END_CANDIDATE_UPDATE\n');
summaries=struct([]);
files=[sourceFile,candidateFile]; names=["original","candidate"];
for k=1:2
    caseDir=fullfile(dest,names(k)); mkdir(caseDir);
    fprintf('BEGIN_FULL_%s_14000\n',upper(names(k))); tic;
    result=run_steady53_case(files(k),14000,true); seconds=toc;
    save(fullfile(caseDir,'result.mat'),'result','seconds','-v7.3');
    writeJSON(fullfile(caseDir,'status.json'),struct('success',result.success, ...
        'final_time_s',result.tFinal_s,'errorId',result.errorId,'errorReport',result.errorReport));
    fprintf('END_FULL_%s success=%d time=%.17g seconds=%.3f error=%s\n', ...
        upper(names(k)),result.success,result.tFinal_s,seconds,result.errorId);
    assert(result.success && result.tFinal_s==14000,'Whole-system run failed; evidence retained.');
    assert(result.modelHashBefore==result.modelHashAfter);
    s=result.signals; f=fieldnames(s); signals=table(result.t(:),VariableNames={'time_s'});
    for j=1:numel(f), signals.(f{j})=s.(f{j})(:); end
    idx=find(endsWith(string({result.states.path}),'/reactor/Integrator7')); assert(isscalar(idx));
    signals.Tfuel_K=result.states(idx).data(:);
    dt=signals.Tfuel_K-(signals.reactor_inlet_T+signals.reactor_outlet_T)/2;
    signals.Qfuel_W=(gamma/kappa)*dt;
    signals.Qcoolant_W=signals.lithium_mdot_reactor.*4111.*(signals.reactor_outlet_T-signals.reactor_inlet_T);
    signals.reactor_transfer_mismatch_W=signals.Qcoolant_W-signals.Qfuel_W;
    F=@(t) .9615*1000*(-104400./t-135.1*log(t)+4.180*t);
    assert(all(signals.reactor_inlet_T>=453.7 & signals.reactor_outlet_T<=1608));
    signals.IHX_Li_boundary_enthalpy_W=signals.lithium_mdot_ihx.*(F(signals.reactor_outlet_T)-F(signals.reactor_inlet_T));
    writetable(signals,fullfile(caseDir,'signals.csv'));
    if k==2, assert(max(abs(signals.reactor_transfer_mismatch_W))<.001); end
    info=struct('name',names(k),'file',files(k),'model_sha256',result.modelHashAfter, ...
        'success',result.success,'final_time_s',result.tFinal_s,'seconds',seconds, ...
        'last_sample',table2struct(signals(end,:)), ...
        'max_reactor_transfer_mismatch_W',max(abs(signals.reactor_transfer_mismatch_W)), ...
        'signals_sha256',hashFile(fullfile(caseDir,'signals.csv')), ...
        'scope','Warm-initialized whole system, same hA-only change; not Fig5.18 component startup acceptance');
    writeJSON(fullfile(caseDir,'summary.json'),info);
    if k==1, summaries=info; else, summaries(k)=info; end
end
verifyProtected(guard); writetable(guard,fullfile(dest,'protected_after.csv'));
writeJSON(fullfile(dest,'summary.json'),summaries);
fprintf('FULL_PAIR_14000_COMPLETE_FORMAL_FILES_UNCHANGED\n'); diary off;

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
        charts(end+1)=struct('path',extractAfter(string(all(k).Path),strlength(model)),'script',string(all(k).Script)); %#ok<SAGROW>
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
