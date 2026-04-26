function fig = hantek_dual_live_app(varargin)
%HANTEK_DUAL_LIVE_APP Live CH1+CH2 USB control panel.

p = inputParser;
addParameter(p, 'sampleRate', 10e6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'nSamples', 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'voltsPerDiv', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'timeStartMs', 0.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'timeWindowMs', 5.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'fftMaxHz', 10000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'refreshPeriod', 0.25, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'triggerEnabled', true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, 'triggerSource', 'ch1', @(x) ischar(x) || isstring(x));
addParameter(p, 'triggerSlope', 'rising', @(x) ischar(x) || isstring(x));
addParameter(p, 'triggerLevel', NaN, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'projectRoot', default_project_root(), @(x) ischar(x) || isstring(x));
addParameter(p, 'applyCalibration', true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, 'calibrationPath', fullfile(default_project_root(), 'data', 'software_calibration.json'), @(x) ischar(x) || isstring(x));
addParameter(p, 'debugEcho', false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, 'maxFailures', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
parse(p, varargin{:});
defaults = p.Results;

fig = figure( ...
    'Name', 'Hantek 6022BE USB Dual Live', ...
    'NumberTitle', 'off', ...
    'Color', 'w', ...
    'MenuBar', 'none', ...
    'ToolBar', 'figure', ...
    'Units', 'pixels', ...
    'Position', [80 80 1240 740], ...
    'CloseRequestFcn', @on_close);

panel = uipanel( ...
    'Parent', fig, ...
    'Title', 'Acquisition', ...
    'Units', 'normalized', ...
    'Position', [0.015 0.04 0.22 0.92]);

viewPanel = uipanel( ...
    'Parent', fig, ...
    'Title', 'View', ...
    'Units', 'normalized', ...
    'Position', [0.30 0.925 0.67 0.065]);

axTime = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.30 0.56 0.67 0.32]);
timeLine1 = plot(axTime, nan, nan, 'LineWidth', 1.1);
hold(axTime, 'on');
timeLine2 = plot(axTime, nan, nan, 'LineWidth', 1.1);
hold(axTime, 'off');
grid(axTime, 'on');
xlabel(axTime, 'Time (ms)');
ylabel(axTime, 'Voltage (V)');
legend(axTime, {'CH1', 'CH2'}, 'Location', 'best');
title(axTime, 'Ready');

metricsTable = uitable( ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.30 0.445 0.67 0.085], ...
    'ColumnName', {'Metric', 'CH1', 'CH2 / Dual'}, ...
    'ColumnWidth', {115, 180, 180}, ...
    'Data', metrics_table_placeholder());

axFft = axes('Parent', fig, 'Units', 'normalized', 'Position', [0.30 0.10 0.67 0.32]);
fftLine1 = plot(axFft, nan, nan, 'LineWidth', 1.1);
hold(axFft, 'on');
fftLine2 = plot(axFft, nan, nan, 'LineWidth', 1.1);
hold(axFft, 'off');
grid(axFft, 'on');
xlabel(axFft, 'Frequency (Hz)');
ylabel(axFft, 'Magnitude (V)');
legend(axFft, {'CH1', 'CH2'}, 'Location', 'best');
title(axFft, 'FFT');

view_label(viewPanel, 'Start ms', [0.03 0.58 0.09 0.30]);
timeStartEdit = view_editbox(viewPanel, sprintf('%.4g', defaults.timeStartMs), [0.03 0.14 0.09 0.42]);
view_label(viewPanel, 'Window ms', [0.14 0.58 0.10 0.30]);
timeWindowEdit = view_editbox(viewPanel, sprintf('%.4g', defaults.timeWindowMs), [0.14 0.14 0.10 0.42]);
view_label(viewPanel, 'FFT max Hz', [0.27 0.58 0.10 0.30]);
fftMaxEdit = view_editbox(viewPanel, sprintf('%.0f', defaults.fftMaxHz), [0.27 0.14 0.11 0.42]);

