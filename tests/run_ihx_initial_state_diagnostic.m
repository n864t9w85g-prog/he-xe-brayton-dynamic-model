% One initial-state-family diagnostic, not a calibrated reproduction.
% All ten IHX thermal states = 1200 K (near the plot lower bound, NOT a
% verified thesis initial condition). Source equations/boundaries unchanged.
repoRoot=fileparts(fileparts(mfilename('fullpath')));
sourceRoot=fullfile(repoRoot,'tmp','steady53_curves_20260828','source_f8bcd83');
outRoot=tempname(fullfile(repoRoot,'tmp')); mkdir(outRoot);
diary(fullfile(outRoot,'diary.txt'));
fprintf('OUTPUT_DIR=%s\n',outRoot);
fprintf('SCOPE=exploratory IHX initial-state family only; initial condition is unverified\n');
cd(sourceRoot); addpath(sourceRoot,fullfile(sourceRoot,'tests','steady53'));
Simulink.fileGenControl('set','CacheFolder',fullfile(outRoot,'cache'), ...
    'CodeGenFolder',fullfile(outRoot,'codegen'),'createDir',true);
run(fullfile(sourceRoot,'start.m'));
h=create_component_harness('IHX');
expectedHash="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391";
assert(h.sourceHash==expectedHash,'Unexpected candidate source.');
ints=sort(string(find_system(h.model+"/DUT",'LookUnderMasks','all','BlockType','Integrator')));
assert(numel(ints)==10 && all(contains(ints,"/T_")),'Unexpected state family.');
before=strings(size(ints)); stateNames=strings(size(ints));
for k=1:numel(ints)
    before(k)=get_param(ints(k),'InitialCondition');
    assert(isfinite(str2double(before(k))));
    set_param(ints(k),'InitialCondition','1200');
    ph=get_param(ints(k),'PortHandles'); stateNames(k)=sprintf('state_%02d',k);
    set_param(ph.Outport(1),'DataLogging','on','DataLoggingNameMode','Custom', ...
        'DataLoggingName',stateNames(k));
end
set_param(h.model,'SignalLogging','on','SignalLoggingName','logsout');
save_system(h.model,h.path); close_system(h.model,0); load_system(h.path);
for k=1:numel(ints)
    assert(strcmp(get_param(ints(k),'InitialCondition'),'1200'));
end
writetable(table(ints,before,repmat("1200",numel(ints),1),stateNames, ...
    'VariableNames',{'path','before','after','log_name'}),fullfile(outRoot,'state_change.csv'));
set_param(h.model,'SimulationCommand','update');
fprintf('UPDATE_PASSED; BEGIN_IHX_500\n'); tic;
out=sim(h.model,'StopTime','500','CaptureErrors','on'); elapsed_s=toc;
save(fullfile(outRoot,'ihx_initial1200.mat'),'out','h','ints','before','stateNames','elapsed_s','-v7.3');
fprintf('FINAL_TIME=%.17g WALL_SECONDS=%.6f ERROR=%s\n',out.tout(end),elapsed_s,out.ErrorMessage);
assert(isempty(out.ErrorMessage)&&out.tout(end)==500,'IHX diagnostic failed.');
vars=out.who;
for k=1:numel(vars)
    v=out.get(vars{k});
    if isa(v,'timeseries')
        writematrix([v.Time(:),reshape(v.Data,numel(v.Time),[])],fullfile(outRoot,[vars{k} '.csv']));
    elseif isa(v,'Simulink.SimulationData.Dataset') && strcmp(vars{k},'logsout')
        for j=1:v.numElements
            e=v.getElement(j); ts=e.Values;
            writematrix([ts.Time(:),reshape(ts.Data,numel(ts.Time),[])], ...
                fullfile(outRoot,[e.Name '.csv']));
        end
    end
end
close_system(h.model,0);
fprintf('DIAGNOSTIC_COMPLETE_NOT_PAPER_ACCEPTANCE\n');
diary off;
