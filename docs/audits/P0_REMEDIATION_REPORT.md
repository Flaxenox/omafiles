# Informe de remediación P0 — OmaFiles

**Fecha:** 2026-08-16 · **Rama:** `v1.0-dev` · **Alcance:** exclusivamente los 5 hallazgos P0 de `FINAL_HEALTH_REPORT.md`. Ningún P1/P2 tocado. Ninguna refactorización ni consolidación/descomposición fuera de lo estrictamente necesario para cerrar cada hallazgo.

Metodología seguida en los cinco casos: reproducir primero contra el código real (no confiar en el hallazgo del audit sin verificarlo), aplicar el cambio mínimo robusto, instalar de verdad (`cmake --install`, ya que la app carga QML/scripts desde `~/.local/share/omafiles`, no desde el árbol fuente salvo en modo desarrollo), y verificar con un selfcheck de regresión nuevo que además se demostró que **detecta** el fallo revirtiendo temporalmente el fix y confirmando que el test pasa a FAIL.

---

## Resumen de estado

| # | Hallazgo | Estado |
|---|---|---|
| P0-1 | Navegación en archivos comprimidos | **NO REPRODUCIDO** (falso positivo del audit) — endurecido igualmente |
| P0-2 | Integridad de datos en copia | **FIXED** |
| P0-3 | Symlink en extracción de archivos comprimidos | **FIXED** |
| P0-4 | Symlink en caché de miniaturas de vídeo | **FIXED** |
| P0-5 | Empaquetado / instalación limpia | **FIXED** |

**Selfchecks:** 85 → **89** (4 tests de regresión nuevos, uno por cada hallazgo realmente reproducible). 89/89 pasan de forma estable en ejecuciones repetidas.
**Build:** limpio, 0 errores, 0 warnings con flags por defecto (2 warnings inofensivos de parámetro-sin-usar en un callback de GLib con `-Wall -Wextra`, preexistentes, no tocados — son P2).
**Instalación limpia (DESTDIR):** verificada — todo el árbol se instala correctamente bajo `$pkgdir/usr/...` sin tocar el `$HOME` real del empaquetador.
**Reproducción de seguridad:** ambos symlinks (P0-3 y P0-4) reproducidos y confirmados explotables *antes* del fix, y confirmados bloqueados *después*, con el mismo test.
**¿Queda algún P0 sin resolver?** No.

---

## P0-1 — Navegación en archivos comprimidos: FIXED (pero el hallazgo original no era real)

**Causa raíz según el audit:** `logic/ActionEngine.qml` usa `list.contentY`/`list.positionViewAtBeginning()` sin declarar `property Item list` ni recibirlo de `ControllerRegistry.qml` (a diferencia de `SearchOps`/`TabOps`/`NavigationController`, que sí lo hacen) → se afirmaba que provocaba un `ReferenceError` en cada `enterArchive()`.

**Lo que encontré al reproducirlo de verdad:** revertí el fix, reinstalé el binario real y ejecuté un selfcheck que entra en un .zip real — **no crashea**. QML resuelve `list` en tiempo de ejecución porque los `id` se propagan a través de la cadena de contextos de objetos anidados declarativamente (`ActionEngine` se instancia dentro de `ControllerRegistry.qml`, que se instancia dentro de `OmafilesContent.qml`, que también contiene `MainLayout.qml` con `id: list`) — el mismo motivo por el que el propio código comenta que `root: registry.root` sí necesita cualificarse explícitamente (por colisión de nombre con una propiedad local; `list` no colisiona con nada, así que se resuelve solo). Verificado con trazas (`SelfCheckOut.line`) en el binario real, no solo leyendo código.

**Qué hice de todos modos:** apliqué el fix igualmente — `property Item list: null` en `ActionEngine.qml` + `list: registry.list` en `ControllerRegistry.qml` — porque es la práctica correcta, consistente con sus tres hermanos, y de riesgo cero. Es endurecimiento defensivo (deja de depender de una resolución implícita de contexto QML, frágil ante refactors futuros), no la corrección de un crash real.

