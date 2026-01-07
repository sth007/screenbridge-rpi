#!/bin/bash
set -euo pipefail

# ==========================================================
# setup_pi1_autovnc_with_webui.sh  (RPi 1 / ARMv6)
#
# Ziel:
#   Linux Laptop (VNC-Server)  -->  Raspberry Pi 1 (VNC-Client) --> HDMI/TV
#
# Features:
# - Minimal GUI: LightDM + Openbox + LXPanel
# - Xorg auf fbdev gezwungen (HDMI zuverlässig auf RPi1)
# - Auto-Login pi, kein CLI-Login am HDMI
# - WebUI (HTTPS via Nginx) zum Setzen von:
#     * WLAN SSID/Pass
#     * VNC Host (IP/Hostname des Linux-Laptops)
#     * VNC Passwort (wird als vncviewer -passwd file gespeichert)
#     * Fullscreen/ViewOnly/Quality/Compress/Delay
#     * HDMI-Auflösung (720p/1080p) -> Reboot erforderlich
# - Autostart: VNC Viewer startet automatisch in X :0 nach Boot
#
# WebUI:
#   https://<PI-IP>   (Self-signed Zertifikat)
# ==========================================================

# --------------- WebUI Login (ändern!) ---------------
WEBUI_USER="admin"
WEBUI_PASS="admin123"

# --------------- Defaults ---------------
DEFAULT_WIFI_COUNTRY="DE"
DEFAULT_WIFI_SSID=""
DEFAULT_WIFI_PASS=""

DEFAULT_VNC_HOST="192.168.178.21"   # Linux-Laptop IP/Hostname
DEFAULT_VNC_PASS=""                 # VNC Passwort (wird als Datei gespeichert)

DEFAULT_VNC_FULLSCREEN="true"
DEFAULT_VNC_VIEWONLY="true"
DEFAULT_VNC_QUALITY="4"             # 0..9
DEFAULT_VNC_COMPRESS="5"            # 0..9
DEFAULT_WAIT_AFTER_BOOT="20"        # Sekunden

# HDMI Output Mode (WebUI: 720p/1080p)
# Valid:
#   720p  -> 1280x720  (hdmi_mode=4, group=1)
#   1080p -> 1920x1080 (hdmi_mode=16, group=1)  (kann auf Pi1 schwer sein)
DEFAULT_OUTPUT_MODE="720p"

TARGET_USER="pi"
TARGET_HOME="/home/pi"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen: sudo $0"
  exit 1
fi

echo "==> Pakete installieren..."
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates openssl \
  rfkill wireless-tools wpasupplicant dhcpcd5 \
  xserver-xorg xinit x11-xserver-utils x11-utils \
  xserver-xorg-video-fbdev \
  openbox lxpanel pcmanfm \
  lightdm lightdm-gtk-greeter \
  unclutter \
  nginx \
  python3 python3-flask \
  net-tools \
  xtightvncviewer tightvncserver \
  wmctrl

# ----------------------------------------------------------
# Verzeichnisse
# ----------------------------------------------------------
echo "==> Verzeichnisse anlegen..."
install -d -m 0755 /opt/autovnc/bin
install -d -m 0755 /opt/autovnc/web
install -d -m 0755 /etc/nginx/ssl

# ----------------------------------------------------------
# HDMI/Xorg Fix (RPi1): fbdev erzwingen + vc4 overlays entfernen
# ----------------------------------------------------------
echo "==> RPi1 HDMI/Xorg Fix (fbdev)..."

BOOTCFG="/boot/config.txt"
if [[ -f "$BOOTCFG" ]]; then
  # Entferne vc4 overlays (kms/fkms)
  sed -i '/^dtoverlay=vc4-kms-v3d/d' "$BOOTCFG" || true
  sed -i '/^dtoverlay=vc4-fkms-v3d/d' "$BOOTCFG" || true

  # Basisblock (nur einmal)
  grep -q "RPi1 HDMI + X11 FIX (AutoVNC)" "$BOOTCFG" || cat >>"$BOOTCFG" <<'EOF'

