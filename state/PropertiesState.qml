pragma Singleton
import QtQuick

// Estado del panel de Propiedades (tamaño/permisos/dueño/fecha) --
// noveno singleton de la capa state/. dialogs/PropertiesPanel.qml es
// puramente presentacional (propio `id: root` local, alimentado por
// binding desde Omafiles.qml), así que no necesita importar esto
// directamente. La carga en sí (stat/du) sigue en logic/PropertiesLoader.qml.
QtObject {
  property bool propertiesOpen: false
  property var propertiesEntry: null
  property string propertiesSize: ""
  property bool propertiesSizeLoading: false
  property string propertiesPerms: ""
  property string propertiesOwner: ""
  property string propertiesMtime: ""
  // Guard de carrera: showProperties()/showPropertiesForSelection() suben
  // este contador cada vez que se abre el panel para un ítem nuevo, y
  // anotan ese número como "dueño" del stat/du que lanzan. Si el usuario
  // cambia de selección antes de que un "du" lento de una carpeta grande
  // termine, la respuesta tardía ya no coincide con propertiesRequestId
  // (que para entonces ya subió) y se descarta en vez de sobreescribir el
  // tamaño del ítem que se está mirando ahora con el de otro distinto.
  property int propertiesRequestId: 0
  property int _propertiesStatOwner: -1
  property int _propertiesDuOwner: -1
  // Selección múltiple: sin permisos/dueño/fecha (no tiene sentido combinar
  // varios), solo cuenta de items y tamaño total.
  property bool propertiesMulti: false
  property int propertiesCount: 0
}