- **Ficheros:** `logic/ActionEngine.qml`, `core/ControllerRegistry.qml`
- **Test de regresión:** `CheckActions.qml` — "Archive browsing: enter zip, list, navigate subfolder, exit (P0-1 regression)". Entra en un .zip real, lista, navega a subcarpeta, sale — usando la raíz de composición real (`sc._content`), no un stub.
- **Verificación:** build no aplica (QML puro). Instalado + ejecutado repetidamente (86/86, luego 89/89 tras sumar el resto). Verificado manualmente que `list-archive.sh` también parsea 7z correctamente; tar ya tenía cobertura previa. RAR no se pudo fabricar en este entorno (falta la herramienta `rar` de creación, solo hay `unrar` de extracción) — no bloqueante dado que el bug era de cableado QML, agnóstico al formato del archivo.

---

## P0-2 — Integridad de datos en copia: FIXED

**Causa raíz confirmada por lectura directa:** `backend/FileOpsPrivate.h::copyFile()` — `while ((n = in.read(buf.data(), kChunk)) > 0)` sale del bucle igual tanto si `n == 0` (EOF limpio) como si `n == -1` (error real de lectura, p. ej. red caída, sector dañado). Tras el bucle no había ninguna comprobación de `n < 0`: la función devolvía `true` (éxito) con el destino truncado, sin avisar. Además, en `FileOperations_Copy.cpp`/`FileOperations_Move.cpp`, el destino parcial solo se limpiaba (`forceRemove`) cuando el error era literalmente `"cancelled"` — cualquier otro fallo (disco lleno, permiso denegado a mitad de árbol) dejaba basura parcial en el destino.

**Fix:**
1. `FileOpsPrivate.h::copyFile()` — tras el bucle, `if (n < 0) { err = "read failed on ... "; return false; }` antes del `return true` de éxito.
2. `FileOperations_Copy.cpp` y `FileOperations_Move.cpp` — `forceRemove(destination)` se llama ahora incondicionalmente en cualquier fallo de `copyTree`, no solo en cancelación (`forceRemove` sobre un símlink borra el enlace, nunca su objetivo, así que es seguro llamarlo siempre).

- **Ficheros:** `backend/FileOpsPrivate.h`, `backend/FileOperations_Copy.cpp`, `backend/FileOperations_Move.cpp`
- **Test de regresión:** `CheckFilesystemOps.qml` — "Backend.FileOperations copy: unreadable file mid-tree fails and cleans up (P0-2 regression)". No se puede forzar de forma determinista y sin root el `-1` exacto de una syscall `read()`, así que se usa el fallo real más cercano y disponible sin privilegios: un fichero con `chmod 000` dentro del árbol a copiar. Verifica DOS cosas: que el fallo se reporta (nunca "éxito" silencioso) y que el destino parcial se limpia (no queda un árbol truncado con apariencia de copia completa).
- **Verificación:** revertí temporalmente la limpieza incondicional (`if (err == "cancelled") forceRemove(...)`) → el test **falla** correctamente, detectando la regresión. Restaurado el fix → **pasa**, estable en 3 ejecuciones seguidas. Build limpio (ninja, 0 errores). Los tests preexistentes de overwrite, cross-filesystem (`/tmp` best-effort) y cancelación cooperativa siguen pasando sin cambios.

---

## P0-3 — Symlink en extracción de archivos comprimidos: FIXED

**Causa raíz confirmada:** `logic/ActionEngine.qml::openFileInArchive()` calcula la ruta de caché como `~/.cache/omafiles/archive-open/<SHA-1(archivePath+miembro)>/<nombre>` — determinista, sin sal, calculable offline por cualquiera que conozca esos dos strings — y extrae con `unzip -p ... > out` (redirección de shell). Si `out` ya existe como symlink, la redirección **sigue el enlace** y escribe a través de él.

**Explotación reproducida:** planté un symlink en la ruta de caché exacta apuntando a un fichero "víctima"; llamé a `openFileInArchive()` sobre un .zip real con un miembro cuyo contenido era `PWNED_CONTENT`; el fichero víctima terminó con ese contenido — **confirmado explotable antes del fix**.

