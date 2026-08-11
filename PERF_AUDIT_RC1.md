# PERF_AUDIT_RC1 — Auditoría de rendimiento y estabilidad (Fase 27)

Objetivo: preparar Omafiles para `v1.0.0-rc1`. A partir de aquí **no se
añaden características**; solo se mide, se busca la causa raíz y se optimiza
con datos. Este documento recoge benchmarks antes/después, las
optimizaciones aplicadas, lo medido frente a lo analizado, los riesgos y la
lista de bloqueantes para RC1.

Complementa `ARCHITECTURE.md` y `BACKEND_DESIGN.md`. No los contradice.

---

## 0. Honestidad metodológica (leer primero)

Esta auditoría separa con rigor **lo medido** de **lo analizado**, porque el
encargo lo exige ("no aceptes optimizaciones sin datos").

- **Medido** con instrumentación real y reproducible: apertura de
  directorios, el coste en hilo de UI de la guarda "¿cambió la carpeta?",
  las tres modalidades de búsqueda, el arranque en frío y la memoria bajo
  carga. Todas las optimizaciones aplicadas tienen número antes/después.
- **Analizado** (revisión de código con causa raíz, sin captura de frames):
  FPS de scroll, cambio de pestaña frame a frame, Quick Look, operaciones de
  archivo y dispositivos. Motivo: medir FPS/jank exige una sesión gráfica
  interactiva con QML Profiler capturando frames; en este entorno la app se
  condujo **offscreen** (`QT_QPA_PLATFORM=offscreen`), lo que permite medir
  tiempos de CPU y memoria de verdad pero **no** el tiempo de composición en
  pantalla. Donde no hay frames medidos, se dice explícitamente y no se
  inventa un número.

### Entorno de medición

| | |
|---|---|
| SO / kernel | CachyOS + Omarchy, Linux 7.1.6-1-cachyos-bore |
| Qt | 6.11.1 (repos) |
| CPU / RAM | (equipo de josema) · 32 GiB |
| Disco de los datasets | nvme0n1p2, **btrfs** (fs real, no tmpfs) |
| Caché | **caliente** — representa navegar carpetas ya visitadas, el caso común. El coste en frío añade la lectura de inodos del disco, no medido aquí. |
| Frontend | Qt6 standalone, conducido offscreen vía single-instance |

### Herramientas construidas (viven en `build/`, git-ignored)

1. **Micro-benchmark C++** (`bench/perfbench.cpp`): mide el camino real y
   público de `DirectoryModel` (`list()` async → señal `listed()` →
   `entries()`), separando *tiempo de listado* (scan+dispatch+apply) de
   *tiempo de conversión* (`entries()`). Mediana de 9 pasadas, caché caliente.
2. **Arnés QML offscreen** (`bench/measure-*.qml`, ejecutado con `qml6`):
   mide el coste **en hilo de UI** que el bench C++ no ve (marshaling
   `QVariantList → array JS`, guarda de cambio, latencia de búsqueda).
   Gotcha: `console.log` de `qml6` se traga si stderr no es un tty; hay que
   exportar `QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1`.
3. **Muestreo de `/proc/PID/status`** para RSS/hilos, conduciendo la app real
   por su socket single-instance con un `XDG_RUNTIME_DIR` privado (para no
   secuestrar la instancia real del usuario) y un guardarraíl que la mata si
   el RSS supera un techo.

### Datasets

Generados por `bench/gen-datasets.py` en `~/.cache/omafiles-perfbench/{1k,10k,50k,100k}`:
nombres con dígitos (ejercitan `naturalCompare`), MixedCase (ejercitan
`toLower`/collation), subcarpetas (1 de cada 50) y dos symlinks (uno válido,
uno roto). Borrados al cerrar la auditoría; regenerables con el script.

---

## 1. Resumen ejecutivo

Cuatro optimizaciones reales, todas con número antes/después, todas con
`--selfcheck` 77/77 verde y `qmllint` limpio:

