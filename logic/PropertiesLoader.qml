import QtQuick
import "../state"
import "../services"
import "../Utils.js" as Utils

// Carga de metadatos de fichero (permisos y propiedades) -- decimoctavo
// componente extraído de Omafiles.qml. Junta startChmod()/showProperties()/
// showPropertiesForSelection() con los tres Process que alimentan (stat de
// permisos, stat de propiedades, du), que antes vivían a más de mil líneas
// de distancia de la función que los lanzaba. ChmodPanel.qml/
// PropertiesPanel.qml (ya extraídos antes) solo pintan ChmodState.chmodMode/
// PropertiesState.propertiesSize/etc. -- este componente es quien los rellena.
//
// Deliberadamente NO incluye commitChmod/chmodDigit/chmodBitSet/
// toggleChmodBit (se quedan en Omafiles.qml) -- esas no tocan ningún
// Process, solo leen/escriben ChmodState.chmodMode y pasan por runAction() (el
// sistema central de acciones/undo), así que moverlas aquí no habría
// eliminado ninguna duplicación ni acercado nada a lo que sí lanza.
Item {
  property Item root: null
  property Item selectionOps: null

  function startChmod(entries) {
    if (ArchiveState.inArchive) return
    if (!entries || entries.length === 0) return
    ChmodState.chmodNames = entries.map(function (e) { return e.name })
    ChmodState.chmodHasDir = entries.some(function (e) { return e.type === "dir" })
    ChmodState.chmodRecursive = false
    // Modo octal NATIVO (BUG-03): octalModes en vez de un `stat -c%a -- <todas
    // las rutas>` en una sola línea bash, que reventaba ARG_MAX con selección
    // enorme. Devuelve el modo en el MISMO orden que las rutas ("" si falla),
    // así el mapeo con chmodNames (para deshacer) se mantiene alineado.
    var modes = FileOperations.octalModes(entries.map(function (e) {
      return Utils.joinPath(NavState.currentPath, e.name)
    }))
    var valid = modes.filter(function (m) { return m.length > 0 })
    var allSame = valid.length > 0 && valid.every(function (m) { return m === valid[0] })
    ChmodState.chmodMixed = !allSame
    ChmodState.chmodMode = allSame ? valid[0] : ""
    var orig = {}
    for (var i = 0; i < ChmodState.chmodNames.length && i < modes.length; i++)
      if (modes[i].length > 0) orig[ChmodState.chmodNames[i]] = modes[i]
    ChmodState.chmodOriginalModes = orig
    ChmodState.chmodOpen = true
  }

  function showPropertiesForSelection() {
    // NavState.currentPath sigue siendo la carpeta real que contiene el
    // archivo mientras se navega dentro de él -- sin este guard,
    // Properties intentaría hacer stat/du de "carpeta-real/nombre-dentro-
    // del-zip", que no existe (o, peor, podría coincidir por casualidad
    // con un fichero real de ese nombre en la carpeta contenedora y
    // enseñar datos de OTRO fichero sin que se note el error).
    if (ArchiveState.inArchive) return
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    if (entries.length === 1) { showProperties(entries[0]); return }
    PropertiesState.propertiesRequestId += 1
    PropertiesState.propertiesMulti = true
    PropertiesState.propertiesEntry = null
    PropertiesState.propertiesCount = entries.length
    PropertiesState.propertiesSize = ""
    PropertiesState.propertiesSizeLoading = true
    PropertiesState.propertiesPerms = ""
    PropertiesState.propertiesOwner = ""
    PropertiesState.propertiesMtime = ""
    PropertiesState.propertiesOpen = true
    // Tamaño NATIVO (BUG-03): totalSize en vez de un `du -shc -- <todas las
    // rutas>` en una sola línea bash (ARG_MAX con selección enorme). Suma de
    // bytes aparentes del árbol, formateada igual; síncrono, sin proceso ni
    // carrera (por eso ya no hace falta el guard _propertiesDuOwner aquí).
    var bytes = FileOperations.totalSize(entries.map(function (e) {
      return Utils.joinPath(NavState.currentPath, e.name)
    }))
    PropertiesState.propertiesSize = Utils.formatSize(bytes)
    PropertiesState.propertiesSizeLoading = false
  }

  function showProperties(entry) {
    if (!entry) return
    PropertiesState.propertiesRequestId += 1
    PropertiesState.propertiesMulti = false
    var path = Utils.joinPath(NavState.currentPath, entry.name)
    PropertiesState.propertiesEntry = entry
    PropertiesState.propertiesSize = entry.type === "dir" ? "" : Utils.formatSize(entry.size)
    PropertiesState.propertiesSizeLoading = entry.type === "dir"
    PropertiesState.propertiesPerms = ""
    PropertiesState.propertiesOwner = ""
    PropertiesState.propertiesMtime = ""
    PropertiesState.propertiesOpen = true
    PropertiesState._propertiesStatOwner = PropertiesState.propertiesRequestId
    propertiesStatProc.start(["stat", "-c", "%A %a\t%U:%G\t%y", "--", path])
    // Deliberadamente NO se toca propertiesDuProc si entry no es carpeta
    // (el tamaño ya se conoce sin proceso). Un "du" anterior de una
    // carpeta puede seguir corriendo en ese caso -- por eso el guard de
    // _propertiesDuOwner de más abajo es imprescindible, no solo para
    // cuando SÍ se relanza.
    if (entry.type === "dir") {
      PropertiesState._propertiesDuOwner = PropertiesState.propertiesRequestId
      propertiesDuProc.start(["du", "-sh", "--", path])
    }
  }

  ProcessRunner {
    id: propertiesStatProc
    onFinished: function (result) {
      // Descarta la respuesta si el usuario ya cambió a otro ítem
      // mientras este "stat" estaba en vuelo (ver propertiesRequestId).
      if (PropertiesState._propertiesStatOwner !== PropertiesState.propertiesRequestId) return
      var parts = String(result.stdout || "").trim().split("\t")
      PropertiesState.propertiesPerms = parts[0] || ""
      PropertiesState.propertiesOwner = parts[1] || ""
      PropertiesState.propertiesMtime = parts[2] || ""
    }
  }

  ProcessRunner {
    id: propertiesDuProc
    onFinished: function (result) {
      // Mismo guard que propertiesStatProc -- este es el que de verdad
      // importa: un "du" de una carpeta grande puede tardar segundos, y
      // sin esto su resultado tardío pisaba el tamaño del ítem que el
      // usuario esté mirando ahora, aunque ya no tenga nada que ver con
      // la carpeta que se estaba midiendo.
      if (PropertiesState._propertiesDuOwner !== PropertiesState.propertiesRequestId) return
      PropertiesState.propertiesSize = String(result.stdout || "").split("\t")[0] || ""
      PropertiesState.propertiesSizeLoading = false
    }
  }
}
