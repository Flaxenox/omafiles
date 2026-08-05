import QtQuick

// Detección de tipo de fichero por extensión (icono + is Image/Video/
// Audio/Pdf) -- lógica de negocio pura que vivía en Omafiles.qml pese a
// no depender de ningún Process ni de otro subsistema, solo de las listas
// de extensiones (imageExt/videoExt/audioExt/archiveExt/codeExt, que se
// quedan en root por ser configuración, no lógica). Encontrado en la
// misma auditoría que logic/SortOps.qml.
//
// root conserva envoltorios de una línea (`function iconFor(entry) {
// return fileTypeUtils.iconFor(entry) }`, ver junto a cada una en
// Omafiles.qml) porque estas 6 funciones tienen 38 sitios de llamada
// externos repartidos en ~10 ficheros -- tocarlos todos habría sido mucho
// más riesgo que el beneficio, mismo criterio que ActionEngine. Ningún
// sitio de llamada existente cambió.
Item {
  property Item root: null

  function extOf(name) {
    var idx = name.lastIndexOf(".")
    return idx > 0 ? name.substring(idx + 1).toLowerCase() : ""
  }

  function iconFor(entry) {
    var ext = extOf(entry.name)
    if (ext === "iso") return "󰗮"
    if (root.imageExt.indexOf(ext) >= 0) return "󰺰"
    if (root.videoExt.indexOf(ext) >= 0) return "󰸬"
    if (root.audioExt.indexOf(ext) >= 0) return "󰸪"
    if (root.archiveExt.indexOf(ext) >= 0) return "󰗄"
    if (ext === "pdf") return "󰈦"
    if (root.codeExt.indexOf(ext) >= 0) return "󱀫"
    return "󰈤"
  }

  function isImage(entry) {
    return entry.type === "file" && root.imageExt.indexOf(extOf(entry.name)) >= 0
  }

  function isVideo(entry) {
    return entry.type === "file" && root.videoExt.indexOf(extOf(entry.name)) >= 0
  }

  function isAudio(entry) {
    return entry.type === "file" && root.audioExt.indexOf(extOf(entry.name)) >= 0
  }

  function isPdf(entry) {
    return entry.type === "file" && extOf(entry.name) === "pdf"
  }
}