# === RPi1 HDMI + X11 FIX (AutoVNC) ===
# NOTE: output_mode wird durch /opt/autovnc/bin/apply_config.sh gepflegt
hdmi_force_hotplug=1
disable_overscan=1
gpu_mem=128

# Default (wird ggf. überschrieben):
hdmi_group=1
hdmi_mode=4
framebuffer_width=1280
framebuffer_height=720
EOF
fi

# Xorg fbdev config
install -d -m 0755 /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/99-fbdev.conf <<'EOF'
Section "Device"
    Identifier "Raspberry Pi FBDEV"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection
EOF

# ----------------------------------------------------------
# config.json
# ----------------------------------------------------------
CONFIG="/opt/autovnc/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "==> Default config.json erstellen..."
  cat >"$CONFIG" <<EOF
{
  "wifi_country": "$DEFAULT_WIFI_COUNTRY",
  "wifi_ssid": "$DEFAULT_WIFI_SSID",
  "wifi_pass": "$DEFAULT_WIFI_PASS",

  "vnc_host": "$DEFAULT_VNC_HOST",
  "vnc_pass": "$DEFAULT_VNC_PASS",

  "vnc_fullscreen": $DEFAULT_VNC_FULLSCREEN,
  "vnc_viewonly": $DEFAULT_VNC_VIEWONLY,
  "vnc_quality": $DEFAULT_VNC_QUALITY,
  "vnc_compress": $DEFAULT_VNC_COMPRESS,

  "wait_after_boot": $DEFAULT_WAIT_AFTER_BOOT,

  "output_mode": "$DEFAULT_OUTPUT_MODE"
}
EOF
  chmod 600 "$CONFIG"
fi

# ----------------------------------------------------------
# apply_config.sh
# - WLAN
# - VNC pass file
# - start-vnc.sh
# - HDMI output_mode in /boot/config.txt (Reboot nötig)
# ----------------------------------------------------------
APPLY="/opt/autovnc/bin/apply_config.sh"
cat >"$APPLY" <<'EOF'
#!/bin/bash
set -euo pipefail

CFG="/opt/autovnc/config.json"
BOOTCFG="/boot/config.txt"
REBOOT_FLAG="/opt/autovnc/reboot_required"

py_get() {
  local k="$1"
  python3 - <<PY
import json
cfg=json.load(open("$CFG"))
v=cfg.get("$k","")
print(v if v is not None else "")
PY
}

py_get_bool() {
  local k="$1"
  python3 - <<PY
import json
cfg=json.load(open("$CFG"))
v=cfg.get("$k", False)
print("true" if bool(v) else "false")
PY
}

py_get_int() {
  local k="$1"
  python3 - <<PY
import json
cfg=json.load(open("$CFG"))
v=cfg.get("$k", 0)
try: print(int(v))
except: print(0)
PY
}

WIFI_COUNTRY="$(py_get wifi_country)"
WIFI_SSID="$(py_get wifi_ssid)"
WIFI_PASS="$(py_get wifi_pass)"

VNC_HOST="$(py_get vnc_host)"
VNC_PASS="$(py_get vnc_pass)"

FULLSCREEN="$(py_get_bool vnc_fullscreen)"
VIEWONLY="$(py_get_bool vnc_viewonly)"
QUALITY="$(py_get_int vnc_quality)"
COMPRESS="$(py_get_int vnc_compress)"
WAIT="$(py_get_int wait_after_boot)"

OUTPUT_MODE="$(py_get output_mode)"

[[ -z "$WIFI_COUNTRY" ]] && WIFI_COUNTRY="DE"
[[ -z "$VNC_HOST" ]] && VNC_HOST="127.0.0.1"
[[ $QUALITY -lt 0 ]] && QUALITY=0
[[ $QUALITY -gt 9 ]] && QUALITY=9
[[ $COMPRESS -lt 0 ]] && COMPRESS=0
[[ $COMPRESS -gt 9 ]] && COMPRESS=9
[[ $WAIT -lt 0 ]] && WAIT=0
[[ -z "$OUTPUT_MODE" ]] && OUTPUT_MODE="720p"

