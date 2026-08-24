function report = evaluate_steady53(t, signals, audit, s)
%EVALUATE_STEADY53 Evaluate nominal section 5.3.1 steady-state acceptance.

arguments
    t (:, 1) double
    signals (1, 1) struct
    audit (1, 1) struct
    s (1, 1) struct
end

failures = strings(0, 1);

if isempty(t) || ~isfinite(t(end)) || t(end) ~= 14000
    failures(end + 1, 1) = "time:not_14000";
end

windowMask = t >= s.finalWindow_s(1) & t <= s.finalWindow_s(2);
if ~any(windowMask)
    failures(end + 1, 1) = "time:no_final_window";
end

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
        elseif ~any(windowMask)
            rowFailures(end + 1, 1) = name + ":target"; %#ok<AGROW>
            rowFailures(end + 1, 1) = name + ":peak_to_peak"; %#ok<AGROW>
            rowFailures(end + 1, 1) = name + ":trend"; %#ok<AGROW>
        else
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
    metricPass(row) = isempty(rowFailures);
end

metrics = table(metricName, target, meanValue, relativeError, ...
    peakToPeakRel, trendRel, settlingTime_s, metricPass);

failures = [failures; auditFailures(audit, s)];
failures = unique(failures, "stable");

report = struct();
report.pass = isempty(failures);
report.failures = failures;
report.metrics = metrics;
report.audit = audit;
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

function failures = auditFailures(audit, s)
failures = strings(0, 1);

if isfield(audit, "warningIds")
    warningIds = string(audit.warningIds(:));
    warningIds = warningIds(~ismissing(warningIds) & strlength(warningIds) > 0);
    failures = [failures; "warning:" + warningIds];
end

if isfield(audit, "lookup")
    requiredFields = ["name", "inputMin", "inputMax", "bpMin", "bpMax"];
    for index = 1:numel(audit.lookup)
        lookup = audit.lookup(index);
        if all(isfield(lookup, requiredFields)) && ...
                (lookup.inputMin < lookup.bpMin || lookup.inputMax > lookup.bpMax)
            failures(end + 1, 1) = "lookup:" + string(lookup.name); %#ok<AGROW>
        end
    end
end

if ~isfield(audit, "property") || ...
        propertyRangeInvalid(audit.property, "HeXe_K", s.property.HeXe_K)
    failures(end + 1, 1) = "property:HeXe";
end
if ~isfield(audit, "property") || ...
        propertyRangeInvalid(audit.property, "Lithium_K", s.property.Lithium_K)
    failures(end + 1, 1) = "property:Lithium";
end

if ~isfield(audit, "massClosureRel") || ...
        ~isnumeric(audit.massClosureRel) || ...
        ~isscalar(audit.massClosureRel) || ...
        ~isreal(audit.massClosureRel) || ...
        ~isfinite(audit.massClosureRel) || ...
        audit.massClosureRel > s.massClosureTol
    failures(end + 1, 1) = "mass:closure";
end

if isfield(audit, "states")
    for index = 1:numel(audit.states)
        state = audit.states(index);
        path = string(state.path);
        fluid = string(state.fluid);
        data = state.data;

        invalid = ~isnumeric(data) || ~isreal(data) || any(~isfinite(data), "all");
        if invalid
            failures(end + 1, 1) = "state:invalid:" + path; %#ok<AGROW>
            continue
        end

        isTemperature = contains(path, "/T_") || contains(path, "T_rad_");
        if isTemperature && any(data <= 0, "all")
            failures(end + 1, 1) = "state:nonpositive:" + path; %#ok<AGROW>
        end

        if fluid == "HeXe" && ...
                (any(data < s.property.HeXe_K(1), "all") || ...
                 any(data > s.property.HeXe_K(2), "all"))
            failures(end + 1, 1) = "state:HeXe_domain:" + path; %#ok<AGROW>
        elseif fluid == "Lithium" && ...
                (any(data < s.property.Lithium_K(1), "all") || ...
                 any(data > s.property.Lithium_K(2), "all"))
            failures(end + 1, 1) = "state:Lithium_domain:" + path; %#ok<AGROW>
        end
    end
end

failures = unique(failures, "stable");
end

function invalid = propertyRangeInvalid(propertyAudit, fieldName, approvedRange)
if ~isfield(propertyAudit, fieldName)
    invalid = true;
    return
end

observedRange = propertyAudit.(fieldName);
invalid = ~isnumeric(observedRange) || numel(observedRange) ~= 2 || ...
    ~isreal(observedRange) || any(~isfinite(observedRange), "all") || ...
    observedRange(1) < approvedRange(1) || ...
    observedRange(2) > approvedRange(2);
end
