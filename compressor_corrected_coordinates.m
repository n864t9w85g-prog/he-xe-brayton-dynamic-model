function [speedRatio, flowRatio] = compressor_corrected_coordinates( ...
    N_rpm, mdot_kg_s, T_in_K, P_in_Pa, target)
%COMPRESSOR_CORRECTED_COORDINATES Normalize NASA corrected map coordinates.

temperatureRatio = T_in_K / target.T_design_K;
pressureRatio = P_in_Pa / target.P_design_Pa;
speedRatio = (N_rpm / target.N_design_rpm) / sqrt(temperatureRatio);
flowRatio = (mdot_kg_s / target.mdot_model_kg_s) * ...
    sqrt(temperatureRatio) / pressureRatio;
end
