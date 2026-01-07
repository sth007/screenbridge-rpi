#!/bin/bash
set -euo pipefail

# ==========================================================
# setup_pi1_autovnc_with_webui.sh  (RPi 1 / ARMv6)
# WebUI (HTTPS) für WLAN, VNC, HDMI-Auflösung, UI-Theme/Farben,
# und VNC Performance (depth/encodings/quality/compress)
# ==========================================================

WEBUI_USER="admin"
WEBUI_PASS="admin123"

DEFAULT_WIFI_COUNTRY="DE"
DEFAULT_WIFI_SSID=""
DEFAULT_WIFI_PASS=""

DEFAULT_VNC_HOST="192.168.178.21"
DEFAULT_VNC_PASS=""

DEFAULT_VNC_FULLSCREEN="true"
DEFAULT_VNC_VIEWONLY="true"

# Performance Defaults (gut für RPi1)
DEFAULT_VNC_QUALITY="3"           # 0..9
DEFAULT_VNC_COMPRESS="6"          # 0..9
DEFAULT_VNC_DEPTH="16"            # 16 oder 24
DEFAULT_VNC_ENCODINGS="stable"    # stable | raw-fast | tight-best

DEFAULT_WAIT_AFTER_BOOT="20"
DEFAULT_OUTPUT_MODE="720p"        # 720p/1080p

# WebUI theme defaults
DEFAULT_UI_THEME="dark"           # light/dark/blue/custom
DEFAULT_UI_BG="#111111"
DEFAULT_UI_FG="#eeeeee"
DEFAULT_UI_ACCENT="#4ea3ff"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen: sudo $0"
  exit 1
fi

echo "==> Installiere Pakete..."
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

echo "==> Verzeichnisse anlegen..."
install -d -m 0755 /opt/autovnc/bin
install -d -m 0755 /opt/autovnc/web
install -d -m 0755 /etc/nginx/ssl

# ----------------------------------------------------------
# HDMI/Xorg Fix: fbdev + stabile config.txt Defaults
# ----------------------------------------------------------
echo "==> HDMI/Xorg Fix (fbdev)..."
BOOTCFG="/boot/config.txt"
if [[ -f "$BOOTCFG" ]]; then
  sed -i '/^dtoverlay=vc4-kms-v3d/d' "$BOOTCFG" || true
  sed -i '/^dtoverlay=vc4-fkms-v3d/d' "$BOOTCFG" || true

  grep -q "RPi1 HDMI + X11 FIX (AutoVNC)" "$BOOTCFG" || cat >>"$BOOTCFG" <<'EOF'

# === RPi1 HDMI + X11 FIX (AutoVNC) ===
hdmi_force_hotplug=1
disable_overscan=1
gpu_mem=128

# Default HDMI Mode (wird über WebUI/apply_config gepflegt)
hdmi_group=1
hdmi_mode=4
framebuffer_width=1280
framebuffer_height=720
EOF
fi

install -d -m 0755 /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/99-fbdev.conf <<'EOF'
Section "Device"
    Identifier "Raspberry Pi FBDEV"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
EndSection
EOF

# ----------------------------------------------------------
# config.json (inkl. output_mode + ui_theme + Farben + Perf)
# ----------------------------------------------------------
CONFIG="/opt/autovnc/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "==> Erzeuge Default /opt/autovnc/config.json ..."
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
  "vnc_depth": $DEFAULT_VNC_DEPTH,
  "vnc_encodings": "$DEFAULT_VNC_ENCODINGS",

  "wait_after_boot": $DEFAULT_WAIT_AFTER_BOOT,
  "output_mode": "$DEFAULT_OUTPUT_MODE",

  "ui_theme": "$DEFAULT_UI_THEME",
  "ui_bg": "$DEFAULT_UI_BG",
  "ui_fg": "$DEFAULT_UI_FG",
  "ui_accent": "$DEFAULT_UI_ACCENT"
}
EOF
  chmod 600 "$CONFIG"
