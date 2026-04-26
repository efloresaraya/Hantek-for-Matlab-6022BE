# Backend USB directo

## Objetivo

El modo `usb` comunica el Hantek 6022BE fisico con el Mac mini sin compilar, instalar ni ejecutar OpenHantek. OpenHantek se usa solo como referencia tecnica local para constantes de protocolo y como ubicacion del firmware ya incluido en el proyecto.

## Seguridad

- Solo se aceptan VID/PID `04b4:6022` en estado loader y `04b5:6022` en estado activo.
- El firmware local `dso6022be-firmware.hex` se verifica antes de usarlo.
- SHA256 permitido: `7773d886de861e2a95b159f103135b06391a6433adf0727d3d1e23aec9e65cfd`.
- No se ejecutan binarios de OpenHantek.
- No se escribe EEPROM ni calibracion persistente en v1.
- La calibracion software es un archivo JSON local aplicado despues de capturar;
  no modifica el dispositivo.
- CH1 y CH2 se capturan desde el backend propio. CH2 usa adquisicion intercalada de dos canales.

## Flujo USB

1. Buscar dispositivo activo `04b5:6022`.
2. Si no existe, buscar loader `04b4:6022`.
3. Verificar hash del firmware local.
4. Cargar firmware Cypress FX2LP por control transfer `0xA0`.
5. Esperar renumeracion a `04b5:6022`.
6. Reclamar interfaz vendor USB.
7. Configurar ganancia, sample rate, numero de canales y frecuencia del calibrador.
8. Iniciar captura con request `0xE3`.
9. Leer muestras por endpoint bulk IN `0x86`.
10. Detener captura con request `0xE3` y payload `0x00`.

Notas de implementacion:

- El calibrador interno se configura con request `0xE6` a `1 kHz`.
- El orden de configuracion sigue la referencia local de OpenHantek: ganancias,
  sample rate, numero de canales, calibrador.
- En modo dual rapido, las lecturas bulk deben pedirse en bloques grandes. Una
  version anterior leia en trozos de `64 KB`, lo que generaba discontinuidades
  temporales visibles en CH1/CH2 a `10 MS/s`. El backend usa ahora solicitudes
  de hasta `1 MB`.

## Uso

```bash
python python/test_connection.py --mode usb --sample-rate 1000000 --n-samples 20000
python python/capture_example.py --mode usb --output data/raw/usb_capture.csv
```

Con log diagnostico en una ruta fija:

```bash
python python/test_connection.py --mode usb --log-path data/logs/mi_prueba_usb.log
```

Por defecto, cada linea del log tambien se muestra en tiempo real en la Terminal de macOS.

Para guardar la bitacora sin mostrar cada paso en consola:

```bash
python python/test_connection.py --mode usb --quiet-log
```

MATLAB:

```matlab
data = hantek_acquire("usb", "channel", 1, "sampleRate", 1e6, "nSamples", 20000);
metrics = analyze_signal(data);
plot_signal_report(data, metrics);
```

Con calibracion software local:

```matlab
data = hantek_acquire("usb", ...
    "channel", 1, ...
    "sampleRate", 10e6, ...
    "nSamples", 100000, ...
    "voltsPerDiv", 1.0, ...
    "applyCalibration", true);
```

Desde Python:

```bash
python python/capture_example.py --mode usb --apply-calibration --output data/raw/usb_calibrated.csv
```

MATLAB en vivo:

```matlab
run("matlab/main_v6_usb_live_app.m")
```

La captura en vivo trabaja por bloques USB: cada iteracion toma un bloque real desde el Hantek, actualiza forma de onda, FFT y metricas, y continua mientras la ventana siga abierta. Es captura directa desde el dispositivo, sin CSV intermedio. El panel permite seleccionar canal, escala, tasa de muestreo, numero de muestras, trigger software, ejes de visualizacion, guardar la ultima captura en `.mat`, activar/desactivar la bitacora USB visible y aplicar `Cal SW`.

El boton `Save CSV+MAT+PNG` guarda la ultima captura como paquete completo en
`data/processed/`: CSV, MAT y PNG de reporte.

