#pragma once

#include <QObject>
#include <QProcess>
#include <QVariant>
#include <QVariantList>
#include <QString>
#include <qqmlregistration.h>

// Backend C++ de services/ProcessRunner.qml (Fase 5, josema). Respalda
// con QProcess real la MISMA API que la implementacion Quickshell sobre
// Quickshell.Io.Process -- ver services/ProcessRunner.qml para el
// contrato y el porque de cada metodo. Se registra como tipo QML
// Omafiles.Backend.ProcessRunner y lo consume el adaptador
// services/ProcessRunner.qml; el nucleo (logic/) sigue
// escribiendo `ProcessRunner { onFinished: ... }` sin enterarse.
//
// No es visual (QObject, no Item) a proposito: ProcessRunner nunca fue
// un elemento de UI, solo se instanciaba dentro de un Item.
class ProcessRunner : public QObject {
  Q_OBJECT
  QML_ELEMENT

  // true mientras hay una ejecucion en marcha -- para el patron
  // "si ya esta ocupado, avisar y salir" repetido por todo el proyecto.
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
  explicit ProcessRunner(QObject *parent = nullptr);

  bool busy() const { return m_running; }

  // Lanza `args` (programa + argumentos). group=true envuelve el comando
  // en su propio grupo de procesos (via setsid) para que cancel() mate
  // tambien a los hijos reales (cp/mv/zip bajo "bash -c"). Devuelve false
  // sin hacer nada si ya hay algo en marcha.
  Q_INVOKABLE bool start(const QVariantList &args, bool group = false);

  // Mata la ejecucion en marcha (todo su grupo si se lanzo con group).
  // No-op si no hay nada corriendo. finished se sigue disparando (con
  // cancelled:true) cuando el proceso realmente termine.
  Q_INVOKABLE void cancel();

signals:
  void busyChanged();
  // Se dispara siempre al terminar (exito, fallo o cancelada) con el
  // resultado completo: { exitCode, stdout, stderr, cancelled }.
  void finished(const QVariant &result);

private:
  void emitFinished(int exitCode);

  QProcess *m_proc;
  bool m_running = false;
  bool m_cancelled = false;
  bool m_group = false;
  QString m_stdout;
  QString m_stderr;
};
