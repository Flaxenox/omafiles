import QtQuick
import "../state"
import "../Utils.js" as Utils

// Orden de la lista (nombre/tamaño/fecha/tipo, asc/desc) -- lógica de
// negocio pura que vivía suelta en Omafiles.qml pese a no tocar ningún
// Process ni necesitar ver otros subsistemas, solo SortState.sortKey/sortDesc/
// entries. Encontrado al auditar Omafiles.qml contra la regla 3
// ("toda lógica de negocio fuera de la UI") del prompt de arquitectura.
Item {
  property Item root: null
  property Item fileTypeUtils: null


  // true cuando el orden pedido es el que ya devuelve C++ (DirectoryModel):
  // nombre ascendente. En ese caso DirLister NO re-ordena (ver _sorted).
  // Fase 10.A.
  readonly property bool isDefaultOrder: SortState.sortKey === "name" && !SortState.sortDesc

  function compareEntries(a, b) {
    var result = 0
    if (SortState.sortKey === "size") {
      result = a.size - b.size
    } else if (SortState.sortKey === "mtime") {
      result = a.mtime - b.mtime
    } else if (SortState.sortKey === "type") {
      var ea = fileTypeUtils.extOf(a.name), eb = fileTypeUtils.extOf(b.name)
      result = ea < eb ? -1 : (ea > eb ? 1 : 0)
    }
    if (result === 0) {
      result = Utils.naturalCompare(a.name.toLowerCase(), b.name.toLowerCase())
    }
    return SortState.sortDesc ? -result : result
  }

  // Las carpetas siempre van antes que los ficheros -- el criterio de orden
  // elegido solo decide cómo se ordena cada grupo entre sí.
  function sortEntries(list) {
    var dirs = list.filter(function (e) { return e.type === "dir" })
    var files = list.filter(function (e) { return e.type !== "dir" })
    dirs.sort(compareEntries)
    files.sort(compareEntries)
    return dirs.concat(files)
  }

  function sortLabel() {
    return SortState.sortKeyLabels[SortState.sortKey] + (SortState.sortDesc ? " ↓" : " ↑")
  }

  function setSort(key) {
    SortState.sortKey = key
    NavState.entries = sortEntries(NavState.entries)
  }

  function cycleSort() {
    var idx = SortState.sortKeys.indexOf(SortState.sortKey)
    setSort(SortState.sortKeys[(idx + 1) % SortState.sortKeys.length])
  }

  function reverseSort() {
    SortState.sortDesc = !SortState.sortDesc
    NavState.entries = sortEntries(NavState.entries)
  }
}
