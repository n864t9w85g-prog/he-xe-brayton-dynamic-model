% Approved exploration: existing Scheme A on four OFFLINE cp/enthalpy paths.
% No model load/simulation, no official function/MAT/SLX change, no flow patch.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
candidate=fullfile(source,'tests','steady53','hexe_property_scheme_a_offline.m');
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',dest);
savedPath=path; pathCleanup=onCleanup(@() path(savedPath));
savedWarnings=warning; warningCleanup=onCleanup(@() warning(savedWarnings));
warning('error','MATLAB:quadgk:MaxIntervalCountReached');
warning('error','MATLAB:quadgk:NonFiniteValue');
addpath(fileparts(candidate));
assert(string(which('hexe_property_scheme_a_offline'))==candidate);
candidateHash="5820e957b90b1affce777c1774aee6cc685f40430310408fb00f303846f606d0";
assert(hashFile(candidate)==candidateHash);
protected=readtable(fullfile(repo,'tmp','tp7d213f64_7fad_4bfa_b722_0771b21d9640','protected_after.csv'),TextType='string');
checkProtected(protected); writetable(protected,fullfile(dest,'protected_before.csv'));
previousFile=fullfile(repo,'tmp','tp4e183961_9624_4b9f_ac65_941d915081f3','summary.json');
assert(hashFile(previousFile)=="b466da117a0a87795b7d4d6669a944e3394c8db76bf526f6e91a153b9b63257d");
previous=jsondecode(fileread(previousFile));

% Table 5.2 simulation column (PDF104/printed89), NOT fitted inputs.
names=["IHX_cold","recuperator_hot","recuperator_cold","cooler_hot"];
values=[1100.91 1522.96 1.543e6 1.539e6 2647.18e3; ...
        1162 663.63 .676e6 .676e6 3130.58e3; ...
        601.90 1100.91 1.551e6 1.543e6 3130.58e3; ...
        663.63 405.16 .676e6 .658e6 1622e3];
