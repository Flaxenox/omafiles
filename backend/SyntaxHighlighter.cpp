#include "SyntaxHighlighter.h"

#include <QFileInfo>
#include <QSet>
#include <QStringList>


void SyntaxHighlighter::appendEscaped(QString &out, QStringView text) {
  for (QChar c : text) {
    if (c == QLatin1Char('&'))
      out.append(QLatin1String("&amp;"));
    else if (c == QLatin1Char('<'))
      out.append(QLatin1String("&lt;"));
    else if (c == QLatin1Char('>'))
      out.append(QLatin1String("&gt;"));
    else if (c == QLatin1Char('"'))
      out.append(QLatin1String("&quot;"));
    else
      out.append(c);
  }
}

void SyntaxHighlighter::appendSpan(QString &out, QStringView text, const char *color, bool italic, bool bold) {
  out.append(QLatin1String("<span style=\"color:"));
  out.append(QLatin1String(color));
  if (italic) out.append(QLatin1String(";font-style:italic"));
  if (bold) out.append(QLatin1String(";font-weight:bold"));
  out.append(QLatin1String("\">"));
  appendEscaped(out, text);
  out.append(QLatin1String("</span>"));
}

SyntaxHighlighter::Language SyntaxHighlighter::detectLanguage(const QString &extensionOrFilename) {
  QString ext = extensionOrFilename.toLower();
  if (ext.contains(QLatin1Char('.'))) {
    ext = QFileInfo(ext).suffix().toLower();
  }

  if (ext == QLatin1String("c") || ext == QLatin1String("cpp") ||
      ext == QLatin1String("cc") || ext == QLatin1String("cxx") ||
      ext == QLatin1String("h") || ext == QLatin1String("hpp") ||
      ext == QLatin1String("hxx") || ext == QLatin1String("rs") ||
      ext == QLatin1String("go") || ext == QLatin1String("zig") ||
      ext == QLatin1String("java") || ext == QLatin1String("cs") ||
      ext == QLatin1String("d") || ext == QLatin1String("kt") ||
      ext == QLatin1String("swift")) {
    return Language::C_Family;
  }
  if (ext == QLatin1String("py") || ext == QLatin1String("pyw") ||
      ext == QLatin1String("pyx")) {
    return Language::Python;
  }
  if (ext == QLatin1String("js") || ext == QLatin1String("mjs") ||
      ext == QLatin1String("cjs") || ext == QLatin1String("ts") ||
      ext == QLatin1String("mts") || ext == QLatin1String("cts") ||
      ext == QLatin1String("qml") || ext == QLatin1String("json")) {
    return Language::JavaScript;
  }
  if (ext == QLatin1String("sh") || ext == QLatin1String("bash") ||
      ext == QLatin1String("zsh") || ext == QLatin1String("fish") ||
      ext == QLatin1String("ksh")) {
    return Language::Shell;
  }
  if (ext == QLatin1String("yaml") || ext == QLatin1String("yml") ||
      ext == QLatin1String("toml") || ext == QLatin1String("ini") ||
      ext == QLatin1String("conf") || ext == QLatin1String("desktop") ||
      ext == QLatin1String("service") || ext == QLatin1String("properties")) {
    return Language::Config;
  }
  if (ext == QLatin1String("html") || ext == QLatin1String("htm") ||
      ext == QLatin1String("xml") || ext == QLatin1String("svg") ||
      ext == QLatin1String("md") || ext == QLatin1String("markdown")) {
    return Language::Markup;
  }
  if (ext == QLatin1String("css") || ext == QLatin1String("scss") ||
      ext == QLatin1String("sass") || ext == QLatin1String("less")) {
    return Language::CSS;
  }
  if (ext == QLatin1String("sql")) {
    return Language::SQL;
  }

  return Language::Unknown;
}

bool SyntaxHighlighter::isSupported(const QString &extensionOrFilename) {
  return detectLanguage(extensionOrFilename) != Language::Unknown;
}

QString SyntaxHighlighter::highlight(const QString &source, const QString &extensionOrFilename, int maxBytes) {
  const Language lang = detectLanguage(extensionOrFilename);
  if (lang == Language::Unknown || source.isEmpty()) {
    return QString();
  }

  const int maxChars = qMin(static_cast<int>(source.size()), maxBytes);

  switch (lang) {
  case Language::C_Family:
    return highlightCFamily(source, maxChars);
  case Language::Python:
    return highlightPython(source, maxChars);
  case Language::JavaScript:
    return highlightJavaScript(source, maxChars);
  case Language::Shell:
    return highlightShell(source, maxChars);
  case Language::Config:
    return highlightConfig(source, maxChars);
  case Language::Markup:
    return highlightMarkup(source, maxChars);
  case Language::CSS:
    return highlightCSS(source, maxChars);
  case Language::SQL:
    return highlightSQL(source, maxChars);
  default:
    return QString();
  }
}

// ---------------------------------------------------------------------------
// C / C++ / Rust / Go / Zig / Java / C#
