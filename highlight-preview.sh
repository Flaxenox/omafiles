#!/bin/bash
# Highlights syntax for the text preview (Space key) --
# Pygments with INLINE styles (noclasses=True), not CSS classes: QML's
# Text.RichText only understands basic HTML with inline style=
# attributes, not external stylesheets. Only the first
# $2 bytes are highlighted, just as the plain-text preview without
# highlighting already did -- there's no point coloring a whole several-MB file
# just to show a fragment.
#
# $1 = path to the file, $2 = bytes to read, $3 = extension (Omafiles.qml
# already knows it via extOf(), avoids guessing the language by content)

path="$1"
bytes="${2:-4000}"
ext="${3,,}"

# Pygments doesn't recognize these two aliases as is -- they're mapped to their
# real lexer. Any other codeExt extension (see Omafiles.qml) matches
# a valid Pygments alias directly.
case "$ext" in
  h) lexer=c ;;
  yml) lexer=yaml ;;
  *) lexer="$ext" ;;
esac

html="$(head -c "$bytes" -- "$path" | pygmentize -l "$lexer" -f html -O "noclasses=True,style=gruvbox-dark" 2>/dev/null)"
[[ -z "$html" ]] && exit 1

# The <pre> is kept on purpose (not nowrap): it's what makes
# QML's Text.RichText respect real line breaks -- outside of
# a <pre>, HTML collapses the text into a single line just like in a
# normal browser. Only the outer <div> is removed (it brings its own
# background, which we don't want -- the background is set by Color.menu.background) and the
# <pre>'s own attributes (Pygments' fixed line-height, which we don't
# want -- that's controlled by Style.font.* like the rest of the file).
#
# Real bug fixed here: a <pre> WITHOUT attributes still implies
# white-space:pre (no line wrap) in Qt's rich-text
# engine -- the QML Text's wrapMode:Text.Wrap doesn't override it. Long
# lines were cut off flat at the panel edge instead of wrapping.
# pre-wrap keeps the real line breaks (what was needed)
# but DOES allow wrapping within a long line; word-break as a
# fallback for a single word/token wider than the panel.
printf '%s' "$html" | sed -e 's#^<div[^>]*>##' -e 's#<pre[^>]*>#<pre style="white-space:pre-wrap; word-break:break-word">#' -e 's#</pre></div>$#</pre>#'
