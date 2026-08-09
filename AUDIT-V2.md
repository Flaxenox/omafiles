# Omafiles — Auditoría arquitectónica v2

**Fecha:** 2026-08-09 · **Commit auditado:** `a634ea1` · **Auditoría anterior:** `AUDIT.md` (2026-08-09, pre-refactor)

---

## Executive summary

**El proyecto está considerablemente más limpio de lo que la auditoría v1 preveía para este punto.** No es cortesía: es medible. De los 11 hallazgos de v1, **8 están cerrados** y 2 más reducidos a residuo. Las invariantes de `ARCHITECTURE.md` se cumplen **sin una sola violación** (verificado por reglas 1, 2, 3, 6 y 7). Un único fichero de todo el árbol importa `Quickshell`. La capa `services/` ya no envuelve Quickshell: es un passthrough del 100% al backend C++.

Dicho eso, hay una conclusión incómoda que domina esta auditoría:

> **El problema principal de Omafiles ya no es la arquitectura del frontend. Es la brecha entre el backend que está construido y el backend que está usado.**

`FileOperations` tiene 364 líneas de C++ con siete operaciones (`copy`, `move`, `rename`, `remove`, `mkdir`, `trash`, `restore`). **QML solo llama a una: `mkdir`.** Las otras seis son código muerto, mientras el motor de acciones sigue construyendo comandos `bash` a mano — con deshacer implementado como comandos inversos y citado de shell manual (`Util.shellQuote` aparece en 8 ficheros de `logic/`). Esa es, con diferencia, la mayor concentración de riesgo real del proyecto: es donde viven las operaciones destructivas.

El segundo hallazgo honesto: **el god object es más pequeño, pero no ha desaparecido; ha cambiado de rol.** `OmafilesContent` pasó de "hace todo" (1598 líneas) a "localizador de servicios" (571 líneas), pero sigue recibiendo **413 referencias** desde el resto del código. El 47% de ellas son wrappers de bajo nivel que solo reenvían a un controlador. La Fase 11 arregló el *ownership*; no arregló el *tráfico*.

Y una autocrítica: **los refactors de la Fase 11 introdujeron deuda nueva**, pequeña pero real (cadena de delegación de 15 saltos, bindings de compatibilidad que iban a ser temporales y siguen ahí, `CommandFacade` leyendo estado por la ruta larga). Está documentada abajo.

**Veredicto:** arquitectura de frontend, sana y estable. Backend, sólido pero **infrautilizado**. La siguiente fase no debería ser paridad Qt6.

---

## Métricas v1 → v2

| Métrica | v1 (pre-refactor) | v2 (`a634ea1`) | Δ |
|---|---:|---:|---|
| `OmafilesContent.qml` | 1596 | **571** | −64% |
| Fichero QML más grande | 1596 | 571 | −64% |
| Ficheros `core/` | 1 | 6 | — |
| Ficheros >500 líneas | 1 | **1** | — |
| Refs al composition root | ~331 (`root.*` en `logic/`) | **413** (medición corregida, todo el árbol) | ver nota |
| Propiedades en `OmafilesContent` | 41 | ~30 | −27% |
| Funciones en `OmafilesContent` | 45 | 44 (31 delegan) | ≈ |
| C++ backend | ~1700 | 1769 | +4% |
| Singletons `state/` | 15 | **22** | +47% |
| `services/` con llamadas a Quickshell | varias | **0** | ✅ |
| Ficheros que importan `Quickshell` | — | **1** (`HostBridge`) | ✅ |
| Violaciones de reglas `ARCHITECTURE.md` | no medido | **0** | ✅ |
| Scripts `.sh` | ~14 | 14 (611 líneas) | ≈ |
| Tests automatizados | 0 | **0** | ⚠️ |

> **Nota sobre las 413 refs:** no es comparable directamente con las "331" de v1. Aquella contaba `root.*` solo en `logic/`; esta cuenta todas las referencias reales al composition root en todo el árbol (`root.*` + `hostRoot.*`), **excluyendo** los 17 ficheros de `dialogs/`/`shared/` que declaran su propio `id: root` local (292 refs que serían falsos positivos). En `logic/` concretamente, las refs bajaron de 331 a **225**.

**Tamaño total:** 9405 líneas QML · 1769 C++ · 611 shell.

---

## Estado de los hallazgos v1

