#!/bin/bash
set -euo pipefail

# ==========================================
# Linux Mint: x11vnc als systemd USER Service
# ==========================================
# - Startet den aktuell eingeloggten Desktop (X11) via VNC
# - Port: 5900
# - Passwort: ~/.vnc/passwd (einmalig setzen)
# - Service: systemctl --user (läuft pro Benutzer-Session)
#
# Usage:
#   chmod +x setup_mint_x11vnc_systemd.sh
#   ./setup_mint_x11vnc_systemd.sh
#
# Danach:
#   systemctl --user status x11vnc.service
#   journalctl --user -u x11vnc.service -f
# ==========================================

SERVICE_NAME="x11vnc.service"
PASSFILE="$HOME/.vnc/passwd"
USER_UNIT_DIR="$HOME/.config/systemd/user"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

echo "==> Prüfe / installiere x11vnc..."
if ! need_cmd x11vnc; then
  sudo apt update
  sudo apt install -y x11vnc
fi

echo "==> Erzeuge Passwortdatei (falls nicht vorhanden): $PASSFILE"
if [[ ! -f "$PASSFILE" ]]; then
  mkdir -p "$HOME/.vnc"
  echo
  echo "Setze jetzt das VNC-Passwort (wird am RPi in der WebUI eingetragen):"
  x11vnc -storepasswd "$PASSFILE"
  chmod 600 "$PASSFILE"
fi

echo "==> Erzeuge systemd User Unit: $USER_UNIT_DIR/$SERVICE_NAME"
mkdir -p "$USER_UNIT_DIR"

cat >"$USER_UNIT_DIR/$SERVICE_NAME" <<'EOF'
[Unit]
Description=x11vnc - Share current X11 desktop over VNC (Port 5900)
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=simple

# WICHTIG:
# Für Linux Mint Cinnamon unter X11 ist DISPLAY meistens :0.
# XAUTHORITY liegt i.d.R. in ~/.Xauthority.
Environment=DISPLAY=:0
Environment=XAUTHORITY=%h/.Xauthority

# Optional: Wenn du mehrere Monitore hast und "falsches" Display siehst,
# kann DISPLAY auch :1 oder ähnlich sein.
# Dann später hier ändern.

ExecStart=/usr/bin/x11vnc \
  -display ${DISPLAY} \
  -auth ${XAUTHORITY} \
  -rfbauth %h/.vnc/passwd \
  -rfbport 5900 \
  -forever \
  -shared \
  -noxdamage \
  -repeat \
  -nomodtweak \
  -noshm

Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF

echo "==> systemd user daemon reload + enable + start..."
systemctl --user daemon-reload
systemctl --user enable --now x11vnc.service

echo
echo "=================================================="
echo "FERTIG ✅ x11vnc läuft als systemd USER Service"
echo
echo "Status:"
echo "  systemctl --user status x11vnc.service"
echo
echo "Logs live:"
echo "  journalctl --user -u x11vnc.service -f"
echo
echo "Stop/Start:"
echo "  systemctl --user stop x11vnc.service"
echo "  systemctl --user start x11vnc.service"
echo
echo "Hinweis: Der Service startet automatisch, sobald DU dich grafisch einloggst."
echo "Port: 5900  | Passwort: ~/.vnc/passwd"
echo "=================================================="

