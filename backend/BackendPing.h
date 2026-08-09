#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Tipo de prueba del spike de empaquetado (Fase 5.B, josema). Su unico
// proposito es verificar que un modulo QML con plugin C++
// (Omafiles.Backend) se puede cargar desde un import path externo -- por
// el frontend Qt6 standalone Y por Quickshell, compartiendo el mismo
// .so. No forma parte del backend real; se retira en cuanto 5.B queda
// validado y los servicios reales cargan por el mismo mecanismo.
//
// Singleton para poder leerlo como BackendPing.message sin instanciarlo.
class BackendPing : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  Q_PROPERTY(QString message READ message CONSTANT)

public:
  explicit BackendPing(QObject *parent = nullptr);

  QString message() const { return QStringLiteral("backend-ok"); }
};
