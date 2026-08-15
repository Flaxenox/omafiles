#pragma once

#include <QString>
#include <QStringView>
#include <QChar>

namespace SyntaxHighlighterPrivate {

// Theme Color Tokens (Gruvbox Dark / Modern Dark palette)
constexpr const char *COLOR_KEYWORD = "#fb4934";      // Red/Coral
constexpr const char *COLOR_TYPE = "#fabd2f";         // Warm Yellow
constexpr const char *COLOR_FUNCTION = "#83a598";     // Muted Blue
constexpr const char *COLOR_STRING = "#b8bb26";       // Green
constexpr const char *COLOR_COMMENT = "#928374";      // Muted Grey
constexpr const char *COLOR_NUMBER = "#d3869b";       // Magenta/Purple
constexpr const char *COLOR_PREPROC = "#8ec07c";      // Aqua/Cyan
constexpr const char *COLOR_PROPERTY = "#fe8019";     // Orange

inline bool isIdentStart(QChar c) {
  return c.isLetter() || c == QLatin1Char('_') || c == QLatin1Char('$');
}

inline bool isIdentChar(QChar c) {
  return c.isLetterOrNumber() || c == QLatin1Char('_') || c == QLatin1Char('$');
}

inline bool isDigit(QChar c) {
  return c.isDigit();
}

} // namespace SyntaxHighlighterPrivate
