#!/usr/bin/env bash
# Install: zsh, Roboto Mono Nerd Font, Starship (Catppuccin), Ranger, Tailscale, Cursor, Claude Code, Chrome, Slack, Apostrophe, Obsidian,
#          git (global config), GNOME Extension Manager + extensions,
#          system tools (btop, duf, ncdu, timeshift), security (age, nmap, sops, wireshark),
#          terminal tools (tmux, zellij, fzf, bat, eza, ripgrep, fd, delta, zoxide, atuin, lazygit, dust),
#          dev tools (yq, xh, direnv, mise, bun, lazydocker)
# For Fedora/RHEL (uses dnf). Run with: bash install-shell-setup.sh [--debug]

set -e

DEBUG=0
for arg in "$@"; do [ "$arg" = "--debug" ] && DEBUG=1; done
if [ "$DEBUG" = "1" ]; then exec 3>&1; else exec 3>/dev/null; fi

# DNF wrapper: quiet by default, verbose with --debug
dnf_quiet() { if [ "$DEBUG" = "1" ]; then sudo dnf "$@"; else sudo dnf -q "$@"; fi; }

# Install a single dnf package with skip-if-present messaging
# Usage: install_dnf_pkg <emoji> <display-name> <command-to-check> [package-name]
install_dnf_pkg() {
  local emoji="$1" label="$2" cmd="$3" pkg="${4:-$3}"
  if command -v "$cmd" &>/dev/null; then
    echo "==> $emoji $label is already installed, skipping."
  else
    echo "==> $emoji Installing $label..."
    dnf_quiet install -y "$pkg"
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
  curl -sSL "$url" | tar xz -C "$tmp" >&3
  local bin; bin=$(find "$tmp" -name "$name" -type f | head -1)
  if [ -n "$bin" ]; then
    install -c -m 0755 "$bin" "${HOME}/.local/bin/$name"
  else
    echo "==> ⚠️  Binary '$name' not found in archive."
  fi
  rm -rf "$tmp"
}

FONT_DIR="${HOME}/.local/share/fonts"
CONFIG_DIR="${HOME}/.config"
NF_VERSION="v3.1.1"
ROBOTO_MONO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/RobotoMono.zip"
EXTENSIONS_GNOME_ORG="https://extensions.gnome.org"

if command -v zsh &>/dev/null; then
  echo "==> 🐚 zsh is already installed, skipping."
else
  echo "==> 🐚 Installing zsh..."
  dnf_quiet install -y zsh
fi
if [ "$SHELL" != "$(which zsh)" ]; then
  echo "==> 🐚 Changing default shell to zsh..."
  chsh -s "$(which zsh)"
fi

if [ -n "$(ls "$FONT_DIR"/RobotoMono*.ttf 2>/dev/null)" ]; then
  echo "==> 🔤 Roboto Mono Nerd Font is already installed, skipping."
else
  echo "==> 🔤 Installing Roboto Mono Nerd Font..."
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
  curl -sS https://starship.rs/install.sh | sh -s -- -y >&3
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
  dnf_quiet install -y ranger
fi

# Tailscale
if command -v tailscale &>/dev/null; then
  echo "==> 🦾 Tailscale is already installed, skipping."
else
  echo "==> 🦾 Installing Tailscale..."
  sudo curl -sSL -o /etc/yum.repos.d/tailscale.repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  sudo rpm --import https://pkgs.tailscale.com/stable/fedora/repo.gpg
  dnf_quiet install -y tailscale
  sudo systemctl enable --now tailscaled >&3
fi

# Cursor IDE
if command -v cursor &>/dev/null; then
  echo "==> 📝 Cursor is already installed, skipping."
else
  echo "==> 📝 Installing Cursor..."
  CURSOR_VERSION="2.5"
  case "$(uname -m)" in
    x86_64) cursor_arch="linux-x64-rpm" ;;
    aarch64|arm64) cursor_arch="linux-arm64-rpm" ;;
    *) echo "==> 📝 Skipping Cursor (unsupported arch)."; cursor_arch="" ;;
  esac
  if [ -n "$cursor_arch" ]; then
    tmp_rpm=$(mktemp -u).rpm
    curl -sSL "https://api2.cursor.sh/updates/download/golden/${cursor_arch}/cursor/${CURSOR_VERSION}" -o "$tmp_rpm"
    dnf_quiet install -y "$tmp_rpm"
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
  curl -fsSL https://claude.ai/install.sh | bash >&3
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# VS Code
if command -v code &>/dev/null; then
  echo "==> 📟 VS Code is already installed, skipping."
