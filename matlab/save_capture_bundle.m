function paths = save_capture_bundle(data, metrics, config, outputDir, baseName, logPath)
%SAVE_CAPTURE_BUNDLE Save one capture as MAT, CSV and PNG report.

if nargin < 2 || isempty(metrics)
    metrics = analyze_signal(data);
end
if nargin < 3 || isempty(config)
    config = struct();
end
if nargin < 4 || strlength(string(outputDir)) == 0
    outputDir = fullfile(default_project_root(), 'data', 'processed');
end
if nargin < 5 || strlength(string(baseName)) == 0
    baseName = ['hantek_capture_' datestr(now, 'yyyymmdd_HHMMSS')];
end
if nargin < 6
    logPath = '';
end

outputDir = char(outputDir);
baseName = sanitize_base_name(char(baseName));
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

matPath = fullfile(outputDir, [baseName '.mat']);
csvPath = fullfile(outputDir, [baseName '.csv']);
pngPath = fullfile(outputDir, [baseName '.png']);

data = normalize_capture_vectors(data);
write_capture_csv(data, csvPath);
write_report_png(data, metrics, pngPath);

paths = struct();
paths.mat = string(matPath);
paths.csv = string(csvPath);
paths.png = string(pngPath);
paths.log = string(logPath);

save(matPath, 'data', 'metrics', 'config', 'logPath', 'paths');
end

function data = normalize_capture_vectors(data)
data.time = double(data.time(:));
data.voltage = double(data.voltage(:));
n = min(numel(data.time), numel(data.voltage));
data.time = data.time(1:n);
data.voltage = data.voltage(1:n);
data.n_samples = n;
end

function write_capture_csv(data, csvPath)
channel = 1;
if isfield(data, 'channel') && ~isempty(data.channel)
    channel = data.channel;
end
voltageName = sprintf('CH%d_V', round(double(channel)));
tbl = table(data.time(:), data.voltage(:), ...
    'VariableNames', {'t_s', voltageName});
writetable(tbl, char(csvPath));
end

function write_report_png(data, metrics, pngPath)
time = double(data.time(:));
voltage = double(data.voltage(:));
sampleRate = double(data.sample_rate);
channel = 1;
if isfield(data, 'channel') && ~isempty(data.channel)
    channel = data.channel;
end
channelNumber = round(double(channel));
calibrationLabel = '';
if isfield(data, 'calibration_applied') && logical(data.calibration_applied)
    calibrationLabel = ' | cal sw';
end
[freq, magnitude] = compute_fft(voltage, sampleRate);

fig = figure('Name', 'Hantek capture report', 'Color', 'w', 'Visible', 'off');
set(fig, 'Position', [100 100 1200 800]);

subplot(3, 1, 1);
plot(time * 1e3, voltage, 'LineWidth', 1.0);
grid on;
xlabel('Time (ms)');
ylabel('Voltage (V)');
title(sprintf('Time domain | CH%d | %.4g S/s | %d samples%s', ...
    channelNumber, sampleRate, numel(voltage), calibrationLabel));

subplot(3, 1, 2);
plot(freq, magnitude, 'LineWidth', 1.0);
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (V)');
title('FFT');

subplot(3, 1, 3);
axis off;
text(0.02, 0.90, metrics_text(metrics), ...
    'FontName', fixed_width_font(), ...
    'FontSize', 11, ...
    'VerticalAlignment', 'top');

print(fig, char(pngPath), '-dpng', '-r150');
close(fig);
end

function textOut = metrics_text(metrics)
textOut = sprintf([ ...
    'Vpp:      %.6g V\n' ...
    'Mean:     %.6g V\n' ...
    'RMS:      %.6g V\n' ...
    'Min:      %.6g V\n' ...
    'Max:      %.6g V\n' ...
    'Fdom:     %.6g Hz\n' ...
    'Edges:    %d\n' ...
    'Tmed:     %.6g ms\n' ...
    'Tmin:     %.6g ms\n' ...
    'Tmax:     %.6g ms\n' ...
    'Tjit:     %.6g %%'], ...
    metrics.vpp_v, metrics.mean_v, metrics.rms_v, metrics.min_v, metrics.max_v, ...
    metrics.dominant_frequency_hz, metrics.rising_edge_count, ...
    metrics.rising_period_median_ms, metrics.rising_period_min_ms, ...
    metrics.rising_period_max_ms, metrics.rising_period_spread_pct);
end

function name = sanitize_base_name(name)
name = regexprep(name, '[^A-Za-z0-9_\-]', '_');
if isempty(name)
    name = ['hantek_capture_' datestr(now, 'yyyymmdd_HHMMSS')];
end
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
