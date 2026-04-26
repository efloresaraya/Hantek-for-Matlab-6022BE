function [freq, magnitude] = compute_fft(voltage, sampleRate)
%COMPUTE_FFT Compute single-sided FFT magnitude.

voltage = double(voltage(:));
sampleRate = double(sampleRate);
n = numel(voltage);

if n == 0
    freq = [];
    magnitude = [];
    return;
end

voltage = voltage - mean(voltage, "omitnan");
if n > 1
    window = 0.5 - 0.5 * cos(2*pi*(0:n-1).'/(n-1));
else
    window = ones(n, 1);
end

coherentGain = sum(window) / n;
spectrum = fft(voltage .* window);
halfCount = floor(n / 2) + 1;
spectrum = spectrum(1:halfCount);

magnitude = abs(spectrum) * 2 / max(n * coherentGain, eps);
freq = (0:halfCount-1).' * sampleRate / n;
end
