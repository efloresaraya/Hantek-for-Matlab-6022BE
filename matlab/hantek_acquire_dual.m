function data = hantek_acquire_dual(varargin)
%HANTEK_ACQUIRE_DUAL Acquire CH1 and CH2 from one USB block.

p = inputParser;
addParameter(p, 'sampleRate', 10e6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'nSamples', 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'voltsPerDiv', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'projectRoot', default_project_root(), @(x) ischar(x) || isstring(x));
addParameter(p, 'applyCalibration', false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, 'calibrationPath', fullfile(default_project_root(), 'data', 'software_calibration.json'), @(x) ischar(x) || isstring(x));
addParameter(p, 'debugLogPath', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'debugEcho', false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
parse(p, varargin{:});
opts = p.Results;

projectRoot = string(opts.projectRoot);
pythonDir = fullfile(projectRoot, 'python');

try
    ensure_python_path(pythonDir);
    py.importlib.invalidate_caches();
    module = py.importlib.import_module('hantek_usb_backend');
    module = py.importlib.reload(module);

    if strlength(string(opts.debugLogPath)) > 0
        backend = module.Hantek6022USBBackend(pyargs( ...
            'project_root', char(projectRoot), ...
            'debug_log_path', char(string(opts.debugLogPath)), ...
            'debug_echo', logical(opts.debugEcho)));
    else
        backend = module.Hantek6022USBBackend(pyargs( ...
            'project_root', char(projectRoot), ...
            'debug_echo', logical(opts.debugEcho)));
    end
    cleanupObj = onCleanup(@() backend.close()); %#ok<NASGU>

    acquireDual = py.getattr(backend, 'acquire_dual');
    capture = acquireDual(pyargs( ...
        'sample_rate', double(opts.sampleRate), ...
        'n_samples', int32(opts.nSamples), ...
        'volts_per_div', double(opts.voltsPerDiv)));
    data = py_dual_capture_to_struct(capture);
    data = normalize_dual_lengths(data);
    data.calibration_applied = false;
    data.raw_ch1 = double(data.ch1(:));
    data.raw_ch2 = double(data.ch2(:));
    if logical(opts.applyCalibration)
        data = apply_dual_calibration(data, opts.calibrationPath);
    end
catch ME
    if contains(string(ME.message), 'ModuleNotFoundError')
        error('hantek_acquire_dual:PythonDependencyMissing', ...
            '%s\nMATLAB esta usando un Python sin las dependencias del proyecto.', ...
            ME.message);
    end
    error('hantek_acquire_dual:UsbUnavailable', ...
        '%s\nRevise PyUSB/libusb, permisos USB y que el Hantek 6022BE este conectado.', ...
        ME.message);
end
end

function projectRoot = default_project_root()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
end

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
metadata = capture.get('metadata');
if ~isequal(metadata, py.None)
    data.metadata = metadata;
end
end

function data = normalize_dual_lengths(data)
n = min([numel(data.time), numel(data.ch1), numel(data.ch2)]);
if n == 0
    error('hantek_acquire_dual:EmptyCapture', 'La captura dual llego vacia.');
end
data.time = double(data.time(1:n));
data.ch1 = double(data.ch1(1:n));
data.ch2 = double(data.ch2(1:n));
data.n_samples = n;
end

function values = py_list_to_double(pyValues)
values = double(py.array.array('d', pyValues));
values = values(:);
end

function data = apply_dual_calibration(data, calibrationPath)
calibrationPath = char(string(calibrationPath));
if ~isfile(calibrationPath)
    error('hantek_acquire_dual:CalibrationFileMissing', ...
        'No existe archivo de calibracion software: %s', calibrationPath);
end

config = jsondecode(fileread(calibrationPath));
if ~isfield(config, 'schema') || string(config.schema) ~= "hantek6022be-software-calibration-v1"
    error('hantek_acquire_dual:CalibrationSchemaInvalid', ...
        'Archivo de calibracion incompatible: %s', calibrationPath);
end
if ~isfield(config, 'channels') || ~isstruct(config.channels)
    error('hantek_acquire_dual:CalibrationChannelsMissing', ...
        'Archivo de calibracion sin tabla channels: %s', calibrationPath);
end

[data.ch1, gain1, offset1] = apply_channel_calibration(data.ch1, config, 1);
[data.ch2, gain2, offset2] = apply_channel_calibration(data.ch2, config, 2);
data.calibration_applied = true;
data.calibration_path = string(calibrationPath);
data.calibration_ch1_gain = gain1;
data.calibration_ch1_offset_v = offset1;
data.calibration_ch2_gain = gain2;
data.calibration_ch2_offset_v = offset2;
end

function [voltage, gain, offset] = apply_channel_calibration(voltage, config, channel)
fieldName = char(sprintf('ch%d', channel));
if ~isfield(config.channels, fieldName)
    error('hantek_acquire_dual:CalibrationChannelMissing', ...
        'No hay calibracion software para CH%d.', channel);
end
entry = config.channels.(fieldName);
if isfield(entry, 'enabled') && ~logical(entry.enabled)
    error('hantek_acquire_dual:CalibrationChannelDisabled', ...
        'La calibracion software para CH%d esta deshabilitada.', channel);
end
gain = double(entry.gain);
offset = double(entry.offset_v);
voltage = double(voltage(:)) .* gain + offset;
end
