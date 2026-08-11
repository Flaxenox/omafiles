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
ffmpegthumbnailer -i "$src" -o "$dest" -s 160 -q 6 2>/dev/null
