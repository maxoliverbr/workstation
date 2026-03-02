#!/usr/bin/env bash
# Install: zsh, Roboto Mono Nerd Font, Starship (Catppuccin), Ranger, Tailscale, Cursor, Claude Code, VS Code, Chrome, WhatsApp webapp,
#          git (global config), Flatpak + Flathub (GNOME Extension Manager, Pika Backup, Slack, Obsidian), Podman, DevPod,
#          system tools (btop, duf, ncdu), security (age, nmap),
#          terminal tools (tmux, fzf, bat, ripgrep, fd, zoxide, atuin, vim, eza, lazygit, delta),
#          dev tools (yq, xh, direnv, lazydocker, Bun), GNOME extensions (Dash2Dock, Tailscale Status, Blur my Shell, etc.)
# For Bluefin OS (Fedora immutable, rpm-ostree). Run with: bash bluefin-shell-setup.sh [--silent]

set -e

if [ "$EUID" -eq 0 ]; then
  echo "Error: do not run this script with sudo. Run as your normal user." >&2
  exit 1
fi

# Require Bluefin or another Fedora immutable (rpm-ostree) system
if [ -f /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release
fi
if [ "$ID" != "bluefin" ] || ! command -v rpm-ostree &>/dev/null; then
  echo "Error: this script requires Bluefin or another Fedora immutable (rpm-ostree) system. Detected OS: ${ID:-unknown}" >&2
  exit 1
fi

# Require curl, rpm-ostree, jq, and unzip (needed for single-pass run; layer with: rpm-ostree install jq unzip, then reboot)
for cmd in curl rpm-ostree jq unzip; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: required command '$cmd' is not available. On Bluefin, layer with: rpm-ostree install jq unzip, then reboot and run this script." >&2
    exit 1
  fi
done

# Require working internet (needed for rpm-ostree, flatpak, and all downloads)
if ! curl -sS -o /dev/null -f --connect-timeout 5 --max-time 10 https://api.github.com 2>/dev/null; then
  echo "Error: no working internet connection. Check your network and try again." >&2
  exit 1
fi

SILENT=0
for arg in "$@"; do [ "$arg" = "--silent" ] && SILENT=1; done
if [ "$SILENT" = "1" ]; then exec 3>/dev/null; else exec 3>&1; fi

# # Require at least 5 GB free on / (rpm-ostree, flatpak, and most installs use root)
# required_kb=$((5 * 1024 * 1024))
# available_kb=$(df -k / | awk 'NR==2 {print $4}')
# if [ "$available_kb" -lt "$required_kb" ]; then
#   available_gb=$(awk "BEGIN {printf \"%.1f\", $available_kb/1024/1024}")
#   echo "Error: at least 5 GB free disk space required on /. Available: ${available_gb} GB" >&2
#   exit 1
# fi

FONT_DIR="${HOME}/.local/share/fonts"
CONFIG_DIR="${HOME}/.config"
EXTENSIONS_GNOME_ORG="https://extensions.gnome.org"

# rpm-ostree wrapper: layer packages, skipping those already layered or requested (avoids "Package is already requested")
ostree_install() {
  local to_install=() pkg layered_requested
  layered_requested=$(rpm-ostree status --json 2>/dev/null | jq -r '.deployments[] | select(.booted) | ((.packages // []) + (.["requested-packages"] // [])) | .[]' 2>/dev/null) || true
  for pkg in "$@"; do
    if [[ "$pkg" == */* ]]; then
      to_install+=("$pkg")
    elif echo "$layered_requested" | grep -qxF "$pkg" 2>/dev/null; then
      : # already layered or requested, skip
    else
      to_install+=("$pkg")
    fi
  done
  if [ ${#to_install[@]} -eq 0 ]; then
    return 0
  fi
  if [ "$SILENT" = "1" ]; then sudo rpm-ostree install "${to_install[@]}" >&3 2>&3; else sudo rpm-ostree install "${to_install[@]}"; fi
}

# Install a single layered package with skip-if-present messaging
# Usage: install_dnf_pkg <emoji> <display-name> <command-to-check> [package-name]
install_dnf_pkg() {
  local emoji="$1" label="$2" cmd="$3" pkg="${4:-$3}"
  if command -v "$cmd" &>/dev/null; then
    echo "==> $emoji $label is already installed, skipping."
  else
    echo "==> $emoji Installing $label..."
    ostree_install "$pkg"
  fi
}

# Install a group of packages in one rpm-ostree call, skipping those already present
# Usage: install_dnf_group <emoji> <label> <cmd:pkg> [<cmd:pkg> ...]
install_dnf_group() {
  local emoji="$1" label="$2"; shift 2
  local missing=()
  for pair in "$@"; do
    local cmd="${pair%%:*}" pkg="${pair##*:}"
    command -v "$cmd" &>/dev/null || missing+=("$pkg")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "==> $emoji $label tools are already installed, skipping."
  else
    echo "==> $emoji Installing $label tools: ${missing[*]}..."
    ostree_install "${missing[@]}"
  fi
}

# Helper: install a binary from a GitHub release tar.gz
install_gh_binary() {
  local name="$1" repo="$2" x86_pattern="$3" arm_pattern="$4"
  if command -v "$name" &>/dev/null; then
    echo "==> 💾 $name is already installed, skipping."
    return
  fi
  echo "==> 💾 Installing $name..."
  local pattern
  case "$(uname -m)" in
    x86_64)        pattern="$x86_pattern" ;;
    aarch64|arm64) pattern="$arm_pattern" ;;
    *) echo "==> ⚠️  Skipping $name (unsupported arch)."; return ;;
  esac
  local url
  url=$(curl -sL "https://api.github.com/repos/${repo}/releases/latest" \
    | jq -r --arg p "$pattern" '.assets[] | select(.name | test($p)) | .browser_download_url' \
    | head -1)
  if [ -z "$url" ]; then
    echo "==> ⚠️  Could not find $name release asset. Skipping."
    return
  fi
  mkdir -p "${HOME}/.local/bin"
  local tmp; tmp=$(mktemp -d)
  curl -sSL "$url" | tar xz -C "$tmp" >&3 2>&3
  local bin; bin=$(find "$tmp" -name "$name" -type f | head -1)
  if [ -n "$bin" ]; then
    install -c -m 0755 "$bin" "${HOME}/.local/bin/$name"
  else
    echo "==> ⚠️  Binary '$name' not found in archive."
  fi
  rm -rf "$tmp"
}

# GitHub CLI (gh)
if command -v gh &>/dev/null; then
  echo "==> 🐙 gh is already installed, skipping."
else
  echo "==> 🐙 Installing GitHub CLI (gh)..."
  ostree_install gh
fi

# Git (install + global config)
if ! command -v git &>/dev/null; then
  echo "==> 📦 Installing git..."
  ostree_install git
fi
echo "==> 📦 Configuring git (defaultBranch, user.email, user.name)..."
git config --global init.defaultBranch main
git config --global user.email "max.oliver@cintrax.com.br"
git config --global user.name "Max Oliver"


if command -v zsh &>/dev/null; then
  echo "==> 🐚 zsh is already installed, skipping."
else
  echo "==> 🐚 Installing zsh..."
  ostree_install zsh
fi
if [ "$SHELL" != "$(which zsh)" ]; then
  echo "==> 🐚 Changing default shell to zsh..."
  chshw -s "$(which zsh)"
fi

if [ -n "$(ls "$FONT_DIR"/RobotoMono*.ttf 2>/dev/null)" ]; then
  echo "==> 🔤 Roboto Mono Nerd Font is already installed, skipping."
else
  echo "==> 🔤 Installing Roboto Mono Nerd Font..."
  NF_VERSION=$(curl -sL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
  ROBOTO_MONO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/RobotoMono.zip"
  mkdir -p "$FONT_DIR"
  tmp_font=$(mktemp -d)
  trap "rm -rf $tmp_font" EXIT
  curl -sSL "$ROBOTO_MONO_URL" -o "$tmp_font/RobotoMono.zip"
  unzip -qo "$tmp_font/RobotoMono.zip" -d "$tmp_font"
  cp "$tmp_font"/*.ttf "$FONT_DIR/" 2>/dev/null || true
  fc-cache -f
fi

export PATH="${HOME}/.local/bin:${PATH}"
if command -v starship &>/dev/null; then
  echo "==> 🚀 Starship is already installed, skipping."
else
  echo "==> 🚀 Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh -s -- -y >&3 2>&3
  export PATH="${HOME}/.local/bin:${PATH}"
fi

if [ -f "$CONFIG_DIR/starship.toml" ]; then
  echo "==> ☕ Starship config already exists, skipping Catppuccin preset."
else
  echo "==> ☕ Setting up Starship with Catppuccin..."
  mkdir -p "$CONFIG_DIR"
  starship preset catppuccin-powerline -o "$CONFIG_DIR/starship.toml"
fi

echo "==> ✏️  Adding Starship to zshrc..."

path_line='export PATH="${HOME}/.local/bin:${PATH}"'
starship_init='eval "$(starship init zsh)"'
if [ -f "${HOME}/.zshrc" ]; then
  grep -q '.local/bin' "${HOME}/.zshrc" || { echo "" >> "${HOME}/.zshrc"; echo "$path_line" >> "${HOME}/.zshrc"; }
  grep -q 'starship init zsh' "${HOME}/.zshrc" || { echo "" >> "${HOME}/.zshrc"; echo "# Starship prompt" >> "${HOME}/.zshrc"; echo "$starship_init" >> "${HOME}/.zshrc"; }
else
  echo "$path_line" > "${HOME}/.zshrc"
  echo "$starship_init" >> "${HOME}/.zshrc"
fi

if command -v ranger &>/dev/null; then
  echo "==> 📁 Ranger is already installed, skipping."
else
  echo "==> 📁 Installing Ranger..."
  ostree_install ranger
fi

# Tailscale
if command -v tailscale &>/dev/null; then
  echo "==> 🦾 Tailscale is already installed, skipping."
else
  echo "==> 🦾 Installing Tailscale..."
  sudo curl -sSL -o /etc/yum.repos.d/tailscale.repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  sudo rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg >&3 2>&3
  ostree_install tailscale
  sudo systemctl enable --now tailscaled >&3 2>&3
fi

# Cursor IDE
if command -v cursor &>/dev/null; then
  echo "==> 📝 Cursor is already installed, skipping."
else
  echo "==> 📝 Installing Cursor..."
  CURSOR_VERSION=$(curl -sL "https://www.cursor.com/downloads" | grep -oP 'linux-x64-rpm/cursor/\K[0-9.]+' | head -1)
  case "$(uname -m)" in
    x86_64) cursor_arch="linux-x64-rpm" ;;
    aarch64|arm64) cursor_arch="linux-arm64-rpm" ;;
    *) echo "==> 📝 Skipping Cursor (unsupported arch)."; cursor_arch="" ;;
  esac
  if [ -n "$cursor_arch" ]; then
    tmp_rpm=$(mktemp -u).rpm
    curl -sSL "https://api2.cursor.sh/updates/download/golden/${cursor_arch}/cursor/${CURSOR_VERSION}" -o "$tmp_rpm"
    ostree_install "$tmp_rpm"
    rm -f "$tmp_rpm"
  fi
fi

# Pin Cursor to dash (GNOME favorites) when in a graphical session
if command -v cursor &>/dev/null && [ -n "${WAYLAND_DISPLAY}${DISPLAY}" ] && command -v gsettings &>/dev/null; then
  favs=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
  if echo "$favs" | grep -q 'cursor'; then
    echo "==> 📝 Cursor already in dash favorites, skipping."
  else
    echo "==> 📝 Pinning Cursor to dash..."
    if [ "$favs" = "@as []" ] || [ "$favs" = "[]" ]; then
      gsettings set org.gnome.shell favorite-apps "['cursor.desktop']"
    else
      gsettings set org.gnome.shell favorite-apps "$(echo "$favs" | sed "s/\]$/, 'cursor.desktop']/")"
    fi
  fi
fi

# Claude Code CLI
if command -v claude &>/dev/null; then
  echo "==> 🤖 Claude Code is already installed, skipping."
else
  echo "==> 🤖 Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash >&3 2>&3
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# VS Code
if command -v code &>/dev/null; then
  echo "==> 📟 VS Code is already installed, skipping."
else
  echo "==> 📟 Installing VS Code..."
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc >&3 2>&3
  sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
  ostree_install code
fi

# Set Roboto Mono Nerd Font in Cursor and VS Code (editor + integrated terminal)
EDITOR_FONT="RobotoMono Nerd Font"
set_editor_font() {
  local config_name="$1"
  local user_dir="${HOME}/.config/${config_name}/User"
  local settings_file="${user_dir}/settings.json"
  [ -d "$user_dir" ] || mkdir -p "$user_dir"
  command -v jq &>/dev/null || ostree_install jq
  local existing
  existing=$(cat "$settings_file" 2>/dev/null) || existing="{}"
  echo "$existing" | jq --arg font "$EDITOR_FONT" '
    .["editor.fontFamily"] = $font |
    .["terminal.integrated.fontFamily"] = $font
  ' > "${settings_file}.new" && mv "${settings_file}.new" "$settings_file"
}
if command -v cursor &>/dev/null; then
  echo "==> 📝 Setting Roboto Mono Nerd Font in Cursor..."
  set_editor_font "Cursor"
fi
if command -v code &>/dev/null; then
  echo "==> 📟 Setting Roboto Mono Nerd Font in VS Code..."
  set_editor_font "Code"
fi

# Google Chrome
if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
  echo "==> 🌐 Chrome is already installed, skipping."
else
  echo "==> 🌐 Installing Google Chrome..."
  case "$(uname -m)" in
    x86_64)
      sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub >&3 2>&3
      tmp_chrome=$(mktemp -u).rpm
      curl -sSL -o "$tmp_chrome" https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
      ostree_install "$tmp_chrome"
      rm -f "$tmp_chrome"
      ;;
    *) echo "==> 🌐 Skipping Chrome (unsupported arch)." ;;
  esac
fi

# Pin Chrome to dash (GNOME favorites) when in a graphical session
if (command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null) && [ -n "${WAYLAND_DISPLAY}${DISPLAY}" ] && command -v gsettings &>/dev/null; then
  favs=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
  if echo "$favs" | grep -q 'google-chrome'; then
    echo "==> 🌐 Chrome already in dash favorites, skipping."
  else
    echo "==> 🌐 Pinning Chrome to dash..."
    if [ "$favs" = "@as []" ] || [ "$favs" = "[]" ]; then
      gsettings set org.gnome.shell favorite-apps "['google-chrome.desktop']"
    else
      gsettings set org.gnome.shell favorite-apps "$(echo "$favs" | sed "s/\]$/, 'google-chrome.desktop']/")"
    fi
  fi
fi

# WhatsApp webapp (Chrome --app window; requires Chrome)
CHROME_CMD=""
command -v google-chrome-stable &>/dev/null && CHROME_CMD="google-chrome-stable"
command -v google-chrome &>/dev/null && CHROME_CMD="google-chrome"
if [ -z "$CHROME_CMD" ]; then
  echo "==> 💬 Skipping WhatsApp webapp (Chrome not installed)."
elif [ -f "${HOME}/.local/share/applications/whatsapp-web.desktop" ]; then
  echo "==> 💬 WhatsApp webapp is already installed, skipping."
else
  echo "==> 💬 Installing WhatsApp webapp..."
  mkdir -p "${HOME}/.local/share/applications"
  WHATSAPP_DESKTOP="${HOME}/.local/share/applications/whatsapp-web.desktop"
  cat > "$WHATSAPP_DESKTOP" << EOF
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
  if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q "${HOME}/.local/share/applications" 2>/dev/null || true
  fi
fi

# Pin WhatsApp to dash when in a graphical session
if [ -n "$CHROME_CMD" ] && [ -f "${HOME}/.local/share/applications/whatsapp-web.desktop" ] && [ -n "${WAYLAND_DISPLAY}${DISPLAY}" ] && command -v gsettings &>/dev/null; then
  favs=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
  if echo "$favs" | grep -q 'whatsapp-web'; then
    echo "==> 💬 WhatsApp already in dash favorites, skipping."
  else
    echo "==> 💬 Pinning WhatsApp to dash..."
    if [ "$favs" = "@as []" ] || [ "$favs" = "[]" ]; then
      gsettings set org.gnome.shell favorite-apps "['whatsapp-web.desktop']"
    else
      gsettings set org.gnome.shell favorite-apps "$(echo "$favs" | sed "s/\]$/, 'whatsapp-web.desktop']/")"
    fi
  fi
fi

# Ensure flatpak + Flathub are available (required for all Flatpak installs below)
if ! command -v flatpak &>/dev/null; then
  echo "==> 📦 Installing flatpak..."
  ostree_install flatpak
fi
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >&3 2>&3

# Flatpak apps (GNOME Extension Manager, Pika Backup, Slack, Obsidian)
flatpak_install_group() {
  local missing=()
  for app in "$@"; do
    flatpak list --app 2>/dev/null | grep -q "$app" || missing+=("$app")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "==> 📦 All Flatpak apps already installed, skipping."
  else
    echo "==> 📦 Installing Flatpak apps: ${missing[*]}..."
    flatpak install -y flathub "${missing[@]}" >&3 2>&3
  fi
}

flatpak_install_group \
  com.mattjakeman.ExtensionManager \
  org.gnome.World.PikaBackup \
  com.slack.Slack \
  md.obsidian.Obsidian

# Pin Obsidian to dash (GNOME favorites) when in a graphical session
if flatpak list --app 2>/dev/null | grep -q md.obsidian.Obsidian && [ -n "${WAYLAND_DISPLAY}${DISPLAY}" ] && command -v gsettings &>/dev/null; then
  favs=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)
  if echo "$favs" | grep -q 'obsidian'; then
    echo "==> 🔮 Obsidian already in dash favorites, skipping."
  else
    echo "==> 🔮 Pinning Obsidian to dash..."
    if [ "$favs" = "@as []" ] || [ "$favs" = "[]" ]; then
      gsettings set org.gnome.shell favorite-apps "['md.obsidian.Obsidian.desktop']"
    else
      gsettings set org.gnome.shell favorite-apps "$(echo "$favs" | sed "s/\]$/, 'md.obsidian.Obsidian.desktop']/")"
    fi
  fi
fi

# DevPod + Podman (CLI only; desktop app has EGL/WebKit issues on Fedora)
if command -v podman &>/dev/null; then
  echo "==> 🐳 Podman is already installed, skipping."
else
  echo "==> 🐳 Installing Podman..."
  ostree_install podman
fi
if command -v devpod &>/dev/null; then
  echo "==> 📦 DevPod CLI is already installed, skipping."
else
  echo "==> 📦 Installing DevPod CLI..."
  case "$(uname -m)" in
    x86_64) devpod_arch="amd64" ;;
    aarch64|arm64) devpod_arch="arm64" ;;
    *) echo "==> 📦 Skipping DevPod (unsupported arch)."; devpod_arch="" ;;
  esac
  if [ -n "$devpod_arch" ]; then
    mkdir -p "${HOME}/.local/bin"
    curl -sSL -o /tmp/devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-linux-${devpod_arch}"
    chmod +x /tmp/devpod
    install -c -m 0755 /tmp/devpod "${HOME}/.local/bin/devpod"
    rm -f /tmp/devpod
  fi
fi
if command -v devpod &>/dev/null; then
  if devpod provider list 2>/dev/null | grep -q 'podman'; then
    echo "==> 📦 DevPod provider 'podman' already configured, skipping."
  else
    echo "==> 📦 Configuring DevPod to use Podman..."
    devpod provider add docker --name podman -o DOCKER_PATH=podman >&3 2>&3
    devpod provider use podman >&3 2>&3
  fi
fi

# System tools
install_dnf_group "🖥️ " "system"   btop:btop duf:duf ncdu:ncdu

# Security / Network
install_dnf_group "🔒" "security" age:age nmap:nmap

# Terminal / Shell tools (packages available in Fedora repos)
install_dnf_group "💻" "terminal" tmux:tmux fzf:fzf bat:bat rg:ripgrep fd:fd-find zoxide:zoxide atuin:atuin vim:vim

# Terminal tools not in Fedora repos — installed from GitHub releases
install_gh_binary "eza"     "eza-community/eza"     "eza_x86_64-unknown-linux-gnu\\.tar\\.gz$"       "eza_aarch64-unknown-linux-gnu\\.tar\\.gz$"
install_gh_binary "lazygit" "jesseduffield/lazygit"  "lazygit_.*_linux_x86_64\\.tar\\.gz$"            "lazygit_.*_linux_arm64\\.tar\\.gz$"
install_gh_binary "delta"   "dandavison/delta"       "delta-.*-x86_64-unknown-linux-gnu\\.tar\\.gz$"  "delta-.*-aarch64-unknown-linux-gnu\\.tar\\.gz$"

# Dev tools
install_dnf_group "🔧" "dev" yq:yq direnv:direnv
install_gh_binary "xh" "ducaale/xh" "xh-.*-x86_64-unknown-linux-musl\\.tar\\.gz$" "xh-.*-aarch64-unknown-linux-musl\\.tar\\.gz$"

install_gh_binary "lazydocker" "jesseduffield/lazydocker" "lazydocker_.*_Linux_x86_64\\.tar\\.gz$" "lazydocker_.*_Linux_arm64\\.tar\\.gz$"

# Bun
if command -v bun &>/dev/null; then
  echo "==> 🍞 Bun is already installed, skipping."
else
  echo "==> 🍞 Installing Bun..."
  curl -fsSL https://bun.sh/install | bash >&3 2>&3
fi


# Zsh integrations
echo "==> 🐚 Updating zshrc with tool integrations..."
add_to_zshrc() {
  local marker="$1" line="$2"
  grep -qF "$marker" "${HOME}/.zshrc" 2>/dev/null || { echo ""; echo "$line"; } >> "${HOME}/.zshrc"
}
add_to_zshrc 'zoxide init'   'eval "$(zoxide init zsh)"'
add_to_zshrc 'atuin init'    'eval "$(atuin init zsh)"'
add_to_zshrc 'direnv hook'   'eval "$(direnv hook zsh)"'
add_to_zshrc 'BUN_INSTALL'   'export BUN_INSTALL="$HOME/.bun"; export PATH="$BUN_INSTALL/bin:$PATH"'
add_to_zshrc 'fzf/shell/key-bindings' '[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh'
add_to_zshrc 'fzf/shell/completion'   '[ -f /usr/share/fzf/shell/completion.zsh ]   && source /usr/share/fzf/shell/completion.zsh'

# Helper: add a UUID to org.gnome.shell enabled-extensions via gsettings
gnome_extension_enable() {
  local euuid="$1"
  local cur
  cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)
  echo "$cur" | grep -qF "$euuid" && return
  if [ "$cur" = "@as []" ] || [ "$cur" = "[]" ]; then
    gsettings set org.gnome.shell enabled-extensions "['$euuid']"
  else
    gsettings set org.gnome.shell enabled-extensions "$(echo "$cur" | sed "s/\]$/, '$euuid']/")"
  fi
}

# GNOME extensions (Dash2Dock Animated, Tailscale Status, Blur my Shell, Clipboard History, Kiwi, AppIndicator Support)
install_gnome_extension() {
  local pk="$1" name="$2"
  if [ -z "${WAYLAND_DISPLAY}${DISPLAY}" ] || ! command -v gsettings &>/dev/null; then
    echo "==> 🔌 Skipping $name (not in a GNOME session)."
    return
  fi
  command -v jq    &>/dev/null || ostree_install jq
  command -v unzip &>/dev/null || ostree_install unzip
  local info uuid shell_major version_tag tmpzip installed_uuid ext_dir
  info=$(curl -sL "${EXTENSIONS_GNOME_ORG}/extension-info/?pk=${pk}")
  if [ -z "$info" ] || ! echo "$info" | jq -e 'type == "object"' &>/dev/null; then
    echo "==> 🔌 Skipping $name (invalid API response)."
    return
  fi
  uuid=$(echo "$info" | jq -r 'if type == "object" then .uuid else empty end')
  if [ -z "$uuid" ] || [ "$uuid" = "null" ]; then
    echo "==> 🔌 Skipping $name (no uuid in API response)."
    return
  fi
  ext_dir="${HOME}/.local/share/gnome-shell/extensions/${uuid}"
  if [ -d "$ext_dir" ]; then
    echo "==> 🔌 $name is already installed, skipping."
    gnome_extension_enable "$uuid"
    return
  fi
  shell_major=$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1)
  version_tag=$(echo "$info" | jq -r --arg v "$shell_major" 'if type == "object" then (.shell_version_map[$v].pk // (.shell_version_map | to_entries | map(select(.value | type == "object" and .pk != null)) | sort_by(.key | tonumber) | reverse | .[0].value.pk)) else empty end')
  if [ -z "$version_tag" ] || [ "$version_tag" = "null" ]; then
    echo "==> 🔌 Skipping $name (no compatible version)."
    return
  fi
  echo "==> 🔌 Installing $name..."
  tmpzip=$(mktemp -u).zip
  curl -sSL "${EXTENSIONS_GNOME_ORG}/download-extension/${uuid}.shell-extension.zip?version_tag=${version_tag}" -o "$tmpzip"
  if ! unzip -t "$tmpzip" &>/dev/null; then
    echo "==> 🔌 Failed to download $name (invalid zip). Skipping."
    rm -f "$tmpzip"
    return
  fi
  installed_uuid=$(unzip -p "$tmpzip" metadata.json 2>/dev/null | jq -r '.uuid // empty' 2>/dev/null)
  local final_uuid="${installed_uuid:-$uuid}"
  mkdir -p "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}"
  unzip -qo "$tmpzip" -d "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}"
  rm -f "$tmpzip"
  if [ ! -f "${HOME}/.local/share/gnome-shell/extensions/${final_uuid}/metadata.json" ]; then
    echo "==> 🔌 Warning: $name extraction may have failed (no metadata.json found)."
    return
  fi
  local schemas_dir="${HOME}/.local/share/gnome-shell/extensions/${final_uuid}/schemas"
  if [ -d "$schemas_dir" ] && ls "$schemas_dir"/*.xml &>/dev/null; then
    glib-compile-schemas "$schemas_dir"
  fi
  gnome_extension_enable "$final_uuid"
}

if command -v gsettings &>/dev/null && [ -n "${WAYLAND_DISPLAY}${DISPLAY}" ]; then
  gsettings set org.gnome.shell disable-user-extensions false 2>/dev/null || true
fi

install_gnome_extension 4994 "Dash2Dock Animated"
install_gnome_extension 5112 "Tailscale Status"
install_gnome_extension 3193 "Blur my Shell"
install_gnome_extension 4839 "Clipboard History"
install_gnome_extension 8276 "Kiwi"
install_gnome_extension 615 "AppIndicator Support"

echo ""
echo "✅ Done. Restart your terminal or run: exec zsh"
echo "💡 Set Roboto Mono Nerd Font in your terminal profile for icons to show."
echo "🔄 Log out and log back in for GNOME extensions to become active."
echo "🔄 Layered packages (rpm-ostree) take effect after a reboot. To apply without rebooting, run: rpm-ostree apply-live"
