
function out = prop_material(T,material,prop)
switch material
    case 'NaK'  % NaK
        switch prop
            case 'rho'
                out = 1*(938.399-0.215438*T-1.71386e-5*T^2); %kg/m^3 密度         
            case 'cp'
                out = 1000*(1.061-3.694e-4*T+4.615e-8*T^2+1.509e-10*T^3);   %J/kgK 比热
            case 'lambda'
                out = 1*(15.0006+3.02877e-2*T-2.08095e-5*T^2); %W/mK 导热系数
            case 'T' %由焓值计算温度
                out = 1*(142.54+1.13064*T*0.001); %K 温度
            case 'Vis' %由温度计算黏性系数
                out = 1*(0.0016363-4.58259e-6*T+4.94085e-9*T^2-1.84513e-12*T^3); %m2/s 黏性系数
            otherwise
                warning('PropErro')
        end
end
end