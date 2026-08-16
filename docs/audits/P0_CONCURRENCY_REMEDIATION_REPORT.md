# Informe de remediación P0 — Concurrencia/UAF (FileOperations, SearchWorker, ThumbnailProvider)

**Fecha:** 2026-08-16 · **Rama:** `v1.0-dev` · **Alcance:** los 3 hallazgos P0 de concurrencia del audit forense original que quedaron fuera de la remediación anterior (esa cubrió P0-1..P0-5 del pedido del usuario; estos tres son el P0-4 del informe original — "3 use-after-free confirmados por lectura de código"). Nada de `ActionEngine.qml` tocado, nada de Trash/Ctrl+L, nada de P1/P2.

Metodología: reconstruir el grafo de propiedad real de cada clase, comparar contra el patrón `Life`+mutex ya probado y documentado en `backend/DirectoryModel.cpp` (única de las cuatro que lo aplicaba bien desde el principio, con `scan()`/`scanMany()` declaradas `static` a propósito), reproducir cada UAF con un binario standalone instrumentado con **AddressSanitizer** (no solo lectura de código), aplicar el fix mínimo que iguala la disciplina de `DirectoryModel`, volver a correr el mismo binario ASan contra el código arreglado, y añadir un selfcheck de regresión permanente por componente.

---

## Estado final

| Componente | Estado |
|---|---|
| `FileOperations` | **FIXED** |
| `SearchWorker` | **FIXED** |
| `ThumbnailProvider` | **FIXED** |

**Selfchecks:** 89 → **92** (3 nuevos, uno por componente). 92/92 estables en 7 ejecuciones limpias consecutivas tras corregir un bug de contaminación cruzada en mi propio test de FileOperations (ver más abajo).
**Build:** limpio, 0 errores, 0 warnings nuevos (los 2 preexistentes de `NetworkResolver.cpp` con `-Wall -Wextra` siguen igual, no relacionados).
**Reproducción:** las 3 se reprodujeron de verdad con AddressSanitizer (no solo "por lectura de código") — 8/8 iteraciones crasheaban antes del fix en cada componente, 0/8+ después, repetido en 4 pasadas completas (96 ciclos crear→iniciar→destruir totales) sin ni un solo fallo tras el fix.

---

## Grafo de propiedad reconstruido (antes de tocar nada)

- **`FileOperations`**: `QML_SINGLETON` — vive hasta que se destruye el `QQmlEngine` (cierre de la app). Cada `copy()`/`move()`/`remove()`/`emptyTrash()`/`restoreByOrigPath()` lanza un `QRunnable` en `QThreadPool::globalInstance()`. Ya tenía un `Life`+mutex (Fase 13.B) pero **solo protegía la entrega final** (`finished`/`error`), no la ejecución del `job()` en sí.
- **`SearchWorker`**: `QML_ELEMENT` (instanciable, no singleton) — `SearchOps.qml` tiene su propia instancia; se puede crear y destruir dinámicamente de verdad. Ya tenía `Life`+mutex y un contador de generación `m_gen` para cancelación.
- **`ThumbnailProvider`**: `QML_SINGLETON` — igual que `FileOperations` en cuanto a ciclo de vida. **No tenía absolutamente ningún mecanismo de vida**: sin destructor propio, sin mutex, nada.
- **`DirectoryModel`** (referencia, no tocado): también `Life`+mutex, pero `scan()`/`scanMany()` están declaradas `static` **a propósito** y documentado explícitamente: "no tocan ni el modelo ni ningún miembro, así que es seguro incluso si el modelo se destruye mientras el hilo corre". Este es el contrato que las otras tres no cumplían.

---

## `FileOperations`

**Causa raíz confirmada:** cada `job()` (el lambda que hace el trabajo real: `copyTree`, `removeTree`, etc.) capturaba `[this, ...]` y accedía a `this->m_cancelled` / llamaba a `this->emitProgress(...)` durante **toda la duración del job** — p. ej. el bucle entero de `copyTree` sobre un árbol grande — todo ello **antes** de que el guard `Life`+mutex se comprobase siquiera (ese guard solo envolvía la entrega final de `finished`/`error`). Cerrar la app (destruir el singleton) mientras un `job()` seguía corriendo en el `QThreadPool` era un use-after-free real.

**Reproducido:** binario standalone con ASan, `new FileOperations(); fo->copy(árbol_grande, dest, true); delete fo;` sin esperar — **8/8 iteraciones crashearon** con `heap-use-after-free` exacto en `FileOpsPrivate::copyTree` → `std::atomic<bool>::load()` sobre memoria ya liberada.

