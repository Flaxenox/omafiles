# Auditoría arquitectónica y de rendimiento (Fase 10)

Auditoría del estado del proyecto tras completar la migración del backend a
C++ (fases 5.C a 9). Complementa `BACKEND_DESIGN.md` (la spec vinculante) y
`ARCHITECTURE.md` (la separación de capas QML), que siguen siendo válidos.

Todos los hallazgos llevan fichero y línea. Los números de rendimiento están
**medidos** en esta máquina, no estimados: benchmark sobre `/usr/bin` real
(4132 entradas) ejecutado con el backend instalado.

Fecha: 2026-08-09.

---

## Estado de partida

Migrado y funcionando en vivo sobre el mismo `.so` en Quickshell y Qt6:
`DirectoryModel`, `ThumbnailProvider`, `PreviewProvider`, `JsonStore`,
`FileOperations`, `ProcessRunner`, `ProcessWatcher`, `Env`, `Detached`,
`Notifier`, más `QFileSystemWatcher` y `QThreadPool`.

Tamaño del proyecto: ~1700 líneas de C++ (`backend/`), ~3400 de lógica
(`logic/`), ~1750 de paneles, ~1200 de diálogos, 434 de estado, 221 de
servicios y **1596 en un solo fichero** (`core/OmafilesContent.qml`).

---

## P1 — Problemas reales (bugs / riesgo de crash)

### 1. `DirectoryModel` puede desreferenciar un puntero muerto

`backend/DirectoryModel.h:37` declara `QML_ELEMENT` **sin** `QML_SINGLETON`:
hay una instancia **por pestaña** (una por `DirLister`). Pero
`DirectoryModel.cpp:175-179` captura `this` crudo y llama
`QMetaObject::invokeMethod(this, ...)` **desde el hilo del pool**.

Cerrar una pestaña mientras su listado sigue en vuelo (carpeta grande, disco
lento, montaje de red) deja al worker desreferenciando un `QObject` ya
destruido. Es comportamiento indefinido: cuelgue o crash. `FileOperations`,
`ThumbnailProvider` y `PreviewProvider` se libran solo porque son singletons
(viven hasta el cierre del engine; aun así tienen la misma clase de riesgo en
el apagado, de severidad mucho menor).

**Impacto: alto.** Ventana pequeña, pero real, y crece con pestañas y red.

**Arreglo:** bandera de vida compartida (`std::shared_ptr<std::atomic_bool>`)
comprobada en el worker antes de invocar, o `QFutureWatcher` propiedad del
modelo (se cancela solo en el destructor).

### 2. Dos cachés que crecen sin límite

- **`tabEntriesCache`** (`core/OmafilesContent.qml:31`):
  `panels/BackgroundPanel.qml:56` hace
  `tabEntriesCache[path] = dirLister.entries` y **nadie lo vacía nunca**.
  Cada carpeta visitada en una pestaña de fondo retiene su array de entradas
  completo. Una visita a `/usr/bin` deja 4132 objetos vivos para siempre.
- **`videoThumbReady`** (`state/VideoThumbState.qml:10`): tampoco se vacía, y
  además `logic/VideoThumbnails.qml:53` hace `Object.assign({}, ...)`,
  **copiando el diccionario entero por cada miniatura generada** → coste
  cuadrático a lo largo de la sesión.

**Impacto: alto**, precisamente por el modo de uso: el plugin va con
`keepLoaded`, así que la app no se cierra nunca y la sesión dura días.

### 3. La caché de miniaturas no se poda nunca

La clave es `hash(ruta|tamaño|bytes|mtime)`. Cuando un fichero cambia, la
clave cambia y **la entrada antigua queda huérfana para siempre**: nunca se
vuelve a acertar y nunca se borra. Crece de forma monótona en disco.

---

## P2 — Rendimiento (medido)

Benchmark real sobre `/usr/bin` (4132 entradas), todo en el hilo de UI:

