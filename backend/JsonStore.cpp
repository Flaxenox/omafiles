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
  // Toda la operacion se difiere al siguiente ciclo del event loop
  // (QueuedConnection): read() vuelve al instante y el handler de loaded()
  // corre despues de la llamada, preservando la semantica async que tenia
  // el ProcessRunner (QProcess) al que sustituye. Leer un fichero de
  // estado (pocos KB) es despreciable, no necesita hilo aparte.
  QMetaObject::invokeMethod(
      this,
      [this, path]() {
        QQmlEngine *engine = qmlEngine(this);
        // undefined nativo para los caminos de fallo (fichero inexistente o
        // JSON invalido) -> Array.isArray(undefined) es false, y
        // Persistence lo normaliza a null, igual que el JSON.parse que
        // lanzaba daba parsed=null.
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

        // Entregar un Array/Object JS NATIVO. QJsonDocument ya valido y
        // parseo (arriba), pero exponer su QVariant a QML da el wrapper de
        // secuencia de QV4, sobre el que Array.isArray() devuelve false
        // (aunque instanceof Array sea true) -- y Persistence usa
        // Array.isArray(parsed) igual que con el JSON.parse original. Para
        // devolver EXACTAMENTE lo que daba aquel JSON.parse, se deja que el
        // propio motor parsee el JSON (ya validado, re-serializado
        // compacto): produce un Array/Object genuino, no un wrapper.
        const QByteArray compact = doc.toJson(QJsonDocument::Compact);
        QJSValue jsonParse =
            engine->globalObject().property("JSON").property("parse");
        emit loaded(path, jsonParse.call({QString::fromUtf8(compact)}), true);
      },
      Qt::QueuedConnection);
}

bool JsonStore::write(const QString &path, const QVariant &data) {
  // Crear ~/.local/state/omafiles/ (o el dir que sea) si aun no existe --
  // lo que hacia el "mkdir -p --" del bash anterior.
  const QFileInfo info(path);
  const QDir dir = info.absoluteDir();
  if (!dir.exists() && !dir.mkpath(QStringLiteral("."))) {
    emit saved(path, false);
    return false;
  }

  // QSaveFile escribe a un temporal y renombra en commit(): la escritura
  // es atomica, nunca se ve un session.json a medias aunque el proceso
  // muera durante la escritura.
  QSaveFile file(path);
  if (!file.open(QIODevice::WriteOnly)) {
    emit saved(path, false);
    return false;
  }

  // Un objeto/array creado en QML llega como QJSValue envuelto en el
  // QVariant; QJsonDocument::fromVariant no lo entiende (daria un documento
  // vacio, fichero de 0 bytes). Se desenvuelve a QVariantMap/QVariantList
  // antes de serializar. Si ya viene como QVariant "puro" (p.ej. desde
  // C++), toVariant() no se aplica y se usa tal cual.
  QVariant value = data;
  if (value.canConvert<QJSValue>())
    value = value.value<QJSValue>().toVariant();

  const QJsonDocument doc = QJsonDocument::fromVariant(value);
  // Compact: mismo formato sin espacios que producia JSON.stringify. El
  // fichero solo lo lee este mismo store, asi que el formato es interno.
  file.write(doc.toJson(QJsonDocument::Compact));

  const bool ok = file.commit();
  emit saved(path, ok);
  return ok;
}
