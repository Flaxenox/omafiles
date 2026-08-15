#include "MediaInfo.h"
#include "MediaInfoPrivate.h"

#include <QFile>

using namespace MediaInfoPrivate;

// ---------------------------------------------------------------------------
bool MediaInfo::parseMp3(const QString &path, Metadata &meta) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) return false;

  meta.codec = QStringLiteral("MP3");
  const qint64 fileSize = file.size();
  const QByteArray header = file.read(65536);
  if (header.size() < 10) return false;

  qint64 audioStartOffset = 0;

  // 1. ID3v2 Tag parsing
  const uchar *p = reinterpret_cast<const uchar *>(header.constData());
  if (p[0] == 'I' && p[1] == 'D' && p[2] == '3') {
    const uchar majorVer = p[3];
    const quint32 tagSize = readSynchsafe(p + 6);
    audioStartOffset = 10 + tagSize;

    QByteArray tagData;
    if (tagSize + 10 <= (quint32)header.size()) {
      tagData = header.mid(10, tagSize);
    } else {
      file.seek(10);
      tagData = file.read(tagSize);
    }

    const uchar *tp = reinterpret_cast<const uchar *>(tagData.constData());
    const int dataSize = tagData.size();
    int idx = 0;

    while (idx + 10 < dataSize) {
      if (tp[idx] == 0) break; // Padding reached

      QString frameId;
      int frameSize = 0;

      if (majorVer == 2) { // ID3v2.2 (3-char IDs, 3-byte size)
        if (idx + 6 > dataSize) break;
        frameId = QString::fromLatin1(reinterpret_cast<const char *>(tp + idx), 3);
        frameSize = ((int)tp[idx + 3] << 16) | ((int)tp[idx + 4] << 8) | (int)tp[idx + 5];
        idx += 6;
      } else if (majorVer == 3) { // ID3v2.3 (4-char IDs, 4-byte BE size)
        frameId = QString::fromLatin1(reinterpret_cast<const char *>(tp + idx), 4);
        frameSize = readBe32(tp + idx + 4);
        idx += 10;
      } else if (majorVer == 4) { // ID3v2.4 (4-char IDs, 4-byte synchsafe size)
        frameId = QString::fromLatin1(reinterpret_cast<const char *>(tp + idx), 4);
        frameSize = readSynchsafe(tp + idx + 4);
        idx += 10;
      } else {
        break;
      }

      if (frameSize <= 0 || idx + frameSize > dataSize) break;

      const uchar encoding = tp[idx];
      const QString value = decodeId3String(tp + idx + 1, frameSize - 1, encoding);

      if (frameId == QLatin1String("TIT2") || frameId == QLatin1String("TT2")) {
        if (meta.title.isEmpty()) meta.title = value;
      } else if (frameId == QLatin1String("TPE1") || frameId == QLatin1String("TP1")) {
        if (meta.artist.isEmpty()) meta.artist = value;
      } else if (frameId == QLatin1String("TALB") || frameId == QLatin1String("TAL")) {
        if (meta.album.isEmpty()) meta.album = value;
      } else if (frameId == QLatin1String("TLEN") || frameId == QLatin1String("TLE")) {
        bool ok = false;
        double ms = value.toDouble(&ok);
        if (ok && ms > 0) meta.durationSecs = ms / 1000.0;
      }

      idx += frameSize;
    }
  }

  // 2. ID3v1 Fallback at the end of file
  if ((meta.title.isEmpty() || meta.artist.isEmpty()) && fileSize >= 128) {
    file.seek(fileSize - 128);
    const QByteArray id3v1 = file.read(128);
    if (id3v1.size() == 128 && id3v1.startsWith("TAG")) {
      if (meta.title.isEmpty()) {
        meta.title = QString::fromLatin1(id3v1.constData() + 3, 30).trimmed();
      }
      if (meta.artist.isEmpty()) {
        meta.artist = QString::fromLatin1(id3v1.constData() + 33, 30).trimmed();
      }
      if (meta.album.isEmpty()) {
        meta.album = QString::fromLatin1(id3v1.constData() + 63, 30).trimmed();
      }
    }
  }

  // 3. MPEG Audio Frame Search for Bitrate / Sample Rate / Duration
  file.seek(audioStartOffset);
  const QByteArray audioBuf = file.read(16384);
  const uchar *ap = reinterpret_cast<const uchar *>(audioBuf.constData());
  const int aLen = audioBuf.size();

  static const int kBitratesV1L3[] = { 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0 };
  static const int kSampleRatesV1[] = { 44100, 48000, 32000, 0 };

  for (int i = 0; i + 4 < aLen; ++i) {
    if (ap[i] == 0xFF && (ap[i + 1] & 0xE0) == 0xE0) { // Syncword found
      const uchar ver = (ap[i + 1] >> 3) & 0x03;     // 3 = MPEG1, 2 = MPEG2, 0 = MPEG2.5
      const uchar layer = (ap[i + 1] >> 1) & 0x03;   // 1 = Layer III
      const uchar brIdx = (ap[i + 2] >> 4) & 0x0F;
      const uchar srIdx = (ap[i + 2] >> 2) & 0x03;
      const uchar mode = (ap[i + 3] >> 6) & 0x03;    // 3 = Mono, others = Stereo

      if (ver == 3 && layer == 1 && brIdx > 0 && brIdx < 15 && srIdx < 3) {
        meta.bitrateKbps = kBitratesV1L3[brIdx];
        meta.sampleRateHz = kSampleRatesV1[srIdx];
        meta.channels = (mode == 3) ? 1 : 2;

        if (meta.durationSecs <= 0 && meta.bitrateKbps > 0) {
          const qint64 audioBytes = qMax(0LL, fileSize - audioStartOffset);
          meta.durationSecs = (audioBytes * 8.0) / (meta.bitrateKbps * 1000.0);
        }
        meta.valid = true;
        break;
      }
    }
  }

  meta.valid = meta.valid || !meta.title.isEmpty() || !meta.artist.isEmpty() || meta.durationSecs > 0;
  return meta.valid;
}

