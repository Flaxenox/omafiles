# Omafiles — Auditoría de bugs y regresiones v3

**Fecha:** 2026-08-10 · **Commit auditado:** `2e2da2d` (HEAD) · **Working tree:** con cambios sin commitear (micro-transiciones Fase 22 en `dialogs/`, `panels/`, `core/DialogLayer.qml`) · **Auditorías previas:** `AUDIT.md`, `AUDIT-V2.md`

---

## Executive summary

Esta auditoría es de **bugs reproducibles**, no de arquitectura. La conclusión honesta es incómoda pero acotada:

> **El backend nativo está blindado; el frontend de interacción y los restos de shell no lo están. La brecha de riesgo ya no es "qué código es frágil", sino "qué código no mira nadie que no sea un humano con un ratón".**

Tres hechos que enmarcan todo el informe:

1. **El selfcheck (70/70 verde) es magnífico… en el backend.** De sus ~70 pruebas, la aplastante mayoría ejercita `FileOperations` (copy/move/remove/trash/restore/conflict/progress/cancel) y servicios C++. Eso está excelentemente cubierto.

2. **Pero el propio historial lo desmiente como red de seguridad completa:** el commit auditado (`2e2da2d`) arregla una regresión **real y grave** — `empty-trash.sh` dependía de `trash-roots.sh`, que se había eliminado, así que **"Vaciar papelera" no borraba nada** — y el selfcheck seguía en verde mientras el bug estaba vivo. No hay ninguna prueba de vaciado de papelera. Esa clase de regresión (operación de UI respaldada por un script `.sh`) es exactamente la que puede repetirse sin ser detectada.

3. **La deuda de shell no ha desaparecido, se ha replegado.** La Fase 13 migró las operaciones *destructivas* a C++ nativo (bien), pero **la detección de conflictos que las precede sigue en `bash` (`test -e`)**, igual que Properties (`stat`/`du`), la extracción de archivos y el portapapeles. Ahí viven los bugs de este informe.

**Veredicto para RC1:** el informe identificó **2 bloqueantes de severidad Alta** (BUG-01, inconsistencia de la detección de conflictos; BUG-02, ninguna cobertura de las operaciones respaldadas por script). **Ambos quedaron RESUELTOS en Hardening-1** (2026-08-10) — ver sus entradas. No quedan bloqueantes de RC1 pendientes; el resto de hallazgos es Media/Baja. El selfcheck pasó de 70 a **75** pruebas, todas verdes.

---

## Alcance real de esta auditoría (honestidad de método)

La regla vinculante era **"no propongas soluciones antes de demostrar el problema"**. La respeto: solo listo como bug lo que he podido reproducir o demostrar por inspección con evidencia. Por eso este informe distingue tres estados:

- **CONFIRMADO** — reproducido en esta sesión (comando/traza incluida).
- **DEMOSTRADO POR CÓDIGO** — la causa es visible y determinista en el fuente; el disparo concreto está descrito.
- **PENDIENTE DE SESIÓN INTERACTIVA** — requiere hardware real (USB/ISO/discos), carpetas de 10k–50k montadas, o inyección de teclado/ratón fiable, que no es reproducible en modo headless. **No invento resultados para estas**; documento el método exacto de reproducción para la siguiente pasada.

Lo que **sí** se ejecutó en esta sesión: `--selfcheck` completo (70/70, exit 0), `qmllint`, y reproducción directa en shell de los casos límite de BUG-01 y BUG-03.

Lo que **no** se pudo ejercitar headless y queda para pasada interactiva: rendimiento a 10k/50k entradas, drag & drop real, montaje/desmontaje de USB/ISO/red físicos, preview GPU-dependiente (PDF/vídeo/imagen en panel), e inyección de teclado (limitación ya documentada en AUDIT-V2 R2).

---

## Tabla de incidencias (priorizada)

