#!/bin/bash
# Empties ALL active trashes: the home one (~/.local/share/Trash) plus the
# .Trash-$UID of any mount point that has it (XDG Trash spec: a
# file deleted from a disk that is not $HOME's goes to THAT disk's
# trash). Self-contained: Phase 16 migrated the root DISCOVERY to
# FileOperations.trashRoots() (native) and removed trash-roots.sh, but this script
# -- which does the BULK deletion with `rm -rf`, simpler than N native
# removes -- kept calling it internally, so it got no root and
# did NOT empty anything (exiting successfully). Now it discovers the roots itself.

uid=$(id -u)
st=0
shopt -s nullglob dotglob

empty_root() {
  local trash_root="$1"
  for f in "$trash_root/files"/* "$trash_root/info"/*.trashinfo; do
    [[ "$f" == */. || "$f" == */.. ]] && continue
    [[ -e "$f" || -L "$f" ]] || continue
    rm -rf -- "$f" || st=1
  done
}

home_trash="$HOME/.local/share/Trash"
[[ -d "$home_trash" ]] && empty_root "$home_trash"

# .Trash-$UID of each mount point that isn't "/" nor an ancestor of $HOME
# (those are already "the same disk as home", covered above).
while IFS= read -r mp; do
  [[ "$mp" == "/" ]] && continue
  [[ "$HOME" == "$mp"* ]] && continue
  cand="$mp/.Trash-$uid"
  [[ -d "$cand" ]] && empty_root "$cand"
done < <(findmnt -rn -o TARGET 2>/dev/null)

exit $st
