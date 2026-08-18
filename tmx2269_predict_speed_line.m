function [flowOut, valueOut, metadata] = tmx2269_predict_speed_line( ...
    flow100, value100, targetSpeedRatio, quantity)
%TMX2269_PREDICT_SPEED_LINE Apply the audited constant-phi similarity rule.
%
% Values below 100% are exposed only for the 90% leave-one-out validation.
% Production maps must use the measured TM X-2269 lines below 100% speed.

if ~(isnumeric(flow100) && isnumeric(value100) && ...
        isequal(size(flow100), size(value100)))
    error('tmx2269:SizeMismatch', ...
        'Flow and value arrays must be numeric and have identical sizes.');
end
if isempty(flow100) || any(~isfinite(flow100), 'all') || ...
        any(~isfinite(value100), 'all') || any(flow100 <= 0, 'all')
    error('tmx2269:InvalidLineData', ...
        'Speed-line coordinates and values must be finite and flow-positive.');
end
if ~(isnumeric(targetSpeedRatio) && isscalar(targetSpeedRatio) && ...
        isfinite(targetSpeedRatio))
    error('tmx2269:InvalidSpeedRatio', ...
        'Target speed ratio must be one finite numeric scalar.');
end

quantity = string(quantity);
if ~isscalar(quantity) || ...
        ~any(quantity == ["pressure_ratio", "efficiency"])
    error('tmx2269:UnsupportedQuantity', ...
        'Quantity must be pressure_ratio or efficiency.');
end
if targetSpeedRatio < 0.9 || targetSpeedRatio > 1.10
    error('tmx2269:SpeedOutsideAuditedDomain', ...
        'Audited prediction domain is 0.9 <= speed ratio <= 1.10.');
end

metadata.source_report = 'NASA TM X-2269';
metadata.calibration_source = [ ...
    'NASA TM X-2269 measured 100% speed line and similarity law only'];
metadata.base_speed_ratio = 1.0;
metadata.target_speed_ratio = targetSpeedRatio;
metadata.gamma_source = 5 / 3;
metadata.head_exponent = 2 / 5;

if targetSpeedRatio == 1
    flowOut = flow100;
    valueOut = value100;
    metadata.source_type = 'measurement';
    metadata.model_use_approved = true;
    metadata.formula = 'identity at the measured 100% speed line';
    return;
end

flowOut = targetSpeedRatio * flow100;
if quantity == "pressure_ratio"
    if any(value100 < 1, 'all')
        error('tmx2269:InvalidPressureRatio', ...
            'Pressure-ratio source values must be at least one.');
    end
    a = metadata.head_exponent;
    valueOut = (1 + targetSpeedRatio^2 * ...
        (value100.^a - 1)).^(1 / a);
    metadata.formula = ...
        'PR_s=(1+s^2*(PR_100^(2/5)-1))^(5/2)';
else
    if any(value100 <= 0 | value100 > 1, 'all')
        error('tmx2269:InvalidEfficiency', ...
            'Efficiency source values must lie in (0,1].');
    end
    valueOut = value100;
    metadata.formula = 'eta_s=eta_100';
end

if targetSpeedRatio < 1
    metadata.source_type = 'validation_prediction';
    metadata.model_use_approved = false;
else
    metadata.source_type = 'similarity_prediction';
    metadata.model_use_approved = true;
end
end
