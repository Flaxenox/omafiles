# `logic/` dependency graph

Generated from `property Item x: null` wiring between `logic/*.qml`
components (UI element/dialog references excluded — this is
component-to-component only). Verified acyclic 2026-08-05.

```mermaid
graph LR
  ArchiveActions --> SelectionOps
  ArchiveActions --> SortOps
  BookmarkOps --> MountActions
  BookmarkOps --> Persistence
  BookmarkOps --> TabOps
  ClipboardOps --> SelectionOps
  ConflictActions --> ArchiveActions
  ConflictActions --> BookmarkOps
  ConflictActions --> ClipboardOps
  ConflictActions --> FileOps
  ConflictActions --> RenameOps
  ConflictActions --> SelectionOps
  DeleteOps --> SelectionOps
  DragDropOps --> ConflictActions
  DragDropOps --> SelectionOps
  FileOps --> SelectionOps
  KeyboardShortcuts --> ClipboardOps
  KeyboardShortcuts --> ConflictActions
  KeyboardShortcuts --> DeleteOps
  KeyboardShortcuts --> DragDropOps
  KeyboardShortcuts --> FileOps
  KeyboardShortcuts --> MountActions
  KeyboardShortcuts --> PreviewLoader
  KeyboardShortcuts --> RenameOps
  KeyboardShortcuts --> SearchOps
  KeyboardShortcuts --> SelectionOps
  KeyboardShortcuts --> SortOps
  KeyboardShortcuts --> TabOps
  MountActions --> TabOps
  OpenWithOps --> BookmarkOps
  Persistence --> TabOps
  PreviewLoader --> FileMeta
  PreviewLoader --> VideoThumbnails
  PropertiesLoader --> SelectionOps
  SearchOps --> SelectionOps
  SearchOps --> SortOps
  SelectionOps --> PreviewLoader
  TabOps --> ArchiveActions
  TabOps --> PreviewLoader
```

Leaf nodes (no `logic/` dependencies): `ActionEngine`, `FileMeta`,
`FileTypeUtils`, `RenameOps`, `SortOps`, `VideoThumbnails`.

Regenerate by checking, for each `logic/*.qml`:
```
grep -oP 'property Item \K\w+' logic/*.qml
```
then filtering out UI-element/dialog references (anything not itself a
`logic/*.qml` file).
