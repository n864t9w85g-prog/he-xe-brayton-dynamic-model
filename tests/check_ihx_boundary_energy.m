% Read-only IHX boundary compatibility: no SLX load/simulation/model edits.
repoRoot=string(fileparts(fileparts(mfilename('fullpath'))));
sourceRoot=fullfile(repoRoot,'tmp','steady53_curves_20260828','source_f8bcd83');
outRoot=string(tempname(fullfile(repoRoot,'tmp'))); mkdir(outRoot);
diary(fullfile(outRoot,'diary.txt')); fprintf('OUTPUT_DIR=%s\n',outRoot);
addpath(sourceRoot);
assert(string(which('Lithium_property_simulink'))==fullfile(sourceRoot,'Lithium_property_simulink.m'));
assert(string(which('HeXe_property_simulink'))==fullfile(sourceRoot,'HeXe_property_simulink.m'));
liFile=fullfile(sourceRoot,'Lithium_property_simulink.m'); heFile=fullfile(sourceRoot,'HeXe_property_simulink.m');
before=[hashFile(liFile),hashFile(heFile)];
assert(before(1)=="666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f");
assert(before(2)=="2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2");
P_h=0.234e6; P_ci=1.543e6; P_co=1.539e6;
T_hi=1600; T_ci=1100.91; mdot_h=4.572; mdot_c=11.97;
cpH=@(t) arrayfun(@(x) Lithium_property_simulink(x,P_h),t);
cpC=@(t,p) arrayfun(@(x) HeXe_property_simulink(x,p),t);
intH=@(lo,hi) integral(cpH,lo,hi,'RelTol',1e-10,'AbsTol',1e-5);
intC=@(lo,hi,p) integral(@(t) cpC(t,p),lo,hi,'RelTol',1e-10,'AbsTol',1e-5);
paperQ=2647.18e3;
scanFile=fullfile(repoRoot,'tmp','tpf255e6c2_bcc0_4262_883f_5caf6d3f6a0d','analysis','paper_ihx_points.csv');
scan=readtable(scanFile);
prev=fullfile(repoRoot,'tmp','tp80484fa0_602f_4386_89ed_ae9ca96b3359');
origHot=readmatrix(fullfile(prev,'original_500','y_001.csv'));
origCold=readmatrix(fullfile(prev,'original_500','y_003.csv'));
candHot=readmatrix(fullfile(prev,'candidate_500','y_001.csv'));
candCold=readmatrix(fullfile(prev,'candidate_500','y_003.csv'));
names=["table5_2","figure5_18_last_sample","original_500_end","candidate_500_end"];
outlets=[1443.27 1522.96;scan.hot_K(end) scan.cold_K(end); ...
    origHot(end,2) origCold(end,2);candHot(end,2) candCold(end,2)];
cases=struct([]);
for k=1:numel(names)
    Tho=outlets(k,1); Tco=outlets(k,2);
    dhH=intH(Tho,T_hi); dhC=intC(T_ci,Tco,P_ci);
    dpTerm=pressureTerm(Tco,P_ci,P_co,.01);
    r=struct('name',names(k),'T_ho_K',Tho,'T_co_K',Tco, ...
        'hot_cp_mean_J_kgK',dhH/(T_hi-Tho),'cold_cp_mean_J_kgK',dhC/(Tco-T_ci), ...
        'hot_Q_W',mdot_h*dhH,'cold_Q_constant_Pin_W',mdot_c*dhC, ...
        'cold_pressure_correction_W',mdot_c*dpTerm, ...
        'cold_Q_pressure_path_W',mdot_c*(dhC+dpTerm), ...
        'gap_W',mdot_h*dhH-mdot_c*(dhC+dpTerm), ...
        'hot_minus_table_power_W',mdot_h*dhH-paperQ, ...
        'cold_minus_table_power_W',mdot_c*(dhC+dpTerm)-paperQ);
    if k==1, cases=r; else, cases(k)=r; end
end
% Positive cp ensures monotone endpoint bounds; verify in this temperature
% domain. Pressure paths are evaluated at the bounding outlet temperatures.
assert(all(cpH(linspace(1400,1600,201))>0));
assert(all(cpC(linspace(1097,1530,201),P_ci)>0));
Ths=scan.hot_K(end); Tcs=scan.cold_K(end); dTread=3;
hotBounds=sort(mdot_h*[intH(Ths-dTread,T_hi),intH(Ths+dTread,T_hi)]);
coldBounds=zeros(1,2);
for k=1:2
    tc=Tcs+(2*k-3)*dTread;
    coldBounds(k)=mdot_c*(intC(T_ci,tc,P_ci)+pressureTerm(tc,P_ci,P_co,.01));
