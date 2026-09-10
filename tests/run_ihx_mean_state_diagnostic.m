function run_ihx_mean_state_diagnostic
% Offline test of literal Eq5.12-14 applied to the existing TWO regions.
% Not the author's recovered implementation, a fit, or a promoted candidate.
% No load_system/sim/start/save_system; formal functions called unchanged.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
prior=fullfile(repo,'tmp','tp80484fa0_602f_4386_89ed_ae9ca96b3359');
out=string(tempname(fullfile(repo,'tmp'))); mkdir(out);
oldPwd=pwd; oldPath=path; oldWarn=warning;
cleanup=onCleanup(@() restore(oldPwd,oldPath,oldWarn)); %#ok<NASGU>
diary(fullfile(out,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',out);
diaryCleanup=onCleanup(@() diary('off')); %#ok<NASGU>
guard=readtable(fullfile(prior,'protected_after.csv'),TextType='string');
checkProtected(guard); assert(height(guard)==34);
assert(fileHash(fullfile(source,'final_steady_24a.slx'))== ...
    "0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
cd(source); addpath(source);
assert(string(which('HeXe_property_simulink'))==fullfile(source,'HeXe_property_simulink.m'));
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
clear HeXe_property_simulink Lithium_property_simulink
for id=["HeXe:T_lo","HeXe:T_hi", ...
        "Lithium_property_simulink:TemperatureBelowRange", ...
        "Lithium_property_simulink:TemperatureAboveRange"]
    warning('error',id);
end

p=struct('A',7.031,'hh',10544,'hc',1171.6,'mh',.6588,'mc',.00919,'mw',162.5, ...
    'mhFlow',4.572,'mcFlow',11.97,'Thi',1600,'Tci',1100.91, ...
    'pressure',[1.543e6,1.541e6]);
% Pressure ordering follows ACTUAL saved wiring (opposite the cold-T path).
% Preserve it here to isolate state closure; do not silently fix that issue.
p.wallT=[293.15,373.15,473.15,573.15,673.15,773.15,873.15,973.15, ...
    1073.15,1173.15,1273.15,1366.48,1473.15,1573.15,1600];
p.wallCp=[419,440,465,490,515,536,561,586,611,636,662,682.4,709.6,734.1,740.7];
original0=1200*ones(10,1);
% State ordering original: [coldMean,coldOut,hotMean,hotOut,wall] per region.
% Literal mean state: [coldMean,hotMean,wall] per region.
% Match all four outlet temperatures and both wall temperatures at 1200 K.
mean0=[1200;1400;1200;1150.455;1200;1200];
consistentOriginal0=original0; consistentOriginal0(3)=1400; consistentOriginal0(6)=1150.455;
[~,v0]=rhs(0,mean0,p,true);
assert(max(abs(v0-1200))<1e-10);
[~,vc0]=rhs(0,consistentOriginal0,p,false);
assert(max(abs(vc0-v0))<1e-10);
% Equal numeric mean states would NOT be equal physical outlet conditions.
[~,alternative0]=rhs(0,1200*ones(6,1),p,true);
initial=struct('original_state_K',original0,'literal_state_K',mean0, ...
    'consistent_original_control_state_K',consistentOriginal0, ...
    'literal_outlets_walls_K',v0,'if_all_literal_means_were1200_outlets_walls_K',alternative0, ...
    'output_order',{{'hot1','hot2','cold1','cold2','wall1','wall2'}}, ...
    'meaning','Match outlets and walls, not all internal states or stored energy; not a fitted initialization.');
% Uniform equilibrium sanity check, with unchanged mass/h/properties.
pu=p; pu.Thi=1200; pu.Tci=1200;
assert(max(abs(rhs(0,original0,pu,false)))<1e-10);
assert(max(abs(rhs(0,1200*ones(6,1),pu,true)))<1e-10);

opts=odeset('RelTol',1e-9,'AbsTol',1e-10,'MaxStep',.1);
fprintf('BEGIN_ORIGINAL_10_STATE_REPLAY\n'); tic;
original=ode15s(@(t,z) rhs(t,z,p,false),[0,500],original0,opts);
assert(original.x(end)==500); fprintf('END_ORIGINAL seconds=%g\n',toc);
replayErrors=zeros(10,1); replayPaths=strings(10,1); replayHashes=strings(10,1);
for k=1:10
    f=fullfile(prior,'original_500',sprintf('state_%02d.csv',k));
    reference=readmatrix(f); predicted=deval(original,reference(:,1),k).';
    replayErrors(k)=max(abs(predicted-reference(:,2)));
    replayPaths(k)=f; replayHashes(k)=fileHash(f);
end
fprintf('ORIGINAL_REPLAY_MAX_ERROR_K=%.17g\n',max(replayErrors));
assert(max(replayErrors)<.02,'Offline original does not reproduce saved SLX; stop.');
writetable(table(replayPaths,replayHashes),fullfile(out,'prior_input_hashes.csv'));

fprintf('BEGIN_ORIGINAL_CONSISTENT_INITIAL_CONTROL\n');
consistentOriginal=ode15s(@(t,z) rhs(t,z,p,false),[0,500],consistentOriginal0,opts);
assert(consistentOriginal.x(end)==500);
fprintf('END_ORIGINAL_CONSISTENT_INITIAL_CONTROL\n');

fprintf('BEGIN_LITERAL_MEAN_6_STATE\n'); tic;
literal=ode15s(@(t,z) rhs(t,z,p,true),[0,500],mean0,opts);
assert(literal.x(end)==500); fprintf('END_LITERAL seconds=%g\n',toc);
% Independent tighter integration, unchanged equations and initial state.
tight=odeset(opts,'RelTol',1e-10,'AbsTol',1e-11,'MaxStep',.05);
fprintf('BEGIN_LITERAL_TIGHTER\n'); tic;
literalTight=ode15s(@(t,z) rhs(t,z,p,true),[0,500],mean0,tight);
assert(literalTight.x(end)==500); fprintf('END_LITERAL_TIGHTER seconds=%g\n',toc);

times=unique([linspace(0,.5,5001),linspace(.5,5,1801),linspace(5,500,4951)]);
ols=deval(original,times); mls=deval(literal,times); tls=deval(literalTight,times);
convergence=max(abs(mls-tls),[],'all'); assert(convergence<.002);
names=["original_replay","literal_mean","literal_tighter"];
solutions={original,literal,literalTight}; metrics=struct([]);
names(4)="original_consistent_initial"; solutions{4}=consistentOriginal;
for k=1:4
    isMean=k==2 || k==3; sol=solutions{k}; states=deval(sol,times);
    n=numel(times); outputs=zeros(n,6); balances=zeros(n,2); q=zeros(n,4); rates=zeros(size(states));
    for j=1:n
        [rates(:,j),outputs(j,:),balances(j,:),q(j,:)]=rhs(times(j),states(:,j),p,isMean);
    end
    assert(all(isfinite(outputs),'all')); assert(max(abs(balances),[],'all')<1e-5);
    writematrix([times.',states.'],fullfile(out,names(k)+"_states.csv"));
    writematrix([times.',outputs,q],fullfile(out,names(k)+"_outputs.csv"));
    [minima,indices]=min(outputs,[],1);
    s=struct('name',names(k),'final_time_s',sol.x(end), ...
        'output_final_K',outputs(end,:),'output_min_K',minima, ...
        'time_of_output_min_s',times(indices),'output_max_K',max(outputs,[],1), ...
        'max_local_power_residual_W',max(abs(balances),[],'all'), ...
        'final_max_state_rate_K_s',max(abs(rates(:,end))), ...
        'state_min_K',min(states,[],2),'state_max_K',max(states,[],2));
    if k==1, metrics=s; else, metrics(k)=s; end %#ok<AGROW>
end
% The original and literal closures share their equilibrium conditions.
equilibriumDifference=max(abs(metrics(1).output_final_K-metrics(2).output_final_K));
assert(equilibriumDifference<.01);
result=struct('scope','Offline ODE, actual two-region arrangement. Not a new SLX run or author implementation.', ...
    'parameters',p,'initial',initial,'original_vs_saved_SLX_max_errors_K',replayErrors, ...
    'literal_tolerance_refinement_max_state_error_K',convergence, ...
    'original_vs_literal_final_output_max_difference_K',equilibriumDifference, ...
    'metrics',metrics,'output_csv_columns', ...
    {{'time','hot1','hot2','cold1','cold2','wall1','wall2','qh1','qc1','qh2','qc2'}}, ...
    'limits',{{'Inherited h and calibrated Li cp are not independently validated here.', ...
    'Two-region discretization is inherited, not recovered from the author.', ...
    'Mean-state and original initial stored energies differ; only outlets/walls are matched.', ...
    'Current pressure wiring is deliberately preserved to isolate state closure.', ...
    'Local cp*deltaT power accounting is not an independent variable-cp enthalpy proof.', ...
    'No wall-state averaging is asserted to be the paper wall temperature.'}});
writeJson(fullfile(out,'summary.json'),result);
save(fullfile(out,'solutions.mat'),'original','literal','literalTight','consistentOriginal','result','times','-v7.3');
checkProtected(guard); writetable(guard,fullfile(out,'protected_after.csv'));
fprintf('%s\n',jsonencode(result,PrettyPrint=true));
fprintf('IHX_MEAN_STATE_DIAGNOSTIC_COMPLETE_500S; PROTECTED=34; NO_SLX_RUN_OR_PROMOTION\n');
end

function [d,v,balance,qout]=rhs(~,z,p,isMean)
if isMean
    cm=z([1,4]); hm=z([2,5]); w=z([3,6]);
    ho=[2*hm(1)-p.Thi;0]; ho(2)=2*hm(2)-ho(1);
    co=[0;2*cm(2)-p.Tci]; co(1)=2*cm(1)-co(2);
else
    cm=z([1,6]); co=z([2,7]); hm=z([3,8]); ho=z([4,9]); w=z([5,10]);
end
hin=[p.Thi;ho(1)]; cin=[co(2);p.Tci];
d=zeros(size(z)); balance=zeros(1,2); qout=zeros(1,4);
for r=1:2
    assert(hm(r)>=453.7 && hm(r)<=1608 && cm(r)>=100 && cm(r)<=2000, ...
        'Diagnostic left a formal property range; no clamping allowed.');
    assert(w(r)>=p.wallT(1) && w(r)<=p.wallT(end),'Diagnostic wall table extrapolation.');
    cph=Lithium_property_simulink(hm(r),.234e6);
    cpc=HeXe_property_simulink(cm(r),p.pressure(r));
    cpw=interp1(p.wallT,p.wallCp,w(r),'linear');
    bh=p.mh*cph; bc=p.mc*cpc; bw=p.mw*cpw;
    ch=p.mhFlow*cph; cc=p.mcFlow*cpc;
    assert(all([bh,bc,bw,ch,cc]>0));
    qh=p.hh*p.A*(hm(r)-w(r)); qc=p.hc*p.A*(w(r)-cm(r));
    if isMean
        offset=(r-1)*3;
        d(offset+1)=(cc*(cin(r)-co(r))+qc)/bc;
        d(offset+2)=(ch*(hin(r)-ho(r))-qh)/bh;
        d(offset+3)=(qh-qc)/bw;
        storage=bc*d(offset+1)+bh*d(offset+2)+bw*d(offset+3);
    else
        offset=(r-1)*5;
        d(offset+1)=(cc*(cin(r)-cm(r))+qc/2)/(bc/2);
        d(offset+2)=(cc*(cm(r)-co(r))+qc/2)/(bc/2);
        d(offset+3)=(ch*(hin(r)-hm(r))-qh/2)/(bh/2);
        d(offset+4)=(ch*(hm(r)-ho(r))-qh/2)/(bh/2);
        d(offset+5)=(qh-qc)/bw;
        storage=bc/2*sum(d(offset+(1:2)))+bh/2*sum(d(offset+(3:4)))+bw*d(offset+5);
    end
    balance(r)=storage-ch*(hin(r)-ho(r))-cc*(cin(r)-co(r));
    qout((r-1)*2+(1:2))=[qh,qc];
end
v=[ho.',co.',w.'];
end

function checkProtected(t)
for k=1:height(t), assert(fileHash(t.paths(k))==t.hashes(k),t.paths(k)); end
end
function h=fileHash(p)
[s,t]=system("shasum -a 256 '"+replace(string(p),"'","'\''")+"'");
assert(s==0); a=split(strtrim(string(t))); h=a(1);
end
function writeJson(p,r)
f=fopen(p,'w'); assert(f~=-1); c=onCleanup(@() fclose(f)); %#ok<NASGU>
fprintf(f,'%s\n',jsonencode(r,PrettyPrint=true));
end
function restore(folder,savedPath,savedWarning)
cd(folder); path(savedPath); warning(savedWarning);
end
