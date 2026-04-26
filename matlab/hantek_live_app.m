function fig = hantek_live_app(varargin)
%HANTEK_LIVE_APP Simple MATLAB control panel for live USB acquisition.
%
% The app captures real USB blocks through hantek_acquire("usb"), updates
% waveform/FFT plots, and exposes the basic controls needed for bench work.

p = inputParser;
addParameter(p, "channel", 1, @(x) isnumeric(x) && isscalar(x) && any(x == [1 2]));
addParameter(p, "sampleRate", 1e6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "nSamples", 20000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "voltsPerDiv", 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "fftMaxHz", 10000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "timeStartMs", 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, "timeWindowMs", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "verticalCenter", 0.0, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "verticalSpan", 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "triggerEnabled", true, @(x) islogical(x) && isscalar(x));
addParameter(p, "triggerSlope", "rising", @(x) ischar(x) || isstring(x));
addParameter(p, "triggerLevel", NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "triggerPositionPercent", 20.0, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);
addParameter(p, "refreshPeriod", 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "projectRoot", default_project_root(), @(x) ischar(x) || isstring(x));
addParameter(p, "applyCalibration", false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, "calibrationPath", fullfile(default_project_root(), "data", "software_calibration.json"), @(x) ischar(x) || isstring(x));
addParameter(p, "debugEcho", false, @(x) islogical(x) && isscalar(x));
addParameter(p, "maxFailures", 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
parse(p, varargin{:});
defaults = p.Results;

fig = figure( ...
    "Name", "Hantek 6022BE USB Live", ...
    "NumberTitle", "off", ...
    "Color", "w", ...
    "MenuBar", "none", ...
    "ToolBar", "figure", ...
    "Units", "pixels", ...
    "Position", [80 80 1220 720], ...
    "CloseRequestFcn", @on_close);

panel = uipanel( ...
    "Parent", fig, ...
    "Title", "Acquisition", ...
    "Units", "normalized", ...
    "Position", [0.015 0.04 0.22 0.92]);

viewPanel = uipanel( ...
    "Parent", fig, ...
    "Title", "View", ...
    "Units", "normalized", ...
    "Position", [0.30 0.925 0.67 0.065]);

axTime = axes( ...
    "Parent", fig, ...
    "Units", "normalized", ...
    "Position", [0.30 0.56 0.67 0.32]);
timeLine = plot(axTime, nan, nan, "LineWidth", 1.1);
grid(axTime, "on");
xlabel(axTime, "Time (ms)");
ylabel(axTime, "Voltage (V)");
title(axTime, "Ready");

axFft = axes( ...
    "Parent", fig, ...
    "Units", "normalized", ...
    "Position", [0.30 0.10 0.67 0.32]);
fftLine = plot(axFft, nan, nan, "LineWidth", 1.1);
grid(axFft, "on");
xlabel(axFft, "Frequency (Hz)");
ylabel(axFft, "Magnitude (V)");
title(axFft, "FFT");
xlim(axFft, [0 double(defaults.fftMaxHz)]);

autoTimeCheckbox = uicontrol( ...
    "Parent", viewPanel, ...
    "Style", "checkbox", ...
    "Units", "normalized", ...
    "Position", [0.015 0.18 0.09 0.58], ...
    "String", "Auto T", ...
    "Value", 0, ...
    "BackgroundColor", get(viewPanel, "BackgroundColor"));
view_label(viewPanel, "Start ms", [0.115 0.58 0.09 0.30]);
timeStartEdit = view_editbox(viewPanel, sprintf("%.4g", defaults.timeStartMs), [0.115 0.14 0.09 0.42]);
view_label(viewPanel, "Window ms", [0.215 0.58 0.10 0.30]);
timeWindowEdit = view_editbox(viewPanel, sprintf("%.4g", defaults.timeWindowMs), [0.215 0.14 0.10 0.42]);

autoVoltageCheckbox = uicontrol( ...
    "Parent", viewPanel, ...
    "Style", "checkbox", ...
    "Units", "normalized", ...
    "Position", [0.345 0.18 0.09 0.58], ...
    "String", "Auto V", ...
    "Value", 0, ...
    "BackgroundColor", get(viewPanel, "BackgroundColor"));
view_label(viewPanel, "Center V", [0.445 0.58 0.09 0.30]);
verticalCenterEdit = view_editbox(viewPanel, sprintf("%.4g", defaults.verticalCenter), [0.445 0.14 0.09 0.42]);
view_label(viewPanel, "Span V", [0.545 0.58 0.09 0.30]);
verticalSpanEdit = view_editbox(viewPanel, sprintf("%.4g", defaults.verticalSpan), [0.545 0.14 0.09 0.42]);
view_label(viewPanel, "FFT max Hz", [0.665 0.58 0.10 0.30]);
fftMaxEdit = view_editbox(viewPanel, sprintf("%.0f", defaults.fftMaxHz), [0.665 0.14 0.11 0.42]);

y = 0.91;
label(panel, "Channel", y);
channelPopup = popup(panel, ["CH1", "CH2"], [1 2], y - 0.055, defaults.channel);

y = y - 0.12;
label(panel, "Scale", y);
voltsValues = [0.02 0.05 0.10 0.20 0.50 1.00 2.00 5.00];
voltsLabels = ["20 mV/div", "50 mV/div", "100 mV/div", "200 mV/div", ...
    "500 mV/div", "1 V/div", "2 V/div", "5 V/div"];
voltsPopup = popup(panel, voltsLabels, voltsValues, y - 0.055, defaults.voltsPerDiv);

y = y - 0.12;
label(panel, "Sample rate", y);
rateValues = [100e3 500e3 1e6 2e6 5e6 10e6];
rateLabels = ["100 kS/s", "500 kS/s", "1 MS/s", "2 MS/s", "5 MS/s", "10 MS/s"];
ratePopup = popup(panel, rateLabels, rateValues, y - 0.055, defaults.sampleRate);

y = y - 0.12;
label(panel, "Samples", y);
nSamplesEdit = editbox(panel, sprintf("%d", defaults.nSamples), y - 0.055);

y = y - 0.12;
label(panel, "Refresh s", y);
refreshEdit = editbox(panel, sprintf("%.3g", defaults.refreshPeriod), y - 0.055);

triggerPanel = uipanel( ...
    "Parent", panel, ...
    "Title", "Trigger", ...
    "Units", "normalized", ...
    "Position", [0.08 0.27 0.84 0.09]);
triggerCheckbox = uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "checkbox", ...
    "Units", "normalized", ...
    "Position", [0.04 0.48 0.28 0.36], ...
    "String", "On", ...
    "Value", logical(defaults.triggerEnabled), ...
    "BackgroundColor", get(triggerPanel, "BackgroundColor"));
