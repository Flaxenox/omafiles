#include "MediaInfo.h"
#include "MediaInfoPrivate.h"

#include <QFile>

using namespace MediaInfoPrivate;

// ---------------------------------------------------------------------------
bool MediaInfo::parseFlac(const QString &path, Metadata &meta) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return false;

  meta.codec = QStringLiteral("FLAC");
  const QByteArray header = file.read(4);
  if (header != "fLaC") return false;

  bool isLast = false;
  while (!isLast && !file.atEnd()) {
    const QByteArray blockHdr = file.read(4);
    if (blockHdr.size() < 4) break;

    const uchar *bp = reinterpret_cast<const uchar *>(blockHdr.constData());
    isLast = (bp[0] & 0x80) != 0;
    const uchar blockType = bp[0] & 0x7F;
    const quint32 blockSize = ((quint32)bp[1] << 16) | ((quint32)bp[2] << 8) | (quint32)bp[3];

    if (blockType == 0) { // STREAMINFO (34 bytes)
      const QByteArray info = file.read(blockSize);
      if (info.size() >= 18) {
        const uchar *ip = reinterpret_cast<const uchar *>(info.constData());
        // Sample rate: 20 bits at byte 10..12
        const quint32 sr = ((quint32)ip[10] << 12) | ((quint32)ip[11] << 4) | ((quint32)ip[12] >> 4);
        const quint32 ch = (((quint32)ip[12] >> 1) & 0x07) + 1;
        // Total samples: 36 bits at byte 13..17
        const quint64 totalSamples = (((quint64)(ip[13] & 0x0F)) << 32) |
                                     ((quint64)ip[14] << 24) |
                                     ((quint64)ip[15] << 16) |
                                     ((quint64)ip[16] << 8) |
                                     (quint64)ip[17];

        meta.sampleRateHz = sr;
        meta.channels = ch;
        if (sr > 0 && totalSamples > 0) {
          meta.durationSecs = static_cast<double>(totalSamples) / static_cast<double>(sr);
          if (meta.durationSecs > 0) {
            meta.bitrateKbps = qRound((file.size() * 8.0) / (meta.durationSecs * 1000.0));
          }
        }
      }
    } else if (blockType == 4) { // VORBIS_COMMENT
      const QByteArray commentData = file.read(blockSize);
      if (commentData.size() >= 8) {
        const uchar *cp = reinterpret_cast<const uchar *>(commentData.constData());
        const quint32 vendorLen = readLe32(cp);
        int offset = 4 + vendorLen;
        if (offset + 4 <= commentData.size()) {
          const quint32 count = readLe32(cp + offset);
          offset += 4;
          for (quint32 c = 0; c < count && offset + 4 <= commentData.size(); ++c) {
            const quint32 itemLen = readLe32(cp + offset);
            offset += 4;
            if (offset + itemLen > (quint32)commentData.size()) break;

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
    } else {
      file.seek(file.pos() + blockSize);
    }
  }

  meta.valid = meta.durationSecs > 0 || !meta.title.isEmpty() || !meta.artist.isEmpty();
  return meta.valid;
}

