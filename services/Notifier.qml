pragma Singleton
import QtQuick
import Omafiles.Backend as Backend

// Notificaciones de escritorio -- adaptador fino sobre el singleton C++
// Omafiles.Backend.Notifier (notify-send desatendido, titulo "Omafiles"
// centralizado en C++, ver backend/Notifier.cpp).
//
// Fase 5.C (josema): implementacion UNICA para los dos frontends. Antes
// esto montaba Quickshell.execDetached(["notify-send", ...]) y el
// standalone tenia un stub que solo imprimia por consola; ahora ambos
// usan el mismo backend C++ y el stub desaparece. Cada uno de los 16+
// sitios de llamada sigue haciendo Notifier.notify(texto) sin enterarse
// (antes de centralizar esto, cada sitio repetia "Omafiles" a mano).
QtObject {
  function notify(text) { Backend.Notifier.notify(text) }
}
