#include "SyntaxHighlighter.h"
#include "SyntaxHighlighterPrivate.h"

#include <QSet>

namespace {
const QSet<QStringView> JS_KEYWORDS = {
    u"async", u"await", u"break", u"case", u"catch", u"class", u"const",
    u"continue", u"debugger", u"default", u"delete", u"do", u"else", u"export",
    u"extends", u"false", u"finally", u"for", u"function", u"if", u"import",
    u"in", u"instanceof", u"let", u"new", u"null", u"of", u"return", u"super",
    u"switch", u"this", u"throw", u"true", u"try", u"typeof", u"undefined",
    u"var", u"void", u"while", u"with", u"yield", u"property", u"signal",
    u"readonly", u"required", u"alias", u"Component", u"Item", u"QtObject", u"id"
};
} // namespace

using namespace SyntaxHighlighterPrivate;

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

