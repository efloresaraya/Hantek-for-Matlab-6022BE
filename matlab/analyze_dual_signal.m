function metrics = analyze_dual_signal(data)
%ANALYZE_DUAL_SIGNAL Compute metrics for one CH1+CH2 capture.

data = normalize_dual_data(data);

metrics = struct();
metrics.ch1 = analyze_signal(data.time, data.ch1, data.sample_rate);
metrics.ch2 = analyze_signal(data.time, data.ch2, data.sample_rate);

edges1 = rising_edge_times(data.time, data.ch1);
edges2 = rising_edge_times(data.time, data.ch2);
[delayMs, delayStdMs, matchedEdges] = edge_delay_ms(edges1, edges2, metrics.ch1.rising_period_median_ms);

metrics.delay_ch2_minus_ch1_ms = delayMs;
metrics.delay_std_ms = delayStdMs;
metrics.delay_matched_edges = matchedEdges;
metrics.phase_ch2_minus_ch1_deg = NaN;

periodMs = metrics.ch1.rising_period_median_ms;
if ~isfinite(periodMs) || periodMs <= 0
    periodMs = metrics.ch2.rising_period_median_ms;
end
if isfinite(delayMs) && isfinite(periodMs) && periodMs > 0
    metrics.phase_ch2_minus_ch1_deg = 360 * delayMs / periodMs;
end
end

function data = normalize_dual_data(data)
data.time = double(data.time(:));
data.ch1 = double(data.ch1(:));
data.ch2 = double(data.ch2(:));
n = min([numel(data.time), numel(data.ch1), numel(data.ch2)]);
if n == 0
    error('analyze_dual_signal:EmptyCapture', 'Dual capture is empty.');
end
data.time = data.time(1:n);
data.ch1 = data.ch1(1:n);
data.ch2 = data.ch2(1:n);
data.n_samples = n;
end

function edgeTimes = rising_edge_times(time, voltage)
time = double(time(:));
voltage = double(voltage(:));
n = min(numel(time), numel(voltage));
edgeTimes = [];
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
    elseif value <= low
        armed = true;
    elseif armed && value >= level
        edgeIdx(end + 1, 1) = i; %#ok<AGROW>
        armed = false;
    end
end
edgeTimes = time(edgeIdx);
end

function [delayMs, delayStdMs, matchedEdges] = edge_delay_ms(edges1, edges2, periodMs)
delayMs = NaN;
delayStdMs = NaN;
matchedEdges = 0;
if numel(edges1) < 1 || numel(edges2) < 1
    return;
end

if ~isfinite(periodMs) || periodMs <= 0
    maxDistanceS = Inf;
else
    maxDistanceS = 0.40 * periodMs / 1e3;
end

delays = [];
for k = 1:numel(edges1)
    [distance, idx] = min(abs(edges2 - edges1(k)));
    if isempty(distance) || ~isfinite(distance)
        continue;
    end
    if distance <= maxDistanceS
        delays(end + 1, 1) = (edges2(idx) - edges1(k)) * 1e3; %#ok<AGROW>
    end
end

matchedEdges = numel(delays);
if matchedEdges == 0
    return;
end
delayMs = median(delays);
if matchedEdges > 1
    delayStdMs = std(delays);
else
    delayStdMs = 0;
end
end
