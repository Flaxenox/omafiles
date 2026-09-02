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
#   ./install.sh --no-keybinding   never touch the Hyprland keybindings
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
NO_KEYBINDING=0

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
  if [[ "$NO_KEYBINDING" == 1 ]]; then
    info "--no-keybinding given; leaving Hyprland bindings untouched."
    return 0
  fi
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
# Step 6 — summary
# ---------------------------------------------------------------------------
summary() {
  step "Done"
  local bin="${BIN_DIR}/omafiles"
  if [[ -x "$bin" ]]; then
    ok "Omafiles installed. Launch it with:  ${GREEN}${BOLD}omafiles${RESET}"
    if [[ "$NO_KEYBINDING" == 0 ]] && grep -q "SUPER + SHIFT + F" "${HOME}/.config/hypr/bindings.lua" 2>/dev/null; then
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
  --no-keybinding  Never modify the Omarchy Hyprland keybindings.
  -h, --help       Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)             ASSUME_YES=1 ;;
    --skip-build)      SKIP_BUILD=1 ;;
    --no-keybinding)   NO_KEYBINDING=1 ;;
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