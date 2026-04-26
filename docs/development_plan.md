# Plan de desarrollo

## Estado actual

- `simulator` y `csv` funcionan como modos base.
- `usb` funciona con firmware local verificado y backend propio PyUSB/libusb.
- MATLAB puede capturar en vivo por bloques con `main_v6_usb_live_app.m`.
- MATLAB tiene vista dual CH1+CH2 por bloques con `main_v9_usb_dual_live_app.m`.
- CH1 y CH2 fueron validados en modo dual a `10 MS/s`.
- Se corrigio una discontinuidad temporal en modo dual: la lectura bulk ya no se
  hace en trozos de `64 KB`, sino en solicitudes grandes de hasta `1 MB`.
- La app live guarda paquetes CSV/MAT/PNG desde `Save CSV+MAT+PNG`.
- Existe chequeo no destructivo de offset/gain con `main_v8_calibration_check.m`.
- Existe calibracion software local en `data/software_calibration.json`, aplicada
  opcionalmente por `hantek_acquire(..., "applyCalibration", true)` y por `Cal SW`.
- OpenHantek sigue solo como referencia tecnica local. No se compila ni ejecuta.

## Fase 1: base estable

- Mantener `simulator` funcionando siempre.
- Mantener `csv` como puente real inicial.
- Usar `data/examples/example_openhantek_export.csv` para pruebas rapidas.
- Ejecutar `python/test_connection.py` despues de cambios.
- Ejecutar `python -m unittest python/test_usb_backend.py` despues de cambios USB.

## Fase 2: validacion con archivos y referencia local

- No compilar ni ejecutar OpenHantek.
- Mantener OpenHantek como referencia tecnica local.
- Exportar o reunir capturas CSV manuales solo si ya existen desde herramientas externas confiables.
- Validar lectura en MATLAB con `main_v1_csv_import.m`.

## Fase 3: automatizacion parcial

- [x] Validar `mode="usb"` con el Hantek 6022BE fisico.
- [x] Confirmar deteccion loader `04b4:6022`, carga de firmware local y renumeracion a `04b5:6022`.
- [x] Capturar CH1 y CH2.
- [x] Validar modo dual CH1/CH2 con `main_v7_ch2_diagnostic.m`.
- [x] Mantener un modo MATLAB en vivo por bloques USB para forma de onda, FFT y metricas en tiempo real.
- [x] Mantener un panel MATLAB simple con controles de canal, escala, tasa, muestras, trigger software, ejes, inicio/detencion y guardado de ultima captura.
- [x] Agregar panel dual CH1+CH2 con presets, trigger software con fuente,
  flanco y nivel manual/auto, `Cal SW`, metricas por canal, delay CH2-CH1 y
  guardado dual CSV/MAT/PNG.
- [x] Agregar guardado dual calibrado + raw y CSV raw adicional.
- [x] Ajustar reportes PNG duales para usar zoom FFT configurado.
- [x] Agregar tabla de metricas dentro de la app dual.

## Fase 4: backend directo

- Documentar procedimiento de verificacion fisica CH1/CH2 con calibrador.
- [x] Mejorar guardado de sesiones desde la app live: CSV + MAT + PNG de reporte.
- [x] Agregar calibracion software local no destructiva de offset/gain.
- Agregar calibracion opcional solo lectura desde EEPROM.
- Agregar seleccion de rangos mas completa.
- Agregar prueba de regresion con CSV dual real en `data/examples` o `data/raw`
  para detectar discontinuidades temporales sin hardware.
- Mantener OpenHantek como referencia tecnica, sin compilarlo ni ejecutarlo.

## Siguientes pasos recomendados

1. Usar `main_v6_usb_live_app.m` como interfaz principal y validar CH1/CH2 con
   la punta en `1x` sobre el calibrador.
2. Guardar una captura limpia CH1 y una CH2 desde la app live.
3. Ejecutar `main_v8_calibration_check.m` en CH1 y CH2, guardando reportes.
4. Agregar presets de laboratorio: calibrador `1 kHz`, senal baja frecuencia,
   senal externa y prueba dual.
5. Agregar pruebas de regresion sobre CSV duales reales para detectar saltos de
   tiempo, duty/frecuencia fuera de rango y calibracion mal aplicada.