triggerSlopePopup = uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "popupmenu", ...
    "Units", "normalized", ...
    "Position", [0.36 0.50 0.28 0.34], ...
    "String", {'Rise', 'Fall'}, ...
    "Value", trigger_slope_index(defaults.triggerSlope), ...
    "UserData", ["rising", "falling"], ...
    "BackgroundColor", "w");
uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", [0.04 0.08 0.25 0.26], ...
    "String", "Level", ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", get(triggerPanel, "BackgroundColor"));
triggerLevelText = "auto";
if isfinite(double(defaults.triggerLevel))
    triggerLevelText = sprintf("%.4g", defaults.triggerLevel);
end
triggerLevelEdit = uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "edit", ...
    "Units", "normalized", ...
    "Position", [0.28 0.08 0.28 0.30], ...
    "String", char(triggerLevelText), ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", "w");
uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", [0.62 0.08 0.17 0.26], ...
    "String", "Pos%", ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", get(triggerPanel, "BackgroundColor"));
triggerPositionEdit = uicontrol( ...
    "Parent", triggerPanel, ...
    "Style", "edit", ...
    "Units", "normalized", ...
    "Position", [0.78 0.08 0.18 0.30], ...
    "String", sprintf("%.4g", defaults.triggerPositionPercent), ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", "w");

calibrationCheckbox = uicontrol( ...
    "Parent", panel, ...
    "Style", "checkbox", ...
    "Units", "normalized", ...
    "Position", [0.08 0.225 0.40 0.04], ...
    "String", "Cal SW", ...
    "Value", logical(defaults.applyCalibration), ...
    "BackgroundColor", get(panel, "BackgroundColor"));

debugCheckbox = uicontrol( ...
    "Parent", panel, ...
    "Style", "checkbox", ...
    "Units", "normalized", ...
    "Position", [0.50 0.225 0.42 0.04], ...
    "String", "Echo log", ...
    "Value", logical(defaults.debugEcho), ...
    "BackgroundColor", get(panel, "BackgroundColor"));

startButton = uicontrol( ...
    "Parent", panel, ...
    "Style", "pushbutton", ...
    "Units", "normalized", ...
    "Position", [0.08 0.165 0.38 0.055], ...
    "String", "Start", ...
    "FontWeight", "bold", ...
    "Callback", @on_start_stop);

singleButton = uicontrol( ...
    "Parent", panel, ...
    "Style", "pushbutton", ...
    "Units", "normalized", ...
    "Position", [0.54 0.165 0.38 0.055], ...
    "String", "Single", ...
    "Callback", @on_single);

saveButton = uicontrol( ...
    "Parent", panel, ...
    "Style", "pushbutton", ...
    "Units", "normalized", ...
    "Position", [0.08 0.105 0.84 0.05], ...
    "String", "Save CSV+MAT+PNG", ...
    "Enable", "off", ...
    "Callback", @on_save);

statusText = uicontrol( ...
    "Parent", panel, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", [0.08 0.055 0.84 0.04], ...
    "String", "Stopped", ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", get(panel, "BackgroundColor"));

metricsText = uicontrol( ...
    "Parent", panel, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", [0.08 0.005 0.84 0.045], ...
    "String", "No capture yet", ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", get(panel, "BackgroundColor"), ...
    "FontName", fixed_width_font());

handles = struct( ...
    "panel", panel, ...
    "viewPanel", viewPanel, ...
    "axTime", axTime, ...
    "axFft", axFft, ...
    "timeLine", timeLine, ...
    "fftLine", fftLine, ...
    "channelPopup", channelPopup, ...
    "voltsPopup", voltsPopup, ...
    "ratePopup", ratePopup, ...
    "nSamplesEdit", nSamplesEdit, ...
    "triggerPanel", triggerPanel, ...
    "triggerCheckbox", triggerCheckbox, ...
    "triggerSlopePopup", triggerSlopePopup, ...
    "triggerLevelEdit", triggerLevelEdit, ...
    "triggerPositionEdit", triggerPositionEdit, ...
    "autoTimeCheckbox", autoTimeCheckbox, ...
    "timeStartEdit", timeStartEdit, ...
    "timeWindowEdit", timeWindowEdit, ...
    "autoVoltageCheckbox", autoVoltageCheckbox, ...
    "verticalCenterEdit", verticalCenterEdit, ...
    "verticalSpanEdit", verticalSpanEdit, ...
    "fftMaxEdit", fftMaxEdit, ...
    "refreshEdit", refreshEdit, ...
    "calibrationCheckbox", calibrationCheckbox, ...
    "debugCheckbox", debugCheckbox, ...
    "startButton", startButton, ...
    "singleButton", singleButton, ...
    "saveButton", saveButton, ...
    "statusText", statusText, ...
    "metricsText", metricsText);

app = struct();
app.projectRoot = char(defaults.projectRoot);
app.calibrationPath = char(defaults.calibrationPath);
app.handles = handles;
app.timer = [];
app.running = false;
app.busy = false;
app.blockCount = 0;
app.failureCount = 0;
app.maxFailures = double(defaults.maxFailures);
app.logPath = "";
app.lastData = [];
app.lastMetrics = [];
app.lastConfig = [];
guidata(fig, app);

    function on_start_stop(~, ~)
        app = guidata(fig);
        if app.running
            stop_live(fig);
        else
            start_live(fig);
        end
    end

    function on_single(~, ~)
        app = guidata(fig);
        if app.running || app.busy
            return;
        end
        app.lastConfig = read_config(fig);
        app.logPath = make_log_path(app.projectRoot, "matlab_app_single");
        guidata(fig, app);
        capture_once(fig);
    end

    function on_save(~, ~)
        app = guidata(fig);
        if isempty(app.lastData)
            set_status(fig, "No capture to save");
            return;
        end
        try
            data = app.lastData;
            metrics = app.lastMetrics;
            config = app.lastConfig;
            logPath = app.logPath;
            outputDir = fullfile(app.projectRoot, 'data', 'processed');
            baseName = sprintf('hantek_ch%d_%s', data.channel, datestr(now, 'yyyymmdd_HHMMSS'));
            paths = save_capture_bundle(data, metrics, config, outputDir, baseName, logPath);
            set_status(fig, ['Saved ' char(paths.csv)]);
        catch ME
            set_status(fig, ['Save error: ' char(ME.message)]);
        end
    end

    function on_close(~, ~)
        stop_live(fig);
        delete(fig);
    end
end

function start_live(fig)
app = guidata(fig);
try
    app.lastConfig = read_config(fig);
catch ME
    set_status(fig, "Config error: " + string(ME.message));
    return;
end
app.running = true;
app.busy = false;
app.blockCount = 0;
app.failureCount = 0;
app.logPath = make_log_path(app.projectRoot, "matlab_app_live");
guidata(fig, app);
set_controls_enabled(fig, false);
set(app.handles.startButton, "String", "Stop");
set_status(fig, "Running | log " + string(app.logPath));

capture_once(fig);
app = guidata(fig);
if ~ishandle(fig) || ~app.running
    return;
end

period = max(0.05, double(app.lastConfig.refreshPeriod));
app.timer = timer( ...
    "ExecutionMode", "fixedSpacing", ...
    "Period", period, ...
    "BusyMode", "drop", ...
    "TimerFcn", @(~, ~) capture_once(fig));
guidata(fig, app);
start(app.timer);
end

function stop_live(fig)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
if ~isempty(app.timer)
    try
        stop(app.timer);
    catch
    end
    try
        delete(app.timer);
    catch
    end
end
app.timer = [];
app.running = false;
app.busy = false;
guidata(fig, app);
set_controls_enabled(fig, true);
set(app.handles.startButton, "String", "Start");
set_status(fig, sprintf("Stopped | blocks %d | failures %d", app.blockCount, app.failureCount));
end

function capture_once(fig)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
if app.busy
    return;
end
if isempty(app.lastConfig)
    try
        app.lastConfig = read_config(fig);
    catch ME
        set_status(fig, "Config error: " + string(ME.message));
        return;
    end
end
app.busy = true;
guidata(fig, app);

try
    cfg = app.lastConfig;
    data = hantek_acquire("usb", ...
        "channel", cfg.channel, ...
        "sampleRate", cfg.sampleRate, ...
        "nSamples", cfg.nSamples, ...
        "voltsPerDiv", cfg.voltsPerDiv, ...
        "projectRoot", app.projectRoot, ...
        "applyCalibration", cfg.applyCalibration, ...
        "calibrationPath", app.calibrationPath, ...
        "debugEcho", cfg.debugEcho, ...
        "debugLogPath", app.logPath);

    metrics = analyze_signal(data);
    [freq, magnitude] = compute_fft(data.voltage, data.sample_rate);
    cfg = apply_trigger_config(cfg, read_trigger_config(fig));
    cfg = apply_view_config(cfg, read_view_config(fig));
    [displayTimeMs, displayVoltage, triggerInfo] = display_waveform(data, cfg);
    fftMask = freq <= cfg.fftMaxHz;

    set(app.handles.timeLine, "XData", displayTimeMs, "YData", displayVoltage);
    set(app.handles.fftLine, "XData", freq(fftMask), "YData", magnitude(fftMask));
    format_axes(app.handles.axTime, app.handles.axFft, displayTimeMs, displayVoltage, freq, magnitude, cfg, triggerInfo.found);

    app.blockCount = app.blockCount + 1;
    app.failureCount = 0;
    app.lastData = data;
    app.lastMetrics = metrics;
    app.lastConfig = cfg;
    app.busy = false;
    guidata(fig, app);

    set(app.handles.saveButton, "Enable", "on");
    set(app.handles.metricsText, "String", metrics_string(metrics));
    calibrationLabel = "";
    if isfield(data, 'calibration_applied') && logical(data.calibration_applied)
        calibrationLabel = " | cal sw";
    end
    if isfinite(metrics.rising_period_median_ms)
        title(app.handles.axTime, sprintf("CH%d | block %d | %.4g Vpp | T %.4g ms%s", ...
            data.channel, app.blockCount, metrics.vpp_v, metrics.rising_period_median_ms, char(calibrationLabel)));
    else
        title(app.handles.axTime, sprintf("CH%d | block %d | %.4g Vpp%s", ...
            data.channel, app.blockCount, metrics.vpp_v, char(calibrationLabel)));
    end
    title(app.handles.axFft, sprintf("FFT | dominant %.4g Hz", metrics.dominant_frequency_hz));
    triggerStatus = "";
    if cfg.triggerEnabled
        if triggerInfo.found
            triggerStatus = " | trig";
        else
            triggerStatus = " | no trig";
        end
    end
    statusSuffix = [char(triggerStatus) char(calibrationLabel)];
    set_status(fig, sprintf("OK block %d | %s%s", app.blockCount, datestr(now, 'HH:MM:SS'), statusSuffix));
catch ME
    app = guidata(fig);
    app.failureCount = app.failureCount + 1;
    app.busy = false;
    guidata(fig, app);
    set_status(fig, sprintf("ERROR %d/%d: %s", app.failureCount, app.maxFailures, ME.message));
    if app.failureCount >= app.maxFailures
        stop_live(fig);
    end
end
drawnow limitrate;
end

function cfg = read_config(fig)
app = guidata(fig);
h = app.handles;
cfg = struct();
cfg.channel = popup_value(h.channelPopup);
cfg.voltsPerDiv = popup_value(h.voltsPopup);
cfg.sampleRate = popup_value(h.ratePopup);
cfg.nSamples = read_positive_number(h.nSamplesEdit, "Samples");
cfg.refreshPeriod = read_positive_number(h.refreshEdit, "Refresh s");
cfg.applyCalibration = logical(get(h.calibrationCheckbox, "Value"));
cfg.debugEcho = logical(get(h.debugCheckbox, "Value"));
cfg = apply_trigger_config(cfg, read_trigger_config(fig));
cfg = apply_view_config(cfg, read_view_config(fig));
end

function trigger = read_trigger_config(fig)
app = guidata(fig);
h = app.handles;
trigger = struct();
trigger.triggerEnabled = logical(get(h.triggerCheckbox, "Value"));
trigger.triggerSlope = popup_string_value(h.triggerSlopePopup);
trigger.triggerLevel = read_optional_number(h.triggerLevelEdit, "Level");
trigger.triggerPositionPercent = read_percent_number(h.triggerPositionEdit, "Pos%");
end

function cfg = apply_trigger_config(cfg, trigger)
fields = fieldnames(trigger);
for k = 1:numel(fields)
    cfg.(fields{k}) = trigger.(fields{k});
end
end

function view = read_view_config(fig)
app = guidata(fig);
h = app.handles;
view = struct();
view.autoTime = logical(get(h.autoTimeCheckbox, "Value"));
view.timeStartMs = read_nonnegative_number(h.timeStartEdit, "Start ms");
view.timeWindowMs = read_positive_number(h.timeWindowEdit, "Window ms");
view.autoVoltage = logical(get(h.autoVoltageCheckbox, "Value"));
view.verticalCenter = read_finite_number(h.verticalCenterEdit, "Center V");
view.verticalSpan = read_positive_number(h.verticalSpanEdit, "Span V");
view.fftMaxHz = read_positive_number(h.fftMaxEdit, "FFT max Hz");
end

function cfg = apply_view_config(cfg, view)
fields = fieldnames(view);
for k = 1:numel(fields)
    cfg.(fields{k}) = view.(fields{k});
end
end

function value = popup_value(handle)
values = get(handle, "UserData");
index = get(handle, "Value");
value = values(index);
end

function value = popup_string_value(handle)
values = get(handle, "UserData");
index = get(handle, "Value");
value = string(values(index));
end

function value = read_positive_number(handle, labelText)
value = str2double(get(handle, "String"));
if ~isfinite(value) || value <= 0
    error("%s debe ser un numero positivo.", char(labelText));
end
value = double(value);
end

function value = read_nonnegative_number(handle, labelText)
value = str2double(get(handle, "String"));
if ~isfinite(value) || value < 0
    error("%s debe ser un numero mayor o igual a cero.", char(labelText));
end
value = double(value);
end

function value = read_finite_number(handle, labelText)
value = str2double(get(handle, "String"));
if ~isfinite(value)
    error("%s debe ser un numero finito.", char(labelText));
end
value = double(value);
end

function value = read_optional_number(handle, labelText)
text = strtrim(string(get(handle, "String")));
if strlength(text) == 0 || lower(text) == "auto"
    value = NaN;
    return;
end
value = str2double(text);
if ~isfinite(value)
    error("%s debe ser un numero o auto.", char(labelText));
end
value = double(value);
end

function value = read_percent_number(handle, labelText)
value = str2double(get(handle, "String"));
if ~isfinite(value) || value < 0 || value > 100
    error("%s debe estar entre 0 y 100.", char(labelText));
end
value = double(value);
end

function [timeMs, voltage, info] = display_waveform(data, cfg)
timeMs = double(data.time(:)) * 1e3;
sourceVoltage = double(data.voltage(:));
sampleCount = min(numel(timeMs), numel(sourceVoltage));
timeMs = timeMs(1:sampleCount);
sourceVoltage = sourceVoltage(1:sampleCount);
voltage = sourceVoltage;
info = struct("found", false, "level", NaN, "index", NaN, "shift", 0);

fs         = double(data.sample_rate);
n          = numel(sourceVoltage);
if n == 0 || numel(timeMs) == 0
    voltage = [];
    return;
end

if cfg.autoTime
    visibleStartMs = min(timeMs);
    visibleEndMs = max(timeMs);
else
    visibleStartMs = double(cfg.timeStartMs);
    visibleEndMs = visibleStartMs + double(cfg.timeWindowMs);
end
visibleWindowMs = visibleEndMs - visibleStartMs;
if ~isfinite(visibleWindowMs) || visibleWindowMs <= 0
    return;
end

if ~cfg.triggerEnabled || n < 3
    return;
end

finiteVoltage = sourceVoltage(isfinite(sourceVoltage));
if isempty(finiteVoltage)
    return;
end

sv = sort(finiteVoltage);
nv = numel(sv);
p5 = sv(max(1, round(0.05 * nv)));
p95 = sv(min(nv, round(0.95 * nv)));
amplitude = max(p95 - p5, eps);
level = double(cfg.triggerLevel);
if ~isfinite(level)
    level = (p5 + p95) / 2;
end
hysteresis = max(0.02, 0.08 * amplitude);

triggerIndices = find_trigger_indices(sourceVoltage, level, hysteresis, cfg.triggerSlope);
if isempty(triggerIndices)
    return;
end

desiredTimeMs = visibleStartMs + visibleWindowMs * double(cfg.triggerPositionPercent) / 100.0;
[~, targetIndex] = min(abs(timeMs - desiredTimeMs));
visibleIndices = find(timeMs >= visibleStartMs & timeMs <= visibleEndMs);
if isempty(visibleIndices)
    visibleIndices = (1:n).';
end

triggerIdx = triggerIndices(1);
selectedShift = targetIndex - triggerIdx;
bestPenalty = Inf;
bestDistance = Inf;
for k = 1:numel(triggerIndices)
    candidateTrigger = triggerIndices(k);
    candidateShift = targetIndex - candidateTrigger;
    candidateSource = visibleIndices - candidateShift;
    penalty = sum(candidateSource < 1 | candidateSource > n);
    distance = abs(candidateShift);
    if penalty < bestPenalty || (penalty == bestPenalty && distance < bestDistance)
        bestPenalty = penalty;
        bestDistance = distance;
        triggerIdx = candidateTrigger;
        selectedShift = candidateShift;
    end
    if penalty == 0
        break;
    end
end

voltage = non_wrapping_shift(sourceVoltage, selectedShift);

info.found = true;
info.level = level;
info.index = triggerIdx;
info.shift = selectedShift;
end

function triggerIndices = find_trigger_indices(values, level, hysteresis, slope)
triggerIndices = [];
low = level - hysteresis;
high = level + hysteresis;
armed = false;
slope = lower(string(slope));

for i = 1:numel(values)
    value = values(i);
    if ~isfinite(value)
        armed = false;
        continue;
    end

    if slope == "falling"
        if value >= high
            armed = true;
        elseif armed && value <= level
            triggerIndices(end + 1, 1) = i; %#ok<AGROW>
            armed = false;
        end
    else
        if value <= low
            armed = true;
        elseif armed && value >= level
            triggerIndices(end + 1, 1) = i; %#ok<AGROW>
            armed = false;
        end
    end
end
end

function shifted = non_wrapping_shift(values, shift)
shifted = nan(size(values));
n = numel(values);
shift = round(double(shift));
if abs(shift) >= n
    return;
end
if shift >= 0
    srcStart = 1;
    srcEnd = n - shift;
    dstStart = 1 + shift;
    dstEnd = n;
else
    srcStart = 1 - shift;
    srcEnd = n;
    dstStart = 1;
    dstEnd = n + shift;
end
if srcStart <= srcEnd && dstStart <= dstEnd
    shifted(dstStart:dstEnd) = values(srcStart:srcEnd);
end
end

function format_axes(axTime, axFft, timeMs, voltage, freq, magnitude, cfg, ~)
if ~isempty(timeMs)
    if cfg.autoTime
        xlim(axTime, [min(timeMs) max(timeMs)]);
    else
        tStart = double(cfg.timeStartMs);
        tWindow = double(cfg.timeWindowMs);
        xlim(axTime, [tStart tStart + tWindow]);
    end
end
if ~isempty(voltage)
    if cfg.autoVoltage
        finiteVoltage = voltage(isfinite(voltage));
        if ~isempty(finiteVoltage)
            vMin = min(finiteVoltage);
            vMax = max(finiteVoltage);
            pad = max((vMax - vMin) * 0.10, 0.05);
            ylim(axTime, [vMin - pad vMax + pad]);
        end
    else
        vCenter = double(cfg.verticalCenter);
        vHalfSpan = double(cfg.verticalSpan) / 2;
        ylim(axTime, [vCenter - vHalfSpan vCenter + vHalfSpan]);
    end
end
xlim(axFft, [0 double(cfg.fftMaxHz)]);
fftMask = freq <= cfg.fftMaxHz;
if any(fftMask)
    maxMag = max(magnitude(fftMask));
    if isfinite(maxMag) && maxMag > 0
        ylim(axFft, [0 maxMag * 1.15]);
    end
end
end

function text = metrics_string(metrics)
text = sprintf([ ...
    'Vpp   %.4g V\n' ...
    'Mean  %.4g V\n' ...
    'RMS   %.4g V\n' ...
    'Fdom  %.4g Hz\n' ...
    'Tmed  %.4g ms\n' ...
    'Tjit  %.4g %%'], ...
    metrics.vpp_v, metrics.mean_v, metrics.rms_v, ...
    metrics.dominant_frequency_hz, metrics.rising_period_median_ms, ...
    metrics.rising_period_spread_pct);
end

function set_status(fig, message)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
set(app.handles.statusText, "String", char(message));
end

function set_controls_enabled(fig, enabled)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
state = 'off';
if enabled
    state = 'on';
end
h = app.handles;
set(h.channelPopup, "Enable", state);
set(h.voltsPopup, "Enable", state);
set(h.ratePopup, "Enable", state);
set(h.nSamplesEdit, "Enable", state);
set(h.refreshEdit, "Enable", state);
set(h.calibrationCheckbox, "Enable", state);
set(h.debugCheckbox, "Enable", state);
set(h.singleButton, "Enable", state);
end

function out = make_log_path(projectRoot, prefix)
folder = fullfile(char(projectRoot), "data", "logs");
if ~exist(folder, "dir")
    mkdir(folder);
end
out = fullfile(folder, [char(prefix) '_' datestr(now, 'yyyymmdd_HHMMSS') '.log']);
end

function h = label(parent, text, y)
h = uicontrol( ...
    "Parent", parent, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", [0.08 y 0.84 0.035], ...
    "String", char(text), ...
    "HorizontalAlignment", "left", ...
    "FontWeight", "bold", ...
    "BackgroundColor", get(parent, "BackgroundColor"));
end

function h = view_label(parent, text, position)
h = uicontrol( ...
    "Parent", parent, ...
    "Style", "text", ...
    "Units", "normalized", ...
    "Position", position, ...
    "String", char(text), ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", get(parent, "BackgroundColor"));
end

function h = popup(parent, labels, values, y, defaultValue)
[~, index] = min(abs(values - double(defaultValue)));
h = uicontrol( ...
    "Parent", parent, ...
    "Style", "popupmenu", ...
    "Units", "normalized", ...
    "Position", [0.08 y 0.84 0.055], ...
    "String", cellstr(labels), ...
    "Value", index, ...
    "UserData", values, ...
    "BackgroundColor", "w");
end

function index = trigger_slope_index(value)
value = lower(string(value));
if value == "falling" || value == "fall" || value == "down"
    index = 2;
else
    index = 1;
end
end

function h = editbox(parent, value, y)
h = uicontrol( ...
    "Parent", parent, ...
    "Style", "edit", ...
    "Units", "normalized", ...
    "Position", [0.08 y 0.84 0.05], ...
    "String", char(value), ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", "w");
end

function h = view_editbox(parent, value, position)
h = uicontrol( ...
    "Parent", parent, ...
    "Style", "edit", ...
    "Units", "normalized", ...
    "Position", position, ...
    "String", char(value), ...
    "HorizontalAlignment", "left", ...
    "BackgroundColor", "w");
end

function fontName = fixed_width_font()
if ismac
    fontName = "Menlo";
else
    fontName = "Monospaced";
end
end

function projectRoot = default_project_root()
thisFile = mfilename("fullpath");
projectRoot = fileparts(fileparts(thisFile));
end
