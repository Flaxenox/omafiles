#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Omafiles — interactive TUI installer (dotfiles/AI-installer style)
#
#  1. Installs required packages (pacman, optional).
#  2. Builds Omafiles from source (cmake + ninja).
#  3. Installs it to ~/.local.
#  4. Registers the default file-manager / FileChooser integrations.
#  5. Asks (arrow-key Yes/No) whether to add the SUPER+SHIFT+F keybinding.
#
# Usage:
#   ./install.sh                interactive, arrow-key Yes/No controls
#   ./install.sh --yes          non-interactive, accept every default
#   ./install.sh --skip-build   reuse an existing build/
#   ./install.sh --uninstall       remove Omafiles (+ keybinding)
#   ./install.sh --uninstall --purge   also remove the dependency packages
#
# Safe to re-run: every step is idempotent.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

# ── styling ────────────────────────────────────────────────────────────────
BOLD=$'\033[1m'; DIM=$'\033[2m'; ITAL=$'\033[3m'; REV=$'\033[7m'
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; MAG=$'\033[35m'; RESET=$'\033[0m'
CHECK=$'\033[32m✓\033[0m'; CROSS=$'\033[31m✗\033[0m'; SKIP=$'\033[90m–\033[0m'; ARROW=$'\033[36m❯\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${REPO_DIR}/build"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local}"
BIN_DIR="${INSTALL_PREFIX}/bin"

# Installer options
ASSUME_YES=0
SKIP_BUILD=0
UNINSTALL=0
PURGE_DEPS=0

# Cursor hide/show + alternate screen buffer (ANSI) so the TUI takes over the
# whole terminal and restores it cleanly on exit.
hide_cursor(){ printf '\033[?25l'; }
show_cursor(){ printf '\033[?25h'; }
enter_alt(){ printf '\033[?1049h\033[2J\033[H'; }
leave_alt(){ printf '\033[?1049l'; }
SCREEN_INIT=0
cleanup(){ show_cursor; [[ "$SCREEN_INIT" == 1 ]] && leave_alt; }
trap cleanup EXIT

# ── message helpers ────────────────────────────────────────────────────────
bark()  { printf '%s\n' "$*"; }
info()  { printf '%s\n' "${CYAN}==>${RESET} $*"; }
ok()    { printf '  %s %s\n' "$CHECK" "$*"; }
warn()  { printf '  %s %s\n' "${YELLOW}!${RESET}" "$*"; }
fail()  { printf '  %s %s\n' "$CROSS" "$*"; }
die()   { printf '%s\n' "${RED}Error:${RESET} $*" >&2; exit 1; }
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

