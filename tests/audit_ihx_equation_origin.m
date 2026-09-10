function audit_ihx_equation_origin
% Read-only scalar audit of inherited h constants and thesis mean states.
% NO load_system, sim, start.m, source writes, candidate SLX, or fitted values.
repo = string(fileparts(fileparts(mfilename('fullpath'))));
source = fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
oldDir = pwd; oldPath = path;
restore = onCleanup(@() restoreEnvironment(oldDir,oldPath)); %#ok<NASGU>
out = string(tempname(fullfile(repo,'tmp'))); mkdir(out);
diary(fullfile(out,'diary.txt')); diaryGuard = onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('OUTPUT_DIR=%s\n',out);
cd(source); addpath(source);
files = [fullfile(source,'Lithium_property_simulink.m'); fullfile(source,'HeXe_property_simulink.m')];
expected = ["666a3a9d7bcb45e0e80afca4bd30e02bd19098ce72cc56bfe9a5f528c67b4c4f"; ...
            "2490785cba7ae3d1f9bb4d4e52621f7b925945aab0f4f93e1a71b504783f5cf2"];
for k=1:2, assert(fileHash(files(k))==expected(k)); end
assert(string(which('Lithium_property_simulink'))==files(1));
assert(string(which('HeXe_property_simulink'))==files(2));
% This does not disable the formal functions' domain protections.
warning('error','Lithium_property_simulink:TemperatureBelowRange');
warning('error','Lithium_property_simulink:TemperatureAboveRange');
warning('error','HeXe_property_simulink:TemperatureBelowRange');
warning('error','HeXe_property_simulink:TemperatureAboveRange');
clear Lithium_property_simulink HeXe_property_simulink

% Reproduce the IHX-only arithmetic in historical table51_consistency.m.
% Geometry/flow choices are inherited assumptions, not newly approved data.
A=14.062; V=0.00651; L=0.0585; mdotH=4.572; mdotC=11.97;
hh=10544; hc=1171.6; mh=2*.6588; mc=2*.00919; mw=325;
d=4*V/A; flowArea=(V/2)/L;
Th=(1600+1443.27)/2; Tc=(1100.91+1522.96)/2;
[cph,~,rhoh,muh,kh,Prh]=Lithium_property_simulink(Th,.234e6);
pressureCases=[1.547e6,1.543e6]; sourceChecks=struct([]);
for k=1:2
    [cpc,~,rhoc,muc,kc,Prc]=HeXe_property_simulink(Tc,pressureCases(k));
    ReH=mdotH/flowArea*d/muh; ReC=mdotC/flowArea*d/muc;
    NuC=.022*ReC^.8*Prc^.43;
    s=struct('P_c_Pa',pressureCases(k),'T_h_mean_K',Th,'T_c_mean_K',Tc, ...
        'diameter_m',d,'flow_area_per_side_m2',flowArea, ...
        'cp_h_J_kgK',cph,'cp_c_J_kgK',cpc,'rho_h',rhoh,'rho_c',rhoc, ...
        'mu_h_Pa_s',muh,'mu_c_Pa_s',muc,'k_h_W_mK',kh,'k_c_W_mK',kc, ...
        'Pr_h',Prh,'Pr_c',Prc,'Re_h',ReH,'Re_c',ReC, ...
        'Nu_c_Mikheev',NuC,'h_c_Mikheev_W_m2K',NuC*kc/d, ...
        'h_h_legacy_Nu6_estimate_W_m2K',6*kh/d, ...
        'Nu_implied_by_active_h_h',hh*d/kh, ...
        'Nu_implied_by_active_h_c',hc*d/kc);
    if k==1, sourceChecks=s; else, sourceChecks(k)=s; end
end

% Published Eq.5.12-5.14 and Tbar=(Tin+Tout)/2. Fixed external inputs only.
% A consistent 1200-K outlet/wall start DOES NOT imply 1200-K mean states.
Thi=1600; Tci=1100.91; Tho=1200; Tco=1200; Tw=1200;
Hh=hh*A; Hc=hc*A;
cpH0=Lithium_property_simulink((Thi+Tho)/2,.234e6);
cpC0=HeXe_property_simulink((Tci+Tco)/2,1.543e6);
Qh=Hh*((Thi+Tho)/2-Tw); Qc=Hc*(Tw-(Tci+Tco)/2);
hotAdv=mdotH*cpH0*(Thi-Tho); coldAdv=mdotC*cpC0*(Tci-Tco);
dMeanH=(hotAdv-Qh)/(mh*cpH0); dMeanC=(coldAdv+Qc)/(mc*cpC0);
% Wall cp taken from the unchanged lookup at 1200 K, not a new correlation.
wallCp0=636+(662-636)*(1200-1173.15)/(1273.15-1173.15);
dWall=(Qh-Qc)/(mw*wallCp0);
initial=struct('T_hi_K',Thi,'T_ci_K',Tci,'T_ho_K',Tho,'T_co_K',Tco,'T_wall_K',Tw, ...
    'required_hot_mean_K',(Thi+Tho)/2,'required_cold_mean_K',(Tci+Tco)/2, ...
    'hot_out_if_mean_were1200_K',2*1200-Thi,'cold_out_if_mean_were1200_K',2*1200-Tci, ...
    'cp_h_J_kgK',cpH0,'cp_c_J_kgK',cpC0,'wall_cp_J_kgK',wallCp0, ...
    'hot_advection_W',hotAdv,'cold_advection_W',coldAdv,'hot_to_wall_W',Qh,'wall_to_cold_W',Qc, ...
    'hot_out_derivative_K_s',2*dMeanH,'cold_out_derivative_K_s',2*dMeanC, ...
    'wall_derivative_K_s',dWall);
