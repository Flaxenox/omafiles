import QtQuick
import "../logic"
import Omafiles.Backend as Backend

// ControllerRegistry -- SOLE owner of all the logic/ controllers
// (Phase 11.C, josema: eradicate the scattered ownership that the
// 2026-08-09 audit flagged). Before, OmafilesContent instantiated the 22
// controllers + used them by id as a god object; now it instantiates them
// here and receives them by property. The controllers still see
// OmafilesContent as `root` (hot state in NavState + facade by
// delegation) and the active ListView as `list` -- both injected.
//
// `root: registry.root` / `list: registry.list` go QUALIFIED: since
// registry has properties root/list and each controller does too, an
// unqualified `root: root` would self-reference (binding loop -> null,
// same case as MainLayout). The cross references between controllers
// (selectionOps, archiveActions, tabOps...) are ids, not properties, so
// they resolve unambiguously and stay unqualified.
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
  readonly property alias bookmarkOps: bookmarkOps
  readonly property alias navController: navController
  readonly property alias openProc: openProc
  readonly property alias mountOps: mountOps
  readonly property alias persistence: persistence
  readonly property alias actionEngine: actionEngine
  readonly property alias conflictActions: conflictActions
  readonly property alias previewLoader: previewLoader
  readonly property alias propertiesLoader: propertiesLoader
  readonly property alias customActions: customActions

  ArchiveActions {
    id: archiveActions
    root: registry.root
    list: registry.list
    selectionOps: selectionOps
    sortOps: sortOps
    actionEngine: actionEngine
    navController: navController
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
  }

  BookmarkOps {
    id: bookmarkOps
    root: registry.root
    persistence: persistence
    tabOps: tabOps
    mountOps: mountOps
    navController: navController
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

  // Shared launcher to open with the default app / open a
  // terminal here.
  Backend.ProcessRunner {
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
  }

  PreviewLoader {
    id: previewLoader
    root: registry.root
    videoThumbs: videoThumbs
    fileMeta: fileMeta
  }

  PropertiesLoader {
    id: propertiesLoader
    root: registry.root
    selectionOps: selectionOps
  }

  CustomActions {
    id: customActions
    root: registry.root
  }
}
