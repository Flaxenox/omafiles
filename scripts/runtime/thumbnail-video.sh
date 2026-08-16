#!/bin/bash
# Generates (if it doesn't already exist) a JPEG thumbnail of a video with
# ffmpegthumbnailer. $1 = source video, $2 = destination path of the .jpg. The
# destination name already includes the source's mtime (decided by the caller),
# so if the file changes a new thumbnail is requested without needing to
# invalidate anything here.

src="$1"
dest="$2"
[[ -n "$src" && -n "$dest" ]] || exit 1
[[ -f "$dest" ]] && exit 0

mkdir -p -- "$(dirname -- "$dest")"
# $dest is a fully predictable, unsalted-hash cache path (see
# VideoThumbnails.qml's cacheKey()). `-f` above only skips regeneration for a
# genuine, already-complete thumbnail; if something else occupies that name
# (most plausibly a symlink, possibly dangling, pre-planted by an attacker)
# it must be removed before ffmpegthumbnailer writes -- otherwise it follows
# the link and creates/overwrites whatever it points to instead of a fresh
# cache file (P0-4, forensic audit 2026-08-16). `rm -f` on a symlink removes
# only the link, never its target.
[[ -e "$dest" || -L "$dest" ]] && rm -f -- "$dest"
ffmpegthumbnailer -i "$src" -o "$dest" -s 160 -q 6 2>/dev/null