| # | Hallazgo v1 | Estado v2 |
|---|---|---|
| 1 | 4 × `JSON.stringify` en el hot path | ✅ **Cerrado** (`entriesEqual`) |
| 2 | `this` colgante en `DirectoryModel` | ✅ **Cerrado** (guard `shared_ptr<Life>`) |
| 3 | `tabEntriesCache` sin límite | ✅ **Cerrado** (LRU-8) |
| 4 | `videoThumbReady` con copia O(n) | ✅ **Cerrado** (LRU-256) |
| 5 | Ordenación duplicada JS/C++ | ✅ **Cerrado** (`naturalCompare` en C++) |
| 6 | `BackgroundPanel` sin `ThumbnailProvider` | ✅ **Cerrado** |
| 7 | `OmafilesContent` god object (1596) | 🟡 **Reducido** (571; sigue siendo el mayor y centraliza 413 refs) |
| 8 | Acoplamiento en estrella / ownership | 🟡 **Ownership cerrado** (`ControllerRegistry`); **tráfico no** |
| 9 | Dos esquemas de hash de caché | ❌ **Abierto** (`Utils.simpleHash` JS + SHA-1 C++ conviven) |
| 10 | `DirectoryModel` con roles muertos | ❌ **Abierto** (roles siguen sin usarse; UI consume `entries`) |
| 11 | 20 `bash -c` en el motor de acciones | ❌ **Abierto** (27 ocurrencias de `bash` en 11 ficheros de `logic/`) |

---

## Puntos fuertes actuales

Merecen decirse explícitamente, porque son caros de conseguir y fáciles de perder:

1. **Independencia del host, real y verificable.** Un único fichero (`integrations/quickshell/HostBridge.qml`) importa `Quickshell` en todo el proyecto. El criterio de "núcleo reutilizable" de `ARCHITECTURE.md` no es aspiracional: se cumple.

2. **Disciplina de capas sin excepciones.** `logic/` no importa UI. `dialogs/`/`shared/` no importan `state/` ni `logic/`. `state/` solo importa `QtQuick` (+`services/` donde está documentado). Cero violaciones medidas.

3. **`services/` cumplió su función y se volvió transparente.** Diez ficheros, 221 líneas, **cero** llamadas a Quickshell: todo reenvía a `Omafiles.Backend`. La abstracción aguantó una sustitución completa de implementación sin tocar un solo llamador. Eso es exactamente lo que se le pedía.

4. **Backend C++ bien registrado y homogéneo.** Los 10 tipos usan `QML_ELEMENT`/`QML_SINGLETON` de forma coherente (singletons para servicios, instanciable para `DirectoryModel`/`ProcessRunner`/`ProcessWatcher`), compartidos por ambos frontends desde un único `.so`.

5. **Grafo `core/` acíclico.** Estrella limpia desde `OmafilesContent`; los cinco componentes no se importan entre sí. Las dependencias se inyectan explícitamente.

6. **`state/` maduro.** 22 singletons, 472 líneas, sin lógica. `NavState` es fuente de verdad real del estado caliente.

7. **Rendimiento del hot path resuelto y medido.** ~105 ms → ~0 ms por refresco en `/usr/bin` (4132 entradas).

---

## Deuda técnica restante

### 🔴 Crítica

**Ninguna.** No hay nada que amenace la corrección o estabilidad de forma inminente. (El punto A1 está a un paso de esta categoría, pero el código actual funciona y está probado en uso real.)

### 🟠 Alta

**A1. El motor de acciones destructivas sigue en `bash`, con `FileOperations` construido y sin usar.**
*Evidencia:* 7 `Q_INVOKABLE` en `backend/FileOperations.h`; solo `mkdir` se llama desde QML (`logic/RenameOps.qml:131,153`). 27 ocurrencias de `bash` en 11 ficheros de `logic/`, concentradas en `ConflictActions` (9) y `ActionEngine` (5).
*Por qué importa:* es donde se borra, mueve y sobrescribe. El deshacer son comandos inversos construidos por concatenación de strings, con citado manual (`Util.shellQuote`). Cada ruta con comillas, saltos de línea o caracteres raros es una superficie de fallo; y un `undo` mal construido actúa sobre disco. Además 364 líneas de C++ probado están muertas.
*Coste:* alto. *Riesgo de la migración:* alto (por eso v1 lo puso el último). Pero el riesgo de **no** hacerlo no baja con el tiempo.

