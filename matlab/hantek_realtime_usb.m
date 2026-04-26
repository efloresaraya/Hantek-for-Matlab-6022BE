function state = hantek_realtime_usb(varargin)
%HANTEK_REALTIME_USB Live MATLAB acquisition from the direct USB backend.
%
% This function captures repeated USB blocks through hantek_acquire("usb"),
% updates time/FFT plots, and prints compact live metrics in the MATLAB
% Command Window. Close the figure or press Ctrl+C to stop.

p = inputParser;
addParameter(p, "channel", 1, @(x) isnumeric(x) && isscalar(x) && any(x == [1 2]));
addParameter(p, "sampleRate", 1e6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "nSamples", 20000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "voltsPerDiv", 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "durationSec", inf, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "refreshPause", 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, "fftMaxHz", 10000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "projectRoot", default_project_root(), @(x) ischar(x) || isstring(x));
addParameter(p, "debugEcho", false, @(x) islogical(x) && isscalar(x));
addParameter(p, "debugLogPath", "", @(x) ischar(x) || isstring(x));
addParameter(p, "maxFailures", 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
parse(p, varargin{:});
opts = p.Results;

runLogPath = string(opts.debugLogPath);
if strlength(runLogPath) == 0
    stamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    runLogPath = fullfile(string(opts.projectRoot), "data", "logs", "matlab_realtime_" + stamp + ".log");
end

fig = figure("Name", "Hantek 6022BE Live USB", "Color", "w");

axTime = subplot(2, 1, 1);
timeLine = plot(axTime, nan, nan, "LineWidth", 1.1);
grid(axTime, "on");
xlabel(axTime, "Time (ms)");
ylabel(axTime, "Voltage (V)");
title(axTime, "Waiting for USB capture...");

axFft = subplot(2, 1, 2);
fftLine = plot(axFft, nan, nan, "LineWidth", 1.1);
grid(axFft, "on");
xlabel(axFft, "Frequency (Hz)");
ylabel(axFft, "Magnitude (V)");
title(axFft, "FFT");
xlim(axFft, [0 double(opts.fftMaxHz)]);

blockCount = 0;
consecutiveFailures = 0;
errors = strings(0, 1);
lastData = struct();
lastMetrics = struct();
startedAt = tic;

fprintf("Hantek live USB iniciado. Cierre la figura para detener.\n");
fprintf("CH%d | %.0f S/s | %d muestras | %.3g V/div\n", ...
    opts.channel, opts.sampleRate, opts.nSamples, opts.voltsPerDiv);
fprintf("Log USB: %s\n", runLogPath);

while ishandle(fig)
    if isfinite(double(opts.durationSec)) && toc(startedAt) >= double(opts.durationSec)
        break;
    end

    try
        data = hantek_acquire("usb", ...
            "channel", opts.channel, ...
            "sampleRate", opts.sampleRate, ...
            "nSamples", opts.nSamples, ...
            "voltsPerDiv", opts.voltsPerDiv, ...
            "projectRoot", opts.projectRoot, ...
            "debugEcho", opts.debugEcho, ...
            "debugLogPath", runLogPath);

        metrics = analyze_signal(data);
        [freq, magnitude] = compute_fft(data.voltage, data.sample_rate);
        fftMask = freq <= double(opts.fftMaxHz);

        set(timeLine, "XData", double(data.time(:)) * 1e3, "YData", double(data.voltage(:)));
        set(fftLine, "XData", freq(fftMask), "YData", magnitude(fftMask));

        title(axTime, sprintf("CH%d live | block %d | Vpp %.4g V | mean %.4g V", ...
            data.channel, blockCount + 1, metrics.vpp_v, metrics.mean_v));
        title(axFft, sprintf("FFT | dominant %.4g Hz | %.4g V", ...
            metrics.dominant_frequency_hz, metrics.dominant_magnitude_v));

        blockCount = blockCount + 1;
        consecutiveFailures = 0;
        lastData = data;
        lastMetrics = metrics;

        fprintf("%s block=%d CH%d Vpp=%.4g V mean=%.4g V fdom=%.4g Hz\n", ...
            char(datetime("now", "Format", "HH:mm:ss")), ...
            blockCount, data.channel, metrics.vpp_v, metrics.mean_v, metrics.dominant_frequency_hz);

        drawnow limitrate;
    catch ME
        consecutiveFailures = consecutiveFailures + 1;
        errors(end + 1, 1) = string(ME.message);
        fprintf("%s ERROR block=%d fail=%d/%d: %s\n", ...
            char(datetime("now", "Format", "HH:mm:ss")), ...
            blockCount + 1, consecutiveFailures, opts.maxFailures, ME.message);
        drawnow limitrate;
        if consecutiveFailures >= double(opts.maxFailures)
            break;
        end
    end

    pause(double(opts.refreshPause));
end

state = struct();
state.block_count = blockCount;
state.error_count = numel(errors);
state.errors = errors;
state.last_data = lastData;
state.last_metrics = lastMetrics;
state.log_path = runLogPath;

fprintf("Hantek live USB detenido. Bloques OK: %d | errores: %d\n", ...
    state.block_count, state.error_count);
end

function projectRoot = default_project_root()
thisFile = mfilename("fullpath");
projectRoot = fileparts(fileparts(thisFile));
end