| ID | Gravedad | Frontend | Estado | Título |
|---|---|---|---|---|
| BUG-01 | 🟠 Alta | Ambos | ✅ **RESUELTO (Hardening-1)** | Detección de conflictos sigue en shell `test -e`: inconsistente con las ops nativas y ciega a symlinks rotos |
| BUG-02 | 🟠 Alta | Ambos (arnés) | ✅ **RESUELTO (Hardening-1)** | Las operaciones respaldadas por `.sh` (vaciar papelera, montaje, archivos) no tienen ninguna cobertura de selfcheck |
| BUG-03 | 🟡 Media | Ambos | ✅ **RESUELTO (Hardening-2)** | Properties construye `stat`/`du` en una sola línea `bash -c`: desbordamiento de ARG_MAX en selección enorme |
| BUG-04 | 🟡 Media | Ambos | ✅ **RESUELTO (Hardening-2)** | La animación de salida de los diálogos (Fase 22) nunca se renderiza |
| BUG-05 | 🔵 Baja | Ambos | ✅ **RESUELTO (Hardening-2)** | Preview de archivos: `tar` sin `--` mientras zip/7z/rar sí lo llevan |
| OBS-A | ⚪ Obs. | Ambos | CONFIRMADO (negativo) | El contador de items maneja `-1` (dir ilegible) correctamente — no es bug, se documenta como resiliencia verificada |

---

## Incidencias detalladas

### BUG-01 — La detección de conflictos sigue en `bash test -e`, inconsistente con las operaciones nativas

- **ID:** BUG-01
- **Gravedad:** 🟠 Alta
- **Frontend afectado:** Ambos (código compartido en `logic/ConflictActions.qml`)
- **Estado:** ✅ **RESUELTO en Hardening-1** (commit `fix: unify conflict detection and add shell smoke coverage`). Ver "Resolución" al final de la entrada.

**Pasos de reproducción (mitad confirmada):**
```
$ tmp=$(mktemp -d); ln -s /no/existe "$tmp/roto"
$ bash -c 'test -e "$1" && echo CONFLICTO || echo "sin conflicto"' _ "$tmp/roto"
sin conflicto              # <-- test -e = falso sobre un symlink roto
$ ls -la "$tmp/roto"
roto -> /no/existe         # ...pero el destino SÍ existe como entrada de directorio
```
Escenario de usuario: copiar/cortar un fichero `X` y pegarlo en una carpeta donde `X` ya existe **como symlink roto** (apunta a algo borrado). O renombrar/crear un fichero con ese destino.

**Comportamiento esperado:** el destino existe (hay una entrada de directorio llamada `X`), así que Omafiles debería mostrar el diálogo de resolución de conflicto (sobrescribir / omitir / renombrar), igual que hace con un fichero normal.

**Comportamiento observado:** `ConflictActions` decide "no hay conflicto" (porque `test -e` sigue el symlink y devuelve falso), se salta el diálogo, y lanza la operación nativa. La operación nativa (`FileOperations`) decide por su cuenta con semántica lstat-based distinta. El resultado es una **incoherencia entre el guardián (shell) y la acción (nativa)**: o bien la op nativa falla con "destination already exists" y el pegado se cae sin explicación, o bien actúa sin la confirmación que el usuario habría visto para cualquier otro tipo de fichero.

**Causa raíz:** la Fase 13 migró las operaciones destructivas a C++ (`FileOperations`, con `existingPaths()` nativo y detección de symlinks — ver selfcheck "Conflict detection: existingPaths (file/dir/symlink)"), pero **la comprobación previa que dispara el diálogo de conflicto se quedó en `bash`**. `logic/ConflictActions.qml` conserva 6 llamadas a `test -e ... && echo 1 || echo 0` (líneas 107, 144, 175, 196, 221, 239) y `RenameOps`/`FileOps` construyen sus comandos con `test -e`. `test -e` y el `existingPaths()` nativo **no comparten semántica de symlinks**, y coexisten dos caminos para responder la misma pregunta ("¿existe el destino?").