banner() {
  enter_alt; SCREEN_INIT=1; hide_cursor
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  (( cols < 60 )) && cols=60
  local hi=$'\033[38;5;45m' mid=$'\033[38;5;39m' lo=$'\033[38;5;32m'
  center(){  # center <text>  -> prints text padded to terminal width
    local vis=$(printf '%s' "$1" | sed -r 's/\x1b\[[0-9;]*m//g')
    local len=${#vis}; local pad=$(( (cols - len) / 2 )); (( pad < 0 )) && pad=0
    printf '%*s%s\n' "$pad" "" "$1"
  }
  # 5-row block letters, each 7 columns wide, unambiguous.
  local words=(O M A F I L E S)
  letter_row() {
    case "$g:$row" in
      O:0) printf ' █████ ';; O:1) printf '██   ██';; O:2) printf '██   ██';; O:3) printf '██   ██';; O:4) printf ' █████ ';;
      M:0) printf '██   ██';; M:1) printf '███████';; M:2) printf '██ █ ██';; M:3) printf '██   ██';; M:4) printf '██   ██' ;;
      A:0) printf ' █████ ';; A:1) printf '██   ██';; A:2) printf '███████';; A:3) printf '██   ██';; A:4) printf '██   ██' ;;
      F:0) printf '███████';; F:1) printf '██     ';; F:2) printf '█████  ';; F:3) printf '██     ';; F:4) printf '██     ' ;;
      I:0) printf '███████';; I:1) printf '  ██   ';; I:2) printf '  ██   ';; I:3) printf '  ██   ';; I:4) printf '███████' ;;
      L:0) printf '██     ';; L:1) printf '██     ';; L:2) printf '██     ';; L:3) printf '██     ';; L:4) printf '███████' ;;
      E:0) printf '███████';; E:1) printf '██     ';; E:2) printf '█████  ';; E:3) printf '██     ';; E:4) printf '███████' ;;
      S:0) printf ' █████ ';; S:1) printf '██     ';; S:2) printf ' █████ ';; S:3) printf '    ██ ';; S:4) printf ' █████ ' ;;
    esac
  }
  for ((row=0; row<5; row++)); do
    local grad
    (($row==0)) && grad=$hi; (($row==1)) && grad=$hi
    (($row==2)) && grad=$mid; (($row==3)) && grad=$mid; (($row==4)) && grad=$lo
    local line=""
    local g
    for g in "${words[@]}"; do
      line+="${grad}${BOLD}$(letter_row)${RESET} "
    done
    center "$line"
  done
  center "  ${BOLD}${hi}Omafiles${RESET} ${DIM}— interactive installer${RESET}  "

  # A centered info box whose width fits the longest line.
  local W=24 c_repo c_build
  c_repo="  repo:  $REPO_DIR  "; c_build="  build: $BUILD_DIR  "
  (( ${#c_repo} > W )) && W=${#c_repo}
  (( ${#c_build} > W )) && W=${#c_build}
  pad_to(){ printf '%-*s' "$W" "$1"; }
  center "${DIM}┌$(printf '─%.0s' $(seq 1 $W))┐${RESET}"
  center "${DIM}│${RESET}$(pad_to "$c_repo")${DIM}│${RESET}"
  center "${DIM}│${RESET}$(pad_to "$c_build")${DIM}│${RESET}"
  center "${DIM}└$(printf '─%.0s' $(seq 1 $W))┘${RESET}"
  printf '\n'
  show_cursor
}

# ── step tracker ───────────────────────────────────────────────────────────
declare -a _steps=()
begin_step(){ _steps+=("$1"); }
run_step(){  # run_step <label> <cmd...>   (uses _run_function / return codes)
  local label="$1"; shift
  local idx=$(( ${#_steps_done[@]} + 1 ))
  printf '%s %s[%s/%s]%s %s%s%s\n' "$ARROW" "$CYAN" "$idx" "${#_steps[@]}" "$RESET" "$BOLD" \
    "$(printf '%s' "$label" | tr 'A-Z' 'a-z' | sed 's/^./\U&/')" "$RESET" 
  local start=$SECONDS
  if "$@"; then
    printf '\r\033[1A\033[K  %s %s[%s/%s]%s %s %s(%ss)%s\n' "$CHECK" "$CYAN" "$idx" \
      "${#_steps[@]}" "$RESET" "$label" "${DIM}" "$(( SECONDS-start ))" "$RESET"
    _steps_done+=("$label")
  else
    printf '\r\033[1A\033[K  %s %s[%s/%s]%s %s %s(failed)%s\n' "$CROSS" "$CYAN" "$idx" \
      "${#_steps[@]}" "$RESET" "$label" "${DIM}" "$RESET"
    _steps_done+=("$label")
    return 1
  fi
}
declare -a _steps_done=()

# ── arrow-key Yes/No selector ──────────────────────────────────────────────
# Prints the prompt and a highlighted [ Yes ] / [ No ] pair. Arrow keys toggle,
# Enter confirms, y/n are shortcuts. Returns 0=yes, 1=no.
confirm() {
  local prompt="$1" default="${2:-y}"
  if [[ "$ASSUME_YES" == 1 ]]; then
    printf '  %s %s\n' "$([ "$default" == y ] && printf '%s' "$CHECK" || printf '%s' "$SKIP")" "${DIM}→ $prompt → $([ "$default" == y ] && echo yes || echo no)${RESET}"
    [[ "$default" == [yY] ]] && return 0
    return 1
  fi

  local sel=1; [[ "$default" == [nN] ]] && sel=0
  local key dir
  hide_cursor
  printf '  %s  ' "$prompt"
  render_choice "$sel" "$default"
  if [[ -t 0 ]]; then
    stty raw -echo 2>/dev/null || stty -icanon -echo 2>/dev/null
    while :; do
      key=""; IFS= read -r -n1 key 2>/dev/null || continue
      if [[ "$key" == $'\x1b' ]]; then            # ESC [ A/B/C/D arrow keys
        IFS= read -r -n1 _b 2>/dev/null || true
        IFS= read -r -n1 dir 2>/dev/null || true
        case "$dir" in A|D) sel=1;; C|B) sel=0;; esac   # Left/Up → Yes, Right/Down → No
      elif [[ "$key" == $'\x0a' || "$key" == $'\x0d' || -z "$key" ]]; then
        break                                     # Enter confirms
      elif [[ "$key" == [yY] ]]; then sel=1
      elif [[ "$key" == [nN] ]]; then sel=0
      fi
      printf '\r\033[2K  %s  ' "$prompt"; render_choice "$sel" "$default"
    done
    stty sane 2>/dev/null || stty echo icanon 2>/dev/null
  else                                            # non-TTY: plain line input
    local ans
    while :; do
      read -r -p "" ans
      case "$(printf '%s' "${ans:-$default}" | tr '[:upper:]' '[:lower:]')" in
        y|yes) sel=1; break;; n|no) sel=0; break;;
        *) printf '  %s\n' "${YELLOW}Please answer y or n.${RESET}";;
      esac
    done
  fi
  show_cursor
  printf '\r\033[2K  %s  %s\n' "$prompt" "$([ "$sel" == 1 ] && printf '%s' "${GREEN}Yes${RESET}" || printf '%s' "${DIM}No${RESET}")"
  [[ "$sel" == 1 ]] && return 0
  return 1
}

render_choice() {
  local sel="$1" default="$2"
  local y n
  # [ Yes ][ No ] — Yes on the left. Left/Up → Yes, Right/Down → No.
  if [[ "$sel" == 1 ]]; then
    y="\033[7;1m Yes \033[0m"; n="  No  "
  else
    y="  Yes  "; n="\033[7;1m  No  \033[0m"
  fi
  local yt=$(printf '%b' "$y") nt=$(printf '%b' "$n")
  printf '%b%b' "$yt" "$nt"
}

# ──────────────────────────────────────────────────────────────────────────
# Dependency install
# ──────────────────────────────────────────────────────────────────────────
install_deps() {
  if ! have_cmd pacman; then
    warn "pacman not found — this targets Arch Linux. Install the deps from the README manually."
    return 0
  fi
  local pkgs=(qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject cmake ninja)
  local missing=()
  for p in "${pkgs[@]}"; do pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if (( ${#missing[@]} == 0 )); then
    ok "All required packages already installed"
    return 0
  fi
  printf '  %s Missing packages: %s\n' "${YELLOW}!${RESET}" "${YELLOW}${missing[*]}${RESET}"
  if ! confirm "Install the missing packages with pacman?" y; then
    warn "Skipped dependency install — a build may still work."
    return 0
  fi
  info "Running: ${DIM}sudo pacman -S --needed ${missing[*]}${RESET}"
  sudo pacman -S --needed "${missing[@]}" && ok "Dependencies installed"
}

# ──────────────────────────────────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────────────────────────────────
build() {
  if [[ "$SKIP_BUILD" == 1 ]]; then
    [[ -f "$BUILD_DIR/omafiles-standalone" ]] || warn "No binary in build/ (nothing to reuse)."
    return 0
  fi
  have_cmd cmake || die "cmake not found — install cmake and ninja."
  have_cmd ninja || die "ninja not found — install cmake and ninja."
  [[ -f "$BUILD_DIR/build.ninja" ]] || {
    info "Configuring…"
    cmake -S "$REPO_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DOMAFILES_BIN_INSTALL_DIR="${INSTALL_PREFIX}/bin" \
      -DOMAFILES_QML_INSTALL_DIR="${INSTALL_PREFIX}/lib/qt6/qml" \
      -DOMAFILES_DATA_INSTALL_DIR="${INSTALL_PREFIX}/share"
  }
  info "Compiling… (may take a few minutes)"
  cmake --build "$BUILD_DIR"
  ok "Build finished"
}

# ──────────────────────────────────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────────────────────────────────
install_app() {
  info "Running: ${DIM}cmake --install ${BUILD_DIR}${RESET}"
  cmake --install "$BUILD_DIR" \
    -DOMAFILES_BIN_INSTALL_DIR="${INSTALL_PREFIX}/bin" \
    -DOMAFILES_QML_INSTALL_DIR="${INSTALL_PREFIX}/lib/qt6/qml" \
    -DOMAFILES_DATA_INSTALL_DIR="${INSTALL_PREFIX}/share"
  ok "Installed to ${INSTALL_PREFIX} (${BIN_DIR}/omafiles)"
}

# ──────────────────────────────────────────────────────────────────────────
# Integrations (default file manager / FileChooser portal)
# ──────────────────────────────────────────────────────────────────────────
integrations() {
  local script="${REPO_DIR}/scripts/install-integrations.sh"
  if [[ -x "$script" ]]; then
    info "Registering default file manager, FileManager1 & FileChooser portal…"
    "$script" && ok "Integrations set" || warn "Integration script reported an error."
  else
    warn "scripts/install-integrations.sh not found — the app runs it on first launch anyway."
  fi
}

# ──────────────────────────────────────────────────────────────────────────
# Keybinding (always interactive)
# ──────────────────────────────────────────────────────────────────────────
# Write a binding for $1 (a combo string) into $BIND_FILE, unbinding conflicts.
# $BIND_FILE and $BIND_CMD are globals set by add_keybinding().
bind_keybinding() {
  local combo="$1"
  if grep -qE "${combo//+/.*}" "$BIND_FILE" 2>/dev/null; then
    printf '\n%s\n' "hl.unbind(\"$combo\")  -- previously used elsewhere; overridden for Omafiles" >> "$BIND_FILE"
  fi
  {
    printf '\n-- Omafiles (added by install.sh)\n'
    printf 'o.bind("%s", "OmaFiles", "%s")\n' "$combo" "$BIND_CMD"
  } >> "$BIND_FILE"
  ok "Keybinding ${combo} added to ${BIND_FILE}"

  if have_cmd hyprctl; then
    if hyprctl reload >/dev/null 2>&1; then
      local errs; errs="$(hyprctl configerrors 2>/dev/null | tr -d '\r')"
      if [[ -z "$errs" || "$errs" =~ ^$ || "$errs" == *"config file is good"* ]]; then
        ok "Hyprland reloaded clean"
      else
        warn "Hyprland config errors:\n$errs"
      fi
    else
      warn "hyprctl reload failed — is a Hyprland session running?"
    fi
  fi
}

# Ask which keybinding to use. Reads the top-5 free combos (not already bound in
# BIND_FILE) plus a "define your own" option. Sets $combo. Returns 1 if skipped.
pick_keybinding() {
  # Candidate combos, most ergonomic first. Only the free ones are offered.
  local candidates=(
    "SUPER + F"   "SUPER + E"   "SUPER + O"   "SUPER + M"
    "SUPER + D"   "ALT + F"     "ALT + E"     "SUPER + RETURN"
    "SUPER + SLASH" "SUPER + SPACE"
  )
  local free=() i c
  for c in "${candidates[@]}"; do
    grep -qF "$c" "$BIND_FILE" 2>/dev/null || free+=("$c")
    (( ${#free[@]} == 5 )) && break
  done
  local n=${#free[@]}

  printf '\n  %s Choose a launcher keybinding:\n' "${CYAN}==>${RESET}"
  if (( n == 0 )); then
    warn "No free candidate keybindings found — you can define a custom one."
  else
    for ((i=0; i<n; i++)); do
      printf '    %s[%s]%s  %s\n' "${GREEN}" "$i" "${RESET}" "${free[i]}"
    done
  fi
  printf '    %s[c]%s  define your own\n' "${GREEN}" "${RESET}"
  printf '    %s[s]%s  skip\n' "${GREEN}" "${RESET}"

  local choice
  while :; do
    printf '  Pick [0-%s, c=custom, s=skip]: ' "$(( n-1 ))"
    IFS= read -r -p "" choice
    case "$choice" in
      s|S) return 1 ;;
      c|C) break ;;
      *) if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice < n )); then
           combo="${free[choice]}"; return 0
         fi
         printf '    %s Invalid choice — try again.%s\n' "${YELLOW}" "${RESET}" ;;
    esac
  done

  # Define your own.
  while :; do
    printf '  Type your keybinding (e.g. SUPER + CTRL + O): '
    IFS= read -r -p "" combo
    [[ -n "$combo" ]] && break
  done
  return 0
}

add_keybinding() {
  BIND_FILE="${HOME}/.config/hypr/bindings.lua"
  BIND_CMD="omafiles --new-window"
  local combo="SUPER + SHIFT + F"

  if [[ ! -f "$BIND_FILE" ]]; then
    info "No Hyprland bindings file found (${BIND_FILE}) — skipping keybinding."
    return 0
  fi

  # There is always a choice: absent → ask to add; already present → ask to keep.
  if grep -qF "$combo" "$BIND_FILE" 2>/dev/null; then
    ok "Keybinding ${combo} is already set."
    if confirm "Keep the existing ${combo} launcher keybinding?" y; then
      ok "Keeping ${combo}."
      return 0
    fi
    # User said no to the existing one → offer to pick a different keybinding.
  else
    info "Optional: bind ${BOLD}${combo}${RESET} → ${DIM}${BIND_CMD}${RESET}"
    if confirm "Add the ${combo} launcher keybinding?" y; then
      bind_keybinding "$combo"
      return 0
    fi
    # User said no to the default → offer to pick a different keybinding.
  fi

  if confirm "Set a different launcher keybinding instead?" y; then
    combo=""
    if pick_keybinding; then
      bind_keybinding "$combo"
    else
      info "OK — skipping the keybinding (add one later in ${BIND_FILE})."
    fi
  else
    info "OK — leaving ${BIND_FILE} untouched."
  fi
}
# ──────────────────────────────────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────────────────────────────────
uninstall() {
  local data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
  local qml_root="${OMAFILES_QML_INSTALL_DIR:-$HOME/.local/lib/qt6/qml}"
  local app_id="io.github.percius04.omafiles"
  local bind_file="${HOME}/.config/hypr/bindings.lua"

  info "Removing the binary, resource tree, icons and integrations…"
  rm -f  "${BIN_DIR}/omafiles"
  rm -rf "${data_root}/omafiles" "${state_root}/omafiles" "${qml_root}/Omafiles"
  find "${data_root}/applications" -name "omafiles*.desktop" -delete 2>/dev/null
  find "${data_root}/dbus-1/services" \( -name "${app_id}.service" -o \
    -name "org.freedesktop.FileManager1.service" -o \
    -name "org.freedesktop.impl.portal.desktop.omafiles.service" \) -delete 2>/dev/null
  rm -f  "${data_root}/xdg-desktop-portal/portals/omafiles.portal"
  rm -f  "${data_root}/icons/hicolor/scalable/apps/omafiles.svg" \
         "${data_root}/icons/hicolor/scalable/apps/omafiles-symbolic.svg"
  for sz in 32 48 64 128 256; do
    rm -f "${data_root}/icons/hicolor/${sz}x${sz}/apps/omafiles.png"
  done
  # Drop the FileChooser portal lines this project adds.
  for conf in "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf" \
              "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/portals.conf"; do
    [[ -f "$conf" ]] && sed -i '/org.freedesktop.impl.portal.FileChooser=omafiles/d' "$conf" 2>/dev/null
  done
  ok "Application and data removed"

  # Keybinding: only remove the block THIS installer added.
  local marker='-- Omafiles (added by install.sh)'
  if [[ -f "$bind_file" ]] && grep -qF "$marker" "$bind_file" 2>/dev/null; then
    if confirm "Remove the ${BOLD}SUPER + SHIFT + F${RESET} keybinding?" y; then
      sed -i "/^$marker$/,/^o\.bind(\"SUPER + SHIFT + F\"/d" "$bind_file" 2>/dev/null
      sed -i '/hl\.unbind("SUPER + SHIFT + F")  -- previously used elsewhere/d' "$bind_file" 2>/dev/null
      ok "Keybinding removed"
      have_cmd hyprctl && hyprctl reload >/dev/null 2>&1 && ok "Hyprland reloaded"
    fi
  fi

  # Dependencies (only if asked).
  if [[ "$PURGE_DEPS" == 1 ]]; then
    purge_deps
  elif have_cmd pacman && confirm "Also remove the dependency packages (qt6, etc.)?" n; then
    purge_deps
  fi
}

purge_deps() {
  local pkgs=(qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject)
  info "Running: ${DIM}sudo pacman -Rns ${pkgs[*]}${RESET}"
  sudo pacman -Rns "${pkgs[@]}" && ok "Dependency packages removed" || warn "pacman reported issues."
}

# ──────────────────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────────────────
summary() {
  printf '\n' && info "All done"
  if [[ -x "${BIN_DIR}/omafiles" ]]; then
    ok "Launch Omafiles with:  ${BOLD}${GREEN}omafiles${RESET}"
    if grep -q "SUPER + SHIFT + F" "${HOME}/.config/hypr/bindings.lua" 2>/dev/null; then
      ok "Launcher keybinding ready:  ${BOLD}SUPER + SHIFT + F${RESET}"
    fi
  else
    warn "Install did not finish — review the output above."
  fi
}

# ──────────────────────────────────────────────────────────────────────────
# Arguments
# ──────────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Omafiles interactive installer

Usage: ./install.sh [options]

Options:
  --yes          Non-interactive: accept every default choice.
  --skip-build   Reuse an existing build/ (skip the cmake build).
  --uninstall    Remove Omafiles, its data and the keybinding (asks about deps).
  --purge        With --uninstall: also remove the dependency packages, no prompt.
  -h, --help     Show this help.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)           ASSUME_YES=1 ;;
    --skip-build)    SKIP_BUILD=1 ;;
    --uninstall)     UNINSTALL=1 ;;
    --purge)         PURGE_DEPS=1 ;;
    -h|--help)       usage ;;
    *) warn "Unknown option: $1"; usage ;;
  esac
  shift