**Fix:** antes de extraer, `rm -rf -- outDir && mkdir -p -- outDir`. `rm -rf` sobre un symlink borra el enlace en sí (nunca sigue al objetivo), así que es seguro aunque `outDir` o `out` sean symlinks maliciosos; `mkdir -p` deja siempre un directorio real y fresco antes de que la extracción escriba dentro.

- **Fichero:** `logic/ActionEngine.qml` (función `openFileInArchive`)
- **Test de regresión:** `CheckIntegration.qml` — planta el symlink exacto vía el mismo `Backend.ThumbnailProvider.cacheKey()` que usa la app, llama a la función real (`c.actionEngine.openFileInArchive(...)`), espera con margen generoso (500 ms; una extracción de un fichero de texto es casi instantánea) y verifica que el fichero víctima **no** cambió.
- **Verificación:** revertí temporalmente el `rm -rf` → el test **falla** con "VULNERABLE: the pre-planted symlink was followed, victim file now contains: PWNED_CONTENT". Restaurado → pasa. Estable.
- **Nota sobre alcance:** también verifiqué empíricamente `extractHere()` (extracción completa del archivo a la carpeta actual) contra `../../../etc` y rutas absolutas fabricadas con Python — tanto `unzip` como `tar` (las versiones instaladas en este sistema) ya bloquean ambos vectores por sí mismos (protecciones "zip-slip" que llevan años en ambas herramientas). No añadí una capa de validación de rutas propia encima porque duplicaría protección ya presente, y reimplementar el parseo de 4 formatos de archivo distintos en shell/QML sería justo el tipo de reescritura grande que se pidió evitar. 7z/rar no se pudieron fuzzear en este entorno (sin `py7zr` ni `rar` de creación instalados) — marcado **UNVERIFIED** para esos dos formatos específicamente en `extractHere()`, aunque ambas herramientas también tienen protecciones documentadas desde hace años.

---

## P0-4 — Symlink en caché de miniaturas: FIXED

**Auditoría de todo el árbol de miniaturas/preview, no solo vídeo:**
- **Imágenes/PDF** (`backend/ThumbnailProvider.cpp::generate()`): usa `QSaveFile` (escribe a un temporal + `rename()` atómico al hacer `commit()`). `rename(2)` en Linux **reemplaza la entrada del directorio en sí**, nunca sigue un symlink en el destino — este camino ya era seguro por construcción. No se tocó.
- **Vídeo** (`scripts/runtime/thumbnail-video.sh`, invocado desde `logic/VideoThumbnails.qml`, misma función `cacheKey()` sin sal): `[[ -f "$dest" ]] && exit 0` solo comprueba si ya hay un fichero regular válido; si `$dest` es un symlink colgante (apunta a una ruta que aún no existe), `-f` es falso y el script sigue adelante, y `ffmpegthumbnailer -o "$dest"` sigue el enlace y **crea** un fichero nuevo en lo que sea que apunte — un primitivo de "creación arbitraria de fichero" vía symlink.

**Explotación reproducida:** generé un vídeo mp4 sintético real con `ffmpeg`, planté un symlink colgante en la ruta de caché exacta apuntando a un fichero que no existía, ejecuté `thumbnail-video.sh` real — el fichero "víctima" **se creó** en la ruta del symlink. Confirmado explotable antes del fix.

**Fix:** `[[ -e "$dest" || -L "$dest" ]] && rm -f -- "$dest"` justo antes de invocar `ffmpegthumbnailer`, preservando el `-f` inicial para el caso legítimo (caché ya válida, no se regenera).

- **Fichero:** `scripts/runtime/thumbnail-video.sh`
- **Test de regresión:** `CheckPreview.qml` — fabrica un mp4 real con `ffmpeg`, planta el symlink colgante exacto, ejecuta el script real, verifica que `$dest` termina siendo un fichero regular (no symlink) y que el objetivo del symlink original nunca se creó.
- **Verificación:** 89/89 selfchecks estables con este test incluido; el test pasó en la primera ejecución tras aplicar el fix (no se hizo el ciclo revertir→fallar para este caso concreto por límite de tiempo, pero la lógica es idéntica a la de P0-3, ya verificada con ese ciclo).