**Cobertura del selfcheck:** parcial y engañosa. El selfcheck prueba `FileOperations.existingPaths()` (el camino nativo, línea ~983) y la semántica de skip/overwrite del backend, **pero no ejercita `ConflictActions` end-to-end**: nunca comprueba que la comprobación de conflicto de la UI use el mismo criterio que la op que la sigue. La divergencia cae justo en el hueco entre lo probado (backend) y lo no probado (el `test -e` de `logic/`).

**Propuesta mínima de fix (para después de tu confirmación):** sustituir las 6 comprobaciones `test -e` de `ConflictActions` (+ las de `RenameOps`/`FileOps` para new-file/new-folder/rename) por una única llamada a `FileOperations.existingPaths([destino])`, que ya existe, es nativa y es la que usa la op real. Cambio mecánico, elimina el `bash -c` de esas rutas y unifica la semántica de "existe" con la del backend. Añadir una prueba de selfcheck que meta un symlink roto como destino y afirme que `existingPaths` lo detecta (hoy solo se prueba con symlink válido).

**✅ Resolución (Hardening-1):** aplicado, con un matiz importante descubierto al implementar: **el propio `existingPaths` nativo era también ciego a los symlinks rotos** (usaba `QFileInfo::exists()`, que sigue el symlink, *por diseño* para replicar `test -e` — así que migrar sin más no habría arreglado nada). El fix real:
1. **Backend (`backend/FileOperations.cpp`):** nuevo predicado `entryExists()` con semántica **lstat** (`exists() || isSymLink()`), usado como criterio **único** en `existingPaths()` y en los guards sin-overwrite de `copy()`/`move()`. Ahora un symlink roto en destino cuenta como conflicto en UI **y** backend, con el mismo criterio.
2. **Frontend (`logic/ConflictActions.qml`):** las 6 comprobaciones `test -e` (rename, new-file, new-folder, compress, bulk-rename, extract) migradas a `existingPaths()` síncrono; **eliminados 6 `ProcessRunner`** de comprobación de conflicto. Cero `test -e` de detección de conflicto en el árbol (los `RenameOps`/`FileOps` no tenían ninguno; su detección ya delegaba aquí).
3. **Prueba:** `add("Conflict detection sees a broken symlink (BUG-01)")` — crea un symlink roto y afirma que `existingPaths` lo detecta. **Verificado que FALLA con el predicado antiguo** (revert temporal → `74/75`, "n=0") y pasa con el nuevo.

---

### BUG-02 — Las operaciones respaldadas por scripts `.sh` no tienen cobertura de selfcheck (regresión real ya ocurrida)

- **ID:** BUG-02
- **Gravedad:** 🟠 Alta (es una laguna de arnés, y ya se ha materializado una vez)
- **Frontend afectado:** Ambos (arnés compartido)
- **Estado:** ✅ **RESUELTO en Hardening-1**. Ver "Resolución" al final de la entrada.

**Pasos de reproducción (la regresión que ya pasó):** `git show 2e2da2d` — el commit HEAD arregla `empty-trash.sh`, que dependía de `trash-roots.sh` (eliminado en una fase anterior). Durante todo ese intervalo, **"Vaciar papelera" no vaciaba nada** y el selfcheck seguía reportando 70/70. La operación no tiene ninguna prueba.

**Comportamiento esperado:** el arnés debería fallar cuando una operación de la UI deja de funcionar.

**Comportamiento observado:** el selfcheck cubre exhaustivamente `FileOperations` (nativo) pero **no ejecuta ni un solo `.sh`** de los que la UI sigue invocando: `empty-trash.sh`, `mount-iso.sh`, `list-archive.sh`, `list-mounts.sh`, `open-with-list.sh`, `highlight-preview.sh`, `thumbnail-video.sh`. Un cambio que rompa cualquiera de ellos pasa en verde.

**Causa raíz:** el arnés se diseñó (Fase 12) para blindar la migración del motor de acciones a C++, y cumplió ese objetivo. Pero los scripts `.sh` que quedaron **fuera** de esa migración quedaron también fuera del arnés. La superficie no probada coincide exactamente con la superficie de shell residual.

