% Approved on 2026-08-28: IHX local hot-side heat allocation, TMP ONLY.
repoRoot=string(fileparts(fileparts(mfilename('fullpath'))));
sourceRoot=fullfile(repoRoot,'tmp','steady53_curves_20260828','source_f8bcd83');
outRoot=string(tempname(fullfile(repoRoot,'tmp'))); mkdir(outRoot);
diary(fullfile(outRoot,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',outRoot);
guardRoots=[repoRoot;repoRoot+"_副本";sourceRoot];
protectedBefore=protectedHashes(guardRoots);
writetable(protectedBefore,fullfile(outRoot,'protected_before.csv'));
cd(sourceRoot); addpath(sourceRoot,fullfile(sourceRoot,'tests','steady53'),fullfile(repoRoot,'tests'));
Simulink.fileGenControl('set','CacheFolder',fullfile(outRoot,'cache'), ...
    'CodeGenFolder',fullfile(outRoot,'codegen'),'createDir',true);
run(fullfile(sourceRoot,'start.m'));
caseNames=["candidate_uniform","candidate_plus4","original_500","candidate_500"];
summaries=struct([]);
for caseIndex=1:numel(caseNames)
    name=caseNames(caseIndex); isCandidate=startsWith(name,"candidate"); isShort=caseIndex<=2;
    caseDir=fullfile(outRoot,name); mkdir(caseDir);
    h=create_component_harness('IHX');
    assert(h.sourceHash=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
    ints=sort(string(find_system(h.model+"/DUT",'BlockType','Integrator')));
    assert(numel(ints)==10);
    if isCandidate
        audit=patch_ihx_local_hot_exchange(h.model);
        save(fullfile(caseDir,'structural_audit.mat'),'audit');
        writeJson(fullfile(caseDir,'structural_audit.json'),audit);
    end
    for k=1:10
        set_param(ints(k),'InitialCondition','1200');
        logBlock(ints(k),sprintf('state_%02d',k));
    end
    if isShort
        hotInput=1200+4*(name=="candidate_plus4");
        set_param(h.model+"/Input_001",'Value',num2str(hotInput,'%.17g'));
        set_param(h.model+"/Input_004",'Value','1200'); stopTime=2; maxStep=.002;
    else
        stopTime=500; maxStep=.1;
    end
    for r=1:2
        p=h.model+"/DUT/IHX_region_"+r;
        mapping=["Gain","hot_q1";"From35","hot_q2";"Q_h","wall_hot"; ...
            "Q_c","cold_q";"Product1","hot_adv1";"Product2","hot_adv2"; ...
            "Product3","cold_adv1";"Product5","cold_adv2"; ...
            "Gain1","hot_half_capacity";"Gain3","cold_half_capacity"; ...
            "C_wall","wall_capacity";"Divide","hot_d1";"Divide1","hot_d2"; ...
            "Divide2","cold_d1";"Divide3*","cold_d2";"Divide4","wall_d"; ...
            "Lithium_Properties_hot","cp_hot";"HeXe_Properties_cold","cp_cold"];
        if isCandidate
            mapping(2,1)="LocalHotOutletHeat"; mapping(3,1)="LocalHotTotal";
        end
        for k=1:size(mapping,1), logBlock(p+"/"+mapping(k,1),"r"+r+"_"+mapping(k,2)); end
    end
    set_param(h.model,'SignalLogging','on','SignalLoggingName','logsout', ...
        'RelTol','1e-7','AbsTol','1e-9','MaxStep',num2str(maxStep), ...
        'StopTime',num2str(stopTime));
    save_system(h.model,h.path); close_system(h.model,0); load_system(h.path);
    for k=1:10, assert(strcmp(get_param(ints(k),'InitialCondition'),'1200')); end
    if isCandidate
        for r=1:2
            p=h.model+"/DUT/IHX_region_"+r;
            checkSource(p,"Sum4",2,"LocalHotOutletHeat");
            checkSource(p,"Sum10",1,"LocalHotTotal");
            assert(strcmp(get_param(p+"/LocalHotOutletHeat",'Gain'),'0.5'));
        end
    end
    set_param(h.model,'SimulationCommand','update');
    fprintf('BEGIN_CASE=%s\n',name); tic;
    out=sim(h.model,'CaptureErrors','on'); elapsed_s=toc;
    save(fullfile(caseDir,'result.mat'),'out','h','ints','elapsed_s','-v7.3');
    fprintf('END_CASE=%s TIME=%.17g WALL_SECONDS=%.4f ERROR=%s\n', ...
        name,out.tout(end),elapsed_s,out.ErrorMessage);
    assert(isempty(out.ErrorMessage)&&out.tout(end)==stopTime);
    for k=1:out.logsout.numElements
        e=out.logsout.getElement(k); ts=e.Values;
        writematrix([ts.Time(:),reshape(ts.Data,numel(ts.Time),[])], ...
            fullfile(caseDir,e.Name+".csv"));
    end
    for k=1:numel(h.outputVariables)
        ts=out.get(h.outputVariables(k));
        writematrix([ts.Time(:),reshape(ts.Data,numel(ts.Time),[])], ...
            fullfile(caseDir,h.outputVariables(k)+".csv"));
    end
    writetable(table(ints),fullfile(caseDir,'state_paths.csv'));
    summary=checkRun(out,isShort,name); summary.name=name; summary.wall_seconds=elapsed_s;
    summary.model_file=h.path; summary.model_sha256=fileHash(h.path);
    if caseIndex==1, summaries=summary; else, summaries(caseIndex)=summary; end %#ok<SAGROW>
    writeJson(fullfile(caseDir,'verification.json'),summary);
    close_system(h.model,0);
end
protectedAfter=protectedHashes(guardRoots);
writetable(protectedAfter,fullfile(outRoot,'protected_after.csv'));
assert(isequal(protectedBefore,protectedAfter),'A protected source file changed.');
writeJson(fullfile(outRoot,'summary.json'),summaries);
fprintf('ALL_FOUR_CASES_COMPLETE_SOURCE_PROTECTED_NOT_THESIS_ACCEPTANCE\n'); diary off;

function logBlock(block,name)
ph=get_param(block,'PortHandles');
set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom','DataLoggingName',name);
end

function checkSource(root,dest,port,expected)
ph=get_param(root+"/"+dest,'PortHandles'); ln=get_param(ph.Inport(port),'Line');
sp=get_param(ln,'SrcPortHandle'); assert(string(get_param(get_param(sp,'Parent'),'Name'))==expected);
end

function summary=checkRun(out,isShort,name)
summary.final_time=out.tout(end); summary.min_state_K=Inf; summary.max_state_K=-Inf;
for k=1:10
    a=series(out,sprintf('state_%02d',k));
    assert(all(isfinite(a)));
    summary.min_state_K=min(summary.min_state_K,min(a));
    summary.max_state_K=max(summary.max_state_K,max(a));
end
if isShort
    assert(summary.min_state_K>=1200-1e-6 && summary.max_state_K<=1204+1e-6, ...
        'Local thermal-domain regression failed. Do not proceed to nominal runs.');
    if name=="candidate_uniform"
        assert(max(abs([summary.min_state_K,summary.max_state_K]-1200))<1e-8);
    end
end
residuals=zeros(2,7);
for r=1:2
    f=@(n) series(out,"r"+r+"_"+n);
    bh=f("hot_half_capacity"); bc=f("cold_half_capacity"); bw=f("wall_capacity");
    assert(all(bh>0)&all(bc>0)&all(bw>0));
    q1=f("hot_q1"); q2=f("hot_q2"); qc=f("cold_q"); qw=f("wall_hot");
    rh1=bh.*f("hot_d1")-f("hot_adv1")+q1;
    rh2=bh.*f("hot_d2")-f("hot_adv2")+q2;
    rc1=bc.*f("cold_d1")-f("cold_adv1")-.5*qc;
    rc2=bc.*f("cold_d2")-f("cold_adv2")-.5*qc;
    rw=bw.*f("wall_d")-qw+qc;
    external=f("hot_adv1")+f("hot_adv2")+f("cold_adv1")+f("cold_adv2");
    storage=bh.*(f("hot_d1")+f("hot_d2"))+bc.*(f("cold_d1")+f("cold_d2"))+bw.*f("wall_d");
    residuals(r,:)=max(abs([rh1 rh2 rc1 rc2 rw qw-q1-q2 storage-external]),[],1);
end
summary.max_balance_residuals_W=residuals;
assert(max(residuals,[],'all')<1e-5,'Instantaneous power accounting failed.');
summary.hot_out_final_K=out.y_001.Data(end);
summary.cold_out_final_K=out.y_003.Data(end);
summary.scope='Exploratory candidate verification, not thesis acceptance; balance is instantaneous model power, not an independent variable-cp enthalpy proof.';
end

function data=series(out,name)
e=out.logsout.getElement(name); data=reshape(e.Values.Data,[],1);
end

function writeJson(path,value)
fid=fopen(path,'w'); assert(fid~=-1); guard=onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end

function hash=fileHash(path)
[status,text]=system("shasum -a 256 '"+replace(string(path),"'","'\''")+"'");
assert(status==0); tokens=split(strtrim(string(text))); hash=tokens(1);
end

function t=protectedHashes(roots)
paths=strings(0,1); hashes=strings(0,1);
for root=roots.'
    for ext=["*.slx","*.mat","*.m"]
        files=dir(fullfile(root,ext));
        for k=1:numel(files)
            p=string(fullfile(files(k).folder,files(k).name));
            paths(end+1,1)=p; hashes(end+1,1)=fileHash(p); %#ok<AGROW>
        end
    end
end
t=sortrows(table(paths,hashes),'paths');
end