y = 0.91;
label(panel, 'Mode', y);
modePopup = popup(panel, {'Dual', 'CH1', 'CH2'}, ["dual", "ch1", "ch2"], y - 0.055, "dual");

y = y - 0.10;
label(panel, 'Preset', y);
presetPopup = popup(panel, {'Cal 1 kHz', 'Diagnostic', 'External', 'Slow', 'Fast', 'Long'}, ...
    ["cal", "diagnostic", "external", "slow", "fast", "long"], y - 0.055, "cal");
set(presetPopup, 'Callback', @on_preset);

y = y - 0.10;
label(panel, 'Scale', y);
voltsValues = [0.02 0.05 0.10 0.20 0.50 1.00 2.00 5.00];
voltsLabels = {'20 mV/div', '50 mV/div', '100 mV/div', '200 mV/div', ...
    '500 mV/div', '1 V/div', '2 V/div', '5 V/div'};
voltsPopup = popup(panel, voltsLabels, voltsValues, y - 0.055, defaults.voltsPerDiv);

y = y - 0.10;
label(panel, 'Sample rate', y);
rateValues = [100e3 500e3 1e6 2e6 5e6 10e6];
rateLabels = {'100 kS/s', '500 kS/s', '1 MS/s', '2 MS/s', '5 MS/s', '10 MS/s'};
ratePopup = popup(panel, rateLabels, rateValues, y - 0.055, defaults.sampleRate);

y = y - 0.10;
label(panel, 'Samples', y);
nSamplesEdit = editbox(panel, sprintf('%d', defaults.nSamples), y - 0.055);

y = y - 0.10;
label(panel, 'Refresh s', y);
refreshEdit = editbox(panel, sprintf('%.3g', defaults.refreshPeriod), y - 0.055);

triggerPanel = uipanel( ...
    'Parent', panel, ...
    'Title', 'Trigger', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.275 0.84 0.125]);
triggerCheckbox = uicontrol( ...
    'Parent', triggerPanel, ...
    'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.04 0.58 0.22 0.32], ...
    'String', 'On', ...
    'Value', logical(defaults.triggerEnabled), ...
    'BackgroundColor', get(triggerPanel, 'BackgroundColor'));
triggerSourcePopup = uicontrol( ...
    'Parent', triggerPanel, ...
    'Style', 'popupmenu', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.60 0.28 0.30], ...
    'String', {'CH1', 'CH2'}, ...
    'Value', trigger_source_index(defaults.triggerSource), ...
    'UserData', ["ch1", "ch2"], ...
    'BackgroundColor', 'w');
triggerSlopePopup = uicontrol( ...
    'Parent', triggerPanel, ...
    'Style', 'popupmenu', ...
    'Units', 'normalized', ...
    'Position', [0.62 0.60 0.34 0.30], ...
    'String', {'Rise', 'Fall'}, ...
    'Value', trigger_slope_index(defaults.triggerSlope), ...
    'UserData', ["rising", "falling"], ...
    'BackgroundColor', 'w');
uicontrol( ...
    'Parent', triggerPanel, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.04 0.16 0.22 0.25], ...
    'String', 'Level', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', get(triggerPanel, 'BackgroundColor'));
triggerLevelText = 'auto';
if isfinite(double(defaults.triggerLevel))
    triggerLevelText = sprintf('%.4g', defaults.triggerLevel);