| Operación | Coste | Veredicto |
|---|---:|---|
| **4× `JSON.stringify`** por refresco | **74 ms** | desperdicio puro |
| **Re-ordenación en JS** (`sortEntries`) | **31 ms** | redundante *y* divergente |
| Lectura de `model.entries` (C++ → JS) | 0 ms | ya es barato |
| Filtro de búsqueda (`visibleEntries`) | 2 ms | irrelevante |

### 4. ~105 ms de tirón por refresco en carpetas grandes

`logic/DirLister.qml:87` hace dos `JSON.stringify` del array completo y
`logic/NavigationController.qml:60` hace **otros dos**: cuatro
serializaciones por refresco, ~330 KB de cadena cada una, es decir **~1,3 MB
de basura por refresco**. El watcher dispara esto en **cada** cambio del
directorio (con debounce de 400 ms): editar ficheros en una carpeta grande
produce un tirón visible cada vez.

Es doblemente absurdo porque la comparación existe solo para evitar un
relayout de la `ListView`… y cuesta más que el relayout que evita.

**Arreglo:** comparar en C++ (el modelo ya sabe si el contenido cambió) o
comparar por una firma barata (nº de entradas + agregado de mtimes), en vez
de serializar el array entero cuatro veces.

### 5. La ordenación de C++ se descarta, y además no coincide

`logic/DirLister.qml:151` aplica `sortOps.sortEntries()` en **todos** los
listados, así que el orden que calculó C++ nunca llega a verse. Y los dos
algoritmos **discrepan de verdad**:

```
file10  file2     ← C++ (wcscoll_l, réplica exacta de `sort -f`)
file2   file10    ← JS (Utils.naturalCompare)  ← este es el que se ve
```

Todo el trabajo fino de collation glibc en `nameLess()` (plegado de caja +
desempate sensible a mayúsculas) **no afecta a nada visible**. Fue necesario
para validar la paridad byte a byte con `list-dir.sh` durante la migración,
pero hoy es peso muerto que además cuesta CPU en cada escaneo.

**Arreglo:** decidir una sola ordenación. O se mueve `naturalCompare` a C++
(y se ganan los 31 ms del hilo de UI), o se simplifica el sort de C++ a lo
mínimo. Mantener las dos no tiene sentido.

### 6. `BackgroundPanel` no usa el pipeline de miniaturas

`panels/BackgroundPanel.qml:240` sigue cargando **la imagen completa**
(`Util.fileUrl(joinPath(...))`) para pintarla a 32 px. La optimización de la
Fase 8 solo llegó al panel activo (`panels/FileListRow.qml`). Una pestaña de
fondo con imágenes de 2 MB las decodifica enteras, una por fila.

---

## P3 — Mantenibilidad

### 7. `core/OmafilesContent.qml` es un god object (1596 líneas)

Triplica el límite de 300-500 líneas de las reglas de arquitectura del
proyecto. Es cuatro cosas a la vez: composition root, almacén de estado
mutable (**41 properties**), fachada de **45 funciones** envoltorio, y el
árbol de UI completo.

### 8. Acoplamiento bidireccional en estrella: 331 llamadas `root.*`

22 de los 23 componentes de `logic/` reciben `property Item root` y llaman de
vuelta al god object. Las más frecuentes:

| Llamada | Veces |
|---|---:|
| `root.currentPath` | 59 |
| `root.joinPath` | 35 |
| `root.runAction` | 34 |
| `root.visibleEntries` | 24 |
| `root.entries` | 13 |
| `root.pushUndo` | 12 |

La ironía: **existe una capa `state/` con 15 singletons creada justo para
evitar esto**, pero el estado más caliente (`currentPath`, `entries`,
`visibleEntries`, `showHidden`, `homeDir`) sigue viviendo en `root`. La
migración a `state/` se quedó a medio camino.

### 9. Dos esquemas de hash de caché conviviendo

