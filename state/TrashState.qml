pragma Singleton
import QtQuick

// Metadatos de la papelera ({ "<nombre>": { origPath, epoch } }, leído
// de ~/.local/share/Trash/info/*.trashinfo por trash-info.sh) --
// decimonoveno singleton de la capa state/. COMPARTIDA a propósito entre
// el panel activo y todos los de fondo (cualquiera de ellos puede pedir
// trash-info.sh, y el resultado sirve para todos por igual) -- ver el
// comentario largo en logic/FileMeta.qml sobre por qué NO se limpia al
// salir de la papelera (protagonista del parpadeo real cazado el
// 2026-08-05, ver [[project_omafiles_componentization_refactor]]). Antes
// de esta migración viajaba como root.trashInfo/hostRoot.trashInfo por
// prop-drilling explícito -- exactamente la clase de estado que motivó
// la capa state/ en primer lugar.
QtObject {
  property var trashInfo: ({})
}
