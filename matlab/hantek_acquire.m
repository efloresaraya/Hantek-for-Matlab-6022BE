function data = hantek_acquire(mode, varargin)
%HANTEK_ACQUIRE Acquire data from simulator, CSV, USB, or OpenHantek bridge.
%
% data = hantek_acquire("simulator", "sampleRate", 1e6, "nSamples", 2048)
% data = hantek_acquire("csv", "csvPath", "../data/examples/example_openhantek_export.csv")
% data = hantek_acquire("usb", "sampleRate", 1e6, "nSamples", 20000)
% data = hantek_acquire("usb", "applyCalibration", true)
% data = hantek_acquire("openhantek", "projectRoot", "..")

if nargin < 1 || strlength(string(mode)) == 0
    mode = "simulator";
end

p = inputParser;
addParameter(p, "channel", 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, "sampleRate", 1e6, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "nSamples", 2048, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "csvPath", "", @(x) ischar(x) || isstring(x));
addParameter(p, "projectRoot", default_project_root(), @(x) ischar(x) || isstring(x));
addParameter(p, "openhantekBinary", "", @(x) ischar(x) || isstring(x));
addParameter(p, "voltsPerDiv", 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, "debugLogPath", "", @(x) ischar(x) || isstring(x));
addParameter(p, "debugEcho", true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, "applyCalibration", false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
addParameter(p, "calibrationPath", fullfile(default_project_root(), "data", "software_calibration.json"), @(x) ischar(x) || isstring(x));
parse(p, varargin{:});

opts = p.Results;
mode = lower(string(mode));

switch mode
    case "simulator"
        data = acquire_simulator(opts);
    case "csv"
        if strlength(string(opts.csvPath)) == 0
            error("hantek_acquire:MissingCsvPath", "mode='csv' requiere csvPath.");
        end
        data = read_capture_csv(string(opts.csvPath), opts.channel, opts.sampleRate, opts.nSamples);
        data.source = "csv";
        data = maybe_apply_matlab_calibration(data, opts);
    case "usb"
        data = acquire_usb(opts);
    case "openhantek"
        data = acquire_openhantek(opts);
        data = maybe_apply_matlab_calibration(data, opts);
    otherwise
        error("hantek_acquire:InvalidMode", "Modo no soportado: %s", mode);
end
end

function projectRoot = default_project_root()
thisFile = mfilename("fullpath");
projectRoot = fileparts(fileparts(thisFile));
end

function data = acquire_simulator(opts)
n = double(opts.nSamples);
fs = double(opts.sampleRate);
t = (0:n-1).' ./ fs;
frequency = 1000;
amplitude = 1.0;
noise = 0.01 * sin(2*pi*frequency*0.137*t);
v = amplitude * sin(2*pi*frequency*t) + noise;

data = struct();
data.time = t;
data.voltage = v;
data.sample_rate = fs;
data.channel = opts.channel;
data.n_samples = numel(v);
data.source = "simulator";
end

function data = acquire_usb(opts)
projectRoot = string(opts.projectRoot);
pythonDir = fullfile(projectRoot, "python");

try
    ensure_python_path(pythonDir);
    py.importlib.invalidate_caches();
    backendModule = py.importlib.import_module("hantek_usb_backend");
    py.importlib.reload(backendModule);
    module = py.importlib.import_module("hantek_adapter");
    module = py.importlib.reload(module);
    if strlength(string(opts.debugLogPath)) > 0
        adapter = module.HantekAdapter(pyargs( ...
            "mode", "usb", ...
            "project_root", char(projectRoot), ...
            "volts_per_div", double(opts.voltsPerDiv), ...
            "debug_echo", logical(opts.debugEcho), ...
            "apply_calibration", logical(opts.applyCalibration), ...
            "calibration_path", char(string(opts.calibrationPath)), ...
            "debug_log_path", char(string(opts.debugLogPath))));
    else
        adapter = module.HantekAdapter(pyargs( ...
            "mode", "usb", ...
            "project_root", char(projectRoot), ...
            "volts_per_div", double(opts.voltsPerDiv), ...
            "debug_echo", logical(opts.debugEcho), ...
            "apply_calibration", logical(opts.applyCalibration), ...
            "calibration_path", char(string(opts.calibrationPath))));
    end

    capture = adapter.acquire(pyargs( ...
        "channel", int32(opts.channel), ...
        "sample_rate", double(opts.sampleRate), ...
        "n_samples", int32(opts.nSamples), ...
        "volts_per_div", double(opts.voltsPerDiv), ...
        "apply_calibration", logical(opts.applyCalibration), ...
        "calibration_path", char(string(opts.calibrationPath))));
    data = py_capture_to_struct(capture);
catch ME
    if contains(string(ME.message), "ModuleNotFoundError")
        error("hantek_acquire:PythonDependencyMissing", ...
            "%s\nMATLAB esta usando un Python sin las dependencias del proyecto. Configure pyenv con el entorno conda hantek6022be-matlab antes de llamar hantek_acquire.", ...
            ME.message);
    end
    error("hantek_acquire:UsbUnavailable", ...
        "%s\nRevise PyUSB/libusb, permisos USB y que el Hantek 6022BE este conectado.", ...
        ME.message);
end
end

function data = acquire_openhantek(opts)
projectRoot = string(opts.projectRoot);
pythonDir = fullfile(projectRoot, "python");

try
    ensure_python_path(pythonDir);
    module = py.importlib.import_module("openhantek_adapter");

    if strlength(string(opts.openhantekBinary)) > 0
        adapter = module.OpenHantekAdapter(pyargs( ...
            "project_root", char(projectRoot), ...
            "binary_path", char(string(opts.openhantekBinary))));
    else
        adapter = module.OpenHantekAdapter(pyargs("project_root", char(projectRoot)));
    end

    tempCsv = string(tempname) + ".csv";
    adapter.capture_to_csv( ...
        int32(opts.channel), ...
        double(opts.sampleRate), ...
        int32(opts.nSamples), ...
        char(tempCsv));

    data = read_capture_csv(tempCsv, opts.channel, opts.sampleRate, opts.nSamples);
    data.source = "openhantek";
    data.openhantek_csv = tempCsv;
catch ME
    error("hantek_acquire:OpenHantekUnavailable", ...
        "%s\nUse mode=""csv"" con una exportacion de OpenHantek o mode=""simulator"".", ...
        ME.message);
end
end

function ensure_python_path(pythonDir)
pythonDir = char(pythonDir);
pyPath = py.sys.path;
if int64(pyPath.count(pythonDir)) == 0
    pyPath.insert(int32(0), pythonDir);
end
end

function data = py_capture_to_struct(capture)
data = struct();
data.time = py_list_to_double(py_dict_get(capture, "time"));
data.voltage = py_list_to_double(py_dict_get(capture, "voltage"));
data.sample_rate = double(py_dict_get(capture, "sample_rate"));
data.channel = double(py_dict_get(capture, "channel"));
data.n_samples = double(py_dict_get(capture, "n_samples"));
data.source = string(py_dict_get(capture, "source"));
data.calibration_applied = false;
calibrationApplied = capture.get('calibration_applied');
if ~isequal(calibrationApplied, py.None)
    data.calibration_applied = logical(calibrationApplied);
end
calibrationGain = capture.get('calibration_gain');
if ~isequal(calibrationGain, py.None)
    data.calibration_gain = double(calibrationGain);
end
calibrationOffset = capture.get('calibration_offset_v');
if ~isequal(calibrationOffset, py.None)
    data.calibration_offset_v = double(calibrationOffset);
end
calibrationPath = capture.get('calibration_path');
if ~isequal(calibrationPath, py.None)
    data.calibration_path = string(calibrationPath);
end
metadata = capture.get('metadata');
if ~isequal(metadata, py.None)
    data.metadata = metadata;
end
end

function value = py_dict_get(pyDict, key)
value = pyDict.get(char(key));
if isequal(value, py.None)
    error("hantek_acquire:PythonKeyMissing", ...
        "La captura Python no contiene la clave requerida: %s", string(key));
end
end

function values = py_list_to_double(pyValues)
values = double(py.array.array('d', pyValues));
values = values(:);
end

function data = read_capture_csv(csvPath, channel, sampleRate, nSamples)
csvPath = char(csvPath);
if ~isfile(csvPath)
    error("hantek_acquire:CsvNotFound", "No existe el archivo CSV: %s", csvPath);
end

opts = detectImportOptions(csvPath, "FileType", "text");
tbl = readtable(csvPath, opts);
if height(tbl) == 0
    error("hantek_acquire:EmptyCsv", "El archivo CSV no contiene muestras: %s", csvPath);
end

names = string(tbl.Properties.VariableNames);
cleanNames = lower(regexprep(names, "[^a-zA-Z0-9]", ""));

timeIdx = find(cleanNames == "ts" | cleanNames == "time" | cleanNames == "times", 1);
if isempty(timeIdx)
    timeIdx = 1;
end

channelToken = "ch" + string(channel);
voltageIdx = find(contains(cleanNames, channelToken) & contains(cleanNames, "v"), 1);
if isempty(voltageIdx)
    fallbackIdx = timeIdx + double(channel);
    if fallbackIdx <= width(tbl)
        voltageIdx = fallbackIdx;
    else
        voltageIdx = find(contains(cleanNames, "v"), 1);
    end
end
if isempty(voltageIdx)
    error("hantek_acquire:VoltageColumnMissing", ...
        "No se encontro columna de voltaje para canal %d.", channel);
end

t = tbl{:, timeIdx};
v = tbl{:, voltageIdx};
t = double(t(:));
v = double(v(:));

maxSamples = min([numel(v), double(nSamples)]);
t = t(1:maxSamples);
v = v(1:maxSamples);

data = struct();
data.time = t;
data.voltage = v;
data.sample_rate = double(sampleRate);
data.channel = channel;
data.n_samples = numel(v);
data.source = "csv";
data.csv_path = string(csvPath);
data.calibration_applied = false;
end

function data = maybe_apply_matlab_calibration(data, opts)
if ~logical(opts.applyCalibration)
    if ~isfield(data, 'calibration_applied')
        data.calibration_applied = false;
    end
    return;
end

calibrationPath = char(string(opts.calibrationPath));
if ~isfile(calibrationPath)
    error("hantek_acquire:CalibrationFileMissing", ...
        "No existe archivo de calibracion software: %s", calibrationPath);
end

config = jsondecode(fileread(calibrationPath));
if ~isfield(config, 'schema') || string(config.schema) ~= "hantek6022be-software-calibration-v1"
    error("hantek_acquire:CalibrationSchemaInvalid", ...
        "Archivo de calibracion incompatible: %s", calibrationPath);
end
if ~isfield(config, 'channels') || ~isstruct(config.channels)
    error("hantek_acquire:CalibrationChannelsMissing", ...
        "Archivo de calibracion sin tabla channels: %s", calibrationPath);
end

channel = round(double(data.channel));
fieldName = char(sprintf("ch%d", channel));
if ~isfield(config.channels, fieldName)
    error("hantek_acquire:CalibrationChannelMissing", ...
        "No hay calibracion software para CH%d en %s", channel, calibrationPath);
end
entry = config.channels.(fieldName);
if isfield(entry, 'enabled') && ~logical(entry.enabled)
    error("hantek_acquire:CalibrationChannelDisabled", ...
        "La calibracion software para CH%d esta deshabilitada.", channel);
end

gain = double(entry.gain);
offset = double(entry.offset_v);
data.voltage = double(data.voltage(:)) .* gain + offset;
data.calibration_applied = true;
data.calibration_gain = gain;
data.calibration_offset_v = offset;
data.calibration_path = string(calibrationPath);
end
