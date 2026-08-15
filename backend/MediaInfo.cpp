#include "MediaInfo.h"

#include <QDataStream>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QtEndian>
#include <cmath>

namespace {

inline quint32 readSynchsafe(const uchar *p) {
  return ((quint32)(p[0] & 0x7F) << 21) | ((quint32)(p[1] & 0x7F) << 14) |
         ((quint32)(p[2] & 0x7F) << 7) | (quint32)(p[3] & 0x7F);
}

inline quint32 readBe32(const uchar *p) {
  return qFromBigEndian<quint32>(p);
}

inline quint16 readBe16(const uchar *p) {
  return qFromBigEndian<quint16>(p);
}

inline quint32 readLe32(const uchar *p) {
  return qFromLittleEndian<quint32>(p);
}

inline quint16 readLe16(const uchar *p) {
  return qFromLittleEndian<quint16>(p);
}

QString decodeId3String(const uchar *data, int len, uchar encoding) {
  if (len <= 0) return QString();
  if (encoding == 0) { // ISO-8859-1 / Latin-1
    return QString::fromLatin1(reinterpret_cast<const char *>(data), len).trimmed();
  } else if (encoding == 1) { // UTF-16 with BOM
    if (len < 2) return QString();
    const char16_t *u16 = reinterpret_cast<const char16_t *>(data);
    int charCount = len / 2;
    if (u16[0] == 0xFEFF || u16[0] == 0xFFFE) {
      return QString::fromUtf16(u16, charCount).trimmed();
    }
    return QString::fromUtf16(u16, charCount).trimmed();
  } else if (encoding == 2) { // UTF-16BE without BOM
    if (len < 2) return QString();
    QString res;
    res.reserve(len / 2);
    for (int i = 0; i + 1 < len; i += 2) {
      res.append(QChar(readBe16(data + i)));
    }
    return res.trimmed();
  } else if (encoding == 3) { // UTF-8
    return QString::fromUtf8(reinterpret_cast<const char *>(data), len).trimmed();
  }
  return QString::fromUtf8(reinterpret_cast<const char *>(data), len).trimmed();
}

} // namespace

bool MediaInfo::isSupported(const QString &extensionOrFilename) {
  QString ext = extensionOrFilename.toLower();
  if (ext.contains(QLatin1Char('.'))) {
    ext = QFileInfo(ext).suffix().toLower();
  }
  return ext == QLatin1String("mp3") || ext == QLatin1String("flac") ||
         ext == QLatin1String("wav") || ext == QLatin1String("ogg") ||
         ext == QLatin1String("opus") || ext == QLatin1String("oga") ||
         ext == QLatin1String("m4a") || ext == QLatin1String("mp4") ||
         ext == QLatin1String("aac");
}

QString MediaInfo::formatDuration(double secs) {
  if (secs <= 0) return QString();
  int totalSecs = qRound(secs);
  int hours = totalSecs / 3600;
  int mins = (totalSecs % 3600) / 60;
  int s = totalSecs % 60;

  if (hours > 0) {
    return QStringLiteral("%1:%2:%3")
        .arg(hours)
        .arg(mins, 2, 10, QLatin1Char('0'))
        .arg(s, 2, 10, QLatin1Char('0'));
  }
  return QStringLiteral("%1:%2")
      .arg(mins)
      .arg(s, 2, 10, QLatin1Char('0'));
}

MediaInfo::Metadata MediaInfo::extract(const QString &path) {
  Metadata meta;
  const QString ext = QFileInfo(path).suffix().toLower();

  if (ext == QLatin1String("mp3")) {
    parseMp3(path, meta);
  } else if (ext == QLatin1String("flac")) {
    parseFlac(path, meta);
  } else if (ext == QLatin1String("wav")) {
    parseWav(path, meta);
  } else if (ext == QLatin1String("ogg") || ext == QLatin1String("opus") || ext == QLatin1String("oga")) {
    parseOgg(path, meta);
  } else if (ext == QLatin1String("m4a") || ext == QLatin1String("mp4") || ext == QLatin1String("aac")) {
    parseMp4(path, meta);
  }

  return meta;
}

QVariantList MediaInfo::toVariantList(const Metadata &meta) {
  QVariantList out;
  if (!meta.valid && meta.durationSecs <= 0 && meta.title.isEmpty() && meta.artist.isEmpty()) {
    return out;
  }

  if (meta.durationSecs > 0) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Duration");
    m[QStringLiteral("value")] = formatDuration(meta.durationSecs);
    out.append(m);
  }
  if (!meta.codec.isEmpty()) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Codec");
    m[QStringLiteral("value")] = meta.codec;
    out.append(m);
  }
  if (meta.bitrateKbps > 0) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Bitrate");
    m[QStringLiteral("value")] = QStringLiteral("%1 kbps").arg(meta.bitrateKbps);
    out.append(m);
  }
  if (meta.sampleRateHz > 0) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Sample rate");
    m[QStringLiteral("value")] = QStringLiteral("%1 kHz").arg(meta.sampleRateHz / 1000.0, 0, 'f', 1);
    out.append(m);
  }
  if (meta.channels > 0) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Channels");
    m[QStringLiteral("value")] = (meta.channels == 1) ? QStringLiteral("Mono")
                                : (meta.channels == 2) ? QStringLiteral("Stereo")
                                : QString::number(meta.channels);
    out.append(m);
  }
  if (!meta.artist.isEmpty()) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Artist");
    m[QStringLiteral("value")] = meta.artist;
    out.append(m);
  }
  if (!meta.title.isEmpty()) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Title");
    m[QStringLiteral("value")] = meta.title;
    out.append(m);
  }
  if (!meta.album.isEmpty()) {
    QVariantMap m;
    m[QStringLiteral("label")] = QStringLiteral("Album");
    m[QStringLiteral("value")] = meta.album;
    out.append(m);
  }

  return out;
}

// ---------------------------------------------------------------------------
// MP3 Parser
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

// ---------------------------------------------------------------------------
// FLAC Parser
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

// ---------------------------------------------------------------------------
// RIFF WAV Parser
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

// ---------------------------------------------------------------------------
// OGG Vorbis / Opus Parser
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

// ---------------------------------------------------------------------------
// ISO MP4 / M4A Parser
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
