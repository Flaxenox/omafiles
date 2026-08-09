#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// Backend C++ de services/Detached.qml (Fase 5.C, josema). Ejecucion
// "dispara y olvida" de un proceso externo -- sin seguimiento de
// resultado, sin busy/cancel (para eso, Omafiles.Backend.ProcessRunner).
// Respalda con QProcess::startDetached la MISMA API que la implementacion
// Quickshell sobre Quickshell.execDetached() -- ver services/Detached.qml
// para el contrato.
//
// Singleton QML (Omafiles.Backend.Detached): sin estado, se consume como
// Detached.run([...]).
class Detached : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Detached(QObject *parent = nullptr);

  // Lanza `args` (programa + argumentos) desatendido y vuelve al
  // instante. No-op si la lista viene vacia (mismo contrato benigno que
  // Quickshell.execDetached ante una lista sin programa).
  Q_INVOKABLE void run(const QVariantList &args);
};