**A2. 413 referencias al composition root: el tráfico del god object sigue.**
*Desglose exacto:*

| Categoría | Refs | % | Naturaleza |
|---|---:|---:|---|
| Wrappers de bajo nivel (`runAction`, `joinPath`, `pushUndo`, `refresh`…) | 198 | 47% | Reenvío puro a un controlador |
| Estado mutable aún en `root` (`searching`, `refreshTick`, `pendingDeleteNames`…) | 67 | 16% | Debería ser `state/` |
| Constantes/rutas (`homeDir`, `pluginDir`, `imageExt`, `*File`…) | 64 | 15% | Debería ser `state/` o backend |
| Estado ya en `NavState`, leído por binding de compat | 48 | 11% | Residuo de Fase 11.A |
| Builders de la fachada | 22 | 5% | Delegan a `CommandFacade` |
| Otros | 14 | 3% | — |

*Lectura:* el 47% son wrappers. `logic/` llama `root.runAction(...)` (34×) y `root.joinPath(...)` (35×) — es decir, los controladores dependen del composition root para funciones que **no son suyas**: `joinPath` es una función pura y `runAction` pertenece a `ActionEngine`. Esto es lo que mantiene vivo el patrón `property Item root` en 22 de 24 ficheros de `logic/`.

**A3. Cero tests automatizados en un proyecto de 11.700 líneas con operaciones destructivas.**
*Evidencia:* no existe ningún fichero de test/spec.
*Por qué importa:* toda la validación de las fases 10 y 11 fue manual (capturas + log + `force-call`). Durante esta misma serie de refactors, dos regresiones reales (lista vacía por `root` null, controladores null por doble indirección de alias) **solo se detectaron por inspección visual y trazas ad-hoc**. La inyección de teclado en el overlay resultó no fiable, así que menús, atajos y diálogos **no son validables de forma reproducible hoy**. Esto es un multiplicador de riesgo para A1.

### 🟡 Media

**M1. `logic/` depende del design system solo por dos funciones puras.**
10 ficheros de `logic/` importan `qs.Commons` únicamente para `Util.shellQuote` (8×) y `Util.fileUrl` (1×). Mover esas dos a `Utils.js` (o al backend) desacoplaría por completo la lógica de negocio del toolkit de Omarchy. Cambio mecánico y seguro. *Nota:* que `shellQuote` exista es un síntoma de A1 — al migrar a `FileOperations` desaparece sola.

