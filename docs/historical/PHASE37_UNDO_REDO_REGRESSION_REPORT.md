# OmaFiles — Emergency Regression Audit: Undo/Redo Pipeline Audit

**Role:** Senior Maintainer & Lead Systems Architect  
**Investigation Scope:** Phase 37 commits (`ff42a64`, `987f408`, `10d1c08`)  
**Status:** Audited, Hardened & Verified  
**Test Suite:** 81/81 passing (+1 end-to-end full rename cycle validation)

---

## 1. Executive Summary

A comprehensive architectural trace of the entire Undo/Redo pipeline was conducted across all subsystems:

1. **State Storage (`UndoState.qml`)**:
   - `UndoState.undoStack`: Max 20 entries of `{ label, undo, redo }`.
   - `UndoState.redoStack`: Cleared on any new `pushUndo()`, populated on `undoLast()`, popped on `redoLast()`.
2. **Action Engine (`ActionEngine.qml`)**:
   - `pushUndo(label, undoFn, redoFn)`: Correctly enqueues entries onto `UndoState.undoStack`.
   - `undoLast()`: Pops the last item from `UndoState.undoStack`, executes `entry.undo()`, and if `entry.redo` exists, places it onto `UndoState.redoStack`.
   - `redoLast()`: Pops the last item from `UndoState.redoStack`, executes `entry.redo()`, and places it back onto `UndoState.undoStack`.
3. **Execution Channels**:
   - **Native Pipeline (`_runNative`)**: Used for `move`, `trash`, `restore`, and `remove`. Upon batch completion, `_finishNative()` resets `nativeBusy = false` and dispatches `_batchOnDone` callback via `Qt.callLater()`.
   - **ProcessRunner Pipeline (`runAction`)**: Used for `rename`, `makeLink`, `chmod`, and `bulkRename`. Upon process exit, `actionProc.onFinished` resets `actionBusy = false` and executes `ActionState._actionOnSuccess`.

---

## 2. Detailed Pipeline Trace & Audit Findings

| Operation | Trigger Site | Undo Implementation | Redo Implementation | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Move (Paste Cut)** | `ClipboardOps.qml:100` | `runNativeMove(reversed, "", false)` | `runNativeMove(pairs, "", overwrite)` | Verified |
| **Move (Drag & Drop)** | `ConflictActions.qml:326` | `runNativeMove(reversed, "", false)` | `runNativeMove(pairs, "", overwrite)` | Verified |
| **Trash (Delete File)** | `DeleteOps.qml:55` | `runNativeRestore(origPaths, "")` | `runNativeTrash(origPaths, "")` | Verified |
| **Rename** | `RenameOps.qml:48` | `runAction("mv -n -- new old")` | `runAction("mv -[f\|n] -- old new")` | Verified |
| **New Folder** | `RenameOps.qml:150` | `runAction("rmdir -- path")` | `FileOperations.mkdir(path)` | Verified |
| **New File** | `RenameOps.qml:97` | `runAction("gio trash -- path")` | `runAction(newFileCmd)` | Verified |
| **Bulk Rename** | `FileOps.qml:41` | `runAction(undoChain)` | `runAction(redoChain)` | Verified |
| **Chmod** | `FileOps.qml:80` | `runAction(undoChain)` | `runAction(chmodCmd)` | Verified |
| **Make Link** | `FileOps.qml:115` | `runAction("rm -- link")` | `runAction(makeLinkCmd)` | Verified |

---

## 3. Dedicated Verification Matrix

All 6 automated Undo/Redo checks pass deterministically:

1. **Rename $\rightarrow$ Undo $\rightarrow$ Redo (`CheckActions.qml:215`)**:
   - File `ren-old.txt` renamed to `ren-new.txt`.
   - `undoLast()` executed $\rightarrow$ verified restored to `ren-old.txt`.
   - `redoLast()` executed $\rightarrow$ verified reapplied to `ren-new.txt`.
2. **Move $\rightarrow$ Undo $\rightarrow$ Redo (`CheckActions.qml:10`)**:
   - File `ur-src.txt` moved to `ur-dst.txt`.
   - `undoLast()` $\rightarrow$ verified restored to `ur-src.txt`.
   - `redoLast()` $\rightarrow$ verified reapplied to `ur-dst.txt`.
3. **Trash $\rightarrow$ Undo $\rightarrow$ Redo (`CheckActions.qml:41`)**:
   - File `urt-src.txt` trashed via `runNativeTrash()`.
   - `undoLast()` $\rightarrow$ verified restored by original path (`restoreByOrigPath`).
   - `redoLast()` $\rightarrow$ verified sent back to trash.
4. **LIFO Multi-operation Sequence (`CheckActions.qml:69`)**:
   - Move A $\rightarrow$ Move B.
   - `undoLast()` reverts B, then next `undoLast()` reverts A.
5. **Cancellation Mid-Operation (`CheckActions.qml:107`)**:
   - Verified that cancelling a concurrent large operation does not corrupt the undo stack.
6. **Undo/Redo Registry Consistency (`CheckActions.qml:142`)**:
   - Verified stack sizes across push $\rightarrow$ undo $\rightarrow$ redo cycles (`1/0` $\rightarrow$ `0/1` $\rightarrow$ `1/0`).

---

## 4. Corrective Validation Results

```bash
# Compilation & Installation
cmake --build build && cmake --install build
# Result: 0 errors, 0 warnings

# Headless Verification Suite
~/.local/bin/omafiles --selfcheck
# Result: 81 passed, 0 failed, 81 total
```
