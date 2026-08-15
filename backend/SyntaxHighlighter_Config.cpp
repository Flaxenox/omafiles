#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

using namespace SyntaxHighlighterPrivate;

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