**M2. `DirectoryModel` sigue siendo un `QAbstractListModel` que nadie usa como modelo.** (v1 #10, sin cambios.) Los roles son código muerto; la UI consume el array `entries`. Se paga el precio conceptual sin ninguna ventaja: sin `dataChanged` por fila, sin actualizaciones incrementales, sin scroll fluido en carpetas de 100k.

**M3. Deuda nueva introducida por la Fase 11.** Honestidad obligada:
- *Cadena de delegación:* 15 funciones en `OmafilesContent` que solo llaman a `commandFacade.X()`. Un salto extra que existe para no tocar los llamadores. Es un puente, y los puentes provisionales se quedan.
- *Bindings de compatibilidad de 11.A:* `root.currentPath`/`entries`/`showHidden`/`searchQuery`/`visibleEntries` siguen existiendo como espejo de `NavState` (48 refs). Se declararon "se retirarán al dividir OmafilesContent" — la división ya ocurrió y siguen ahí.
- *`CommandFacade` lee estado por la ruta larga:* 13 usos de `root.currentPath` cuando `NavState.currentPath` es la fuente de verdad.
- *Trampa de `X: X`:* al pasar de ids a properties inyectadas, `root: root` se autorreferencia (binding loop → null). Costó dos regresiones. Está documentado en los ficheros, pero es un filo afilado para el siguiente refactor.

**M4. 14 scripts de shell (611 líneas) sin dueño claro.** Algunos son plumbing legítimo (`trash-roots.sh`, `install-integrations.sh`); otros son candidatos claros a backend (`list-mounts.sh`, `open-with-list.sh`, `search-recursive.sh`). `trash-info.sh` está referenciado desde 5 ficheros QML.

### 🔵 Baja

**B1. Dos esquemas de hash de caché conviviendo.** (v1 #9, sin cambios.) `Utils.simpleHash` (JS, 32 bits; miniaturas de vídeo y archivos abiertos) y SHA-1 en C++ (`ThumbnailProvider`). Dos formatos de clave, dos directorios, dos políticas de invalidación.

**B2. `services/` es hoy una capa de reenvío vestigial.** 221 líneas que solo hacen `Backend.X.y()`. Cumplió su misión (aislar el cambio de implementación) y ahora es indirección pura. *Recomendación: no tocarla.* El coste es trivial y sigue dando estabilidad de nombres si el backend se reorganiza. Se anota para que no se confunda con arquitectura necesaria.

**B3. `OmafilesContent` sigue siendo el único fichero >500 líneas.** No es alarmante para un composition root, pero es el techo que queda.

### ⚪ Opcional

- **O1.** Poda de la caché de miniaturas por antigüedad/tamaño al arrancar (v1 #6, nunca hecho).
- **O2.** `MimeDb` en backend (previsto en `BACKEND_DESIGN.md` 6.B); hoy el tipo de fichero se decide por listas de extensiones en `OmafilesContent`.
- **O3.** Unificar `sortKeys`/`sortKeyLabels` con `SortState`.

---

## Backend: ¿estable o requiere trabajo estructural?

| Tipo | Líneas | Registro | Uso real | Veredicto |
|---|---:|---|---|---|
| **`JsonStore`** | 157 | `QML_SINGLETON` | Completo (bookmarks, recientes, sesión, historial) | ✅ **Estable.** Nada que hacer. |
| **`ThumbnailProvider`** | 190 | `QML_SINGLETON` | Completo (panel activo + fondo tras 10.A) | ✅ **Estable.** Solo falta poda de caché (O1). |
| **`PreviewProvider`** | 125 | `QML_SINGLETON` | Completo | ✅ **Estable.** |
| **`ProcessRunner`/`Watcher`/`Env`/`Detached`/`Notifier`** | 313 | mixto, correcto | Completo | ✅ **Estables.** |
| **`DirectoryModel`** | 541 | `QML_ELEMENT` | Parcial: se usa `entries`; los roles, no | 🟡 **Decisión pendiente, no urgente.** Funciona y es rápido. Requiere trabajo estructural *solo si* se quieren carpetas de 100k con scroll incremental. Decidir explícitamente: o se usan los roles de verdad, o se degrada a proveedor de datos y se borran. |
| **`FileOperations`** | 364 | `QML_SINGLETON` | **1 de 7 métodos (14%)** | 🔴 **Requiere trabajo estructural.** No es un problema del backend en sí (la API está bien diseñada), sino de que el frontend no la usa. Además le falta lo que el motor actual sí tiene: progreso, cancelación y semántica de conflicto/sobrescritura. |

**Conclusión backend:** 8 de 10 tipos están en estado estable y terminado. `DirectoryModel` es una decisión aplazable. `FileOperations` es el único que exige trabajo real — y el trabajo está mayormente **en el lado QML**, no en el C++.

---

## Frontend: ¿deuda importante restante?

| Componente | Líneas | Responsabilidad | Veredicto |
|---|---:|---|---|
| `ControllerRegistry` | 204 | Ownership único de 23 controladores | ✅ **Sano.** Cero `root.*` propias. Hace una cosa. |
| `AppBindings` | 46 | onCompleted + 2 timers | ✅ **Sano.** |
| `DialogLayer` | 359 | UI modal | ✅ **Sano.** 18 `root.*`, casi todas estado que debería estar en `state/`. |
| `MainLayout` | 400 | UI principal | 🟡 **Casi sano.** 27 `root.*`, de las cuales ~10 leen `NavState` por el binding de compat (M3). |
| `CommandFacade` | 342 | Builders de menús/comandos | 🟡 **El más acoplado.** 54 `root.*`. Es lógica de presentación que depende del estado global; una parte natural (construye menús *sobre* el estado actual), otra evitable (leer `NavState` directamente). |
| `OmafilesContent` | 571 | Composition root + estado + wrappers | 🟠 **Deuda restante concentrada aquí.** 44 funciones (31 delegan), ~30 propiedades, receptor de 413 refs. |

**Conclusión frontend:** la descomposición funcionó y los componentes nuevos son sanos. La deuda no está repartida: está **concentrada en `OmafilesContent`**, y es de naturaleza distinta a la de v1. Ya no es "hace demasiadas cosas"; es "es el directorio telefónico de todo el mundo".

---

## Paridad Qt6 ↔ Quickshell: ¿debe ser la siguiente fase?

**Respuesta corta: no.**

*Lo que está mejor de lo esperado:*
- Un solo fichero importa `Quickshell`. Estructuralmente, la independencia ya está lograda.
- `services/` no tiene ni una llamada a Quickshell; el backend C++ compartido sirve a los dos frontends.
- El standalone (`integrations/standalone/Main.qml`) instancia **el mismo** `OmafilesContent` y arranca sin un solo error QML (verificado headless en esta auditoría).
- Existen stubs para los 10 componentes de `qs.Ui` realmente usados.

*Lo que falta de verdad:*
- El acoplamiento restante no es con Quickshell: es con **`qs.Commons`/`qs.Ui`**, el design system de Omarchy, usado en 32 ficheros. Los stubs del standalone existen pero su **fidelidad visual no está verificada** — nadie ha comparado las dos ventanas lado a lado.
- No hay equivalente a `HostBridge` para standalone (posicionamiento, ciclo de vida de ventana).

*Por qué no debería ser lo siguiente:* la paridad Qt6 tiene **alto coste y bajo valor entregado hoy**. No arregla ningún riesgo (A1), no mejora la experiencia en el sistema real de josema (que usa Quickshell), y su parte difícil —replicar el design system de Omarchy— es trabajo cosmético sin fin. Es una fase de *opcionalidad futura*, no de valor presente. Con el núcleo ya independiente, **puede esperar indefinidamente sin coste creciente**: es de las pocas cosas que no se pudre.

---

## Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | Un `undo` mal construido por concatenación de shell borra o sobrescribe datos reales | Baja | **Muy alto** | Migrar a `FileOperations` (A1); mientras tanto, no ampliar el motor de acciones |
| R2 | Una regresión funcional pasa desapercibida: menús/atajos/diálogos no son validables de forma reproducible | **Alta** | Alto | Arnés de validación (A3) — bloquea con seguridad cualquier refactor futuro grande |
| R3 | Ruta con comillas/saltos de línea rompe una operación de fichero | Media | Alto | Igual que R1 |
| R4 | El siguiente refactor de inyección repite la trampa `X: X` → null | Media | Medio | Ya documentado en los ficheros; añadir a `ARCHITECTURE.md` |
| R5 | Los bindings de compat de `NavState` se fosilizan y aparece un tercer camino para leer el mismo estado | Media | Medio | Retirarlos (fase 12.A) |
| R6 | Omarchy cambia `qs.Ui`/`qs.Commons` y rompe la UI | Baja | Medio | Ya hay stubs; sin acción |

---

## Roadmap v2

Ordenado por: impacto arquitectónico → reducción de riesgo → valor de usuario → facilidad de validación. **Es un roadmap nuevo; el anterior (fases 5-9 de `BACKEND_DESIGN.md`) queda absorbido o superado.**

### Fase 12 — Arnés de validación *(habilitador, hacer primero)*
> **Impacto:** medio · **Riesgo:** muy bajo · **Valor:** alto (indirecto) · **Validable:** trivialmente

Sin esto, todo lo demás se valida a ojo. Contenido: un modo de auto-comprobación en el standalone Qt6 (headless) que ejercite los builders (`itemActions`, `paletteCommands`, `emptyAreaActions`…), instancie cada diálogo y afirme invariantes; más un smoke script que compare listados contra `ls`. **No requiere framework de tests**: el patrón `force-call` usado en la Fase 11.C ya demostró que funciona y encuentra fallos reales.

*Por qué primero:* convierte A1 (alto riesgo) en una fase auditable. Es el multiplicador de todo lo demás.

### Fase 13 — Migrar el motor de acciones a `FileOperations`
> **Impacto:** alto · **Riesgo:** alto (mitigado por Fase 12) · **Valor:** alto · **Validable:** sí, tras 12

La deuda más importante que queda. Por escalones, uno por operación, cada uno con su deshacer:
- **13.A** `mkdir`/`rename` (ya hay precedente con `mkdir`)
- **13.B** `trash`/`restore`
- **13.C** `copy`/`move` con progreso real y cancelación (aquí `FileOperations` necesita ampliarse: progreso, cancelación, política de conflicto)
- **13.D** retirar `Util.shellQuote` y los `bash -c` que queden

*Efecto colateral:* cierra M1 (dependencia de `logic/` con el design system) sin trabajo extra.

### Fase 14 — Disolver el tráfico del composition root
> **Impacto:** alto · **Riesgo:** medio · **Valor:** bajo (interno) · **Validable:** sí, tras 12

Ataca las 413 refs por categorías, de menor a mayor riesgo:
- **14.A** Retirar los bindings de compat de `NavState`; que `core/` y `panels/` lean `NavState` directo (−48 refs, mecánico)
- **14.B** Constantes y rutas → `PathsState`/`FileTypeState` (−64 refs, mecánico)
- **14.C** Estado mutable restante → singletons `state/` (−67 refs)
- **14.D** Wrappers: que `logic/` llame a los controladores directamente por inyección en vez de `root.X()` (−198 refs). **Es el grande**; hacerlo controlador a controlador. `joinPath` → `Utils.js` de entrada.

*Resultado esperado:* `OmafilesContent` en el rango 250-350 real, y `property Item root` eliminable de la mayoría de `logic/`.

### Fase 15 — Decisión sobre `DirectoryModel`
> **Impacto:** medio · **Riesgo:** alto · **Valor:** medio (solo carpetas enormes) · **Validable:** sí

Decidir explícitamente: usar los roles y adoptar el modelo de verdad en la UI (habilita actualizaciones incrementales y carpetas de 100k), o degradarlo a proveedor de datos y borrar los roles muertos. **No empezar sin haber medido** que las carpetas grandes son un problema real de uso.

### Fase 16 — Limpieza de shell restante
> **Impacto:** bajo · **Riesgo:** bajo · **Valor:** bajo · **Validable:** sí

`list-mounts.sh`, `list-network-mounts.sh`, `open-with-list.sh`, `search-recursive.sh` → backend (`MimeDb`, `SearchWorker`, `MountsProvider`). Unificar el hashing de caché (B1). Poda de miniaturas (O1).

### Fase 17 — Paridad Qt6 *(opcional, sin caducidad)*
> **Impacto:** bajo hoy · **Riesgo:** bajo · **Valor:** solo si se quiere distribuir fuera de Omarchy

Comparación visual lado a lado, fidelidad de stubs, equivalente a `HostBridge`. Hacer **solo** si aparece la intención real de distribuir Omafiles como app independiente.

---

## Recomendación: siguiente fase concreta

### **Fase 12 — Arnés de validación en el standalone Qt6**

**Qué:** un modo `--selfcheck` en `omafiles-standalone` que, en headless, abra el core sobre un directorio temporal controlado y afirme:
1. Los 7 builders devuelven listas coherentes (ya probado en 11.C).
2. Cada diálogo instancia sin `TypeError` y con sus propiedades resueltas.
3. El listado de un directorio de prueba coincide exactamente con la realidad del disco (nombres, tipos, orden).
4. Cero `TypeError`/`Binding loop` en el log tras el arranque.

**Por qué esta y no otra:**
- Es la única fase que **reduce el riesgo de todas las demás**. Las fases 13 y 14 son las valiosas, pero hoy no son auditables con confianza: durante la Fase 11 dos regresiones reales solo se vieron por captura de pantalla, y la inyección de teclado en el overlay demostró no ser fiable.
- Es **barata y de riesgo casi nulo**: no toca código de producción.
- Convierte la migración de operaciones destructivas (Fase 13) de "arriesgado" a "verificable" — y esa migración es la deuda más importante que queda.
- Aprovecha algo que ya existe y funciona: el standalone Qt6 arranca limpio y comparte el mismo núcleo. Le da además, por fin, **un propósito presente** al frontend Qt6, que hoy es solo una prueba de independencia.

**Lo que explícitamente no recomiendo hacer ahora:** paridad Qt6 (coste alto, valor presente nulo, no se pudre) y `DirectoryModel` (alto riesgo sin evidencia de que las carpetas enormes sean un problema real de uso).

---

## Cierre honesto

La Fase 11 hizo lo que prometía y el proyecto está objetivamente sano: las invariantes se cumplen, el núcleo es independiente del host, el backend es sólido y el rendimiento del camino caliente está resuelto.

Pero conviene nombrar el patrón: **las últimas tres fases han sido de arquitectura, y la deuda con mayor riesgo real —el motor de acciones en shell— lleva dos auditorías intacta**, porque siempre ha sido la más difícil y la peor de validar. Ese es el orden que propone este roadmap: primero la herramienta que hace segura esa migración, después la migración.

La arquitectura ya no es el cuello de botella. La capacidad de verificar cambios, sí.
