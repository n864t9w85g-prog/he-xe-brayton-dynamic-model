function run_pressure_closure_case(runDirectory,mode,stopTime)
% Controlled candidate/reference execution; no formal files are written.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,string(runDirectory));mode=string(mode);
assert(isfolder(dest)&&startsWith(dest,fullfile(repo,'tmp')+filesep));
assert(any(mode==["reference","candidate"])&&any(stopTime==[500,14000]));
caseDir=fullfile(dest,mode+"_"+stopTime);assert(~isfolder(caseDir));mkdir(caseDir);
diary(fullfile(caseDir,'diary.txt'));finishDiary=onCleanup(@() diary('off'));
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640', ...
    'protected_after.csv'),TextType='string');checkProtected(protected);
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
original=fullfile(source,'final_steady_24a.slx');
assert(hashFile(original)=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
model="pressure_"+mode;modelFile=fullfile(dest,model+".slx");
assert(~bdIsLoaded(model));
if ~isfile(modelFile)
    assert(stopTime==500);copyfile(original,modelFile);
    isNew=true;
else
    assert(stopTime==14000);isNew=false;
end
oldDir=pwd;finishDir=onCleanup(@() cd(oldDir));cd(caseDir);
oldPath=path;finishPath=onCleanup(@() path(oldPath));
addpath(source,fullfile(source,'tests','steady53'),fullfile(repo,'tests'),dest);
assert(string(which('HeXe_property_simulink'))==fullfile(source,'HeXe_property_simulink.m'));
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
fileConfig=Simulink.fileGenControl('getConfig');
finishFiles=onCleanup(@() Simulink.fileGenControl('set','CacheFolder',fileConfig.CacheFolder, ...
    'CodeGenFolder',fileConfig.CodeGenFolder,'createDir',true));
Simulink.fileGenControl('set','CacheFolder',fullfile(caseDir,'cache'), ...
    'CodeGenFolder',fullfile(caseDir,'codegen'),'createDir',true);
startScript=replace(fullfile(source,'start.m'),"'","''");
evalin('base',"run('"+startScript+"')");
load_system(modelFile);finishModel=onCleanup(@() closeModel(model));
if mode=="candidate"&&isNew
    patch_pressure_algebraic_candidate(model);
end
modelHash=hashFile(modelFile);
% Probe both requested durations before altering the saved configuration.
sampleBlocks=["Unit Delay","Unit Delay1","TAC/Compressor/Gain3", ...
    "TAC/Compressor/2-D Lookup"+newline+"Table3","TAC/p_out_Compressor"];
sampling=struct([]);
for duration=[500,14000]
    set_param(model,'StopTime',num2str(duration));
    feval(char(model),[],[],[],'compile');
    st=struct();
    for k=1:numel(sampleBlocks)
        st.("block_"+k)=struct('path',sampleBlocks(k), ...
            'compiled_sample_time',get_param(model+"/"+sampleBlocks(k),'CompiledSampleTime'));
    end
    feval(char(model),[],[],[],'term');
    row=struct('stop_time_s',duration,'blocks',st);
    if isempty(sampling),sampling=row;else,sampling(end+1)=row;end %#ok<AGROW>
end
writeJSON(fullfile(caseDir,'sampling.json'),sampling);
[manifest,states]=steady53_signal_manifest(model);
for k=1:numel(manifest),logPort(manifest(k).block,manifest(k).port,manifest(k).name);end
for k=1:numel(states),logPort(states(k).path,1,"state_"+compose('%03d',k));end
logPort(model+"/Unit Delay",1,'pressure_delay_witness');
logPort(model+"/Unit Delay1",1,'flow_delay_witness');
if mode=="candidate",logPort(model+"/PressureAlgebraicCandidate",1,'pressure_algebraic_feed');end
reset_steady53_property_warning_state();
warnings=warning;finishWarnings=onCleanup(@() warning(warnings));
for id=["HeXe:T_lo","HeXe:T_hi","Lithium_property_simulink:TemperatureBelowRange", ...
        "Lithium_property_simulink:TemperatureAboveRange"]
    warning('error',id);
end
set_param(model,'StopTime',num2str(stopTime),'SignalLogging','on','SignalLoggingName','logsout');
fprintf('BEGIN_%s_%d\n',upper(mode),stopTime);timer=tic;
out=sim(model,'CaptureErrors','on','ReturnWorkspaceOutputs','on');seconds=toc(timer);
save(fullfile(caseDir,'output.mat'),'out','sampling','manifest','states','seconds','-v7.3');
success=isempty(out.ErrorMessage)&&~isempty(out.tout)&&out.tout(end)==stopTime;
sourceFiles=[original,fullfile(source,'HeXe_property_simulink.m'),fullfile(source,'Lithium_property_simulink.m'), ...
    fullfile(source,'hexe_compressor_lookup.mat'),fullfile(source,'turbine_table1.mat'), ...
    fullfile(source,'turbine_table2.mat'),string(mfilename('fullpath'))+".m", ...
    fullfile(source,'tests','steady53','steady53_signal_manifest.m')];
hashes=struct([]);for k=1:numel(sourceFiles),hashes(k).path=sourceFiles(k);hashes(k).sha256=hashFile(sourceFiles(k));end
status=struct('success',success,'requested_stop_time_s',stopTime,'seconds',seconds, ...
    'error',out.ErrorMessage,'model_file',modelFile,'model_sha256',modelHash,'source_hashes',hashes, ...
    'mode',mode,'formal_mutations',false,'paper_acceptance',false);
if ~isempty(out.tout),status.final_time_s=out.tout(end);else,status.final_time_s=[];end
writeJSON(fullfile(caseDir,'status.json'),status);
if isprop(out,'logsout')||any(string(out.who)=="logsout")
    for k=1:out.logsout.numElements
        el=out.logsout.getElement(k);ts=el.Values;
        data=reshape(ts.Data,numel(ts.Time),[]);assert(size(data,2)==1);
        writetable(table(ts.Time(:),data,VariableNames={'time_s','value'}),fullfile(caseDir,el.Name+".csv"));
    end
end
names=["P_sw","WT_sw","Wc_sw"];
for name=names
    ts=out.get(name);writetable(table(ts.Time(:),ts.Data(:),VariableNames={'time_s','value'}), ...
        fullfile(caseDir,name+".csv"));
end
assert(hashFile(modelFile)==modelHash);checkProtected(protected);
writetable(protected,fullfile(caseDir,'protected_after.csv'));
fprintf('END_%s_%d_SUCCESS=%d_SECONDS=%.3f\n',upper(mode),stopTime,success,seconds);
assert(success,out.ErrorMessage);
end

function logPort(block,port,name)
ph=get_param(block,'PortHandles');set_param(ph.Outport(port),'DataLogging','on', ...
    'DataLoggingNameMode','Custom','DataLoggingName',name);
end
function closeModel(model)
if bdIsLoaded(model),close_system(model,0);end
end
function checkProtected(t)
for k=1:height(t),assert(hashFile(t.paths(k))==t.hashes(k),t.paths(k));end
end
function value=hashFile(p)
[status,txt]=system("shasum -a 256 '"+replace(string(p),"'","'\\''")+"'");
assert(status==0);parts=split(strtrim(string(txt)));value=parts(1);
end
function writeJSON(p,value)
fid=fopen(p,'w');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