MATLAB dual CH1+CH2 en vivo:

```matlab
run("matlab/main_v9_usb_dual_live_app.m")
```

La app dual usa `hantek_acquire_dual.m`, que llama a `acquire_dual()` del
backend Python. Cada refresco obtiene CH1 y CH2 del mismo bloque USB, aplica
opcionalmente `Cal SW`, calcula metricas por canal y delay CH2-CH1, y permite
guardar CSV/MAT/PNG dual.

Controles importantes de `v9`:

- `Preset`: calibrador, diagnostico, senal externa, lento, rapido o largo.
- `Mode`: vista `Dual`, `CH1` o `CH2`.
- `Trigger`: fuente CH1/CH2, flanco Rise/Fall y nivel `auto` o manual.
- `Cal SW`: aplica calibracion software local despues de capturar.
- `Raw CSV`: si `Cal SW` esta activo, guarda tambien columnas y archivo raw.
- `FFT max Hz`: limita la vista FFT en la app y en el PNG guardado.

CSV dual calibrado + raw:

```text
t_s, CH1_V, CH2_V, CH1_raw_V, CH2_raw_V
```

Archivo raw adicional:

```text
hantek_dual_YYYYMMDD_HHMMSS_raw.csv
```

Adquisicion dual por script:

```matlab
data = hantek_acquire_dual( ...
    'sampleRate', 10e6, ...
    'nSamples', 100000, ...
    'voltsPerDiv', 1.0, ...
    'applyCalibration', true);
metrics = analyze_dual_signal(data);
paths = save_dual_capture_bundle(data, metrics, struct(), "", "", "");
```

Diagnostico CH1/CH2 en un mismo bloque:

```matlab
run("matlab/main_v7_ch2_diagnostic.m")
```

Diagnostico equivalente desde Terminal:

```bash
python python/diagnose_ch2_dual.py --sample-rate 10000000 --n-samples 100000 --volts-per-div 1
```

Ambos diagnosticos guardan un CSV con `CH1` y `CH2` del mismo bloque USB y
reportan metricas de periodo entre flancos. Use este diagnostico si una senal
parece deformarse en CH2 o en modo dual.

Validacion de regresion sobre un CSV dual:

```bash
python python/validate_dual_capture.py data/raw/dual_diag_20260426_142709.csv
```

El validador revisa monotonia temporal, saltos de muestra, frecuencia esperada,
Tjit y cantidad minima de flancos en ambos canales.

Chequeo de calibracion no destructivo:

```matlab
run("matlab/main_v8_calibration_check.m")
```

Para CH2:

```matlab
calibrationChannel = 2;
run("matlab/main_v8_calibration_check.m")
```

Este script estima niveles alto/bajo, Vpp, frecuencia y `Tjit`, guarda un
reporte y actualiza `data/software_calibration.json`. No escribe EEPROM ni
modifica calibracion persistente. La formula aplicada despues de capturar es:

```text
voltaje_corregido = voltaje_crudo * gain + offset_v
```

## Limitaciones v1

- Sin streaming continuo sample-by-sample; MATLAB actualiza por bloques.
- Sin trigger hardware avanzado; la app dual tiene trigger software por fuente,
  flanco y nivel.
- Sin calibracion EEPROM. Solo hay calibracion software local y reversible.
- Conversion ADC a voltaje con offset nominal `0x80` y escala fija del rango seleccionado.
- Si macOS/libusb no puede reclamar el dispositivo, el backend falla sin intentar drivers externos.
- El modo live es por bloques. No es streaming continuo sample-by-sample, aunque
  para uso de laboratorio ya muestra CH1/CH2 en tiempo real por refresco de bloques.

## Bitacora diagnostica

El backend registra cada etapa critica:

- carga de PyUSB;
- busqueda de VID/PID loader y activo;
- verificacion SHA256 del firmware;
- parseo Intel HEX;
- carga de firmware y renumeracion;
- reclamo de interfaz USB;
- configuracion de ganancia, canal y sample rate;
- lectura bulk y conversion de muestras.

Por defecto los logs quedan en `data/logs/hantek_usb_YYYYMMDD_HHMMSS.log`.
