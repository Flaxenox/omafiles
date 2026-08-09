import QtQuick
import "../logic"
import "../services"

// ControllerRegistry -- ÚNICO propietario de todos los controladores de
// logic/ (Fase 11.C, josema: erradicar el ownership disperso que señalaba la
// auditoría 2026-08-09). Antes OmafilesContent instanciaba los 22
// controladores + los usaba por id como god object; ahora los instancia
// aquí y los recibe por propiedad. Los controladores siguen viendo
// OmafilesContent como `root` (estado caliente en NavState + fachada por
// delegación) y la ListView activa como `list` -- ambos inyectados.
//
// `root: registry.root` / `list: registry.list` van CUALIFICADOS: como
// registry tiene properties root/list y cada controlador también, un
// `root: root` sin cualificar se autorreferenciaría (binding loop -> null,
// mismo caso que MainLayout). Las referencias cruzadas entre controladores
// (selectionOps, archiveActions, tabOps...) son ids, no properties, así que
// se resuelven inequívocamente y se quedan sin cualificar.
Item {
  id: registry

  property Item root
  property Item list

  readonly property alias archiveActions: archiveActions
  readonly property alias fileOps: fileOps
  readonly property alias videoThumbs: videoThumbs
  readonly property alias renameOps: renameOps
  readonly property alias clipboardOps: clipboardOps
  readonly property alias dragDropOps: dragDropOps
  readonly property alias searchOps: searchOps
  readonly property alias openWithOps: openWithOps
  readonly property alias fileMeta: fileMeta
  readonly property alias deleteOps: deleteOps
  readonly property alias tabOps: tabOps
  readonly property alias selectionOps: selectionOps
  readonly property alias sortOps: sortOps
  readonly property alias fileTypeUtils: fileTypeUtils
  readonly property alias bookmarkOps: bookmarkOps
  readonly property alias navController: navController
  readonly property alias openProc: openProc
  readonly property alias mountOps: mountOps
  readonly property alias persistence: persistence
  readonly property alias actionEngine: actionEngine
  readonly property alias conflictActions: conflictActions
  readonly property alias previewLoader: previewLoader
  readonly property alias propertiesLoader: propertiesLoader

  ArchiveActions {
    id: archiveActions
    root: registry.root
    list: registry.list
    selectionOps: selectionOps
    sortOps: sortOps
    actionEngine: actionEngine
    navController: navController
    fileTypeUtils: fileTypeUtils
  }

  FileOps {
    id: fileOps
    root: registry.root
    selectionOps: selectionOps
    actionEngine: actionEngine
  }

  VideoThumbnails {
    id: videoThumbs
    root: registry.root
  }

  RenameOps {
    id: renameOps
    root: registry.root
    actionEngine: actionEngine
    navController: navController
  }

  ClipboardOps {
    id: clipboardOps
    root: registry.root
    selectionOps: selectionOps
    actionEngine: actionEngine
  }

  DragDropOps {
    id: dragDropOps
    root: registry.root
    conflictActions: conflictActions
    selectionOps: selectionOps
  }

  SearchOps {
    id: searchOps
    root: registry.root
    list: registry.list
    selectionOps: selectionOps
    sortOps: sortOps
    navController: navController
  }

  OpenWithOps {
    id: openWithOps
    root: registry.root
    bookmarkOps: bookmarkOps
  }

  FileMeta {
    id: fileMeta
    root: registry.root
  }

  DeleteOps {
    id: deleteOps
    root: registry.root
    selectionOps: selectionOps
    actionEngine: actionEngine
  }

  TabOps {
    id: tabOps
    root: registry.root
    list: registry.list
    archiveActions: archiveActions
    previewLoader: previewLoader
    navController: navController
  }

  SelectionOps {
    id: selectionOps
    root: registry.root
    previewLoader: previewLoader
  }

  SortOps {
    id: sortOps
    root: registry.root
    fileTypeUtils: fileTypeUtils
  }

  FileTypeUtils {
    id: fileTypeUtils
    root: registry.root
  }

  BookmarkOps {
    id: bookmarkOps
    root: registry.root
    persistence: persistence
    tabOps: tabOps
    mountOps: mountOps
    navController: navController
    fileTypeUtils: fileTypeUtils
  }

  NavigationController {
    id: navController
    root: registry.root
    list: registry.list
    archiveActions: archiveActions
    mountOps: mountOps
    bookmarkOps: bookmarkOps
    selectionOps: selectionOps
    sortOps: sortOps
  }

  // Lanzador compartido para abrir con la app por defecto / abrir una
  // terminal aquí -- ver openWithDefault()/openTerminalHere() más
  // arriba. ProcessRunner (con seguimiento), no Detached: bug real
  // documentado ahí (gio open vs xdg-open bajo Hyprland, envuelto en
  // bash -c).
  ProcessRunner {
    id: openProc
  }

  MountActions {
    id: mountOps
    root: registry.root
    tabOps: tabOps
    navController: navController
  }

  Persistence {
    id: persistence
    root: registry.root
    tabOps: tabOps
    navController: navController
  }

  ActionEngine {
    id: actionEngine
    root: registry.root
    navController: navController
  }

  ConflictActions {
    id: conflictActions
    root: registry.root
    archiveActions: archiveActions
    fileOps: fileOps
    renameOps: renameOps
    clipboardOps: clipboardOps
    selectionOps: selectionOps
    bookmarkOps: bookmarkOps
    actionEngine: actionEngine
    fileTypeUtils: fileTypeUtils
  }

  PreviewLoader {
    id: previewLoader
    root: registry.root
    videoThumbs: videoThumbs
    fileMeta: fileMeta
    fileTypeUtils: fileTypeUtils
  }


  PropertiesLoader {
    id: propertiesLoader
    root: registry.root
    selectionOps: selectionOps
  }
}
