# OmaFiles — Phase 38: In-Process Native Trash Emptying (`FileOperations.emptyTrash`)

**Author:** Lead Architect & Performance Engineer  
**Status:** Completed & Validated  
**Test Suite:** 80/80 passing

---

## 1. Summary of Changes

Migrated bulk trash emptying from `empty-trash.sh` to native C++ on `QThreadPool` within [`backend/FileOperations.cpp`](file:///home/josema/Projects/omafiles/backend/FileOperations.cpp):

1. **Native C++ Implementation**:
   - `FileOperations::emptyTrash()`: Discovers all active XDG roots via `discoverTrashRoots()` (`$XDG_DATA_HOME/Trash` and `.Trash-$UID` across all mounted storage volumes).
   - Cleans all entries in `<root>/files/` recursively using `removeTree()` with cooperative cancellation support (`m_cancelled`).
   - Cleans all `<root>/info/*.trashinfo` metadata files.
   - Emits standard `finished("emptyTrash", "")` / `error("emptyTrash", "", msg)`.

2. **Frontend Wiring**:
   - Added `ActionEngine.emptyTrash(onDone)` in [`logic/ActionEngine.qml`](file:///home/josema/Projects/omafiles/logic/ActionEngine.qml).
   - Replaced all 3 shell invocations of `empty-trash.sh` in [`core/CommandFacade.qml`](file:///home/josema/Projects/omafiles/core/CommandFacade.qml) (Command Palette, Empty Area context menu, and Trash Bookmark context menu).

3. **Cleanup**:
   - Deleted `empty-trash.sh` from the repository and CMake install manifests.
   - Updated self-check test in [`src/selfcheck/checks/CheckIntegration.qml`](file:///home/josema/Projects/omafiles/src/selfcheck/checks/CheckIntegration.qml) to validate `Backend.FileOperations.emptyTrash()`.