end
triggerLevelEdit = uicontrol( ...
    'Parent', triggerPanel, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', [0.28 0.16 0.34 0.28], ...
    'String', triggerLevelText, ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');

calibrationCheckbox = uicontrol( ...
    'Parent', panel, ...
    'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.23 0.26 0.04], ...
    'String', 'Cal SW', ...
    'Value', logical(defaults.applyCalibration), ...
    'BackgroundColor', get(panel, 'BackgroundColor'));
rawSaveCheckbox = uicontrol( ...
    'Parent', panel, ...
    'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.36 0.23 0.28 0.04], ...
    'String', 'Raw CSV', ...
    'Value', 1, ...
    'BackgroundColor', get(panel, 'BackgroundColor'));
debugCheckbox = uicontrol( ...
    'Parent', panel, ...
    'Style', 'checkbox', ...
    'Units', 'normalized', ...
    'Position', [0.66 0.23 0.26 0.04], ...
    'String', 'Echo log', ...
    'Value', logical(defaults.debugEcho), ...
    'BackgroundColor', get(panel, 'BackgroundColor'));

startButton = uicontrol( ...
    'Parent', panel, ...
    'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.165 0.38 0.055], ...
    'String', 'Start', ...
    'FontWeight', 'bold', ...
    'Callback', @on_start_stop);
singleButton = uicontrol( ...
    'Parent', panel, ...
    'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.54 0.165 0.38 0.055], ...
    'String', 'Single', ...
    'Callback', @on_single);
saveButton = uicontrol( ...
    'Parent', panel, ...
    'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.105 0.84 0.05], ...
    'String', 'Save Dual CSV+MAT+PNG', ...
    'Enable', 'off', ...
    'Callback', @on_save);

statusText = uicontrol( ...
    'Parent', panel, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.080 0.84 0.030], ...
    'String', 'Stopped', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', get(panel, 'BackgroundColor'));
metricsText = uicontrol( ...
    'Parent', panel, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.08 0.005 0.84 0.070], ...
    'String', 'No capture yet', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', get(panel, 'BackgroundColor'), ...
    'FontName', fixed_width_font());

handles = struct( ...
    'modePopup', modePopup, ...
    'presetPopup', presetPopup, ...
    'voltsPopup', voltsPopup, ...
    'ratePopup', ratePopup, ...
    'nSamplesEdit', nSamplesEdit, ...
    'refreshEdit', refreshEdit, ...
    'triggerCheckbox', triggerCheckbox, ...
    'triggerSourcePopup', triggerSourcePopup, ...
    'triggerSlopePopup', triggerSlopePopup, ...
    'triggerLevelEdit', triggerLevelEdit, ...
    'calibrationCheckbox', calibrationCheckbox, ...
    'rawSaveCheckbox', rawSaveCheckbox, ...
    'debugCheckbox', debugCheckbox, ...
    'timeStartEdit', timeStartEdit, ...
    'timeWindowEdit', timeWindowEdit, ...
    'fftMaxEdit', fftMaxEdit, ...
    'startButton', startButton, ...
    'singleButton', singleButton, ...
    'saveButton', saveButton, ...
    'statusText', statusText, ...
    'metricsText', metricsText, ...
    'metricsTable', metricsTable, ...
    'axTime', axTime, ...
    'axFft', axFft, ...
    'timeLine1', timeLine1, ...
    'timeLine2', timeLine2, ...
    'fftLine1', fftLine1, ...
    'fftLine2', fftLine2);

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
        try
            app.lastConfig = read_config(fig);
        catch ME
            set_status(fig, ['Config error: ' char(ME.message)]);
            return;
        end
        app.logPath = make_log_path(app.projectRoot, 'matlab_dual_app_single');
        guidata(fig, app);
        capture_once(fig);
    end

    function on_save(~, ~)
        app = guidata(fig);
        if isempty(app.lastData)
            set_status(fig, 'No capture to save');
            return;
        end
        try
            outputDir = fullfile(app.projectRoot, 'data', 'processed');
            baseName = ['hantek_dual_' datestr(now, 'yyyymmdd_HHMMSS')];
            paths = save_dual_capture_bundle(app.lastData, app.lastMetrics, ...
                app.lastConfig, outputDir, baseName, app.logPath);
            set_status(fig, ['Saved ' char(paths.csv)]);
        catch ME
            set_status(fig, ['Save error: ' char(ME.message)]);
        end
    end

    function on_preset(~, ~)
        if ~ishandle(fig)
            return;
        end
        app = guidata(fig);
        if app.running || app.busy
            return;
        end
        apply_preset(fig, popup_value(app.handles.presetPopup));
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
    set_status(fig, ['Config error: ' char(ME.message)]);
    return;
