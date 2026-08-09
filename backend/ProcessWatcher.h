#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// Backend C++ de services/ProcessWatcher.qml (Fase 5, josema). Respalda
// con QProcess la MISMA API que la implementacion Quickshell sobre
// Quickshell.Io.Process + SplitParser -- ver services/ProcessWatcher.qml
// para el contrato. A diferencia de ProcessRunner, vigila un proceso que
// NO termina solo (inotifywait -m): emite lineRead por cada linea de
// stdout en vez de un resultado final. Se registra como tipo QML
// Omafiles.Backend.ProcessWatcher y lo consume el adaptador
// services/+standalone/ProcessWatcher.qml.
class ProcessWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true mientras el proceso vigilado sigue vivo.
  Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
  explicit ProcessWatcher(QObject *parent = nullptr);

  bool active() const;

  // Lanza `args` (programa + argumentos) en modo monitor. Si ya habia uno
  // en marcha lo reinicia (mismo comportamiento que la version Quickshell,
  // que ponia running=false antes de relanzar).
  Q_INVOKABLE void start(const QVariantList &args);

  // Para el proceso vigilado. No-op si no hay nada corriendo.
  Q_INVOKABLE void stop();

signals:
  void activeChanged();
  // Una linea de salida del proceso vigilado (sin el salto final). El
  // contenido suele dar igual -- basta con SABER que algo cambio.
  void lineRead(const QString &line);

private:
  void drainLines();

  QProcess *m_proc;
  QString m_buf; // resto sin terminar en salto de linea entre lecturas
};
