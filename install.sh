#!/usr/bin/env bash
# Quick local install: plasmoid package + systemd --user backend service.
# For a real pacman package instead, see PKGBUILD ("makepkg -si").
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="bakawidget"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "error: kpackagetool6 not found — install plasma-workspace first." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found (pacman -S python)." >&2
    exit 1
fi

if ! python3 -c "import dbus" >/dev/null 2>&1; then
    echo "error: the Python 'dbus' module is missing (pacman -S python-dbus)." >&2
    echo "       This is required for storing your Bakaláři token in KWallet." >&2
    exit 1
fi

echo "==> Installing the plasmoid…"
if kpackagetool6 -t Plasma/Applet -s "$PLUGIN_ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$HERE"
else
    kpackagetool6 -t Plasma/Applet -i "$HERE"
fi

echo "==> Installing the systemd --user backend service…"
mkdir -p "$SYSTEMD_USER_DIR"
cp "$HERE/systemd/bakawidget-backend.service" "$SYSTEMD_USER_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now bakawidget-backend.service

cat <<'EOF'

Done. Next steps:
  1. Add "BakaWidget" to a panel (right-click panel → Add Widgets…).
  2. Right-click the widget → Configure… → enter your subdomain/username/password → Log in.

To remove everything later, run ./uninstall.sh from this same directory.
EOF
