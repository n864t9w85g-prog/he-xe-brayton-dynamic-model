function result = run_final_steady_reachability( ...
        modelPath, stopTime_s, logSignals)
%RUN_FINAL_STEADY_REACHABILITY Acceptance entry with runner ownership rules.
%   Model ownership is delegated entirely to run_steady53_case. In
%   particular, a preloaded model is rejected and is never closed, saved,
%   or modified by this entry point.

arguments
    modelPath {mustBeTextScalar}
    stopTime_s (1, 1) double {mustBePositive, mustBeFinite}
    logSignals (1, 1) logical = false
end

result = run_steady53_case(modelPath, stopTime_s, logSignals);
end