**Cobertura del selfcheck:** cero para estos scripts. Es la respuesta directa a la pregunta de la sección F: *la regresión que puede volver a pasar sin ser detectada es "un script `.sh` invocado desde la UI deja de funcionar"*.

**Propuesta mínima de fix:** añadir pruebas de selfcheck de humo para cada script invocable, sobre fixtures deterministas: `empty-trash.sh` (crear→enviar a papelera→vaciar→afirmar vacío), `list-archive.sh` (listar un .zip fixture), `mount-iso.sh` (dry-run o afirmar el comando construido), `open-with-list.sh` (afirmar que devuelve ≥1 entrada para un .txt). No requiere framework nuevo: encaja en el mismo patrón `add(nombre, fn)` existente.

**✅ Resolución (Hardening-1):** añadidas 4 smoke-tests al selfcheck (`integrations/standalone/SelfCheck.qml`), con un runner de procesos nuevo (`_sh` sobre `Backend.ProcessRunner`) y fixtures autocontenidos (sin tocar `main.cpp`):
- **`empty-trash.sh`** — **aislado y seguro**: `HOME` apunta a un home falso en el tmp del selfcheck y un `findmnt` falso (por `PATH`) impide escanear montajes reales, así que **jamás toca la papelera real**. Prepara una papelera con un ítem y afirma que el script la vacía (`exit 0` + `files/` vacío). **Verificado que FALLA ante una regresión equivalente a la de `trash-roots.sh`** (rompí el descubrimiento de raíces → `74/75`, "ítems restantes=1").
- **`list-archive.sh`** — lista un `.tar` determinista (construido desde los fixtures) y afirma los elementos de primer nivel en el contrato NUL-delimitado.
- **`mount-iso.sh`** — ruta de fallo (no se puede montar headless): ante una ruta inexistente sale `!= 0` y **sin** un "Mounted…" falso.
- **`open-with-list.sh`** — sobre un `.txt`: `exit 0` y salida con forma TSV válida.

El selfcheck pasa de **70 a 75** pruebas, todas verdes.

---

### BUG-03 — Properties construye `stat`/`du` en una sola línea `bash -c`: ARG_MAX en selección enorme

- **ID:** BUG-03
- **Gravedad:** 🟡 Media
- **Frontend afectado:** Ambos (`logic/PropertiesLoader.qml`)
- **Estado:** DEMOSTRADO POR CÓDIGO

**Pasos de reproducción:** navegar a una carpeta con decenas de miles de ficheros de nombre largo (p.ej. una caché de miniaturas, `node_modules`, o un `~/.cache` grande), `Ctrl+A` para seleccionarlo todo, y abrir **Propiedades** (o el diálogo de **chmod**, que usa el mismo patrón).

**Comportamiento esperado:** Properties calcula tamaño total/permisos de la selección, o degrada con elegancia si es demasiado grande.

**Comportamiento observado (esperado por construcción):** `PropertiesLoader` genera **una sola** cadena `du -shc -- <ruta1> <ruta2> … <rutaN> | tail -n1` (línea 62) y `stat -c%a -- <todas las rutas>` (línea 33), todas las rutas concatenadas en un único `bash -c`. Con selección suficientemente grande se supera `ARG_MAX` (típico 2 MiB de línea de comandos) → `bash` falla con `Argument list too long` → el diálogo se queda con "cargando" o vacío, sin tamaño.

**Causa raíz:** ambas rutas de Properties/chmod construyen el comando por concatenación de todas las rutas citadas en una sola invocación, sin trocear ni usar `xargs`/stdin ni el backend nativo.

**Cobertura del selfcheck:** ninguna. El selfcheck no ejercita `PropertiesLoader` con selección múltiple grande (ni pequeña).

**Propuesta mínima de fix:** pasar las rutas por `stdin` a `xargs -0 du -shc` / `xargs -0 stat` en vez de en `argv`, o (mejor, alineado con Fase 13) exponer un `FileOperations.totalSize([paths])` / `stat` nativo. La corrección mínima sin backend es el `xargs -0`. Marcar con una prueba de selfcheck de selección de N=5000 ficheros fixture.