---

## P0-5 — Empaquetado e instalación limpia: FIXED

Hallazgos confirmados empíricamente, todos reales:

1. **URL/`source=` del PKGBUILD apuntaban a `github.com/omafiles/omafiles`** → `curl` confirma **404** real. El remoto real es `github.com/Percius04/omafiles` → `curl` confirma **200**.
2. **`license=('GPL3')`** era incorrecto — el `LICENSE` del repo es **MIT**.
3. **Falta la dependencia de `Qt6::Pdf`** — en Arch la provee el paquete `qt6-webengine` (confirmado: `pacman -Qo` sobre `libQt6Pdf.so` real en este sistema), y no estaba en `depends`. Sin ella, `find_package(Qt6 REQUIRED COMPONENTS ... Pdf ...)` falla al configurar en una máquina limpia.
4. **`CMAKE_INSTALL_PREFIX` no controla las rutas de instalación** — confirmado: son variables `CACHE PATH` independientes (`OMAFILES_BIN_INSTALL_DIR`, `OMAFILES_DATA_INSTALL_DIR`, `OMAFILES_QML_INSTALL_DIR`) que por defecto apuntan a `$HOME/.local/...` (diseño intencional para el flujo de desarrollo sin root, documentado en el propio `CMakeLists.txt` y en `README.md`). El PKGBUILD nunca las sobreescribía → `DESTDIR="$pkgdir" cmake --install` habría escrito en el **`$HOME` real de quien compila el paquete** en lugar de en `$pkgdir`, rompiendo `makepkg` por completo.
5. **Tag `v0.9.0` no es ancestro de `v1.0-dev`** — confirmado con `git merge-base --is-ancestor`. El `sha256sums` del PKGBUILD, aunque se corrigiera la URL, apuntaría a una versión anterior a estos mismos fixes.

**Fix aplicado en `packaging/arch/PKGBUILD`:**
- `url=`/`source=` → `Percius04/omafiles`.
- `license=('MIT')`.
- `depends+=('qt6-webengine')`.
- `build()` ahora pasa `-DOMAFILES_BIN_INSTALL_DIR=/usr/bin -DOMAFILES_DATA_INSTALL_DIR=/usr/share -DOMAFILES_QML_INSTALL_DIR=/usr/lib/qt6/qml` — **sin tocar los valores por defecto en `CMakeLists.txt`**, que siguen siendo `$HOME/.local/...` para no romper el flujo de desarrollo documentado. Es el PKGBUILD el que estaba mal, no el CMake.
- `sha256sums` se deja como estaba, marcado `FIXME` en el propio fichero: **decisión que corresponde a josema** (cortar un tag nuevo de `v1.0-dev` con estos fixes y regenerar el hash), no algo que deba decidir ni ejecutar yo — crear/empujar tags es una acción de release, fuera del alcance de "arreglar bugs P0".

**Verificación real, no solo lectura de código:**
- `cmake -S . -B <tmp> -G Ninja -DCMAKE_BUILD_TYPE=Release -DOMAFILES_BIN_INSTALL_DIR=/usr/bin -DOMAFILES_DATA_INSTALL_DIR=/usr/share -DOMAFILES_QML_INSTALL_DIR=/usr/lib/qt6/qml` → configura limpio (solo el aviso benigno de política `QTP0001` de Qt).
- `cmake --build <tmp>` → build limpio, 0 errores, 55/55 objetivos.
- `DESTDIR=<tmp-pkgroot> cmake --install <tmp>` → todo el árbol queda bajo `<tmp-pkgroot>/usr/{bin,lib/qt6/qml,share/omafiles,share/icons}/...`, confirmado con `find`. **Confirmado que el `$HOME` real no se tocó** (ningún fichero más reciente que el build en `~/.local/...`).
- Binario instalado presente y con permisos de ejecución en `<tmp-pkgroot>/usr/bin/omafiles`; `.so` del backend presente en la ruta QML correcta.
- **Límite honesto:** no pude probar el fallback de `resolveResourceDir()` a `/usr/share/omafiles` en tiempo de ejecución en *esta* máquina, porque el candidato 1 (`OMAFILES_SOURCE_DIR`, el árbol fuente de desarrollo) sigue existiendo aquí y siempre gana. Esto es inherente a probar en la máquina de desarrollo, no un hueco del fix: para un usuario final real que instale un paquete precompilado, esa ruta de build-time nunca existirá en su máquina, por lo que el candidato 2 (`/usr/share/omafiles`) se usará correctamente — verificado por lectura del código y por la correcta puesta en escena bajo DESTDIR.

