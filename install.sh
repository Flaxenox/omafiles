#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Omafiles TUI installer
#
# An interactive, terminal-based installer for Arch Linux (Hyprland / Omarchy):
#  1. Installs the required packages (pacman).
#  2. Builds Omafiles from source (cmake + ninja).
#  3. Installs it to ~/.local (no root needed for the app itself).
#  4. Prompts whether to add the SUPER+SHIFT+F launcher keybinding to the
#     Omarchy Hyprland keybindings.
#
# Usage:
#   ./install.sh               interactive (asks before privileged steps)
#   ./install.sh --yes         non-interactive, accept every default
#   ./install.sh --skip-build  re-run only the integration/keybinding steps
#   ./install.sh --uninstall / --uninstall --purge   remove Omafiles (and deps)
#
# Safe to re-run: every step is idempotent.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${REPO_DIR}/build"
BIN_DIR="${HOME}/.local/bin"

# Installer options
ASSUME_YES=0
SKIP_BUILD=0
UNINSTALL=0
PURGE_DEPS=0

# ---------------------------------------------------------------------------
# TUI helpers
# ---------------------------------------------------------------------------
info()  { printf '%s\n' "${CYAN}==>${RESET} $*"; }
step()  { printf '\n%s\n' "${BOLD}${CYAN}── $* ──${RESET}"; }
ok()    { printf '%s\n' "    ${GREEN}✓${RESET} $*"; }
warn()  { printf '%s\n' "    ${YELLOW}!${RESET} $*" >&2; }
fail()  { printf '%s\n' "    ${RED}✗${RESET} $*" >&2; }

die() { printf '%s\n' "${RED}Error:${RESET} $*" >&2; exit 1; }

