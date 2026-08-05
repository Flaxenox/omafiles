pragma Singleton
import QtQuick
import Quickshell

// Notificaciones de escritorio -- hoy vía Quickshell.execDetached() con
// "notify-send", pero es el ÚNICO sitio que construye ese comando (Fase
// 1.5, ver [[project_omafiles_standalone_prep]]). Antes de esto, cada
// uno de los 16+ sitios de llamada montaba
// Quickshell.execDetached(["notify-send", "Omafiles", texto]) a mano,
// con "Omafiles" repetido cada vez. Standalone puede cambiar notify()
// (a QSystemTrayIcon::showMessage, org.freedesktop.Notifications por
// D-Bus directo, etc.) sin tocar ningún sitio de llamada.
QtObject {
  function notify(text) {
    Quickshell.execDetached(["notify-send", "Omafiles", text])
  }
}