end
app.running = true;
app.busy = false;
app.blockCount = 0;
app.failureCount = 0;
app.logPath = make_log_path(app.projectRoot, 'matlab_dual_app_live');
guidata(fig, app);
set_controls_enabled(fig, false);
set(app.handles.startButton, 'String', 'Stop');
set_status(fig, ['Running | log ' char(app.logPath)]);

capture_once(fig);
app = guidata(fig);
if ~ishandle(fig) || ~app.running
    return;
end

period = max(0.05, double(app.lastConfig.refreshPeriod));
app.timer = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'Period', period, ...
    'BusyMode', 'drop', ...
    'TimerFcn', @(~, ~) capture_once(fig));
guidata(fig, app);
start(app.timer);
end

function stop_live(fig)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
if ~isempty(app.timer)
    try, stop(app.timer); catch, end
    try, delete(app.timer); catch, end
end
app.timer = [];
app.running = false;
app.busy = false;
guidata(fig, app);
set_controls_enabled(fig, true);
set(app.handles.startButton, 'String', 'Start');
set_status(fig, sprintf('Stopped | blocks %d | failures %d', app.blockCount, app.failureCount));
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
        set_status(fig, ['Config error: ' char(ME.message)]);
        return;
    end
end
app.busy = true;
guidata(fig, app);

try
    cfg = app.lastConfig;
    data = hantek_acquire_dual( ...
        'sampleRate', cfg.sampleRate, ...
        'nSamples', cfg.nSamples, ...
        'voltsPerDiv', cfg.voltsPerDiv, ...
        'projectRoot', app.projectRoot, ...
        'applyCalibration', cfg.applyCalibration, ...
        'calibrationPath', app.calibrationPath, ...
        'debugEcho', cfg.debugEcho, ...
        'debugLogPath', app.logPath);

    metrics = analyze_dual_signal(data);
    cfg = apply_view_config(cfg, read_view_config(fig));
    [timeMs, ch1, ch2, triggerFound] = display_dual_waveform(data, cfg);
    [freq1, mag1] = compute_fft(data.ch1, data.sample_rate);
    [freq2, mag2] = compute_fft(data.ch2, data.sample_rate);
    fftMask1 = freq1 <= cfg.fftMaxHz;
    fftMask2 = freq2 <= cfg.fftMaxHz;

    update_lines(app.handles, cfg.mode, timeMs, ch1, ch2, ...
        freq1(fftMask1), mag1(fftMask1), freq2(fftMask2), mag2(fftMask2));
    format_axes(app.handles.axTime, app.handles.axFft, timeMs, ch1, ch2, cfg);

    app.blockCount = app.blockCount + 1;
    app.failureCount = 0;
    app.lastData = data;
    app.lastMetrics = metrics;
    app.lastConfig = cfg;
    app.busy = false;
    guidata(fig, app);

    set(app.handles.saveButton, 'Enable', 'on');
    set(app.handles.metricsText, 'String', metrics_string(metrics));
    set(app.handles.metricsTable, 'Data', metrics_table_data(metrics));
    calLabel = '';
    if isfield(data, 'calibration_applied') && logical(data.calibration_applied)
        calLabel = ' | cal sw';
    end
    trigLabel = '';
    if cfg.triggerEnabled
        if triggerFound
            trigLabel = ' | trig';
        else
            trigLabel = ' | no trig';
        end
    end
    title(app.handles.axTime, sprintf('Dual block %d | CH1 %.4g Vpp | CH2 %.4g Vpp%s', ...
        app.blockCount, metrics.ch1.vpp_v, metrics.ch2.vpp_v, calLabel));
    title(app.handles.axFft, sprintf('FFT | CH1 %.4g Hz | CH2 %.4g Hz', ...
        metrics.ch1.dominant_frequency_hz, metrics.ch2.dominant_frequency_hz));
    set_status(fig, sprintf('OK block %d | %s%s%s', app.blockCount, datestr(now, 'HH:MM:SS'), trigLabel, calLabel));
