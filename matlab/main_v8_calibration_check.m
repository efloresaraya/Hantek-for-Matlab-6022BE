% MAIN_V8_CALIBRATION_CHECK Non-destructive offset/gain check.
%
% Connect the selected channel to the Hantek calibrator with the probe at 1x.
% This script captures one block, estimates square-wave levels, saves a report,
% and prints suggested display corrections. It does not write EEPROM.
%
% Optional before running:
%   calibrationChannel = 2;
%   run("matlab/main_v8_calibration_check.m")

clearvars -except calibrationChannel calibrationSampleRate calibrationNSamples ...
    calibrationVoltsPerDiv calibrationExpectedLowV calibrationExpectedHighV ...
    calibrationExpectedFrequencyHz
clc;

scriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);
addpath(scriptDir);

if ~exist('calibrationChannel', 'var'), calibrationChannel = 1; end
if ~exist('calibrationSampleRate', 'var'), calibrationSampleRate = 10e6; end
if ~exist('calibrationNSamples', 'var'), calibrationNSamples = 100000; end
if ~exist('calibrationVoltsPerDiv', 'var'), calibrationVoltsPerDiv = 1.0; end
if ~exist('calibrationExpectedLowV', 'var'), calibrationExpectedLowV = 0.0; end
if ~exist('calibrationExpectedHighV', 'var'), calibrationExpectedHighV = 2.0; end
if ~exist('calibrationExpectedFrequencyHz', 'var'), calibrationExpectedFrequencyHz = 1000.0; end

channel = round(double(calibrationChannel));
sampleRate = double(calibrationSampleRate);
nSamples = round(double(calibrationNSamples));
voltsPerDiv = double(calibrationVoltsPerDiv);
expectedLowV = double(calibrationExpectedLowV);
expectedHighV = double(calibrationExpectedHighV);
expectedFrequencyHz = double(calibrationExpectedFrequencyHz);

if ~ismember(channel, [1 2])
    error('main_v8_calibration_check:InvalidChannel', ...
        'calibrationChannel must be 1 or 2.');
end

fprintf('Non-destructive calibration check\n');
fprintf('Channel: CH%d | expected %.4g..%.4g V | %.4g Hz\n', ...
    channel, expectedLowV, expectedHighV, expectedFrequencyHz);

data = hantek_acquire('usb', ...
    'channel', channel, ...
    'sampleRate', sampleRate, ...
    'nSamples', nSamples, ...
    'voltsPerDiv', voltsPerDiv, ...
    'projectRoot', projectRoot, ...
    'debugEcho', false);

metrics = analyze_signal(data);
levels = estimate_square_levels(data.voltage);
expectedVpp = expectedHighV - expectedLowV;
measuredVpp = levels.high_v - levels.low_v;

if ~isfinite(measuredVpp) || measuredVpp <= 0
    error('main_v8_calibration_check:InvalidVpp', ...
        'Measured Vpp is invalid: %.6g V. Check probe, channel and calibrator connection.', ...
        measuredVpp);
end

gainCorrection = expectedVpp / measuredVpp;
offsetCorrection = expectedLowV - levels.low_v * gainCorrection;
frequencyErrorPct = 100 * (metrics.rising_frequency_hz - expectedFrequencyHz) / expectedFrequencyHz;

calibration = struct();
calibration.channel = channel;
calibration.expected_low_v = expectedLowV;
calibration.expected_high_v = expectedHighV;
calibration.expected_frequency_hz = expectedFrequencyHz;
calibration.measured_low_v = levels.low_v;
calibration.measured_high_v = levels.high_v;
calibration.measured_vpp_v = measuredVpp;
calibration.measured_frequency_hz = metrics.rising_frequency_hz;
calibration.gain_correction_suggestion = gainCorrection;
calibration.offset_correction_suggestion_v = offsetCorrection;
calibration.frequency_error_pct = frequencyErrorPct;
calibration.note = 'Display-only suggestion; EEPROM is not written.';

outputDir = fullfile(projectRoot, 'data', 'processed');
baseName = sprintf('calibration_check_ch%d_%s', channel, datestr(now, 'yyyymmdd_HHMMSS'));
paths = save_capture_bundle(data, metrics, calibration, outputDir, baseName, '');
summaryPath = fullfile(outputDir, [baseName '_summary.txt']);
write_summary(summaryPath, calibration, metrics, paths);
calibrationPath = fullfile(projectRoot, 'data', 'software_calibration.json');
write_software_calibration(calibrationPath, calibration, summaryPath);