echo "==> [apply] WLAN SSID=${WIFI_SSID:-<leer>} | VNC host=$VNC_HOST | wait=$WAIT | output_mode=$OUTPUT_MODE"

# --- WLAN anwenden (nur wenn SSID gesetzt) ---
if [[ -n "$WIFI_SSID" ]]; then
  WPA="/etc/wpa_supplicant/wpa_supplicant.conf"
  mkdir -p /etc/wpa_supplicant
  cp -a "$WPA" "${WPA}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

  cat >"$WPA" <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=$WIFI_COUNTRY

WPAEOF
  wpa_passphrase "$WIFI_SSID" "$WIFI_PASS" >> "$WPA"

  chmod 600 "$WPA"
  chown root:root "$WPA"

  rfkill unblock wifi || true
  systemctl restart wpa_supplicant >/dev/null 2>&1 || true
  systemctl restart dhcpcd >/dev/null 2>&1 || true
fi

# --- HDMI output_mode setzen (boot/config.txt) ---
# 720p: group=1 mode=4  framebuffer 1280x720
# 1080p: group=1 mode=16 framebuffer 1920x1080
# Wir setzen nur dann reboot_required, wenn sich Werte ändern.
desired_group="1"
desired_mode="4"
desired_w="1280"
desired_h="720"

case "$OUTPUT_MODE" in
  720p|720P)
    desired_group="1"; desired_mode="4"; desired_w="1280"; desired_h="720"
    ;;
  1080p|1080P)
    desired_group="1"; desired_mode="16"; desired_w="1920"; desired_h="1080"
    ;;
  *)
    echo "WARN: output_mode '$OUTPUT_MODE' unbekannt -> fallback 720p"
    desired_group="1"; desired_mode="4"; desired_w="1280"; desired_h="720"
    ;;
esac

if [[ -f "$BOOTCFG" ]]; then
  cur_group="$(grep -E '^hdmi_group=' "$BOOTCFG" | tail -n1 | cut -d= -f2 || true)"
  cur_mode="$(grep -E '^hdmi_mode=' "$BOOTCFG" | tail -n1 | cut -d= -f2 || true)"
  cur_w="$(grep -E '^framebuffer_width=' "$BOOTCFG" | tail -n1 | cut -d= -f2 || true)"
  cur_h="$(grep -E '^framebuffer_height=' "$BOOTCFG" | tail -n1 | cut -d= -f2 || true)"

  changed="no"
  [[ "$cur_group" != "$desired_group" ]] && changed="yes"
  [[ "$cur_mode"  != "$desired_mode"  ]] && changed="yes"
  [[ "$cur_w"     != "$desired_w"     ]] && changed="yes"
  [[ "$cur_h"     != "$desired_h"     ]] && changed="yes"

  # Replace or append lines
  grep -q '^hdmi_group=' "$BOOTCFG" && sed -i "s/^hdmi_group=.*/hdmi_group=$desired_group/" "$BOOTCFG" || echo "hdmi_group=$desired_group" >>"$BOOTCFG"
  grep -q '^hdmi_mode=' "$BOOTCFG" && sed -i "s/^hdmi_mode=.*/hdmi_mode=$desired_mode/" "$BOOTCFG" || echo "hdmi_mode=$desired_mode" >>"$BOOTCFG"
  grep -q '^framebuffer_width=' "$BOOTCFG" && sed -i "s/^framebuffer_width=.*/framebuffer_width=$desired_w/" "$BOOTCFG" || echo "framebuffer_width=$desired_w" >>"$BOOTCFG"
  grep -q '^framebuffer_height=' "$BOOTCFG" && sed -i "s/^framebuffer_height=.*/framebuffer_height=$desired_h/" "$BOOTCFG" || echo "framebuffer_height=$desired_h" >>"$BOOTCFG"

  if [[ "$changed" == "yes" ]]; then
    echo "==> [apply] HDMI output geändert -> Reboot erforderlich"
    date > "$REBOOT_FLAG"
  else
    rm -f "$REBOOT_FLAG" || true
  fi
