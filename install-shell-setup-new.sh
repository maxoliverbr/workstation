#!/usr/bin/env bash
# Faster Fedora/RHEL shell setup installer.
# Run: bash install-shell-setup-new.sh [--debug]

set -euo pipefail

DEBUG=0
for arg in "$@"; do
  if [ "$arg" = "--debug" ]; then
    DEBUG=1
  fi
done

if [ "$DEBUG" = "1" ]; then
  exec 3>&1
else
  exec 3>/dev/null
fi

log() { printf '==> %s\n' "$*"; }
run_quiet() { if [ "$DEBUG" = "1" ]; then "$@"; else "$@" >&3 2>&3; fi; }
dnf_quiet() { run_quiet sudo dnf "$@"; }

FONT_DIR="${HOME}/.local/share/fonts"
CONFIG_DIR="${HOME}/.config"
LOCAL_BIN="${HOME}/.local/bin"
EXTENSIONS_GNOME_ORG="https://extensions.gnome.org"
ARCH="$(uname -m)"

mkdir -p "$LOCAL_BIN"
export PATH="${LOCAL_BIN}:${PATH}"

log "Refreshing sudo credentials..."
sudo -v

# -----------------------------
# DNF (single bulk transaction)
# -----------------------------
declare -a DNF_QUEUE=()
declare -A DNF_SEEN=()

queue_dnf_pkg() {
  local cmd="$1"
  local pkg="${2:-$1}"
  local label="${3:-$pkg}"
  if command -v "$cmd" >/dev/null 2>&1; then
    log "$label already installed, skipping."
    return
  fi
  if [ -z "${DNF_SEEN[$pkg]+x}" ]; then
    DNF_QUEUE+=("$pkg")
    DNF_SEEN[$pkg]=1
  fi
}

queue_dnf_pkg zsh
queue_dnf_pkg ranger
queue_dnf_pkg gh
queue_dnf_pkg git
queue_dnf_pkg flatpak
queue_dnf_pkg podman

# System tools
queue_dnf_pkg btop
queue_dnf_pkg duf
queue_dnf_pkg ncdu
queue_dnf_pkg timeshift

# Security/network
queue_dnf_pkg age
queue_dnf_pkg nmap

# Terminal tools
queue_dnf_pkg tmux
queue_dnf_pkg fzf
queue_dnf_pkg bat
queue_dnf_pkg rg ripgrep ripgrep
queue_dnf_pkg fd fd-find fd
queue_dnf_pkg zoxide
queue_dnf_pkg atuin

# Dev tools / script deps
queue_dnf_pkg yq
queue_dnf_pkg direnv
queue_dnf_pkg jq
queue_dnf_pkg unzip

# Only needed if Claude Code is missing and npm is missing.
if ! command -v claude >/dev/null 2>&1 && ! command -v npm >/dev/null 2>&1; then
  queue_dnf_pkg npm nodejs nodejs
fi

if [ "${#DNF_QUEUE[@]}" -gt 0 ]; then
  log "Installing missing DNF packages in one transaction..."
  dnf_quiet install -y "${DNF_QUEUE[@]}"
else
  log "No missing DNF packages."
fi

# -----------------------------
# zsh defaults
# -----------------------------
if [ -x "$(command -v zsh)" ] && [ "${SHELL:-}" != "$(command -v zsh)" ]; then
  log "Changing default shell to zsh..."
  run_quiet chsh -s "$(command -v zsh)"
fi

# -----------------------------
# Fonts
# -----------------------------
if compgen -G "$FONT_DIR/RobotoMono*.ttf" >/dev/null; then
  log "Roboto Mono Nerd Font already installed, skipping."
