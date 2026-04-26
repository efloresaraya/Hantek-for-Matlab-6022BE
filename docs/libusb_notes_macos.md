# Notas libusb en macOS

El backend `usb` usa `PyUSB/libusb` para comunicarse con el Hantek 6022BE. En macOS, los puntos de falla mas comunes son:

- Dependencia `libusb` no instalada o no visible para PyUSB.
- Permisos o reclamo del dispositivo USB por otro proceso.
- Renumeracion USB del 6022BE antes/despues de cargar firmware.

Comandos utiles para validar dependencia Python:

```bash
python -c "import usb.core; print('PyUSB OK')"
python python/test_connection.py --mode usb --n-samples 20000
```

El backend `usb` no usa drivers externos de Hantek ni ejecuta OpenHantek.