% Independently rearranged hot-outlet equation must give the same derivative.
directHot=(2*mdotH*cpH0*(Thi-Tho)-Hh*(Thi+Tho-2*Tw))/(mh*cpH0);
assert(abs(directHot-initial.hot_out_derivative_K_s)<1e-8);
assert(abs(mh*cpH0*dMeanH+mc*cpC0*dMeanC+mw*wallCp0*dWall-hotAdv-coldAdv)<1e-7);

% Uniform-point input coupling, exact linearization because all heat-flow
% differences vanish at equilibrium; cp derivative terms then contribute zero.
cpUniform=Lithium_property_simulink(1200,.234e6);
coupling=struct([]);
for numberOfRegions=[1,2]
    regionA=A/numberOfRegions; regionM=mh/numberOfRegions;
    C=mdotH*cpUniform; H=hh*regionA;
    gain=(2*C-H)/(regionM*cpUniform);
    s=struct('region_count',numberOfRegions,'area_per_region_m2',regionA, ...
        'hot_mass_per_region_kg',regionM,'cp_uniform_J_kgK',cpUniform, ...
        'H_over_2C',H/(2*C),'hot_input_to_outlet_derivative_coupling_per_s',gain);
    if numberOfRegions==1, coupling=s; else, coupling(numberOfRegions)=s; end
end

% Frozen-property algebraic equilibrium of the literal whole-component
% equations; NOT a variable-property simulation or a replacement boundary.
C_H=mdotH*cph; C_C=mdotC*sourceChecks(2).cp_c_J_kgK;
Q=(Thi-Tci)/(1/Hh+1/Hc+1/(2*C_H)+1/(2*C_C));
ThoEq=Thi-Q/C_H; TcoEq=Tci+Q/C_C; TwEq=(Thi+ThoEq)/2-Q/Hh;
res=[C_H*(Thi-ThoEq)-Hh*((Thi+ThoEq)/2-TwEq), ...
     C_C*(Tci-TcoEq)+Hc*(TwEq-(Tci+TcoEq)/2), ...
     Hh*((Thi+ThoEq)/2-TwEq)-Hc*(TwEq-(Tci+TcoEq)/2)];
assert(max(abs(res))<1e-6);
frozen=struct('Q_W',Q,'T_ho_K',ThoEq,'T_co_K',TcoEq,'T_wall_K',TwEq, ...
    'residuals_W',res,'cp_hot_frozen_J_kgK',cph,'cp_cold_frozen_J_kgK',sourceChecks(2).cp_c_J_kgK);

result=struct('scope','Scalar offline audit. No ODE integration or SLX load/simulation. No parameter applied.', ...
    'source_property_hashes',expected,'source_checks',sourceChecks, ...
    'consistent_outlet1200_initial_derivatives',initial,'uniform_input_coupling',coupling, ...
    'frozen_property_whole_component_equilibrium',frozen, ...
    'limits',{{'Historical geometry and flows are assumptions, not recovered author inputs.', ...
    'Nu=6 is the historical script estimate, not a validated lithium correlation.', ...
    'One-region and two-region interpretation are separate from the mean-state definition.', ...
    'Input derivatives apply to fixed inlets; moving internal interfaces require dTin/dt.', ...
    'Frozen-cp equilibrium is an algebraic diagnostic, not a simulated result or thesis acceptance.'}});
for k=1:2, assert(fileHash(files(k))==expected(k)); end
fid=fopen(fullfile(out,'audit.json'),'w'); assert(fid~=-1);
fprintf(fid,'%s\n',jsonencode(result,PrettyPrint=true)); fclose(fid);
save(fullfile(out,'audit.mat'),'result');
disp(jsonencode(result,PrettyPrint=true));
fprintf('IHX_SCALAR_AUDIT_COMPLETE_NO_SLX_OR_ODE_RUN\n');
end

function h=fileHash(p)
[s,t]=system("shasum -a 256 '"+replace(string(p),"'","'\''")+"'");
assert(s==0); v=split(strtrim(string(t))); h=v(1);
end

function restoreEnvironment(folder,savedPath)
cd(folder); path(savedPath);
end
