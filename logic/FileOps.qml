import QtQuick
import qs.Commons
import "../state"

// Operaciones de fichero sueltas con undo propio: renombrado en lote,
// chmod, crear enlace simbólico, restaurar de la papelera --
// decimoquinto componente extraído de Omafiles.qml. Todas comparten el
// mismo patrón (montar el/los comando(s), runAction(), pushUndo() con el
// comando inverso) sin tener ningún Process propio -- usan el motor
// central de ActionEngine a través de los wrappers de root
// (root.runAction/root.pushUndo/root.chainCmds).
Item {
  property Item root: null
  property Item selectionOps: null

  function startBulkRename() {
    if (ArchiveState.inArchive) return
    DialogsState.bulkRenamePattern = "{name}{ext}"
    DialogsState.bulkRenameOpen = true
  }

  function runPendingBulkRename() {
    var pairs = ConflictState.pendingBulkRename
    ConflictState.pendingBulkRename = null
    ConflictState.bulkRenameConflictOpen = false
    if (!pairs) return
    // Antes bulk rename era la única operación de riesgo (junto a chmod)
    // sin ningún undo -- un patrón {n}/{name}/{ext} mal escrito podía
    // renombrar decenas de ficheros de golpe sin red de seguridad.
    var toRename = pairs.filter(function (p) { return p.newName !== p.oldName })
    var cmds = toRename.map(function (p) {
      return "mv -n -- " + Util.shellQuote(p.oldPath) + " " + Util.shellQuote(p.newPath)
    })
    if (cmds.length === 0) return
    var bulkRenameCmd = root.chainCmds(cmds)
    root.runAction(bulkRenameCmd, "Renaming " + cmds.length + " items…", function () {
      var label = toRename.length === 1 ? "rename \"" + toRename[0].oldName + "\"" : "bulk rename " + toRename.length + " items"
      root.pushUndo(label, function () {
        var undoCmds = toRename.map(function (p) {
          return "mv -n -- " + Util.shellQuote(p.newPath) + " " + Util.shellQuote(p.oldPath)
        })
        return root.runAction(root.chainCmds(undoCmds))
      }, function () {
        return root.runAction(bulkRenameCmd)
      })
    })
  }

  function cancelPendingBulkRename() {
    ConflictState.pendingBulkRename = null
    ConflictState.bulkRenameConflictOpen = false
  }

  function commitChmod(mode) {
    ChmodState.chmodOpen = false
    mode = mode.trim()
    if (!/^[0-7]{3,4}$/.test(mode) || ChmodState.chmodNames.length === 0) return
    // -R es inofensivo sobre un fichero suelto (no baja a ningún sitio),
    // así que se puede aplicar al comando entero sin separar ficheros de
    // carpetas -- más simple que dos ramas de chainCmds distintas.
    var flag = ChmodState.chmodRecursive ? "-R " : ""
    var cmds = ChmodState.chmodNames.map(function (n) {
      return "chmod " + flag + mode + " -- " + Util.shellQuote(root.joinPath(root.currentPath, n))
    })
    var label = ChmodState.chmodNames.length === 1
      ? "Setting permissions for \"" + ChmodState.chmodNames[0] + "\"…"
      : "Setting permissions for " + ChmodState.chmodNames.length + " items…"
    // chmod era, junto a bulk rename, la única acción de riesgo real
    // (más aún con -R) sin ningún undo. Restaura el modo original de
    // cada ítem seleccionado -- NO el de su contenido si se aplicó
    // recursivo, ver el comentario de chmodOriginalModes.
    var names = ChmodState.chmodNames
    var originalModes = ChmodState.chmodOriginalModes
    var chmodCmd = root.chainCmds(cmds)
    root.runAction(chmodCmd, label, function () {
      var undoLabel = names.length === 1 ? "permissions on \"" + names[0] + "\"" : "permissions on " + names.length + " items"
      root.pushUndo(undoLabel, function () {
        var undoCmds = names.filter(function (n) { return !!originalModes[n] }).map(function (n) {
          return "chmod " + originalModes[n] + " -- " + Util.shellQuote(root.joinPath(root.currentPath, n))
        })
        if (undoCmds.length === 0) return false
        return root.runAction(root.chainCmds(undoCmds))
      }, function () {
        return root.runAction(chmodCmd)
      })
    })
  }

  // ownerIdx: 0=owner (tú) 1=group 2=other. bit: 4=read 2=write 1=execute.
  function toggleChmodBit(ownerIdx, bit) {
    var mode = String(ChmodState.chmodMode || "0")
    while (mode.length < 3) mode = "0" + mode
    var digits = mode.substring(mode.length - 3)
    var arr = [digits.charCodeAt(0) - 48, digits.charCodeAt(1) - 48, digits.charCodeAt(2) - 48]
    arr[ownerIdx] = arr[ownerIdx] ^ bit
    ChmodState.chmodMode = "" + arr[0] + arr[1] + arr[2]
  }

  function makeLinkFor(entry) {
    if (ArchiveState.inArchive) return
    if (!entry) return
    var target = root.joinPath(root.currentPath, entry.name)
    var linkName = "Link to " + entry.name
    var linkPath = root.joinPath(root.currentPath, linkName)
    // El undo solo se registra si "ln -s" confirmó éxito -- antes se
    // registraba a ciegas, así que si ya existía un archivo con el nombre
    // "Link to X" (ln sin -f falla en silencio en ese caso), un Ctrl+Z
    // posterior lo borraba igualmente aunque no tuviera nada que ver con
    // el enlace que se intentó crear.
    var makeLinkCmd = "ln -s -- " + Util.shellQuote(target) + " " + Util.shellQuote(linkPath)
    root.runAction(makeLinkCmd, undefined, function () {
      root.pushUndo("make link \"" + linkName + "\"", function () {
        return root.runAction("rm -- " + Util.shellQuote(linkPath))
      }, function () {
        return root.runAction(makeLinkCmd)
      })
    })
  }

  function restoreFromTrash() {
    var entries = selectionOps.selectedEntries()
    if (entries.length === 0) return
    // TrashState.trashInfo (ver trash-info.sh) ya sabe la ruta original
    // absoluta de cada ítem, resuelta correctamente incluso para la
    // papelera de otro disco (donde Path= es relativo al punto de
    // montaje, no a casa) -- restore-by-origpath.sh la usa para
    // localizar el .trashinfo correcto sin asumir una única papelera.
    var cmds = entries
      .filter(function (e) { return !!TrashState.trashInfo[e.name] })
      .map(function (e) {
        return "bash " + Util.shellQuote(root.pluginDir + "/restore-by-origpath.sh") + " " + Util.shellQuote(TrashState.trashInfo[e.name].origPath)
      })
    if (cmds.length === 0) return
    root.runAction(root.chainCmds(cmds), entries.length === 1 ? "Restoring \"" + entries[0].name + "\"…" : "Restoring " + entries.length + " items…")
  }
}
