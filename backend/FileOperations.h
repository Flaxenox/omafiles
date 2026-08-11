#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

// C++ backend for file operations (Phase 7, josema). Native replacement
// for the shell commands (cp/mv/rm/mkdir/gio trash/...) that today
// ActionEngine.runAction builds and executes. See BACKEND_DESIGN.md 5.3 (FileOps).
//
// Phase 7 INTRODUCES and validates it; for now only "new folder" (mkdir) is
// wired live. The rest of the consumers (copy/move/delete/trash,
// with their undo/conflict/progress over shell) migrate in a later
// step -- that engine is the most delicate code (destructive + undo).
//
// Async API: each operation returns immediately, runs on a thread of the
// QThreadPool and delivers the result by signal on the UI thread. Three
// signals: progress (only for large copies/moves), finished (success) and
// error (failure). The `op` identifies the operation ("copy", "move", ...) and
// `path` its main path, so the consumer can correlate.
//
// No dependency on Quickshell: only public Qt. The refresh after an
// operation is NOT triggered by this type -- it is done by DirectoryModel's
// QFileSystemWatcher (Phase 6.D) when the directory changes. The integration
// with Notifier lives in the QML adapter (services/FileOperations.qml), which
// re-emits these signals and warns on errors.
class FileOperations : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit FileOperations(QObject *parent = nullptr);
  ~FileOperations() override;

  // Copies `source` to `destination` (the FULL destination path, including the
  // final name). Recursive if source is a folder (preserves symlinks as
  // symlinks and each file's mode). Emits progress during the copy.
  // If destination exists: with overwrite=true it REPLACES it (deletes and copies);
  // with overwrite=false, error. Phase 13.A (josema): overwrite adds the
  // equivalent of `cp -f`; without it it was `cp -n`.
  Q_INVOKABLE void copy(const QString &source, const QString &destination,
                        bool overwrite = false);

  // Cancels the operation in progress (long copy) cooperatively: the
  // worker checks the flag between chunks and aborts with error "cancelled".
  // Phase 13.A. The consumer (ActionEngine) cleans up the partial destination.
  Q_INVOKABLE void cancel();

  // NATIVE conflict detection (Phase 13.F): returns the subset of
  // `paths` that ALREADY EXIST on disk. lstat criterion (entryExists): counts a
  // file, folder or symlink -- including a BROKEN symlink -- like the
  // no-overwrite guards of copy/move (BUG-01, Hardening-1). Synchronous (only
  // lstat): fast even for large selections. Used by paste/drop and the
  // conflict checks of ConflictActions to decide whether to open the
  // dialog; the RESOLUTION (overwrite/skip) is already executed by copy/move.
  Q_INVOKABLE QStringList existingPaths(const QStringList &paths) const;

  // Total size (recursive, in bytes) of a set of paths. Native, for
  // the copy/move progress percentage without `du` (Phase 13.G) and for the
  // size of a multiple selection in Properties without building a gigantic
  // `du -shc` line (BUG-03, Hardening-2). Synchronous (walks the tree).
  Q_INVOKABLE qint64 totalSize(const QStringList &paths) const;

  // Octal mode (%a: mode & 07777, no leading zero) of each path, in the
  // SAME order as `paths`; "" if the stat fails. Native, to prefill the
  // chmod dialog of a multiple selection without building a gigantic
  // `stat -c%a -- ...` line that would blow up ARG_MAX (BUG-03, Hardening-2).
  // Follows symlinks, just as `stat -c%a` did. Synchronous.
  Q_INVOKABLE QStringList octalModes(const QStringList &paths) const;

  // Moves `source` to `destination` (the FULL destination path). Tries an
  // atomic rename (same filesystem); if it crosses disks, copies +
  // deletes the source (with progress, cancelable). If destination exists: with
  // overwrite=true it REPLACES it (deletes and moves, = `mv -f`); with
  // overwrite=false, error. Phase 13.B (josema).
  Q_INVOKABLE void move(const QString &source, const QString &destination,
                        bool overwrite = false);

  // Renames `path` to `newName` (same directory). Does not overwrite.
  Q_INVOKABLE void rename(const QString &path, const QString &newName);

  // Deletes `path` PERMANENTLY (recursive if it is a folder; symlinks are
  // deleted as a link, without following the target). No trash, no undo --
  // for that use trash(). Cooperative cancellation. With ignoreMissing=true (=
  // `rm -f`) it is NOT an error that `path` does not exist. Phase 13.C (josema).
  Q_INVOKABLE void remove(const QString &path, bool ignoreMissing = false);

  // Creates the folder `path` (and the missing parents, like mkdir -p).
  Q_INVOKABLE void mkdir(const QString &path);

  // Sends `path` to the XDG trash (QFile::moveToTrash, creates the standard
  // .trashinfo; on other disks it uses their .Trash-$UID as the spec mandates).
  Q_INVOKABLE void trash(const QString &path);

  // Restores from the trash the file `path` (inside <root>/files/):
  // reads its <root>/info/<name>.trashinfo, moves it back to its original
  // path (Path=, percent-decoded) and deletes the .trashinfo.
  Q_INVOKABLE void restore(const QString &path);

  // Restores a trash item IDENTIFIED BY ITS ORIGINAL PATH (not by the
  // name inside files/, which may carry a suffix if there was a collision).
  // Native replica of restore-by-origpath.sh (Phase 13.E): it searches ALL the
  // active XDG roots (home trash + .Trash-$uid of other mounts) for the
  // .trashinfo whose Path= (percent-decoded; relative to the mount point in
  // disk trashes) matches `origPath`, uses the most recent, moves
  // files/<name> back to origPath (atomic rename + cross-fs fallback) and
  // deletes the .trashinfo. Emits finished("restore", origPath) / error.
  Q_INVOKABLE void restoreByOrigPath(const QString &origPath);

  // Active XDG trash roots (Phase 16): the home one (~/.local/share/
  // Trash) plus the .Trash-$uid of any other mount point. Native
  // replacement for trash-roots.sh; the Trash view lists "<root>/files" of each
  // one with DirectoryModel.listMany. Synchronous (only stat over the mounts).
  Q_INVOKABLE QStringList trashRoots() const;

  // Metadata of all the .trashinfo of all the roots (Phase 16): native
  // replacement for trash-info.sh. A list of objects {name, origPath, epoch,
  // trashRoot}: `name` = stem of the file in files/, `origPath` = Path=
  // percent-decoded (relative to the resolved mount point in disk
  // trashes), `epoch` = DeletionDate in seconds, `trashRoot` = the physical root
  // that contains that item (to restore/delete in the correct trash).
  // Reuses the same parsing as restoreByOrigPath. Synchronous.
  Q_INVOKABLE QVariantList trashInfo() const;

