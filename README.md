# Hantek6022BE MATLAB Toolkit

Toolkit para adquirir, importar y analizar senales del osciloscopio Hantek 6022BE desde MATLAB, usando una capa Python intermedia cuando corresponde.

La arquitectura esperada es:

```text
Hantek 6022BE
    ↓
backend USB propio PyUSB/libusb
    ↓
adaptador Python o flujo CSV
    ↓
MATLAB
    ↓
analisis, FFT, metricas, graficos
```

`OpenHantek6022` permanece dentro del proyecto solo como referencia tecnica local
auditada. No se compila, no se instala y no se ejecuta.

## Modos de adquisicion

- `simulator`: genera senales sinteticas. Debe funcionar siempre y sirve para validar MATLAB/Python.
- `csv`: lee capturas ya existentes exportadas por herramientas externas compatibles.
- `usb`: backend propio por `PyUSB/libusb` para hablar con el Hantek 6022BE fisico en macOS, sin compilar ni ejecutar OpenHantek.
- `openhantek`: modo legado de deteccion/referencia. No es el camino principal de captura.

## Estructura

```text
OpenHantek6022/              # base existente, no modificada
python/
  hantek_adapter.py          # selector simulator/csv/usb/openhantek
  hantek_usb_backend.py      # backend USB directo propio
  software_calibration.py    # correccion local no destructiva de gain/offset
  openhantek_adapter.py      # deteccion y puente seguro para OpenHantek6022
  hantek_backend_template.py # plantilla para una API C/C++ futura
  hantek_simulator.py
  signal_utils.py
  test_connection.py
  capture_example.py
  diagnose_ch2_dual.py       # diagnostico CH1/CH2 en un mismo bloque USB
  validate_dual_capture.py   # regresion de timing/frecuencia/jitter sobre CSV dual
matlab/
  main_v1_csv_import.m
  main_v2_python_bridge.m
  main_v3_openhantek_bridge.m
  main_v4_usb_bridge.m
  main_v5_usb_realtime.m
  main_v6_usb_live_app.m
  main_v7_ch2_diagnostic.m
  main_v8_calibration_check.m
  main_v9_usb_dual_live_app.m
  hantek_acquire.m
  hantek_acquire_dual.m
  hantek_realtime_usb.m
  hantek_live_app.m
  hantek_dual_live_app.m
  save_capture_bundle.m
  save_dual_capture_bundle.m
  analyze_signal.m
  analyze_dual_signal.m
  compute_fft.m
  plot_signal_report.m
data/
  software_calibration.json  # coeficientes locales, no EEPROM
  raw/
  processed/
  examples/
  logs/
docs/
```

## Inicio rapido

Crear entorno:

```bash
conda env create -f environment.yml
conda activate hantek6022be-matlab
```

Probar Python:

```bash
python python/test_connection.py --csv data/examples/example_openhantek_export.csv
python python/capture_example.py --mode simulator --output data/examples/simulator_capture.csv
```

Probar USB directo con hardware conectado:

```bash
python python/test_connection.py --mode usb --sample-rate 1000000 --n-samples 20000
python python/capture_example.py --mode usb --output data/raw/usb_capture.csv
```

Cada prueba USB crea una bitacora en `data/logs/` e imprime los pasos en pantalla:

```bash
python python/test_connection.py --mode usb --log-path data/logs/mi_prueba_usb.log
```

Probar MATLAB:

```matlab
run("matlab/main_v1_csv_import.m")
run("matlab/main_v2_python_bridge.m")
run("matlab/main_v4_usb_bridge.m")
```

Captura en vivo desde MATLAB:

```matlab
run("matlab/main_v6_usb_live_app.m")
```

El panel en vivo no usa CSV como intermediario: MATLAB llama a `hantek_acquire("usb", ...)` en bloques cortos, actualiza forma de onda/FFT/metricas y permite elegir CH1/CH2, escala, tasa de muestreo, numero de muestras, trigger software y ejes de visualizacion. Los controles `Auto T`, `Start ms`, `Window ms`, `Auto V`, `Center V` y `Span V` permiten hacer zoom/desplazar la senal sin detener la captura. El trigger `On/Rise/Fall/Level/Pos%` alinea cada bloque antes de graficarlo para estabilizar pulsos. El checkbox `Cal SW` aplica la calibracion software local de `data/software_calibration.json` sin escribir nada en el Hantek. Tambien existe `main_v5_usb_realtime.m` como modo live simple por script.