done

# ──────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────
banner

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ "$ASSUME_YES" == 0 ]] && ! confirm "Remove Omafiles from this system?" n; then
    echo "  Aborted."; exit 0
  fi
  begin_step "Uninstall"
  if uninstall; then
    _steps_done+=("Uninstall")
    ok "Uninstall complete"
  else
    _steps_done+=("Uninstall")
    warn "Uninstall had issues"
  fi
  exit 0
fi

if [[ "$ASSUME_YES" == 0 ]]; then
  if ! confirm "Install Omafiles to ${INSTALL_PREFIX}?" y; then
    if confirm "Install to a different directory instead?" y; then
      while :; do
        read -r -p "  Enter install prefix (e.g. /opt/omafiles or ~/apps): " INSTALL_PREFIX
        INSTALL_PREFIX="${INSTALL_PREFIX/#\~/$HOME}"
        INSTALL_PREFIX="${INSTALL_PREFIX%/}"
        [[ -n "$INSTALL_PREFIX" ]] && break
      done
      BIN_DIR="${INSTALL_PREFIX}/bin"
      printf '  %s Using install prefix:  %s\n' "${CYAN}==>${RESET}" "${BOLD}${INSTALL_PREFIX}${RESET}"
    else
      echo "  Aborted."; exit 0
    fi
  fi
fi

[[ -d "$BUILD_DIR" ]] || mkdir -p "$BUILD_DIR"
printf '\n'

begin_step "Dependencies"
begin_step "Build"
begin_step "Install"
begin_step "Integrations"
begin_step "Keybinding"
run_step "Dependencies" install_deps   || true
run_step "Build"        build          || true
run_step "Install"      install_app    || true
run_step "Integrations" integrations   || true
run_step "Keybinding"   add_keybinding || true
summary
