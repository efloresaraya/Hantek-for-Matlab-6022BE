% MAIN_V2_PYTHON_BRIDGE Acquire simulated data through the Python adapter.

clear; clc;

projectRoot = fileparts(fileparts(mfilename("fullpath")));
pythonDir = fullfile(projectRoot, "python");
ensure_python_path(pythonDir);

adapterModule = py.importlib.import_module("hantek_adapter");
adapter = adapterModule.HantekAdapter(pyargs( ...
    "mode", "simulator", ...
    "project_root", char(projectRoot)));

capture = adapter.acquire(pyargs( ...
    "channel", int32(1), ...
    "sample_rate", 1e6, ...
    "n_samples", int32(2048)));

data = struct();
data.time = py_list_to_double(py_dict_get(capture, "time"));
data.voltage = py_list_to_double(py_dict_get(capture, "voltage"));
data.sample_rate = double(py_dict_get(capture, "sample_rate"));
data.channel = double(py_dict_get(capture, "channel"));
data.n_samples = double(py_dict_get(capture, "n_samples"));
data.source = string(py_dict_get(capture, "source"));

metrics = analyze_signal(data);
disp(metrics);
plot_signal_report(data, metrics);

function ensure_python_path(pythonDir)
pythonDir = char(pythonDir);
pyPath = py.sys.path;
if int64(pyPath.count(pythonDir)) == 0
    pyPath.insert(int32(0), pythonDir);
end
end

function value = py_dict_get(pyDict, key)
value = pyDict.get(char(key));
if isequal(value, py.None)
    error("main_v2_python_bridge:PythonKeyMissing", ...
        "La captura Python no contiene la clave requerida: %s", string(key));
end
end

function values = py_list_to_double(pyValues)
values = double(py.array.array('d', pyValues));
values = values(:);
end
