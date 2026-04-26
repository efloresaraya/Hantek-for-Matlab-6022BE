function paths = save_dual_capture_bundle(data, metrics, config, outputDir, baseName, logPath)
%SAVE_DUAL_CAPTURE_BUNDLE Save CH1+CH2 capture as MAT, CSV and PNG report.

if nargin < 2 || isempty(metrics)
    metrics = analyze_dual_signal(data);
end
if nargin < 3 || isempty(config)
    config = struct();
end
if nargin < 4 || strlength(string(outputDir)) == 0
    outputDir = fullfile(default_project_root(), 'data', 'processed');
end
if nargin < 5 || strlength(string(baseName)) == 0
    baseName = ['hantek_dual_' datestr(now, 'yyyymmdd_HHMMSS')];
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
rawCsvPath = fullfile(outputDir, [baseName '_raw.csv']);

data = normalize_dual_data(data);
writeRawCsv = isfield(config, 'saveRawCsv') && logical(config.saveRawCsv);
includeRawInMain = has_raw_dual(data) && isfield(data, 'calibration_applied') && logical(data.calibration_applied);
write_dual_csv(data, csvPath, false, includeRawInMain);
if writeRawCsv && has_raw_dual(data)
    write_dual_csv(data, rawCsvPath, true, false);
end
write_dual_report_png(data, metrics, config, pngPath);

paths = struct();
paths.mat = string(matPath);
paths.csv = string(csvPath);
paths.png = string(pngPath);
paths.log = string(logPath);
if writeRawCsv && has_raw_dual(data)
    paths.raw_csv = string(rawCsvPath);
end

save(matPath, 'data', 'metrics', 'config', 'logPath', 'paths');
end

function data = normalize_dual_data(data)
data.time = double(data.time(:));
data.ch1 = double(data.ch1(:));
data.ch2 = double(data.ch2(:));
n = min([numel(data.time), numel(data.ch1), numel(data.ch2)]);
data.time = data.time(1:n);
data.ch1 = data.ch1(1:n);
data.ch2 = data.ch2(1:n);
data.n_samples = n;
if isfield(data, 'raw_ch1') && isfield(data, 'raw_ch2')
    data.raw_ch1 = double(data.raw_ch1(:));
    data.raw_ch2 = double(data.raw_ch2(:));
    nr = min([n, numel(data.raw_ch1), numel(data.raw_ch2)]);
    data.raw_ch1 = data.raw_ch1(1:nr);
    data.raw_ch2 = data.raw_ch2(1:nr);
end
end

function write_dual_csv(data, csvPath, useRaw, includeRawInMain)
if useRaw
    n = min([numel(data.time), numel(data.raw_ch1), numel(data.raw_ch2)]);
    tbl = table(data.time(1:n), data.raw_ch1(1:n), data.raw_ch2(1:n), ...
        'VariableNames', {'t_s', 'CH1_raw_V', 'CH2_raw_V'});
elseif includeRawInMain && has_raw_dual(data)
    n = min([numel(data.time), numel(data.ch1), numel(data.ch2), numel(data.raw_ch1), numel(data.raw_ch2)]);
    tbl = table(data.time(1:n), data.ch1(1:n), data.ch2(1:n), data.raw_ch1(1:n), data.raw_ch2(1:n), ...
        'VariableNames', {'t_s', 'CH1_V', 'CH2_V', 'CH1_raw_V', 'CH2_raw_V'});
else
    n = min([numel(data.time), numel(data.ch1), numel(data.ch2)]);
    tbl = table(data.time(1:n), data.ch1(1:n), data.ch2(1:n), ...
        'VariableNames', {'t_s', 'CH1_V', 'CH2_V'});
end
writetable(tbl, char(csvPath));
end

function write_dual_report_png(data, metrics, config, pngPath)
timeMs = double(data.time(:)) * 1e3;
sampleRate = double(data.sample_rate);
[freq1, mag1] = compute_fft(data.ch1, sampleRate);
[freq2, mag2] = compute_fft(data.ch2, sampleRate);
fftMaxHz = sampleRate / 2;
if isfield(config, 'fftMaxHz') && isfinite(double(config.fftMaxHz)) && double(config.fftMaxHz) > 0
    fftMaxHz = min(sampleRate / 2, double(config.fftMaxHz));
