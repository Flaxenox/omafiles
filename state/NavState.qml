pragma Singleton
import QtQuick
import "../services"

// Estado de navegación caliente (Fase 11.A, josema): la ruta actual, su
// listado y el filtro de búsqueda visible. Era el acoplamiento principal
// entre logic/ y root -- currentPath (59 lecturas), visibleEntries (24) y
// entries (13) eran las properties más leídas de todo el plugin desde la
// capa de lógica, siempre vía `property Item root`. Moverlas a un singleton
// deja que logic/ lea/escriba NavState.* directamente y que root conserve
// solo bindings finos de compatibilidad para el árbol visual (aún sin
// dividir). Ver ARCHITECTURE.md (capa state/) y la auditoría 2026-08-09.
//
// El valor inicial de currentPath es solo un placeholder: open() lo
// reescribe siempre antes de que el usuario vea nada (payload real o
// restauración de sesión vía Persistence), igual que TabsState.
QtObject {
  property string currentPath: Env.get("HOME")

  // Listado de la carpeta actual, ya ordenado (DirectoryModel en C++ lo
  // devuelve por naturalCompare; logic/ solo re-ordena si el usuario pidió
  // otro criterio -- ver SortOps.isDefaultOrder). Fuente de verdad; root.
  // entries es un binding a esto.
  property var entries: []

  property bool showHidden: false

  // Texto del buscador rápido del panel activo (filtro por subcadena sobre
  // la carpeta actual, no búsqueda recursiva). Vacío = sin filtro.
  property string searchQuery: ""

  // Subconjunto visible de `entries` tras aplicar el filtro rápido. Derivada
  // (readonly): antes se calculaba en root.visibleEntries y la leían 24
  // sitios de logic/. Misma expresión, ahora junto a su fuente de datos.
  readonly property var visibleEntries: searchQuery
    ? entries.filter(function (e) { return e.name.toLowerCase().indexOf(searchQuery.toLowerCase()) >= 0 })
    : entries
}
