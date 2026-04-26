function metrics = analyze_signal(dataOrTime, voltage, sampleRate)
%ANALYZE_SIGNAL Compute basic signal metrics.

if nargin == 1 && isstruct(dataOrTime)
    data = dataOrTime;
    time = data.time;
    voltage = data.voltage;
    if isfield(data, "sample_rate")
        sampleRate = data.sample_rate;
    else
        sampleRate = infer_sample_rate(time);
    end
else
    time = dataOrTime;
    if nargin < 3 || isempty(sampleRate)
        sampleRate = infer_sample_rate(time);
    end
end

time = double(time(:));
voltage = double(voltage(:));
sampleRate = double(sampleRate);

metrics = struct();
metrics.n_samples = numel(voltage);
metrics.sample_rate_hz = sampleRate;
metrics.duration_s = time(end) - time(1);
metrics.mean_v = mean(voltage, "omitnan");
metrics.rms_v = sqrt(mean(voltage.^2, "omitnan"));
metrics.min_v = min(voltage);
metrics.max_v = max(voltage);
metrics.vpp_v = metrics.max_v - metrics.min_v;

[freq, mag] = compute_fft(voltage, sampleRate);
if numel(mag) > 1
    [~, idx] = max(mag(2:end));
    metrics.dominant_frequency_hz = freq(idx + 1);
    metrics.dominant_magnitude_v = mag(idx + 1);
else
    metrics.dominant_frequency_hz = NaN;
    metrics.dominant_magnitude_v = NaN;
end

edge = rising_edge_metrics(time, voltage);
metrics.rising_edge_count = edge.count;
metrics.rising_period_median_ms = edge.period_median_ms;
metrics.rising_period_min_ms = edge.period_min_ms;
metrics.rising_period_max_ms = edge.period_max_ms;
metrics.rising_period_spread_pct = edge.period_spread_pct;
metrics.rising_frequency_hz = edge.frequency_hz;

square = square_wave_metrics(voltage);
metrics.low_level_v = square.low_level_v;
metrics.high_level_v = square.high_level_v;
metrics.mid_level_v = square.mid_level_v;
metrics.duty_cycle_pct = square.duty_cycle_pct;
end

function sampleRate = infer_sample_rate(time)
time = double(time(:));
if numel(time) < 2
    sampleRate = NaN;
    return;
end
dt = median(diff(time));
sampleRate = 1 ./ dt;
end

function edge = rising_edge_metrics(time, voltage)
edge = struct( ...
    "count", 0, ...
    "period_median_ms", NaN, ...
    "period_min_ms", NaN, ...
    "period_max_ms", NaN, ...
    "period_spread_pct", NaN, ...
    "frequency_hz", NaN);

time = double(time(:));
voltage = double(voltage(:));
n = min(numel(time), numel(voltage));
if n < 3
    return;
end
time = time(1:n);
voltage = voltage(1:n);

finiteVoltage = voltage(isfinite(voltage));
if isempty(finiteVoltage)
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
hysteresis = max(0.02, 0.08 * amplitude);
low = level - hysteresis;

armed = false;
edgeIdx = [];
for i = 1:n
    value = voltage(i);
    if ~isfinite(value)
        armed = false;
        continue;
    end
    if value <= low
        armed = true;
    elseif armed && value >= level
        edgeIdx(end + 1, 1) = i; %#ok<AGROW>
        armed = false;
    end
end

edge.count = numel(edgeIdx);
if numel(edgeIdx) < 2
    return;
end
periodsMs = diff(time(edgeIdx)) * 1e3;
periodsMs = periodsMs(isfinite(periodsMs) & periodsMs > 0);
if isempty(periodsMs)
    return;
end
edge.period_median_ms = median(periodsMs);
edge.period_min_ms = min(periodsMs);
edge.period_max_ms = max(periodsMs);
edge.period_spread_pct = 100 * (edge.period_max_ms - edge.period_min_ms) / edge.period_median_ms;
edge.frequency_hz = 1000 / edge.period_median_ms;
end

function square = square_wave_metrics(voltage)
square = struct( ...
    'low_level_v', NaN, ...
    'high_level_v', NaN, ...
    'mid_level_v', NaN, ...
    'duty_cycle_pct', NaN);

voltage = double(voltage(:));
voltage = voltage(isfinite(voltage));
if numel(voltage) < 3
    return;
end

sortedVoltage = sort(voltage);
n = numel(sortedVoltage);
lowBand = sortedVoltage(1:max(1, round(0.20 * n)));
highBand = sortedVoltage(max(1, round(0.80 * n)):end);
lowLevel = median(lowBand);
highLevel = median(highBand);
midLevel = (lowLevel + highLevel) / 2;

square.low_level_v = lowLevel;
square.high_level_v = highLevel;
square.mid_level_v = midLevel;
if isfinite(midLevel) && highLevel > lowLevel
    square.duty_cycle_pct = 100 * mean(voltage >= midLevel);
end
end