# Ask a yes/no question, defaulting to $1. Returns 0=yes, 1=no.
confirm() {
  local prompt="$1" default="$2" ans
  if [[ "$ASSUME_YES" == 1 ]]; then
    printf '%s (y/N) → %s\n' "$prompt" "$default"
    [[ "$default" == "y" || "$default" == "Y" ]] && return 0
    return 1
  fi
  while true; do
    read -r -p "$prompt [y/N] " ans
    answer="$(printf '%s' "${ans:-$default}" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) printf '%s\n' "    ${YELLOW}Please answer y or n.${RESET}" ;;
    esac
  done
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Step 1 — dependencies
# ---------------------------------------------------------------------------
install_deps() {
  step "Step 1: Dependencies"
  if ! have_cmd pacman; then
    fail "pacman not found — this installer targets Arch Linux. Install the packages"
    fail "listed in README.md's Dependencies section manually, then re-run."
    return 1
  fi
  info "Checking required packages…"
  local pkgs=(
    qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject
    cmake ninja
  )
  local missing=()
  for p in "${pkgs[@]}"; do
    pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    ok "All required packages already installed."
    return 0
  fi
  printf '%s' "    Missing: ${YELLOW}${missing[*]}${RESET}\n"
  if ! confirm "Install missing packages with sudo pacman?" "y"; then
    warn "Skipping dependency install — building may fail without them."
    return 0
  fi
  info "Running: sudo pacman -S --needed ${missing[*]}"
  sudo pacman -S --needed "${missing[@]}" || fail "pacman install failed."
  ok "Dependencies installed."
}

# ---------------------------------------------------------------------------
# Step 2 — build
# ---------------------------------------------------------------------------
build() {
  step "Step 2: Build"
  if [[ "$SKIP_BUILD" == 1 ]]; then
    info "--skip-build given; assuming an existing build."
    [[ -f "${BUILD_DIR}/omafiles-standalone" ]] || warn "No binary found at build/. Consider building."
    return 0
  fi
  for t in cmake ninja; do
    have_cmd "$t" || die "Build tool '$t' not found. Install cmake and ninja."
  done
  if [[ ! -f "$BUILD_DIR/build.ninja" ]]; then
    info "Configuring with cmake (Ninja, Release)…"
    cmake -S "$REPO_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release
  else
    info "Build directory already configured."
  fi
  info "Compiling… (this may take a few minutes)"
  cmake --build "$BUILD_DIR"
  ok "Build finished."
}

# ---------------------------------------------------------------------------
# Step 3 — install
# ---------------------------------------------------------------------------
install_app() {
  step "Step 3: Install to ~/.local"
  info "Running: cmake --install ${BUILD_DIR}"
  cmake --install "$BUILD_DIR" || die "Install failed."
  if [[ -x "$BIN_DIR/omafiles" ]]; then
    ok "Installed: $BIN_DIR/omafiles"
  else
    warn "Binary not found at expected $BIN_DIR/omafiles — check OMAFILES_BIN_INSTALL_DIR."
  fi
}

# ---------------------------------------------------------------------------
# Step 4 — self-registration integrations
# ---------------------------------------------------------------------------
integrations() {
  step "Step 4: Default file-manager integrations"
  local script="${REPO_DIR}/scripts/install-integrations.sh"
  if [[ -x "$script" ]]; then
    info "Registering default file manager, FileManager1 & FileChooser portal…"
    "$script" "$@" && ok "Integrations set up." || fail "Integration script reported an error."
  else
    warn "scripts/install-integrations.sh not found — skipping (the app runs it on first launch anyway)."
  fi
}

# ---------------------------------------------------------------------------
# Step 5 — optional Omarchy keybinding
# ---------------------------------------------------------------------------
add_keybinding() {
  step "Step 5: Omarchy keybinding"
  local bind_file="${HOME}/.config/hypr/bindings.lua"
  local combo="SUPER + SHIFT + F"
  local cmd="omafiles --new-window"

  if [[ ! -f "$bind_file" ]]; then
    warn "No $bind_file (Omarchy bindings) found — not a Hyprland/Omarchy setup? Skipping."
    return 0
  fi

  if grep -qF "$combo" "$bind_file" 2>/dev/null; then
    ok "Keybinding ${combo} is already present in $bind_file."
    return 0
  fi

  if ! confirm "Add a ${combo} keybinding to launch Omafiles in $bind_file?" "y"; then
    info "Skipping keybinding."
    return 0
  fi

  # Prepend an unbind if the combo is already used for something else, so the
  # new binding overrides it cleanly (hyprland.md rule: unbind before rebind).
  if grep -qE "SUPER[^,;]*SHIFT[^,;]*F|SHIFT[^,;]*SUPER[^,;]*F" "$bind_file" 2>/dev/null; then
    printf '\n%s\n' "hl.unbind(\"$combo\")  -- was already bound; overridden for Omafiles" >> "$bind_file"
  fi

  {
    printf '\n-- Omafiles (added by install.sh)\n'
    printf 'o.bind("%s", "OmaFiles", "%s")\n' "$combo" "$cmd"
  } >> "$bind_file"
  ok "Appended ${combo} → ${cmd} to $bind_file."

  # Apply & validate.
  if have_cmd hyprctl; then
    if hyprctl reload >/dev/null 2>&1; then
      local errs
      errs="$(hyprctl configerrors 2>/dev/null | tr -d '\r')"
      if [[ -z "$errs" || "$errs" =~ ^$ || "$errs" == "config file is good" ]]; then
        ok "Hyprland reloaded with no config errors."
      else
        warn "Hyprland reported config errors after reload:\n$errs"
      fi
    else
      warn "hyprctl reload failed — is a Hyprland session running?"
    fi
  else
    info "hyprctl not found — keybinding will apply on next Hyprland reload/login."
  fi
}

# ---------------------------------------------------------------------------
# Uninstall — remove the app, its data, and optionally the dependencies
# ---------------------------------------------------------------------------
uninstall() {
  step "Uninstall Omafiles"
  local data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}"
  local qml_root="${OMAFILES_QML_INSTALL_DIR:-$HOME/.local/lib/qt6/qml}"
  local app_id="io.github.percius04.omafiles"
  local bind_file="${HOME}/.config/hypr/bindings.lua"

  info "Removing the binary, resource tree, icons and integrations…"

  rm -f "${BIN_DIR}/omafiles"
  rm -rf "${data_root}/omafiles"
  rm -rf "${state_root}/omafiles"
  rm -rf "${qml_root}/Omafiles"
  find "${data_root}/applications" -name "omafiles*.desktop" -delete 2>/dev/null
  find "${data_root}/dbus-1/services" \( -name "${app_id}.service" -o -name "org.freedesktop.FileManager1.service" -o -name "org.freedesktop.impl.portal.desktop.omafiles.service" \) -delete 2>/dev/null
  rm -f "${data_root}/xdg-desktop-portal/portals/omafiles.portal"
  rm -f "${data_root}/icons/hicolor/scalable/apps/omafiles.svg" \
        "${data_root}/icons/hicolor/scalable/apps/omafiles-symbolic.svg"
  for sz in 32 48 64 128 256; do
    rm -f "${data_root}/icons/hicolor/${sz}x${sz}/apps/omafiles.png"
  done

  # Drop the FileChooser portal preference lines this project adds.
  for conf in "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/hyprland-portals.conf" \
              "${XDG_CONFIG_HOME:-$HOME/.config}/xdg-desktop-portal/portals.conf"; do
    [[ -f "$conf" ]] && sed -i '/org.freedesktop.impl.portal.FileChooser=omafiles/d' "$conf" 2>/dev/null
  done

  ok "Application and data removed."

  # Remove the keybinding added for SUPER+SHIFT+F, if present. Only the block
  # THIS installer wrote is removed -- a binding the user added by hand (with a
  # different comment/marker) is left alone.
  local oma_marker='-- Omafiles (added by install.sh)'
  local combo_line='o.bind("SUPER + SHIFT + F"'
  if [[ -f "$bind_file" ]] && grep -qF "$oma_marker" "$bind_file" 2>/dev/null; then
    if confirm "Remove the SUPER + SHIFT + F keybinding from $bind_file?" "y"; then
      sed -i "/^$oma_marker$/,/^o\.bind(\"SUPER + SHIFT + F\"/d" "$bind_file" 2>/dev/null
      sed -i '/hl\.unbind("SUPER + SHIFT + F")  -- was already bound; overridden for Omafiles/d' "$bind_file" 2>/dev/null
      ok "Removed SUPER + SHIFT + F binding."
      if have_cmd hyprctl; then
        hyprctl reload >/dev/null 2>&1 && ok "Hyprland reloaded."
      fi
    fi
  elif [[ -f "$bind_file" ]] && grep -qF "$combo_line" "$bind_file" 2>/dev/null; then
    info "A SUPER + SHIFT + F binding exists but wasn't added by this installer — leaving it as-is."
  fi

  # Optionally remove the dependencies the installer brought in.
  if [[ "$PURGE_DEPS" == 1 ]]; then
    remove_deps_via_pacman
  elif ! have_cmd pacman; then
    warn "pacman not found — dependency removal skipped."
  elif confirm "Also remove the packages this installer depends on (qt6, etc.)?" "n"; then
    remove_deps_via_pacman
  else
    info "Leaving system packages in place."
  fi

  step "Uninstall complete"
}