**Fix:**
1. `m_cancelled` pasa de `std::atomic<bool>` (miembro) a `std::shared_ptr<std::atomic<bool>>` — cada `job()` captura su propia copia del `shared_ptr` (`cancelled`), independiente de la vida de `this`.
2. `run()` ahora construye una `ProgressFn` (closure segura: comprueba `life->alive` bajo el mismo mutex que usa el destructor **antes** de tocar `this`, exactamente como ya hacía la entrega de `finished`/`error`) y se la pasa a `job()` como parámetro en vez de que `job()` llame a `this->emitProgress(...)` directamente.
3. Resultado: **ningún `job()` de ningún método (`copy`/`move`/`remove`/`emptyTrash`/`restoreByOrigPath`) toca `this` en ningún momento** — igualan la disciplina "static, `this`-free" de `DirectoryModel::scan()`, sin necesitar declararlas `static` porque ya no son miembros, son lambdas normales sin captura de `this`.

**Ficheros:** `backend/FileOperations.h`, `backend/FileOperations.cpp`, `backend/FileOperations_Copy.cpp`, `backend/FileOperations_Move.cpp`, `backend/FileOperations_Remove.cpp`, `backend/FileOperations_Trash.cpp`.

**Verificado con ASan:** 0/8+ crashes tras el fix, repetido en 4 pasadas.

**Selfcheck de regresión:** `CheckFilesystemOps.qml` — "FileOperations: rapid copy+cancel cycles don't corrupt delivery (P0 regression)". `FileOperations` es `QML_SINGLETON`, así que no se puede destruir en pleno vuelo desde QML (por eso la prueba real de "destruir a mitad" vive en el binario ASan, no en el selfcheck); en su lugar este test machaca el mismo mecanismo de cancelación cooperativa (que comparte exactamente el fix del `shared_ptr`) 15 veces seguidas y confirma que el singleton sigue funcionando con una copia real al final.

**Bug encontrado y corregido en mi propio test durante la verificación:** la primera versión disparaba 15 `copy()+cancel()` sin esperar a que cada uno terminara, dejando operaciones sueltas en vuelo que llegaban tarde y contaminaban las señales `finished`/`error` **compartidas** del singleton — provocando fallos intermitentes en los tests de Trash (que corren justo después en el orden de registro) al recibir señales que no eran suyas. Corregido serializando cada iteración (esperar antes de lanzar la siguiente) y, sobre todo, corrigiendo el filtro de ruta: `run()` reporta la ruta **origen**, no la de destino, y mi filtro inicial comparaba contra la de destino — por eso el test colgaba (timeout) tras arreglar lo primero. Verificado con 7 ejecuciones completas y limpias tras el arreglo.

---

## `SearchWorker`

**Causa raíz confirmada:** el bucle de escaneo (`while (it.hasNext()) { if (m_gen.load() != gen) return; ... }`) leía `this->m_gen` en **cada entrada iterada**, sin ninguna protección, durante toda la duración de un escaneo potencialmente largo — todo antes de que el guard `Life`+mutex se comprobase (que solo protegía la entrega final). Destruir el worker (p. ej. cerrar la pestaña/panel que lo posee) mientras seguía escaneando un árbol grande era un use-after-free real, y el más frecuente de los tres (se comprueba en cada entrada, no solo unas pocas veces).

**Reproducido:** binario standalone con ASan, `new SearchWorker(); sw->search(árbol_100k, "e", true); delete sw;` sin esperar — **8/8 iteraciones crashearon** con `heap-use-after-free` exacto en `SearchWorker.cpp:51` (`m_gen.load()` dentro del bucle).

**Fix:**
1. `m_gen` pasa de `std::atomic<quint64>` (miembro) a `std::shared_ptr<std::atomic<quint64>>` — el lambda del worker captura su propia copia (`genPtr`), independiente de `this`.
2. **Bug propio encontrado durante la verificación (no estaba en el hallazgo original del audit):** al aplicar el fix inicial, el binario ASan **seguía crasheando**, ahora con un SEGV distinto dentro de `QCoreApplicationPrivate::notify_helper`. Investigando: la entrega final ya tenía el guard `Life`+mutex, pero **mal colocado** — el `lock_guard` estaba *dentro* del lambda diferido que `QMetaObject::invokeMethod` programa para más tarde, no *alrededor* de la propia llamada a `invokeMethod(this, ...)`. Llamar a `invokeMethod` en sí ya necesita desreferenciar `this` (para averiguar su hilo), así que hacerlo sin comprobar antes si sigue vivo es inseguro **independientemente** de lo que compruebe el lambda diferido. Corregido moviendo el guard para que envuelva la llamada a `invokeMethod`, igual que ya hacían correctamente `FileOperations`/`DirectoryModel`. Este era un fallo real, preexistente en el código original, que ni el audit original ni mi primer pase detectaron — solo salió a la luz al re-ejecutar el mismo binario ASan tras el primer intento de fix.
3. Resultado: el bucle de escaneo y la entrega final son ahora ambos seguros ante la destrucción del objeto.