projectMdot=11.97; % Existing approved component-fixture boundary; not paper-direct.
rootT=previous.root_T_K;
paths=struct([]); domainRows=[];
for k=1:numel(names)
    v=values(k,:); fprintf('EVALUATING %s\n',names(k));
    assert(all(v==[previous.paths(k).Tin_K previous.paths(k).Tout_K ...
        previous.paths(k).Pin_Pa previous.paths(k).Pout_Pa previous.paths(k).table_duty_W]));
    % Audit both L-shaped integration routes (not a claim of every interior point).
    ts=linspace(min(v(1:2)),max(v(1:2)),1001);
    if min(ts)<rootT && rootT<max(ts)
        ts=unique([ts rootT rootT+[-1e-3 -1e-6 1e-6 1e-3]]);
    end
    coordinates=[];
    for p=unique(v(3:4))
        coordinates=[coordinates; ts(:) repmat(p,numel(ts),1)]; %#ok<AGROW>
    end
    ps=linspace(v(3),v(4),101);
    for t=unique(v(1:2))
        coordinates=[coordinates; repmat(t,numel(ps),1) ps(:)]; %#ok<AGROW>
    end
    coordinates=unique(coordinates,'rows');
    local=zeros(size(coordinates,1),19);
    for j=1:size(coordinates,1)
        T=coordinates(j,1); P=coordinates(j,2);
        [cp,gamma,rho,a]=hexe_property_scheme_a_offline(T,P);
        n=a.rhoHat;
        relEOS=abs(8.314*T*(n+a.B*n^2+a.C*n^3)-P)/P;
        zeroTerms=[a.C111 a.C112 a.C122 a.dC111_dT a.dC112_dT ...
            a.dC122_dT a.d2C111_dT2 a.d2C112_dT2 a.d2C122_dT2];
        assert(all(zeroTerms==0));
        assert(all(isfinite([cp gamma rho a.cvMass a.dPdrho])));
        assert(cp>0 && a.cvMass>0 && gamma>1 && rho>0 && a.dPdrho>0);
        assert(a.stablePositiveRealRootCount==1 && ~a.productionNewton.clampChanged);
        assert(relEOS<1e-12);
        local(j,:)=[k T P cp a.cvMass gamma rho a.dPdrho ...
            a.stablePositiveRealRootCount a.productionNewton.clampChanged ...
            relEOS a.productionNewton.converged a.productionNewton.iterations ...
            a.productionNewton.lastDelta max(abs(zeroTerms)) n ...
            a.drhoHat_dT enthalpy(a) pressureFromAudit(a)];
    end
    domainRows=[domainRows;local]; %#ok<AGROW>
    % Same path as the prior official calculation: T first at Pin, then P at Tout.
    fT=@(T) arrayfun(@(t) cpAt(t,v(3)),T);
    fP=@(P) arrayfun(@(p) pressureAt(v(2),p),P);
    [dT,eT]=quadgk(fT,v(1),v(2),'RelTol',1e-10,'AbsTol',1e-6);
    [dP,eP]=quadgk(fP,v(3),v(4),'RelTol',1e-10,'AbsTol',1e-6);
    sT1=simpson(fT,v(1),v(2),1000); sT2=simpson(fT,v(1),v(2),2000);
    sP1=simpson(fP,v(3),v(4),200); sP2=simpson(fP,v(3),v(4),400);
    [~,~,~,aIn]=hexe_property_scheme_a_offline(v(1),v(3));
    [~,~,~,aOut]=hexe_property_scheme_a_offline(v(2),v(4));
    dhEndpoint=enthalpy(aOut)-enthalpy(aIn);
    % Alternative rectangle route tests state-function consistency, not a new input.
    altP=quadgk(@(P) arrayfun(@(p) pressureAt(v(1),p),P),v(3),v(4), ...
        'RelTol',1e-10,'AbsTol',1e-6);
    altT=quadgk(@(T) arrayfun(@(t) cpAt(t,v(4)),T),v(1),v(2), ...
        'RelTol',1e-10,'AbsTol',1e-6);
    dh=dT+dP;
    % Numerical cross-check limits, NOT paper-reproduction acceptance tolerances.
    assert(max(abs([dT-sT2 dP-sP2 sT2-sT1 sP2-sP1]))<1e-3);
    assert(abs(dh-dhEndpoint)<1e-3 && abs(dh-altT-altP)<1e-3);
    item=struct('name',names(k),'Tin_K',v(1),'Tout_K',v(2),'Pin_Pa',v(3), ...
        'Pout_Pa',v(4),'table_duty_W',v(5),'cpbar_J_kgK',dT/(v(2)-v(1)), ...
        'dH_T_J_kg',dT,'dH_P_J_kg',dP,'dH_total_J_kg',dh, ...
        'endpoint_dH_J_kg',dhEndpoint,'alternate_route_dH_J_kg',altT+altP, ...
        'quadgk_error_T',eT,'quadgk_error_P',eP, ...
        'simpson_T_1000',sT1,'simpson_T_2000',sT2, ...
        'simpson_P_200',sP1,'simpson_P_400',sP2, ...
        'inferred_flow_kg_s',v(5)/abs(dh), ...
        'duty_at_project_flow_W',projectMdot*abs(dh), ...
        'project_flow_duty_error_percent',100*(projectMdot*abs(dh)/v(5)-1), ...
        'sample_count',size(local,1),'cp_min',min(local(:,4)),'cp_max',max(local(:,4)), ...
        'cv_min',min(local(:,5)),'cv_max',max(local(:,5)), ...
        'gamma_min',min(local(:,6)),'gamma_max',max(local(:,6)), ...
        'max_relative_EOS_residual',max(local(:,11)), ...
        'newton_delta_stop_false_count',nnz(~local(:,12)), ...
        'max_abs_newton_last_delta',max(abs(local(:,14))), ...
        'official_path_valid',previous.paths(k).cpbar_valid, ...
        'official_inferred_flow_kg_s',previous.paths(k).inferred_flow_kg_s);
    if isempty(paths), paths=item; else, paths(k)=item; end
end
domain=array2table(domainRows,VariableNames={'path_index','T_K','P_Pa','cp_J_kgK', ...
    'cv_J_kgK','gamma','rho_kg_m3','dPdrho','stable_positive_root_count', ...
    'density_floor_active','relative_EOS_residual','newton_delta_stop_met', ...
    'newton_iterations','newton_last_delta','removed_terms_max_abs','rho_molar', ...
    'drho_molar_dT','h_J_kg','pressure_dh_integrand_m3_kg'});
