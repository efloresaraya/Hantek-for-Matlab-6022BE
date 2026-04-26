% MAIN_V3_OPENHANTEK_BRIDGE Try the OpenHantek backend safely.

clear; clc;

try
    data = hantek_acquire("openhantek", ...
        "channel", 1, ...
        "sampleRate", 1e6, ...
        "nSamples", 2048);

    metrics = analyze_signal(data);
    disp(metrics);
    plot_signal_report(data, metrics);
catch ME
    fprintf("\nOpenHantek no esta disponible como backend automatico.\n");
    fprintf("%s\n", ME.message);
    fprintf("Recomendacion: use mode=\"csv\" con una exportacion manual de OpenHantek, o mode=\"simulator\".\n\n");

    data = hantek_acquire("simulator", ...
        "channel", 1, ...
        "sampleRate", 1e6, ...
        "nSamples", 2048);
    metrics = analyze_signal(data);
    disp(metrics);
    plot_signal_report(data, metrics);
end

