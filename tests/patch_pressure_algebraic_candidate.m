function patch_pressure_algebraic_candidate(model)
% Exploration-only numerical closure of the EXISTING fixed-loss equation.
% The reference regression must fail before this function may be called.
model=string(model);repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,'tmp','pressure_closure_4FKFZS');
file=string(get_param(model,'FileName'));
assert(model=="pressure_candidate"&&file==fullfile(dest,model+".slx"));
assert(hashFile(file)=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
red=jsondecode(fileread(fullfile(dest,'reference_500','independent_verification.json')));
assert(~red.closure_gate_passed&&red.max_abs_closure_residual_Pa>8);
assert(red.reference_replay_max_error_Pa<1e-5);
assert(~isfile(fullfile(dest,'patch_audit.json')));
before=inventory(model);
assert(strcmp(get_param(model+"/Unit Delay",'InitialCondition'),'1.551e6'));
assert(strcmp(get_param(model+"/Unit Delay1",'InitialCondition'),'11.982029'));
assert(strcmp(get_param(model+"/Unit Delay",'SampleTime'),'-1'));
requireSource(model+"/recuperator",4,model+"/Unit Delay",1);
requireSource(model+"/Unit Delay",1,model+"/TAC",6);
requireSource(model+"/Unit Delay1",1,model+"/TAC",2);
assert(numel(get_param(model+"/TAC",'PortHandles').Outport)==6);
high=0;low=0;
for sid=[533,767,289,399]
    b=string(Simulink.ID.getFullName(model+":"+sid));high=high+str2double(get_param(b,'Value'));
end
for sid=[534,768,2918,3027]
    b=string(Simulink.ID.getFullName(model+":"+sid));low=low+str2double(get_param(b,'Value'));
end
assert(high==12000&&low==18000);
v=zeros(1,4);
for k=1:4
    b=string(Simulink.ID.getFullName(model+":"+(3942+k)));v(k)=str2double(get_param(b,'Value'));
end
assert(isequal(v,[0,.011605,.005158,.002579]));
h=v(3)+v(4);l=v(1)+v(2);
for item={"Gain1","Gain2"}
    assert(strcmp(get_param(model+"/TAC/Compressor/"+item{1},'Gain'),'1/55090'));
end
for item={"Gain3","Gain4"}
    assert(strcmp(get_param(model+"/TAC/Compressor/"+item{1},'Gain'),'1/12.04'));
end
newOut=model+"/TAC/PressureRatioDiagnostic";newFcn=model+"/PressureAlgebraicCandidate";
assert(getSimulinkBlockHandle(newOut)<0&&getSimulinkBlockHandle(newFcn)<0);
expr=sprintf('((1+u(1)*%.17g)*%.17g+u(1)*%.17g*(1-%.17g))/(u(1)*%.17g+%.17g)', ...
    l,high,low,h,l,h);
add_block('simulink/Ports & Subsystems/Out1',newOut,'Port','7','Position',[1000 700 1030 714]);
add_line(model+"/TAC",'Compressor/1','PressureRatioDiagnostic/1','autorouting','on');
add_block('simulink/User-Defined Functions/Fcn',newFcn,'Expr',expr,'Position',[650 680 950 720]);
add_line(model,'TAC/7','PressureAlgebraicCandidate/1','autorouting','on');
delete_line(model,'Unit Delay/1','recuperator/4');
add_line(model,'PressureAlgebraicCandidate/1','recuperator/4','autorouting','on');
after=inventory(model);
addedBlocks=setdiff(after.blocks.relative,before.blocks.relative);
assert(isequal(sort(addedBlocks),sort(["/TAC/PressureRatioDiagnostic";"/PressureAlgebraicCandidate"])));
assert(isequal(before.blocks,after.blocks(~ismember(after.blocks.relative,addedBlocks),:)));
newParameters=false(height(after.parameters),1);
for p=addedBlocks.',newParameters=newParameters|startsWith(after.parameters.key,p+"|");end
assert(isequal(before.parameters,after.parameters(~newParameters,:)));
assert(isequal(before.charts,after.charts)&&isequal(before.settings,after.settings));
removed=setdiff(before.edges,after.edges);added=setdiff(after.edges,before.edges);
assert(isequal(removed,"/Unit Delay#1->/recuperator#4"));
expected=["/TAC/Compressor#1->/TAC/PressureRatioDiagnostic#1"; ...
    "/TAC#7->/PressureAlgebraicCandidate#1";"/PressureAlgebraicCandidate#1->/recuperator#4"];
assert(isequal(sort(added),sort(expected)));
save_system(model,file);close_system(model,0);load_system(file);
assert(isequal(after,inventory(model)),'Inventory changed on reopen');
audit=struct('before',before,'after',after,'removed_edges',removed,'added_edges',added, ...
    'added_blocks',addedBlocks,'high_drop_Pa',high,'low_drop_Pa',low,'normalized_high',h, ...
    'normalized_low',l,'expression',expr,'candidate_file',file,'candidate_sha256',hashFile(file), ...
    'patch_sha256',hashFile(string(mfilename('fullpath'))+".m"), ...
    'scope','Pressure numerical feed only; old delay kept as unused-output witness; no physics/table/state-IC changes.');
fid=fopen(fullfile(dest,'patch_audit.json'),'w');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(audit,PrettyPrint=true));
fprintf('PRESSURE_PATCH_STRUCTURE_PASS; ADDED_BLOCKS=2; ADDED_EDGES=3; REMOVED_EDGES=1\n');
end