remove_deps_via_pacman() {
  local pkgs=(
    qt6-base qt6-declarative qt6-webengine glib2 zip unzip python-gobject
  )
  info "Running: sudo pacman -Rns ${pkgs[*]}"
  sudo pacman -Rns "${pkgs[@]}" || warn "pacman removal reported issues."
  ok "Dependencies removed."
}

# ---------------------------------------------------------------------------
# Step 6 — summary
# ---------------------------------------------------------------------------
summary() {
  step "Done"
  local bin="${BIN_DIR}/omafiles"
  if [[ -x "$bin" ]]; then
    ok "Omafiles installed. Launch it with:  ${GREEN}${BOLD}omafiles${RESET}"
    if [[ "$ASSUME_YES" == 0 ]] && grep -q "SUPER + SHIFT + F" "${HOME}/.config/hypr/bindings.lua" 2>/dev/null; then
      ok "Launcher keybinding ready:  ${BOLD}SUPER + SHIFT + F${RESET}"
    fi
  else
    warn "Install did not complete — review the messages above."
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Omafiles TUI installer

Usage: ./install.sh [options]

Options:
  --yes            Non-interactive: accept every default choice.
  --skip-build     Skip the cmake build (assume an existing build/).
  --uninstall      Remove Omafiles, its data and the keybinding. Asks whether
                   to also remove the dependencies it needs.
  --purge          With --uninstall: also remove the dependencies without asking.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)             ASSUME_YES=1 ;;
    --skip-build)      SKIP_BUILD=1 ;;
    --uninstall)       UNINSTALL=1 ;;
    --purge)           PURGE_DEPS=1 ;;
    -h|--help)         usage; exit 0 ;;
    *)                 warn "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Banner + run
# ---------------------------------------------------------------------------
step "Omafiles installer"
info "Repo:    ${BOLD}$REPO_DIR${RESET}"
info "Build:   ${BOLD}$BUILD_DIR${RESET}"

if [[ "$UNINSTALL" == 1 ]]; then
  if [[ "$ASSUME_YES" == 0 ]] && ! confirm "Remove Omafiles and its data from this system?" "n"; then
    echo "Aborted."; exit 0
  fi
  uninstall
  exit 0
fi

if [[ "$ASSUME_YES" == 0 && "$SKIP_BUILD" == 0 ]]; then
  printf '\n'
  if ! confirm "This will build and install Omafiles. Continue?" "y"; then
    echo "Aborted."; exit 0
  fi
fi

[[ -d "$BUILD_DIR" ]] || mkdir -p "$BUILD_DIR"

install_deps
build
install_app
integrations
add_keybinding
summary