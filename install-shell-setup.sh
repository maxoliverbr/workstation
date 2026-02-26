#!/usr/bin/env bash
# Install: zsh, Roboto Mono Nerd Font, Starship (Catppuccin), Ranger, Tailscale, Cursor, Claude Code, Chrome, Slack, git (global config), GNOME Extension Manager + extensions
# For Fedora/RHEL (uses dnf). Run with: bash install-shell-setup.sh

set -e

FONT_DIR="${HOME}/.local/share/fonts"
CONFIG_DIR="${HOME}/.config"
NF_VERSION="v3.1.1"
ROBOTO_MONO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/RobotoMono.zip"
EXTENSIONS_GNOME_ORG="https://extensions.gnome.org"

if command -v zsh &>/dev/null; then
  echo "==> 🐚 zsh is already installed, skipping."
else
  echo "==> 🐚 Installing zsh..."
  sudo dnf install -y zsh
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
  fc-cache -fv
fi

export PATH="${HOME}/.local/bin:${PATH}"
if command -v starship &>/dev/null; then
  echo "==> 🚀 Starship is already installed, skipping."
else
  echo "==> 🚀 Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh -s -- -y
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
  sudo dnf install -y ranger
fi

# Tailscale
if command -v tailscale &>/dev/null; then
  echo "==> 🦾 Tailscale is already installed, skipping."
else
  echo "==> 🦾 Installing Tailscale..."
  sudo curl -sSL -o /etc/yum.repos.d/tailscale.repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  sudo dnf install -y tailscale
  sudo systemctl enable --now tailscaled
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
    sudo dnf install -y "$tmp_rpm"
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
  curl -fsSL https://claude.ai/install.sh | bash
  export PATH="${HOME}/.local/bin:${PATH}"
fi

# VS Code
if command -v code &>/dev/null; then
  echo "==> 📟 VS Code is already installed, skipping."
else
  echo "==> 📟 Installing VS Code..."
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
  sudo dnf install -y code
fi

# Google Chrome
if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
  echo "==> 🌐 Chrome is already installed, skipping."
else
  echo "==> 🌐 Installing Google Chrome..."
  case "$(uname -m)" in
    x86_64)
      if [ ! -f /etc/yum.repos.d/google-chrome.repo ]; then
        sudo sh -c 'echo -e "[google-chrome]\nname=google-chrome\nbaseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64\nenabled=1\ngpgcheck=1\ngpgkey=https://dl.google.com/linux/linux_signing_key.pub" > /etc/yum.repos.d/google-chrome.repo'
      fi
      sudo dnf install -y google-chrome-stable
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

# GitHub CLI (gh)
if command -v gh &>/dev/null; then
  echo "==> 🐙 gh is already installed, skipping."
else
  echo "==> 🐙 Installing GitHub CLI (gh)..."
  sudo dnf install -y gh
fi

# Git (install + global config)
if ! command -v git &>/dev/null; then
  echo "==> 📦 Installing git..."
  sudo dnf install -y git
fi
echo "==> 📦 Configuring git (defaultBranch, user.email, user.name)..."
git config --global init.defaultBranch main
git config --global user.email "max.oliver@cintrax.com.br"
git config --global user.name "Max Oliver"

# GNOME Extension Manager (Flatpak)
if flatpak list --app 2>/dev/null | grep -q com.mattjakeman.ExtensionManager; then
  echo "==> 🧩 GNOME Extension Manager is already installed, skipping."
else
  echo "==> 🧩 Installing GNOME Extension Manager..."
  if ! command -v flatpak &>/dev/null; then
    echo "    Installing flatpak..."
    sudo dnf install -y flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
  flatpak install -y flathub com.mattjakeman.ExtensionManager
fi

# Pika Backup (Flatpak)
if flatpak list --app 2>/dev/null | grep -q org.gnome.World.PikaBackup; then
  echo "==> 💾 Pika Backup is already installed, skipping."
else
  echo "==> 💾 Installing Pika Backup..."
  command -v flatpak &>/dev/null || { sudo dnf install -y flatpak; flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; }
  flatpak install -y flathub org.gnome.World.PikaBackup
fi

# Slack (Flatpak)
if flatpak list --app 2>/dev/null | grep -q com.slack.Slack; then
  echo "==> 💬 Slack is already installed, skipping."
else
  echo "==> 💬 Installing Slack..."
  command -v flatpak &>/dev/null || { sudo dnf install -y flatpak; flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; }
  flatpak install -y flathub com.slack.Slack
fi

# DevPod + Podman (CLI only; desktop app has EGL/WebKit issues on Fedora)
if command -v podman &>/dev/null; then
  echo "==> 🐳 Podman is already installed, skipping."
else
  echo "==> 🐳 Installing Podman..."
  sudo dnf install -y podman
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
    devpod provider add docker --name podman -o DOCKER_PATH=podman
    devpod provider use podman
  fi
fi

# GNOME extensions (Dash2Dock Animated, Tailscale Status, Blur my Shell)
install_gnome_extension() {
  local pk="$1" name="$2"
  if ! command -v gnome-extensions &>/dev/null || [ -z "${WAYLAND_DISPLAY}${DISPLAY}" ]; then
    echo "==> 🔌 Skipping $name (not in a GNOME session)."
    return
  fi
  command -v jq &>/dev/null || sudo dnf install -y jq
  local info uuid shell_major version_tag tmpzip
  info=$(curl -sL "${EXTENSIONS_GNOME_ORG}/extension-info/?pk=${pk}")
  uuid=$(echo "$info" | jq -r '.uuid')
  if gnome-extensions list 2>/dev/null | grep -qx "$uuid"; then
    echo "==> 🔌 $name is already installed, skipping."
    return
  fi
  shell_major=$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1)
  version_tag=$(echo "$info" | jq -r --arg v "$shell_major" '.shell_version_map[$v].pk // .shell_version_map | to_entries | map(select(.value.pk != null)) | sort_by(.key | tonumber) | reverse | .[0].value.pk')
  if [ -z "$version_tag" ] || [ "$version_tag" = "null" ]; then
    echo "==> 🔌 Skipping $name (no compatible version)."
    return
  fi
  echo "==> 🔌 Installing $name..."
  tmpzip=$(mktemp -u).zip
  curl -sSL "${EXTENSIONS_GNOME_ORG}/download-extension/${pk}.shell-extension.zip?version_tag=${version_tag}" -o "$tmpzip"
  gnome-extensions install --force "$tmpzip"
  rm -f "$tmpzip"
  gnome-extensions enable "$uuid"
}

install_gnome_extension 4994 "Dash2Dock Animated"
install_gnome_extension 5112 "Tailscale Status"
install_gnome_extension 3193 "Blur my Shell"

echo ""
echo "✅ Done. Restart your terminal or run: exec zsh"
echo "💡 Set Roboto Mono Nerd Font in your terminal profile for icons to show."
