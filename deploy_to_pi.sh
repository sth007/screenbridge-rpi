#!/bin/bash
# =========== usage ===========
# chmod +x deploy_to_pi.sh
# ./deploy_to_pi.sh
# ./deploy_to_pi.sh --host 192.168.178.66 --reboot
# ./deploy_to_pi.sh --help
# =============================

set -e

# -----------------------------
# Defaults
# -----------------------------
PI_HOST="raspberrypi.local"
PI_USER="pi"
LOCAL_SCRIPT="./setup_pi1_autovnc_with_webui.sh"
REMOTE_SCRIPT="/home/pi/setup_pi1_autovnc_with_webui.sh"
DO_REBOOT="no"
DO_KEYSETUP="yes"

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_PUB="$SSH_KEY.pub"

# -----------------------------
# Helper functions
# -----------------------------
die() {
  echo "❌ $*" >&2
  exit 1
}

help() {
  cat <<EOF
Deploy setup script to Raspberry Pi via SSH.

Options:
  --host <host>       Hostname/IP of Pi (default: raspberrypi.local)
  --user <user>       SSH user (default: pi)
  --script <path>     Local setup script
  --remote <path>     Remote path on Pi
  --no-key            Skip ssh-keygen / ssh-copy-id
  --reboot            Reboot Pi after setup
  -h, --help          Show this help

Examples:
  ./deploy_to_pi.sh
  ./deploy_to_pi.sh --host 192.168.178.66 --reboot
EOF
}

# -----------------------------
# Argument parsing (POSIX-safe)
# -----------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --host)   PI_HOST="$2"; shift 2 ;;
    --user)   PI_USER="$2"; shift 2 ;;
    --script) LOCAL_SCRIPT="$2"; shift 2 ;;
    --remote) REMOTE_SCRIPT="$2"; shift 2 ;;
    --no-key) DO_KEYSETUP="no"; shift ;;
    --reboot) DO_REBOOT="yes"; shift ;;
    -h|--help) help; exit 0 ;;
    *)
      die "Unbekannte Option: $1 (nutze --help)"
      ;;
  esac
done

[ -f "$LOCAL_SCRIPT" ] || die "Lokales Script nicht gefunden: $LOCAL_SCRIPT"

# -----------------------------
# Preflight checks
# -----------------------------
echo "==> Preflight: Prüfe Erreichbarkeit von $PI_HOST ..."
if ! ping -c 1 -t 2 "$PI_HOST" >/dev/null 2>&1; then
  die "Host nicht per Ping erreichbar: $PI_HOST"
fi

echo "==> Preflight: Prüfe SSH Port 22 ..."
if ! nc -vz "$PI_HOST" 22 >/dev/null 2>&1; then
  die "SSH Port 22 nicht erreichbar.

👉 SSH auf dem Pi aktivieren:
   - SD-Karte am Mac einstecken
   - auf der BOOT-Partition eine leere Datei 'ssh' anlegen
     z.B.: touch /Volumes/boot/ssh"
fi

# -----------------------------
# SSH key setup (optional)
# -----------------------------
if [ "$DO_KEYSETUP" = "yes" ]; then
  echo "==> Prüfe SSH-Key (ed25519)..."
  if [ ! -f "$SSH_KEY" ]; then
    echo "    Kein Key gefunden → erstelle neuen"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
  else
    echo "    SSH-Key vorhanden"
  fi

  echo "==> Prüfe, ob Key bereits autorisiert ist..."
  if ssh -o BatchMode=yes -o ConnectTimeout=5 \
       "$PI_USER@$PI_HOST" "exit" 2>/dev/null; then
    echo "    Key ist bereits hinterlegt ✔"
  else
    echo "    Key noch nicht hinterlegt → ssh-copy-id (Passwort 1× nötig)"
    ssh-copy-id -i "$SSH_PUB" "$PI_USER@$PI_HOST"
  fi
else
  echo "==> SSH-Key-Setup übersprungen (--no-key)"
fi

# -----------------------------
# Deploy
# -----------------------------
echo "==> Kopiere Setup-Script auf den Pi..."
scp "$LOCAL_SCRIPT" "$PI_USER@$PI_HOST:$REMOTE_SCRIPT"

echo "==> Mache Script auf dem Pi ausführbar..."
ssh "$PI_USER@$PI_HOST" "chmod +x '$REMOTE_SCRIPT'"

echo "==> Führe Setup-Script per sudo aus..."
ssh -t "$PI_USER@$PI_HOST" "sudo '$REMOTE_SCRIPT'"

# -----------------------------
# Optional reboot
# -----------------------------
if [ "$DO_REBOOT" = "yes" ]; then
  echo "==> Reboot wird ausgelöst..."
  ssh -t "$PI_USER@$PI_HOST" "sudo reboot" || true
  echo "✅ Reboot ausgelöst."
else
  echo "==> Optional: Neustart des Pi? (y/n)"
  read ans
  case "$ans" in
    y|Y|yes|YES|Yes)
      ssh -t "$PI_USER@$PI_HOST" "sudo reboot" || true
      echo "✅ Reboot ausgelöst."
      ;;
    *)
      echo "✅ Fertig ohne Neustart."
      ;;
  esac
fi

