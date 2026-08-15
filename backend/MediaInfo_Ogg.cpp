#include "MediaInfo.h"
#include "MediaInfoPrivate.h"

#include <QFile>

using namespace MediaInfoPrivate;

// ---------------------------------------------------------------------------
bool MediaInfo::parseOgg(const QString &path, Metadata &meta) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return false;

  meta.codec = QStringLiteral("OGG");
  const QByteArray sample = file.read(65536);
  if (!sample.startsWith("OggS")) return false;

  // Search for Vorbis or Opus comment block in first 64 KB
  int idx = sample.indexOf("vorbis");
  if (idx < 0) idx = sample.indexOf("OpusTags");

  if (idx > 0) {
    const uchar *cp = reinterpret_cast<const uchar *>(sample.constData());
    int offset = idx + ((sample.mid(idx, 6) == "vorbis") ? 6 : 8);

    if (offset + 4 <= sample.size()) {
      const quint32 vendorLen = readLe32(cp + offset);
      offset += 4 + vendorLen;
      if (offset + 4 <= sample.size()) {
        const quint32 count = readLe32(cp + offset);
        offset += 4;
        for (quint32 c = 0; c < count && offset + 4 <= sample.size(); ++c) {
          const quint32 itemLen = readLe32(cp + offset);
          offset += 4;
          if (offset + itemLen > (quint32)sample.size()) break;

          const QString comment = QString::fromUtf8(reinterpret_cast<const char *>(cp + offset), itemLen);
          offset += itemLen;

          const int eq = comment.indexOf(QLatin1Char('='));
          if (eq > 0) {
            const QString key = comment.left(eq).toUpper();
            const QString val = comment.mid(eq + 1).trimmed();
            if (key == QLatin1String("TITLE") && meta.title.isEmpty()) meta.title = val;
            else if (key == QLatin1String("ARTIST") && meta.artist.isEmpty()) meta.artist = val;
            else if (key == QLatin1String("ALBUM") && meta.album.isEmpty()) meta.album = val;
          }
        }
      }
    }
  }

  meta.valid = !meta.title.isEmpty() || !meta.artist.isEmpty();
  return meta.valid;
}

