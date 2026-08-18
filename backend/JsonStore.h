#pragma once

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QVariant>
#include <qqmlregistration.h>

// C++ backend for Omafiles' JSON persistence.
// Replaces the pattern of reading with "cat" (one fork per file) and writing
// with "bash -c 'mkdir -p ... && printf > ...'" (another fork) that
// logic/Persistence.qml used. See BACKEND_DESIGN.md.
//
// Three gains over the shell approach:
//   - no forks: QFile/QJsonDocument do the syscall directly;
//   - parsing in C++ (QJsonDocument), not JSON.parse on the UI thread;
//   - ATOMIC write (QSaveFile: temporary file + rename), which
//     printf-by-redirection did not guarantee -- a cut in the middle of
//     saveSession() could leave session.json truncated.
//
// QML singleton (Omafiles.Backend.JsonStore): no per-file state, one
// instance routes all reads/writes. It is consumed by the adapter
// Single delivery point for JSON state files.
class JsonStore : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit JsonStore(QObject *parent = nullptr);

  // Reads and parses `path` ASYNCHRONOUSLY: returns immediately and delivers
  // the result via the loaded() signal on the next event loop cycle. The
  // asynchrony is a contract: logic/ relies on loadSession firing
  // refresh()/startDirWatch AFTER the call returns (see
  // core/OmafilesContent.qml open()). Nonexistent file or invalid JSON
  // -> loaded(path, undefined, false), just as before a failed `cat` +
  // a throwing JSON.parse gave parsed=null.
  Q_INVOKABLE void read(const QString &path);

  // Writes `data` as JSON to `path` ATOMICALLY (QSaveFile),
  // creating the intermediate directories if needed. Synchronous: it is a
  // small write and the current callers are fire-and-forget (they did not
  // wait for the Detached fork). Returns whether it could be saved and also
  // emits saved() for whoever wants to be notified.
  Q_INVOKABLE bool write(const QString &path, const QVariant &data);

signals:
  // Result of read(). `data` is the parsed JSON as a NATIVE JS value
  // (QJSValue built in the engine), or undefined if ok is false. QJSValue is
  // used instead of QVariant on purpose: a QVariant(QVariantList)
  // exposed to QML arrives as a sequence wrapper, on which
  // Array.isArray() returns false; QJSValue delivers a native Array, which is
  // what the original JSON.parse gave and what Array.isArray expects.
  void loaded(const QString &path, const QJSValue &data, bool ok);
  // Result of write().
  void saved(const QString &path, bool ok);
};