fi

# ----------------------------------------------------------
# apply_config.sh
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
print("true" if bool(cfg.get("$k", False)) else "false")
PY
}
py_get_int() {
  local k="$1"
  python3 - <<PY
import json
cfg=json.load(open("$CFG"))
try: print(int(cfg.get("$k",0)))
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
DEPTH="$(py_get_int vnc_depth)"
ENC_PRESET="$(py_get vnc_encodings)"
WAIT="$(py_get_int wait_after_boot)"

OUTPUT_MODE="$(py_get output_mode)"

[[ -z "$WIFI_COUNTRY" ]] && WIFI_COUNTRY="DE"
[[ -z "$VNC_HOST" ]] && VNC_HOST="127.0.0.1"
[[ -z "$OUTPUT_MODE" ]] && OUTPUT_MODE="720p"
[[ $QUALITY -lt 0 ]] && QUALITY=0
[[ $QUALITY -gt 9 ]] && QUALITY=9
[[ $COMPRESS -lt 0 ]] && COMPRESS=0
[[ $COMPRESS -gt 9 ]] && COMPRESS=9
[[ "$DEPTH" != "16" && "$DEPTH" != "24" ]] && DEPTH=16
[[ -z "$ENC_PRESET" ]] && ENC_PRESET="stable"

# --- WLAN ---
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

# --- HDMI output_mode ---
desired_group="1"
desired_mode="4"
desired_w="1280"
desired_h="720"

case "$OUTPUT_MODE" in
  720p|720P)  desired_group="1"; desired_mode="4";  desired_w="1280"; desired_h="720" ;;
  1080p|1080P) desired_group="1"; desired_mode="16"; desired_w="1920"; desired_h="1080" ;;
  *) desired_group="1"; desired_mode="4"; desired_w="1280"; desired_h="720" ;;
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

  grep -q '^hdmi_group=' "$BOOTCFG" && sed -i "s/^hdmi_group=.*/hdmi_group=$desired_group/" "$BOOTCFG" || echo "hdmi_group=$desired_group" >>"$BOOTCFG"
  grep -q '^hdmi_mode=' "$BOOTCFG" && sed -i "s/^hdmi_mode=.*/hdmi_mode=$desired_mode/" "$BOOTCFG" || echo "hdmi_mode=$desired_mode" >>"$BOOTCFG"
  grep -q '^framebuffer_width=' "$BOOTCFG" && sed -i "s/^framebuffer_width=.*/framebuffer_width=$desired_w/" "$BOOTCFG" || echo "framebuffer_width=$desired_w" >>"$BOOTCFG"
  grep -q '^framebuffer_height=' "$BOOTCFG" && sed -i "s/^framebuffer_height=.*/framebuffer_height=$desired_h/" "$BOOTCFG" || echo "framebuffer_height=$desired_h" >>"$BOOTCFG"

  if [[ "$changed" == "yes" ]]; then
    date > "$REBOOT_FLAG"
  else
    rm -f "$REBOOT_FLAG" || true
  fi
fi

# --- VNC client passwordfile ---
mkdir -p /home/pi/.vnc
chown -R pi:pi /home/pi/.vnc
chmod 700 /home/pi/.vnc

PASSFILE="/home/pi/.vnc/client.passwd"
if [[ -n "$VNC_PASS" ]]; then
  printf "%s\n" "$VNC_PASS" | vncpasswd -f > "$PASSFILE"
  chown pi:pi "$PASSFILE"
  chmod 600 "$PASSFILE"
else
  rm -f "$PASSFILE" || true
fi

# --- Encoding presets ---
ENC=""
case "$ENC_PRESET" in
  stable)   ENC="tight copyrect hextile raw" ;;
  raw-fast) ENC="raw" ;;
  tight-best) ENC="tight copyrect" ;;
  *)        ENC="tight copyrect hextile raw" ;;
esac