fprintf('\nMeasured low/high: %.6g V / %.6g V\n', levels.low_v, levels.high_v);
fprintf('Measured Vpp:      %.6g V\n', measuredVpp);
fprintf('Measured freq:     %.6g Hz\n', metrics.rising_frequency_hz);
fprintf('Suggested gain:    %.6g\n', gainCorrection);
fprintf('Suggested offset:  %.6g V\n', offsetCorrection);
fprintf('Frequency error:   %.6g %%\n', frequencyErrorPct);
fprintf('\nSaved:\n');
fprintf('  MAT: %s\n', char(paths.mat));
fprintf('  CSV: %s\n', char(paths.csv));
fprintf('  PNG: %s\n', char(paths.png));
fprintf('  TXT: %s\n', summaryPath);
fprintf('  CAL: %s\n', calibrationPath);

function levels = estimate_square_levels(voltage)
voltage = double(voltage(:));
voltage = voltage(isfinite(voltage));
if isempty(voltage)
    error('main_v8_calibration_check:EmptyCapture', 'No finite voltage samples.');
end
sortedVoltage = sort(voltage);
n = numel(sortedVoltage);
lowBand = sortedVoltage(1:max(1, round(0.20 * n)));
highBand = sortedVoltage(max(1, round(0.80 * n)):end);
levels = struct();
levels.low_v = median(lowBand);
levels.high_v = median(highBand);
end

function write_summary(path, calibration, metrics, paths)
fid = fopen(path, 'w');
if fid < 0
    error('main_v8_calibration_check:SummaryWriteFailed', 'Could not write %s.', path);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'Hantek 6022BE non-destructive calibration check\n');
fprintf(fid, 'Channel: CH%d\n', calibration.channel);
fprintf(fid, 'Expected low/high: %.8g V / %.8g V\n', calibration.expected_low_v, calibration.expected_high_v);
fprintf(fid, 'Measured low/high: %.8g V / %.8g V\n', calibration.measured_low_v, calibration.measured_high_v);
fprintf(fid, 'Measured Vpp: %.8g V\n', calibration.measured_vpp_v);
fprintf(fid, 'Measured frequency: %.8g Hz\n', calibration.measured_frequency_hz);
fprintf(fid, 'Frequency error: %.8g %%\n', calibration.frequency_error_pct);
fprintf(fid, 'Suggested gain correction: %.8g\n', calibration.gain_correction_suggestion);
fprintf(fid, 'Suggested offset correction: %.8g V\n', calibration.offset_correction_suggestion_v);
fprintf(fid, 'Tjit: %.8g %%\n', metrics.rising_period_spread_pct);
fprintf(fid, '\nNo EEPROM write was performed.\n');
fprintf(fid, '\nFiles:\n');
fprintf(fid, 'MAT: %s\n', char(paths.mat));
fprintf(fid, 'CSV: %s\n', char(paths.csv));
fprintf(fid, 'PNG: %s\n', char(paths.png));
end

function write_software_calibration(path, calibration, summaryPath)
config = struct();
if isfile(path)
    raw = strtrim(fileread(path));
    if strlength(string(raw)) > 0
        config = jsondecode(raw);
    end
end

if ~isfield(config, 'schema')
    config.schema = 'hantek6022be-software-calibration-v1';
end
config.updated_at = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
config.source = 'matlab/main_v8_calibration_check.m';
config.notes = 'Software-only display/analysis correction. No EEPROM write is performed.';
if ~isfield(config, 'channels') || ~isstruct(config.channels)
    config.channels = struct();
end

entry = struct();
entry.enabled = true;
entry.gain = calibration.gain_correction_suggestion;
entry.offset_v = calibration.offset_correction_suggestion_v;
entry.expected_low_v = calibration.expected_low_v;
entry.expected_high_v = calibration.expected_high_v;
entry.measured_low_v = calibration.measured_low_v;
entry.measured_high_v = calibration.measured_high_v;
entry.measured_vpp_v = calibration.measured_vpp_v;
entry.measured_frequency_hz = calibration.measured_frequency_hz;
entry.source_summary = relative_to_project(summaryPath);

fieldName = sprintf('ch%d', calibration.channel);
config.channels.(fieldName) = entry;

try
    encoded = jsonencode(config, 'PrettyPrint', true);
catch
    encoded = jsonencode(config);
end

fid = fopen(path, 'w');
if fid < 0
    error('main_v8_calibration_check:CalibrationWriteFailed', ...
        'Could not write %s.', path);
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', encoded);
end

function relativePath = relative_to_project(path)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
path = char(path);
prefix = [projectRoot filesep];
if startsWith(path, prefix)
    relativePath = path(numel(prefix) + 1:end);
else
    relativePath = path;
end
end
