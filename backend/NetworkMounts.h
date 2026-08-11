#pragma once

#include <QObject>
#include <QVariantList>
#include <qqmlregistration.h>

// Enumeration of network locations mounted via GVfs (SFTP/SMB/WebDAV/FTP)
// for the sidebar (Phase 16, josema). Replacement for
// list-network-mounts.sh: each active mount appears as a real, navigable
// subdirectory under $XDG_RUNTIME_DIR/gvfs/ (gvfsd-fuse exposes it there, and
// DirectoryModel already knows how to list it unchanged). The only thing
// needed is to discover which ones are active and get a readable label from the
// internal mount name ("scheme:key=value,key=value,...").
//
// Synchronous (just a readdir + stats over the gvfs dir, cheap): returns
// a list of {label, path, scheme} objects, the same shape that
// Utils.parseNetworkMounts produced. QML singleton. No dependency on Quickshell.
class NetworkMounts : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit NetworkMounts(QObject *parent = nullptr);

  // Network locations mounted right now. Empty if there are none (or the
  // gvfs directory does not exist).
  Q_INVOKABLE QVariantList list() const;
};