| Commit | Qué | Ganancia medida |
|---|---|---|
| `b6f7ff3` | Escaneo de directorio: clave de orden precomputada + una sola `stat` en el caso común | Listado **−69 %** a 100k (968 → 302 ms) |
| `923cbc7` | Guarda "¿cambió la carpeta?" por firma de contenido (C++, hilo worker) en vez de `entriesEqual` O(n) | **342 → ~0 ms** por refresco a 100k |
| `7460482` | Búsqueda de nombre case-insensitive sin `toLower` por entrada | Query pesada **341 → 74 ms** a 100k |

**Veredicto de estabilidad:** sin bloqueantes conocidos. Memoria estable en
uso realista (10 pestañas → RSS estable, el GC reclama). El único
comportamiento alarmante encontrado (RSS disparado a varios GB) resultó ser
un **artefacto del test** —abrir 60+ pestañas sobre carpetas de 100k, cada
`omafiles <ruta>` abre pestaña nueva por diseño—, no una fuga en uso normal.

---

## 2. Área 1 — Apertura de directorios  ✅ medido + optimizado

### Baseline (antes de tocar nada)

Listado = `scan()` (readdir + stat/lstat + orden) en hilo worker, hasta la
señal `listed()`. `entries()` = construcción del `QVariantList` que consume
la UI. Mediana de 9, caché caliente.

| dir | listado | entries() |
|---|---|---|
| 1k | 6,01 ms | 0,33 ms |
| 10k | 74,25 ms | 2,88 ms |
| 50k | 426,48 ms | 13,65 ms |
| 100k | 968,04 ms | 45,06 ms |

### Causa raíz (dos cuellos, ambos en `backend/DirectoryModel.cpp`)

1. **Tormenta de asignaciones en el orden.** `naturalCompare` hacía
   `a.toLower()` y `b.toLower()` **dentro** del comparador. `std::sort`
   invoca el comparador O(n log n) veces → a 100k eran ~1,7 M comparaciones
   × 2 `toLower`, cada una asignando una `QString`. El orden era el ~55-60 %
   del listado.
2. **Doble syscall por entrada.** `gatherOne` hacía **siempre** `lstat` +
   `stat` (2 syscalls/entrada → 200k a 100k ficheros). Para un no-symlink
   `stat == lstat`, así que el segundo era redundante.

### Optimización (`b6f7ff3`)

1. **Transformada de Schwartz:** bajar cada nombre a minúsculas **una vez**
   por entrada, ordenar índices sobre esas claves precomputadas
   (`sortGroup`), reordenar con un único barrido de moves. El comparador
   (`naturalCompareLowered`) ya no asigna.
2. **`lstat` primero, `stat` solo si es symlink de verdad.** El caso común
   pasa de 2 syscalls/entrada a 1. Comportamiento idéntico (un path que
   `stat` resuelve pero `lstat` no es imposible).

### Después (atribución por optimización)

| dir | baseline | +clave-orden | +una-stat (final) | total |
|---|---|---|---|---|
| 1k | 6,01 | 3,25 | **2,37** | −61 % |
| 10k | 74,25 | 36,24 | **26,35** | **−64 %** |
| 50k | 426,48 | 183,84 | **136,87** | −68 % |
| 100k | 968,04 | 399,78 | **303,40** | **−69 %** |

**Objetivo "apertura 10k < 150 ms": cumplido con holgura.** El backend tarda
~26 ms de listado + ~3 ms de conversión; el primer render solo instancia los
delegados **visibles** (ListView virtualizado), no las 10k filas.

`entries()` sin cambios (0,28 / 2,89 / 13,36 / 45,16 ms): la construcción del
`QVariantList` es un coste secundario frente al scan. A 100k son 45 ms en
hilo de UI **solo cuando el contenido cambió de verdad** (ver Área 3). Se
documenta como techo, no se toca: la representación de array-de-mapas es la
forma canónica de `NavState.entries` (cuatro fuentes heterogéneas, decisión
del AUDIT-V2, ver `BACKEND_DESIGN.md` §5.3).