function requireSource(block,port,source,sourcePort)
ph=get_param(block,'PortHandles');line=get_param(ph.Inport(port),'Line');assert(line>=0);
sp=get_param(line,'SrcPortHandle');assert(string(get_param(sp,'Parent'))==source);
assert(get_param(sp,'PortNumber')==sourcePort);
end

function data=inventory(model)
paths=sort(string(find_system(model,'LookUnderMasks','all','FollowLinks','off','Type','Block')));
relative=extractAfter(paths,strlength(model));types=strings(size(paths));
keys=strings(0,1);vals=strings(0,1);edges=strings(0,1);
for k=1:numel(paths)
    b=paths(k);types(k)=string(get_param(b,'BlockType'));params=get_param(b,'DialogParameters');
    if ~isempty(params)
        names=sort(string(fieldnames(params)));
        for j=1:numel(names)
            keys(end+1,1)=relative(k)+"|"+names(j);vals(end+1,1)=string(jsonencode(get_param(b,names(j)))); %#ok<AGROW>
        end
    end
    ph=get_param(b,'PortHandles');
    for j=1:numel(ph.Inport)
        ln=get_param(ph.Inport(j),'Line');if ln<0,continue;end
        sp=get_param(ln,'SrcPortHandle');if sp<0,continue;end
        edges(end+1,1)=extractAfter(string(get_param(sp,'Parent')),strlength(model))+ ...
            "#"+get_param(sp,'PortNumber')+"->"+relative(k)+"#"+j; %#ok<AGROW>
    end
end
settings=struct();
for key=["Solver","SolverType","StartTime","StopTime","RelTol","AbsTol","MaxStep", ...
        "LoadInitialState","InitialState","AlgebraicLoopSolver"]
    settings.(key)=get_param(model,key);
end
sf=sfroot;all=sf.find('-isa','Stateflow.EMChart');charts=struct('path',{},'script',{});
for k=1:numel(all)
    if startsWith(string(all(k).Path),model+"/")
        charts(end+1)=struct('path',extractAfter(string(all(k).Path),strlength(model)), ...
            'script',string(all(k).Script)); %#ok<AGROW>
    end
end
if ~isempty(charts),[~,order]=sort(string({charts.path}));charts=charts(order);end
data=struct('blocks',table(relative,types),'edges',sort(edges), ...
    'parameters',sortrows(table(keys,vals,VariableNames={'key','value'}),'key'), ...
    'settings',settings,'charts',{charts});
end

function value=hashFile(p)
[status,txt]=system("shasum -a 256 '"+replace(string(p),"'","'\\''")+"'");
assert(status==0);parts=split(strtrim(string(txt)));value=parts(1);
end
