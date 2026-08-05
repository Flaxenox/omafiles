import QtQuick
import "../state"

// Atajos de teclado del panel activo (Keys.onPressed de la ListView) --
// primer corte de panels/ActiveFileList.qml (761 líneas, por encima del
// límite 300-500), sacando la parte más "lógica" (un if/else largo que
// decide qué hacer según event.key/modifiers) y dejando dentro la parte
// más visual (delegate de fila, marquee, drag&drop). handlePress() recibe
// el mismo `event` que llegaba a Keys.onPressed -- accepted se sigue
// marcando aquí igual que antes, ActiveFileList solo delega la llamada
// entera.
Item {
  property Item hostRoot: null
  property Item hostListView: null
  property Timer hostGTimer: null
  property Item hostPreviewLoader: null
  property Item hostConflictActions: null
  property Item hostMountOps: null
  property Item hostFileOps: null
  property Item hostRenameOps: null
  property Item hostClipboardOps: null
  property Item hostDragDropOps: null
  property Item hostSearchOps: null
  property Item hostDeleteOps: null
  property Item hostTabOps: null
  property Item hostSortOps: null
  property Item hostSelectionOps: null
  property Item hostDeleteConfirm: null
  property Item hostRenameConflictConfirm: null
  property Item hostExtractConflictConfirm: null
  property Item hostCompressConflictConfirm: null
  property Item hostBulkRenameConflictConfirm: null

  function handlePress(event) {
    if (PaletteState.paletteOpen) return
    if (PreviewState.openWithOpen) {
      if (event.key === Qt.Key_Escape) { PreviewState.openWithOpen = false; event.accepted = true }
      return
    }
    if (ChmodState.chmodOpen) {
      if (event.key === Qt.Key_Escape) { ChmodState.chmodOpen = false; event.accepted = true }
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { hostFileOps.commitChmod(ChmodState.chmodMode); event.accepted = true }
      return
    }
    if (ContextMenuState.contextMenuOpen) {
      if (event.key === Qt.Key_Escape) { ContextMenuState.contextMenuOpen = false; event.accepted = true }
      return
    }
    if (hostRoot.pendingDeleteNames.length > 0) {
      if (hostDeleteConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.renameConflictOpen) {
      if (hostRenameConflictConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.extractConflictOpen) {
      if (hostExtractConflictConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.compressConflictOpen) {
      if (hostCompressConflictConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.bulkRenameConflictOpen) {
      if (hostBulkRenameConflictConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.pasteConflictOpen) {
      if (event.key === Qt.Key_Escape) { hostClipboardOps.cancelPasteConflict(); event.accepted = true }
      return
    }
    if (ConflictState.dropConflictOpen) {
      if (event.key === Qt.Key_Escape) { hostDragDropOps.cancelDropConflict(); event.accepted = true }
      return
    }
    if (PropertiesState.propertiesOpen) {
      if (event.key === Qt.Key_Escape) { PropertiesState.propertiesOpen = false; event.accepted = true }
      return
    }
    if (DialogsState.shortcutsHelpOpen) {
      if (event.key === Qt.Key_Escape || event.key === Qt.Key_Question) { DialogsState.shortcutsHelpOpen = false; event.accepted = true }
      return
    }
    // Red de seguridad -- bulkRenameField normalmente tiene el
    // foco y gestiona Escape/Enter él solo, pero si alguna vez
    // no lo tiene, esto evita que j/k/Supr caigan en la lista de
    // detrás con el diálogo todavía abierto encima.
    if (DialogsState.bulkRenameOpen) {
      if (event.key === Qt.Key_Escape) { DialogsState.bulkRenameOpen = false; event.accepted = true }
      return
    }
    // Misma red de seguridad que bulkRenameOpen -- connectServerField
    // gestiona Escape/Enter él solo mientras tiene el foco.
    if (DialogsState.connectServerOpen) {
      if (event.key === Qt.Key_Escape) {
        if (DialogsState.networkConnecting) hostMountOps.cancelNetworkConnect()
        else hostMountOps.cancelConnectToServer()
        event.accepted = true
      }
      return
    }
    if (hostRoot.creatingFolder || hostRoot.creatingFile || hostRoot.renamingIndex >= 0 || hostRoot.editingPath || hostRoot.searching) return

    var extend = (event.modifiers & Qt.ShiftModifier) !== 0

    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
      hostRoot.openTerminalHere()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      // Con 2+ pestañas, Escape cierra el panel activo (el que
      // tiene el cursor encima, gracias al HoverHandler de cada
      // panel) en vez de la ventana entera -- sustituye a la ×
      // que había antes en cada cabecera. closeTab() ya cae en
      // requestClose() si solo queda 1, así que el comportamiento
      // de siempre (Escape cierra la ventana) no cambia con una
      // sola pestaña abierta.
      if (PreviewState.previewOpen) PreviewState.previewOpen = false
      else hostTabOps.closeTab()
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace || (event.key === Qt.Key_H && event.modifiers === Qt.NoModifier)) {
      hostRoot.goUp()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_L && event.modifiers === Qt.NoModifier)) {
      if (SelectionState.selectedIndex >= 0) hostRoot.enter(hostRoot.visibleEntries[SelectionState.selectedIndex])
      event.accepted = true
    } else if (event.key === Qt.Key_Space) {
      hostPreviewLoader.togglePreview()
      event.accepted = true
    } else if (event.key === Qt.Key_Slash) {
      hostSearchOps.startSearch()
      event.accepted = true
    } else if (event.key === Qt.Key_Colon || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
      hostRoot.openPalette()
      event.accepted = true
    } else if (event.key === Qt.Key_Question) {
      DialogsState.shortcutsHelpOpen = true
      event.accepted = true
    } else if (event.key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
      hostSearchOps.goBottom()
      event.accepted = true
    } else if (event.key === Qt.Key_G && event.modifiers === Qt.NoModifier) {
      if (hostRoot.gPending) { hostSearchOps.goTop(); hostRoot.gPending = false }
      else { hostRoot.gPending = true; hostGTimer.restart() }
      event.accepted = true
    } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && event.modifiers === Qt.NoModifier)) {
      var down = Math.min(hostRoot.visibleEntries.length - 1, SelectionState.selectedIndex + 1)
      if (extend) hostSelectionOps.selectRange(down); else hostSelectionOps.selectOnly(down)
      hostListView.positionViewAtIndex(down, ListView.Contain)
      event.accepted = true
    } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers === Qt.NoModifier)) {
      var up = Math.max(0, SelectionState.selectedIndex - 1)
      if (extend) hostSelectionOps.selectRange(up); else hostSelectionOps.selectOnly(up)
      hostListView.positionViewAtIndex(up, ListView.Contain)
      event.accepted = true
    } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
      hostSelectionOps.selectNone()
      event.accepted = true
    } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
      SelectionState.selectedIndices = Array.from({ length: hostRoot.visibleEntries.length }, function (_, i) { return i })
      event.accepted = true
    } else if (event.key === Qt.Key_I && (event.modifiers & Qt.ControlModifier)) {
      hostSelectionOps.invertSelection()
      event.accepted = true
    } else if (event.key === Qt.Key_F2) {
      hostRenameOps.startRename(SelectionState.selectedIndex)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete) {
      hostDeleteOps.requestDelete()
      event.accepted = true
    } else if (event.key === Qt.Key_F5) {
      hostRoot.refresh()
      event.accepted = true
    } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ShiftModifier)) {
      hostSortOps.reverseSort()
      event.accepted = true
    } else if (event.key === Qt.Key_S && event.modifiers === Qt.NoModifier) {
      hostSortOps.cycleSort()
      event.accepted = true
    } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
      hostSearchOps.startEditPath()
      event.accepted = true
    } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
      hostRenameOps.startNewFolder()
      event.accepted = true
    } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
      // "New file" no tenía atajo propio, a diferencia de
      // "New folder" (Ctrl+Shift+N, arriba) -- solo estaba en
      // paleta/menú contextual.
      hostRenameOps.startNewFile()
      event.accepted = true
    } else if (event.key === Qt.Key_Backslash && (event.modifiers & Qt.ControlModifier)) {
      // Antes alternaba la vista dividida; ahora cada pestaña ES
      // ya un panel visible, así que este atajo simplemente abre
      // uno nuevo (igual que Ctrl+T).
      hostTabOps.newTab()
      event.accepted = true
    } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
      hostRoot.navBack()
      event.accepted = true
    } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
      hostRoot.navForward()
      event.accepted = true
    } else if (event.key === Qt.Key_T && (event.modifiers & Qt.ControlModifier)) {
      hostTabOps.newTab()
      event.accepted = true
    } else if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
      hostTabOps.closeTab()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
      hostTabOps.nextTab()
      event.accepted = true
    } else if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
      hostSearchOps.toggleHidden()
      event.accepted = true
    } else if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
      hostClipboardOps.copySelected()
      event.accepted = true
    } else if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
      hostClipboardOps.cutSelected()
      event.accepted = true
    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
      hostConflictActions.paste()
      event.accepted = true
    } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
      hostRoot.redoLast()
      event.accepted = true
    } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
      hostRoot.redoLast()
      event.accepted = true
    } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
      hostRoot.undoLast()
      event.accepted = true
    }
  }
}