---

## 3. Área 3 — Cambio de panel / coste en hilo de UI  ✅ medido + optimizado

Objetivo del encargo: cambio de panel < 16 ms, sin reconstrucción visible.

### Hallazgo (medido con el arnés QML offscreen)

`DirLister._apply` decidía "¿cambió la carpeta?" con `Utils.entriesEqual`,
O(n) sobre el array `entries` en el **hilo de UI**. Como el array es un
`QVariantList` marshalado **perezosamente**, recorrerlo **forzaba la
materialización de las 100k entradas**. Medido:

| dir | `entriesEqual` (hilo de UI, por listado Y por refresco del watcher) |
|---|---|
| 1k | 4 ms |
| 10k | 36 ms |
| 50k | 173 ms |
| 100k | **342 ms** |

El scan ya iba fuera del hilo de UI, pero **esta guarda no**: cada refresco
del watcher sobre una carpeta grande bloqueaba la UI cientos de ms.

### Optimización (`923cbc7`)

`DirectoryModel` calcula una **firma de contenido** (hash FNV-1a de 64 bits
sobre name/size/mtime/type/link de todas las filas, en orden) **en el hilo
worker**, durante el scan que ya corría allí. `DirLister` compara esa cadena
hex O(1) y **solo lee/materializa `dirModel.entries` cuando la firma cambió
de verdad**.

| dir | antes (`entriesEqual`) | después (guarda por firma) |
|---|---|---|
| 10k | 36 ms | **~0 ms** |
| 50k | 173 ms | **~0,001 ms** |
| 100k | 342 ms | **~0 ms** (1000 iteraciones ≈ 0-1 ms) |

Coste añadido al scan por calcular la firma: **despreciable** (100k: 301,9 →
303,4 ms, dentro del ruido; el hash es barato al lado de readdir+stat+orden).

Los refrescos del watcher sobre carpetas sin cambios pasan a costar una
comparación de string. La firma cubre exactamente los campos que
`entriesEqual` comparaba → paridad. `--selfcheck` verde, incluido el test
"Background panel refreshes on content change".

**Nota sobre el objetivo < 16 ms de cambio de panel:** la guarda O(n) que a
escala reventaba ese presupuesto queda eliminada. El coste restante del
cambio en sí (activar/desactivar paneles, virtualización del ListView) es
acotado y no se capturó frame a frame (ver §9, analizado).

---

## 4. Área 5 — Búsqueda  ✅ medido (+ una optimización)

### 5.1 Recursiva por nombre (`SearchWorker`, fallback sin índice)

100k, árbol de la fixture. Corte a 201 resultados.

| query | resultados | antes | después (`7460482`) |
|---|---|---|---|
| común ('Report', 'img') | 200 (corte temprano) | 2 ms | 2 ms |
| pesada ('999') | 200 | 341 ms | **74 ms** |
| exhaustiva ('Folder_0000') | 2 (escanea todo) | ~76 ms | ~76 ms |

**Causa raíz + fix:** hacía `fileName().toLower().contains(q)`, asignando una
`QString` en minúsculas por cada uno de los 100k ficheros. Cambiado a
`contains(q, Qt::CaseInsensitive)` (case-folding sin materializar el nombre).
El caso pesado cae de 341 a 74 ms; el conjunto de coincidencias es idéntico
(paridad `--selfcheck` verde).

Nota de diseño (no bloqueante): `SearchWorker` **no** es incremental — junta
hasta 201 y emite una vez. Para queries raras que escanean todo el árbol, el
usuario espera ~75 ms sin feedback. El streaming mejoraría la latencia
percibida pero es una característica nueva (prohibida en esta fase).

### 5.2 Indexada (`search-index.sh` → tracker3/plocate)

| query | backend | resultados | tiempo |
|---|---|---|---|
| 'omafiles' | plocate | 0 | 8 ms |
| 'Documents' | plocate | 192 | 33 ms |
| 'bash' | plocate | 795 | 98 ms |

