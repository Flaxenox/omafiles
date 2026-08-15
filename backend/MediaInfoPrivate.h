#pragma once

#include <QString>
#include <QtEndian>

namespace MediaInfoPrivate {

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

inline QString decodeId3String(const uchar *data, int len, uchar encoding) {
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

} // namespace MediaInfoPrivate