ARGS=""
[[ "$FULLSCREEN" == "true" ]] && ARGS="$ARGS -fullscreen"
[[ "$VIEWONLY" == "true" ]] && ARGS="$ARGS -viewonly"

cat >/home/pi/autovnc/start-vnc.sh <<START
#!/bin/bash
set -e
export DISPLAY=:0
export XAUTHORITY=/home/pi/.Xauthority

xset s off || true
xset -dpms || true
xset s noblank || true

LOG=/home/pi/autovnc/vnc.log
exec >>"\$LOG" 2>&1
echo "=== vnc start \$(date) ==="
echo "Host: $VNC_HOST"
echo "ENC_PRESET: $ENC_PRESET  | depth=$DEPTH | quality=$QUALITY | compress=$COMPRESS"
sleep $WAIT

if [[ -f "$PASSFILE" ]]; then
  exec vncviewer $ARGS -encodings "$ENC" -depth $DEPTH -quality $QUALITY -compresslevel $COMPRESS -passwd "$PASSFILE" "$VNC_HOST"
else
  exec vncviewer $ARGS -encodings "$ENC" -depth $DEPTH -quality $QUALITY -compresslevel $COMPRESS "$VNC_HOST"
fi
START

chmod 0755 /home/pi/autovnc/start-vnc.sh
chown -R pi:pi /home/pi/autovnc
EOF

chmod 0755 "$APPLY"
chown root:root "$APPLY"

# ----------------------------------------------------------
# WebUI: app.py (Auflösung + Theme/Farben + Perf)
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

THEMES = {
    "light":  {"bg":"#ffffff","fg":"#111111","accent":"#2a7fff"},
    "dark":   {"bg":"#111111","fg":"#eeeeee","accent":"#4ea3ff"},
    "blue":   {"bg":"#0b1c2d","fg":"#e6f0ff","accent":"#3fa9f5"},
}

def load_creds():
    u="admin"; p="admin123"
    try:
        for l in open(CREDS):
            if l.startswith("WEBUI_USER="): u=l.split("=",1)[1].strip()
            if l.startswith("WEBUI_PASS="): p=l.split("=",1)[1].strip()
    except: pass
    return u,p

def authed():
    h=request.headers.get("Authorization","")
    if not h.lower().startswith("basic "): return False
    try:
        raw=base64.b64decode(h.split(" ",1)[1]).decode()
        u,p=raw.split(":",1)
        U,P=load_creds()
        return u==U and p==P
    except:
        return False

def need_auth():
    return Response("Auth required",401,{"WWW-Authenticate":"Basic realm=AutoVNC"})

def read_cfg():
    return json.load(open(CFG))

def write_cfg(c):
    json.dump(c,open(CFG,"w"),indent=2)

def theme_css(cfg):
    t = cfg.get("ui_theme","dark")
    if t == "custom":
        bg = cfg.get("ui_bg","#111111")
        fg = cfg.get("ui_fg","#eeeeee")
        ac = cfg.get("ui_accent","#4ea3ff")
    else:
        d = THEMES.get(t, THEMES["dark"])
        bg,fg,ac = d["bg"],d["fg"],d["accent"]

    return f"""
    body {{
      background:{bg};
      color:{fg};
      font-family:system-ui,-apple-system,sans-serif;
      max-width:900px;
      margin:20px auto;
      padding:0 14px;
    }}
    input,select,button {{
      background:{bg};
      color:{fg};
      border:1px solid {ac};
      padding:10px;
      margin:6px 0 14px 0;
      width:100%;
      border-radius:10px;
    }}
    button {{
      background:{ac};
      color:#fff;
      font-weight:700;
      cursor:pointer;
    }}
    .row {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; }}
    .warn {{ background:#ffe8a1; color:#000; padding:10px; border-radius:10px; }}
    h2,h3 {{ margin: 10px 0; }}
    """

def reboot_needed():
    return os.path.exists(REBOOT_FLAG)