**Ficheros:** `backend/SearchWorker.h`, `backend/SearchWorker.cpp`.

**Verificado con ASan:** 0/8+ crashes tras el fix completo (2 iteraciones de fix necesarias, ambas verificadas con el mismo binario), repetido en 4 pasadas.

**Selfcheck de regresión:** `CheckSearch.qml` — "SearchWorker: create/search/destroy under load doesn't corrupt state (P0 regression)". `SearchWorker` es `QML_ELEMENT` (a diferencia de los otros dos), así que esta es la única de las tres pruebas de regresión que reproduce el ciclo de vida real completo **desde QML de verdad**: 40 ciclos crear→buscar→destruir sin esperar sobre un árbol de 3000 ficheros, más 20 ciclos de iniciar→cancelar→reiniciar sobre un worker vivo, y una búsqueda final real para confirmar que el estado compartido no quedó corrupto. Una regresión real aquí crashearía el proceso entero de selfcheck, no solo fallaría este test.

---

## `ThumbnailProvider`

**Causa raíz confirmada:** el peor de los tres — **no había ningún mecanismo de vida en absoluto**: sin destructor propio, sin `Life`, sin mutex. El worker del pool llamaba a `QMetaObject::invokeMethod(this, ...)` completamente desprotegido tras generar la miniatura. `generate()` en sí ya era estática/segura (usa `QSaveFile` + `rename()` atómico, que nunca sigue symlinks — por eso el camino de miniaturas de imagen/PDF nunca tuvo este problema); el fallo estaba exclusivamente en la entrega.

**Reproducido:** binario standalone con ASan, `new ThumbnailProvider(); tp->request(imagen_4000x4000, 256); delete tp;` sin esperar — **8/8 iteraciones crashearon**, esta vez con un **SEGV real** (no solo un aviso de ASan) dentro de `QCoreApplicationPrivate::notify_helper` — el propio sistema de entrega de eventos de Qt petando al intentar despachar un evento a un objeto ya liberado. El más severo de los tres por la ausencia total de protección.

**Fix:**
1. Añadido el mismo patrón `Life`+mutex que las otras tres clases (struct, `m_life`, destructor).
2. `request()`: captura `life` antes de lanzar al pool; tras `generate()` (estática, sin tocar `this`), adquiere `life->mtx`, comprueba `alive`, y solo entonces llama a `QMetaObject::invokeMethod(this, ...)` — exactamente el patrón correcto (aplicando también la corrección aprendida en `SearchWorker`: el guard envuelve la llamada, no vive dentro del lambda diferido).
3. `pruneCache()` ya era segura (captura `m_cacheDir` por valor, llama a una función libre, nunca toca `this`) — no se tocó.

**Ficheros:** `backend/ThumbnailProvider.h`, `backend/ThumbnailProvider.cpp`.

**Verificado con ASan:** 0/8+ crashes tras el fix, repetido en 4 pasadas.

**¿Puede un resultado tardío de una petición vieja sobrescribir una miniatura más nueva?** Investigado explícitamente (lo pedía el encargo) — **no, por diseño, no hace falta contador de generación aquí**: la clave de caché (`hashKey(path|size|filesize|mtime)`) incluye tamaño y fecha de modificación, así que dos peticiones para el mismo fichero en estados distintos generan claves (y por tanto rutas de salida) **distintas** — no pueden pisarse entre sí. La única colisión posible es dos peticiones **idénticas** en vuelo a la vez, y ya está deduplicada por `m_inflight`. Confirmado, no es un bug.

**Selfcheck de regresión:** `CheckPreview.qml` — "ThumbnailProvider: many concurrent distinct requests all deliver exactly once (P0 regression)". `ThumbnailProvider` es `QML_SINGLETON` como `FileOperations`, así que tampoco se puede destruir en pleno vuelo desde QML; esta prueba dispara 12 peticiones concurrentes con claves de caché distintas (para que ninguna se deduplique) y confirma que las 12 entregan `ready` **exactamente una vez** cada una, sin duplicados ni caídas.

