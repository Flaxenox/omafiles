pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Watcher reactivo de dispositivos -- adaptador fino sobre el singleton C++
// Omafiles.Backend.UDisksWatcher (suscripción D-Bus a org.freedesktop.UDisks2,
// ver backend/UDisksWatcher.cpp). Fase 20 (josema): sustituto reactivo del
// polling de 7 s. Como el contrato es una SEÑAL (no una función), este
// adaptador la reemite para que logic/core no importen Omafiles.Backend
// (regla 8), igual que JsonStore reemite loaded/saved.
QtObject {
  id: root

  // Reemitida cuando UDisks2 notifica cualquier cambio de dispositivo de
  // bloque. El frontend responde con refreshMounts().
  signal devicesChanged()

  function available() { return Backend.UDisksWatcher.available() }

  property Connections _c: Connections {
    target: Backend.UDisksWatcher
    function onDevicesChanged() { root.devicesChanged() }
  }
}