fi

# --- VNC Passwortdatei erzeugen (für vncviewer -passwd) ---
mkdir -p /home/pi/.vnc
chown -R pi:pi /home/pi/.vnc
chmod 700 /home/pi/.vnc

PASSFILE="/home/pi/.vnc/client.passwd"
if [[ -n "$VNC_PASS" ]]; then
  printf "%s\n" "$VNC_PASS" | vncpasswd -f > "$PASSFILE"
  chown pi:pi "$PASSFILE"
  chmod 600 "$PASSFILE"
  echo "==> [apply] VNC Passwortdatei aktualisiert: $PASSFILE"
else
  rm -f "$PASSFILE" || true
  echo "==> [apply] Kein VNC Passwort gesetzt (PASSFILE entfernt)"
fi

# --- start-vnc.sh erzeugen ---
ARGS=""
[[ "$FULLSCREEN" == "true" ]] && ARGS="$ARGS -fullscreen"
[[ "$VIEWONLY" == "true" ]] && ARGS="$ARGS -viewonly"

cat >/home/pi/autovnc/start-vnc.sh <<START
#!/bin/bash
set -e

export DISPLAY=:0
export XAUTHORITY=/home/pi/.Xauthority

# kein Blank/DPMS
xset s off || true
xset -dpms || true
xset s noblank || true

LOG=/home/pi/autovnc/vnc.log
exec >>"\$LOG" 2>&1
echo "=== vnc start \$(date) ==="
echo "DISPLAY=\$DISPLAY XAUTHORITY=\$XAUTHORITY"
echo "Host: $VNC_HOST"

sleep $WAIT

# Port check
nc -z -w2 "$VNC_HOST" 5900 && echo "Port 5900 erreichbar" || echo "WARN: Port 5900 nicht erreichbar"

if [[ -f "$PASSFILE" ]]; then
  exec vncviewer $ARGS -quality $QUALITY -compresslevel $COMPRESS -passwd "$PASSFILE" "$VNC_HOST"
else
  echo "WARN: Kein Passwortfile vorhanden -> vncviewer könnte auf Eingabe warten."
  exec vncviewer $ARGS -quality $QUALITY -compresslevel $COMPRESS "$VNC_HOST"
fi
START

chmod 0755 /home/pi/autovnc/start-vnc.sh
chown -R pi:pi /home/pi/autovnc

echo "==> [apply] start-vnc.sh aktualisiert."
EOF

chmod 0755 "$APPLY"
chown root:root "$APPLY"

# ----------------------------------------------------------
# WebUI (Flask, lokal 127.0.0.1:8080) + BasicAuth
# ----------------------------------------------------------
CREDS="/opt/autovnc/web/creds.env"
cat >"$CREDS" <<EOF
WEBUI_USER=$WEBUI_USER
WEBUI_PASS=$WEBUI_PASS
EOF
chmod 600 "$CREDS"
chown root:root "$CREDS"

APP="/opt/autovnc/web/app.py"
cat >"$APP" <<'EOF'
import os, json, base64, subprocess
from flask import Flask, request, Response

CFG="/opt/autovnc/config.json"
CREDS="/opt/autovnc/web/creds.env"
APPLY="/opt/autovnc/bin/apply_config.sh"
REBOOT_FLAG="/opt/autovnc/reboot_required"

app = Flask(__name__)

def load_creds():
    user="admin"; pw="admin123"
    try:
        with open(CREDS,"r",encoding="utf-8") as f:
            for line in f:
                if line.startswith("WEBUI_USER="): user=line.strip().split("=",1)[1]
                if line.startswith("WEBUI_PASS="): pw=line.strip().split("=",1)[1]
    except:
        pass
    return user, pw

