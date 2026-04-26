% MAIN_V4_USB_BRIDGE Capture from the Hantek 6022BE through the direct USB backend.

clear; clc;

try
    data = hantek_acquire("usb", ...
        "channel", 1, ...
        "sampleRate", 1e6, ...
        "nSamples", 20000, ...
        "voltsPerDiv", 1.0, ...
        "debugEcho", true);

    metrics = analyze_signal(data);
    disp(metrics);
    plot_signal_report(data, metrics);
catch ME
    fprintf("\nNo se pudo capturar por USB directo.\n");
    fprintf("%s\n", ME.message);
    fprintf("Revise PyUSB/libusb, permisos USB y que el Hantek 6022BE este conectado al Mac mini.\n\n");
end