def sel(v, cur): return "selected" if str(v)==str(cur) else ""

@app.route("/", methods=["GET"])
def index():
    if not authed(): return need_auth()
    c=read_cfg()
    css=theme_css(c)

    reboot_block = ""
    if reboot_needed():
        reboot_block = """
        <div class="warn">
          <b>Reboot erforderlich</b> (HDMI-Auflösung wurde geändert).<br/>
          <form method="post" action="/reboot" style="margin-top:10px">
            <button type="submit">Jetzt neu starten</button>
          </form>
        </div>
        """

    out_mode = c.get("output_mode","720p")
    ui_theme = c.get("ui_theme","dark")
    enc = c.get("vnc_encodings","stable")
    depth = c.get("vnc_depth",16)

    return f"""
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AutoVNC</title>
<style>{css}</style>
</head><body>

<h2>AutoVNC (Linux → RPi1 → HDMI)</h2>

<form method="post" action="/save">

<h3>WLAN</h3>
<div class="row">
  <div><label>Land</label><input name="wifi_country" value="{c.get("wifi_country","DE")}"></div>
  <div><label>Start-Delay (Sek.)</label><input name="wait_after_boot" value="{c.get("wait_after_boot",20)}"></div>
</div>
<label>SSID</label><input name="wifi_ssid" value="{c.get("wifi_ssid","")}">
<label>WLAN Passwort</label><input name="wifi_pass" value="{c.get("wifi_pass","")}">

<h3>HDMI Auflösung</h3>
<select name="output_mode">
  <option value="720p" {sel("720p", out_mode)}>720p (empfohlen)</option>
  <option value="1080p" {sel("1080p", out_mode)}>1080p (experimentell)</option>
</select>

<h3>VNC</h3>
<label>VNC Host (Linux-IP/Hostname)</label>
<input name="vnc_host" value="{c.get("vnc_host","")}">

<label>VNC Passwort</label>
<input name="vnc_pass" value="{c.get("vnc_pass","")}">

<div class="row">
  <div>
    <label>Fullscreen</label>
    <select name="vnc_fullscreen">
      <option value="true" {sel("true", "true" if c.get("vnc_fullscreen",True) else "false")}>true</option>
      <option value="false" {sel("false", "true" if c.get("vnc_fullscreen",True) else "false")}>false</option>
    </select>
  </div>
  <div>
    <label>ViewOnly</label>
    <select name="vnc_viewonly">
      <option value="true" {sel("true", "true" if c.get("vnc_viewonly",True) else "false")}>true</option>
      <option value="false" {sel("false", "true" if c.get("vnc_viewonly",True) else "false")}>false</option>
    </select>
  </div>
</div>

<h3>VNC Performance</h3>
<div class="row">
  <div>
    <label>Color depth</label>
    <select name="vnc_depth">
      <option value="16" {sel("16", depth)}>16 (schneller)</option>
      <option value="24" {sel("24", depth)}>24 (besseres Bild)</option>
    </select>
  </div>
  <div>
    <label>Encodings</label>
    <select name="vnc_encodings">
      <option value="stable" {sel("stable", enc)}>stable (empfohlen)</option>
      <option value="raw-fast" {sel("raw-fast", enc)}>raw-fast (LAN, viel Bandbreite)</option>
      <option value="tight-best" {sel("tight-best", enc)}>tight-best (WLAN, mehr CPU)</option>
    </select>
  </div>
</div>

<div class="row">
  <div><label>Quality (0..9)</label><input name="vnc_quality" value="{c.get("vnc_quality",3)}"></div>
  <div><label>Compress (0..9)</label><input name="vnc_compress" value="{c.get("vnc_compress",6)}"></div>
</div>

<h3>WebUI Farben</h3>
<label>Theme</label>
<select name="ui_theme">
  <option value="light" {sel("light", ui_theme)}>Light</option>
  <option value="dark" {sel("dark", ui_theme)}>Dark</option>
  <option value="blue" {sel("blue", ui_theme)}>Blue</option>
  <option value="custom" {sel("custom", ui_theme)}>Custom</option>
</select>

<div class="row">
  <div><label>BG (Custom)</label><input name="ui_bg" value="{c.get("ui_bg","#111111")}"></div>
  <div><label>FG (Custom)</label><input name="ui_fg" value="{c.get("ui_fg","#eeeeee")}"></div>
</div>
<label>Accent (Custom)</label><input name="ui_accent" value="{c.get("ui_accent","#4ea3ff")}">

<button type="submit">Speichern & Anwenden</button>
</form>

{reboot_block}

</body></html>
"""