else
  echo "==> 📟 Installing VS Code..."
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
  dnf_quiet install -y code
fi

# Google Chrome
if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
  echo "==> 🌐 Chrome is already installed, skipping."
else
  echo "==> 🌐 Installing Google Chrome..."
  case "$(uname -m)" in
    x86_64)
      sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
      tmp_chrome=$(mktemp -u).rpm
      curl -sSL -o "$tmp_chrome" https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
      dnf_quiet install -y "$tmp_chrome"
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

# GitHub CLI (gh)
if command -v gh &>/dev/null; then
  echo "==> 🐙 gh is already installed, skipping."
else
  echo "==> 🐙 Installing GitHub CLI (gh)..."
  dnf_quiet install -y gh
fi

# Git (install + global config)
if ! command -v git &>/dev/null; then
  echo "==> 📦 Installing git..."
  dnf_quiet install -y git
fi
echo "==> 📦 Configuring git (defaultBranch, user.email, user.name)..."
git config --global init.defaultBranch main
git config --global user.email "max.oliver@cintrax.com.br"
git config --global user.name "Max Oliver"

# Ensure flatpak + Flathub are available (required for all Flatpak installs below)
if ! command -v flatpak &>/dev/null; then
  echo "==> 📦 Installing flatpak..."
  dnf_quiet install -y flatpak
fi
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >&3

# GNOME Extension Manager (Flatpak)
if flatpak list --app 2>/dev/null | grep -q com.mattjakeman.ExtensionManager; then
  echo "==> 🧩 GNOME Extension Manager is already installed, skipping."
else
  echo "==> 🧩 Installing GNOME Extension Manager..."
  flatpak install -y flathub com.mattjakeman.ExtensionManager >&3
fi

# Pika Backup (Flatpak)
if flatpak list --app 2>/dev/null | grep -q org.gnome.World.PikaBackup; then
  echo "==> 💾 Pika Backup is already installed, skipping."
else
  echo "==> 💾 Installing Pika Backup..."
  flatpak install -y flathub org.gnome.World.PikaBackup >&3
fi

# Slack (Flatpak)
if flatpak list --app 2>/dev/null | grep -q com.slack.Slack; then
  echo "==> 💬 Slack is already installed, skipping."
else
  echo "==> 💬 Installing Slack..."
  flatpak install -y flathub com.slack.Slack >&3
fi

# Apostrophe - Markdown editor (Flatpak)
if flatpak list --app 2>/dev/null | grep -q org.gnome.gitlab.somas.Apostrophe; then
  echo "==> 📄 Apostrophe is already installed, skipping."
else
  echo "==> 📄 Installing Apostrophe..."
  flatpak install -y flathub org.gnome.gitlab.somas.Apostrophe >&3
fi

# Obsidian (Flatpak)
if flatpak list --app 2>/dev/null | grep -q md.obsidian.Obsidian; then
  echo "==> 🔮 Obsidian is already installed, skipping."
else
  echo "==> 🔮 Installing Obsidian..."
  flatpak install -y flathub md.obsidian.Obsidian >&3
fi

# DevPod + Podman (CLI only; desktop app has EGL/WebKit issues on Fedora)
if command -v podman &>/dev/null; then
  echo "==> 🐳 Podman is already installed, skipping."
else
  echo "==> 🐳 Installing Podman..."
  dnf_quiet install -y podman
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
    devpod provider add docker --name podman -o DOCKER_PATH=podman >&3
    devpod provider use podman >&3
  fi
fi

# System tools
install_dnf_pkg "🖥️ " "btop"      btop
install_dnf_pkg "🖥️ " "duf"       duf
install_dnf_pkg "🖥️ " "ncdu"      ncdu
install_dnf_pkg "🖥️ " "timeshift" timeshift

# Security / Network
install_dnf_pkg "🔒" "age"       age
install_dnf_pkg "🔒" "nmap"      nmap
install_dnf_pkg "🔒" "wireshark" wireshark