catch ME
    app = guidata(fig);
    app.failureCount = app.failureCount + 1;
    app.busy = false;
    guidata(fig, app);
    set_status(fig, sprintf('ERROR %d/%d: %s', app.failureCount, app.maxFailures, ME.message));
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
cfg.mode = char(popup_value(h.modePopup));
cfg.voltsPerDiv = popup_value(h.voltsPopup);
cfg.sampleRate = popup_value(h.ratePopup);
cfg.nSamples = read_positive_number(h.nSamplesEdit, 'Samples');
cfg.refreshPeriod = read_positive_number(h.refreshEdit, 'Refresh s');
cfg.triggerEnabled = logical(get(h.triggerCheckbox, 'Value'));
cfg.triggerSource = char(popup_value(h.triggerSourcePopup));
cfg.triggerSlope = char(popup_value(h.triggerSlopePopup));
cfg.triggerLevel = read_optional_number(h.triggerLevelEdit, 'Level');
cfg.applyCalibration = logical(get(h.calibrationCheckbox, 'Value'));
cfg.saveRawCsv = logical(get(h.rawSaveCheckbox, 'Value'));
cfg.plotRawOverlay = cfg.saveRawCsv && cfg.applyCalibration;
cfg.debugEcho = logical(get(h.debugCheckbox, 'Value'));
cfg = apply_view_config(cfg, read_view_config(fig));
end

function view = read_view_config(fig)
app = guidata(fig);
h = app.handles;
view = struct();
view.timeStartMs = read_nonnegative_number(h.timeStartEdit, 'Start ms');
view.timeWindowMs = read_positive_number(h.timeWindowEdit, 'Window ms');
view.fftMaxHz = read_positive_number(h.fftMaxEdit, 'FFT max Hz');
end

function cfg = apply_view_config(cfg, view)
fields = fieldnames(view);
for k = 1:numel(fields)
    cfg.(fields{k}) = view.(fields{k});
end
end

function [timeMs, ch1, ch2, triggerFound] = display_dual_waveform(data, cfg)
time = double(data.time(:));
ch1Source = double(data.ch1(:));
ch2Source = double(data.ch2(:));
n = min([numel(time), numel(ch1Source), numel(ch2Source)]);
time = time(1:n);
ch1Source = ch1Source(1:n);
ch2Source = ch2Source(1:n);

fs = double(data.sample_rate);
nDisplay = min(n, max(2, round(cfg.timeWindowMs * 1e-3 * fs)));
startIndex = min(max(1, round(cfg.timeStartMs * 1e-3 * fs) + 1), max(1, n - nDisplay + 1));
triggerFound = false;

if cfg.triggerEnabled && nDisplay < n
    preTrigger = min(nDisplay - 1, max(1, round(0.20 * nDisplay)));
    if strcmpi(cfg.triggerSource, 'ch2')
        source = ch2Source;
    else
        source = ch1Source;
    end
    edgeIdx = edge_indices(source, cfg.triggerSlope, cfg.triggerLevel);
    valid = edgeIdx(edgeIdx - preTrigger >= 1 & edgeIdx + (nDisplay - preTrigger) - 1 <= n);
    if ~isempty(valid)
        triggerFound = true;
        startIndex = valid(1) - preTrigger;
    end
end