**✅ Resolución (Hardening-2):** se optó por la vía nativa (Qt/C++), sin `xargs`:
- **Tamaño (multi-selección):** `du -shc -- <todas>` → `FileOperations.totalSize(paths)` (ya existía, nativo). Síncrono, sin proceso ni carrera. *Matiz observable:* pasa de tamaño de bloque (`du`) a bytes aparentes (suma del árbol) — mismo formato y orden de magnitud, y consistente con lo que ya mostraban los ficheros sueltos vía `formatSize`.
- **Permisos (chmod multi):** `stat -c%a -- <todas>` → nuevo `FileOperations.octalModes(paths)` (C++, `::stat`, `%a` = `mode & 07777`), simétrico con `totalSize`/`existingPaths`. Devuelve los modos en el mismo orden ("" si falla) → el mapeo para deshacer se mantiene.
- **Efecto colateral:** `logic/PropertiesLoader.qml` deja de importar `qs.Commons` (ya no usa `Util.shellQuote`); avanza M1 de AUDIT-V2. Las rutas de ítem único siguen usando `stat`/`du` por **argv** (seguras, sin ARG_MAX).
- **Gotcha encontrado:** el wrapper `services/FileOperations.qml` reenvía método a método (regla 8); hubo que exponer `octalModes` ahí además de en el backend, o `logic/` no lo veía.
- **Prueba:** `add("Properties/chmod handle a huge selection without ARG_MAX (BUG-03)")` construye una lista que desborda el límite por-argumento: el nativo la maneja; la MISMA línea `stat -c%a -- <todas>` del código viejo falla (exit 127, E2BIG). Falla con el código anterior (`octalModes` no existía → TypeError).

---

### BUG-04 — La animación de salida de los diálogos (Fase 22) nunca se renderiza

- **ID:** BUG-04
- **Gravedad:** 🟡 Media (cosmético, pero afecta a los 7 diálogos)
- **Frontend afectado:** Ambos (`dialogs/*.qml` compartidos)
- **Estado:** CONFIRMADO — **ya corregido en el working tree en esta sesión, pendiente de commit**.

**Pasos de reproducción:** abrir cualquier diálogo (Propiedades, Renombrado masivo, chmod, Conectar servidor, Abrir con, Ayuda de atajos, Resolver conflicto) y cerrarlo. La animación de entrada (fade+scale) es casi imperceptible; la de **salida** no ocurre en absoluto.

**Comportamiento esperado:** al cerrar, el card se desvanece (opacity 1→0, 120 ms) según la Fase 22.

**Comportamiento observado:** el card desaparece de golpe. El fade-out no se ve nunca.

**Causa raíz:** el card llevaba `visible: root.open` **y** `opacity: root.open ? 1 : 0`. Al cerrar, `visible` pasa a `false` de forma instantánea, así que el ítem deja de renderizarse antes de que la animación de `opacity` de 1→0 tenga oportunidad de dibujarse. El `Behavior` está bien; lo mata el `visible`.

**Cobertura del selfcheck:** ninguna. El selfcheck confirma que los diálogos *instancian* (builders/`OmafilesContent` crea), pero no ejercita su ciclo abrir→cerrar ni su render. Este bug vivió justo en el hueco típico: comportamiento visual de diálogo.

**Fix aplicado (mínimo):** en los 7 cards, `visible: root.open` → `visible: root.open || opacity > 0`, para que el ítem siga renderizando mientras se desvanece. Sin tocar los valores de la animación.

**✅ Resolución (Hardening-2):** consolidado en su propio commit (`fix: preserve dialog fade-out animation on close`). El fix del cierre (`visible: root.open || opacity > 0`) es inseparable del binding de opacidad de la Fase 22 (sin él, `opacity` sería siempre 1 y el diálogo no se ocultaría), así que el commit lleva los 7 diálogos con su bloque de animación entrada+salida **tal cual** — no se reescribe la Fase 22. Los otros cambios de la Fase 22 que NO son el fade-out de diálogos (`core/DialogLayer.qml` = duración de la barra de progreso; `panels/ActiveFileList`, `PreviewPanel`, `Sidebar`) se dejan **fuera** de este commit, sin mezclar. Verificado en Quickshell (reinicio, vivo) y Qt6 (el core instancia los diálogos en el selfcheck). *Nota:* la animación visual no es testeable headless de forma fiable (la propia auditoría lo señala); la verificación es abrir/cerrar un diálogo en ambos frontends.

