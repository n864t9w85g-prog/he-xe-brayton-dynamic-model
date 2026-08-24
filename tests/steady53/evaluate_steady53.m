function report = evaluate_steady53(t, signals, audit, s)
%EVALUATE_STEADY53 Evaluate nominal section 5.3.1 steady-state acceptance.

arguments
    t (:, 1) double
    signals (1, 1) struct
    audit (1, 1) struct
    s (1, 1) struct
end

failures = strings(0, 1);
[timeFailures, validTime, windowMask] = validateTimeAxis(t, s);
failures = [failures; timeFailures];

metricCount = height(s.metrics);
metricName = s.metrics.name;
target = s.metrics.target;
meanValue = nan(metricCount, 1);
relativeError = nan(metricCount, 1);
peakToPeakRel = nan(metricCount, 1);
trendRel = nan(metricCount, 1);
settlingTime_s = nan(metricCount, 1);
metricPass = false(metricCount, 1);

for row = 1:metricCount
    name = metricName(row);
    rowFailures = strings(0, 1);

    if ~isfield(signals, name)
        rowFailures(end + 1, 1) = name + ":missing"; %#ok<AGROW>
    else
        values = signals.(name);
        if numel(values) ~= numel(t)
            rowFailures(end + 1, 1) = name + ":length"; %#ok<AGROW>
        elseif ~isreal(values)
            rowFailures(end + 1, 1) = name + ":complex"; %#ok<AGROW>
        elseif any(~isfinite(values), "all")
            rowFailures(end + 1, 1) = name + ":nonfinite"; %#ok<AGROW>
        elseif validTime
            values = values(:);
            windowValues = values(windowMask);
            windowTime = t(windowMask);
            normalizer = abs(target(row));

            meanValue(row) = mean(windowValues);
            relativeError(row) = abs(meanValue(row) - target(row)) / normalizer;
            peakToPeakRel(row) = ...
                (max(windowValues) - min(windowValues)) / normalizer;

            if numel(windowTime) < 2 || range(windowTime) == 0
                rowFailures(end + 1, 1) = name + ":trend"; %#ok<AGROW>
            else
                fitCoefficients = polyfit(windowTime, windowValues, 1);
                trendRel(row) = abs(fitCoefficients(1)) * ...
                    diff(s.finalWindow_s) / normalizer;
                if trendRel(row) > s.windowTrendTol
                    rowFailures(end + 1, 1) = name + ":trend"; %#ok<AGROW>
                end
            end

            if relativeError(row) > s.metrics.relTol(row)
                rowFailures(end + 1, 1) = name + ":target"; %#ok<AGROW>
            end
            if peakToPeakRel(row) > s.windowPeakToPeakTol
                rowFailures(end + 1, 1) = name + ":peak_to_peak"; %#ok<AGROW>
            end

            withinTargetBand = abs(values - target(row)) / normalizer <= ...
                s.metrics.relTol(row);
            settlingTime_s(row) = permanentSettlingTime(t, withinTargetBand);
            deadline = s.metrics.settleDeadline_s(row);
            if isfinite(deadline) && settlingTime_s(row) > deadline
                rowFailures(end + 1, 1) = name + ":settling"; %#ok<AGROW>
            end
        end
    end

    rowFailures = unique(rowFailures, "stable");
    failures = [failures; rowFailures]; %#ok<AGROW>
    metricPass(row) = validTime && isempty(rowFailures);
end

metrics = table(metricName, target, meanValue, relativeError, ...
    peakToPeakRel, trendRel, settlingTime_s, metricPass);

failures = [failures; auditFailures(audit, s, t, windowMask, validTime)];
failures = unique(failures, "stable");

report = struct();
report.pass = isempty(failures);
report.failures = failures;
report.metrics = metrics;
report.audit = audit;
end

function [failures, valid, windowMask] = validateTimeAxis(t, s)
failures = strings(0, 1);
windowMask = false(size(t));

invalid = isempty(t) || ~isreal(t) || any(~isfinite(t), "all");
if ~invalid
    invalid = any(diff(t) <= 0) || t(1) > s.finalWindow_s(1);
end

wrongStop = isempty(t) || ~isreal(t(end)) || ~isfinite(t(end)) || ...
    t(end) ~= s.stopTime_s;
if wrongStop
    failures(end + 1, 1) = "time:not_stop_time";
end

if ~invalid
    windowMask = t >= s.finalWindow_s(1) & t <= s.finalWindow_s(2);
    invalid = nnz(windowMask) < 2;
end

if invalid
    failures(end + 1, 1) = "time:invalid";
end
valid = ~invalid && ~wrongStop;
end

function settlingTime_s = permanentSettlingTime(t, withinTargetBand)
lastOutside = find(~withinTargetBand, 1, "last");
if isempty(lastOutside)
    if isempty(t)
        settlingTime_s = Inf;
    else
        settlingTime_s = t(1);
    end
