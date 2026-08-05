pragma Singleton
import QtQuick

// Unidades locales y montajes de red listados en la barra lateral --
// decimoquinto singleton de la capa state/, completa
// logic/MountActions.qml.
QtObject {
  property var mounts: []
  // Ubicaciones de red (SFTP/SMB/WebDAV/FTP) montadas vía GVfs -- cada
  // una es un directorio real bajo $XDG_RUNTIME_DIR/gvfs/, list-dir.sh la
  // navega igual que cualquier carpeta local sin cambios.
  property var networkMounts: []
}