@app.route("/save", methods=["POST"])
def save():
    if not authed(): return need_auth()
    c=read_cfg()

    c["wifi_country"] = (request.form.get("wifi_country","DE").strip() or "DE")
    c["wifi_ssid"] = request.form.get("wifi_ssid","").strip()
    c["wifi_pass"] = request.form.get("wifi_pass","")

    c["output_mode"] = (request.form.get("output_mode","720p").strip() or "720p")

    c["vnc_host"] = request.form.get("vnc_host","").strip()
    c["vnc_pass"] = request.form.get("vnc_pass","")

    c["vnc_fullscreen"] = (request.form.get("vnc_fullscreen","true")=="true")
    c["vnc_viewonly"] = (request.form.get("vnc_viewonly","true")=="true")

    try: c["vnc_depth"] = int(request.form.get("vnc_depth","16"))
    except: c["vnc_depth"] = 16

    c["vnc_encodings"] = request.form.get("vnc_encodings","stable")

    try: c["vnc_quality"] = int(request.form.get("vnc_quality","3"))
    except: c["vnc_quality"] = 3

    try: c["vnc_compress"] = int(request.form.get("vnc_compress","6"))
    except: c["vnc_compress"] = 6

    try: c["wait_after_boot"] = int(request.form.get("wait_after_boot","20"))
    except: c["wait_after_boot"] = 20

    c["ui_theme"] = request.form.get("ui_theme","dark").strip() or "dark"
    c["ui_bg"] = request.form.get("ui_bg", c.get("ui_bg","#111111"))
    c["ui_fg"] = request.form.get("ui_fg", c.get("ui_fg","#eeeeee"))
    c["ui_accent"] = request.form.get("ui_accent", c.get("ui_accent","#4ea3ff"))

    write_cfg(c)
    subprocess.run([APPLY], check=False)
    return Response("OK", 302, {"Location": "/"})

@app.route("/reboot", methods=["POST"])
def do_reboot():
    if not authed(): return need_auth()
    try:
        subprocess.Popen(["/usr/sbin/reboot"])
    except:
        pass
    return Response("Rebooting...", 200, {"Content-Type":"text/plain"})

if __name__=="__main__":
    app.run("127.0.0.1", 8080)
EOF

chmod 0644 "$APP"
chown root:root "$APP"

# systemd web service
WEB_SERVICE="/etc/systemd/system/autovnc-web.service"
cat >"$WEB_SERVICE" <<EOF
[Unit]
Description=AutoVNC Web Config UI (Flask)
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/autovnc/web/creds.env
ExecStart=/usr/bin/python3 /opt/autovnc/web/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable autovnc-web.service >/dev/null 2>&1 || true
systemctl restart autovnc-web.service >/dev/null 2>&1 || true

# nginx https
CRT="/etc/nginx/ssl/autovnc.crt"
KEY="/etc/nginx/ssl/autovnc.key"
if [[ ! -f "$CRT" || ! -f "$KEY" ]]; then
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

# GUI autologin + openbox autostart
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

echo "==> Initial apply..."
bash "$APPLY" || true

echo "FERTIG ✅  WebUI: https://<PI-IP>  Login: $WEBUI_USER / $WEBUI_PASS"

