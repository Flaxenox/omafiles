# bench/ — arnés de rendimiento (Fase 27, PERF_AUDIT_RC1)

Herramientas de medición reproducibles usadas en `PERF_AUDIT_RC1.md`. No
forman parte de la app; se ejecutan a mano.

| Fichero | Qué mide |
|---|---|
| `gen-datasets.py` | Genera `~/.cache/omafiles-perfbench/{1k,10k,50k,100k}` (nombres con dígitos/MixedCase, subdirs, symlinks válido+roto). |
| `perfbench.cpp` | Camino real de `DirectoryModel` (`list()` async → `listed()` → `entries()`): separa tiempo de listado del de conversión. Mediana de 9, caché caliente. |
| `measure-ui-guard.qml` | Coste EN HILO DE UI de la guarda "¿cambió la carpeta?" (firma O(1)) que sustituyó a `entriesEqual` O(n). |
| `measure-search.qml` | Latencia de `SearchWorker` (búsqueda recursiva por nombre). |

## Uso

```sh
# 1) datasets
python3 bench/gen-datasets.py

# 2) bench C++ del listado
cd build   # el árbol de build de cmake/ninja ya existe
g++ -std=c++17 -O2 -fPIC -I../backend -I. \
  $(pkg-config --cflags Qt6Core Qt6Qml) \
  ../bench/perfbench.cpp ../backend/DirectoryModel.cpp \
  $(find . -name moc_DirectoryModel.cpp) \
  $(pkg-config --libs Qt6Core Qt6Qml) -o perfbench
./perfbench

# 3) arneses QML (gotcha: sin estas dos vars, qml6 se traga console.log)
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  qml6 -I ~/.local/lib/qt6/qml bench/measure-ui-guard.qml
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  qml6 -I ~/.local/lib/qt6/qml bench/measure-search.qml
```

Las rutas de los datasets están hardcodeadas en los `.qml`/`.cpp` a
`~/.cache/omafiles-perfbench/`. Borra ese árbol al terminar (son ~161k
ficheros): `rm -rf ~/.cache/omafiles-perfbench`.
