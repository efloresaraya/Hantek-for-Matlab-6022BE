function plot_signal_report(data, metrics)
%PLOT_SIGNAL_REPORT Plot time-domain and frequency-domain views.

if nargin < 2 || isempty(metrics)
    metrics = analyze_signal(data);
end

time = double(data.time(:));
voltage = double(data.voltage(:));
sampleRate = double(data.sample_rate);
[freq, magnitude] = compute_fft(voltage, sampleRate);

figure("Name", "Hantek 6022BE Signal Report", "Color", "w");

subplot(2, 1, 1);
plot(time, voltage, "LineWidth", 1.1);
grid on;
xlabel("Time (s)");
ylabel("Voltage (V)");
title("Capture - " + string(data.source));

subplot(2, 1, 2);
plot(freq, magnitude, "LineWidth", 1.1);
grid on;
xlabel("Frequency (Hz)");
ylabel("Magnitude (V)");
title(sprintf("FFT | Vpp %.3g V | RMS %.3g V | Dominant %.3g Hz", ...
    metrics.vpp_v, metrics.rms_v, metrics.dominant_frequency_hz));
end

