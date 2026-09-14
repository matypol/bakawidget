#!/usr/bin/env bash
# Reverses install.sh: stops/removes the backend service, clears stored
# credentials (KWallet entry + local state), and removes the plasmoid.
set -uo pipefail

PLUGIN_ID="bakawidget"
PLUGIN_DIR="$HOME/.local/share/plasma/plasmoids/$PLUGIN_ID"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "==> Logging out / clearing stored credentials…"
if [ -f "$PLUGIN_DIR/contents/backend/bakawidget_backend.py" ]; then
    python3 "$PLUGIN_DIR/contents/backend/bakawidget_backend.py" logout || true
fi

echo "==> Stopping and removing the backend service…"
systemctl --user disable --now bakawidget-backend.service 2>/dev/null || true
rm -f "$SYSTEMD_USER_DIR/bakawidget-backend.service"
systemctl --user daemon-reload

echo "==> Removing the plasmoid…"
kpackagetool6 -t Plasma/Applet -r "$PLUGIN_ID" || true

echo "Done. Remove the widget from your panel too, if you haven't already (right-click it → Remove)."