stopIndex = min(n, startIndex + nDisplay - 1);
idx = startIndex:stopIndex;
ch1 = ch1Source(idx);
ch2 = ch2Source(idx);
if cfg.triggerEnabled && triggerFound
    triggerIndex = min(numel(idx), max(1, round(0.20 * numel(idx))));
    timeMs = ((0:numel(idx)-1).' - triggerIndex) ./ fs .* 1e3;
else
    timeMs = time(idx) * 1e3;
end
end

function edgeIdx = edge_indices(voltage, slope, manualLevel)
voltage = double(voltage(:));
finiteVoltage = voltage(isfinite(voltage));
edgeIdx = [];
if numel(finiteVoltage) < 3
    return;
end
sv = sort(finiteVoltage);
nv = numel(sv);
p5 = sv(max(1, round(0.05 * nv)));
p95 = sv(min(nv, round(0.95 * nv)));
amplitude = p95 - p5;
if ~isfinite(amplitude) || amplitude <= 0
    return;
end
level = (p5 + p95) / 2;
if isfinite(double(manualLevel))
    level = double(manualLevel);
end
hysteresis = max(0.02, 0.08 * amplitude);
low = level - hysteresis;
high = level + hysteresis;
armed = false;
for i = 1:numel(voltage)
    value = voltage(i);
    if ~isfinite(value)
        armed = false;
    elseif strcmpi(slope, 'falling')
        if value >= high
            armed = true;
        elseif armed && value <= level
            edgeIdx(end + 1, 1) = i; %#ok<AGROW>
            armed = false;
        end
    else
        if value <= low
            armed = true;
        elseif armed && value >= level
            edgeIdx(end + 1, 1) = i; %#ok<AGROW>
            armed = false;
        end
    end
end
end

function update_lines(h, mode, timeMs, ch1, ch2, freq1, mag1, freq2, mag2)
set(h.timeLine1, 'XData', timeMs, 'YData', ch1);
set(h.timeLine2, 'XData', timeMs, 'YData', ch2);
set(h.fftLine1, 'XData', freq1, 'YData', mag1);
set(h.fftLine2, 'XData', freq2, 'YData', mag2);

if strcmpi(mode, 'ch1')
    set(h.timeLine1, 'Visible', 'on');
    set(h.timeLine2, 'Visible', 'off');
    set(h.fftLine1, 'Visible', 'on');
    set(h.fftLine2, 'Visible', 'off');
elseif strcmpi(mode, 'ch2')
    set(h.timeLine1, 'Visible', 'off');
    set(h.timeLine2, 'Visible', 'on');
    set(h.fftLine1, 'Visible', 'off');
    set(h.fftLine2, 'Visible', 'on');
else
    set(h.timeLine1, 'Visible', 'on');
    set(h.timeLine2, 'Visible', 'on');
    set(h.fftLine1, 'Visible', 'on');
    set(h.fftLine2, 'Visible', 'on');
end
end

function format_axes(axTime, axFft, timeMs, ch1, ch2, cfg)
if ~isempty(timeMs)
    xlim(axTime, [min(timeMs) max(timeMs)]);
end
values = [];
if strcmpi(cfg.mode, 'ch1') || strcmpi(cfg.mode, 'dual')
    values = [values; ch1(:)]; %#ok<AGROW>
end
if strcmpi(cfg.mode, 'ch2') || strcmpi(cfg.mode, 'dual')
    values = [values; ch2(:)]; %#ok<AGROW>
end
values = values(isfinite(values));
if ~isempty(values)
    low = min(values);
    high = max(values);
    span = max(high - low, 0.5);
    center = (low + high) / 2;
    ylim(axTime, [center - 0.65 * span, center + 0.65 * span]);
end
xlim(axFft, [0 cfg.fftMaxHz]);
end

function textOut = metrics_string(metrics)
textOut = sprintf([ ...
    'CH1 %.3gV %.3gHz %.3g%%\n' ...
    'CH2 %.3gV %.3gHz %.3g%%\n' ...
    'Dly %.3gms %.3gdeg'], ...
    metrics.ch1.vpp_v, metrics.ch1.rising_frequency_hz, metrics.ch1.duty_cycle_pct, ...
    metrics.ch2.vpp_v, metrics.ch2.rising_frequency_hz, metrics.ch2.duty_cycle_pct, ...
    metrics.delay_ch2_minus_ch1_ms, metrics.phase_ch2_minus_ch1_deg);
end

function data = metrics_table_placeholder()
data = {
    'Vpp', '', '';
    'Freq', '', '';
    'Duty', '', '';
    'Mean', '', '';
    'Tjit', '', '';
    'Delay', '', ''
    };
end

function data = metrics_table_data(metrics)
data = {
    'Vpp', sprintf('%.6g V', metrics.ch1.vpp_v), sprintf('%.6g V', metrics.ch2.vpp_v);
    'Freq', sprintf('%.6g Hz', metrics.ch1.rising_frequency_hz), sprintf('%.6g Hz', metrics.ch2.rising_frequency_hz);
    'Duty', sprintf('%.6g %%', metrics.ch1.duty_cycle_pct), sprintf('%.6g %%', metrics.ch2.duty_cycle_pct);
    'Mean', sprintf('%.6g V', metrics.ch1.mean_v), sprintf('%.6g V', metrics.ch2.mean_v);
    'Tjit', sprintf('%.6g %%', metrics.ch1.rising_period_spread_pct), sprintf('%.6g %%', metrics.ch2.rising_period_spread_pct);
    'Delay', '', sprintf('%.6g ms | %.6g deg', metrics.delay_ch2_minus_ch1_ms, metrics.phase_ch2_minus_ch1_deg)
    };
end

function apply_preset(fig, preset)
app = guidata(fig);
h = app.handles;
preset = char(preset);
switch preset
    case 'slow'
        set_popup_to_value(h.ratePopup, 1e6);
        set(h.nSamplesEdit, 'String', '50000');
        set(h.timeWindowEdit, 'String', '20');
        set(h.fftMaxEdit, 'String', '5000');
    case 'fast'
        set_popup_to_value(h.ratePopup, 10e6);
        set(h.nSamplesEdit, 'String', '100000');
        set(h.timeWindowEdit, 'String', '2');
        set(h.fftMaxEdit, 'String', '50000');
    case 'long'
        set_popup_to_value(h.ratePopup, 1e6);
        set(h.nSamplesEdit, 'String', '200000');
        set(h.timeWindowEdit, 'String', '50');
        set(h.fftMaxEdit, 'String', '10000');
    case 'diagnostic'
        set_popup_to_value(h.ratePopup, 10e6);
        set(h.nSamplesEdit, 'String', '100000');
        set(h.timeWindowEdit, 'String', '5');
        set(h.fftMaxEdit, 'String', '10000');
    case 'external'
        set_popup_to_value(h.ratePopup, 5e6);
        set(h.nSamplesEdit, 'String', '100000');
        set(h.timeWindowEdit, 'String', '10');
        set(h.fftMaxEdit, 'String', '100000');
    otherwise
        set_popup_to_value(h.ratePopup, 10e6);
        set(h.nSamplesEdit, 'String', '100000');
        set(h.timeWindowEdit, 'String', '5');
        set(h.fftMaxEdit, 'String', '10000');
        set_popup_to_value(h.voltsPopup, 1.0);
end
set_status(fig, ['Preset ' preset]);
end

function set_controls_enabled(fig, enabled)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
h = app.handles;
state = 'off';
if enabled
    state = 'on';
end
set(h.modePopup, 'Enable', state);
set(h.presetPopup, 'Enable', state);
set(h.voltsPopup, 'Enable', state);
set(h.ratePopup, 'Enable', state);
set(h.nSamplesEdit, 'Enable', state);
set(h.refreshEdit, 'Enable', state);
set(h.triggerCheckbox, 'Enable', state);
set(h.triggerSourcePopup, 'Enable', state);
set(h.triggerSlopePopup, 'Enable', state);
set(h.triggerLevelEdit, 'Enable', state);
set(h.calibrationCheckbox, 'Enable', state);
set(h.rawSaveCheckbox, 'Enable', state);
set(h.debugCheckbox, 'Enable', state);
set(h.timeStartEdit, 'Enable', state);
set(h.timeWindowEdit, 'Enable', state);
set(h.fftMaxEdit, 'Enable', state);
set(h.singleButton, 'Enable', state);
end

function set_status(fig, message)
if ~ishandle(fig)
    return;
end
app = guidata(fig);
set(app.handles.statusText, 'String', char(message));
end

function h = popup(parent, labels, values, y, selected)
if isstring(labels)
    labels = cellstr(labels);
end
idx = find_popup_index(values, selected);
h = uicontrol( ...
    'Parent', parent, ...
    'Style', 'popupmenu', ...
    'Units', 'normalized', ...
    'Position', [0.08 y 0.84 0.04], ...
    'String', labels, ...
    'Value', idx, ...
    'UserData', values, ...
    'BackgroundColor', 'w');
end

function idx = find_popup_index(values, selected)
idx = 1;
if isnumeric(values)
    found = find(abs(values - double(selected)) < 1e-12, 1);
else
    found = find(string(values) == string(selected), 1);
end
if ~isempty(found)
    idx = found;
end
end

function set_popup_to_value(handle, selected)
values = get(handle, 'UserData');
idx = find_popup_index(values, selected);
set(handle, 'Value', idx);
end

function value = popup_value(handle)
values = get(handle, 'UserData');
index = get(handle, 'Value');
value = values(index);
end

function h = editbox(parent, text, y)
h = uicontrol( ...
    'Parent', parent, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', [0.08 y 0.84 0.05], ...
    'String', char(text), ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');
end

function h = view_editbox(parent, text, position)
h = uicontrol( ...
    'Parent', parent, ...
    'Style', 'edit', ...
    'Units', 'normalized', ...
    'Position', position, ...
    'String', char(text), ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', 'w');
end

function label(parent, text, y)
uicontrol( ...
    'Parent', parent, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.08 y 0.84 0.035], ...
    'String', char(text), ...
    'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', get(parent, 'BackgroundColor'));
end

function view_label(parent, text, position)
uicontrol( ...
    'Parent', parent, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', position, ...
    'String', char(text), ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', get(parent, 'BackgroundColor'));
end

function value = read_positive_number(handle, labelText)
value = str2double(get(handle, 'String'));
if ~isfinite(value) || value <= 0
    error('%s debe ser un numero positivo.', char(labelText));
end
value = double(value);
end

function value = read_nonnegative_number(handle, labelText)
value = str2double(get(handle, 'String'));
if ~isfinite(value) || value < 0
    error('%s debe ser un numero mayor o igual a cero.', char(labelText));
end
value = double(value);
end

function value = read_optional_number(handle, labelText)
text = strtrim(string(get(handle, 'String')));
if strlength(text) == 0 || lower(text) == "auto"
    value = NaN;
    return;
end
value = str2double(text);
if ~isfinite(value)
    error('%s debe ser un numero o auto.', char(labelText));
end
value = double(value);
end

function index = trigger_source_index(value)
values = ["ch1", "ch2"];
index = find(string(values) == lower(string(value)), 1);
if isempty(index)
    index = 1;
end
end

function index = trigger_slope_index(value)
values = ["rising", "falling"];
text = lower(string(value));
if text == "rise"
    text = "rising";
elseif text == "fall"
    text = "falling";
end
index = find(values == text, 1);
if isempty(index)
    index = 1;
end
end

function out = make_log_path(projectRoot, prefix)
folder = fullfile(char(projectRoot), 'data', 'logs');
if ~exist(folder, 'dir')
    mkdir(folder);
end
out = fullfile(folder, [char(prefix) '_' datestr(now, 'yyyymmdd_HHMMSS') '.log']);
end

function fontName = fixed_width_font()
if ismac
    fontName = 'Menlo';
else
    fontName = 'Monospaced';
end
end

function projectRoot = default_project_root()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
end
