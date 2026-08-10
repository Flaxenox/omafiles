#pragma once

#include <QObject>
#include <QTimer>
#include <qqmlregistration.h>

// Watcher reactivo de UDisks2 (Fase 20, josema). Sustituye el polling de 7 s
// de la barra lateral por una suscripción D-Bus a las señales del bus de
// SISTEMA de org.freedesktop.UDisks2. Cuando UDisks2 notifica CUALQUIER
// cambio de dispositivo de bloque -- conectar/expulsar un USB, montar/
// desmontar una ISO, conectar/desmontar un disco externo, cambio de label o
// de estado de montaje -- emite devicesChanged(), COALESCIDA con un QTimer
// para que una ráfaga de señales dispare un único refresco.
//
// Deliberadamente NO enumera dispositivos ni construye objetos de montaje:
// la única fuente de verdad sigue siendo list-mounts.sh (findmnt+lsblk, un
// "system adapter" que BACKEND_DESIGN.md mantiene a propósito). Este watcher
// solo avisa de "algo cambió, vuelve a listar", así que no hay una segunda
// fuente que pueda desincronizarse. Sin polling. Sin dependencia de
// Quickshell (singleton QML, igual que el resto de backend/).
class UDisksWatcher : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit UDisksWatcher(QObject *parent = nullptr);

  // true si se pudo conectar al bus de sistema y registrar las suscripciones.
  // Si no (p.ej. CI headless sin bus de sistema), el watcher queda inerte sin
  // fallar: la app sigue refrescando por eventos internos y al abrir.
  Q_INVOKABLE bool available() const;

signals:
  // Emitida (coalescida) ante cualquier cambio de dispositivo de bloque en
  // UDisks2. El frontend responde volviendo a listar (refreshMounts()).
  void devicesChanged();

private slots:
  // Un único punto para las tres señales D-Bus: (re)arranca el coalescedor.
  void schedule();

private:
  bool m_available = false;
  QTimer m_coalesce;
};