signals:
  // Progress by BYTES of a copy/move in progress (Phase 13.G): `done`
  // = bytes copied of the current item, `total` = size of the item. The
  // consumer (ActionEngine) aggregates over the batch. It was a percentage before.
  void progress(const QString &op, const QString &path, qint64 done,
                qint64 total);
  // The operation finished successfully.
  void finished(const QString &op, const QString &path);
  // The operation failed; `message` describes the reason.
  void error(const QString &op, const QString &path, const QString &message);

private:
  struct Result {
    bool ok = false;
    QString message;
  };

  // Launches `job` on the pool and emits finished/error according to its Result, on the
  // UI thread. `op`/`path` for the signals.
  void run(const QString &op, const QString &path, std::function<Result()> job);
  // Emits progress(op, path, done, total) safely from the worker.
  void emitProgress(const QString &op, const QString &path, qint64 done,
                    qint64 total);

  // Cooperative cancellation flag (see cancel()/copy()). Atomic because it is
  // written by the UI thread and read by the pool worker.
  std::atomic<bool> m_cancelled{false};

  // Life guard against the dangling `this` (same pattern as
  // DirectoryModel, Phase 10.A): a pool worker that finishes AFTER the
  // singleton is destroyed (e.g. closing the app mid-copy)
  // would invokeMethod on dead memory -> crash. The worker checks
  // `alive` under the mutex before delivering; the destructor sets it to false
  // under the same mutex. Phase 13.B.
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();
};