else
  log "Installing Roboto Mono Nerd Font..."
  mkdir -p "$FONT_DIR"
  tmp_font="$(mktemp -d)"
  trap 'rm -rf "$tmp_font"' EXIT
  curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/RobotoMono.zip" -o "$tmp_font/RobotoMono.zip"
  unzip -qo "$tmp_font/RobotoMono.zip" -d "$tmp_font"
  cp "$tmp_font"/*.ttf "$FONT_DIR/" 2>/dev/null || true
  run_quiet fc-cache -f
fi

# -----------------------------
# Starship + config
# -----------------------------
if command -v starship >/dev/null 2>&1; then
  log "Starship already installed, skipping binary install."
else
  log "Installing Starship..."
  run_quiet bash -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y'
  export PATH="${LOCAL_BIN}:${PATH}"
fi

if [ -f "$CONFIG_DIR/starship.toml" ]; then
  log "Starship config exists, skipping preset."
else
  log "Setting Starship Catppuccin preset..."
  mkdir -p "$CONFIG_DIR"
  starship preset catppuccin-powerline -o "$CONFIG_DIR/starship.toml"
fi

path_line='export PATH="${HOME}/.local/bin:${PATH}"'
starship_init='eval "$(starship init zsh)"'
if [ -f "${HOME}/.zshrc" ]; then
  grep -q '.local/bin' "${HOME}/.zshrc" || { echo "" >> "${HOME}/.zshrc"; echo "$path_line" >> "${HOME}/.zshrc"; }
  grep -q 'starship init zsh' "${HOME}/.zshrc" || { echo "" >> "${HOME}/.zshrc"; echo "# Starship prompt" >> "${HOME}/.zshrc"; echo "$starship_init" >> "${HOME}/.zshrc"; }
else
  printf '%s\n%s\n' "$path_line" "$starship_init" > "${HOME}/.zshrc"
fi

# -----------------------------
# Tailscale
# -----------------------------
if command -v tailscale >/dev/null 2>&1; then
  log "Tailscale already installed, skipping."
else
  log "Installing Tailscale..."
  run_quiet sudo curl -fsSL -o /etc/yum.repos.d/tailscale.repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  run_quiet sudo rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg
  dnf_quiet install -y tailscale
  run_quiet sudo systemctl enable --now tailscaled
fi

# -----------------------------
# Cursor
# -----------------------------
if command -v cursor >/dev/null 2>&1; then
  log "Cursor already installed, skipping."
else
  log "Installing Cursor..."
  cursor_arch=""
  case "$ARCH" in
    x86_64) cursor_arch="linux-x64-rpm" ;;
    aarch64|arm64) cursor_arch="linux-arm64-rpm" ;;
  esac

  if [ -n "$cursor_arch" ]; then
    cursor_version="$(curl -fsSL "https://www.cursor.com/downloads" | grep -oP 'linux-x64-rpm/cursor/\K[0-9.]+' | head -1 || true)"
    if [ -n "$cursor_version" ]; then
      tmp_rpm="$(mktemp /tmp/cursor.XXXXXX.rpm)"
      curl -fsSL "https://api2.cursor.sh/updates/download/golden/${cursor_arch}/cursor/${cursor_version}" -o "$tmp_rpm"
      dnf_quiet install -y "$tmp_rpm"
      rm -f "$tmp_rpm"
    else
      log "Could not discover Cursor version, skipping."
    fi
  else
    log "Skipping Cursor (unsupported arch)."
  fi
fi

pin_favorite_desktop() {
  local desktop_id="$1"
  local label="$2"
  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || ! command -v gsettings >/dev/null 2>&1; then
    return
  fi
  favs="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || true)"
  if printf '%s' "$favs" | grep -q "$desktop_id"; then
    log "$label already in dash favorites, skipping."
    return
  fi
  log "Pinning $label to dash..."
  if [ "$favs" = "@as []" ] || [ "$favs" = "[]" ]; then
    gsettings set org.gnome.shell favorite-apps "['$desktop_id']"
  else
    gsettings set org.gnome.shell favorite-apps "$(printf '%s' "$favs" | sed "s/\]$/, '$desktop_id']/")"
  fi
}

if command -v cursor >/dev/null 2>&1; then
  pin_favorite_desktop "cursor.desktop" "Cursor"
fi

# -----------------------------
# Claude Code
# -----------------------------
if command -v claude >/dev/null 2>&1; then
  log "Claude Code already installed, skipping."
else
  log "Installing Claude Code..."
  run_quiet npm install -g @anthropic-ai/claude-code
fi

# -----------------------------
# VS Code
# -----------------------------
if command -v code >/dev/null 2>&1; then
  log "VS Code already installed, skipping."
else
  log "Installing VS Code..."
  run_quiet sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  if [ ! -f /etc/yum.repos.d/vscode.repo ]; then
    run_quiet sudo bash -c 'cat > /etc/yum.repos.d/vscode.repo <<"EOF"
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF'
  fi
  dnf_quiet install -y code
fi

# -----------------------------
# Google Chrome + WhatsApp app
# -----------------------------
if command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1; then
  log "Chrome already installed, skipping."
else
  case "$ARCH" in
    x86_64)
      log "Installing Google Chrome..."
      run_quiet sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
      tmp_chrome="$(mktemp /tmp/chrome.XXXXXX.rpm)"
      curl -fsSL -o "$tmp_chrome" https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
      dnf_quiet install -y "$tmp_chrome"
      rm -f "$tmp_chrome"
      ;;
    *)
      log "Skipping Chrome (unsupported arch)."
      ;;
  esac
fi

if command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1; then
  pin_favorite_desktop "google-chrome.desktop" "Chrome"
fi

CHROME_CMD=""
if command -v google-chrome-stable >/dev/null 2>&1; then CHROME_CMD="google-chrome-stable"; fi
if command -v google-chrome >/dev/null 2>&1; then CHROME_CMD="google-chrome"; fi

if [ -z "$CHROME_CMD" ]; then
  log "Skipping WhatsApp webapp (Chrome not installed)."
elif [ -f "${HOME}/.local/share/applications/whatsapp-web.desktop" ]; then
  log "WhatsApp webapp already installed, skipping."
else
  log "Installing WhatsApp webapp..."
  mkdir -p "${HOME}/.local/share/applications"
  WHATSAPP_DESKTOP="${HOME}/.local/share/applications/whatsapp-web.desktop"
  cat > "$WHATSAPP_DESKTOP" <<EOF
[Desktop Entry]
Name=WhatsApp
Comment=WhatsApp Web
Exec=$CHROME_CMD --app=https://web.whatsapp.com
Icon=web-browser
Type=Application
Categories=Network;InstantMessaging;
StartupNotify=true
EOF
  chmod +x "$WHATSAPP_DESKTOP"
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "${HOME}/.local/share/applications" 2>/dev/null || true
  fi
fi

if [ -n "$CHROME_CMD" ] && [ -f "${HOME}/.local/share/applications/whatsapp-web.desktop" ]; then
  pin_favorite_desktop "whatsapp-web.desktop" "WhatsApp"
fi

# -----------------------------
# Git global config
# -----------------------------
if command -v git >/dev/null 2>&1; then
  log "Configuring git globals..."
  git config --global init.defaultBranch main
  git config --global user.email "max.oliver@cintrax.com.br"
  git config --global user.name "Max Oliver"
fi

# -----------------------------
# Flatpak (single bulk install)
# -----------------------------
run_quiet flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

declare -a FLATPAK_APPS=(
  com.mattjakeman.ExtensionManager
  org.gnome.World.PikaBackup
  com.slack.Slack
  org.gnome.gitlab.somas.Apostrophe
  md.obsidian.Obsidian
)

installed_flatpaks="$(flatpak list --app --columns=application 2>/dev/null || true)"
declare -a FLATPAK_MISSING=()
for app in "${FLATPAK_APPS[@]}"; do
  if printf '%s\n' "$installed_flatpaks" | grep -qx "$app"; then
    log "$app already installed via Flatpak, skipping."
  else
    FLATPAK_MISSING+=("$app")
  fi
done

if [ "${#FLATPAK_MISSING[@]}" -gt 0 ]; then
  log "Installing missing Flatpak apps in one transaction..."
  run_quiet flatpak install -y flathub "${FLATPAK_MISSING[@]}"
else
  log "No missing Flatpak apps."
fi

# -----------------------------
# Generic GitHub binary installer
# -----------------------------
install_gh_binary() {
  local name="$1"
  local repo="$2"
  local x86_pattern="$3"
  local arm_pattern="$4"

  if command -v "$name" >/dev/null 2>&1; then
    log "$name already installed, skipping."
    return 0
  fi

  local pattern=""
  case "$ARCH" in
    x86_64) pattern="$x86_pattern" ;;
    aarch64|arm64) pattern="$arm_pattern" ;;
    *)
      log "Skipping $name (unsupported arch)."
      return 0
      ;;
  esac

  log "Installing $name..."
  local url
  url="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" | jq -r --arg p "$pattern" '.assets[] | select(.name | test($p)) | .browser_download_url' | head -1)"
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    log "Could not find release asset for $name, skipping."
    return 0
  fi

  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "$url" | tar xz -C "$tmp" >&3 2>&3
  local bin
  bin="$(find "$tmp" -name "$name" -type f | head -1 || true)"
  if [ -n "$bin" ] && [ -f "$bin" ]; then
    install -c -m 0755 "$bin" "$LOCAL_BIN/$name"
  else
    log "Binary $name not found in archive."
  fi
  rm -rf "$tmp"
}

# Run independent GitHub binary installs in parallel (network-bound).
MAX_JOBS=4
declare -a PIDS=()

run_bg() {
  while [ "$(jobs -pr | wc -l)" -ge "$MAX_JOBS" ]; do
    sleep 0.2
  done
  "$@" &
  PIDS+=("$!")
}

wait_bg() {
  local failed=0
  local pid
  for pid in "${PIDS[@]}"; do
    if ! wait "$pid"; then
      failed=1
    fi
  done
  PIDS=()
  return "$failed"
}

run_bg install_gh_binary eza eza-community/eza 'eza_x86_64-unknown-linux-gnu\.tar\.gz$' 'eza_aarch64-unknown-linux-gnu\.tar\.gz$'
run_bg install_gh_binary zellij zellij-org/zellij 'zellij-x86_64-unknown-linux-musl\.tar\.gz$' 'zellij-aarch64-unknown-linux-musl\.tar\.gz$'
run_bg install_gh_binary lazygit jesseduffield/lazygit 'lazygit_.*_linux_x86_64\.tar\.gz$' 'lazygit_.*_linux_arm64\.tar\.gz$'
run_bg install_gh_binary delta dandavison/delta 'delta-.*-x86_64-unknown-linux-gnu\.tar\.gz$' 'delta-.*-aarch64-unknown-linux-gnu\.tar\.gz$'
run_bg install_gh_binary dust bootandy/dust 'dust-.*-x86_64-unknown-linux-musl\.tar\.gz$' 'dust-.*-aarch64-unknown-linux-musl\.tar\.gz$'
run_bg install_gh_binary xh ducaale/xh 'xh-.*-x86_64-unknown-linux-musl\.tar\.gz$' 'xh-.*-aarch64-unknown-linux-musl\.tar\.gz$'
run_bg install_gh_binary lazydocker jesseduffield/lazydocker 'lazydocker_.*_Linux_x86_64\.tar\.gz$' 'lazydocker_.*_Linux_arm64\.tar\.gz$'

if ! wait_bg; then
  log "One or more GitHub binary installs failed; continuing."
fi

# -----------------------------
# sops + DevPod + mise + bun
# -----------------------------
if command -v sops >/dev/null 2>&1; then
  log "sops already installed, skipping."
else
  sops_arch=""
  case "$ARCH" in
    x86_64) sops_arch="amd64" ;;
    aarch64|arm64) sops_arch="arm64" ;;
  esac
  if [ -n "$sops_arch" ]; then
    log "Installing sops..."
    sops_version="$(curl -fsSL https://api.github.com/repos/getsops/sops/releases/latest | jq -r '.tag_name')"
    curl -fsSL "https://github.com/getsops/sops/releases/download/${sops_version}/sops-${sops_version}.linux.${sops_arch}" -o "$LOCAL_BIN/sops"
    chmod +x "$LOCAL_BIN/sops"
  else
    log "Skipping sops (unsupported arch)."
  fi
fi

if command -v devpod >/dev/null 2>&1; then
  log "DevPod already installed, skipping binary install."
else
  devpod_arch=""
  case "$ARCH" in
    x86_64) devpod_arch="amd64" ;;
    aarch64|arm64) devpod_arch="arm64" ;;
  esac
  if [ -n "$devpod_arch" ]; then
    log "Installing DevPod CLI..."
    tmp_devpod="$(mktemp /tmp/devpod.XXXXXX)"
    curl -fsSL -o "$tmp_devpod" "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-${devpod_arch}"
    chmod +x "$tmp_devpod"
    install -c -m 0755 "$tmp_devpod" "$LOCAL_BIN/devpod"
    rm -f "$tmp_devpod"
  else
    log "Skipping DevPod (unsupported arch)."
  fi
fi

if command -v devpod >/dev/null 2>&1; then
  if devpod provider list 2>/dev/null | grep -q 'podman'; then
    log "DevPod provider podman already configured."
  else
    log "Configuring DevPod provider podman..."
    run_quiet devpod provider add docker --name podman -o DOCKER_PATH=podman
    run_quiet devpod provider use podman
  fi
fi

if command -v mise >/dev/null 2>&1; then
  log "mise already installed, skipping."
else
  log "Installing mise..."
  run_quiet bash -c 'curl -fsSL https://mise.run | sh'
fi

if command -v bun >/dev/null 2>&1; then
  log "bun already installed, skipping."
else
  log "Installing bun..."
  run_quiet bash -c 'curl -fsSL https://bun.sh/install | bash'
fi

# -----------------------------
# zsh integrations
# -----------------------------
touch "${HOME}/.zshrc"
add_to_zshrc() {
  local marker="$1"
  local line="$2"
  grep -qF "$marker" "${HOME}/.zshrc" 2>/dev/null || { echo ""; echo "$line"; } >> "${HOME}/.zshrc"
}
add_to_zshrc 'zoxide init' 'eval "$(zoxide init zsh)"'
add_to_zshrc 'atuin init' 'eval "$(atuin init zsh)"'
add_to_zshrc 'mise activate' 'eval "$(mise activate zsh)"'
add_to_zshrc 'direnv hook' 'eval "$(direnv hook zsh)"'
add_to_zshrc 'BUN_INSTALL' 'export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"'
add_to_zshrc 'fzf/shell/key-bindings' '[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh'
add_to_zshrc 'fzf/shell/completion' '[ -f /usr/share/fzf/shell/completion.zsh ] && source /usr/share/fzf/shell/completion.zsh'

# -----------------------------
# GNOME extensions
# -----------------------------
gnome_extension_enable() {
  local euuid="$1"
  local cur
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
  printf '%s' "$cur" | grep -qF "$euuid" && return
  if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then
    gsettings set org.gnome.shell enabled-extensions "['$euuid']"
  else
    gsettings set org.gnome.shell enabled-extensions "$(printf '%s' "$cur" | sed "s/\]$/, '$euuid']/")"
  fi
}

install_gnome_extension() {
  local pk="$1"
  local name="$2"

  if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || ! command -v gsettings >/dev/null 2>&1; then
    log "Skipping $name (not in a GNOME session)."
    return
  fi

  local info uuid shell_major version_tag tmpzip installed_uuid ext_dir
  info="$(curl -fsSL "${EXTENSIONS_GNOME_ORG}/extension-info/?pk=${pk}" || true)"
  if [ -z "$info" ] || ! printf '%s' "$info" | jq -e 'type == "object"' >/dev/null 2>&1; then
    log "Skipping $name (invalid API response)."
    return
  fi

  uuid="$(printf '%s' "$info" | jq -r 'if type == "object" then .uuid else empty end')"
  if [ -z "$uuid" ] || [ "$uuid" = "null" ]; then
    log "Skipping $name (missing uuid)."
    return
  fi

  ext_dir="${HOME}/.local/share/gnome-shell/extensions/${uuid}"
  if [ -d "$ext_dir" ]; then
    log "$name already installed, ensuring enabled."
    gnome_extension_enable "$uuid"
    return
  fi

  shell_major="$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1 || true)"
  version_tag="$(printf '%s' "$info" | jq -r --arg v "$shell_major" 'if type == "object" then (.shell_version_map[$v].pk // (.shell_version_map | to_entries | map(select(.value | type == "object" and .pk != null)) | sort_by(.key | tonumber) | reverse | .[0].value.pk)) else empty end')"
  if [ -z "$version_tag" ] || [ "$version_tag" = "null" ]; then
    log "Skipping $name (no compatible version)."
    return
  fi

  log "Installing GNOME extension: $name"
  tmpzip="$(mktemp /tmp/gnome-ext.XXXXXX.zip)"
  curl -fsSL "${EXTENSIONS_GNOME_ORG}/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}" -o "$tmpzip"
  if ! unzip -t "$tmpzip" >/dev/null 2>&1; then
    log "Failed to download valid archive for $name, skipping."
    rm -f "$tmpzip"
    return
  fi

  installed_uuid="$(unzip -p "$tmpzip" metadata.json 2>/dev/null | jq -r '.uuid // empty' 2>/dev/null || true)"
  final_uuid="${installed_uuid:-$uuid}"
  mkdir -p "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}"
  unzip -qo "$tmpzip" -d "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}"
  rm -f "$tmpzip"

  if [ ! -f "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}/metadata.json" ]; then
    log "Extension $name extraction incomplete (metadata.json missing)."
    return
  fi

  schemas_dir="${HOME}/.local/share/gnome-shell/extensions/${final_uuid}/schemas"
  if [ -d "$schemas_dir" ] && compgen -G "$schemas_dir/*.xml" >/dev/null; then
    run_quiet glib-compile-schemas "$schemas_dir"
  fi

  gnome_extension_enable "$final_uuid"
}

if command -v gsettings >/dev/null 2>&1 && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
  gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true
fi

install_gnome_extension 4994 "Dash2Dock Animated"
install_gnome_extension 5112 "Tailscale Status"
install_gnome_extension 3193 "Blur my Shell"
install_gnome_extension 4839 "Clipboard History"
install_gnome_extension 8276 "Kiwi"
install_gnome_extension 615 "AppIndicator Support"

echo ""
echo "Done. Restart your terminal or run: exec zsh"
echo "Set Roboto Mono Nerd Font in your terminal profile for icons."
echo "Log out and back in for GNOME extensions to activate."
