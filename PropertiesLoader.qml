import QtQuick
import Quickshell.Io
import qs.Commons
import "Utils.js" as Utils

// Carga de metadatos de fichero (permisos y propiedades) -- decimoctavo
// componente extraído de Omafiles.qml. Junta startChmod()/showProperties()/
// showPropertiesForSelection() con los tres Process que alimentan (stat de
// permisos, stat de propiedades, du), que antes vivían a más de mil líneas
// de distancia de la función que los lanzaba. ChmodPanel.qml/
// PropertiesPanel.qml (ya extraídos antes) solo pintan root.chmodMode/
// root.propertiesSize/etc. -- este componente es quien los rellena.
//
// Deliberadamente NO incluye commitChmod/chmodDigit/chmodBitSet/
// toggleChmodBit (se quedan en Omafiles.qml) -- esas no tocan ningún
// Process, solo leen/escriben root.chmodMode y pasan por runAction() (el
// sistema central de acciones/undo), así que moverlas aquí no habría
// eliminado ninguna duplicación ni acercado nada a lo que sí lanza.
Item {
  property Item root: null

  function startChmod(entries) {
    if (root.inArchive) return
    if (!entries || entries.length === 0) return
    root.chmodNames = entries.map(function (e) { return e.name })
    root.chmodMode = ""
    root.chmodMixed = false
    root.chmodHasDir = entries.some(function (e) { return e.type === "dir" })
    root.chmodRecursive = false
    var paths = entries.map(function (e) { return Util.shellQuote(root.joinPath(root.currentPath, e.name)) }).join(" ")
    chmodStatProc.command = ["bash", "-c", "stat -c%a -- " + paths]
    chmodStatProc.running = true
    root.chmodOpen = true
  }

  function showPropertiesForSelection() {
    // root.currentPath sigue siendo la carpeta real que contiene el
    // archivo mientras se navega dentro de él -- sin este guard,
    // Properties intentaría hacer stat/du de "carpeta-real/nombre-dentro-
    // del-zip", que no existe (o, peor, podría coincidir por casualidad
    // con un fichero real de ese nombre en la carpeta contenedora y
    // enseñar datos de OTRO fichero sin que se note el error).
    if (root.inArchive) return
    var entries = root.selectedEntries()
    if (entries.length === 0) return
    if (entries.length === 1) { showProperties(entries[0]); return }
    root.propertiesRequestId += 1
    root.propertiesMulti = true
    root.propertiesEntry = null
    root.propertiesCount = entries.length
    root.propertiesSize = ""
    root.propertiesSizeLoading = true
    root.propertiesPerms = ""
    root.propertiesOwner = ""
    root.propertiesMtime = ""
    root.propertiesOpen = true
    var quoted = entries.map(function (e) {
      return Util.shellQuote(root.joinPath(root.currentPath, e.name))
    }).join(" ")
    root._propertiesDuOwner = root.propertiesRequestId
    propertiesDuProc.command = ["bash", "-c", "du -shc -- " + quoted + " | tail -n1"]
    propertiesDuProc.running = true
  }

  function showProperties(entry) {
    if (!entry) return
    root.propertiesRequestId += 1
    root.propertiesMulti = false
    var path = root.joinPath(root.currentPath, entry.name)
    root.propertiesEntry = entry
    root.propertiesSize = entry.type === "dir" ? "" : Utils.formatSize(entry.size)
    root.propertiesSizeLoading = entry.type === "dir"
    root.propertiesPerms = ""
    root.propertiesOwner = ""
    root.propertiesMtime = ""
    root.propertiesOpen = true
    root._propertiesStatOwner = root.propertiesRequestId
    propertiesStatProc.command = ["stat", "-c", "%A %a\t%U:%G\t%y", "--", path]
    propertiesStatProc.running = true
    // Deliberadamente NO se toca propertiesDuProc si entry no es carpeta
    // (el tamaño ya se conoce sin proceso). Un "du" anterior de una
    // carpeta puede seguir corriendo en ese caso -- por eso el guard de
    // _propertiesDuOwner de más abajo es imprescindible, no solo para
    // cuando SÍ se relanza.
    if (entry.type === "dir") {
      root._propertiesDuOwner = root.propertiesRequestId
      propertiesDuProc.command = ["du", "-sh", "--", path]
      propertiesDuProc.running = true
    }
  }

  Process {
    id: chmodStatProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n").filter(function (l) { return l.length > 0 })
        if (lines.length === 0) return
        var allSame = lines.every(function (l) { return l === lines[0] })
        root.chmodMixed = !allSame
        root.chmodMode = allSame ? lines[0] : ""
        // stat conserva el orden de los argumentos -- lines[i] es el modo
        // de root.chmodNames[i]. Guardado para poder deshacer (ver
        // commitChmod/chmodOriginalModes).
        var orig = {}
        for (var i = 0; i < root.chmodNames.length && i < lines.length; i++) orig[root.chmodNames[i]] = lines[i]
        root.chmodOriginalModes = orig
      }
    }
  }

  Process {
    id: propertiesStatProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Descarta la respuesta si el usuario ya cambió a otro ítem
        // mientras este "stat" estaba en vuelo (ver propertiesRequestId).
        if (root._propertiesStatOwner !== root.propertiesRequestId) return
        var parts = String(text || "").trim().split("\t")
        root.propertiesPerms = parts[0] || ""
        root.propertiesOwner = parts[1] || ""
        root.propertiesMtime = parts[2] || ""
      }
    }
  }

  Process {
    id: propertiesDuProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Mismo guard que propertiesStatProc -- este es el que de verdad
        // importa: un "du" de una carpeta grande puede tardar segundos, y
        // sin esto su resultado tardío pisaba el tamaño del ítem que el
        // usuario esté mirando ahora, aunque ya no tenga nada que ver con
        // la carpeta que se estaba midiendo.
        if (root._propertiesDuOwner !== root.propertiesRequestId) return
        root.propertiesSize = String(text || "").split("\t")[0] || ""
        root.propertiesSizeLoading = false
      }
    }
  }
}
