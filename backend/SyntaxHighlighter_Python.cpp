#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

#include <QSet>

namespace {
const QSet<QStringView> PY_KEYWORDS = {
    u"and", u"as", u"assert", u"async", u"await", u"break", u"class", u"continue",
    u"def", u"del", u"elif", u"else", u"except", u"False", u"finally", u"for",
    u"from", u"global", u"if", u"import", u"in", u"is", u"lambda", u"None",
    u"nonlocal", u"not", u"or", u"pass", u"raise", u"return", u"True", u"try",
    u"while", u"with", u"yield", u"self", u"cls"
};
} // namespace

using namespace SyntaxHighlighterPrivate;

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