end
timeWindowMs = min(max(timeMs) - min(timeMs), 10);
if isfield(config, 'timeWindowMs') && isfinite(double(config.timeWindowMs)) && double(config.timeWindowMs) > 0
    timeWindowMs = min(max(timeMs) - min(timeMs), double(config.timeWindowMs));
end
calibrationLabel = '';
if isfield(data, 'calibration_applied') && logical(data.calibration_applied)
    calibrationLabel = ' | cal sw';
end

fig = figure('Name', 'Hantek dual capture report', 'Color', 'w', 'Visible', 'off');
set(fig, 'Position', [100 100 1300 900]);

subplot(3, 1, 1);
plot(timeMs, data.ch1, 'LineWidth', 1.0);
hold on;
plot(timeMs, data.ch2, 'LineWidth', 1.0);
if has_raw_dual(data) && isfield(config, 'plotRawOverlay') && logical(config.plotRawOverlay)
    plot(timeMs, data.raw_ch1, '--', 'LineWidth', 0.8);
    plot(timeMs, data.raw_ch2, '--', 'LineWidth', 0.8);
end
hold off;
grid on;
xlabel('Time (ms)');
ylabel('Voltage (V)');
if has_raw_dual(data) && isfield(config, 'plotRawOverlay') && logical(config.plotRawOverlay)
    legend({'CH1 cal', 'CH2 cal', 'CH1 raw', 'CH2 raw'}, 'Location', 'best');
else
    legend({'CH1', 'CH2'}, 'Location', 'best');
end
title(sprintf('Dual time domain | %.4g S/s | %d samples%s', ...
    sampleRate, numel(data.time), calibrationLabel));
if isfinite(timeWindowMs) && timeWindowMs > 0
    xlim([min(timeMs), min(timeMs) + timeWindowMs]);
end

subplot(3, 1, 2);
plot(freq1, mag1, 'LineWidth', 1.0);
hold on;
plot(freq2, mag2, 'LineWidth', 1.0);
hold off;
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (V)');
legend({'CH1', 'CH2'}, 'Location', 'best');
title(sprintf('FFT | 0..%.4g Hz', fftMaxHz));
xlim([0 fftMaxHz]);

subplot(3, 1, 3);
axis off;
text(0.02, 0.94, metrics_text(metrics), ...
    'FontName', fixed_width_font(), ...
    'FontSize', 11, ...
    'VerticalAlignment', 'top');

print(fig, char(pngPath), '-dpng', '-r150');
close(fig);
end

function tf = has_raw_dual(data)
tf = isfield(data, 'raw_ch1') && isfield(data, 'raw_ch2') && ...
    ~isempty(data.raw_ch1) && ~isempty(data.raw_ch2);
end

function textOut = metrics_text(metrics)
textOut = sprintf([ ...
    'CH1 Vpp:      %.6g V     CH2 Vpp:      %.6g V\n' ...
    'CH1 mean:     %.6g V     CH2 mean:     %.6g V\n' ...
    'CH1 freq:     %.6g Hz    CH2 freq:     %.6g Hz\n' ...
    'CH1 duty:     %.6g %%     CH2 duty:     %.6g %%\n' ...
    'CH1 Tjit:     %.6g %%     CH2 Tjit:     %.6g %%\n' ...
    'Delay CH2-CH1 %.6g ms    Phase:        %.6g deg\n' ...
    'Matched edges: %d'], ...
    metrics.ch1.vpp_v, metrics.ch2.vpp_v, ...
    metrics.ch1.mean_v, metrics.ch2.mean_v, ...
    metrics.ch1.rising_frequency_hz, metrics.ch2.rising_frequency_hz, ...
    metrics.ch1.duty_cycle_pct, metrics.ch2.duty_cycle_pct, ...
    metrics.ch1.rising_period_spread_pct, metrics.ch2.rising_period_spread_pct, ...
    metrics.delay_ch2_minus_ch1_ms, metrics.phase_ch2_minus_ch1_deg, ...
    metrics.delay_matched_edges);
end

function name = sanitize_base_name(name)
name = regexprep(name, '[^A-Za-z0-9_\-]', '_');
if isempty(name)
    name = ['hantek_dual_' datestr(now, 'yyyymmdd_HHMMSS')];
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
