pragma Singleton
import QtQuick

// Trash metadata ({ "<name>": { origPath, epoch } }, read
// from ~/.local/share/Trash/info/*.trashinfo by trash-info.sh) --
// nineteenth singleton of the state/ layer. SHARED on purpose between
// the active panel and all the background ones (any of them can request
// trash-info.sh, and the result serves them all equally) -- see the
// long comment in logic/FileMeta.qml about why it is NOT cleared on
// leaving the trash (the culprit of the real flicker caught on
// 2026-08-05, see [[project_omafiles_componentization_refactor]]). Before
// this migration it travelled as root.trashInfo/hostRoot.trashInfo by
// explicit prop-drilling -- exactly the kind of state that motivated
// the state/ layer in the first place.
QtObject {
  property var trashInfo: ({})
}
