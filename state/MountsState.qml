pragma Singleton
import QtQuick

// Unidades locales y montajes de red listados en la barra lateral --
// decimoquinto singleton de la capa state/, completa
// logic/MountActions.qml.
QtObject {
  property var mounts: []
  // Dispositivo (device path, p.ej. /dev/sdb1) cuya expulsión está en curso --
  // dispara el spinner del botón de eject de la barra lateral (Fase 21). Se
  // pone en MountActions.ejectMount() y se limpia al terminar; la fila
  // desaparece sola cuando UDisksWatcher refresca el listado. Sin timers.
  property string ejectingDevice: ""
  // Ubicaciones de red (SFTP/SMB/WebDAV/FTP) montadas vía GVfs -- cada
  // una es un directorio real bajo $XDG_RUNTIME_DIR/gvfs/, list-dir.sh la
  // navega igual que cualquier carpeta local sin cambios.
  property var networkMounts: []
}
