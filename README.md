# Workstation setup

One-shot install script for a Fedora/RHEL workstation: shell, fonts, IDEs, browsers, Flatpak apps, terminal and dev tools, and GNOME extensions.

## Requirements

- Fedora or RHEL (uses `dnf`)
- At least **5 GB free** disk space on `/`
- Run as your **normal user** (do not run with `sudo`; the script uses `sudo` only where needed)
- Network access

## Usage

```bash
bash install-shell-setup.sh
```

Optional:

- `--silent` — suppress install output (script messages still shown; only tool output is hidden)

## What gets installed

### Shell and prompt

- **zsh** (default shell; you may be prompted for your password to run `chsh`)
- **Starship** prompt with Catppuccin preset
- **Roboto Mono Nerd Font** (in `~/.local/share/fonts`)

### Git and GitHub

- **git** — global config: `init.defaultBranch main`, `user.name`, `user.email`
- **gh** (GitHub CLI)

### Apps (system / RPM)

- **Ranger** (file manager)
- **Tailscale**
- **Cursor** IDE
- **Claude Code** CLI (`~/.local/bin`)
- **VS Code** (from Microsoft repo)
- **Google Chrome** (x86_64)
- **WhatsApp** webapp (Chrome app window; desktop entry in `~/.local/share/applications`)

### Flatpak (Flathub)

- **GNOME Extension Manager**
- **Pika Backup**
- **Slack**
- **Obsidian** (pinned to dash when in a GNOME session)

### Containers and dev environments

- **Podman**
- **DevPod** CLI (`~/.local/bin`), with Podman provider

### System and security tools (dnf)

- **btop**, **duf**, **ncdu**
- **age**, **nmap**

### Terminal tools

- **tmux**, **fzf**, **bat**, **ripgrep**, **fd-find**, **zoxide**, **atuin**, **vim** (dnf)
- **eza**, **lazygit**, **delta** (GitHub releases → `~/.local/bin`)

### Dev tools

- **yq**, **direnv** (dnf)
- **xh**, **lazydocker** (GitHub releases → `~/.local/bin`)
- **Bun** (install script → `~/.bun`)

### GNOME extensions (when in a GNOME session)

- Dash2Dock Animated  
- Tailscale Status  
- Blur my Shell  
- Clipboard History  
- Kiwi  
- AppIndicator Support  

### Dash pins (when in a graphical session)

Cursor, Chrome, WhatsApp, and Obsidian are pinned to the GNOME dash if installed and in a GNOME session.

## After running

- Restart your terminal or run: `exec zsh`
- Set **Roboto Mono Nerd Font** in your terminal profile for icons
- Log out and back in for GNOME extensions to become active
