function [Tout, cpbar] = reactor_li_enthalpy_outlet(Tin, Tf, mdot, hA)
% Exploratory warm-heating outlet closure, not a formal model dependency.
% Same heat-transfer mean temperature; only the Li enthalpy convention changes.
values=[Tin,Tf,mdot,hA];
if ~(isscalar(Tin)&&isscalar(Tf)&&isscalar(mdot)&&isscalar(hA) && ...
        isnumeric(values)&&isreal(values)&&all(isfinite(values)) && ...
        Tin>=453.7&&Tin<=1608&&Tf>=Tin&&mdot>0&&hA>0)
    error('steady53:LiOutletInput','Outside the tested warm-heating input domain.');
end
if Tf==Tin
    Tout=Tin; cpbar=Lithium_property_simulink(Tin,0.234e6); return
end
upper=min(Tf,1608);
residual=@(T) mdot*enthalpyIncrement(Tin,T)-hA*(Tf-(Tin+T)/2);
if residual(upper)<0
    error('steady53:LiOutletNoRoot','No outlet root within the active Li property domain.');
end
[Tout,err,flag]=fzero(residual,[Tin,upper],optimset('TolX',1e-11,'Display','off'));
if flag<=0 || abs(err)>.001 || Tout<Tin || Tout>upper
    error('steady53:LiOutletSolve','The candidate outlet equation did not close.');
end
cpbar=enthalpyIncrement(Tin,Tout)/(Tout-Tin);
end

function deltaH=enthalpyIncrement(Tin,Tout)
if Tin==Tout, deltaH=0; return; end
% Numerical integration choice, not a fitted physical coefficient. Calling
% the protected source function retains all current correlations and guards.
deltaH=integral(@(T) arrayfun(@(x) Lithium_property_simulink(x,0.234e6),T), ...
    Tin,Tout,'AbsTol',1e-6,'RelTol',1e-10);
end