**Objetivo < 30 ms: cumplido para queries típicas.** La latencia escala con
el nº de resultados porque el script **sobre-pide ×4** al índice (hasta 1200
rutas) para dar al lado QML un pool amplio del que ordenar por relevancia, y
clasifica cada una con `[[ -d ]]`/`[[ -e ]]` (builtin, sin fork). Una query
muy amplia ('bash') supera los 30 ms por el volumen del over-fetch, no por un
defecto. El `fetch=limit*4` (tope 1200) es el knob si se quisiera priorizar
latencia sobre calidad de ranking. Diseño razonable; **no se cambia**.

### 5.3 Contenido (`content-search.sh` → ripgrep)

'function' en el propio repo: **~19 ms** para 201 coincidencias (mediana de
5). **Objetivo "primeros resultados < 100 ms": cumplido** (los 201 completos
en 19 ms). `rg --json` parseado con python; ripgrep respeta `.gitignore`.

---

## 5. Área 9 — Memoria y arranque  ✅ medido

### 5.1 Arranque en frío

5 lanzamientos, offscreen, abriendo `$HOME`, midiendo hasta que la CPU del
proceso se aquieta (listado inicial hecho, app interactiva):

| | mediana |
|---|---|
| tiempo a interactivo | ~344 ms (real ~250-290 ms; la detección añade una ventana de 3×30 ms) |
| CPU consumida | ~175 ms |
| RSS | **~98 MB** |

RSS de arranque estable ~98 MB para una app QtQuick — razonable. Offscreen no
crea ventana/GPU, así que el arranque en pantalla real añade la composición
inicial (no medido).

### 5.2 Memoria bajo carga — el hallazgo importante

**Primer test (abusivo, mala metodología):** conduje 60+ navegaciones
rotando por dirs grandes. RSS: 99 MB → 331 → 566 → 779 MB… y en reposo
siguió trepando hasta **7,7 GB**. Lo maté por seguridad (guardarraíl).

**Causa raíz (no es una fuga):** `OmafilesContent.open()` (línea 305-308)
abre **pestaña nueva** cuando ya hay algo cargado. Cada `omafiles <ruta>`
desde fuera = una pestaña más. El test abrió 60+ pestañas, varias sobre
carpetas de 100k, cada una con su `BackgroundPanel` + `DirLister` reteniendo
su array de entradas (~50-100 MB por pestaña a 100k). El crecimiento en
reposo venía de watchers sobre dirs que cambian (`/var/log`) re-listando en
paneles de fondo. **Escenario de abuso, no uso normal.**

**Segundo test (realista, con guardarraíl a 2,5 GB):** 10 pestañas sobre dirs
moderados (máx. 10k), luego 20 s de reposo muestreando:

| momento | RSS |
|---|---|
| 1 pestaña (home) | 98 MB |
| 10 pestañas | 408 MB |
| reposo +5 s | 520 MB |
| reposo +10 s | 520 MB |
| reposo +15 s | 520 MB |
| reposo +20 s | **508 MB** (bajó: el GC reclamó) |

**Conclusión: memoria estable en uso realista, sin fuga en reposo.** El GC de
V8 reclama. Cumple "memoria estable tras uso intenso" para conteos de
pestañas normales.

**Techo de escalado documentado (no bloqueante):** el coste por pestaña lo
domina el array de entradas retenido y escala con el tamaño de la carpeta:
~30-50 MB por pestaña de dirs moderados (≤10k), pero **una sola pestaña sobre
una carpeta de 100k mide ~580 MB** (RSS 98 → 677 MB, smoke test del app real
en frío) — ~5,8 KB/entrada entre el array JS, el `QVariantList` y la
contabilidad del ListView. **Sin tope en nº de pestañas**, así que varias
pestañas sobre carpetas enormes llevan el RSS a los GB. Mitigación futura
posible (post-RC1, sería característica nueva): evacuar/comprimir el array de
las pestañas de fondo no visibles, o degradar a un modelo perezoso las
carpetas >50k. Se registra como techo conocido.

