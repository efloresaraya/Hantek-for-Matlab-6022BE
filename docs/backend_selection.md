# Seleccion de backend

## `simulator`

Uso recomendado:

- Validar instalacion.
- Probar MATLAB sin hardware.
- Crear datos controlados para FFT y metricas.

Python:

```bash
python python/capture_example.py --mode simulator
```

MATLAB:

```matlab
data = hantek_acquire("simulator");
```

## `csv`

Uso recomendado:

- Primer puente con archivos ya existentes.
- Validar capturas exportadas previamente por herramientas externas.
- Trabajar sin depender del acceso USB desde MATLAB.

MATLAB:

```matlab
data = hantek_acquire("csv", "csvPath", "data/raw/captura.csv");
```

## `openhantek`

Uso recomendado:

- Solo como referencia/deteccion de la carpeta local.
- No es el backend principal por criterio de confianza.

## `usb`

Uso recomendado:

- Capturar desde el Hantek 6022BE fisico en macOS.
- Evitar compilar o ejecutar OpenHantek.
- Usar PyUSB/libusb con firmware local verificado.

MATLAB:

```matlab
data = hantek_acquire("usb", "channel", 1, "sampleRate", 1e6, "nSamples", 20000);
```

Si falla, revise PyUSB/libusb, permisos USB y que el equipo este conectado.

Para adquisicion en vivo desde MATLAB:

```matlab
run("matlab/main_v6_usb_live_app.m")
```

Esta ruta abre el panel de control live y actualiza graficos y metricas por bloques USB sin usar CSV intermedio.
