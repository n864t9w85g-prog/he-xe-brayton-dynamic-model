% Single independent hA candidate in temporary component copies only.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',dest);
protected=readtable(fullfile(repo,'tmp','tp80484fa0_602f_4386_89ed_ae9ca96b3359','protected_after.csv'),TextType='string');
verifyProtected(protected); writetable(protected,fullfile(dest,'protected_before.csv'));
addpath(source,fullfile(source,'tests','steady53'));
assert(string(which('create_component_harness'))==fullfile(source,'tests','steady53','create_component_harness.m'));
Simulink.fileGenControl('set','CacheFolder',fullfile(dest,'cache'), ...
    'CodeGenFolder',fullfile(dest,'codegen'),'createDir',true);
allResults=struct([]);
for index=1:2
    candidate=index==2; name="original";
    if candidate, name="candidate"; end
    caseDir=fullfile(dest,name); mkdir(caseDir);
    h=create_component_harness('reactor');
    assert(h.sourceHash=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
    p=h.model+"/DUT";
    mapping=["From33","Tin_K";"Sum15","Tout_K";"Integrator7","Tf_K"; ...
        "Integrator6","P_Rx_W";"Sum11","dTf_dt_K_s";"Constant1","mdot_kg_s"; ...
        "Sum10","rho";"cp_Li","cp_J_kgK";"1//C_fuel","kappa";"gamma_f","gamma"];
    for j=1:size(mapping,1)
        ph=get_param(p+"/"+mapping(j,1),'PortHandles');
        set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',mapping(j,2));
    end
    powerPorts=get_param(p+"/Integrator6",'PortHandles');
    powerLine=get_param(powerPorts.Inport(1),'Line');
    powerSrc=get_param(powerLine,'SrcPortHandle');
    set_param(powerSrc,'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName','dP_dt_W_s');
    set_param(h.model,'SignalLogging','on','SignalLoggingName','logsout','StopTime','500', ...
        'RelTol','1e-7','AbsTol','1e-9','MaxStep','0.1');
    before=inventory(h.model);
    kappa=str2double(get_param(p+"/1//C_fuel",'Value'));
    gamma=str2double(get_param(p+"/gamma_f",'Value'));
    assert(kappa==2.246e-5 && gamma==.2906);
    for b=["hA1","hA2"]
        assert(string(get_param(p+"/"+b,'BlockType'))=="Constant");
        assert(str2double(get_param(p+"/"+b,'Value'))==13296);
        if candidate, set_param(p+"/"+b,'Value',num2str(gamma/kappa,'%.17g')); end
    end
    after=inventory(h.model);
    assert(isequal(before.blocks,after.blocks) && isequal(before.edges,after.edges));
    assert(isequal(before.parameters.key,after.parameters.key));
    changed=before.parameters.value~=after.parameters.value;
    diff=table(before.parameters.key(changed),before.parameters.value(changed), ...
        after.parameters.value(changed),VariableNames={'key','before','after'});
    if candidate
        assert(isequal(diff.key,["/DUT/hA1|Value";"/DUT/hA2|Value"]));
    else
        assert(isempty(diff));
    end
    writetable(diff,fullfile(caseDir,'parameter_diff.csv'));
    save(fullfile(caseDir,'inventory.mat'),'before','after');
    writeJSON(fullfile(caseDir,'inventory.json'),struct('before',before,'after',after));
    save_system(h.model,h.path); close_system(h.model,0); load_system(h.path);
    reopened=inventory(h.model);
    assert(isequal(after,reopened),'Saved/reopened inventory differs.');
    set_param(h.model,'SimulationCommand','update');
    fprintf('BEGIN_%s\n',upper(name)); tic;
    out=sim(h.model,'CaptureErrors','on'); seconds=toc;
    save(fullfile(caseDir,'result.mat'),'out','h','seconds','-v7.3');
    fprintf('END_%s time=%.17g wall=%.3f error=%s\n',upper(name),out.tout(end),seconds,out.ErrorMessage);
    assert(isempty(out.ErrorMessage) && out.tout(end)==500);
    ref=out.logsout.getElement('Tf_K').Values; t=ref.Time(:);
    values=table(t,VariableNames={'time_s'});
    fields=[mapping(:,2);"dP_dt_W_s"];
    for j=1:numel(fields)
        ts=out.logsout.getElement(fields(j)).Values;
        v=reshape(ts.Data,[],1); assert(all(isfinite(v)) && isreal(v));
        if ~isequal(ts.Time(:),t)
            % Constant sources may be logged only once. Broadcast only exact
            % constants; never interpolate or conceal a changing signal.
            assert(all(v==v(1)),'Nonconstant log sample times differ: %s',fields(j));
            v=repmat(v(1),size(t));
        end
        values.(fields(j))=v;
    end
    values.Q_fuel_W=values.gamma./values.kappa.*(values.Tf_K-(values.Tin_K+values.Tout_K)/2);
    values.Q_coolant_W=values.mdot_kg_s.*values.cp_J_kgK.*(values.Tout_K-values.Tin_K);
    values.Q_storage_W=values.dTf_dt_K_s./values.kappa;
    values.energy_residual_W=values.P_Rx_W-values.Q_storage_W-values.Q_coolant_W;
    values.fuel_equation_residual_W=values.P_Rx_W-values.Q_storage_W-values.Q_fuel_W;
    assert(max(abs(values.fuel_equation_residual_W))<1e-5);
    if candidate
        assert(max(abs(values.energy_residual_W))<.001,'Candidate closure failed.');
    else
        assert(max(abs(values.energy_residual_W))>1e4,'Original defect did not reproduce.');
    end
    writetable(values,fullfile(caseDir,'signals.csv'));
    tail=t>=450;
    summary=struct('name',name,'hA_W_K',str2double(get_param(p+"/hA1",'Value')), ...
        'model_path',h.path,'model_sha256',hashFile(h.path),'source_sha256',h.sourceHash, ...
        'final_time_s',out.tout(end),'wall_seconds',seconds,'block_count',height(after.blocks), ...
        'changed_parameter_count',height(diff),'max_energy_residual_W',max(abs(values.energy_residual_W)), ...
        'final_Tout_K',values.Tout_K(end),'final_Tfuel_K',values.Tf_K(end),'final_power_W',values.P_Rx_W(end), ...
        'final_dTf_dt_K_s',values.dTf_dt_K_s(end),'final_dP_dt_W_s',values.dP_dt_W_s(end), ...
        'tail_Tout_span_K',max(values.Tout_K(tail))-min(values.Tout_K(tail)), ...
        'tail_power_span_W',max(values.P_Rx_W(tail))-min(values.P_Rx_W(tail)), ...
        'signals_sha256',hashFile(fullfile(caseDir,'signals.csv')), ...
        'scope','Exploratory fixed-inlet reactor run; not whole system or thesis curve acceptance');
    writeJSON(fullfile(caseDir,'summary.json'),summary); disp(summary);
    if index==1, allResults=summary; else, allResults(index)=summary; end
    close_system(h.model,0);
end
verifyProtected(protected); writetable(protected,fullfile(dest,'protected_after.csv'));
writeJSON(fullfile(dest,'summary.json'),allResults);
fprintf('TWO_REACTOR_CASES_COMPLETE_FORMAL_FILES_UNCHANGED_NOT_THESIS_ACCEPTANCE\n'); diary off;

function data=inventory(model)
paths=sort(string(find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block')));
relative=extractAfter(paths,strlength(model)); types=strings(size(paths));
keys=strings(0,1); vals=strings(0,1); edges=strings(0,1);
for k=1:numel(paths)
    b=paths(k); types(k)=string(get_param(b,'BlockType'));
    params=get_param(b,'DialogParameters');
    if ~isempty(params)
        names=sort(string(fieldnames(params)));
        for j=1:numel(names)
            keys(end+1,1)=relative(k)+"|"+names(j); %#ok<SAGROW>
            vals(end+1,1)=string(jsonencode(get_param(b,names(j)))); %#ok<SAGROW>
        end
    end
    ph=get_param(b,'PortHandles');
    for j=1:numel(ph.Inport)
        ln=get_param(ph.Inport(j),'Line');
        if ln<0, continue; end
        sp=get_param(ln,'SrcPortHandle');
        if sp<0, continue; end
        parent=string(get_param(sp,'Parent'));
        edges(end+1,1)=extractAfter(parent,strlength(model))+"#"+get_param(sp,'PortNumber')+ ...
            "->"+relative(k)+"#"+j; %#ok<SAGROW>
    end
end
data=struct('blocks',table(relative,types),'edges',sort(edges), ...
    'parameters',sortrows(table(keys,vals,VariableNames={'key','value'}),'key'));
end
function verifyProtected(items)
for k=1:height(items), assert(hashFile(items.paths(k))==items.hashes(k),'Protected file changed: %s',items.paths(k)); end
end
function hash=hashFile(p)
[status,txt]=system("shasum -a 256 '"+replace(string(p),"'","'\''")+"'");
assert(status==0); parts=split(strtrim(string(txt))); hash=parts(1);
end
function writeJSON(p,value)
fid=fopen(p,'w'); assert(fid~=-1); guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