elseif lastOutside == numel(t)
    settlingTime_s = Inf;
else
    settlingTime_s = t(lastOutside + 1);
end
end

function failures = auditFailures(audit, s, t, windowMask, validTime)
failures = strings(0, 1);

requiredAuditFields = ["warningIds", "lookup", "property", ...
    "massClosureRel", "states"];
for field = requiredAuditFields
    if ~isfield(audit, field)
        failures(end + 1, 1) = "audit:missing:" + field; %#ok<AGROW>
    end
end

if isfield(audit, "warningIds")
    % warningIds is runner-prefiltered property-clamp IDs, not all warnings.
    [validWarningIds, warningIds] = normalizeWarningIds(audit.warningIds);
    if validWarningIds
        failures = [failures; "warning:" + warningIds];
    else
        failures(end + 1, 1) = "audit:invalid:warningIds";
    end
end

if isfield(audit, "lookup")
    failures = [failures; lookupFailures(audit.lookup)];
end

if ~isfield(audit, "property") || ...
        fluidPropertyInvalid(audit.property, ...
        "HeXeMin_K", "HeXeMax_K", s.property.HeXe_K)
    failures(end + 1, 1) = "property:HeXe";
end
if ~isfield(audit, "property") || ...
        fluidPropertyInvalid(audit.property, ...
        "LithiumMin_K", "LithiumMax_K", s.property.Lithium_K)
    failures(end + 1, 1) = "property:Lithium";
end
% Lithium saturation-pressure coverage awaits runner propertyAudit data;
% this evaluator intentionally assumes no pressure constant or correlation.

if ~isfield(audit, "massClosureRel") || ...
        ~isnumeric(audit.massClosureRel) || ...
        ~isscalar(audit.massClosureRel) || ...
        ~isreal(audit.massClosureRel) || ...
        ~isfinite(audit.massClosureRel) || ...
        audit.massClosureRel < 0 || ...
        audit.massClosureRel > s.massClosureTol
    failures(end + 1, 1) = "mass:closure";
end

if isfield(audit, "states")
    failures = [failures; stateFailures( ...
        audit.states, s, t, windowMask, validTime)];
end

failures = unique(failures, "stable");
end

function [valid, warningIds] = normalizeWarningIds(value)
valid = true;
warningIds = strings(0, 1);

if isstring(value)
    warningIds = value(:);
elseif ischar(value)
    if isempty(value)
        return
    end
    warningIds = string(cellstr(value));
elseif iscellstr(value)
    warningIds = string(value(:));
else
    valid = false;
    return
end

valid = all(~ismissing(warningIds) & strlength(warningIds) > 0);
if ~valid
    warningIds = strings(0, 1);
end
end

function failures = lookupFailures(lookups)
failures = strings(0, 1);
requiredFields = ["name", "inputMin", "inputMax", "bpMin", "bpMax"];

if ~isstruct(lookups)
    failures(end + 1, 1) = "audit:invalid:lookup";
    return
end
if ~all(isfield(lookups, requiredFields)) && isempty(lookups)
    failures(end + 1, 1) = "lookup:invalid:1";
    return
end

for index = 1:numel(lookups)
    lookup = lookups(index);
    label = auditEntryLabel(lookup, "name", index);
    if ~all(isfield(lookup, requiredFields)) || ...
            ~validTextScalar(lookup.name) || ...
            ~validFiniteScalar(lookup.inputMin) || ...
            ~validFiniteScalar(lookup.inputMax) || ...
            ~validFiniteScalar(lookup.bpMin) || ...
            ~validFiniteScalar(lookup.bpMax) || ...
            lookup.inputMin > lookup.inputMax || ...
            lookup.bpMin > lookup.bpMax
        failures(end + 1, 1) = "lookup:invalid:" + label; %#ok<AGROW>
        continue
    end

    if lookup.inputMin < lookup.bpMin || lookup.inputMax > lookup.bpMax
        failures(end + 1, 1) = "lookup:" + string(lookup.name); %#ok<AGROW>
    end
end
end

function failures = stateFailures(states, s, t, windowMask, validTime)
failures = strings(0, 1);
requiredFields = ["path", "fluid", "data"];
allowedFluids = ["HeXe", "Lithium", "none"];
allowedKinds = ["temperature", "pressure", "power", "massFlow", ...
    "speed", "dimensionless", "other"];

if ~isstruct(states)
    failures(end + 1, 1) = "audit:invalid:states";
    return
end
if ~all(isfield(states, requiredFields)) && isempty(states)
    failures(end + 1, 1) = "state:invalid:1";
    return
end

