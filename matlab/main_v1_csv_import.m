% MAIN_V1_CSV_IMPORT Import an OpenHantek-style CSV and analyze it.

clear; clc;

projectRoot = fileparts(fileparts(mfilename("fullpath")));
csvPath = fullfile(projectRoot, "data", "examples", "example_openhantek_export.csv");

data = hantek_acquire("csv", ...
    "csvPath", csvPath, ...
    "channel", 1, ...
    "sampleRate", 1e6, ...
    "nSamples", 1024);

metrics = analyze_signal(data);
disp(metrics);
plot_signal_report(data, metrics);

