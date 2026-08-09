import QtQuick
import qs.Commons
import qs.Ui
import "../dialogs"
import "../state"

// DialogLayer -- capa de diálogos/overlays modales de Omafiles (Fase 11.B,
// josema: descomponer el god object core/OmafilesContent.qml por
// responsabilidad). Contiene TODO lo que antes eran los últimos ~315
// líneas de OmafilesContent: renombrar en lote, conectar a servidor,
// permisos, propiedades, ayuda de atajos, tarjeta de copiar/mover en curso,
// abrir-con, menú contextual, los siete ConfirmDialog, los dos
// ConflictResolveDialog y la paleta de comandos.
//
// Dependencias INYECTADAS explícitamente (mismo patrón que ActiveFileList,
// no vía root.* -- ver ARCHITECTURE.md: dialogs reciben datos por
// props/callbacks). root/list para la fachada y devolver el foco; los ops
// de logic/ que cada diálogo confirma. Los siete ConfirmDialog se exponen
// como alias porque ActiveFileList los referencia de vuelta (abre/cierra
// según el resultado del listado).
Item {
  id: dialogLayer
  anchors.fill: parent

  property Item root
  property Item list
  property var conflictActions
  property var mountOps
  property var fileOps
  property var openWithOps
  property var deleteOps
  property var renameOps
  property var archiveActions
  property var clipboardOps
  property var dragDropOps

  property alias deleteConfirm: deleteConfirm
  property alias renameConflictConfirm: renameConflictConfirm
  property alias newFileConflictConfirm: newFileConflictConfirm
  property alias newFolderConflictConfirm: newFolderConflictConfirm
  property alias extractConflictConfirm: extractConflictConfirm
  property alias compressConflictConfirm: compressConflictConfirm
  property alias bulkRenameConflictConfirm: bulkRenameConflictConfirm

  // ---------- Renombrar en lote ----------
  BulkRenamePanel {
    anchors.fill: parent
    open: DialogsState.bulkRenameOpen
    selectedCount: SelectionState.selectedIndices.length
    pattern: DialogsState.bulkRenamePattern
    history: BookmarksState.bulkRenameHistory
    onCloseRequested: DialogsState.bulkRenameOpen = false
    onRenameRequested: function (pattern) { DialogsState.bulkRenamePattern = pattern; conflictActions.commitBulkRename() }
    onFocusReturnRequested: list.forceActiveFocus()
  }

  // ---------- Conectar a servidor ----------
  ConnectServer {
    anchors.fill: parent
    open: DialogsState.connectServerOpen
    connecting: DialogsState.networkConnecting
    uri: DialogsState.connectServerUri
    errorText: DialogsState.connectServerError
    onConnectRequested: function (uri) { DialogsState.connectServerUri = uri; mountOps.commitConnectToServer() }
    onCancelConnectingRequested: mountOps.cancelNetworkConnect()
    onCloseRequested: mountOps.cancelConnectToServer()
    onFocusReturnRequested: list.forceActiveFocus()
  }

  // ---------- Permisos (chmod) ----------
  ChmodPanel {
    anchors.fill: parent
    open: ChmodState.chmodOpen
    names: ChmodState.chmodNames
    mixed: ChmodState.chmodMixed
    mode: ChmodState.chmodMode
    hasDir: ChmodState.chmodHasDir
    recursive: ChmodState.chmodRecursive
    onCloseRequested: ChmodState.chmodOpen = false
    onBitToggled: function (ownerIdx, bit) { fileOps.toggleChmodBit(ownerIdx, bit) }
    onRecursiveToggled: ChmodState.chmodRecursive = !ChmodState.chmodRecursive
    onApplyRequested: function (mode) { fileOps.commitChmod(mode) }
  }

  // ---------- Propiedades ----------
  PropertiesPanel {
    anchors.fill: parent
    open: PropertiesState.propertiesOpen
    multi: PropertiesState.propertiesMulti
    count: PropertiesState.propertiesCount
    entry: PropertiesState.propertiesEntry
    sizeLoading: PropertiesState.propertiesSizeLoading
    size: PropertiesState.propertiesSize
    perms: PropertiesState.propertiesPerms
    owner: PropertiesState.propertiesOwner
    mtime: PropertiesState.propertiesMtime
    onCloseRequested: PropertiesState.propertiesOpen = false
  }

  // ---------- Ayuda de atajos de teclado ----------
  // Primer componente extraído a su propio fichero (ShortcutsHelp.qml)
  // -- ver comentario ahí sobre por qué se eligió este trozo primero.
  ShortcutsHelp {
    anchors.fill: parent
    open: DialogsState.shortcutsHelpOpen
    onRequestClose: DialogsState.shortcutsHelpOpen = false
  }

  // ---------- Copiar/mover en curso ----------
  // No bloquea el resto de la ventana (sin MouseArea de fondo a pantalla
  // completa) -- cp/mv no reportan progreso real, así que esto es solo
  // "sigue vivo" (puntos animados) + Cancel, no una barra de porcentaje.
  BorderSurface {
    id: actionBusyCard
    visible: ActionState.actionBusy
    width: Math.min(parent.width - 80, 420)
    height: actionBusyColumn.implicitHeight + contentTopInset + contentBottomInset
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.lg
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.flat(Color.menu.border, Style.normalBorderWidth)
    padding: Style.spacing.sm
    z: 25

    Column {
      id: actionBusyColumn
      anchors.fill: parent
      anchors.topMargin: actionBusyCard.contentTopInset
      anchors.rightMargin: actionBusyCard.contentRightInset
      anchors.bottomMargin: actionBusyCard.contentBottomInset
      anchors.leftMargin: actionBusyCard.contentLeftInset
      spacing: Style.spacing.xs

      Row {
        id: actionBusyRow
        width: parent.width
        spacing: Style.spacing.sm

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - cancelActionButton.width - parent.spacing
          // Porcentaje real para copiar/mover (ver
          // startCopyProgress/actionProgressPct); puntos animados
          // para cualquier otra acción, que no tiene un "tamaño
          // total" con el que calcular nada.
          text: ActionState.actionLabel + (ActionState.actionProgressPct >= 0 ? " " + Math.round(ActionState.actionProgressPct) + "%" : root.actionBusyDots)
          font.pixelSize: Style.font.subtitle
          font.family: Style.font.family
          color: Color.menu.text
          elide: Text.ElideRight
        }

        Button {
          id: cancelActionButton
          text: "Cancel"
          bordered: true
          anchors.verticalCenter: parent.verticalCenter
          Accessible.role: Accessible.Button
          Accessible.name: text
          onClicked: root.cancelAction()
        }
      }

      Rectangle {
        visible: ActionState.actionProgressPct >= 0
        width: parent.width
        height: 3
        radius: height / 2
        color: Qt.darker(Color.menu.text, 2.5)

        Rectangle {
          width: parent.width * (ActionState.actionProgressPct / 100)
          height: parent.height
          radius: height / 2
          color: Color.accent

          Behavior on width { NumberAnimation { duration: 200 } }
        }
      }
    }
  }

  Timer {
    running: ActionState.actionBusy
    repeat: true
    interval: 400
    onTriggered: root.actionBusyDots = root.actionBusyDots.length >= 3 ? "" : root.actionBusyDots + "."
  }

  // ---------- Abrir con... ----------
  OpenWithPanel {
    anchors.fill: parent
    open: PreviewState.openWithOpen
    entry: PreviewState.openWithEntry
    apps: PreviewState.openWithApps
    onCloseRequested: PreviewState.openWithOpen = false
    onAppSelected: function (appId) { openWithOps.launchWith(appId) }
  }

  // ---------- Menú contextual ----------
  ContextMenuPanel {
    anchors.fill: parent
    open: ContextMenuState.contextMenuOpen
    menuX: ContextMenuState.contextMenuX
    menuY: ContextMenuState.contextMenuY
    actions: ContextMenuState.contextMenuActions
    onCloseRequested: ContextMenuState.contextMenuOpen = false
  }

  ConfirmDialog {
    id: deleteConfirm
    anchors.fill: parent
    z: 10
    opened: root.pendingDeleteNames.length > 0
    message: NavState.currentPath === Paths.trashDir
      ? (root.pendingDeleteNames.length === 1
        ? "Delete \"" + root.pendingDeleteNames[0] + "\" PERMANENTLY? This cannot be undone."
        : "Delete " + root.pendingDeleteNames.length + " items PERMANENTLY? This cannot be undone.")
      : (root.pendingDeleteNames.length === 1
        ? "Send \"" + root.pendingDeleteNames[0] + "\" to trash?"
        : "Send " + root.pendingDeleteNames.length + " items to trash?")
    confirmText: "Delete"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: root.pendingDeleteNames = []
    onConfirmed: deleteOps.confirmDelete()
  }

  ConfirmDialog {
    id: renameConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.renameConflictOpen
    message: ConflictState.pendingRename
      ? "\"" + ConflictState.pendingRename.newPath.substring(ConflictState.pendingRename.newPath.lastIndexOf("/") + 1) + "\" already exists here. Overwrite?"
      : ""
    confirmText: "Overwrite"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: renameOps.cancelPendingRename()
    onConfirmed: renameOps.runPendingRename(true)
  }

  ConfirmDialog {
    id: newFileConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.newFileConflictOpen
    message: ConflictState.pendingNewFile
      ? "\"" + ConflictState.pendingNewFile.name + "\" already exists here. Overwrite?"
      : ""
    confirmText: "Overwrite"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: renameOps.cancelPendingNewFile()
    onConfirmed: renameOps.runPendingNewFile(true)
  }

  ConfirmDialog {
    id: newFolderConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.newFolderConflictOpen
    message: ConflictState.pendingNewFolder
      ? "\"" + ConflictState.pendingNewFolder.name + "\" already exists here. Overwrite?"
      : ""
    confirmText: "Overwrite"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: renameOps.cancelPendingNewFolder()
    onConfirmed: renameOps.runPendingNewFolder(true)
  }

  ConfirmDialog {
    id: extractConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.extractConflictOpen
    message: ConflictState.extractConflictNames.length === 1
      ? "\"" + ConflictState.extractConflictNames[0] + "\" already exists here and will be overwritten."
      : ConflictState.extractConflictNames.length + " items already exist here and will be overwritten."
    confirmText: "Overwrite"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: archiveActions.cancelPendingExtract()
    onConfirmed: archiveActions.runPendingExtract()
  }

  ConfirmDialog {
    id: compressConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.compressConflictOpen
    message: ConflictState.pendingCompress ? "\"" + ConflictState.pendingCompress.archiveName + "\" already exists. Overwrite it?" : ""
    confirmText: "Overwrite"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: archiveActions.cancelPendingCompress()
    onConfirmed: archiveActions.runPendingCompress()
  }

  ConfirmDialog {
    id: bulkRenameConflictConfirm
    anchors.fill: parent
    z: 10
    opened: ConflictState.bulkRenameConflictOpen
    message: ConflictState.bulkRenameConflictCount === 1
      ? "1 rename would collide with an existing name and will be skipped. Rename the rest?"
      : ConflictState.bulkRenameConflictCount + " renames would collide with existing or duplicate names and will be skipped. Rename the rest?"
    confirmText: "Continue"
    cancelText: "Cancel"
    background: Color.menu.background
    foreground: Color.menu.text
    onCanceled: fileOps.cancelPendingBulkRename()
    onConfirmed: fileOps.runPendingBulkRename()
  }

  // ---------- Conflicto al pegar ----------
  ConflictResolveDialog {
    anchors.fill: parent
    open: ConflictState.pasteConflictOpen
    names: ConflictState.pasteConflictNames
    onOverwriteRequested: clipboardOps.runPaste("overwrite")
    onSkipRequested: clipboardOps.runPaste("skip")
    onCancelRequested: clipboardOps.cancelPasteConflict()
  }

  // ---------- Conflicto al soltar (drag & drop) ----------
  ConflictResolveDialog {
    anchors.fill: parent
    open: ConflictState.dropConflictOpen
    names: ConflictState.dropConflictNames
    onOverwriteRequested: conflictActions.runDrop("overwrite")
    onSkipRequested: conflictActions.runDrop("skip")
    onCancelRequested: dragDropOps.cancelDropConflict()
  }

  // ---------- Paleta de comandos (: o Ctrl+P) ----------
  CommandPalettePanel {
    anchors.fill: parent
    open: PaletteState.paletteOpen
    query: PaletteState.paletteQuery
    index: PaletteState.paletteIndex
    commands: PaletteState.paletteOpen ? root.filteredPaletteCommands() : []
    onQueryEdited: function (text) { PaletteState.paletteQuery = text; PaletteState.paletteIndex = 0 }
    onCloseRequested: root.closePalette()
    onIndexRequested: function (idx) { PaletteState.paletteIndex = idx }
    onCommandActivated: function (idx) { root.runPaletteCommand(idx) }
    onFocusReturnRequested: list.forceActiveFocus()
  }
}
