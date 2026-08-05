import QtQuick
import "../Utils.js" as Utils

// Orden de la lista (nombre/tamaño/fecha/tipo, asc/desc) -- lógica de
// negocio pura que vivía suelta en Omafiles.qml pese a no tocar ningún
// Process ni necesitar ver otros subsistemas, solo root.sortKey/sortDesc/
// entries. Encontrado al auditar Omafiles.qml contra la regla 3
// ("toda lógica de negocio fuera de la UI") del prompt de arquitectura.
Item {
  property Item root: null

  function compareEntries(a, b) {
    var result = 0
    if (root.sortKey === "size") {
      result = a.size - b.size
    } else if (root.sortKey === "mtime") {
      result = a.mtime - b.mtime
    } else if (root.sortKey === "type") {
      var ea = root.extOf(a.name), eb = root.extOf(b.name)
      result = ea < eb ? -1 : (ea > eb ? 1 : 0)
    }
    if (result === 0) {
      result = Utils.naturalCompare(a.name.toLowerCase(), b.name.toLowerCase())
    }
    return root.sortDesc ? -result : result
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
    return root.sortKeyLabels[root.sortKey] + (root.sortDesc ? " ↓" : " ↑")
  }

  function setSort(key) {
    root.sortKey = key
    root.entries = sortEntries(root.entries)
  }

  function cycleSort() {
    var idx = root.sortKeys.indexOf(root.sortKey)
    setSort(root.sortKeys[(idx + 1) % root.sortKeys.length])
  }

  function reverseSort() {
    root.sortDesc = !root.sortDesc
    root.entries = sortEntries(root.entries)
  }
}