writetable(domain,fullfile(dest,'domain_samples.csv'));
writetable(struct2table(paths),fullfile(dest,'four_paths.csv'));
flows=[paths.inferred_flow_kg_s];
consistency=struct('min_flow_kg_s',min(flows),'max_flow_kg_s',max(flows), ...
    'mean_flow_kg_s',mean(flows),'range_kg_s',range(flows), ...
    'range_over_mean_percent',100*range(flows)/mean(flows), ...
    'max_deviation_from_mean_percent',100*max(abs(flows/mean(flows)-1)), ...
    'exact_common_flow',all(flows==flows(1)), ...
    'new_acceptance_threshold_created',false,'flow_applied',false);
checkProtected(protected); assert(hashFile(candidate)==candidateHash);
writetable(protected,fullfile(dest,'protected_after.csv'));
files=[string(mfilename('fullpath'))+".m",candidate,previousFile, ...
    fullfile(repo,'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf'), ...
    fullfile(source,'tests','steady53','steady53_component_boundaries.m'), ...
    fullfile(dest,'domain_samples.csv'),fullfile(dest,'four_paths.csv')];
hashes=struct([]);
for k=1:numel(files), hashes(k).path=files(k); hashes(k).sha256=hashFile(files(k)); end
result=struct('paths',paths,'flow_consistency',consistency,'source_hashes',hashes, ...
    'project_fixture_flow_kg_s',projectMdot,'protected_count',height(protected), ...
    'sample_count',height(domain),'sample_domain_pass',true, ...
    'no_SLX_loaded',true,'no_SLX_simulated',true,'scheme_A_evaluated',true, ...
    'model_acceptance_passed',false,'candidate_promoted',false, ...
    'numerical_crosscheck_abs_limit_J_kg',1e-3, ...
    'scope','Approved existing Scheme A only for four offline cp/enthalpy paths. No formal changes or inferred-flow application. Sampled-domain positivity is not a global or experimental property validation.');
fid=fopen(fullfile(dest,'summary.json'),'w');assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true));fclose(fid);
disp(struct2table(paths)); disp(consistency);
fprintf('SCHEME_A_FOUR_PATHS_OFFLINE_COMPLETE; SAMPLED_DOMAIN_PASS; PROTECTED=%d; NO_MODEL_PROMOTION\n',height(protected));
diary off;

function cp=cpAt(T,P)
[cp,~,~,~]=hexe_property_scheme_a_offline(T,P);
end
function a=pressureAt(T,P)
[~,~,~,s]=hexe_property_scheme_a_offline(T,P);a=pressureFromAudit(s);
end
function a=pressureFromAudit(s)
M=.7172*.0040026+(1-.7172)*.131293;
% v=1/(M*n); dv/dT=-n_T/(M*n^2), valid here with inactive density floor.
a=1/(M*s.rhoHat)+s.T_K*s.drhoHat_dT/(M*s.rhoHat^2);
end
function h=enthalpy(s)
M=.7172*.0040026+(1-.7172)*.131293;T=s.T_K;n=s.rhoHat;
% Integrated virial state function, up to an arbitrary constant.
% h = (5RT/2 + RT*((B-T*B_T)*n+(C-T*C_T/2)*n^2))/M.
h=(2.5*8.314*T+8.314*T*((s.B-T*s.dB_dT)*n+ ...
    (s.C-.5*T*s.dC_dT)*n^2))/M;
end
function q=simpson(fun,a,b,n)
assert(mod(n,2)==0);if a==b, q=0;return;end
x=linspace(a,b,n+1);y=fun(x);
q=(b-a)/n/3*(y(1)+y(end)+4*sum(y(2:2:end-1))+2*sum(y(3:2:end-2)));
end
function checkProtected(t)
for n=1:height(t), assert(hashFile(t.paths(n))==t.hashes(n),t.paths(n)); end
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\\''")+"'");
assert(status==0);tokens=split(strtrim(string(txt)));hash=tokens(1);
end