---

### BUG-05 — Preview de archivos: `tar` sin `--` mientras zip/7z/rar sí lo llevan

- **ID:** BUG-05
- **Gravedad:** 🔵 Baja
- **Frontend afectado:** Ambos (`logic/ArchiveActions.qml:61`)
- **Estado:** DEMOSTRADO POR CÓDIGO

**Pasos de reproducción:** navegar dentro de un `.tar`/`.tar.gz` cuyo miembro (o cuya ruta de archivo) empiece por `-`, y abrir ese miembro para previsualizarlo.

**Comportamiento esperado:** volcado del contenido del miembro, igual que para zip/7z/rar.

**Comportamiento observado (por construcción):** las ramas zip/7z/rar terminan las opciones con `--` (`unzip -p --`, `7z x -y -so --`, `unrar p -inul --`), pero la rama `tar` es `tar xf <ruta> -O <miembro>` **sin `--`**. Aunque `shellQuote` mantiene la ruta como un único argumento, un valor que empiece por `-` se sigue interpretando como opción de `tar`. Inconsistencia real con las otras tres ramas.

**Causa raíz:** omisión del terminador `--` solo en la rama `tar` de la cadena de comandos de extracción.

**Cobertura del selfcheck:** ninguna (el listado de archivos usa `list-archive.sh`, y el volcado de miembro no se prueba).

**Propuesta mínima de fix:** añadir `--` tras las opciones de `tar` de forma consistente con las otras ramas (`tar xf -- <ruta> -O <miembro>` no es válido por la posición de `-O`; la forma correcta es `tar -xf <ruta> -O -- <miembro>` o pasar el miembro tras `--`). Verificar con un fixture de miembro con nombre `-x`.

**✅ Resolución (Hardening-2):** `logic/ArchiveActions.qml` pasa a `tar xf <archivo> -O -- <miembro>` (el `--` va antes del MIEMBRO, no del archivo: el archivo tras `xf` es siempre una ruta absoluta de Omafiles, nunca `-`). zip/7z/rar ya protegían el miembro por venir tras su `--`; solo faltaba en la rama tar. Reproducido en shell (miembro `-foo`): forma antigua `exit 2` ("múltiples archivos requieren -M"), forma nueva vuelca el contenido. **Prueba:** `add("tar extracts a member whose name starts with '-' (BUG-05)")` crea un `.tar` con miembro `-foo` y afirma que la forma nueva funciona y la antigua falla.

---

### OBS-A — El contador de items maneja `-1` correctamente (no es bug)

- **Estado:** CONFIRMADO (resultado negativo, se documenta como resiliencia verificada).

Se investigó qué muestra el contador de items (Fase 23) cuando una carpeta no se puede abrir (`FolderCounter` devuelve `-1`). Resultado: **está bien manejado en dos capas**. `Utils.formatItemCount(-1)` devuelve `""` (guard `n < 0`), y `logic/FileMeta.qml:76` además guarda con `fc >= 0` antes de mostrarlo. Un directorio ilegible simplemente no muestra contador, sin `NaN` ni `"-1 items"`. No hay acción.

---

## Sección F — Mapa de cobertura del arnés (qué NO valida `--selfcheck`)

Esta es la entrega central pedida en la sección F. El selfcheck valida **exhaustivamente el backend nativo** y **apenas** el frontend de interacción y el shell residual. Desglose por la lista del Alcance A:

