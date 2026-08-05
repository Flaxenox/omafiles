import QtQuick

// Catcher del lazo de selección (pulsar+arrastrar dibuja un rectángulo de
// selección, como Nautilus/cualquier gestor de iconos) -- el mismo bloque
// de 4 handlers estaba repetido 4 veces antes de esta extracción (hueco
// de arriba de la ListView, footer/hueco de abajo, y los dos gutters
// izquierdo/derecho de cada fila en FileListRow.qml). Encontrado
// auditando Omafiles.qml contra la regla 4 del prompt de arquitectura
// ("evita duplicación de código incluso si implica crear un componente
// nuevo").
//
// Nombres de properties SIN prefijo `host` a propósito, pero elegidos
// para no coincidir con ningún id/property de los ficheros que lo
// instancian (`listView`/`selectionOps` en panels/ActiveFileList.qml,
// `hostListView`/`hostSelectionOps` en panels/FileListRow.qml) -- si
// coincidieran con cualquiera de los dos, QML autoenlazaría la property
// consigo misma en vez de al valor pasado (ver
// [[project_omafiles_architecture_rules]], mismo bug que
// BackgroundPanel.qml/KeyboardShortcuts.qml).
MouseArea {
  property Item catcherListView: null
  property Item catcherSelectionOps: null

  acceptedButtons: Qt.LeftButton
  onPressed: function (mouse) {
    var p = mapToItem(catcherListView.contentItem, mouse.x, mouse.y)
    var vp = mapToItem(catcherListView, mouse.x, mouse.y)
    catcherSelectionOps.startMarquee(p.x, p.y, vp.y, (mouse.modifiers & Qt.ControlModifier) !== 0)
  }
  onPositionChanged: function (mouse) {
    var p = mapToItem(catcherListView.contentItem, mouse.x, mouse.y)
    var vp = mapToItem(catcherListView, mouse.x, mouse.y)
    catcherSelectionOps.moveMarquee(p.x, p.y, vp.y)
  }
  onReleased: catcherSelectionOps.endMarquee()
  onCanceled: catcherSelectionOps.endMarquee()
}