El boton `Save CSV+MAT+PNG` de la app live guarda la ultima captura como:

- `.csv` con tiempo y voltaje;
- `.mat` con datos, metricas, configuracion y ruta del log;
- `.png` con reporte de forma de onda, FFT y metricas.

Captura dual CH1+CH2 en vivo:

```matlab
run("matlab/main_v9_usb_dual_live_app.m")
```

La app `v9` captura CH1 y CH2 desde el mismo bloque USB en cada refresco.
Tiene modos de vista `Dual`, `CH1` y `CH2`, presets de laboratorio, trigger
software con fuente CH1/CH2, flanco Rise/Fall y nivel `auto` o manual,
`Cal SW`, FFT por canal, tabla de metricas por canal, delay CH2-CH1 y
guardado `CSV/MAT/PNG` dual. El preset `External` deja una configuracion base
para senales externas.

Cuando `Cal SW` y `Raw CSV` estan activos, el CSV principal guarda columnas
calibradas y raw:

```text
t_s, CH1_V, CH2_V, CH1_raw_V, CH2_raw_V
```

Tambien se guarda un archivo adicional `*_raw.csv` con solo las columnas raw.
El PNG dual usa el `FFT max Hz` de la app para que la FFT quede con zoom util.

Validar un CSV dual guardado:

```bash
python python/validate_dual_capture.py data/raw/dual_diag_20260426_142709.csv
```

## Validacion CH1/CH2

Para validar el modo dual, use:

```matlab
run("matlab/main_v7_ch2_diagnostic.m")
```

Este script captura CH1 y CH2 desde el mismo bloque USB, grafica ambos canales,
guarda un CSV en `data/raw/dual_diag_*.csv` y muestra metricas `Tmed`/`Tjit`.
Fue agregado despues de detectar que las capturas duales a `10 MS/s` se
deformaban cuando la lectura bulk se hacia en trozos pequenos. El backend ahora
pide lecturas bulk grandes para evitar discontinuidades temporales en modo dual.

## Chequeo de calibracion no destructivo

Para medir offset/gain de forma no destructiva:

```matlab
run("matlab/main_v8_calibration_check.m")
```

Para repetirlo en CH2 sin editar archivos:

```matlab
calibrationChannel = 2;
run("matlab/main_v8_calibration_check.m")
```

El script captura un canal conectado al calibrador, estima niveles alto/bajo,
frecuencia y `Tjit`, y guarda CSV/MAT/PNG/TXT. No escribe EEPROM ni aplica
calibracion persistente. Tambien actualiza `data/software_calibration.json`
con los coeficientes locales para analisis/visualizacion:

```text
voltaje_corregido = voltaje_crudo * gain + offset_v
```

Uso manual desde MATLAB:

```matlab
data = hantek_acquire("usb", ...
    "channel", 1, ...
    "sampleRate", 10e6, ...
    "nSamples", 100000, ...
    "voltsPerDiv", 1.0, ...
    "applyCalibration", true);
```

Uso manual desde Python:

```bash
python python/capture_example.py --mode usb --apply-calibration --output data/raw/usb_calibrated.csv
```

## Integracion con OpenHantek6022 existente

El proyecto ya contiene `OpenHantek6022/OpenHantek6022-main`, que se usa como referencia tecnica local para el backend real del Hantek 6022BE. Por criterio de confianza, este toolkit no compila, instala ni ejecuta OpenHantek.

La inspeccion inicial muestra:

- El codigo fuente tiene modulos USB/protocolo en `openhantek/src/usb`, `openhantek/src/hantekprotocol` y `openhantek/src/hantekdso`.
- La exportacion CSV/JSON existe en `openhantek/src/exporting`.
- El ejecutable OpenHantek6022 expone opciones de linea de comandos para GUI/configuracion/demo, pero no se detecto una opcion documentada de captura headless a CSV.
- La documentacion incluida sirve para auditar detalles tecnicos, pero este toolkit no compila ni ejecuta OpenHantek.

Por eso el proyecto queda preparado asi:

1. `simulator` y `csv` funcionan como base estable.
2. `usb` usa `python/hantek_usb_backend.py` para capturar desde el dispositivo fisico con `PyUSB/libusb`.
3. El firmware local se verifica con SHA256 antes de cargarse al dispositivo.
4. `openhantek_adapter.py` queda como referencia/deteccion, no como backend principal.

Mas detalle en [docs/usb_backend.md](docs/usb_backend.md) y [docs/openhantek_integration.md](docs/openhantek_integration.md).