def authed():
    h = request.headers.get("Authorization","")
    if not h.lower().startswith("basic "): return False
    try:
        raw = base64.b64decode(h.split(" ",1)[1].strip()).decode("utf-8")
        u,p = raw.split(":",1)
        user,pw = load_creds()
        return (u==user and p==pw)
    except:
        return False

def require_auth():
    return Response("Auth required",401,{"WWW-Authenticate":'Basic realm="AutoVNC"'})

def read_cfg():
    with open(CFG,"r",encoding="utf-8") as f:
        return json.load(f)

def write_cfg(cfg):
    with open(CFG,"w",encoding="utf-8") as f:
        json.dump(cfg,f,indent=2)

def reboot_required():
    return os.path.exists(REBOOT_FLAG)

PAGE = """
<!doctype html>
<html><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>AutoVNC Config</title>
<style>
body{{font-family:system-ui,-apple-system,sans-serif;max-width:900px;margin:20px auto;padding:0 14px}}
.row{{display:grid;grid-template-columns:1fr 1fr;gap:12px}}
input,select{{width:100%;padding:10px;margin:6px 0 14px 0}}
.ok{{background:#e8ffe8;padding:10px;border:1px solid #b4f0b4;border-radius:10px}}
.warn{{background:#fff3cd;padding:10px;border:1px solid #ffe69c;border-radius:10px}}
.small{{color:#555}}
button{{padding:12px;width:100%}}
hr{{margin:18px 0}}
</style></head>
<body>
<h2>AutoVNC Konfiguration (Linux → RPi1 → HDMI)</h2>
<p class="small">
VNC Host ist die IP/Hostname deines Linux-Laptops. Dort muss ein VNC-Server auf Port 5900 laufen.
</p>
{msg}
<form method="post" action="/save">
<h3>WLAN</h3>
<div class="row">
  <div><label>Land</label><input name="wifi_country" value="{wifi_country}"/></div>
  <div><label>Start-Verzögerung (Sek.)</label><input name="wait_after_boot" value="{wait_after_boot}"/></div>
</div>
<label>SSID</label><input name="wifi_ssid" value="{wifi_ssid}"/>
<label>Passwort</label><input name="wifi_pass" value="{wifi_pass}"/>

<h3>HDMI / Auflösung</h3>
<label>Output Mode (Reboot erforderlich)</label>
<select name="output_mode">
  <option value="720p" {om_720}>720p (1280x720) – empfohlen</option>
  <option value="1080p" {om_1080}>1080p (1920x1080) – evtl. langsam auf Pi1</option>
</select>

<h3>VNC</h3>
<label>VNC Host (Linux Laptop IP/Hostname)</label><input name="vnc_host" value="{vnc_host}"/>

<label>VNC Passwort (wird auf dem Pi als Datei gespeichert)</label>
<input name="vnc_pass" value="{vnc_pass}" placeholder="leer = nicht empfohlen"/>

<div class="row">
  <div>
    <label>Fullscreen</label>
    <select name="vnc_fullscreen">
      <option value="true" {fs_t}>true</option>
      <option value="false" {fs_f}>false</option>
    </select>
  </div>
  <div>
    <label>ViewOnly</label>
    <select name="vnc_viewonly">
      <option value="true" {vo_t}>true</option>
      <option value="false" {vo_f}>false</option>
    </select>
  </div>
</div>

<div class="row">
  <div><label>Quality (0..9)</label><input name="vnc_quality" value="{vnc_quality}"/></div>
  <div><label>Compress (0..9)</label><input name="vnc_compress" value="{vnc_compress}"/></div>
</div>

<button type="submit">Speichern & Anwenden</button>
</form>

{reboot_block}

<hr/>
<p class="small">
WebUI läuft intern auf 127.0.0.1:8080, außen via HTTPS über Nginx.
</p>
</body></html>
"""

