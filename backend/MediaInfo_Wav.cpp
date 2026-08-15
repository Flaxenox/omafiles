#include "MediaInfo.h"
#include "MediaInfoPrivate.h"

#include <QFile>

using namespace MediaInfoPrivate;

// ---------------------------------------------------------------------------
bool MediaInfo::parseWav(const QString &path, Metadata &meta) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return false;

  meta.codec = QStringLiteral("WAV");
  const QByteArray hdr = file.read(12);
  if (hdr.size() < 12 || !hdr.startsWith("RIFF") || hdr.mid(8, 4) != "WAVE") return false;

  while (!file.atEnd()) {
    const QByteArray chunkHdr = file.read(8);
    if (chunkHdr.size() < 8) break;

    const QByteArray chunkId = chunkHdr.left(4);
    const quint32 chunkSize = readLe32(reinterpret_cast<const uchar *>(chunkHdr.constData() + 4));

    if (chunkId == "fmt ") {
      const QByteArray fmt = file.read(chunkSize);
      if (fmt.size() >= 16) {
        const uchar *fp = reinterpret_cast<const uchar *>(fmt.constData());
        meta.channels = readLe16(fp + 2);
        meta.sampleRateHz = readLe32(fp + 4);
        const quint32 byteRate = readLe32(fp + 8);
        if (byteRate > 0) meta.bitrateKbps = qRound((byteRate * 8.0) / 1000.0);
      }
    } else if (chunkId == "data") {
      if (meta.bitrateKbps > 0 && chunkSize > 0) {
        meta.durationSecs = (chunkSize * 8.0) / (meta.bitrateKbps * 1000.0);
      }
      file.seek(file.pos() + chunkSize);
    } else {
      file.seek(file.pos() + chunkSize);
    }
  }

  meta.valid = meta.sampleRateHz > 0 || meta.durationSecs > 0;
  return meta.valid;
}