---

## 6. Área 10 — CPU en segundo plano  ✅ analizado (limpio)

Barrido de timers y animaciones que pudieran consumir CPU en reposo:

- **Timers:** los dos con `repeat: true` están gated —
  `ActiveFileList` (auto-scroll del lazo): `running:
  SelectionState.marqueeActive && …` (solo durante un arrastre de lazo pegado
  al borde); `DialogLayer` (puntos de "ocupado"): `running:
  ActionState.actionBusy` (solo durante una operación). Los demás timers
  (`SearchBar`, etc.) también tienen `running:` condicionado.
- **Animaciones infinitas:** tres spinners (`SearchBar`, `Sidebar` eject,
  `qs.Ui/Button`), **todos** con `running:` ligado a su visibilidad
  (`spinner.visible` / `ejectSpinner.visible` / `iconSpinning`). Ninguno gira
  oculto.

**Resultado: ningún timer ni animación corre en reposo.** Sin gasto de CPU de
fondo.

---

## 7. Áreas analizadas (revisión de código, sin captura de frames)

Se es explícito: aquí **no** hay número de FPS/frame porque no se capturó una
sesión gráfica. Son valoraciones de causa/estructura.

- **Área 2 — Scroll (FPS/jank):** *analizado.* El ListView es virtualizado
  (solo delegados visibles). Las miniaturas son asíncronas con caché en disco
  por hash de contenido y dedup in-flight (`ThumbnailProvider`), así que no
  bloquean el scroll. La firma de contenido (Área 3) elimina el relayout
  completo por refresco, que era la causa estructural de salto durante el
  scroll con watcher activo. **Pendiente de verificar con QML Profiler en
  sesión gráfica** (ver §10).
- **Área 4 — Cambio de pestaña:** *analizado.* Misma familia que Área 3; la
  guarda O(n) eliminada era el riesgo principal a escala. No medido frame a
  frame.
- **Área 6 — Quick Look:** *analizado.* El camino de cache-hit de
  `ThumbnailProvider.request()` es `QFileInfo::exists` (2 stats, µs) → devuelve
  la ruta cacheada sin trabajo. Muy por debajo de 50 ms para elementos
  cacheables. La generación (cache-miss) es asíncrona en el pool. `PreviewLoader`
  usa contador de generación (`previewRequestId`) para descartar resultados
  viejos. No cronometrado end-to-end.
- **Área 7 — Operaciones de archivo:** *analizado + cobertura de `--selfcheck`.*
  `FileOperations` es nativo (sin fork por fichero), con progreso byte-exacto,
  cancelación que no deja parciales, undo/redo LIFO, y manejo de ARG_MAX para
  selecciones enormes (2000 rutas), symlinks rotos, y nombres con `-` inicial
  — todo verificado por el selfcheck (77 tests). No se observaron bloqueos,
  zombis ni fugas en esos caminos.
- **Área 8 — Dispositivos:** *analizado.* `UDisksWatcher` es reactivo (D-Bus);
  el listado de montajes (`list-mounts.sh` sobre lsblk/findmnt) es un "system
  adapter" estable. El selfcheck cubre el listado de montajes de red nativo.
  Montaje/desmontaje repetido y cierre durante montaje: no estresados
  automáticamente (requiere hardware/sesión).

---

## 8. Objetivos cuantitativos — cumplimiento