# sops (binary from GitHub — not in Fedora repos)
if command -v sops &>/dev/null; then
  echo "==> 🔒 sops is already installed, skipping."
else
  echo "==> 🔒 Installing sops..."
  case "$(uname -m)" in
    x86_64) sops_arch="amd64" ;;
    aarch64|arm64) sops_arch="arm64" ;;
    *) echo "==> 🔒 Skipping sops (unsupported arch)."; sops_arch="" ;;
  esac
  if [ -n "$sops_arch" ]; then
    mkdir -p "${HOME}/.local/bin"
    sops_version=$(curl -sL https://api.github.com/repos/getsops/sops/releases/latest | jq -r '.tag_name')
    curl -sSL "https://github.com/getsops/sops/releases/download/${sops_version}/sops-${sops_version}.linux.${sops_arch}" -o "${HOME}/.local/bin/sops"
    chmod +x "${HOME}/.local/bin/sops"
  fi
fi

# Terminal / Shell tools (packages available in Fedora repos)
install_dnf_pkg "💻" "tmux"    tmux
install_dnf_pkg "💻" "fzf"     fzf
install_dnf_pkg "💻" "bat"     bat
install_dnf_pkg "💻" "ripgrep" rg    ripgrep
install_dnf_pkg "💻" "fd"      fd    fd-find
install_dnf_pkg "💻" "zoxide"  zoxide
install_dnf_pkg "💻" "atuin"   atuin

# Terminal tools not in Fedora repos — installed from GitHub releases
install_gh_binary "eza"     "eza-community/eza"     "eza_x86_64-unknown-linux-musl\\.tar\\.gz$"      "eza_aarch64-unknown-linux-musl\\.tar\\.gz$"
install_gh_binary "zellij"  "zellij-org/zellij"     "zellij-x86_64-unknown-linux-musl\\.tar\\.gz$"   "zellij-aarch64-unknown-linux-musl\\.tar\\.gz$"
install_gh_binary "lazygit" "jesseduffield/lazygit"  "lazygit_.*_Linux_x86_64\\.tar\\.gz$"            "lazygit_.*_Linux_arm64\\.tar\\.gz$"
install_gh_binary "delta"   "dandavison/delta"       "delta-.*-x86_64-unknown-linux-musl\\.tar\\.gz$" "delta-.*-aarch64-unknown-linux-musl\\.tar\\.gz$"
install_gh_binary "dust"    "bootandy/dust"          "dust-.*-x86_64-unknown-linux-musl\\.tar\\.gz$"  "dust-.*-aarch64-unknown-linux-musl\\.tar\\.gz$"

# Dev tools
install_dnf_pkg "🔧" "yq"     yq
install_dnf_pkg "🔧" "xh"     xh
install_dnf_pkg "🔧" "direnv" direnv

# mise (runtime version manager)
if command -v mise &>/dev/null; then
  echo "==> 🔧 mise is already installed, skipping."
else
  echo "==> 🔧 Installing mise..."
  curl https://mise.run | sh >&3
fi

# Bun
if command -v bun &>/dev/null; then
  echo "==> 🍞 Bun is already installed, skipping."
else
  echo "==> 🍞 Installing Bun..."
  curl -fsSL https://bun.sh/install | bash >&3
fi

install_gh_binary "lazydocker" "jesseduffield/lazydocker" "lazydocker_.*_Linux_x86_64\\.tar\\.gz$" "lazydocker_.*_Linux_arm64\\.tar\\.gz$"

# Zsh integrations
echo "==> 🐚 Updating zshrc with tool integrations..."
add_to_zshrc() {
  local marker="$1" line="$2"
  grep -qF "$marker" "${HOME}/.zshrc" 2>/dev/null || { echo ""; echo "$line"; } >> "${HOME}/.zshrc"
}
add_to_zshrc 'zoxide init'   'eval "$(zoxide init zsh)"'
add_to_zshrc 'atuin init'    'eval "$(atuin init zsh)"'
add_to_zshrc 'mise activate' 'eval "$(mise activate zsh)"'
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
  command -v jq    &>/dev/null || dnf_quiet install -y jq
  command -v unzip &>/dev/null || dnf_quiet install -y unzip
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
