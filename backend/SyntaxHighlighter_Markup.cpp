#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

using namespace SyntaxHighlighterPrivate;

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

