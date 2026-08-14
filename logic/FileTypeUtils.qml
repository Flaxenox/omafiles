import QtQuick
import "../state"

// File type detection by extension (icon + is Image/Video/
// Audio/Pdf) -- pure business logic that lived in core despite
// not depending on any Process nor another subsystem, only on the extension
// lists (imageExt/videoExt/audioExt/archiveExt/codeExt, which stay
// in root as they are configuration, not logic). Found in the
// same audit as logic/SortOps.qml.
//
Item {
  property Item root: null

  function extOf(name) {
    var idx = name.lastIndexOf(".")
    return idx > 0 ? name.substring(idx + 1).toLowerCase() : ""
  }

  function iconFor(entry) {
    var ext = extOf(entry.name)
    if (ext === "iso") return "󰗮"
    if (FileTypeConfig.imageExt.indexOf(ext) >= 0) return "󰺰"
    if (FileTypeConfig.videoExt.indexOf(ext) >= 0) return "󰸬"
    if (FileTypeConfig.audioExt.indexOf(ext) >= 0) return "󰸪"
    if (FileTypeConfig.archiveExt.indexOf(ext) >= 0) return "󰗄"
    if (ext === "pdf") return "󰈦"
    if (FileTypeConfig.codeExt.indexOf(ext) >= 0) return "󱀫"
    return "󰈤"
  }

  function isImage(entry) {
    return entry.type === "file" && FileTypeConfig.imageExt.indexOf(extOf(entry.name)) >= 0
  }

  function isVideo(entry) {
    return entry.type === "file" && FileTypeConfig.videoExt.indexOf(extOf(entry.name)) >= 0
  }

  function isAudio(entry) {
    return entry.type === "file" && FileTypeConfig.audioExt.indexOf(extOf(entry.name)) >= 0
  }

  function isPdf(entry) {
    return entry.type === "file" && extOf(entry.name) === "pdf"
  }
}
