function run_precooler_boundary_diagnostic(runDirectory)
% Execute report 33.6: fixed-boundary diagnosis, NOT a physical-model patch.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
dest=fullfile(repo,string(runDirectory));
assert(isfolder(dest)&&startsWith(dest,fullfile(repo,'tmp')+filesep));
assert(~isfile(fullfile(dest,'summary.json')));
diary(fullfile(dest,'diary.txt'));diaryDone=onCleanup(@() diary('off'));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640', ...
    'protected_after.csv'),TextType='string');checkProtected(protected);
sourceFile=fullfile(source,'final_steady_24a.slx');
assert(hashFile(sourceFile)=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
oldPath=path;pathDone=onCleanup(@() path(oldPath));
oldDir=pwd;dirDone=onCleanup(@() cd(oldDir));cd(dest);
addpath(source,fullfile(source,'tests','steady53'));
assert(string(which('HeXe_property_simulink'))==fullfile(source,'HeXe_property_simulink.m'));
evalin('base',"run('"+replace(fullfile(source,'start.m'),"'","''")+"')");
reference=fullfile(repo,'tmp','pressure_closure_4FKFZS','reference_14000');
signalNames=["cooler_cold_inlet_T","recuperator_hot_outlet_T", ...
    "recuperator_hot_outlet_P","hexe_mdot_recup_hot","compressor_inlet_T", ...
    "cooler_cold_outlet_T"];
endpoint=zeros(1,numel(signalNames));evidence=struct([]);
for k=1:numel(signalNames)
    p=fullfile(reference,signalNames(k)+'.csv');t=readtable(p);
    assert(t.time_s(end)==14000);endpoint(k)=t.value(end);
    evidence(k).path=p;evidence(k).sha256=hashFile(p);
end
% Input order is checked by the existing harness against the source ports.
base=[endpoint(1),6.95,endpoint(2:4)];
b=steady53_component_boundaries();target=b.precooler.inputs;
assert(isequal(target,[360.10,6.95,663.63,676000,11.97]));
assert(base(2)==target(2)); % no invented NaK flow correction
inputs=repmat(base,6,1);names=["same_coupled_inputs","only_NaK_Tin", ...
    "only_HeXe_Tin","only_HeXe_Pin","only_HeXe_mdot","all_contract_inputs"];
for k=2:5,idx=[1,3,4,5];inputs(k,idx(k-1))=target(idx(k-1));end
inputs(6,:)=target;
h=create_component_harness('precooler');model=h.model;
modelDone=onCleanup(@() closeIfLoaded(model));
fileConfig=Simulink.fileGenControl('getConfig');
filesDone=onCleanup(@() Simulink.fileGenControl('set','CacheFolder',fileConfig.CacheFolder, ...
    'CodeGenFolder',fileConfig.CodeGenFolder,'createDir',true));
Simulink.fileGenControl('set','CacheFolder',fullfile(dest,'cache'), ...
    'CodeGenFolder',fullfile(dest,'codegen'),'createDir',true);
parameters=struct([]);stateNames=["T_c1_average_Integrator","T_c2_out_Integrator", ...
    "T_h1_average_Integrator","T_h2_out_Integrator","T_wall_Integrator"];
for region=1:2
    p=model+"/DUT/precooler_"+region;
    for field=["h_h","h_c","A_region","A_region2","m_wall_region", ...
            "m_h_region","m_c_region","DeltaP_h"]
        parameters(region).(field)=str2double(get_param(p+"/"+field,'Value'));
    end
    assert(parameters(region).h_h==1384.3&&parameters(region).h_c==94550);
    for j=1:5
        sp=p+"/"+stateNames(j);ph=get_param(sp,'PortHandles');
        set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
            'DataLoggingName',"r"+region+"_s"+j);
    end