end
coldBounds=sort(coldBounds);
% Wider sensitivity: allow all four temperatures +/-3 K, not just read-off
% outlet values. These inlet intervals are hypothetical, not source errors.
wideHot=[mdot_h*intH(Ths+3,T_hi-3),mdot_h*intH(Ths-3,T_hi+3)];
wideCold=[mdot_c*intC(T_ci+3,Tcs-3,P_ci),mdot_c*intC(T_ci-3,Tcs+3,P_ci)];
% Quantify pressure/cp quadrature sensitivity rather than assume it is zero.
coldPressureEndpoints=mdot_c*[intC(T_ci,1522.96,P_ci),intC(T_ci,1522.96,P_co)];
pressureFDsteps=[.1,.01,.001]; pressureFD=zeros(size(pressureFDsteps));
for k=1:numel(pressureFDsteps)
    pressureFD(k)=mdot_c*pressureTerm(1522.96,P_ci,P_co,pressureFDsteps(k));
end
% Analytic integral of the EXACT active lithium correlation; not a new cp.
F=@(t) .9615*1000*(-1.044e5./t-135.1*log(t)+4.180*t);
analyticResidual=abs(intH(1443.27,T_hi)-(F(T_hi)-F(1443.27)));
assert(analyticResidual<1e-6);
% Inverse quantities describe incompatibility; NEVER applied to models.
required=struct( ...
    'Li_flow_for_tableQ_kg_s',paperQ/intH(1443.27,T_hi), ...
    'HeXe_flow_for_tableQ_kg_s',paperQ/(intC(T_ci,1522.96,P_ci)+pressureTerm(1522.96,P_ci,P_co,.01)), ...
    'Li_cp_average_for_tableQ_J_kgK',paperQ/(mdot_h*(T_hi-1443.27)), ...
    'Li_cp_average_for_reactor2664kW_J_kgK',2664e3/(mdot_h*(T_hi-1443.27)), ...
    'hot_inlet_for_tableQ_K',fzero(@(thi) mdot_h*intH(1443.27,thi)-paperQ,[1444,1600]), ...
    'hot_outlet_for_tableQ_K',fzero(@(tho) mdot_h*intH(tho,T_hi)-paperQ,[1400,1599]), ...
    'cold_outlet_for_tableQ_K',fzero(@(tco) mdot_c*intC(T_ci,tco,P_ci)-paperQ,[1400,1599]));
result=struct('cases',cases,'inputs',struct('T_hi',T_hi,'T_ci',T_ci,'mdot_h',mdot_h, ...
    'mdot_c',mdot_c,'P_h',P_h,'P_ci',P_ci,'P_co',P_co,'IHX_table_power_W',paperQ), ...
    'scan_outlet_only_Q_bounds_W',struct('hot',hotBounds,'cold',coldBounds, ...
        'minimum_gap',hotBounds(1)-coldBounds(2)), ...
    'all_four_temperatures_plusminus3K_sensitivity_W',struct('hot',wideHot,'cold_at_Pin',wideCold), ...
    'cold_P_endpoint_cp_integrals_W',coldPressureEndpoints, ...
    'pressure_FD_steps_K',pressureFDsteps,'pressure_FD_corrections_W',pressureFD, ...
    'Li_integral_analytic_residual_J_kg',analyticResidual,'required_not_applied',required, ...
    'property_hashes',before,'scan_csv_hash',hashFile(scanFile), ...
    'scope','Conditional boundary audit using current property functions. Pressure path uses dh=cp dT+(v-T dv/dT)_P dP. Not an independent validation of those properties, not a proposal to apply inverse values.');
assert(isequal(before,[hashFile(liFile),hashFile(heFile)]));
fid=fopen(fullfile(outRoot,'boundary_energy.json'),'w'); assert(fid~=-1);
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true)); fclose(fid);
save(fullfile(outRoot,'boundary_energy.mat'),'result');
disp(jsonencode(result,PrettyPrint=true));
fprintf('READ_ONLY_PROPERTY_AUDIT_COMPLETE_NO_SLX_LOADED\n'); diary off;

function h=pressureTerm(T,P1,P2,dT)
h=integral(@(p) arrayfun(@(x) pressureIntegrand(T,x,dT),p),P1,P2, ...
    'RelTol',1e-8,'AbsTol',1e-5);
end
function a=pressureIntegrand(T,P,dT)
[~,~,rho]=HeXe_property_simulink(T,P);
[~,~,rhoP]=HeXe_property_simulink(T+dT,P);
[~,~,rhoM]=HeXe_property_simulink(T-dT,P);
a=1/rho-T*((1/rhoP-1/rhoM)/(2*dT));
end
function hash=hashFile(file)
[status,text]=system("shasum -a 256 '"+replace(string(file),"'","'\''")+"'");
assert(status==0); tokens=split(strtrim(string(text))); hash=tokens(1);
end