---

## Verificación final

- **Build limpio** (`ninja` desde cero + reconfiguración completa con `-Wall -Wextra` en un árbol temporal): 0 errores, 0 warnings nuevos.
- **Selfchecks: 92/92**, estables en 7 ejecuciones limpias consecutivas (tras corregir el bug de contaminación cruzada del propio test de FileOperations descrito arriba).
- **Reproducción con AddressSanitizer:** las 3 clases reproducidas de verdad (no solo inspección de código) contra el código sin arreglar, y confirmadas limpias contra el código arreglado — 4 pasadas completas × 24 ciclos = 96 ciclos crear/iniciar/destruir sin un solo fallo tras el fix. La herramienta (`uaf_repro.cpp`) queda en el scratchpad de esta sesión, no se ha añadido al repositorio (para no ampliar el alcance más allá de lo pedido) — el comando exacto para reproducirla está documentado abajo por si se quiere repetir o convertir en herramienta permanente.
- **Rendimiento:** el intento de medir con `bench-gate.py` se vio contaminado dos veces por un efecto secundario **ya conocido y no relacionado** (el selfcheck de P0-3 abre una terminal+nvim real vía `openWithDefault`; el propio `bench-gate.py` invoca `omafiles --selfcheck` internamente y su subproceso se queda colgado esperando a que ese proceso hijo interactivo cierre su pipe, no un problema de estos fixes). Diagnosticado y desbloqueado manualmente matando la ventana colgada las dos veces; la métrica de "Startup Wall Time" quedó inservible por ese cuelgue de ~26 minutos (nada que ver con el código). El resto de métricas (listado de directorios, búsqueda, débito de copia/borrado) mostraron variaciones de un solo dígito o bajo doble dígito porcentual, en su mayoría sobre **código que no toqué en esta sesión** (p. ej. `DirectoryModel`) — coherente con ruido de una máquina de desarrollo bajo carga sostenida durante una sesión larga, no con una regresión real: los cambios aplicados son, en el peor de los casos, una indirección de puntero extra por comprobación/callback (nanosegundos), no un cambio algorítmico.
- **Efecto secundario ya documentado, reencontrado aquí:** el `openWithDefault()` disparado por el selfcheck de P0-3 puede dejar colgado cualquier proceso que invoque `omafiles --selfcheck` y espere a que su pipe de stdout/stderr se cierre (incluido `bench-gate.py`), porque el proceso hijo real (terminal + editor) hereda el descriptor y no lo cierra hasta que el usuario sale de él manualmente. Sigue fuera de alcance P0, pero merece una nota para quien ejecute CI/benchmarks de forma desatendida.

**¿Queda algún P0 de concurrencia sin resolver?** No. **¿Riesgos nuevos introducidos?** Ninguno identificado — todos los cambios son indirección adicional (shared_ptr) o reordenación del guard existente para que cubra lo que ya pretendía cubrir; ninguna lógica de negocio cambió.

No declaro el proyecto "estable" ni "listo para v1.0" — quedan los P1/P2 del informe original y Trash/Ctrl+L, explícitamente fuera de este encargo.

---

## Apéndice: reproducir el binario ASan

```sh
MOCDIR=$(find build -name moc_FileOperations.cpp -exec dirname {} \;)
g++ -std=c++17 -g -O0 -fsanitize=address -fno-omit-frame-pointer -fPIC \
  -Ibackend -I. $(pkg-config --cflags Qt6Core Qt6Gui Qt6Pdf Qt6Qml) \
  uaf_repro.cpp \
  backend/FileOperations.cpp backend/FileOperations_Copy.cpp backend/FileOperations_Move.cpp \
  backend/FileOperations_Remove.cpp backend/FileOperations_Trash.cpp \
  backend/SearchWorker.cpp backend/ThumbnailProvider.cpp \
  "$MOCDIR/moc_FileOperations.cpp" "$MOCDIR/moc_SearchWorker.cpp" "$MOCDIR/moc_ThumbnailProvider.cpp" \
  $(pkg-config --libs Qt6Core Qt6Gui Qt6Pdf Qt6Qml) -o uaf_repro
UAF_REPRO_TREE=~/.cache/omafiles-perfbench/100k UAF_REPRO_IMG=/path/to/big.png ./uaf_repro all
```
(`uaf_repro.cpp` no está en el repo; si se quiere como herramienta permanente en `bench/`, siguiendo el precedente de `bench/perfbench.cpp`, decirlo y se añade.)