for index = 1:numel(states)
    state = states(index);
    path = auditEntryLabel(state, "path", index);
    if ~all(isfield(state, requiredFields)) || ...
            ~validTextScalar(state.path) || ...
            ~validTextScalar(state.fluid) || ...
            ~isnumeric(state.data) || isempty(state.data) || ...
            numel(state.data) ~= numel(t) || ...
            ~isreal(state.data) || any(~isfinite(state.data), "all")
        failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
        continue
    end

    fluid = string(state.fluid);
    if ~any(fluid == allowedFluids)
        failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
        continue
    end

    if isfield(state, "kind")
        if ~validTextScalar(state.kind) || ...
                ~any(string(state.kind) == allowedKinds)
            failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
            continue
        end
        kind = string(state.kind);
    else
        kind = inferredStateKind(path, fluid);
    end

    if fluid ~= "none" && kind ~= "temperature"
        failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
        continue
    end

    nonnegative = false;
    if isfield(state, "nonnegative")
        if ~islogical(state.nonnegative) || ~isscalar(state.nonnegative)
            failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
            continue
        end
        nonnegative = state.nonnegative;
    end

    data = state.data(:);
    if nonnegative && any(data < 0)
        failures(end + 1, 1) = "state:negative:" + path; %#ok<AGROW>
    end

    if kind == "temperature" && any(data <= 0)
        failures(end + 1, 1) = "state:nonpositive:" + path; %#ok<AGROW>
    end

    if kind == "temperature" && fluid == "HeXe" && ...
            (any(data < s.property.HeXe_K(1)) || ...
             any(data > s.property.HeXe_K(2)))
        failures(end + 1, 1) = "state:HeXe_domain:" + path; %#ok<AGROW>
    elseif kind == "temperature" && fluid == "Lithium" && ...
            (any(data < s.property.Lithium_K(1)) || ...
             any(data > s.property.Lithium_K(2)))
        failures(end + 1, 1) = "state:Lithium_domain:" + path; %#ok<AGROW>
    end

    if validTime
        windowData = data(windowMask);
        windowTime = t(windowMask);
        normalizer = max(abs(mean(windowData)), stateScaleFloor(kind, s));
        peakToPeakRel = (max(windowData) - min(windowData)) / normalizer;
        fitCoefficients = polyfit(windowTime, windowData, 1);
        trendRel = abs(fitCoefficients(1)) * ...
            diff(s.finalWindow_s) / normalizer;

        if peakToPeakRel > s.windowPeakToPeakTol
            failures(end + 1, 1) = ...
                "state:peak_to_peak:" + path; %#ok<AGROW>
        end
        if trendRel > s.windowTrendTol
            failures(end + 1, 1) = "state:trend:" + path; %#ok<AGROW>
        end
    end
end
end

function kind = inferredStateKind(path, fluid)
if fluid == "HeXe" || fluid == "Lithium"
    kind = "temperature";
    return
end

lowerPath = lower(path);
if contains(lowerPath, "/t_") || contains(lowerPath, "t_rad_") || ...
        contains(lowerPath, "temperature")
    kind = "temperature";
elseif contains(lowerPath, "/p_") || contains(lowerPath, "pressure")
    kind = "pressure";
elseif contains(lowerPath, "power")
    kind = "power";
elseif contains(lowerPath, "massflow") || contains(lowerPath, "mass_flow")
    kind = "massFlow";
elseif contains(lowerPath, "speed") || contains(lowerPath, "rpm")
    kind = "speed";
else
    kind = "other";
end
end

function scaleFloor = stateScaleFloor(kind, s)
switch kind
    case "temperature"
        scaleFloor = s.scale.temperature_K;
    case "pressure"
        scaleFloor = s.scale.pressure_Pa;
    case "power"
        scaleFloor = s.scale.power_W;
    case "massFlow"
        scaleFloor = s.scale.massFlow_kg_s;
    case "speed"
        scaleFloor = s.scale.speed_rpm;
    otherwise
        scaleFloor = s.scale.other;
end
end

function label = auditEntryLabel(entry, fieldName, index)
label = string(index);
if isfield(entry, fieldName) && validTextScalar(entry.(fieldName))
    label = string(entry.(fieldName));
end
end

function valid = validTextScalar(value)
valid = (isstring(value) && isscalar(value) && ...
    ~ismissing(value) && strlength(value) > 0) || ...
    (ischar(value) && isrow(value) && ~isempty(value));
end

function valid = validFiniteScalar(value)
valid = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
end

function invalid = fluidPropertyInvalid(propertyAudit, minField, maxField, ...
        approvedRange)
if ~isstruct(propertyAudit) || ~isscalar(propertyAudit) || ...
        ~isfield(propertyAudit, minField) || ...
        ~isfield(propertyAudit, maxField)
    invalid = true;
    return
end

observedMin = propertyAudit.(minField);
observedMax = propertyAudit.(maxField);
invalid = ~validFiniteScalar(observedMin) || ...
    ~validFiniteScalar(observedMax) || ...
    observedMin > observedMax || ...
    observedMin < approvedRange(1) || ...
    observedMax > approvedRange(2);
end
