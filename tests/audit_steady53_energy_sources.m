% Read-only source/energy audit. No load_system, model update, or simulation.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
prior=fullfile(fileparts(repo),'不接入转子稳态模型_副本','tmp','steady53','task8', ...
    'run_1787845512573_a1e82217bf864a55aceb5277bc0a0660');
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',dest);
addpath(source);
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
assert(string(which('HeXe_property_simulink'))==fullfile(source,'HeXe_property_simulink.m'));
model=fullfile(source,'final_steady_24a.slx');
modelHash=hashFile(model);
assert(modelHash=="0532e9ddf2deb7ef5e40cc1b8e619c44ea7afd36b00d807d118f4cd812a5a391");
liHash=hashFile(fullfile(source,'Lithium_property_simulink.m'));
heHash=hashFile(fullfile(source,'HeXe_property_simulink.m'));
assert(liHash=="666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f");
assert(heHash=="2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
manifest=jsondecode(fileread(fullfile(prior,'manifest.json')));
assert(string(manifest.sourceModelHash)==modelHash);
raw=fullfile(prior,manifest.rawMatFile);
assert(hashFile(raw)==string(manifest.rawMatHash));
for k=1:numel(manifest.smallFileHashes)
    item=manifest.smallFileHashes(k);
    assert(hashFile(fullfile(prior,item.name))==string(item.sha256));
end
data=load(raw,'result'); r=data.result;
assert(r.success && r.tFinal_s==500 && r.modelHashBefore==modelHash && r.modelHashAfter==modelHash);

% Unpack for inspection only. The saved SLX is never opened in Simulink.
xmlRoot=fullfile(dest,'readonly_slx'); unzip(model,xmlRoot);
doc=xmlread(fullfile(xmlRoot,'simulink','systems','system_1.xml'));
c=struct('inverse_C_fuel',constantValue(doc,'175','1/C_fuel'), ...
    'gamma_f',constantValue(doc,'178','gamma_f'), ...
    'hA1_W_K',constantValue(doc,'217','hA1'), ...
    'hA2_W_K',constantValue(doc,'222','hA2'), ...
    'reactor_cp_J_kgK',constantValue(doc,'207','cp_Li'), ...
    'Li_flow_kg_s',constantValue(doc,'251','Constant1'));
assert(c.hA1_W_K==c.hA2_W_K);
cpLi=@(t) arrayfun(@(x) Lithium_property_simulink(x,.234e6),t);
intLi=@(lo,hi) integral(cpLi,lo,hi,'RelTol',1e-10,'AbsTol',1e-5);
cpHe=@(t,p) arrayfun(@(x) HeXe_property_simulink(x,p),t);
intHe=@(lo,hi,p) integral(@(t) cpHe(t,p),lo,hi,'RelTol',1e-10,'AbsTol',1e-5);

% Four independent heat duties in Table 5.2. Inferred flows are NOT inputs.
names=["IHX_cold","recuperator_hot","recuperator_cold","cooler_hot"];
% [Tin Tout Pin Pout duty_W]. Duties are positive magnitudes.
tableValues=[1100.91 1522.96 1.543e6 1.539e6 2647.18e3; ...
    1162 663.63 .676e6 .676e6 3130.58e3; ...
    601.90 1100.91 1.551e6 1.543e6 3130.58e3; ...
    663.63 405.16 .676e6 .658e6 1622e3];
flows=struct([]);
for k=1:4
    v=tableValues(k,:);
    lastwarn('');
    dhT=intHe(v(1),v(2),v(3));
    [warnMessage,warnId]=lastwarn;
    if strlength(string(warnMessage))>0
        % A quadrature warning is a failed source check, NOT a usable flow.
        f=struct('name',names(k),'valid',false,'invalid_reason',string(warnMessage), ...
            'warning_id',string(warnId),'table_values',v,'cp_mean_J_kgK',NaN, ...
            'delta_h_T_J_kg',NaN,'delta_h_P_J_kg',NaN,'inferred_flow_kg_s',NaN, ...
            'inferred_flow_constant_Pin_kg_s',NaN,'Q_at_11_97_W',NaN);
        if k==1, flows=f; else, flows(k)=f; end
        continue
    end
    dhP=integral(@(p) arrayfun(@(x) pressureIntegrand(v(2),x),p), ...
        v(3),v(4),'RelTol',1e-8,'AbsTol',1e-6);
    assert(isempty(lastwarn),'Pressure integral warning: do not use this result.');
    grid=linspace(v(1),v(2),1001);
    sample=cpHe(grid,v(3)); assert(all(isfinite(sample) & sample>0));
    assert(abs(trapz(grid,sample)-dhT)<1e-3,'Independent quadrature cross-check failed.');
    f=struct('name',names(k),'valid',true,'invalid_reason',"",'warning_id',"", ...
        'table_values',v,'cp_mean_J_kgK',dhT/(v(2)-v(1)), ...
        'delta_h_T_J_kg',dhT,'delta_h_P_J_kg',dhP, ...
        'inferred_flow_kg_s',v(5)/abs(dhT+dhP), ...
        'inferred_flow_constant_Pin_kg_s',v(5)/abs(dhT), ...
        'Q_at_11_97_W',11.97*abs(dhT+dhP));
    if k==1, flows=f; else, flows(k)=f; end
end

s=r.signals;
idx=find(endsWith(string({r.states.path}),'/reactor/Integrator7'));
assert(isscalar(idx));
Tin=s.reactor_inlet_T(end); Tout=s.reactor_outlet_T(end);
Tf=r.states(idx).data(end); Prx=s.reactor_power(end);
mdot=s.lithium_mdot_reactor(end); assert(abs(mdot-c.Li_flow_kg_s)<1e-12);
Hfuel=c.gamma_f/c.inverse_C_fuel;
Tave=(Tin+Tout)/2;
Tout_formula=Tin+2*c.hA1_W_K*(Tf-Tin)/(2*mdot*c.reactor_cp_J_kgK+c.hA2_W_K);
assert(abs(Tout_formula-Tout)<1e-8);
Qfuel=Hfuel*(Tf-Tave);
Qout=mdot*c.reactor_cp_J_kgK*(Tout-Tin);
Qihx=intLi(Tin,Tout)*mdot;
fuelResidual=c.inverse_C_fuel*Prx-c.gamma_f*(Tf-Tave);
assert(abs(fuelResidual)<1e-6);
assert(abs(Qout-c.hA1_W_K*(Tf-Tave))<1e-6);
loop=struct('record_kind','Reanalysis of saved 500 s result, not a new simulation', ...
    't_final_s',r.t(end),'T_in_K',Tin,'T_out_K',Tout,'T_fuel_K',Tf,'P_Rx_W',Prx, ...
    'reactor_formula_T_out_K',Tout_formula,'fuel_derivative_from_equation_K_s',fuelResidual, ...
    'fuel_heat_coefficient_W_K',Hfuel,'outlet_heat_coefficient_W_K',c.hA1_W_K, ...
    'fuel_loss_W',Qfuel,'reactor_outlet_heat_W',Qout,'IHX_property_enthalpy_W',Qihx, ...
    'outlet_minus_fuel_W',Qout-Qfuel,'outlet_minus_IHX_property_W',Qout-Qihx, ...
    'IHX_property_minus_Rx_W',Qihx-Prx, ...
    'current_IHX_cp_average_J_kgK',Qihx/(mdot*(Tout-Tin)), ...
    'counterfactual_unscaled_ORNL_IHX_heat_W',Qihx/.9615, ...
    'hexe_mdot_IHX_kg_s',s.hexe_mdot_ihx(end));

% Literature functions evaluated OFFLINE. They do not replace active code.
lo=1443.27; hi=1600; Qtarget=2647.18e3;
F=@(t) 1000*(-1.044e5./t-135.1*log(t)+4.180*t);
cpORNL=(F(hi)-F(lo))/(hi-lo);
cpCurrent=intLi(lo,hi)/(hi-lo);
assert(abs(cpCurrent-.9615*cpORNL)<1e-7);
lithium=struct('T_lo_K',lo,'T_hi_K',hi,'current_cp_average_J_kgK',cpCurrent, ...
    'ORNL_Eq8_cp_average_J_kgK',cpORNL,'NASA_TN_D4650_Eq5_cp_J_kgK',4169, ...
    'reactor_constant_cp_J_kgK',c.reactor_cp_J_kgK, ...
    'inverse_cp_for_fixed_table_targets_J_kgK',Qtarget/(mdot*(hi-lo)), ...
    'Q_current_W',mdot*cpCurrent*(hi-lo),'Q_ORNL_W',mdot*cpORNL*(hi-lo), ...
    'Q_NASA_W',mdot*4169*(hi-lo),'Q_reactor_constant_W',mdot*c.reactor_cp_J_kgK*(hi-lo));
scheme=struct('specific_work_table4_9_kJ_kg',93.56, ...
    'conditional_flow_if_1MW_net_kg_s',1000/93.56, ...
    'conditional_flow_if_table5_2_design_shaft_net_kg_s',(2253-1233)/93.56, ...
    'note','Conditional cross-table ratios, not thesis-specified flow. Eq2.48 has a dimensional inconsistency in its last equality; Eq2.47 and prose define specific work.');
result=struct('scope','Read-only source trace and energy accounting; inverse values not applied; no new simulation', ...
    'constants',c,'saved_loop',loop,'table5_2_inferred_flows',flows,'lithium_sources',lithium, ...
    'schemeB_crosscheck',scheme,'model_sha256',modelHash,'li_sha256',liHash,'hexe_sha256',heHash, ...
    'source_record',raw,'source_record_sha256',hashFile(raw));
assert(hashFile(model)==modelHash && hashFile(fullfile(source,'Lithium_property_simulink.m'))==liHash);
fid=fopen(fullfile(dest,'energy_source_audit.json'),'w'); assert(fid~=-1);
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true)); fclose(fid);
disp(jsonencode(result,PrettyPrint=true));
fprintf('READ_ONLY_ENERGY_SOURCE_AUDIT_COMPLETE; VALID_HEXE_PATHS=%d/4; INVALID_PATHS_EXCLUDED\n',nnz([flows.valid])); diary off;

function value=constantValue(doc,sid,name)
blocks=doc.getElementsByTagName('Block'); found=false;
for k=0:blocks.getLength-1
    b=blocks.item(k);
    if strcmp(char(b.getAttribute('SID')),sid)
        assert(~found && strcmp(char(b.getAttribute('Name')),name));
        assert(strcmp(char(b.getAttribute('BlockType')),'Constant'));
        ps=b.getElementsByTagName('P');
        for j=0:ps.getLength-1
            p=ps.item(j);
            if strcmp(char(p.getAttribute('Name')),'Value')
                value=str2double(char(p.getTextContent)); found=true;
            end
        end
    end
end
assert(found && isfinite(value));
end
function a=pressureIntegrand(T,P)
[~,~,rho]=HeXe_property_simulink(T,P);
[~,~,rp]=HeXe_property_simulink(T+.01,P);
[~,~,rm]=HeXe_property_simulink(T-.01,P);
a=1/rho-T*(1/rp-1/rm)/.02;
end
function hash=hashFile(file)
[status,txt]=system("shasum -a 256 '"+replace(string(file),"'","'\''")+"'");
assert(status==0); tokens=split(strtrim(string(txt))); hash=tokens(1);
end
