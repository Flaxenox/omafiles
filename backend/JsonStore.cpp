#include "JsonStore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QQmlEngine>
#include <QSaveFile>

JsonStore::JsonStore(QObject *parent) : QObject(parent) {}

void JsonStore::read(const QString &path) {
  // The whole operation is deferred to the next event loop cycle
  // (QueuedConnection): read() returns immediately and the loaded() handler
  // runs after the call, preserving the async semantics that the
  // ProcessRunner (QProcess) it replaces had. Reading a state file
  // (a few KB) is negligible, it does not need a separate thread.
  QMetaObject::invokeMethod(
      this,
      [this, path]() {
        QQmlEngine *engine = qmlEngine(this);
        // Native undefined for the failure paths (nonexistent file or
        // invalid JSON) -> Array.isArray(undefined) is false, and
        // Persistence normalizes it to null, just as the throwing JSON.parse
        // gave parsed=null.
        const QJSValue undefined =
            engine ? engine->toScriptValue(QVariant()) : QJSValue();

        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
          emit loaded(path, undefined, false);
          return;
        }

        const QByteArray raw = file.readAll();
        file.close();

        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
        if (err.error != QJsonParseError::NoError || doc.isNull()) {
          emit loaded(path, undefined, false);
          return;
        }

        // Deliver a NATIVE JS Array/Object. QJsonDocument already validated and
        // parsed (above), but exposing its QVariant to QML gives the QV4
        // sequence wrapper, on which Array.isArray() returns false
        // (even though instanceof Array is true) -- and Persistence uses
        // Array.isArray(parsed) just like with the original JSON.parse. To
        // return EXACTLY what that JSON.parse gave, the engine itself is let
        // to parse the JSON (already validated, re-serialized
        // compact): it produces a genuine Array/Object, not a wrapper.
        const QByteArray compact = doc.toJson(QJsonDocument::Compact);
        QJSValue jsonParse =
            engine->globalObject().property("JSON").property("parse");
        emit loaded(path, jsonParse.call({QString::fromUtf8(compact)}), true);
      },
      Qt::QueuedConnection);
}

bool JsonStore::write(const QString &path, const QVariant &data) {
  // Create ~/.local/state/omafiles/ (or whatever dir) if it does not exist yet
  // -- what the "mkdir -p --" of the previous bash did.
  const QFileInfo info(path);
  const QDir dir = info.absoluteDir();
  if (!dir.exists() && !dir.mkpath(QStringLiteral("."))) {
    emit saved(path, false);
    return false;
  }

  // QSaveFile writes to a temporary and renames on commit(): the write
  // is atomic, a half-written session.json is never seen even if the process
  // dies during the write.
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly)) {
    emit saved(path, false);
    return false;
  }

  // An object/array created in QML arrives as a QJSValue wrapped in the
  // QVariant; QJsonDocument::fromVariant does not understand it (it would give
  // an empty document, a 0-byte file). It is unwrapped to
  // QVariantMap/QVariantList before serializing. If it already comes as a
  // "pure" QVariant (e.g. from C++), toVariant() is not applied and it is used
  // as is.
  QVariant value = data;
  if (value.canConvert<QJSValue>())
    value = value.value<QJSValue>().toVariant();

  const QJsonDocument doc = QJsonDocument::fromVariant(value);
  // Compact: same space-free format that JSON.stringify produced. The
  // file is only read by this same store, so the format is internal.
  file.write(doc.toJson(QJsonDocument::Compact));

  const bool ok = file.commit();
  emit saved(path, ok);
  return ok;
}
