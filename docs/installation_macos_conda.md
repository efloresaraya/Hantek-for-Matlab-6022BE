# Instalacion en macOS con conda

## Entorno Python

Desde la raiz del proyecto:

```bash
conda env create -f environment.yml
conda activate hantek6022be-matlab
python python/test_connection.py
```

Para USB directo, `pyusb` se instala desde `requirements.txt`. En macOS tambien debe existir `libusb` en el entorno o sistema. Con conda-forge puede agregarse con:

```bash
conda install -c conda-forge libusb
```

Si falla una prueba USB, revise la bitacora generada en `data/logs/`. Tambien puede fijar la ruta:

```bash
python python/test_connection.py --mode usb --log-path data/logs/diagnostico_usb.log
```

## MATLAB y Python

En MATLAB, seleccione el Python del entorno conda:

```matlab
pyenv("Version", "/ruta/a/conda/envs/hantek6022be-matlab/bin/python")
```

Luego pruebe:

```matlab
run("matlab/main_v2_python_bridge.m")
```

## OpenHantek6022

No es necesario compilar OpenHantek para el backend principal. El modo `usb` no ejecuta OpenHantek; solo usa la carpeta local como referencia tecnica y como ubicacion del firmware verificado por SHA256.
