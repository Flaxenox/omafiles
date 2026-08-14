#pragma once

#include <QString>
#include <QStringView>

// In-process C++ syntax highlighter for OmaFiles code previews (Phase 36).
// Converts source code into sanitized, inline-styled HTML suitable for
// QML's Text.RichText.
//
// Eliminates the external pygmentize/python subprocess and highlight-preview.sh.
// Runs in sub-millisecond time on the QThreadPool worker thread.
class SyntaxHighlighter {
public:
  enum class Language {
    Unknown,
    C_Family,     // c, cpp, cc, cxx, h, hpp, cs, java, rs, go, zig, d, kt, swift
    Python,       // py, pyw, pyx
    JavaScript,   // js, mjs, cjs, ts, mts, cts, qml, json
    Shell,        // sh, bash, zsh, fish, ksh
    Config,       // yaml, yml, toml, ini, conf, desktop, service, properties
    Markup,       // html, htm, xml, svg, md, markdown
    CSS,          // css, scss, sass, less
    SQL           // sql
  };

  // Maps a filename or extension to Language enum.
  static Language detectLanguage(const QString &extensionOrFilename);

  // Checks if the extension is supported for syntax highlighting.
  static bool isSupported(const QString &extensionOrFilename);

  // Highlights source code and returns inline-styled HTML wrapped in <pre>.
  // If language is unknown or unsupported, returns an empty QString.
  static QString highlight(const QString &source, const QString &extensionOrFilename, int maxBytes = 8192);

private:
  static QString highlightCFamily(const QString &source, int maxChars);
  static QString highlightPython(const QString &source, int maxChars);
  static QString highlightJavaScript(const QString &source, int maxChars);
  static QString highlightShell(const QString &source, int maxChars);
  static QString highlightConfig(const QString &source, int maxChars);
  static QString highlightMarkup(const QString &source, int maxChars);
  static QString highlightCSS(const QString &source, int maxChars);
  static QString highlightSQL(const QString &source, int maxChars);

  static void appendEscaped(QString &out, QStringView text);
  static void appendSpan(QString &out, QStringView text, const char *color, bool italic = false, bool bold = false);
};