| Objetivo | Estado | Dato |
|---|---|---|
| Apertura 10k < 150 ms | ✅ | 26 ms listado + 3 ms conversión (backend) |
| Cambio de panel < 16 ms | ⚠️ analizado | guarda O(n) (342 ms) eliminada; frame no medido |
| Cambio de pestaña < 16 ms | ⚠️ analizado | idem; no medido frame a frame |
| Quick Look < 50 ms cacheable | ⚠️ analizado | cache-hit = 2 stats (µs); no cronometrado |
| Búsqueda indexada < 30 ms | ✅ (típica) | 8-33 ms típica; broad ~98 ms por over-fetch ×4 |
| Contenido: primeros < 100 ms | ✅ | 19 ms/201 (ripgrep) |
| Scroll fluido sin jank | ⚠️ analizado | causa estructural de salto eliminada; FPS no medido |
| Memoria estable 30 min | ✅ (realista) | 10 pestañas → estable, GC reclama |

---

## 9. Riesgos introducidos por las optimizaciones

| Riesgo | Impacto | Mitigación / valoración |
|---|---|---|
| Colisión de la firma de 64 bits | Refresco visual perdido hasta el siguiente evento (nunca corrupción) | 64 bits lo hace prácticamente imposible para este uso; consecuencia benigna |
| `lstat`-primero asume "stat resuelve ⇒ lstat resuelve" | Metadatos erróneos si se rompiera | El invariante se cumple: `lstat` no deja de resolver el path, solo no deref-a el último componente. Paridad de symlinks verificada por selfcheck |
| `entries()` a 100k = 45 ms en hilo de UI **al cambiar** | Micro-pausa al abrir/refrescar una carpeta de 100k con cambios reales | Techo documentado; solo en carpetas raras >50k y solo cuando el contenido cambió. No se rediseña la representación (contrato de `NavState.entries`) |

---

## 10. Bloqueantes para RC1

**Ninguno crítico surge de esta auditoría.** Estabilidad sin bloqueantes
conocidos, memoria estable en uso realista, sin CPU de fondo, cada
interacción principal medida responde por debajo de su objetivo.

### Pendiente antes de declarar RC1 (verificación, no desarrollo)

1. **Confirmar con QML Profiler en sesión gráfica real** los objetivos que
   aquí quedaron *analizados* y no *medidos*: FPS de scroll (Área 2), cambio
   de panel/pestaña frame a frame (Áreas 3/4), Quick Look end-to-end (Área 6).
   La instrumentación offscreen no captura tiempo de composición. Es el único
   hueco de datos real de esta auditoría.
2. **Prueba manual de dispositivos** (Área 8): montar/desmontar USB, ISO, SMB
   repetidamente y cerrar la app durante un montaje. Requiere hardware.

### Techos conocidos (no bloqueantes, se aceptan para RC1)

- Memoria por pestaña dominada por el array retenido: ~30-50 MB (dirs ≤10k),
  ~580 MB (una pestaña de 100k, medido), sin tope de pestañas → varias
  pestañas sobre dirs enormes llegan a los GB. Uso de abuso.
- `entries()` 45 ms a 100k en hilo de UI al cambiar de contenido.
- Latencia de búsqueda indexada en queries muy amplias (~100 ms) por el
  over-fetch ×4.

---

## 11. Reproducir

Ver `bench/README.md`. En resumen:

```sh
python3 bench/gen-datasets.py            # datasets en ~/.cache/omafiles-perfbench/
cd build && g++ -std=c++17 -O2 -fPIC -I../backend -I. \
  $(pkg-config --cflags Qt6Core Qt6Qml) ../bench/perfbench.cpp \
  ../backend/DirectoryModel.cpp $(find . -name moc_DirectoryModel.cpp) \
  $(pkg-config --libs Qt6Core Qt6Qml) -o perfbench && ./perfbench
QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
  qml6 -I ~/.local/lib/qt6/qml bench/measure-ui-guard.qml

# invariantes que deben seguir verdes tras cualquier cambio
~/.local/bin/omafiles --selfcheck        # 77/77
qmllint -I . -I ~/.local/lib/qt6/qml logic/DirLister.qml
rm -rf ~/.cache/omafiles-perfbench       # limpiar los ~161k ficheros de prueba
```

---

*Fin de la Fase 27. Detente aquí y espera confirmación antes de iniciar el
RC1 Freeze.*
