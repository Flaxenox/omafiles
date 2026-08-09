#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// Enumeración de ubicaciones de red montadas vía GVfs (SFTP/SMB/WebDAV/FTP)
// para la barra lateral (Fase 16, josema). Sustituto de
// list-network-mounts.sh: cada mount activo aparece como un subdirectorio
// real y navegable bajo $XDG_RUNTIME_DIR/gvfs/ (gvfsd-fuse lo expone ahí, y
// DirectoryModel ya lo sabe listar sin cambios). Lo único que hace falta es
// descubrir cuáles hay activos y sacar una etiqueta legible del nombre
// interno del mount ("esquema:clave=valor,clave=valor,...").
//
// Síncrono (solo un readdir + stats sobre el dir de gvfs, barato): devuelve
// una lista de objetos {label, path, scheme}, la misma forma que producía
// Utils.parseNetworkMounts. Singleton QML. Sin dependencia de Quickshell.
class NetworkMounts : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit NetworkMounts(QObject *parent = nullptr);

  // Ubicaciones de red montadas ahora mismo. Vacía si no hay ninguna (o no
  // existe el directorio de gvfs).
  Q_INVOKABLE QVariantList list() const;
};
