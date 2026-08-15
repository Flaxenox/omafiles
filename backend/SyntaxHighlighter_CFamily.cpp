#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

#include <QSet>

namespace {
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
} // namespace

using namespace SyntaxHighlighterPrivate;

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