`Utils.simpleHash` (JS, 32 bits; miniaturas de vídeo y archivos abiertos) y
SHA-1 en C++ (`ThumbnailProvider`). Dos formatos de clave, dos directorios de
caché, dos políticas de invalidación para el mismo problema.

---

## P4 — Arquitectura / escalabilidad

### 10. `DirectoryModel` es un `QAbstractListModel` que nadie usa como modelo

Los ocho roles (`name`, `path`, `type`, `isDir`, `isSymlink`, `link`, `size`,
`mtime`) son **código muerto**: la UI consume la propiedad `entries` (un
array). Se paga el precio conceptual del modelo sin ninguna de sus ventajas.
Mientras siga así, nunca habrá actualizaciones incrementales (`dataChanged`
por fila) ni scroll fluido de carpetas de 100k entradas.

### 11. Quedan 20 `bash -c`, todos en el motor de acciones

Es la última isla de shell y la más delicada: operaciones destructivas con
deshacer implementado como comandos inversos, conflictos tejidos en la
construcción de los comandos y progreso por sondeo con `du`.

---

## Plan priorizado

| # | Acción | Impacto | Esfuerzo | Riesgo |
|---|---|---|---|---|
| 1 | Eliminar los 4 `JSON.stringify` (comparar en C++ o por firma barata) | **Alto** | Bajo | Bajo |
| 2 | Arreglar el `this` colgante de `DirectoryModel` | **Alto** | Bajo | Bajo |
| 3 | Acotar `tabEntriesCache` (LRU ~8) y `videoThumbReady` (sin `Object.assign`) | **Alto** | Bajo | Bajo |
| 4 | Unificar la ordenación: `naturalCompare` a C++, tirar el sort duplicado | **Alto** | Medio | Bajo |
| 5 | `BackgroundPanel` → `ThumbnailProvider` | Medio | Bajo | Bajo |
| 6 | Poda de la caché de miniaturas (por antigüedad/tamaño, al arrancar) | Medio | Bajo | Bajo |
| 7 | Mover `currentPath`/`entries`/`showHidden` de `root` a `state/` | **Alto** (mantenibilidad) | Alto | Medio |
| 8 | Trocear `OmafilesContent` (UI ↔ composition root ↔ fachada) | Alto | Alto | Medio |
| 9 | Unificar el hashing de caché en el backend | Bajo | Bajo | Bajo |
| 10 | Decidir sobre `DirectoryModel`: usar los roles de verdad o degradarlo a proveedor de datos | Medio | Alto | Alto |
| 11 | Migrar el motor de acciones a `FileOperations` | Medio | **Muy alto** | **Alto** |

### Lectura del plan

**Bloque 1-6: un fin de semana, casi todo el beneficio real.** Eliminan
~105 ms de tirón por refresco, cierran un riesgo de crash y detienen tres
fugas de memoria. Ninguno toca la arquitectura, así que son seguros de hacer
ya y por separado.

**Bloque 7-8: el trabajo de fondo que permite crecer años.** Mientras
`logic/` dependa de `root`, cada componente nuevo suma acoplamiento y el
fichero de 1596 líneas seguirá creciendo. Es refactor mecánico pero amplio;
merece su propia fase, con la disciplina de las anteriores (cambios pequeños
de uno en uno, validando en vivo en los dos frontends).

**El 11 va al final**, por coherencia con lo decidido en la Fase 7: máximo
riesgo (destructivo + deshacer), valor sobre todo estético.

---

## Método

- Los números de la sección P2 se midieron con un harness QML sobre el
  backend instalado, listando `/usr/bin` real (4132 entradas) y cronometrando
  cada operación del camino caliente con `Date.now()`.
- El resto de hallazgos son lecturas directas del código, con fichero y línea
  citados, no impresiones.
- La divergencia de ordenación (§5) se verificó ejecutando `sort -fz` real y
  comparándolo con la salida de `naturalCompare`.
- Esta auditoría es solo diagnóstico: no se modificó ningún fichero del
  proyecto al elaborarla.
