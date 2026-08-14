pragma Singleton
import QtQuick

// Current sort criterion (name/size/date/type, asc/desc) --
// thirteenth singleton of the state/ layer, completes the migration of
// logic/SortOps.qml (its logic was already extracted; this was the only
// state it manipulated and that still lived in core).
QtObject {
  property string sortKey: "name"
  property bool sortDesc: false

  // Available sort keys and their labels (Phase 14.B, josema, closes
  // O2/O3 of the revalidation): they were readonly constants of OmafilesContent
  // (sortKeys/sortKeyLabels) read by logic/SortOps. Pure sort
  // configuration -- their natural place is next to sortKey/sortDesc.
  readonly property var sortKeys: ["name", "size", "mtime", "type"]
  readonly property var sortKeyLabels: ({ name: "Name", size: "Size", mtime: "Date", type: "Type" })
}