end
set_param(model,'SignalLogging','on','SignalLoggingName','logsout');
modelFile=fullfile(dest,model+'.slx');assert(~isfile(modelFile));
save_system(model,modelFile);close_system(model,0);load_system(modelFile);
savedHash=hashFile(modelFile);results=struct([]);
warning('error','HeXe:T_lo');warning('error','HeXe:T_hi');
for k=1:6
    caseDir=fullfile(dest,names(k));assert(~isfolder(caseDir));mkdir(caseDir);
    for j=1:5
        set_param(model+"/Input_"+compose('%03d',j),'Value',num2str(inputs(k,j),'%.17g'));
    end
    fprintf('BEGIN %s\n',names(k));timer=tic;
    out=sim(model,'StopTime','500','CaptureErrors','on','ReturnWorkspaceOutputs','on');
    seconds=toc(timer);save(fullfile(caseDir,'raw.mat'),'out','-v7.3');
    assert(isempty(out.ErrorMessage)&&out.tout(end)==500,out.ErrorMessage);
    outputs=zeros(1,5);states=zeros(2,5);
    for j=1:5
        ts=out.get(h.outputVariables(j));exportSeries(ts,fullfile(caseDir,"y_"+j+".csv"));
        outputs(j)=ts.Data(end);
    end
    for region=1:2
        for j=1:5
            name="r"+region+"_s"+j;ts=out.logsout.getElement(name).Values;
            exportSeries(ts,fullfile(caseDir,name+'.csv'));states(region,j)=ts.Data(end);
        end
    end
    cp=zeros(2,2);
    for region=1:2
        cp(region,1)=HeXe_property_simulink(states(region,3),inputs(k,4)-(region-1)*9000);
        t=states(region,1);cp(region,2)=1000*(1.061-3.694e-4*t+4.615e-8*t^2+1.509e-10*t^3);
    end
    row=struct('name',names(k),'inputs',inputs(k,:),'outputs',outputs, ...
        'states',states,'cp_hot_cold',cp,'final_time_s',out.tout(end), ...
        'error',out.ErrorMessage,'seconds',seconds,'raw_sha256',hashFile(fullfile(caseDir,'raw.mat')));
    if k==1,results=row;else,results(k)=row;end
    fprintf('END %s T_HeXe_out=%.12f T_NaK_out=%.12f seconds=%.3f\n', ...
        names(k),outputs(3),outputs(4),seconds);
end
assert(hashFile(modelFile)==savedHash);checkProtected(protected);
writetable(protected,fullfile(dest,'protected_after.csv'));
sourcePaths=[sourceFile,fullfile(source,'HeXe_property_simulink.m'), ...
    fullfile(source,'tests','steady53','create_component_harness.m'), ...
    fullfile(source,'tests','steady53','steady53_component_boundaries.m'), ...
    string(mfilename('fullpath'))+'.m'];
hashes=struct([]);
for k=1:numel(sourcePaths)
    hashes(k).path=sourcePaths(k);hashes(k).sha256=hashFile(sourcePaths(k));
end
summary=struct('scope','Fixed-boundary local counterfactual, NOT coupled attribution or curve acceptance', ...
    'model_file',modelFile,'model_sha256',savedHash,'harness_source',h, ...
    'parameters',parameters,'source_hashes',hashes,'boundary_evidence',evidence, ...
    'coupled_outputs',[endpoint(5),endpoint(6)],'cases',results, ...
    'formal_mutations',false,'paper_acceptance',false);
fid=fopen(fullfile(dest,'summary.json'),'w');assert(fid>=0);done=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(summary,PrettyPrint=true));
end
function exportSeries(ts,p)
assert(all(isfinite(ts.Data),'all'));
writetable(table(ts.Time(:),ts.Data(:),VariableNames={'time_s','value'}),p);
end
function checkProtected(t)
for k=1:height(t),assert(hashFile(t.paths(k))==t.hashes(k),t.paths(k));end
end
function closeIfLoaded(m)
if bdIsLoaded(m),close_system(m,0);end
end
function value=hashFile(p)
[status,txt]=system("shasum -a 256 '"+replace(string(p),"'","'\\''")+"'");
assert(status==0);parts=split(strtrim(string(txt)));value=parts(1);
end