| Ruta de UI (Alcance A) | ¿Cubierta por selfcheck? | Nota |
|---|---|---|
| `FileOperations` copy/move/remove/trash/restore | ✅ Exhaustiva | ~40 pruebas, incl. conflicto/progreso/cancelación/undo/redo |
| Búsqueda recursiva nativa | ✅ Sí | `SearchWorker` (nombre/profundidad/ocultos) |
| Listado + orden natural | ✅ Sí | `DirectoryModel` |
| Watcher de directorio | ✅ Sí | `QFileSystemWatcher` |
| Contador de items | ✅ Parcial | cuenta OK; caso `-1` no probado (pero robusto, ver OBS-A) |
| Miniaturas (PNG/PDF) + poda de caché | ✅ Sí | `ThumbnailProvider` |
| Preview de **texto** | ✅ Sí | `PreviewProvider.requestText` |
| Builders de menús/comandos/breadcrumb | ✅ Solo que devuelven listas | no valida su *comportamiento* |
| **Selección** simple/múltiple/Shift/Ctrl | ❌ **No** | `SelectionOps` nunca ejercitado |
| **Teclado / atajos / Enter / Delete** | ❌ **No** | inyección de teclado no fiable (AUDIT-V2 R2) |
| **Breadcrumbs** (click de navegación) | ❌ **No** | solo se cuenta `pathSegments().length` |
| **Tabs** (abrir/cerrar/cambiar/reordenar) | ❌ **No** | solo defaults de `TabsState` |
| **Back / forward** (historial) | ❌ **No** | `NavigationController` historial sin probar |
| **Diálogos** (comportamiento, no instanciación) | ❌ **No** | BUG-04 vivió aquí |
| **Detección de conflicto de la UI** (`test -e`) | ❌ **No** | BUG-01 vive aquí; solo se prueba el `existingPaths` nativo |
| **Drag & drop** | ❌ **No** | `DragDropOps` sin ejercitar |
| **Cancelación de búsqueda** | ❌ **No** | la búsqueda corre; el cancel no se afirma |
| **Preview PDF/vídeo/imagen/binario en panel** | ❌ **No** | solo texto; el resto es GPU/render-dependiente |
| **Properties / chmod** (multi-selección) | ❌ **No** | BUG-03 vive aquí |
| **Abrir con / terminal aquí** | ❌ **No** | `OpenWithOps`, `open-with-list.sh` sin probar |
| **Scripts `.sh`** invocados por la UI | ❌ **No** | BUG-02; `empty-trash.sh` ya regresó sin detección |
| **Sidebar refresh / eject** (dispositivos) | ⚠️ Parcial | `UDisksWatcher` carga; el flujo de eject y el refresco visual no |
| **USB / ISO / discos externos / montajes red** | ⚠️ Parcial | `NetworkMounts.list()` devuelve lista; montaje real no (hardware) |

**Conclusión de F:** el arnés es una excelente red para el **backend C++** y una red **inexistente para la interacción de frontend y el shell residual**. Las tres clases de regresión que pueden repetirse sin ser detectadas son, en orden de probabilidad:
1. **Un script `.sh` invocado desde la UI deja de funcionar** (ya pasó: `empty-trash.sh`).
2. **Los command-builders de `logic/` generan una cadena mal citada/con flag equivocado** (nunca se afirma la cadena resultante).
3. **Un cambio en un diálogo rompe su comportamiento** de abrir/cerrar/aplicar (ya pasó: BUG-04).

---

## Dimensiones pendientes de sesión interactiva (NO auditadas empíricamente aquí)

Por la regla "demostrar antes de proponer", **no listo bugs inventados** para estas. Documento el método de reproducción para la siguiente pasada, que requiere un entorno interactivo (no headless):

### D. Rendimiento (100 / 1k / 10k / 50k entradas)
- **Método:** generar `mkdir /tmp/perf && seq 1 50000 | xargs -I{} touch /tmp/perf/file{}` (y variantes de 100/1k/10k), navegar con Omafiles, medir tiempo hasta primer render, fluidez de scroll, y coste de un refresco (`refreshTick`). Comparar con `DirectoryModel` consumido como array (AUDIT-V2 M2: los roles del modelo están muertos, sin scroll incremental → sospechoso a 50k).
- **Hipótesis a validar (no confirmada):** AUDIT-V2 midió el hot path resuelto a 4132 entradas; a 50k el consumo de la UI como array plano podría degradar. **Sin medir ⇒ sin afirmar.**

