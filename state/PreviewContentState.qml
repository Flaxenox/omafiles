pragma Singleton
import QtQuick

// Contenido cargado de la vista previa (texto/resaltado/PDF/audio) --
// décimo singleton de la capa state/. Distinto de state/PreviewState.qml
// (que solo guarda si el panel está abierto/cerrado): esto es el
// resultado real de loadPreview(), que sigue en logic/PreviewLoader.qml.
QtObject {
  property var previewEntry: null
  property string previewText: ""
  property bool previewIsText: false
  // HTML con estilos inline (Pygments, noclasses=True) para el fragmento
  // en previsualización -- vacío si el lenguaje no se reconoce o
  // highlight-preview.sh falla, en cuyo caso se cae al Text plano de
  // siempre con previewText. Ver PreviewLoader.loadPreview().
  property string previewHighlighted: ""
  // Render de la primera página como PNG (pdftoppm) -- vacío mientras se
  // genera o si pdftoppm falla, igual que videoThumbReady con los vídeos.
  property string previewPdfImage: ""
  // Metadatos de audio (ffprobe): duración/formato/bitrate/etc, mismo
  // formato { label, value } que ya usa el Repeater de Properties.
  property var previewAudioInfo: []
  // Guard de carrera, mismo mecanismo que propertiesRequestId: loadPreview()
  // sube este contador cada vez que se previsualiza un ítem nuevo y anota
  // ese número como "dueño" de cada proceso que lanza (texto/resaltado/
  // PDF/audio). Sin esto, seleccionar rápido un fichero A (con highlight-
  // preview.sh/pdftoppm/ffprobe lento) y pasar a un fichero B antes de que
  // termine dejaba que el resultado de A, al llegar tarde, se pintara
  // encima de la previsualización de B.
  property int previewRequestId: 0
  property int _previewTextOwner: -1
  property int _previewHighlightOwner: -1
  property int _previewPdfOwner: -1
  property int _previewAudioOwner: -1
}
