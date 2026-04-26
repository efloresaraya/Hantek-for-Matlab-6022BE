# Integracion con OpenHantek6022

## Estado actual

La carpeta `OpenHantek6022` ya esta dentro del proyecto. En esta instalacion la base real esta anidada como:

```text
OpenHantek6022/OpenHantek6022-main/
```

La inspeccion local encontro:

- `CMakeLists.txt` en la raiz de OpenHantek.
- Codigo Qt/C++ en `openhantek/src`.
- Comunicacion USB en `openhantek/src/usb`.
- Protocolo Hantek en `openhantek/src/hantekprotocol`.
- Control/captura en `openhantek/src/hantekdso`.
- Exportadores CSV/JSON en `openhantek/src/exporting`.
- Guia de compilacion macOS en `docs/build.md`.

No se modifico masivamente OpenHantek6022. Se usa como referencia tecnica local. Por criterio de confianza, el backend principal no compila ni ejecuta OpenHantek.

## Capacidades detectadas

OpenHantek6022 tiene opciones de linea de comandos para arrancar la aplicacion, por ejemplo `--demoMode`, `--config`, `--useGLES`, `--noAutoConnect`, `--font`, `--size`, `--verbose` y opciones OpenGL. La exportacion CSV existe, pero esta implementada como exportador de GUI que abre un dialogo para elegir archivo.

No se detecto una CLI documentada del tipo:

```bash
OpenHantek --capture-to-csv capture.csv --samples 2048
```

Por esta razon, el modo `openhantek` no asume captura automatica. Detecta carpeta/binario y falla de forma explicita si no hay interfaz compatible. El camino principal de hardware ahora es `mode="usb"`.

En esta inspeccion local tampoco se encontro un binario compilado en las rutas comunes de build; la carpeta `OpenHantek` existente dentro de la base corresponde a codigo fuente, no a un ejecutable.

## Politica: no compilar

No se debe compilar ni ejecutar OpenHantek para este proyecto. La carpeta local se inspecciona como documentacion tecnica auditable: VID/PID, endpoints, comandos USB, firmware local y conversion ADC a voltaje.

El backend principal es `python/hantek_usb_backend.py`.

## Usar archivos CSV como puente

Si ya existen capturas CSV generadas previamente por OpenHantek u otra herramienta, pueden importarse sin ejecutar OpenHantek desde este proyecto:

1. Guardar el archivo en `data/raw/` o `data/examples/`.
2. Leerlo desde Python o MATLAB en modo `csv`.

Python:

```bash
python python/capture_example.py --mode csv --csv-path data/raw/captura.csv
```

MATLAB:

```matlab
data = hantek_acquire("csv", "csvPath", "data/raw/captura.csv");
metrics = analyze_signal(data);
plot_signal_report(data, metrics);
```

## Adaptador OpenHantek

`python/openhantek_adapter.py` queda como deteccion/referencia y rechaza captura automatica por politica de seguridad. No ejecuta binarios, no usa CLI y no enlaza codigo C++ externo.

El desarrollo de hardware debe hacerse en `python/hantek_usb_backend.py`.

## Limitaciones esperadas

- No se asume API Python oficial de OpenHantek6022.
- No se asume CLI de captura.
- El modo `openhantek` puede detectar carpeta y binario sin poder adquirir muestras automaticamente.
- La exportacion CSV de OpenHantek puede depender del locale: separador `,` o `;`, decimal `.` o `,`. El parser Python intenta soportar ambas variantes.
- En macOS pueden aparecer bloqueos por permisos USB, firma del bundle, Qt, libusb o acceso al dispositivo.
