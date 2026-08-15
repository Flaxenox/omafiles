# OmaFiles — Trash Undo Path Resolution Failure Investigation & Fix

**Component:** Native Trash & Restore (`backend/FileOperations.cpp`)  
**Status:** Fixed, Verified & Tested Live  
**Selfcheck:** 82 passed, 0 failed, 82 total  

---

## 1. Root Cause Analysis

### Reproduction Scenario
A file in `/home/josema/Descargas/github-recovery-codes.txt` was moved to Trash.
When pressing `Ctrl+Z` (Undo), the UI reported:
`"Action failed: no matching trashed item for /home/josema/Descargas/github-recovery-codes.txt"`

### Underlying Cause
1. In Linux/Unix setups, user directories (such as `~/Descargas`) are frequently symlinked to another storage partition or drive (e.g. `/home/josema/Descargas -> /mnt/Almacen/Descargas`).
2. When deleting a file on an external/secondary mount, the FreeDesktop XDG Trash specification mandates trashing to that volume's top-level trash directory (e.g. `/mnt/Almacen/.Trash-1000/`).
3. In such top-level disk trashes, the `Path=` key inside `.trashinfo` is written as a path relative to the mount point (e.g. `Path=Descargas/github-recovery-codes.txt`).
4. `FileOperations::restoreByOrigPath` resolved `Path=` against the mount root (`/mnt/Almacen`), yielding `/mnt/Almacen/Descargas/github-recovery-codes.txt`.
5. However, `DeleteOps.qml` recorded `origPaths` as `/home/josema/Descargas/github-recovery-codes.txt`.
6. When `restoreByOrigPath` evaluated `if (decoded != origPath)`, it compared the canonical physical mount path against the symlinked logical path:
   `"/mnt/Almacen/Descargas/github-recovery-codes.txt" != "/home/josema/Descargas/github-recovery-codes.txt"`
7. Because of strict string inequality, no matching `.trashinfo` entry was found.

---

## 2. Exact Code Path & Fix

**File:** [`backend/FileOperations.cpp`](file:///home/josema/Projects/omafiles/backend/FileOperations.cpp)  
**Functions:** `canonicalPathForFile()`, `FileOperations::restoreByOrigPath()`

### Helper: `canonicalPathForFile()`
Handles resolving canonical paths even when the target file itself has been deleted (resolving symlinks across existing parent directories up the hierarchy):
```cpp
QString canonicalPathForFile(const QString &path) {
  const QFileInfo fi(path);
  const QString canonical = fi.canonicalFilePath();
  if (!canonical.isEmpty())
    return canonical;
  const QDir parentDir(fi.absolutePath());
  const QString parentCanonical = parentDir.canonicalPath();
  if (!parentCanonical.isEmpty())
    return parentCanonical + QLatin1Char('/') + fi.fileName();
  return QDir::cleanPath(path);
}
```

### Matching Logic in `restoreByOrigPath()`:
```cpp
const bool matches = (decoded == origPath) ||
                     (QDir::cleanPath(decoded) == origClean) ||
                     (canonicalPathForFile(decoded) == origCanonical);
if (!matches)
  continue;
```

---

## 3. Verification & Test Matrix

1. **Trash from Symlinked Directory (`Descargas -> /mnt/Almacen/Descargas`)**:
   - Live test executed on real `/home/josema/Descargas/github-recovery-codes-test.txt`.
   - Result: File restored to original location instantly via atomic rename.
2. **Dedicated Automated SelfCheck**:
   - Added test `"Trash + restore from symlinked directory (path normalization)"` in [`src/selfcheck/checks/CheckFilesystemTrash.qml`](file:///home/josema/Projects/omafiles/src/selfcheck/checks/CheckFilesystemTrash.qml).
   - Automated suite: 82/82 PASS.
3. **Duplicate Filenames & Collision Resolution**:
   - `lastModified` timestamp ordering selects the most recent `.trashinfo` entry.
4. **Unicode Filenames**:
   - UTF-8 percent-decoding handles all multi-byte characters and special symbols.
