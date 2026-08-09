#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Backend C++ de services/Notifier.qml (Fase 5.C, josema). Notificaciones
// de escritorio -- hoy lanza "notify-send" como proceso desatendido, la
// MISMA forma que la implementacion Quickshell sobre
// Quickshell.execDetached(). Ver services/Notifier.qml para el contrato y
// el porque de centralizar aqui el titulo "Omafiles".
//
// Nota de diseno (BACKEND_DESIGN.md 5.1): la forma idiomatica seria
// org.freedesktop.Notifications por QDBus (sin fork, con IDs de
// notificacion). Se deja como notify-send en 5.C para no introducir
// cambios de comportamiento; la migracion a QDBus es trabajo posterior.
//
// Singleton QML (Omafiles.Backend.Notifier): sin estado, se consume como
// Notifier.notify("texto").
class Notifier : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Notifier(QObject *parent = nullptr);

  // Muestra una notificacion de escritorio con el titulo fijo "Omafiles"
  // y `text` como cuerpo.
  Q_INVOKABLE void notify(const QString &text);
};
