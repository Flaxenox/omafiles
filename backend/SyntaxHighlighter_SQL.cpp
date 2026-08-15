#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

#include <QSet>

namespace {
const QSet<QStringView> SQL_KEYWORDS = {
    u"SELECT", u"FROM", u"WHERE", u"INSERT", u"UPDATE", u"DELETE", u"JOIN",
    u"INNER", u"LEFT", u"RIGHT", u"OUTER", u"ON", u"GROUP", u"BY", u"ORDER",
    u"HAVING", u"LIMIT", u"OFFSET", u"CREATE", u"TABLE", u"DROP", u"ALTER",
    u"INDEX", u"AND", u"OR", u"NOT", u"IN", u"IS", u"NULL", u"LIKE", u"AS",
    u"UNION", u"ALL", u"DISTINCT", u"VALUES", u"SET", u"PRIMARY", u"KEY",
    u"FOREIGN", u"REFERENCES", u"INTEGER", u"TEXT", u"VARCHAR", u"BOOLEAN"
};
} // namespace

using namespace SyntaxHighlighterPrivate;

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