@app.route("/", methods=["GET"])
def index():
    if not authed(): return require_auth()
    cfg=read_cfg()

    reboot_block = ""
    if reboot_required():
        reboot_block = """
        <div class="warn">
          <b>Reboot erforderlich</b> (Auflösung/HDMI wurde geändert).<br/>
          <form method="post" action="/reboot" style="margin-top:10px">
            <button type="submit">Jetzt neu starten</button>
          </form>
        </div>
        """

    return PAGE.format(
        msg="",
        wifi_country=cfg.get("wifi_country","DE"),
        wifi_ssid=cfg.get("wifi_ssid",""),
        wifi_pass=cfg.get("wifi_pass",""),
        vnc_host=cfg.get("vnc_host",""),
        vnc_pass=cfg.get("vnc_pass",""),
        vnc_quality=str(cfg.get("vnc_quality",4)),
        vnc_compress=str(cfg.get("vnc_compress",5)),
        wait_after_boot=str(cfg.get("wait_after_boot",20)),
        fs_t="selected" if cfg.get("vnc_fullscreen",True) else "",
        fs_f="selected" if not cfg.get("vnc_fullscreen",True) else "",
        vo_t="selected" if cfg.get("vnc_viewonly",True) else "",
        vo_f="selected" if not cfg.get("vnc_viewonly",True) else "",
        om_720="selected" if cfg.get("output_mode","720p")=="720p" else "",
        om_1080="selected" if cfg.get("output_mode","720p")=="1080p" else "",
        reboot_block=reboot_block
    )

@app.route("/save", methods=["POST"])
def save():
    if not authed(): return require_auth()
    cfg=read_cfg()

    cfg["wifi_country"]=request.form.get("wifi_country","DE").strip() or "DE"
    cfg["wifi_ssid"]=request.form.get("wifi_ssid","").strip()
    cfg["wifi_pass"]=request.form.get("wifi_pass","")

    cfg["output_mode"]=request.form.get("output_mode","720p").strip() or "720p"

    cfg["vnc_host"]=request.form.get("vnc_host","").strip()
    cfg["vnc_pass"]=request.form.get("vnc_pass","")

    cfg["vnc_fullscreen"]=(request.form.get("vnc_fullscreen","true")=="true")
    cfg["vnc_viewonly"]=(request.form.get("vnc_viewonly","true")=="true")

    try: cfg["vnc_quality"]=int(request.form.get("vnc_quality","4"))
    except: cfg["vnc_quality"]=4

    try: cfg["vnc_compress"]=int(request.form.get("vnc_compress","5"))
    except: cfg["vnc_compress"]=5

    try: cfg["wait_after_boot"]=int(request.form.get("wait_after_boot","20"))
    except: cfg["wait_after_boot"]=20

    write_cfg(cfg)

    msg=""
    try:
        subprocess.run([APPLY], check=False)
        msg='<div class="ok">Gespeichert & angewendet. WLAN/VNC/HDMI wurde aktualisiert.</div>'
    except Exception as e:
        msg=f'<div class="warn">Gespeichert, aber Apply-Fehler: {e}</div>'

    # Reboot block einfügen
    reboot_block = ""
    if reboot_required():
        reboot_block = """
        <div class="warn">
          <b>Reboot erforderlich</b> (Auflösung/HDMI wurde geändert).<br/>
          <form method="post" action="/reboot" style="margin-top:10px">
            <button type="submit">Jetzt neu starten</button>
          </form>
        </div>
        """

    cfg=read_cfg()
    return PAGE.format(
        msg=msg,
        wifi_country=cfg.get("wifi_country","DE"),
        wifi_ssid=cfg.get("wifi_ssid",""),
        wifi_pass=cfg.get("wifi_pass",""),
        vnc_host=cfg.get("vnc_host",""),
        vnc_pass=cfg.get("vnc_pass",""),
        vnc_quality=str(cfg.get("vnc_quality",4)),
        vnc_compress=str(cfg.get("vnc_compress",5)),
        wait_after_boot=str(cfg.get("wait_after_boot",20)),
        fs_t="selected" if cfg.get("vnc_fullscreen",True) else "",
        fs_f="selected" if not cfg.get("vnc_fullscreen",True) else "",
        vo_t="selected" if cfg.get("vnc_viewonly",True) else "",
        vo_f="selected" if not cfg.get("vnc_viewonly",True) else "",
        om_720="selected" if cfg.get("output_mode","720p")=="720p" else "",
        om_1080="selected" if cfg.get("output_mode","720p")=="1080p" else "",
        reboot_block=reboot_block
    )

