% Read-only diagnosis: official cp on Table 5.2 recuperator paths.
% No SLX load, simulation, property substitution, or Scheme A evaluation.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',dest);
savedPath=path; pathCleanup=onCleanup(@() path(savedPath));
savedWarnings=warning; warningCleanup=onCleanup(@() warning(savedWarnings));
warning('error','MATLAB:integral:MaxIntervalCountReached');
warning('error','MATLAB:integral:NonFiniteValue');
warning('error','MATLAB:quadgk:MaxIntervalCountReached');
warning('error','MATLAB:quadgk:NonFiniteValue');
warning('error','HeXe:T_lo'); warning('error','HeXe:T_hi');
addpath(source);
prop=fullfile(source,'HeXe_property_simulink.m');
assert(string(which('HeXe_property_simulink'))==prop);
assert(hashFile(prop)=="2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640','protected_after.csv'),TextType='string');
checkProtected(protected);
model=fullfile(fileparts(repo),'不接入转子稳态模型_副本','final_steady_24a.slx');
assert(hashFile(model)=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");

% Exact active C111 expression, independently bracketed, no property edits.
rootT=fzero(@heliumC,[990 995]);
pressures=[.676e6 1.551e6];
offsets=10.^(-(1:6));
rows=[];
for P=pressures
    for d=offsets
        for side=[-1 1]
            T=rootT+side*d;
            [cp,gamma,rho]=HeXe_property_simulink(T,P);
            rows(end+1,:)=[P d side T cp cp/gamma gamma rho heliumC(T)]; %#ok<SAGROW>
        end
    end
end
samples=array2table(rows,VariableNames={'P_Pa','offset_K','side','T_K','cp_J_kgK','cv_J_kgK','gamma','rho_kg_m3','C111_m6_mol2'});
writetable(samples,fullfile(dest,'pole_samples.csv'));

% No integral crosses the singular point. Log-distance change of variables
% resolves each finite truncated interval without interpreting a warning as
% an answer. These one-sided truncations are NOT admissible whole-path cpbar.
cutoffs=10.^(-(2:5)); integralRows=[];
for P=pressures
    for epsilon=cutoffs
        for side=[-1 1]
            fun=@(y) arrayfun(@(v) officialCp(rootT+side*exp(v),P)*exp(v),y);
            [q,err]=quadgk(fun,log(epsilon),log(.1),'RelTol',1e-7,'AbsTol',1e-4);
            assert(isfinite(q) && isfinite(err));
            % Composite Simpson in log-distance is an independent quadrature
            % of this same finite, one-sided interval, not a physical repair.
            yy=linspace(log(epsilon),log(.1),8001); ff=fun(yy);
            h=yy(2)-yy(1);
            qs=h/3*(ff(1)+ff(end)+4*sum(ff(2:2:end-1))+2*sum(ff(3:2:end-2)));
            assert(abs(q-qs)<max(.01,abs(q)*2e-4));
            integralRows(end+1,:)=[P epsilon side q err qs abs(q-qs)]; %#ok<SAGROW>
        end
    end
end
truncated=array2table(integralRows,VariableNames={'P_Pa','cutoff_K','side','integral_cp_J_kg','quadgk_error_estimate','simpson_J_kg','crosscheck_abs_J_kg'});
writetable(truncated,fullfile(dest,'one_sided_integrals.csv'));

% Values below are direct Table 5.2 endpoints/duties, not inferred flows.
names=["IHX_cold","recuperator_hot","recuperator_cold","cooler_hot"];
values=[1100.91 1522.96 1.543e6 1.539e6 2647.18e3; ...
        1162 663.63 .676e6 .676e6 3130.58e3; ...
        601.90 1100.91 1.551e6 1.543e6 3130.58e3; ...
        663.63 405.16 .676e6 .658e6 1622e3];
paths=struct([]);
for k=1:numel(names)
    v=values(k,:); crosses=min(v(1:2))<rootT && rootT<max(v(1:2));
    item=struct('name',names(k),'Tin_K',v(1),'Tout_K',v(2),'Pin_Pa',v(3), ...
        'Pout_Pa',v(4),'table_duty_W',v(5),'crosses_C111_zero',crosses, ...
        'cpbar_valid',false,'inferred_flow_kg_s',NaN,'cpbar_J_kgK',NaN, ...
        'reason',"Crosses active signed-cube-root derivative singularity; no whole-path flow returned.");
    if ~crosses
        ts=linspace(min(v(1:2)),max(v(1:2)),1001);
        cps=arrayfun(@(t) officialCp(t,v(3)),ts); assert(all(cps>0));
        dh=integral(@(t) arrayfun(@(x) officialCp(x,v(3)),t),v(1),v(2), ...
            'RelTol',1e-10,'AbsTol',1e-5);
        dp=integral(@(p) arrayfun(@(x) pressureIntegrand(v(2),x),p),v(3),v(4), ...
            'RelTol',1e-8,'AbsTol',1e-6);
        item.cpbar_valid=true; item.cpbar_J_kgK=dh/(v(2)-v(1));
        item.inferred_flow_kg_s=v(5)/abs(dh+dp);
        item.reason="Conditional inverse using official property, not thesis-direct mass flow.";
    end
    if isempty(paths), paths=item; else, paths(k)=item; end
end
assert(nnz([paths.cpbar_valid])==2);
checkProtected(protected); writetable(protected,fullfile(dest,'protected_after.csv'));
files=[string(mfilename('fullpath'))+".m",prop,model, ...
    fullfile(repo,'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf'), ...
    fullfile(dest,'pole_samples.csv'),fullfile(dest,'one_sided_integrals.csv')];
hashes=struct([]);
for k=1:numel(files), hashes(k).path=files(k); hashes(k).sha256=hashFile(files(k)); end
result=struct('root_T_K',rootT,'root_C111',heliumC(rootT),'paths',paths, ...
    'source_hashes',hashes,'protected_count',height(protected), ...
    'no_SLX_loaded',true,'scheme_A_evaluated',false,'model_acceptance_passed',false, ...
    'scope','Official property only. Finite one-sided integrals are diagnostic, not a principal value, physical enthalpy or accepted cpbar. No parameter/model change.');
fid=fopen(fullfile(dest,'summary.json'),'w');assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true));fclose(fid);
disp(truncated);disp(struct2table(paths));
fprintf('HEXE_PATH_INTEGRABILITY_AUDIT_COMPLETE; VALID_PATHS=2/4; NO_SCHEME_A; PROTECTED=%d\n',height(protected));
diary off;

function c=heliumC(T)
theta=T/5.19; v=.0040026/69.64;
c=v^2*(.0757+(-.0862-3.6e-5*theta+.0237/theta^.059)*tanh(.84*theta));
end
function cp=officialCp(T,P)
[cp,~,~,~,~,~]=HeXe_property_simulink(T,P);
end
function a=pressureIntegrand(T,P)
[~,~,rho]=HeXe_property_simulink(T,P);
[~,~,rp]=HeXe_property_simulink(T+.01,P);
[~,~,rm]=HeXe_property_simulink(T-.01,P);
a=1/rho-T*(1/rp-1/rm)/.02;
end
function checkProtected(t)
for n=1:height(t), assert(hashFile(t.paths(n))==t.hashes(n),t.paths(n)); end
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
