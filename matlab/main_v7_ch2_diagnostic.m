% MAIN_V7_CH2_DIAGNOSTIC Capture CH1 and CH2 from the same dual USB block.
%
% Use this when CH1 looks stable but CH2 appears to have irregular pulse
% widths. The script captures both channels in one hardware acquisition so the
% comparison is apples-to-apples.

clear; clc;

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
addpath(scriptDir);

sampleRate = 10e6;
nSamples = 100000;
voltsPerDiv = 1.0;

pythonDir = fullfile(projectRoot, 'python');
ensure_python_path(pythonDir);
py.importlib.invalidate_caches();
module = py.importlib.import_module('hantek_usb_backend');
module = py.importlib.reload(module);
backendFile = string(py.getattr(module, '__file__'));
fprintf('Backend Python: %s\n', char(backendFile));

logPath = fullfile(projectRoot, 'data', 'logs', ...
    ['matlab_dual_diag_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '.log']);

backend = module.Hantek6022USBBackend(pyargs( ...
    'project_root', char(projectRoot), ...
    'debug_log_path', char(logPath), ...
    'debug_echo', false));
cleanupObj = onCleanup(@() backend.close()); %#ok<NASGU>

fprintf('Capturando CH1+CH2 en el mismo bloque USB...\n');
acquireDual = py.getattr(backend, 'acquire_dual');
capture = acquireDual(pyargs( ...
    'sample_rate', double(sampleRate), ...
    'n_samples', int32(nSamples), ...
    'volts_per_div', double(voltsPerDiv)));

data = py_dual_capture_to_struct(capture);
data = normalize_dual_lengths(data);
m1 = analyze_signal(data.time, data.ch1, data.sample_rate);
m2 = analyze_signal(data.time, data.ch2, data.sample_rate);

csvPath = fullfile(projectRoot, 'data', 'raw', ...
    ['dual_diag_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '.csv']);
tbl = table(data.time(:), data.ch1(:), data.ch2(:), ...
    'VariableNames', {'t_s', 'CH1_V', 'CH2_V'});
writetable(tbl, char(csvPath));

fprintf('\nCSV: %s\n', char(csvPath));
fprintf('Log: %s\n\n', char(logPath));
print_metrics('CH1', m1);
print_metrics('CH2', m2);

figure('Name', 'Hantek dual-channel diagnostic', 'Color', 'w');
tMs = data.time * 1e3;

subplot(2, 1, 1);
plot(tMs, data.ch1, 'LineWidth', 1.0);
grid on;
xlim([0 5]);
ylim([-2.5 2.5]);
title(sprintf('CH1 | Vpp %.4g V | Tmed %.4g ms | Tjit %.4g %%' , ...
    m1.vpp_v, m1.rising_period_median_ms, m1.rising_period_spread_pct));
xlabel('Time (ms)');
ylabel('Voltage (V)');

subplot(2, 1, 2);
plot(tMs, data.ch2, 'LineWidth', 1.0);
grid on;
xlim([0 5]);
ylim([-2.5 2.5]);
title(sprintf('CH2 | Vpp %.4g V | Tmed %.4g ms | Tjit %.4g %%' , ...
    m2.vpp_v, m2.rising_period_median_ms, m2.rising_period_spread_pct));
xlabel('Time (ms)');
ylabel('Voltage (V)');

function ensure_python_path(pythonDir)
pythonDir = char(pythonDir);
pyPath = py.sys.path;
if int64(pyPath.count(pythonDir)) == 0
    pyPath.insert(int32(0), pythonDir);
end
end

function data = py_dual_capture_to_struct(capture)
data = struct();
data.time = py_list_to_double(capture.get('time'));
data.ch1 = py_list_to_double(capture.get('ch1'));
data.ch2 = py_list_to_double(capture.get('ch2'));
data.sample_rate = double(capture.get('sample_rate'));
data.n_samples = double(capture.get('n_samples'));
data.source = string(capture.get('source'));
end

function data = normalize_dual_lengths(data)
nTime = numel(data.time);
nCh1 = numel(data.ch1);
nCh2 = numel(data.ch2);
n = min([nTime, nCh1, nCh2]);
if n == 0
    error('main_v7_ch2_diagnostic:EmptyCapture', ...
        'La captura dual llego vacia: time=%d, ch1=%d, ch2=%d.', nTime, nCh1, nCh2);
end
if nTime ~= nCh1 || nTime ~= nCh2
    warning('main_v7_ch2_diagnostic:LengthMismatch', ...
        'Longitudes distintas en captura dual; se recorta a %d muestras. time=%d, ch1=%d, ch2=%d.', ...
        n, nTime, nCh1, nCh2);
end
data.time = data.time(1:n);
data.ch1 = data.ch1(1:n);
data.ch2 = data.ch2(1:n);
data.n_samples = n;
end

function values = py_list_to_double(pyValues)
values = double(py.array.array('d', pyValues));
values = values(:);
end

function print_metrics(name, metrics)
fprintf('%s:\n', name);
fprintf('  Vpp: %.6g V\n', metrics.vpp_v);
fprintf('  Fdom: %.6g Hz\n', metrics.dominant_frequency_hz);
fprintf('  edges: %d\n', metrics.rising_edge_count);
fprintf('  Tmed: %.6g ms\n', metrics.rising_period_median_ms);
fprintf('  Tmin: %.6g ms\n', metrics.rising_period_min_ms);
fprintf('  Tmax: %.6g ms\n', metrics.rising_period_max_ms);
fprintf('  Tjit: %.6g %%\n\n', metrics.rising_period_spread_pct);
end
