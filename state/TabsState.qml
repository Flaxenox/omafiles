pragma Singleton
import QtQuick
import "../services"

// Pestañas (cada una un panel visible, lado a lado) + historial
// atrás/adelante de la pestaña ACTIVA -- vigesimoprimer y último
// singleton de la capa state/. El más central de todos: currentPath/
// _goToPath/refresh (que sí se quedan en Omafiles.qml, demasiado
// centrales para mover) leen/escriben esto constantemente. Los valores
// iniciales son solo un placeholder -- open() los reescribe siempre
// antes de que el usuario vea nada (con el payload real, o restaurando
// la sesión anterior vía Persistence.loadSession()).
QtObject {
  readonly property string _initialHome: Env.get("HOME")
  property var tabs: [{ path: _initialHome, history: [_initialHome], historyIndex: 0 }]
  property int activeTabIndex: 0
  // Historial atrás/adelante de la pestaña ACTIVA -- cada pestaña guarda
  // el suyo propio en su objeto (campos history/historyIndex de arriba)
  // y este par de properties es solo la "vista en curso" de esa
  // pestaña, que se intercambia al cambiar de pestaña (ver
  // switchToTab/newTab/etc. en logic/TabOps.qml).
  property var navHistory: [_initialHome]
  property int navHistoryIndex: 0
}