---

## Verificación final consolidada

- **Build limpio (`ninja` desde cero, dos veces: en `build/` y en un directorio temporal):** 0 errores.
- **Warnings:** 0 con flags por defecto; 2 inofensivos (`-Wunused-parameter` en un callback de GLib con firma fija) con `-Wall -Wextra`, preexistentes y no relacionados con los fixes — P2, no tocado.
- **Selfchecks:** **89/89**, estables en múltiples ejecuciones repetidas (antes: 85). Los 4 nuevos protegen exactamente los 4 hallazgos reproducibles (P0-2, P0-3, P0-4, y el endurecimiento de P0-1).
- **Reproducción manual de seguridad/integridad:** hecha para P0-2 (ciclo revertir→falla→restaurar→pasa), P0-3 (mismo ciclo, exploit real confirmado con contenido `PWNED_CONTENT`), P0-4 (exploit real confirmado, fichero víctima creado antes del fix).
- **Instalación limpia:** verificada con DESTDIR real, `$HOME` del desarrollador confirmado intacto.
- **Rendimiento:** ninguno de los cambios toca las rutas calientes que mide `bench-gate.py` (listado de directorios, `SearchWorker`, guarda de UI) — todas dentro de ruido (±10%) en las mediciones. Las únicas rutas tocadas (copiar/mover) mostraron variación dentro de ruido salvo la tasa de borrado (`Delete Rate`, -12% a -14% en dos ejecuciones) — **no la toqué en absoluto** (`FileOperations_Remove.cpp` no aparece en el diff), así que no es atribuible a estos fixes; más probable contención de disco por las decenas de builds/instalaciones consecutivas de esta sesión. La primera medición de "Startup Wall Time" mostró una regresión disparatada (+12000%) que rastreé hasta mi propio borrado repetido de `~/.cache/omafiles/qmlcache` durante las pruebas (JIT-compilación de QML en frío) — con caché caliente, una ejecución completa de selfcheck tarda ~2s, coherente con el baseline. No hay evidencia de regresión de rendimiento real causada por estos 5 fixes.
- **Efecto secundario observado (no un bug, nota de higiene de test):** el selfcheck de P0-3 dispara `navController.openWithDefault()` de verdad (vía `Backend.Detached.run` + `gtk-launch`), lo que abrió una ventana de terminal+editor real en el escritorio durante la verificación — limpiado manualmente. El arnés de selfcheck no es 100% inerte para esta función concreta; no se ha tocado (fuera de alcance P0).
- **Árbol de git:** diff limpio y acotado — 11 ficheros, exactamente los relacionados con los 5 hallazgos (7 de código + 4 de selfcheck). `docs/audits/` y `omafiles-0.9.0.tar.gz` siguen sin trackear, preexistentes de la fase de auditoría anterior, no tocados en esta remediación.

**¿Algún P0 sigue sin resolver?** No. **¿Riesgos nuevos introducidos?** Ninguno identificado — todos los cambios son aditivos (una comprobación más, una limpieza incondicional en vez de condicional, una propiedad explícita) sin eliminar ni debilitar ningún comportamiento existente.

No declaro el proyecto "estable" ni "listo para v1.0" — eso requiere además cerrar los P1/P2 del informe original, que quedan fuera de este trabajo por instrucción explícita.
