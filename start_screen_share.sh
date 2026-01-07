#!/bin/bash
set -euo pipefail

# ==========================================
# Linux Mint: Screen Sharing per x11vnc
# - installiert x11vnc automatisch (falls fehlt)
# - erstellt Passwortdatei einmalig
# - startet VNC auf Port 5900
#  usage: chmod +x start_screen_share.sh
#  ./start_screen_share.sh
# ==========================================

PASSFILE="$HOME/.vnc/passwd"
DISPLAY_ID="${DISPLAY:-:0}"
XAUTHORITY_FILE="${XAUTHORITY:-$HOME/.Xauthority}"
PORT="5900"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

install_x11vnc_if_needed() {
  if need_cmd x11vnc; then
    echo "==> x11vnc ist vorhanden: $(command -v x11vnc)"
    return
  fi

  echo "==> x11vnc nicht gefunden → installiere via apt (sudo)..."
  sudo apt update
  sudo apt install -y x11vnc

  if ! need_cmd x11vnc; then
    echo "FEHLER: x11vnc wurde installiert, aber ist weiterhin nicht im PATH."
    echo "Teste: /usr/bin/x11vnc -version"
    exit 1
  fi
}

ensure_passfile() {
  if [[ -f "$PASSFILE" ]]; then
    echo "==> Passwortdatei vorhanden: $PASSFILE"
    return
  fi

  echo "==> Erstelle VNC-Passwort (einmalig)."
  mkdir -p "$HOME/.vnc"
  # Fragt interaktiv nach Passwort und schreibt HASH in PASSFILE
  x11vnc -storepasswd "$PASSFILE"
  chmod 600 "$PASSFILE"
}

echo "==> Starte Linux Mint Bildschirmübertragung (x11vnc)"
echo "    DISPLAY=$DISPLAY_ID"
echo "    XAUTHORITY=$XAUTHORITY_FILE"
echo "    PORT=$PORT"

install_x11vnc_if_needed

if [[ ! -f "$XAUTHORITY_FILE" ]]; then
  echo "FEHLER: XAUTHORITY nicht gefunden: $XAUTHORITY_FILE"
  echo "Bist du wirklich im grafischen Login angemeldet (Cinnamon/X11)?"
  exit 1
fi

ensure_passfile

echo "==> x11vnc wird gestartet (beenden mit Ctrl+C)"
exec x11vnc \
  -display "$DISPLAY_ID" \
  -auth "$XAUTHORITY_FILE" \
  -rfbauth "$PASSFILE" \
  -rfbport "$PORT" \
  -forever \
  -shared \
  -noxdamage \
  -repeat \
  -nomodtweak \
  -noshm

