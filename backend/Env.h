#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Backend C++ de services/Env.qml (Fase 5, josema). Da acceso REAL a
// variables de entorno via qEnvironmentVariable -- QML no las expone de
// forma nativa (por eso Quickshell.env() existe del lado Quickshell, y
// por eso Fase 4 tuvo que inyectar HOME como context property). Con esto
// desaparece ese truco: el standalone lee el entorno directamente.
//
// Singleton QML (Omafiles.Backend.Env): no tiene estado, una sola
// instancia basta y se consume como Env.get("HOME").
class Env : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Env(QObject *parent = nullptr);

  // Valor de la variable `name`, o "" si no existe (mismo contrato que la
  // version Quickshell sobre Quickshell.env()).
  Q_INVOKABLE QString get(const QString &name) const;
};
