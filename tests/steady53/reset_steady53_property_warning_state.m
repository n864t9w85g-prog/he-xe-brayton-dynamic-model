function reset_steady53_property_warning_state()
%RESET_STEADY53_PROPERTY_WARNING_STATE Rearm diagnostic clamp warnings.
%   The two property functions retain only one-shot warning-suppression
%   latches in persistent variables. Clearing the functions resets those
%   diagnostic latches to their uninitialized state; it does not edit the
%   property correlations, clamp limits, model parameters, or saved files.

clear("HeXe_property_simulink", "Lithium_property_simulink");
end
