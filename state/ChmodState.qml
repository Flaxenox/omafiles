pragma Singleton
import QtQuick

// Estado del diálogo de permisos (chmod) -- octavo singleton de la capa
// state/. dialogs/ChmodPanel.qml es puramente presentacional (propio
// `id: root` local, alimentado por binding desde Omafiles.qml), así que
// no necesita importar esto directamente.
QtObject {
  property bool chmodOpen: false
  // Lista de nombres en vez de un string suelto -- chmod admite aplicar
  // el mismo modo a toda la selección, no solo a un fichero.
  property var chmodNames: []
  // true si al abrir el diálogo los ítems seleccionados NO tenían todos
  // el mismo modo octal -- chmodMode se deja en blanco en ese caso (no
  // tiene sentido precargar el modo de "uno cualquiera" de ellos) y la UI
  // avisa de que es una selección mixta.
  property bool chmodMixed: false
  property string chmodMode: ""
  // true si al menos uno de los seleccionados es una carpeta -- controla
  // si se muestra el toggle "Apply to subfolders" (chmod -R no tiene
  // nada que ofrecer sobre una selección de solo ficheros).
  property bool chmodHasDir: false
  property bool chmodRecursive: false
  // { "<nombre>": "<modo octal previo>" }, capturado por PropertiesLoader
  // al abrir el diálogo -- para poder deshacer. Restaura solo el modo del
  // propio ítem seleccionado, NO el de su contenido si se aplicó con -R --
  // capturar el árbol entero antes de cambiar nada sería mucho más caro
  // (find+stat recursivo) para lo que pedía el hueco real (chmod era,
  // junto a bulk rename, la única acción de riesgo sin ningún undo).
  property var chmodOriginalModes: ({})
}
