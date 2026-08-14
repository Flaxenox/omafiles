#pragma once

#include <QByteArray>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// High-speed in-process audio/video metadata extractor for OmaFiles previews (Phase 37.1).
// Parses ID3v1, ID3v2 (2.2, 2.3, 2.4), FLAC (STREAMINFO & Vorbis Comments),
// Ogg Vorbis/Opus, RIFF WAV, and ISO MP4/M4A directly in C++.
//
// Eliminates the external ffprobe subprocess and python/json parsing.
// Extracts duration, artist, title, album, codec, bitrate, sample rate, and channels in < 0.1 ms.
class MediaInfo {
public:
  struct Metadata {
    QString title;
    QString artist;
    QString album;
    QString year;
    QString genre;
    QString codec;
    double durationSecs = 0.0;
    int bitrateKbps = 0;
    int sampleRateHz = 0;
    int channels = 0;
    bool valid = false;
  };

  // Extracts metadata from the audio/video file at `path`.
  static Metadata extract(const QString &path);

  // Converts Metadata into the QML-friendly QVariantList expected by PreviewPanel.
  static QVariantList toVariantList(const Metadata &meta);

  // Checks if the extension is supported for media metadata extraction.
  static bool isSupported(const QString &extensionOrFilename);

private:
  static bool parseMp3(const QString &path, Metadata &meta);
  static bool parseFlac(const QString &path, Metadata &meta);
  static bool parseOgg(const QString &path, Metadata &meta);
  static bool parseWav(const QString &path, Metadata &meta);
  static bool parseMp4(const QString &path, Metadata &meta);

  static QString formatDuration(double secs);
};
