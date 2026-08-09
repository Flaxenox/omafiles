#pragma once

#include <QJSValue>
#include <QObject>
#include <QString>
#include <QVariant>
#include <qqmlregistration.h>

// Backend C++ de la persistencia JSON de Omafiles (Fase 6.A, josema).
// Sustituye al patron de leer con "cat" (un fork por fichero) y escribir
// con "bash -c 'mkdir -p ... && printf > ...'" (otro fork) que tenia
// logic/Persistence.qml. Ver BACKEND_DESIGN.md 5.2.
//
// Gana tres cosas sobre el enfoque shell:
//   - sin forks: QFile/QJsonDocument hacen la syscall directa;
//   - parseo en C++ (QJsonDocument), no JSON.parse en el hilo de UI;
//   - escritura ATOMICA (QSaveFile: fichero temporal + rename), que el
//     printf por redireccion no garantizaba -- un corte a mitad de
//     saveSession() podia dejar session.json truncado.
//
// Singleton QML (Omafiles.Backend.JsonStore): sin estado por fichero, una
// instancia enruta todas las lecturas/escrituras. Lo consume el adaptador
// services/JsonStore.qml; logic/ no lo importa directamente (regla 8).
class JsonStore : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit JsonStore(QObject *parent = nullptr);

  // Lee y parsea `path` de forma ASINCRONA: vuelve al instante y entrega
  // el resultado por la senal loaded() en el siguiente ciclo del event
  // loop. La asincronia es un contrato: logic/ cuenta con que loadSession
  // dispara refresh()/startDirWatch DESPUES de volver de la llamada (ver
  // core/OmafilesContent.qml open()). Fichero inexistente o JSON invalido
  // -> loaded(path, undefined, false), igual que antes un `cat` fallido +
  // JSON.parse que lanzaba daban parsed=null.
  Q_INVOKABLE void read(const QString &path);

  // Escribe `data` como JSON en `path` de forma ATOMICA (QSaveFile),
  // creando los directorios intermedios si hacen falta. Sincrona: es una
  // escritura pequena y los llamadores actuales son fire-and-forget (no
  // esperaban al fork Detached). Devuelve si se pudo guardar y ademas
  // emite saved() para quien quiera enterarse.
  Q_INVOKABLE bool write(const QString &path, const QVariant &data);

signals:
  // Resultado de read(). `data` es el JSON parseado como valor JS NATIVO
  // (QJSValue construido en el motor), o undefined si ok es false. Se usa
  // QJSValue en vez de QVariant a proposito: un QVariant(QVariantList)
  // expuesto a QML llega como wrapper de secuencia, sobre el que
  // Array.isArray() da false; QJSValue entrega un Array nativo, que es lo
  // que daba el JSON.parse original y lo que Array.isArray espera.
  void loaded(const QString &path, const QJSValue &data, bool ok);
  // Resultado de write().
  void saved(const QString &path, bool ok);
};
