#!/bin/bash
# Lists ONE depth level inside a compressed archive (zip/7z/
# rar/tar-family) without extracting it -- to be able to "enter" a .zip as if
# it were just another folder (see inArchive/archivePath/archiveSubPath in
# Omafiles.qml). NUL-delimited, 2 fields per entry: name / is-folder
# (0|1). No size: each tool exposes it in a different column format
# and parsing all 4 robustly wasn't worth it against the
# complexity -- it can be added later if it's really needed.
#
# $1 = real path to the archive on disk, $2 = subpath inside the archive
# ("" = archive root)

archive="$1"
sub="$2"
ext="${archive##*.}"
ext="${ext,,}"

list_raw() {
  case "$ext" in
    zip) unzip -Z1 -- "$archive" 2>/dev/null ;;
    7z) 7z l -ba -slt -- "$archive" 2>/dev/null | grep '^Path = ' | sed 's/^Path = //' ;;
    rar) unrar lb -- "$archive" 2>/dev/null ;;
    # No "--" on purpose: with "tf" (grouped short form of -t -f), tar
    # takes the NEXT token as the direct argument of -f -- a "--" there
    # is interpreted as the file name itself to open, not as end
    # of options, and tar fails with "--: No such file or directory". It's
    # not needed as protection anyway: $archive is always an
    # absolute path built by Omafiles itself, never loose user
    # text that could start with "-".
    tar|gz|tgz|bz2|tbz2|xz|txz) tar tf "$archive" 2>/dev/null ;;
    *) exit 1 ;;
  esac
}

prefix=""
[[ -n "$sub" ]] && prefix="${sub%/}/"

# Two passes instead of one -- necessary because the order in which list_raw
# outputs the entries is not guaranteed (some tools list the explicit
# directory entry BEFORE its children, others after, and 7z
# doesn't mark directories with a trailing "/" at all). With a single pass,
# if the folder entry "a" (with no children seen yet) was processed
# before "a/inside.txt", it was marked as a file and that result could no longer
# be corrected afterward by the "seen" -- 7z reproduced exactly this bug
# (a top-level folder came out as a file). Now everything is collected
# in is_dir_of[] and only printed at the end, so the order doesn't matter.
declare -A is_dir_of
order=()

while IFS= read -r rawpath; do
  explicit_dir=0
  [[ "$rawpath" == */ ]] && explicit_dir=1
  path="${rawpath%/}"
  [[ -z "$path" ]] && continue

  if [[ -n "$prefix" ]]; then
    [[ "$path" == "$prefix"* ]] || continue
    rel="${path#"$prefix"}"
  else
    rel="$path"
  fi
  [[ -z "$rel" ]] && continue

  first="${rel%%/*}"
  if [[ -z "${is_dir_of[$first]+x}" ]]; then
    order+=("$first")
    is_dir_of[$first]=0
  fi
  # A folder if: there are more segments below (always true no matter
  # what happens with the "/" flag), or the top-level entry itself came
  # marked as an explicit directory.
  if [[ "$first" != "$rel" || "$explicit_dir" == "1" ]]; then
    is_dir_of[$first]=1
  fi
done < <(list_raw)

for name in "${order[@]}"; do
  printf '%s\0%s\0' "$name" "${is_dir_of[$name]}"
done
