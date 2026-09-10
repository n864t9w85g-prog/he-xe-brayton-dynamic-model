% Physical-domain diagnostic only: uniform 1200 K, then hot inlet +4 K.
% No parameter fitting and no changes to source equations or model files.
repoRoot=fileparts(fileparts(mfilename('fullpath')));
sourceRoot=fullfile(repoRoot,'tmp','steady53_curves_20260828','source_f8bcd83');
outRoot=tempname(fullfile(repoRoot,'tmp')); mkdir(outRoot);
diary(fullfile(outRoot,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',outRoot);
cd(sourceRoot); addpath(sourceRoot,fullfile(sourceRoot,'tests','steady53'));
Simulink.fileGenControl('set','CacheFolder',fullfile(outRoot,'cache'), ...
    'CodeGenFolder',fullfile(outRoot,'codegen'),'createDir',true);
run(fullfile(sourceRoot,'start.m'));
[cp1200,~,~,~,~,~]=Lithium_property_simulink(1200,0.234e6);
Hh=10544*7.031; Ch=4.572*cp1200;
fprintf('cp1200=%.17g Hh=%.17g Ch=%.17g Hh_over_2Ch=%.17g\n',cp1200,Hh,Ch,Hh/(2*Ch));
fprintf('hot_outlet_cross_coefficient=%.17g 1/s\n',(2*Ch-Hh)/(0.6588*cp1200));
for delta_K=[0,4]
    h=create_component_harness('IHX');
    assert(h.sourceHash=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
    assert(strcmp(get_param(h.model+"/DUT/IHX_region_1/h_Li",'Value'),'10544'));
    assert(strcmp(get_param(h.model+"/DUT/IHX_region_1/A_region",'Value'),'7.031'));
    ints=sort(string(find_system(h.model+"/DUT",'LookUnderMasks','all','BlockType','Integrator')));
    assert(numel(ints)==10 && all(contains(ints,"/T_")));
    for k=1:numel(ints)
        set_param(ints(k),'InitialCondition','1200');
        ph=get_param(ints(k),'PortHandles');
        set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
            'DataLoggingName',sprintf('state_%02d',k));
    end
    set_param(h.model+"/Input_001",'Value',num2str(1200+delta_K,'%.17g'));
    set_param(h.model+"/Input_004",'Value','1200');
    extraBlocks=["Q_h","Product2","Gain","Divide1","Lithium_Properties_hot"];
    extraNames=["Q_h","advective_out_W","allocated_out_loss_W","dTh2_K_s","cp_hot"];
    for k=1:numel(extraBlocks)
        ph=get_param(h.model+"/DUT/IHX_region_1/"+extraBlocks(k),'PortHandles');
        set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
            'DataLoggingName',extraNames(k));
    end
    % Numerical diagnostic choice only: resolve a small early excursion.
    set_param(h.model,'SignalLogging','on','SignalLoggingName','logsout', ...
        'RelTol','1e-7','AbsTol','1e-9','MaxStep','0.002','StopTime','2');
    save_system(h.model,h.path); close_system(h.model,0); load_system(h.path);
    set_param(h.model,'SimulationCommand','update');
    tic; out=sim(h.model,'CaptureErrors','on'); elapsed_s=toc;
    fprintf('CASE_DELTA=%.1f FINAL_TIME=%.17g WALL_SECONDS=%.4f ERROR=%s\n', ...
        delta_K,out.tout(end),elapsed_s,out.ErrorMessage);
    caseDir=fullfile(outRoot,sprintf('delta_%g',delta_K)); mkdir(caseDir);
    save(fullfile(caseDir,'result.mat'),'out','h','delta_K','ints','elapsed_s','-v7.3');
    assert(isempty(out.ErrorMessage)&&out.tout(end)==2);
    for k=1:out.logsout.numElements
        e=out.logsout.getElement(k); ts=e.Values;
        writematrix([ts.Time(:),reshape(ts.Data,numel(ts.Time),[])], ...
            fullfile(caseDir,[e.Name '.csv']));
    end
    for k=[1,3]
        ts=out.get(sprintf('y_%03d',k));
        writematrix([ts.Time(:),ts.Data(:)],fullfile(caseDir,sprintf('y_%03d.csv',k)));
    end
    writetable(table(ints),fullfile(caseDir,'state_paths.csv'));
    close_system(h.model,0);
end
fprintf('COMPLETE_DIAGNOSTIC_ONLY\n'); diary off;
