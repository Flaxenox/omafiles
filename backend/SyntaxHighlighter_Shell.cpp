#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

#include <QSet>

namespace {
const QSet<QStringView> SH_KEYWORDS = {
    u"case", u"do", u"done", u"elif", u"else", u"esac", u"fi", u"for",
    u"function", u"if", u"in", u"select", u"then", u"until", u"while",
    u"return", u"exit", u"local", u"export", u"source", u"echo", u"printf",
    u"read", u"set", u"unset", u"shift"
};
} // namespace

using namespace SyntaxHighlighterPrivate;

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

