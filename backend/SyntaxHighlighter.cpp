#include "SyntaxHighlighter.h"

#include <QFileInfo>
#include <QSet>
#include <QStringList>

namespace {

// Theme Color Tokens (Gruvbox Dark / Modern Dark palette)
constexpr const char *COLOR_KEYWORD = "#fb4934";      // Red/Coral
constexpr const char *COLOR_TYPE = "#fabd2f";         // Warm Yellow
constexpr const char *COLOR_FUNCTION = "#83a598";     // Muted Blue
constexpr const char *COLOR_STRING = "#b8bb26";       // Green
constexpr const char *COLOR_COMMENT = "#928374";      // Muted Grey
constexpr const char *COLOR_NUMBER = "#d3869b";       // Magenta/Purple
constexpr const char *COLOR_PREPROC = "#8ec07c";      // Aqua/Cyan
constexpr const char *COLOR_PROPERTY = "#fe8019";     // Orange

const QSet<QStringView> C_KEYWORDS = {
    u"auto", u"break", u"case", u"catch", u"class", u"const", u"constexpr",
    u"consteval", u"continue", u"default", u"delete", u"do", u"else", u"enum",
    u"explicit", u"export", u"extern", u"false", u"final", u"fn", u"for",
    u"friend", u"func", u"goto", u"if", u"impl", u"import", u"inline", u"let",
    u"match", u"mut", u"namespace", u"new", u"noexcept", u"nullptr", u"operator",
    u"override", u"package", u"private", u"protected", u"pub", u"public",
    u"return", u"sizeof", u"static", u"struct", u"switch", u"template",
    u"this", u"throw", u"trait", u"true", u"try", u"typedef", u"typeid",
    u"typename", u"union", u"using", u"var", u"virtual", u"volatile", u"while",
    u"yield", u"val"
};

const QSet<QStringView> C_TYPES = {
    u"bool", u"char", u"char8_t", u"char16_t", u"char32_t", u"double", u"float",
    u"int", u"long", u"short", u"signed", u"unsigned", u"void", u"wchar_t",
    u"size_t", u"int8_t", u"int16_t", u"int32_t", u"int64_t", u"uint8_t",
    u"uint16_t", u"uint32_t", u"uint64_t", u"uintptr_t", u"intptr_t",
    u"u8", u"u16", u"u32", u"u64", u"usize", u"i8", u"i16", u"i32", u"i64", u"isize",
    u"f32", u"f64", u"QString", u"QByteArray", u"QVector", u"QList", u"QMap",
    u"std", u"string", u"vector", u"map", u"unordered_map", u"set", u"unique_ptr",
    u"shared_ptr"
};

const QSet<QStringView> PY_KEYWORDS = {
    u"and", u"as", u"assert", u"async", u"await", u"break", u"class", u"continue",
    u"def", u"del", u"elif", u"else", u"except", u"False", u"finally", u"for",
    u"from", u"global", u"if", u"import", u"in", u"is", u"lambda", u"None",
    u"nonlocal", u"not", u"or", u"pass", u"raise", u"return", u"True", u"try",
    u"while", u"with", u"yield", u"self", u"cls"
};

const QSet<QStringView> JS_KEYWORDS = {
    u"async", u"await", u"break", u"case", u"catch", u"class", u"const",
    u"continue", u"debugger", u"default", u"delete", u"do", u"else", u"export",
    u"extends", u"false", u"finally", u"for", u"function", u"if", u"import",
    u"in", u"instanceof", u"let", u"new", u"null", u"of", u"return", u"super",
    u"switch", u"this", u"throw", u"true", u"try", u"typeof", u"undefined",
    u"var", u"void", u"while", u"with", u"yield", u"property", u"signal",
    u"readonly", u"required", u"alias", u"Component", u"Item", u"QtObject", u"id"
};

const QSet<QStringView> SH_KEYWORDS = {
    u"case", u"do", u"done", u"elif", u"else", u"esac", u"fi", u"for",
    u"function", u"if", u"in", u"select", u"then", u"until", u"while",
    u"return", u"exit", u"local", u"export", u"source", u"echo", u"printf",
    u"read", u"set", u"unset", u"shift"
};

const QSet<QStringView> SQL_KEYWORDS = {
    u"SELECT", u"FROM", u"WHERE", u"INSERT", u"UPDATE", u"DELETE", u"JOIN",
    u"INNER", u"LEFT", u"RIGHT", u"OUTER", u"ON", u"GROUP", u"BY", u"ORDER",
    u"HAVING", u"LIMIT", u"OFFSET", u"CREATE", u"TABLE", u"DROP", u"ALTER",
    u"INDEX", u"AND", u"OR", u"NOT", u"IN", u"IS", u"NULL", u"LIKE", u"AS",
    u"UNION", u"ALL", u"DISTINCT", u"VALUES", u"SET", u"PRIMARY", u"KEY",
    u"FOREIGN", u"REFERENCES", u"INTEGER", u"TEXT", u"VARCHAR", u"BOOLEAN"
};

inline bool isIdentStart(QChar c) {
  return c.isLetter() || c == QLatin1Char('_') || c == QLatin1Char('$');
}

inline bool isIdentChar(QChar c) {
  return c.isLetterOrNumber() || c == QLatin1Char('_') || c == QLatin1Char('$');
}

inline bool isDigit(QChar c) {
  return c.isDigit();
}

} // namespace

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
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightCFamily(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Single-line comment
    if (c == QLatin1Char('/') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('/')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Multi-line comment
    if (c == QLatin1Char('/') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('*')) {
      int start = i;
      i += 2;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('*') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('/')) {
          i += 2;
          break;
        }
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Preprocessor directive (#include, #define, etc.)
    if (c == QLatin1Char('#')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_PREPROC);
      continue;
    }

    // String literals ("..." or '...')
    if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('\\') && i + 1 < maxChars) {
          i += 2;
          continue;
        }
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Numbers
    if (isDigit(c) || (c == QLatin1Char('.') && i + 1 < maxChars && isDigit(src.at(i + 1)))) {
      int start = i++;
      while (i < maxChars && (src.at(i).isLetterOrNumber() || src.at(i) == QLatin1Char('.'))) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_NUMBER);
      continue;
    }

    // Identifiers & Keywords
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && isIdentChar(src.at(i))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      if (C_KEYWORDS.contains(word)) {
        appendSpan(out, word, COLOR_KEYWORD, false, true);
      } else if (C_TYPES.contains(word)) {
        appendSpan(out, word, COLOR_TYPE);
      } else {
        // Look ahead for function call: foo(...)
        int k = i;
        while (k < maxChars && src.at(k).isSpace() && src.at(k) != QLatin1Char('\n')) ++k;
        if (k < maxChars && src.at(k) == QLatin1Char('(')) {
          appendSpan(out, word, COLOR_FUNCTION);
        } else {
          appendEscaped(out, word);
        }
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// Python
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightPython(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Comment
    if (c == QLatin1Char('#')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Triple-quoted string (""" or ''')
    if ((c == QLatin1Char('"') || c == QLatin1Char('\'')) &&
        i + 2 < maxChars && src.at(i + 1) == c && src.at(i + 2) == c) {
      const QChar q = c;
      int start = i;
      i += 3;
      while (i + 2 < maxChars) {
        if (src.at(i) == q && src.at(i + 1) == q && src.at(i + 2) == q) {
          i += 3;
          break;
        }
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Standard string
    if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('\\') && i + 1 < maxChars) {
          i += 2;
          continue;
        }
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Decorator (@decorator)
    if (c == QLatin1Char('@')) {
      int start = i++;
      while (i < maxChars && isIdentChar(src.at(i))) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_PREPROC);
      continue;
    }

    // Numbers
    if (isDigit(c)) {
      int start = i++;
      while (i < maxChars && (src.at(i).isLetterOrNumber() || src.at(i) == QLatin1Char('.'))) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_NUMBER);
      continue;
    }

    // Identifiers & Keywords
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && isIdentChar(src.at(i))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      if (PY_KEYWORDS.contains(word)) {
        appendSpan(out, word, COLOR_KEYWORD, false, true);
      } else {
        int k = i;
        while (k < maxChars && src.at(k).isSpace() && src.at(k) != QLatin1Char('\n')) ++k;
        if (k < maxChars && src.at(k) == QLatin1Char('(')) {
          appendSpan(out, word, COLOR_FUNCTION);
        } else {
          appendEscaped(out, word);
        }
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// JavaScript / TypeScript / QML / JSON
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightJavaScript(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Single-line comment
    if (c == QLatin1Char('/') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('/')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Multi-line comment
    if (c == QLatin1Char('/') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('*')) {
      int start = i;
      i += 2;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('*') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('/')) {
          i += 2;
          break;
        }
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Strings & Template Literals
    if (c == QLatin1Char('"') || c == QLatin1Char('\'') || c == QLatin1Char('`')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('\\') && i + 1 < maxChars) {
          i += 2;
          continue;
        }
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (quote != QLatin1Char('`') && src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Numbers
    if (isDigit(c)) {
      int start = i++;
      while (i < maxChars && (src.at(i).isLetterOrNumber() || src.at(i) == QLatin1Char('.'))) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_NUMBER);
      continue;
    }

    // Identifiers / Keywords / QML properties
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && isIdentChar(src.at(i))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      if (JS_KEYWORDS.contains(word)) {
        appendSpan(out, word, COLOR_KEYWORD, false, true);
      } else {
        // Look ahead for property colon: prop: value
        int k = i;
        while (k < maxChars && src.at(k).isSpace() && src.at(k) != QLatin1Char('\n')) ++k;
        if (k < maxChars && src.at(k) == QLatin1Char(':')) {
          appendSpan(out, word, COLOR_PROPERTY);
        } else if (k < maxChars && src.at(k) == QLatin1Char('(')) {
          appendSpan(out, word, COLOR_FUNCTION);
        } else {
          appendEscaped(out, word);
        }
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// Shell / Bash
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightShell(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Comment
    if (c == QLatin1Char('#')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Strings
    if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('\\') && i + 1 < maxChars) {
          i += 2;
          continue;
        }
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Variables ($VAR, ${VAR}, $1, etc.)
    if (c == QLatin1Char('$')) {
      int start = i++;
      if (i < maxChars && src.at(i) == QLatin1Char('{')) {
        while (i < maxChars && src.at(i) != QLatin1Char('}') && src.at(i) != QLatin1Char('\n')) ++i;
        if (i < maxChars && src.at(i) == QLatin1Char('}')) ++i;
      } else {
        while (i < maxChars && (isIdentChar(src.at(i)) || src.at(i) == QLatin1Char('?') || src.at(i) == QLatin1Char('@') || src.at(i) == QLatin1Char('*'))) ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_PROPERTY);
      continue;
    }

    // Identifiers & Keywords
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && (isIdentChar(src.at(i)) || src.at(i) == QLatin1Char('-'))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      if (SH_KEYWORDS.contains(word)) {
        appendSpan(out, word, COLOR_KEYWORD, false, true);
      } else {
        appendEscaped(out, word);
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// Config / YAML / TOML / INI
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightConfig(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Comments (# or ;)
    if (c == QLatin1Char('#') || c == QLatin1Char(';')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Section header ([Section])
    if (c == QLatin1Char('[')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char(']') && src.at(i) != QLatin1Char('\n')) ++i;
      if (i < maxChars && src.at(i) == QLatin1Char(']')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_PREPROC, false, true);
      continue;
    }

    // Strings
    if (c == QLatin1Char('"') || c == QLatin1Char('\'')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Key names (key: or key =)
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && (isIdentChar(src.at(i)) || src.at(i) == QLatin1Char('-') || src.at(i) == QLatin1Char('.'))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      int k = i;
      while (k < maxChars && src.at(k).isSpace() && src.at(k) != QLatin1Char('\n')) ++k;
      if (k < maxChars && (src.at(k) == QLatin1Char(':') || src.at(k) == QLatin1Char('='))) {
        appendSpan(out, word, COLOR_PROPERTY, false, true);
      } else if (word == QLatin1String("true") || word == QLatin1String("false") || word == QLatin1String("null")) {
        appendSpan(out, word, COLOR_NUMBER);
      } else {
        appendEscaped(out, word);
      }
      continue;
    }

    // Numbers
    if (isDigit(c)) {
      int start = i++;
      while (i < maxChars && (src.at(i).isLetterOrNumber() || src.at(i) == QLatin1Char('.'))) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_NUMBER);
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// Markup / HTML / XML / Markdown
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightMarkup(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // HTML/XML Comment (<!-- -->)
    if (c == QLatin1Char('<') && i + 3 < maxChars &&
        src.at(i + 1) == QLatin1Char('!') && src.at(i + 2) == QLatin1Char('-') && src.at(i + 3) == QLatin1Char('-')) {
      int start = i;
      i += 4;
      while (i + 2 < maxChars) {
        if (src.at(i) == QLatin1Char('-') && src.at(i + 1) == QLatin1Char('-') && src.at(i + 2) == QLatin1Char('>')) {
          i += 3;
          break;
        }
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Tag (<tag... > or </tag>)
    if (c == QLatin1Char('<') && i + 1 < maxChars && (src.at(i + 1).isLetter() || src.at(i + 1) == QLatin1Char('/'))) {
      int start = i++;
      while (i < maxChars && src.at(i) != QLatin1Char('>') && src.at(i) != QLatin1Char('\n')) {
        if (src.at(i) == QLatin1Char('"') || src.at(i) == QLatin1Char('\'')) {
          const QChar q = src.at(i++);
          while (i < maxChars && src.at(i) != q && src.at(i) != QLatin1Char('\n')) ++i;
          if (i < maxChars && src.at(i) == q) ++i;
          continue;
        }
        ++i;
      }
      if (i < maxChars && src.at(i) == QLatin1Char('>')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_PREPROC);
      continue;
    }

    // Markdown header (# Header)
    if (c == QLatin1Char('#') && (i == 0 || src.at(i - 1) == QLatin1Char('\n'))) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_KEYWORD, false, true);
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// CSS
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightCSS(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Comment
    if (c == QLatin1Char('/') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('*')) {
      int start = i;
      i += 2;
      while (i < maxChars) {
        if (src.at(i) == QLatin1Char('*') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('/')) {
          i += 2;
          break;
        }
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Properties
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && (isIdentChar(src.at(i)) || src.at(i) == QLatin1Char('-'))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      int k = i;
      while (k < maxChars && src.at(k).isSpace() && src.at(k) != QLatin1Char('\n')) ++k;
      if (k < maxChars && src.at(k) == QLatin1Char(':')) {
        appendSpan(out, word, COLOR_PROPERTY);
      } else {
        appendEscaped(out, word);
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}

// ---------------------------------------------------------------------------
// SQL
// ---------------------------------------------------------------------------
QString SyntaxHighlighter::highlightSQL(const QString &src, int maxChars) {
  QString out;
  out.reserve(maxChars * 2);
  out.append(QLatin1String("<pre style=\"white-space:pre-wrap; word-break:break-word\">"));

  int i = 0;
  while (i < maxChars) {
    const QChar c = src.at(i);

    // Comment (-- ...)
    if (c == QLatin1Char('-') && i + 1 < maxChars && src.at(i + 1) == QLatin1Char('-')) {
      int start = i;
      while (i < maxChars && src.at(i) != QLatin1Char('\n')) ++i;
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_COMMENT, true);
      continue;
    }

    // Strings
    if (c == QLatin1Char('\'') || c == QLatin1Char('"')) {
      const QChar quote = c;
      int start = i++;
      while (i < maxChars) {
        if (src.at(i) == quote) {
          ++i;
          break;
        }
        if (src.at(i) == QLatin1Char('\n')) break;
        ++i;
      }
      appendSpan(out, QStringView(src).mid(start, i - start), COLOR_STRING);
      continue;
    }

    // Identifiers & Keywords
    if (isIdentStart(c)) {
      int start = i++;
      while (i < maxChars && isIdentChar(src.at(i))) ++i;
      const QStringView word = QStringView(src).mid(start, i - start);

      if (SQL_KEYWORDS.contains(word.toString().toUpper())) {
        appendSpan(out, word, COLOR_KEYWORD, false, true);
      } else {
        appendEscaped(out, word);
      }
      continue;
    }

    appendEscaped(out, QStringView(src).mid(i, 1));
    ++i;
  }

  out.append(QLatin1String("</pre>"));
  return out;
}