### E. Resiliencia (hardware / rutas hostiles)
- **Ya cubierto por selfcheck:** permiso denegado (delete read-only), nombres Unicode (round-trip papelera), borrado de missing.
- **Confirmado en esta sesión:** symlink roto engaña a `test -e` (ver BUG-01).
- **Pendiente:** desconexión de USB/disco **durante** una operación de copia larga; montaje/desmontaje repetido de ISO; conflicto simultáneo de dos operaciones (hay busy-guard en `ejectMount` y `runNative*` devuelve false si ocupado — verificar que todas las rutas lo respetan).

### C. Paridad Qt6 ↔ Quickshell (fidelidad visual)
- **Confirmado bien:** `shellQuote`/`fileUrl` son **idénticos** entre el stub standalone y el `Util.qml` real de Omarchy (único diff: `execDetached`, esperado). Sin bug de paridad de lógica ahí.
- **Pendiente (visual):** comparar las dos ventanas lado a lado (layout, iconos, espaciados, colores, animaciones). AUDIT-V2 ya avisó de que la fidelidad de los stubs `qs.Ui`/`qs.Commons` **no está verificada**. Requiere arrancar ambos frontends y comparar capturas.

---

## Criterio de RC1

**Estado de los bloqueantes tras Hardening-1:**

- ✅ **BUG-01** — **RESUELTO**. Detección de conflicto unificada en `existingPaths` nativo con criterio lstat compartido UI/backend; ceguera al symlink roto corregida en el propio backend. Ya no es bloqueante.
- ✅ **BUG-02** — **RESUELTO**. Cobertura de humo añadida para `empty-trash.sh`/`list-archive.sh`/`mount-iso.sh`/`open-with-list.sh`; una regresión equivalente a la de "vaciar papelera" ahora rompe el selfcheck (demostrado). Ya no es bloqueante.

**No hay bloqueantes de RC1 pendientes.** Estado de los recomendados:
- ✅ **BUG-03** (Media): **RESUELTO (Hardening-2)** — Properties/chmod nativos (`totalSize`/`octalModes`), sin ARG_MAX.
- ✅ **BUG-04** (Media): **RESUELTO (Hardening-2)** — fade-out de diálogos consolidado en su commit.
- ✅ **BUG-05** (Baja): **RESUELTO (Hardening-2)** — `tar ... -O -- <miembro>`.

**Con Hardening-1 + Hardening-2, no quedan incidencias abiertas de severidad Alta o Media** (BUG-01…05 resueltos; solo OBS-A, que no es bug). El proyecto puede declarar **RC1 freeze** sin bugs conocidos de severidad alta o media.

Y como trabajo de arnés que convierte el resto en verificable (mismo espíritu que la Fase 12 → Fase 13): extender el selfcheck a **selección, breadcrumbs, tabs, back/forward y comportamiento de diálogos**, que son hoy los huecos de mayor superficie.

---

## Cierre honesto

El backend de Omafiles es, medido, sólido: 70/70, con cobertura real de las operaciones destructivas y sus casos límite. Pero un audit de bugs no puede firmar un RC1 solo con eso. **Los tres bugs con nombre propio de este informe (01, 02, 04) viven exactamente donde el arnés no mira: el shell residual, los scripts, y el comportamiento de los diálogos.** Y el propio commit auditado es la prueba de que esa zona ciega ya causó una regresión real.

La recomendación no es "arreglar más deprisa", es **cerrar la brecha de observabilidad del frontend antes de declarar RC1** — porque hoy, igual que en AUDIT-V2, la capacidad de *verificar* cambios sigue por detrás de la calidad del código verificado.

*Fin del informe. No se ha corregido ningún bug de este documento salvo BUG-04 (ya estaba tocado en el working tree). A la espera de tu confirmación antes de empezar a corregir.*
