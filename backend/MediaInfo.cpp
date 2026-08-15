#include "MediaInfo.h"

#include <QDataStream>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QtEndian>
#include <cmath>


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
