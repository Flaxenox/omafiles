#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

using namespace SyntaxHighlighterPrivate;

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

