#include "NetworkMounts.h"

#include <QDir>
#include <QFileInfo>
#include <QVariantMap>

#include <unistd.h>

NetworkMounts::NetworkMounts(QObject *parent) : QObject(parent) {}

QVariantList NetworkMounts::list() const {
  QVariantList out;
  const QString runtime = qEnvironmentVariable(
      "XDG_RUNTIME_DIR",
      QStringLiteral("/run/user/%1").arg(::getuid()));
  QDir gvfs(runtime + QStringLiteral("/gvfs"));
  if (!gvfs.exists())
    return out;

  const auto dirs = gvfs.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
  for (const QFileInfo &fi : dirs) {
    // Nombre interno del mount: "esquema:clave=valor,clave=valor,...".
    const QString name = fi.fileName();
    const int colon = name.indexOf(QLatin1Char(':'));
    const QString scheme = colon >= 0 ? name.left(colon) : name;
    const QString rest = colon >= 0 ? name.mid(colon + 1) : QString();

    QString host, share, user;
    const auto pairs = rest.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &pair : pairs) {
      if (pair.startsWith(QLatin1String("host=")))
        host = pair.mid(5);
      else if (pair.startsWith(QLatin1String("server=")))
        host = pair.mid(7);
      else if (pair.startsWith(QLatin1String("share=")))
        share = pair.mid(6);
      else if (pair.startsWith(QLatin1String("user=")))
        user = pair.mid(5);
    }

    QString proto;
    if (scheme == QLatin1String("sftp"))
      proto = QStringLiteral("SFTP");
    else if (scheme == QLatin1String("ftp") || scheme == QLatin1String("ftps"))
      proto = QStringLiteral("FTP");
    else if (scheme == QLatin1String("dav") || scheme == QLatin1String("davs"))
      proto = QStringLiteral("WebDAV");
    else if (scheme == QLatin1String("smb-share") ||
             scheme == QLatin1String("smb"))
      proto = QStringLiteral("SMB");
    else
      proto = scheme;

    QString label = proto + QStringLiteral(": ") + (host.isEmpty() ? name : host);
    if (!share.isEmpty())
      label += QLatin1Char('/') + share;
    if (!user.isEmpty())
      label += QStringLiteral(" (") + user + QLatin1Char(')');

    QVariantMap m;
    m[QStringLiteral("label")] = label;
    m[QStringLiteral("path")] = fi.absoluteFilePath();
    m[QStringLiteral("scheme")] = scheme;
    out.append(m);
  }
  return out;
}