@app.route("/reboot", methods=["POST"])
def do_reboot():
    if not authed(): return require_auth()
    try:
        subprocess.Popen(["/usr/sbin/reboot"])
    except:
        pass
    return Response("Rebooting...", 200, {"Content-Type": "text/plain"})

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
EOF

chmod 0644 "$APP"
chown root:root "$APP"

# systemd service für WebUI
WEB_SERVICE="/etc/systemd/system/autovnc-web.service"
cat >"$WEB_SERVICE" <<EOF
[Unit]
Description=AutoVNC Web Config UI (Flask)
After=network.target

[Service]
Type=simple
EnvironmentFile=$CREDS
ExecStart=/usr/bin/python3 $APP
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable autovnc-web.service >/dev/null 2>&1 || true
systemctl restart autovnc-web.service >/dev/null 2>&1 || true

# ----------------------------------------------------------
# HTTPS via Nginx (Self-signed)
# ----------------------------------------------------------
CRT="/etc/nginx/ssl/autovnc.crt"
KEY="/etc/nginx/ssl/autovnc.key"
if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
  echo "==> Self-signed Zertifikat erzeugen..."
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout "$KEY" -out "$CRT" -subj "/CN=autovnc.local" >/dev/null 2>&1 || true
  chmod 600 "$KEY"
  chmod 644 "$CRT"
fi

NG_SITE="/etc/nginx/sites-available/autovnc"
cat >"$NG_SITE" <<'EOF'
server {
  listen 80;
  server_name _;
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl;
  server_name _;

  ssl_certificate     /etc/nginx/ssl/autovnc.crt;
  ssl_certificate_key /etc/nginx/ssl/autovnc.key;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $remote_addr;
  }
}
EOF

ln -sf "$NG_SITE" /etc/nginx/sites-enabled/autovnc
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl enable nginx >/dev/null 2>&1 || true
systemctl restart nginx >/dev/null 2>&1 || true

# ----------------------------------------------------------
# GUI: Autologin + Openbox Autostart
# ----------------------------------------------------------
echo "==> GUI Autologin + Openbox Autostart..."

systemctl set-default graphical.target >/dev/null 2>&1 || true

mkdir -p /etc/lightdm/lightdm.conf.d
cat >/etc/lightdm/lightdm.conf.d/12-autologin.conf <<'EOF'
[Seat:*]
autologin-user=pi
autologin-user-timeout=0
user-session=openbox
EOF

echo 'exec openbox-session' > /home/pi/.xsession
chown pi:pi /home/pi/.xsession
chmod 0644 /home/pi/.xsession

mkdir -p /home/pi/.config/openbox
cat >/home/pi/.config/openbox/autostart <<'EOF'
lxpanel &
unclutter -idle 0.5 -root &
/home/pi/autovnc/start-vnc.sh &
EOF
chown -R pi:pi /home/pi/.config/openbox
chmod 0644 /home/pi/.config/openbox/autostart

systemctl enable lightdm >/dev/null 2>&1 || true

# initial apply
echo "==> Initial apply_config..."
bash "$APPLY" || true

echo
echo "=================================================="
echo "FERTIG ✅"
echo "WebUI (HTTPS): https://<PI-IP>"
echo "Login: $WEBUI_USER / $WEBUI_PASS"
echo "Hinweis: Nach Änderung der Auflösung ist ein Reboot nötig."
echo "=================================================="

