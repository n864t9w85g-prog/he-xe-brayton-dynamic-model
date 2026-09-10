% Offline regression gate; no SLX is loaded or simulated.
repo=string(fileparts(fileparts(mfilename('fullpath'))));
source=fullfile(repo,'tmp','steady53_curves_20260828','source_f8bcd83');
addpath(fullfile(repo,'tests'),source);
dest=string(tempname(fullfile(repo,'tmp'))); mkdir(dest);
diary(fullfile(dest,'diary.txt')); fprintf('OFFLINE_TEST_DIR=%s\n',dest);
assert(isfile(fullfile(repo,'tests','reactor_li_enthalpy_outlet.m')), ...
    'Missing candidate enthalpy-outlet implementation.');
assert(string(which('Lithium_property_simulink'))==fullfile(source,'Lithium_property_simulink.m'));
hA=.2906/2.246e-5; mdot=4.572;
points=[1441.281053243832,1724.8735284013458;1443.27,1722; ...
    460,600;900,1200;1500,1690;1000,1000];
rows=zeros(size(points,1),8);
for k=1:size(points,1)
    ti=points(k,1); tf=points(k,2);
    old=ti+2*hA*(tf-ti)/(2*mdot*4111+hA);
    [to,cpbar]=reactor_li_enthalpy_outlet(ti,tf,mdot,hA);
    % Independent primitive of the protected active cp polynomial.
    F=@(T) .9615*1000*(-104400./T-135.1*log(T)+4.180*T);
    q=mdot*(F(to)-F(ti)); qf=hA*(tf-(ti+to)/2);
    assert(to>=ti && to<=min(tf,1608));
    assert(abs(q-qf)<.001,'Candidate enthalpy balance failed.');
    assert(abs(mdot*cpbar*(to-ti)-q)<.001);
    rows(k,:)=[ti,tf,old,to,cpbar,q,qf,q-qf];
end
assert(abs(rows(1,6)-hA*(points(1,2)-(points(1,1)+rows(1,3))/2))>1e4);
expectError(@() reactor_li_enthalpy_outlet(400,1722,mdot,hA),'steady53:LiOutletInput');
expectError(@() reactor_li_enthalpy_outlet(1443,1722,0,hA),'steady53:LiOutletInput');
expectError(@() reactor_li_enthalpy_outlet(1450,1800,mdot,1e8),'steady53:LiOutletNoRoot');
expectError(@() reactor_li_enthalpy_outlet(1500,1750,mdot,hA),'steady53:LiOutletNoRoot');
expectError(@() reactor_li_enthalpy_outlet(1000,900,mdot,hA),'steady53:LiOutletInput');
t=array2table(rows,VariableNames={'Tin_K','Tf_K','old_Tout_K','new_Tout_K','cpbar_J_kgK','Qboundary_W','Qfuel_W','residual_W'});
writetable(t,fullfile(dest,'offline_points.csv')); disp(t);
fprintf('OFFLINE_ENTHALPY_TESTS_PASS_NO_SLX_LOADED\n'); diary off;

function expectError(fun,id)
caught=false;
try, fun(); catch e, assert(string(e.identifier)==id,e.message); caught=true; end
assert(caught,'Expected invalid-input/domain rejection.');
end
