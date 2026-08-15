#include "MediaInfo.h"
#include "MediaInfoPrivate.h"

#include <QFile>

using namespace MediaInfoPrivate;

// ---------------------------------------------------------------------------
bool MediaInfo::parseMp4(const QString &path, Metadata &meta) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return false;

  meta.codec = QStringLiteral("AAC / MP4");
  const qint64 fileSize = file.size();

  while (!file.atEnd()) {
    const QByteArray boxHdr = file.read(8);
    if (boxHdr.size() < 8) break;

    const quint32 boxSize = readBe32(reinterpret_cast<const uchar *>(boxHdr.constData()));
    const QByteArray boxType = boxHdr.mid(4, 4);
    if (boxSize < 8) break;

    if (boxType == "moov") {
      const QByteArray moovData = file.read(qMin(static_cast<qint64>(boxSize - 8), 1048576LL));
      const uchar *mp = reinterpret_cast<const uchar *>(moovData.constData());
      const int mLen = moovData.size();

      // Look for mvhd
      for (int i = 0; i + 24 < mLen; ++i) {
        if (mp[i] == 'm' && mp[i + 1] == 'v' && mp[i + 2] == 'h' && mp[i + 3] == 'd') {
          const uchar ver = mp[i + 4];
          if (ver == 0 && i + 24 <= mLen) {
            const quint32 timescale = readBe32(mp + i + 16);
            const quint32 duration = readBe32(mp + i + 20);
            if (timescale > 0 && duration > 0) {
              meta.durationSecs = static_cast<double>(duration) / static_cast<double>(timescale);
              if (meta.durationSecs > 0) {
                meta.bitrateKbps = qRound((fileSize * 8.0) / (meta.durationSecs * 1000.0));
              }
            }
          }
          break;
        }
      }
      break;
    } else {
      file.seek(file.pos() + boxSize - 8);
    }
  }

  meta.valid = meta.durationSecs > 0;
  return meta.valid;
}
