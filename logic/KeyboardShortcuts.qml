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
  property Item hostActionEngine: null
  property Item hostNavController: null
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
  property Item hostNewFileConflictConfirm: null
  property Item hostNewFolderConflictConfirm: null

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
    if (ConflictState.newFileConflictOpen) {
      if (hostNewFileConflictConfirm.handleKey(event)) event.accepted = true
      return
    }
    if (ConflictState.newFolderConflictOpen) {
      if (hostNewFolderConflictConfirm.handleKey(event)) event.accepted = true
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
    // NavState.searching NO va aquí (Fase 19): mientras la lupa está abierta,
    // el campo de búsqueda vive en la barra superior y tiene su propio foco;
    // si el usuario hace clic en un resultado y la lista recupera el foco,
    // los atajos (navegar, copiar, borrar...) deben funcionar sobre los
    // resultados igual que sobre cualquier listado (req 7).
    if (EditModeState.creatingFolder || EditModeState.creatingFile || EditModeState.renamingIndex >= 0 || EditModeState.editingPath) return

    var extend = (event.modifiers & Qt.ShiftModifier) !== 0

    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
      hostRoot.openTerminalHere()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      // Escape cierra, por este orden, lo que esté "abierto": la búsqueda,
      // la vista previa, o -- con 2+ pestañas -- el panel activo (el que
      // tiene el cursor encima, gracias al HoverHandler de cada panel;
      // sustituye a la × que había antes en cada cabecera). Con UNA sola
      // pestaña y nada abierto, Escape NO hace nada: NO cierra la app
      // (josema) -- antes closeTab() caía en requestClose() y cerraba la
      // ventana entera, comportamiento que ya no queremos.
      if (NavState.searching) hostSearchOps.exitSearch()
      else if (PreviewState.previewOpen) PreviewState.previewOpen = false
      else if (TabsState.tabs.length > 1) hostTabOps.closeTab()
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace || (event.key === Qt.Key_H && event.modifiers === Qt.NoModifier)) {
      hostNavController.goUp()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (event.key === Qt.Key_L && event.modifiers === Qt.NoModifier)) {
      if (SelectionState.selectedIndex >= 0) hostNavController.enter(NavState.visibleEntries[SelectionState.selectedIndex])
      event.accepted = true
    } else if (event.key === Qt.Key_Space) {
      hostPreviewLoader.togglePreview()
      event.accepted = true
    } else if (event.key === Qt.Key_Slash || (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier))) {
      // Ctrl+F (o /) abre la lupa expandible de la barra superior (Fase 19).
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
      var down = Math.min(NavState.visibleEntries.length - 1, SelectionState.selectedIndex + 1)
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
      SelectionState.selectedIndices = Array.from({ length: NavState.visibleEntries.length }, function (_, i) { return i })
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
      hostNavController.refresh()
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
      hostNavController.navBack()
      event.accepted = true
    } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.AltModifier)) {
      hostNavController.navForward()
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
      hostActionEngine.redoLast()
      event.accepted = true
    } else if (event.key === Qt.Key_Y && (event.modifiers & Qt.ControlModifier)) {
      hostActionEngine.redoLast()
      event.accepted = true
    } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
      hostActionEngine.undoLast()
      event.accepted = true
    }
  }
}
